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
        .library(name: "DesignSystem", targets: ["DesignSystem"])
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
            dependencies: ["Models"],
            path: "Sources/Auth"
        ),
        .target(
            name: "Persistence",
            dependencies: ["Models"],
            path: "Sources/Persistence"
        ),
        .target(name: "DesignSystem", path: "Sources/DesignSystem"),
        .testTarget(
            name: "NetworkingTests",
            dependencies: ["Networking", "Models"],
            path: "Tests/NetworkingTests"
        ),
        .testTarget(
            name: "AuthTests",
            dependencies: ["Auth"],
            path: "Tests/AuthTests"
        ),
        .testTarget(
            name: "DesignSystemTests",
            dependencies: ["DesignSystem"],
            path: "Tests/DesignSystemTests"
        )
    ],
    swiftLanguageModes: [.v6]
)
