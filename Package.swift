// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "iPodConnect",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .executableTarget(
            name: "iPodConnect",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/iPodConnect"
        )
    ]
)
