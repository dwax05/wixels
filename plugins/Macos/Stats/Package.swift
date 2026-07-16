// swift-tools-version:6.0
import PackageDescription
let package = Package(name: "WidgetStats", platforms: [.macOS(.v14)], products: [.library(name: "WidgetStats", type: .dynamic, targets: ["WidgetStats"])], dependencies: [.package(path: "../../../WixelsKit"), .package(path: "../Support")], targets: [.target(name: "WidgetStats", dependencies: [.product(name: "WixelsKit", package: "WixelsKit"), .product(name: "MacosWidgetPresentation", package: "Support")])])
