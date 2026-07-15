// swift-tools-version:6.0
import PackageDescription
let package = Package(name: "WidgetWeather", platforms: [.macOS(.v14)], products: [.library(name: "WidgetWeather", type: .dynamic, targets: ["WidgetWeather"])], dependencies: [.package(path: "../../../WixelsKit")], targets: [.target(name: "WidgetWeather", dependencies: [.product(name: "WixelsKit", package: "WixelsKit")])])
