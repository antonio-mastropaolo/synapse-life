// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SynapseLifeKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "Models", targets: ["Models"]),
        .library(name: "Networking", targets: ["Networking"]),
        .library(name: "Auth", targets: ["Auth"]),
        .library(name: "Persistence", targets: ["Persistence"]),
        .library(name: "Connectors", targets: ["Connectors"]),
        .library(name: "Intelligence", targets: ["Intelligence"]),
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .library(name: "Charts", targets: ["SynapseCharts"]),
        .library(name: "Features", targets: ["Features"]),
        .library(name: "AppLifecycle", targets: ["AppLifecycle"]),
        .library(name: "Tools", targets: ["Tools"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/pointfreeco/swift-snapshot-testing",
            exact: "1.17.4"
        )
    ],
    targets: [
        .target(name: "Models", path: "Sources/Models"),
        .target(
            name: "Networking",
            dependencies: ["Models"],
            path: "Sources/Networking"
        ),
        .target(
            name: "Auth",
            dependencies: ["Models", "Networking"],
            path: "Sources/Auth"
        ),
        .target(
            name: "Persistence",
            dependencies: ["Models"],
            path: "Sources/Persistence"
        ),
        .target(
            name: "Connectors",
            dependencies: ["Models", "Networking", "Persistence"],
            path: "Sources/Connectors"
        ),
        .target(
            name: "Intelligence",
            dependencies: ["Models", "Networking", "Persistence"],
            path: "Sources/Intelligence"
        ),
        .target(name: "DesignSystem", path: "Sources/DesignSystem"),
        .target(
            name: "SynapseCharts",
            dependencies: ["DesignSystem"],
            path: "Sources/Charts"
        ),
        .target(
            name: "Features",
            dependencies: ["Models", "Networking", "DesignSystem", "Auth", "SynapseCharts"],
            path: "Sources/Features"
        ),
        .target(
            name: "Tools",
            path: "Sources/Tools"
        ),
        .target(
            name: "AppLifecycle",
            dependencies: ["Models", "Networking", "Auth", "DesignSystem", "Features", "Persistence", "Intelligence"],
            path: "Sources/AppLifecycle"
        ),
        .testTarget(
            name: "AppLifecycleTests",
            dependencies: ["AppLifecycle", "Models", "Networking", "Auth", "Features"],
            path: "Tests/AppLifecycleTests"
        ),
        .testTarget(
            name: "ModelsTests",
            dependencies: ["Models"],
            path: "Tests/ModelsTests"
        ),
        .testTarget(
            name: "NetworkingTests",
            dependencies: ["Networking", "Models", "Features"],
            path: "Tests/NetworkingTests"
        ),
        .testTarget(
            name: "AuthTests",
            dependencies: ["Auth", "Networking", "Models"],
            path: "Tests/AuthTests"
        ),
        .testTarget(
            name: "PersistenceTests",
            dependencies: ["Persistence", "Models"],
            path: "Tests/PersistenceTests"
        ),
        .testTarget(
            name: "ConnectorsTests",
            dependencies: ["Connectors", "Persistence", "Models", "Networking"],
            path: "Tests/ConnectorsTests"
        ),
        .testTarget(
            name: "IntelligenceTests",
            dependencies: ["Intelligence", "Persistence", "Models", "Networking"],
            path: "Tests/IntelligenceTests"
        ),
        .testTarget(
            name: "DesignSystemTests",
            dependencies: ["DesignSystem"],
            path: "Tests/DesignSystemTests"
        ),
        .testTarget(
            name: "FeaturesTests",
            dependencies: ["Features", "Models", "Networking", "Auth", "DesignSystem"],
            path: "Tests/FeaturesTests"
        ),
        .testTarget(
            name: "SnapshotTests",
            dependencies: [
                "Features",
                "Models",
                "DesignSystem",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing")
            ],
            path: "Tests/SnapshotTests",
            exclude: ["__Snapshots__/README.md"]
        )
    ],
    swiftLanguageModes: [.v6]
)
