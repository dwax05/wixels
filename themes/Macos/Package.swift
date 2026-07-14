// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ThemeMacos",
    platforms: [.macOS(.v14)],
    products: [.library(name: "ThemeMacos", type: .dynamic, targets: ["ThemeMacos"])],
    dependencies: [.package(path: "../../WixelsKit")],
    targets: [.target(name: "ThemeMacos",
        dependencies: [.product(name: "WixelsKit", package: "WixelsKit")])]
)
