// swift-tools-version:6.0
import PackageDescription
let package = Package(name: "WidgetClock", platforms: [.macOS(.v14)], products: [.library(name: "WidgetClock", type: .dynamic, targets: ["WidgetClock"])], dependencies: [.package(path: "../../../WixelsKit")], targets: [.target(name: "WidgetClock", dependencies: [.product(name: "WixelsKit", package: "WixelsKit")])])
