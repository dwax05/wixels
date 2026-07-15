// Paths — the one place the "env override > config value > built-in default" path
// precedence lives. PaletteStore, the host Config, and file-backed widgets (Quotes)
// all resolve their data file the same way; this keeps that ladder
// from being copy-pasted per source.

import Foundation

public enum Paths {
    /// Resolve a data-file path by precedence: an environment override, then a
    /// caller-supplied path (from config), then a built-in default. The env value is
    /// taken verbatim; the config path and default are tilde-expanded.
    public static func resolve(env: String, config: String?, default def: String) -> String {
        if let e = ProcessInfo.processInfo.environment[env] { return e }
        if let c = config { return (c as NSString).expandingTildeInPath }
        return (def as NSString).expandingTildeInPath
    }
}
