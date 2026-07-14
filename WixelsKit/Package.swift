// swift-tools-version:6.0
import PackageDescription

// WixelsKit is its own package so its dynamic library is linked (not statically
// embedded) by the host and every plugin. A same-package .dynamic product still
// gets static-linked into sibling targets — only a CROSS-package dynamic product
// is shared as one dylib at runtime, which is what gives type identity across
// dlopen. That single shared copy is the whole point of this split.
let package = Package(
    name: "WixelsKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "WixelsKit", type: .dynamic, targets: ["WixelsKit"]),
    ],
    targets: [
        .target(name: "WixelsKit"),
        .executableTarget(
            name: "WixelsKitTests",
            dependencies: ["WixelsKit"],
            path: "Tests/WixelsKitTests"
        ),
    ]
)
