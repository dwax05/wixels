// swift-tools-version:6.0
import PackageDescription

// Standalone widget plugin producing libWidgetStats.dylib. The repo's ./build-plugins.sh
// builds every plugins/* package into ./build and installs the dylibs next to the
// wixels executable (build/<config>/), where the host loads them at launch — no core
// rebuild. Build with the SAME Swift toolchain as the core (no stable cross-version
// Swift ABI). See DESIGN.md "Adding a widget".
let package = Package(
    name: "WidgetStats",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "WidgetStats", type: .dynamic, targets: ["WidgetStats"]),
    ],
    dependencies: [
        .package(path: "../../WixelsKit"),
    ],
    targets: [
        .target(name: "WidgetStats",
                dependencies: [.product(name: "WixelsKit", package: "WixelsKit")]),
        .executableTarget(name: "WidgetStatsTests",
                          dependencies: ["WidgetStats", .product(name: "WixelsKit", package: "WixelsKit")],
                          path: "Tests"),
    ]
)
