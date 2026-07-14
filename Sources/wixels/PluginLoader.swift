// PluginLoader — finds widget plugin dylibs and registers their specs.
//
// A plugin is a dynamic library exporting a C `wixels_register` symbol (see any
// Widget*/Register.swift). We dlopen each, dlsym that symbol, and call it with a
// pointer to the shared Registrar — the plugin adds its spec(s) to it. Because
// host and plugin both link the one dynamic WixelsKit, the Registrar and WidgetSpec
// types have a single runtime identity, so the call is safe.
//
// Search order: the running binary's own directory (build-plugins.sh installs the
// built-in plugin dylibs next to the executable in build/<config>/), then
// ~/.config/wixels/plugins for user drop-ins. A plugin that fails to load is logged
// and skipped, never fatal.

import Foundation
import WixelsKit

enum PluginLoader {
    static func load(into registrar: Registrar) {
        var seen = Set<String>()
        for dir in searchDirs() {
            guard let items = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
            for file in items.sorted() where isLoadable(file) && seen.insert(file).inserted {
                loadOne(dir + "/" + file, into: registrar)
            }
        }
    }

    /// Built-in plugins are named `libWidget*.dylib`; user drop-ins may be any
    /// `.dylib`/`.bundle` — but we only auto-load the `Widget*` naming to avoid
    /// dlopening unrelated libraries sitting in the build dir.
    private static func isLoadable(_ file: String) -> Bool {
        ((file.hasPrefix("libWidget") || file.hasPrefix("libTheme")) && file.hasSuffix(".dylib"))
    }

    private static func searchDirs() -> [String] {
        var dirs: [String] = []
        if let exe = Bundle.main.executableURL?.resolvingSymlinksInPath()
            .deletingLastPathComponent().path { dirs.append(exe) }
        dirs.append(("~/.config/wixels/plugins" as NSString).expandingTildeInPath)
        dirs.append(("~/.config/wixels/themes" as NSString).expandingTildeInPath)
        return dirs
    }

    private static func loadOne(_ path: String, into registrar: Registrar) {
        guard let handle = dlopen(path, RTLD_NOW) else {
            let err = dlerror().map { String(cString: $0) } ?? "unknown error"
            Log.note("dlopen failed for \(path): \(err)")
            return
        }
        guard let sym = dlsym(handle, "wixels_register") else {
            Log.note("no wixels_register in \(path) — not a widget plugin?")
            return
        }
        typealias RegisterFn = @convention(c) (UnsafeMutableRawPointer) -> Void
        let register = unsafeBitCast(sym, to: RegisterFn.self)
        register(Unmanaged.passUnretained(registrar).toOpaque())
    }

    static func runTestSuite() -> Int32 {
        let registrar = Registrar()
        load(into: registrar)
        let expected: Set<String> = ["sys", "nowplaying", "disk-snail", "pet", "plant", "quotes",
                                     "frog", "clock", "stats", "owl", "weather", "poster"]
        let loaded = Set(registrar.specs.keys).union(registrar.themedSpecs.keys)
        let missing = expected.subtracting(loaded)
        guard missing.isEmpty else {
            print("FAIL bundled plugins did not load: \(missing.sorted().joined(separator: ", "))")
            return 1
        }
        guard registrar.themes["macos"] != nil, registrar.themes["cynaberii"] != nil else {
            print("FAIL bundled themes did not load")
            return 1
        }
        print("PASS 12 bundled plugins and 2 themes load at runtime")
        return 0
    }
}
