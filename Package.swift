// swift-tools-version:6.0
import PackageDescription

// The wixels host (executable) + its dep on WixelsKit. WixelsKit lives in its own
// package (./WixelsKit) so its dynamic library is a cross-package product — linked as
// one shared dylib by the host AND every plugin, giving a single copy of the shared
// type metadata at runtime (type identity holds across dlopen).
//
// Widgets are NOT built here. Each is a standalone package under ./plugins/<Name>/
// producing a libWidget<Name>.dylib. Run ./build-plugins.sh separately to stage
// extensions for an app bundle or an explicit source-checkout run.
let package = Package(
    name: "wixels",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "WixelsKit"),
        .package(url: "https://github.com/LebJe/TOMLKit.git", from: "0.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "wixels",
            dependencies: [
                .product(name: "WixelsKit", package: "WixelsKit"),
                .product(name: "TOMLKit", package: "TOMLKit"),
            ],
            path: "Sources/wixels"
        ),
    ]
)
