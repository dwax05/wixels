// swift-tools-version:6.0
import PackageDescription

// Standalone widget plugin producing libWidgetFrog.dylib. The repo's ./build-plugins.sh
// builds every plugins/* package into ./build and installs the dylibs next to the
// wixels executable (.build/<config>/), where the host loads them at launch — no core
// rebuild. Build with the SAME Swift toolchain as the core (no stable cross-version
// Swift ABI). See docs/architecture.md.
let package = Package(
    name: "WidgetFrog",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "WidgetFrog", type: .dynamic, targets: ["WidgetFrog"]),
    ],
    dependencies: [
        .package(path: "../../../WixelsKit"),
    ],
    targets: [
        .target(name: "WidgetFrog",
                dependencies: [.product(name: "WixelsKit", package: "WixelsKit")]),
    ]
)
