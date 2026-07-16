// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MacosWidgetPresentation",
    platforms: [.macOS(.v14)],
    products: [.library(name: "MacosWidgetPresentation", targets: ["MacosWidgetPresentation"])],
    dependencies: [.package(path: "../../../WixelsKit")],
    targets: [.target(name: "MacosWidgetPresentation", dependencies: [.product(name: "WixelsKit", package: "WixelsKit")])]
)
