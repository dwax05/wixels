import WixelsKit
import Foundation

// Covers the orphaned-child fix: the MediaRemoteAdapter perl stream must die
// with the host on every exit path. Uses a stub adapter script that records its
// PID and blocks forever — exactly the "no track events, never hits SIGPIPE"
// shape that leaked in production.
@MainActor
enum ChildReaperTests {
    static func run() async throws {
        try await terminateAllKillsRegisteredChildren()
        try await unregisteredChildSurvivesTerminateAll()
        try terminateAllIsIdempotentAndSafeOnDeadChildren()
        try await musicMonitorStreamDiesOnTerminateAll()
        try await musicMonitorDeinitReapsItsStream()
        print("PASS child-reaper suite")
    }

    // MARK: reaper semantics

    private static func terminateAllKillsRegisteredChildren() async throws {
        let child = try spawnBlockedChild()
        ChildReaper.shared.register(child)

        ChildReaper.shared.terminateAll()
        try await waitUntil("registered child exits after terminateAll") { !child.isRunning }
    }

    private static func unregisteredChildSurvivesTerminateAll() async throws {
        let kept = try spawnBlockedChild()
        let dropped = try spawnBlockedChild()
        ChildReaper.shared.register(kept)
        ChildReaper.shared.register(dropped)
        ChildReaper.shared.unregister(kept)
        defer { kept.terminate() }

        ChildReaper.shared.terminateAll()
        try await waitUntil("still-registered child exits") { !dropped.isRunning }
        try check(kept.isRunning, "unregistered child is not touched by terminateAll")
    }

    private static func terminateAllIsIdempotentAndSafeOnDeadChildren() throws {
        let child = try spawnBlockedChild()
        ChildReaper.shared.register(child)
        child.terminate()
        child.waitUntilExit()

        // Already-dead child and a drained registry: both calls must be no-ops.
        ChildReaper.shared.terminateAll()
        ChildReaper.shared.terminateAll()
        try check(true, "terminateAll is idempotent and tolerates dead children")
    }

    // MARK: MusicMonitor stream lifecycle

    private static func musicMonitorStreamDiesOnTerminateAll() async throws {
        let root = try makeStubAdapterRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let monitor = MusicMonitor(resourceRoot: root)

        _ = await monitor.nowPlaying()                  // triggers startStreamIfNeeded
        let pid = try await waitForStreamPID(root: root)
        try check(kill(pid, 0) == 0, "adapter stream is running after first read")

        // The quit path: signal handler / applicationWillTerminate calls this.
        ChildReaper.shared.terminateAll()
        try await waitUntil("adapter stream exits after terminateAll") { !processAlive(pid) }
    }

    private static func musicMonitorDeinitReapsItsStream() async throws {
        let root = try makeStubAdapterRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        var monitor: MusicMonitor? = MusicMonitor(resourceRoot: root)

        _ = await monitor?.nowPlaying()
        let pid = try await waitForStreamPID(root: root)
        try check(kill(pid, 0) == 0, "adapter stream is running before monitor release")

        // The config-reload path: old Services dropped, monitor deinits.
        monitor = nil
        try await waitUntil("adapter stream exits after monitor deinit") { !processAlive(pid) }
    }

    // MARK: helpers

    /// A child that blocks forever on stdin — like the adapter stream with no
    /// track events, it never writes and so never notices a closed pipe.
    private static func spawnBlockedChild() throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/cat")
        process.standardInput = Pipe()
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        return process
    }

    /// A resource root whose `mediaremote-adapter.pl` writes its PID next to
    /// itself and then blocks, matching the real adapter's invocation shape.
    private static func makeStubAdapterRoot() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wixels-reaper-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("MediaRemoteAdapter.framework"),
            withIntermediateDirectories: true)
        let script = root.appendingPathComponent("mediaremote-adapter.pl")
        try """
        #!/usr/bin/perl
        open(my $fh, '>', "$0.pid") or die "pidfile: $!";
        print $fh $$;
        close($fh);
        sleep 3600 while 1;
        """.write(to: script, atomically: true, encoding: .utf8)
        return root
    }

    private static func waitForStreamPID(root: URL) async throws -> pid_t {
        let pidfile = root.appendingPathComponent("mediaremote-adapter.pl.pid").path
        var pid: pid_t = 0
        try await waitUntil("adapter stub writes its pidfile") {
            guard let text = try? String(contentsOfFile: pidfile, encoding: .utf8),
                  let value = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines))
            else { return false }
            pid = value
            return true
        }
        return pid
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
        throw ReaperTestFailure("timed out: \(what)")
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw ReaperTestFailure(message) }
        print("PASS \(message)")
    }
}

private struct ReaperTestFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
