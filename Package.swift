// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MExplorer",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MExplorer",
            path: "Sources/MExplorer",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
