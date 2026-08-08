// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Fidelity",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Fidelity", path: "Sources/Fidelity")
    ]
)
