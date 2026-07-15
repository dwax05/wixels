import WixelsKit
import Foundation

// Covers the orphaned-child fix: the MediaRemoteAdapter perl stream must die
// with the host on every exit path — including SIGKILL/force-quit, which no
// handler can catch. The stream runs under a /bin/sh wrapper holding a
// "lifeline" stdin pipe from the host; any host death closes the write end and
// the wrapper kills the adapter. Uses a stub adapter script that records its
// PID (and the wrapper's) and blocks forever — exactly the "no track events,
// never hits SIGPIPE" shape that leaked in production.
@MainActor
enum StreamLifelineTests {
    /// Child mode for the force-quit test: behave like a host whose music
    /// widget is polling, then hang until the parent SIGKILLs us.
    static let hostModeVariable = "WIXELS_TEST_STREAM_HOST"

    static func run() async throws {
        try await monitorDeinitReapsStreamAndWrapper()
        try await forceKilledHostReapsStreamAndWrapper()
        print("PASS stream-lifeline suite")
    }

    static func runHostModeIfRequested() async -> Bool {
        guard let root = ProcessInfo.processInfo.environment[hostModeVariable] else { return false }
        let monitor = MusicMonitor(resourceRoot: URL(fileURLWithPath: root))
        while true {
            _ = await monitor.nowPlaying()
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    // The config-reload path: old Services dropped, monitor deinits, lifeline
    // closes, wrapper kills the adapter and exits on its own.
    private static func monitorDeinitReapsStreamAndWrapper() async throws {
        let root = try makeStubAdapterRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        var monitor: MusicMonitor? = MusicMonitor(resourceRoot: root)

        _ = await monitor?.nowPlaying()                 // triggers startStreamIfNeeded
        let (adapter, wrapper) = try await waitForStreamPIDs(root: root)
        try check(processAlive(adapter), "adapter stream is running before monitor release")
        try check(processAlive(wrapper), "wrapper shell is running before monitor release")

        monitor = nil
        try await waitUntil("adapter stream exits after monitor deinit") { !processAlive(adapter) }
        try await waitUntil("wrapper shell exits after monitor deinit") { !processAlive(wrapper) }
    }

    // The force-quit path: SIGKILL the host outright — no deinit, no handler,
    // no atexit. The kernel closing the host's pipe ends must be enough.
    private static func forceKilledHostReapsStreamAndWrapper() async throws {
        let root = try makeStubAdapterRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let host = Process()
        host.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        var environment = ProcessInfo.processInfo.environment
        environment[hostModeVariable] = root.path
        host.environment = environment
        host.standardOutput = FileHandle.nullDevice
        host.standardError = FileHandle.nullDevice
        try host.run()

        let (adapter, wrapper) = try await waitForStreamPIDs(root: root)
        try check(processAlive(adapter), "adapter stream is running under the fake host")

        kill(host.processIdentifier, SIGKILL)
        host.waitUntilExit()
        try await waitUntil("adapter stream exits after host SIGKILL") { !processAlive(adapter) }
        try await waitUntil("wrapper shell exits after host SIGKILL") { !processAlive(wrapper) }
    }

    // MARK: helpers

    /// A resource root whose `mediaremote-adapter.pl` writes its own PID and
    /// its parent's (the wrapper shell) next to itself and then blocks,
    /// matching the real adapter's invocation shape.
    private static func makeStubAdapterRoot() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wixels-lifeline-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("MediaRemoteAdapter.framework"),
            withIntermediateDirectories: true)
        let script = root.appendingPathComponent("mediaremote-adapter.pl")
        try """
        #!/usr/bin/perl
        open(my $fh, '>', "$0.pid") or die "pidfile: $!";
        print $fh "$$ ", getppid();
        close($fh);
        sleep 3600 while 1;
        """.write(to: script, atomically: true, encoding: .utf8)
        return root
    }

    private static func waitForStreamPIDs(root: URL) async throws -> (adapter: pid_t, wrapper: pid_t) {
        let pidfile = root.appendingPathComponent("mediaremote-adapter.pl.pid").path
        var pids: (pid_t, pid_t) = (0, 0)
        try await waitUntil("adapter stub writes its pidfile") {
            guard let text = try? String(contentsOfFile: pidfile, encoding: .utf8) else { return false }
            let parts = text.split(separator: " ").compactMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            guard parts.count == 2 else { return false }
            pids = (parts[0], parts[1])
            return true
        }
        return pids
    }

    private static func processAlive(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0
    }

    private static func waitUntil(
        _ what: String,
        timeout: Duration = .seconds(5),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() {
                print("PASS \(what)")
                return
            }
            try await clock.sleep(for: .milliseconds(20))
        }
        throw LifelineTestFailure("timed out: \(what)")
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw LifelineTestFailure(message) }
        print("PASS \(message)")
    }
}

private struct LifelineTestFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
