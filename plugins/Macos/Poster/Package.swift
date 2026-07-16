// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "WidgetPoster",
    platforms: [.macOS(.v14)],
    products: [.library(name: "WidgetPoster", type: .dynamic, targets: ["WidgetPoster"])],
    dependencies: [.package(path: "../../../WixelsKit"), .package(path: "../Support")],
    targets: [.target(name: "WidgetPoster", dependencies: [.product(name: "WixelsKit", package: "WixelsKit"), .product(name: "MacosWidgetPresentation", package: "Support")])]
)
