// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-configuration-aws",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "swift-configuration-aws",
            targets: ["ConfigurationAWS"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-configuration", .upToNextMinor(from: "0.2.0")),
        .package(url: "https://github.com/apple/swift-service-lifecycle", .upToNextMinor(from: "2.9.1")),
        .package(url: "https://github.com/soto-project/soto.git", from: "7.10.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "ConfigurationAWS",
            dependencies: [
                .product(name: "Configuration", package: "swift-configuration"),
                .product(name: "ServiceLifecycle", package: "swift-service-lifecycle")
            ]
        ),
        .executableTarget(
            name: "SotoExample",
            dependencies: [
                "ConfigurationAWS",
                .product(name: "SotoSecretsManager", package: "soto")
            ]
        ),
    ]
)
