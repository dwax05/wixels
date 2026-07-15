// swift-tools-version:6.0
import PackageDescription

// The wixels host (executable) + its dep on WixelsKit. WixelsKit lives in its own
// package (./WixelsKit) so its dynamic library is a cross-package product — linked as
// one shared dylib by the host AND every plugin, giving a single copy of the shared
// type metadata at runtime (type identity holds across dlopen).
//
// Widgets are NOT built here. Each is a standalone package under ./plugins/<Name>/
// producing a libWidget<Name>.dylib. Run ./build-plugins.sh to build the host + every
// plugin into ./build and install the dylibs next to the wixels executable
// (.build/<config>/), where the host loads them at launch.
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
