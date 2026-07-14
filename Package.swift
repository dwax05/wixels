// swift-tools-version:6.0
import PackageDescription

// WixelsKit lives in its own package (./WixelsKit) so its dynamic library is a
// cross-package product — linked as one shared dylib by the host AND every plugin,
// giving a single copy of the shared type metadata at runtime (type identity holds
// across dlopen). Same-package targets would each static-link it, defeating that.
let package = Package(
    name: "wixels",
    platforms: [.macOS(.v14)],
    products: [
        // Each widget is a standalone dynamic plugin the host dlopens at runtime.
        // The host does NOT depend on these; making them products just ensures
        // `swift build` builds their dylibs into .build/<config>/.
        .library(name: "WidgetClock", type: .dynamic, targets: ["WidgetClock"]),
        .library(name: "WidgetStats", type: .dynamic, targets: ["WidgetStats"]),
    ],
    dependencies: [
        .package(path: "WixelsKit"),
        .package(url: "https://github.com/LebJe/TOMLKit.git", from: "0.6.0"),
    ],
    targets: [
        .target(name: "WidgetClock",
                dependencies: [.product(name: "WixelsKit", package: "WixelsKit")]),
        .target(name: "WidgetStats",
                dependencies: [.product(name: "WixelsKit", package: "WixelsKit")]),
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
