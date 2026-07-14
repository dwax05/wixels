// swift-tools-version:6.0
import PackageDescription
let package = Package(name: "ThemeCynaberii", platforms: [.macOS(.v14)],
    products: [.library(name: "ThemeCynaberii", type: .dynamic, targets: ["ThemeCynaberii"])],
    dependencies: [.package(path: "../../WixelsKit")],
    targets: [.target(name: "ThemeCynaberii", dependencies: [.product(name: "WixelsKit", package: "WixelsKit")])])
