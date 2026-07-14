// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "wixels",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "wixels",
            path: "Sources/wixels"
        )
    ]
)
