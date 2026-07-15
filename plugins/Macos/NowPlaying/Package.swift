// swift-tools-version:6.0
import PackageDescription
let package = Package(name: "WidgetNowPlaying", platforms: [.macOS(.v14)], products: [.library(name: "WidgetNowPlaying", type: .dynamic, targets: ["WidgetNowPlaying"])], dependencies: [.package(path: "../../../WixelsKit")], targets: [.target(name: "WidgetNowPlaying", dependencies: [.product(name: "WixelsKit", package: "WixelsKit")])])
