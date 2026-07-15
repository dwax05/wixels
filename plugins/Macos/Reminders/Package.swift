// swift-tools-version:6.0
import PackageDescription
let package = Package(name: "WidgetReminders", platforms: [.macOS(.v14)], products: [.library(name: "WidgetReminders", type: .dynamic, targets: ["WidgetReminders"])], dependencies: [.package(path: "../../../WixelsKit")], targets: [.target(name: "WidgetReminders", dependencies: [.product(name: "WixelsKit", package: "WixelsKit")])])
