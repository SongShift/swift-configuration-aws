// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-configuration-aws",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "swift-configuration-aws",
            targets: ["ConfigurationAWS"]
        ),
    ],
    traits: [
        .trait(
            name: "Soto",
            description: "Include Soto SecretsManager conformance and convenience initializers"
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-configuration", from: "1.1.0"),
        .package(
            url: "https://github.com/swift-server/swift-service-lifecycle",
            .upToNextMinor(from: "2.9.1")
        ),
        .package(url: "https://github.com/soto-project/soto.git", from: "7.10.0"),
    ],
    targets: [
        .target(
            name: "ConfigurationAWS",
            dependencies: [
                .product(name: "Configuration", package: "swift-configuration"),
                .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
                .product(
                    name: "SotoSecretsManager",
                    package: "soto",
                    condition: .when(traits: ["Soto"])
                ),
            ]
        ),
        .testTarget(
            name: "ConfigurationAWSTests",
            dependencies: [
                "ConfigurationAWS",
                .product(name: "Configuration", package: "swift-configuration"),
                .product(name: "ConfigurationTesting", package: "swift-configuration"),
            ]
        ),
    ]
)
