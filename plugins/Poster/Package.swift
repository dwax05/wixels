// swift-tools-version:6.0
import PackageDescription

// Standalone widget plugin. `swift build` emits `.build/debug/libWidgetPoster.dylib`;
// the repo's ./build-plugins.sh builds every plugins/* package and installs the
// dylibs next to the wixels executable, where the host loads them at launch (no
// core rebuild). Build with the SAME Swift toolchain as the core — no stable
// cross-version Swift ABI. See DESIGN.md "Adding a widget".
let package = Package(
    name: "WidgetPoster",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "WidgetPoster", type: .dynamic, targets: ["WidgetPoster"]),
    ],
    dependencies: [
        .package(path: "../../WixelsKit"),
    ],
    targets: [
        .target(name: "WidgetPoster",
                dependencies: [.product(name: "WixelsKit", package: "WixelsKit")]),
    ]
)
