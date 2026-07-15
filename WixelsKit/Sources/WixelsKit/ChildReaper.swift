// ChildReaper — terminates long-lived helper children the host has spawned
// (today: the MediaRemoteAdapter perl stream) when the app exits.
//
// Why it exists: the stream child's only tie to the host is its stdout pipe,
// and perl only notices a closed pipe on its next write. With no track-change
// events it never writes, so a plain Ctrl-C / SIGTERM / menu Quit would orphan
// it forever. Registered children are terminated explicitly on the way out.
//
// Lock-based and nonisolated on purpose: `terminateAll()` must be callable
// from a signal DispatchSource handler, where Swift Concurrency is off-limits
// (see CLAUDE.md sharp edges).

import Foundation

public final class ChildReaper: @unchecked Sendable {
    public static let shared = ChildReaper()

    private let lock = NSLock()
    private var children: [ObjectIdentifier: Process] = [:]

    public func register(_ process: Process) {
        lock.lock(); defer { lock.unlock() }
        children[ObjectIdentifier(process)] = process
    }

    public func unregister(_ process: Process) {
        lock.lock(); defer { lock.unlock() }
        children.removeValue(forKey: ObjectIdentifier(process))
    }

    /// Terminate every registered child. Idempotent; safe from any thread and
    /// from plain-Dispatch signal handlers.
    public func terminateAll() {
        lock.lock()
        let processes = Array(children.values)
        children.removeAll()
        lock.unlock()
        for process in processes where process.isRunning {
            process.terminate()
        }
    }
}
