// swift-tools-version:6.0
import PackageDescription

// Standalone widget plugin. Copy this whole `Template/` folder, rename it, and edit
// Sources/WidgetTemplate/. `swift build` emits `.build/debug/libWidgetTemplate.dylib`
// — drop that into ~/.config/wixels/plugins/ and the wixels host loads it at launch
// (no core rebuild). See docs/architecture.md.
//
// The one hard rule: build this with the SAME Swift toolchain as the core — Swift has
// no stable cross-version ABI, so a mismatched plugin fails type identity across dlopen.
let package = Package(
    name: "WidgetTemplate",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "WidgetTemplate", type: .dynamic, targets: ["WidgetTemplate"]),
    ],
    dependencies: [
        // The shared plugin ABI. Point this at your wixels checkout's WixelsKit package
        // (this path assumes plugins/Template/ lives inside the repo).
        .package(path: "../../WixelsKit"),
    ],
    targets: [
        .target(name: "WidgetTemplate",
                dependencies: [.product(name: "WixelsKit", package: "WixelsKit")]),
    ]
)
