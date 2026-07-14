// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ThemeTemplate", platforms: [.macOS(.v14)],
    products: [.library(name: "ThemeTemplate", type: .dynamic, targets: ["ThemeTemplate"])],
    dependencies: [.package(path: "../../WixelsKit")],
    targets: [.target(name: "ThemeTemplate", dependencies: [.product(name: "WixelsKit", package: "WixelsKit")])]
)
