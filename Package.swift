// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "dooyou",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "dooyou",
            path: "Sources/dooyou",
            resources: [.process("Resources")]
        )
    ]
)
