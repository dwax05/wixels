// swift-tools-version:6.0
import PackageDescription

// Standalone widget plugin producing libWidgetClock.dylib. The repo's ./build-plugins.sh
// builds every plugins/* package into a staging directory for app resources — no core
// rebuild. Build with the SAME Swift toolchain as the core (no stable cross-version
// Swift ABI). See docs/architecture.md.
let package = Package(
    name: "WidgetClock",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "WidgetClock", type: .dynamic, targets: ["WidgetClock"]),
    ],
    dependencies: [
        .package(path: "../../../WixelsKit"),
    ],
    targets: [
        .target(name: "WidgetClock",
                dependencies: [.product(name: "WixelsKit", package: "WixelsKit")]),
    ]
)
