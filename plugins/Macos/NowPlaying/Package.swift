// swift-tools-version:6.0
import PackageDescription
let package = Package(name: "WidgetNowPlaying", platforms: [.macOS(.v14)], products: [.library(name: "WidgetNowPlaying", type: .dynamic, targets: ["WidgetNowPlaying"])], dependencies: [.package(path: "../../../WixelsKit"), .package(path: "../Support")], targets: [.target(name: "WidgetNowPlaying", dependencies: [.product(name: "WixelsKit", package: "WixelsKit"), .product(name: "MacosWidgetPresentation", package: "Support")])])
