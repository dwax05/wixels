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

private struct ExtensionPackageManifest: Decodable {
    struct Compatibility: Decodable { let minInclusive: String; let maxExclusive: String }
    struct Library: Decodable { let file: String; let kind: String?; let themeID: String? }
    let schemaVersion: Int
    let id: String
    let wixelsKit: Compatibility
    let libraries: [Library]

    func acceptsHost() -> Bool {
        guard schemaVersion == 1,
              let host = Version(WixelsKitAPI.version), let min = Version(wixelsKit.minInclusive),
              let max = Version(wixelsKit.maxExclusive) else { return false }
        return min <= host && host < max
    }

    func library(named name: String) -> Library? { libraries.first { $0.file == name } }
}

private struct Version: Comparable {
    let major: Int; let minor: Int; let patch: Int
    init?(_ string: String) {
        let parts = string.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        major = parts[0]; minor = parts[1]; patch = parts[2]
    }
    static func < (lhs: Version, rhs: Version) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

enum PluginLoader {
    static let ungrouped = "Ungrouped"

    /// Loads extensions and returns each package folder's widgets and bundled theme.
    /// A package is an immediate subfolder of a plugin root; for example,
    /// `plugins/mypackage/libThemeCynaberii.dylib` and
    /// `plugins/mypackage/libWidgetPet.dylib` load as one selectable package.
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
        let manifests = compatibleManifests(in: dirs)
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
                guard manifestAllows(filename: filename, group: group, directory: dir, manifests: manifests) else { continue }
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
                    if let declared = manifests[manifestKey(directory: dir, group: group)]?.library(named: filename)?.themeID,
                       declared != id {
                        Log.note("package manifest declares theme '\(declared)' for '\(filename)', but its filename resolves to '\(id)'")
                        continue
                    }
                    catalog.themeIDsByGroup[group] = id
                }
            }
        }
        return catalog
    }

    private static func compatibleManifests(in dirs: [String]) -> [String: ExtensionPackageManifest] {
        var manifests: [String: ExtensionPackageManifest] = [:]
        var warnedLegacy = Set<String>()
        for dir in dirs {
            for file in loadableFiles(in: dir) {
                let group = folder(for: file)
                guard group != ungrouped else {
                    if warnedLegacy.insert("\(dir)/\(group)").inserted { Log.note("legacy loose extensions in '\(dir)' have no wixels-package.json; compatibility was not preflighted") }
                    continue
                }
                let key = manifestKey(directory: dir, group: group)
                guard manifests[key] == nil else { continue }
                let path = key + "/wixels-package.json"
                guard let data = FileManager.default.contents(atPath: path) else {
                    if warnedLegacy.insert(key).inserted { Log.note("legacy package '\(group)' has no wixels-package.json; compatibility was not preflighted") }
                    continue
                }
                guard let manifest = try? JSONDecoder().decode(ExtensionPackageManifest.self, from: data), manifest.acceptsHost() else {
                    Log.note("package '\(group)' has an invalid or incompatible wixels-package.json for WixelsKit \(WixelsKitAPI.version)")
                    continue
                }
                manifests[key] = manifest
            }
        }
        return manifests
    }

    private static func manifestAllows(filename: String, group: String, directory: String,
                                       manifests: [String: ExtensionPackageManifest]) -> Bool {
        guard group != ungrouped else { return true }
        let key = manifestKey(directory: directory, group: group)
        let path = key + "/wixels-package.json"
        guard FileManager.default.fileExists(atPath: path) else { return true }
        guard let manifest = manifests[key] else { return false }
        guard manifest.library(named: filename) != nil else {
            Log.note("package '\(manifest.id)' does not declare '\(filename)' — skipping it")
            return false
        }
        return true
    }

    private static func manifestKey(directory: String, group: String) -> String { directory + "/" + group }

    /// An explicit build/run selection limits widget dylibs to its matching package.
    /// With no selection, independent packages compose freely.
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

    /// A package means the first path component beneath a plugin root. Deeper
    /// directories are scanned for convenience but remain part of that package.
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
        // An explicit root is a hermetic staging/test environment. Do not mix
        // user-installed extensions into its validation result.
        if let developmentRoot {
            return [developmentRoot.appendingPathComponent("plugins").path,
                    developmentRoot.appendingPathComponent("themes").path]
        }
        var dirs: [URL] = []
        if let resources = bundleResourceURL {
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
