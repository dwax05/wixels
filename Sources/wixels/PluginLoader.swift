// PluginLoader — finds widget plugin dylibs and registers their specs.
//
// A plugin is a dynamic library exporting a C `wixels_register` symbol (see any
// Widget*/Register.swift). We dlopen each, dlsym that symbol, and call it with a
// pointer to the shared Registrar — the plugin adds its spec(s) to it. Because
// host and plugin both link the one dynamic WixelsKit, the Registrar and WidgetSpec
// types have a single runtime identity, so the call is safe.
//
// Search order is bundled app resources, then user drop-ins. A source checkout can
// opt into an explicit staging root with WIXELS_PLUGIN_ROOT; production never scans
// the executable or SwiftPM build directories.

import Foundation
import WixelsKit

enum PluginLoader {
    static func load(into registrar: Registrar) {
        var seen = Set<String>()
        for dir in searchDirs() {
            for file in loadableFiles(in: dir) where seen.insert(file).inserted {
                loadOne(dir + "/" + file, into: registrar)
            }
        }
    }

    static func loadableFiles(in directory: String) -> [String] {
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: directory) else {
            return []
        }
        return items.filter(isLoadable).sorted()
    }

    /// Only Wixels extension names are considered, avoiding unrelated libraries in
    /// either the app bundle or a user extension directory.
    private static func isLoadable(_ file: String) -> Bool {
        ((file.hasPrefix("libWidget") || file.hasPrefix("libTheme")) && file.hasSuffix(".dylib"))
    }

    private static func searchDirs() -> [String] {
        let root = ProcessInfo.processInfo.environment["WIXELS_PLUGIN_ROOT"]
            .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
        return searchDirs(bundleResourceURL: Bundle.main.resourceURL,
                          homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
                          developmentRoot: root)
    }

    // Kept injectable so path policy can be tested without changing process
    // environment or depending on an app bundle on disk.
    static func searchDirs(bundleResourceURL: URL?, homeDirectory: URL,
                           developmentRoot: URL? = nil) -> [String] {
        var dirs: [URL] = []
        if let root = developmentRoot {
            dirs += [root.appendingPathComponent("plugins"), root.appendingPathComponent("themes")]
        } else if let resources = bundleResourceURL {
            dirs += [resources.appendingPathComponent("plugins"), resources.appendingPathComponent("themes")]
        }
        let user = homeDirectory.appendingPathComponent(".config/wixels")
        dirs += [user.appendingPathComponent("plugins"), user.appendingPathComponent("themes")]
        return dirs.map(\.path)
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
        let suite = ProcessInfo.processInfo.environment["WIXELS_WIDGET_SUITE"]
        let expectedThemes = suite.map { Set([$0.lowercased()]) } ?? Set(["macos", "cynaberii"])
        let missingThemes = expectedThemes.subtracting(registrar.themes.keys)
        guard missingThemes.isEmpty else {
            print("FAIL bundled themes did not load: \(missingThemes.sorted().joined(separator: ", "))")
            return 1
        }
        print("PASS 12 bundled plugins and \(expectedThemes.count) theme(s) load at runtime")
        return 0
    }
}
