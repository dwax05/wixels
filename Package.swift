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
        .library(name: "WidgetSysBox", type: .dynamic, targets: ["WidgetSysBox"]),
        .library(name: "WidgetNowPlaying", type: .dynamic, targets: ["WidgetNowPlaying"]),
        .library(name: "WidgetDiskSnail", type: .dynamic, targets: ["WidgetDiskSnail"]),
        .library(name: "WidgetCatPet", type: .dynamic, targets: ["WidgetCatPet"]),
        .library(name: "WidgetPlant", type: .dynamic, targets: ["WidgetPlant"]),
        .library(name: "WidgetQuotes", type: .dynamic, targets: ["WidgetQuotes"]),
        .library(name: "WidgetFrog", type: .dynamic, targets: ["WidgetFrog"]),
        .library(name: "WidgetOwl", type: .dynamic, targets: ["WidgetOwl"]),
        .library(name: "WidgetWeather", type: .dynamic, targets: ["WidgetWeather"]),
        .library(name: "WidgetPoster", type: .dynamic, targets: ["WidgetPoster"]),
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
        .target(name: "WidgetSysBox",
                dependencies: [.product(name: "WixelsKit", package: "WixelsKit")]),
        .target(name: "WidgetNowPlaying",
                dependencies: [.product(name: "WixelsKit", package: "WixelsKit")]),
        .target(name: "WidgetDiskSnail",
                dependencies: [.product(name: "WixelsKit", package: "WixelsKit")]),
        .target(name: "WidgetCatPet",
                dependencies: [.product(name: "WixelsKit", package: "WixelsKit")]),
        .target(name: "WidgetPlant",
                dependencies: [.product(name: "WixelsKit", package: "WixelsKit")]),
        .target(name: "WidgetQuotes",
                dependencies: [.product(name: "WixelsKit", package: "WixelsKit")]),
        .target(name: "WidgetFrog",
                dependencies: [.product(name: "WixelsKit", package: "WixelsKit")]),
        .target(name: "WidgetOwl",
                dependencies: [.product(name: "WixelsKit", package: "WixelsKit")]),
        .target(name: "WidgetWeather",
                dependencies: [.product(name: "WixelsKit", package: "WixelsKit")]),
        .target(name: "WidgetPoster",
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
