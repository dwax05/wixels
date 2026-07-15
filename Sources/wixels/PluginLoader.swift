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

struct PluginWidget: Hashable {
    let group: String
    let kind: String
}

struct PluginCatalog {
    var widgets = Set<PluginWidget>()
    var themeIDsByGroup: [String: String] = [:]
    var folders = Set<String>()
}

enum PluginLoader {
    static let ungrouped = "Ungrouped"

    /// Loads extensions and returns each folder's widgets and bundled theme.
    static func load(into registrar: Registrar, excluding excluded: Set<String> = []) -> PluginCatalog {
        var seen = Set<String>()
        var catalog = PluginCatalog()
        let dirs = searchDirs()
        let requestedFolder = ProcessInfo.processInfo.environment["WIXELS_WIDGET_SUITE"]
            .flatMap { $0.isEmpty ? nil : $0 } ?? Config.selectedPluginFolder()
        let themedFolders = Set(dirs.filter { ($0 as NSString).lastPathComponent == "plugins" }.flatMap { dir in
            loadableFiles(in: dir).filter { ($0 as NSString).lastPathComponent.hasPrefix("libTheme") }
                .map(folder(for:)).filter { $0 != ungrouped }
        })
        let selectedFolder = requestedFolder ?? themedFolders.sorted().first
        // Reuse the first loaded implementation for copies of the same plugin
        // filename. Swift dylibs may contain Objective-C-visible classes, so dlopen
        // of a second copy can produce duplicate-class warnings or crashes.
        var loadedWidgetsByFilename: [String: (path: String, kinds: Set<String>)] = [:]
        for dir in dirs {
            for file in loadableFiles(in: dir) where seen.insert(file).inserted {
                let path = dir + "/" + file
                guard !excluded.contains(path) else { continue }
                let filename = (file as NSString).lastPathComponent
                let group = folder(for: file)
                if group != ungrouped { catalog.folders.insert(group) }
                guard belongsToSelectedFolder(file, selectedFolder: selectedFolder,
                                               themedFolders: themedFolders,
                                               restrictAll: requestedFolder != nil) else { continue }
                if filename.hasPrefix("libWidget"), let previous = loadedWidgetsByFilename[filename] {
                    if FileManager.default.contentsEqual(atPath: path, andPath: previous.path) {
                        catalog.widgets.formUnion(previous.kinds.map { PluginWidget(group: group, kind: $0) })
                    } else {
                        Log.note("duplicate plugin filename '\(filename)' in '\(group)' — keeping \(previous.path)")
                    }
                    continue
                }
                let isolated = Registrar()
                loadOne(path, into: isolated)
                for spec in isolated.specs.values { registrar.add(spec) }
                for spec in isolated.themedSpecs.values { registrar.add(spec) }
                for theme in isolated.themes.values { registrar.add(theme) }
                if filename.hasPrefix("libWidget") {
                    let kinds = Set(isolated.specs.keys).union(isolated.themedSpecs.keys)
                    loadedWidgetsByFilename[filename] = (path, kinds)
                    catalog.widgets.formUnion(kinds.map { PluginWidget(group: group, kind: $0) })
                } else if filename.hasPrefix("libTheme"), group != ungrouped,
                          let id = themeID(from: filename) {
                    catalog.themeIDsByGroup[group] = id
                }
            }
        }
        return catalog
    }

    /// An explicit build/run selection limits widget dylibs to its matching first
    /// folder. With no selection, independent folders compose freely.
    static func belongsToSelectedFolder(_ relativePath: String, selectedFolder: String?,
                                        themedFolders: Set<String> = [], restrictAll: Bool = true) -> Bool {
        guard let selectedFolder else { return true }
        let filename = (relativePath as NSString).lastPathComponent
        guard filename.hasPrefix("libWidget") || filename.hasPrefix("libTheme") else { return true }
        let group = folder(for: relativePath)
        if group.caseInsensitiveCompare(selectedFolder) == .orderedSame { return true }
        return !restrictAll && !themedFolders.contains(group)
    }

    private static func themeID(from filename: String) -> String? {
        guard filename.hasPrefix("libTheme"), filename.hasSuffix(".dylib") else { return nil }
        let start = filename.index(filename.startIndex, offsetBy: "libTheme".count)
        let end = filename.index(filename.endIndex, offsetBy: -".dylib".count)
        let id = String(filename[start..<end]).lowercased()
        return ThemeManifest.isValidID(id) ? id : nil
    }

    static func loadableFiles(in directory: String) -> [String] {
        guard let enumerator = FileManager.default.enumerator(atPath: directory) else {
            return []
        }
        return enumerator.compactMap { $0 as? String }.filter(isLoadable).sorted()
    }

    /// Only Wixels extension names are considered, avoiding unrelated libraries in
    /// either the app bundle or a user extension directory.
    private static func isLoadable(_ file: String) -> Bool {
        let name = (file as NSString).lastPathComponent
        return ((name.hasPrefix("libWidget") || name.hasPrefix("libTheme")) && name.hasSuffix(".dylib"))
    }

    /// A folder means the first path component beneath a plugin root. Deeper
    /// directories are scanned for convenience but do not create nested menus.
    static func folder(for relativePath: String) -> String {
        let parts = relativePath.split(separator: "/", omittingEmptySubsequences: true)
        return parts.count > 1 ? String(parts[0]) : ungrouped
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
        _ = load(into: registrar)
        let suite = ProcessInfo.processInfo.environment["WIXELS_WIDGET_SUITE"]
        let expected: Set<String> = switch suite {
        case "Macos": ["clock", "stats", "weather", "nowplaying", "reminders", "poster"]
        default: ["sys", "nowplaying", "disk-snail", "pet", "plant", "quotes",
                  "frog", "clock", "stats", "owl", "weather", "poster"]
        }
        let loaded = Set(registrar.specs.keys).union(registrar.themedSpecs.keys)
        let missing = expected.subtracting(loaded)
        guard missing.isEmpty else {
            print("FAIL bundled plugins did not load: \(missing.sorted().joined(separator: ", "))")
            return 1
        }
        let expectedThemes = suite.map { Set([$0.lowercased()]) } ?? Set(["macos", "cynaberii"])
        let missingThemes = expectedThemes.subtracting(registrar.themes.keys)
        guard missingThemes.isEmpty else {
            print("FAIL bundled themes did not load: \(missingThemes.sorted().joined(separator: ", "))")
            return 1
        }
        print("PASS \(expected.count) bundled plugins and \(expectedThemes.count) theme(s) load at runtime")
        return 0
    }
}
