import Foundation
import WixelsKit

// Tracks live child process groups so quit paths (SIGTERM/SIGINT, normal
// terminate) can kill them without touching actor state. Lock-protected —
// callable from signal dispatch sources where Swift Concurrency is off-limits.
final class ProcessGroupRegistry: @unchecked Sendable {
    static let shared = ProcessGroupRegistry()
    private var pgids: Set<pid_t> = []
    private let lock = NSLock()

    func add(_ pgid: pid_t) { lock.lock(); pgids.insert(pgid); lock.unlock() }
    func remove(_ pgid: pid_t) { lock.lock(); pgids.remove(pgid); lock.unlock() }
    func killAll() {
        lock.lock(); let live = pgids; lock.unlock()
        for pgid in live { kill(-pgid, SIGTERM) }
    }
}

actor CommandVariableStore {
    private let definitions: [VariableDefinition]
    private var values: [String: String]
    private var tasks: [Task<Void, Never>] = []
    private var failing: Set<String> = []

    init(definitions: [VariableDefinition]) {
        self.definitions = definitions
        self.values = Dictionary(uniqueKeysWithValues: definitions.map { ($0.name, $0.initial) })
    }

    func start() {
        guard tasks.isEmpty else { return }
        for definition in definitions {
            switch definition.kind {
            case .poll(let interval):
                tasks.append(Task { [weak self] in
                    while !Task.isCancelled {
                        await self?.refresh(definition)
                        try? await Task.sleep(for: .seconds(interval))
                    }
                })
            case .listen:
                tasks.append(Task { [weak self] in await self?.listenLoop(definition) })
            }
        }
    }

    func stop() { tasks.forEach { $0.cancel() }; tasks.removeAll() }
    func snapshot() -> [String: String] { values }

    private func refresh(_ definition: VariableDefinition) async {
        do {
            let output = try await Self.run(definition.command)
            if failing.remove(definition.name) != nil {
                Log.note("widgets.toml variable '\(definition.name)' recovered")
            }
            values[definition.name] = output.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            // Keep the last good value; log once per failure streak, not per tick.
            guard failing.insert(definition.name).inserted else { return }
            Log.note("widgets.toml variable '\(definition.name)' failed (\(error)) — keeping last value")
        }
    }

    // Shared launcher: perl setpgrp makes the shell a process-group leader so a
    // timeout or teardown can kill the whole pipeline, not just /bin/sh
    // (Process can't set pgid itself). Returns the running process, its stdout
    // pipe, and a stream that finishes when the process exits.
    private nonisolated static func spawn(_ command: String) throws -> (Process, Pipe, AsyncStream<Void>) {
        let process = Process(), input = Pipe(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = ["-e", "setpgrp(0, 0); exec '/bin/sh', '-lc', $ARGV[0];", "--", command]
        process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
        let exited = AsyncStream<Void> { continuation in
            process.terminationHandler = { _ in continuation.yield(); continuation.finish() }
        }
        do { try process.run() } catch { throw CommandError.launchFailed(error.localizedDescription) }
        try? input.fileHandleForWriting.close()
        ProcessGroupRegistry.shared.add(process.processIdentifier)
        return (process, output, exited)
    }

    private nonisolated static func run(_ command: String) async throws -> String {
        let (process, output, exited) = try spawn(command)
        let result: Result<String, Error>
        do {
            result = .success(try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask { try await readOutput(output.fileHandleForReading) }
                group.addTask {
                    try await Task.sleep(for: .seconds(5))
                    // Kill the group here, not after the task group: the output
                    // reader only unblocks once every pipe writer is dead (EOF),
                    // and the group can't finish while the reader is blocked.
                    if process.isRunning { kill(-process.processIdentifier, SIGTERM) }
                    throw CommandError.timeout
                }
                defer { group.cancelAll() }
                return try await group.next()!
            })
        } catch { result = .failure(error) }
        await reap(process, exited: exited)
        if case .success = result, process.terminationReason == .exit, process.terminationStatus != 0 {
            throw CommandError.exitStatus(process.terminationStatus)
        }
        return try result.get()
    }

    /// Click actions use the same bounded, process-group-supervised launcher as
    /// variables, so a config reload or app termination cannot orphan a shell.
    nonisolated static func runAction(_ command: String) async throws {
        _ = try await run(command)
    }

    private nonisolated static func reap(_ process: Process, exited: AsyncStream<Void>) async {
        let pgid = process.processIdentifier
        if process.isRunning {
            kill(-pgid, SIGTERM)
            let escalate = Task {
                try await Task.sleep(for: .seconds(2))
                kill(-pgid, SIGKILL)
            }
            for await _ in exited {}
            escalate.cancel()
        } else {
            for await _ in exited {}
        }
        ProcessGroupRegistry.shared.remove(pgid)
    }

    private nonisolated static func readOutput(_ handle: FileHandle) async throws -> String {
        var data = Data()
        for try await byte in handle.bytes {
            data.append(byte)
            if data.count > 8_192 { throw CommandError.outputTooLarge }
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: listen variables (eww deflisten): one long-lived process, each stdout
    // line becomes the value; restart with backoff when it dies.

    private func listenLoop(_ definition: VariableDefinition) async {
        var backoff: Duration = .seconds(1)
        while !Task.isCancelled {
            let healthy = await runListen(definition)
            if Task.isCancelled { break }
            if healthy >= .seconds(30) { backoff = .seconds(1) }
            if failing.insert(definition.name).inserted {
                Log.note("widgets.toml listen variable '\(definition.name)' exited — restarting with backoff")
            }
            try? await Task.sleep(for: backoff)
            backoff = min(backoff * 2, .seconds(60))
        }
    }

    /// Runs the listen process until its output stream ends, then returns the
    /// duration it stayed healthy. Reaping (SIGTERM → 2s grace → SIGKILL) happens
    /// after that measurement so a slow-to-die process doesn't inflate the
    /// healthy-run clock `listenLoop` uses to decide whether to reset backoff.
    private func runListen(_ definition: VariableDefinition) async -> Duration {
        let process: Process, output: Pipe, exited: AsyncStream<Void>
        do { (process, output, exited) = try Self.spawn(definition.command) }
        catch {
            guard failing.insert(definition.name).inserted else { return .zero }
            Log.note("widgets.toml listen variable '\(definition.name)' failed (\(error))")
            return .zero
        }
        let started = ContinuousClock.now
        let pgid = process.processIdentifier
        await withTaskCancellationHandler {
            do {
                for try await line in Self.lines(output.fileHandleForReading) {
                    if failing.remove(definition.name) != nil {
                        Log.note("widgets.toml listen variable '\(definition.name)' recovered")
                    }
                    values[definition.name] = line.trimmingCharacters(in: .whitespaces)
                }
            } catch {
                if failing.insert(definition.name).inserted {
                    Log.note("widgets.toml listen variable '\(definition.name)' failed (\(error)) — keeping last value")
                }
                kill(-pgid, SIGTERM)
            }
        } onCancel: {
            // Sync C call only — no Swift Concurrency in cancellation handlers.
            kill(-pgid, SIGTERM)
        }
        let healthy = ContinuousClock.now - started
        await Self.reap(process, exited: exited)
        return healthy
    }

    private nonisolated static func lines(_ handle: FileHandle) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var data = Data()
                do {
                    for try await byte in handle.bytes {
                        if byte == UInt8(ascii: "\n") {
                            continuation.yield(String(data: data, encoding: .utf8) ?? "")
                            data.removeAll(keepingCapacity: true)
                        } else {
                            data.append(byte)
                            if data.count > 8_192 { throw CommandError.outputTooLarge }
                        }
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

private enum CommandError: Error, CustomStringConvertible {
    case timeout, outputTooLarge, launchFailed(String), exitStatus(Int32)
    var description: String {
        switch self {
        case .timeout: "timed out after 5s"
        case .outputTooLarge: "output exceeded 8 KiB"
        case .launchFailed(let reason): "launch failed: \(reason)"
        case .exitStatus(let status): "exited with status \(status)"
        }
    }
}

func interpolate(_ template: String, values: [String: String]) -> String {
    var result = "", index = template.startIndex
    while index < template.endIndex {
        guard template[index] == "{", let end = template[index...].firstIndex(of: "}") else {
            result.append(template[index]); index = template.index(after: index); continue
        }
        let name = String(template[template.index(after: index)..<end])
        if ThemeManifest.isValidID(name), let value = values[name] { result += value }
        else { result += template[index...end] }
        index = template.index(after: end)
    }
    return result
}
