// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MExplorer",
    platforms: [.macOS(.v14)],
    targets: [
        // Passerelle C vers la bibliotheque SMART d'IOKit, dont l'en-tete n'est
        // pas expose au module Swift.
        .target(name: "CSmart", path: "Sources/CSmart"),
        .executableTarget(
            name: "MExplorer",
            dependencies: ["CSmart"],
            path: "Sources/MExplorer",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
