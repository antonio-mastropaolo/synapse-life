// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SynnapseKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "Models", targets: ["Models"]),
        .library(name: "Networking", targets: ["Networking"]),
        .library(name: "Auth", targets: ["Auth"]),
        .library(name: "Persistence", targets: ["Persistence"]),
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .library(name: "Charts", targets: ["SynnapseCharts"]),
        .library(name: "Features", targets: ["Features"])
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
        .target(name: "DesignSystem", path: "Sources/DesignSystem"),
        .target(
            name: "SynnapseCharts",
            dependencies: ["DesignSystem"],
            path: "Sources/Charts"
        ),
        .target(
            name: "Features",
            dependencies: ["Models", "Networking", "DesignSystem", "Auth", "SynnapseCharts"],
            path: "Sources/Features"
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
            name: "DesignSystemTests",
            dependencies: ["DesignSystem"],
            path: "Tests/DesignSystemTests"
        ),
        .testTarget(
            name: "FeaturesTests",
            dependencies: ["Features", "Models", "Networking", "Auth"],
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
