# Swift Configuration AWS

[![](https://img.shields.io/badge/Swift-6.2+-red?logo=Swift&logoColor=white)](https://swift.org)
[![](https://github.com/SongShift/swift-configuration-aws/actions/workflows/ci.yml/badge.svg?event=push)](https://github.com/SongShift/swift-configuration-aws/actions/workflows/ci.yml)
[![](https://img.shields.io/github/v/release/SongShift/swift-configuration-aws)](https://github.com/SongShift/swift-configuration-aws/releases)

An [AWS Secrets Manager](https://aws.amazon.com/secrets-manager/) provider for the [Swift Configuration](https://github.com/apple/swift-configuration) framework.

This package implements Swift Configuration's `ConfigProvider` protocol to vend secrets stored in AWS Secrets Manager. It is not a general-purpose configuration library. For the core API (readers, provider hierarchy, watching, etc.), see the [swift-configuration](https://github.com/apple/swift-configuration) repository.

It works with any server-side Swift application, whether you're running on [AWS Lambda](https://aws.amazon.com/lambda/), ECS, EC2, or anywhere else with access to Secrets Manager. At [SongShift](https://songshift.com), we use it to power configuration across our Swift Lambda functions. If you're curious about that stack, we spoke about it at [ServerSide.swift 2025](https://youtu.be/JwSwAg-ESMI?si=IYtB12ZhJ8G7dY4T).

## Requirements

- Swift 6.2+
- macOS 15+ / Linux

## AWS SDK support

This package doesn't bundle its own AWS client. Instead, it defines an `AWSSecretsManagerVendor` protocol with a single requirement:

```swift
public protocol AWSSecretsManagerVendor: Sendable {
    func fetchSecretValue(forKey key: String) async throws -> String?
}
```

The actual networking is left to whichever AWS SDK you're already using. Currently, the package ships with built-in support for [Soto](https://github.com/soto-project/soto), enabled through a [package trait](https://docs.swift.org/swiftpm/documentation/packagemanagerdocs/addingdependencies#Packages-with-Traits):

| SDK | Trait | Status |
| --- | ----- | ------ |
| [Soto](https://github.com/soto-project/soto) `SecretsManager` | `Soto` | Supported |

When the `Soto` trait is enabled, `SotoSecretsManager.SecretsManager` automatically conforms to `AWSSecretsManagerVendor`, and convenience initializers are available on `AWSSecretsManagerProvider`.

If you use a different AWS SDK, you can conform its Secrets Manager client to `AWSSecretsManagerVendor` yourself.

## Installation

Add the following to your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/apple/swift-configuration.git", from: "1.0.0"),
    .package(url: "https://github.com/songshift/swift-configuration-aws.git", from: "1.0.0"),
]
```

Then add the dependency to your target:

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "Configuration", package: "swift-configuration"),
        .product(name: "ConfigurationAWS", package: "swift-configuration-aws"),
    ]
)
```

To enable Soto support, add the `Soto` trait to the package dependency:

```swift
.package(
    url: "https://github.com/songshift/swift-configuration-aws.git",
    from: "1.0.0",
    traits: ["Soto"]
),
```

## Usage

### Key format

Secrets in AWS Secrets Manager are expected to be JSON objects. Keys are dot-separated, where the first component is the secret name and the rest navigate into the JSON structure.

For example, given a secret named `prod/database` with the following value:

```json
{
  "host": "db.example.com",
  "port": 5432,
  "credentials": {
    "username": "song",
    "password": "shift"
  }
}
```

You would access these values using:

```swift
config.string(forKey: "prod/database.host")                    // "db.example.com"
config.int(forKey: "prod/database.port")                       // 5432
config.string(forKey: "prod/database.credentials.username")    // "song"
config.string(forKey: "prod/database.credentials.password")    // "shift"
```

All values returned by this provider are automatically marked as secrets.

### Basic usage

Create a provider and pass it to a `ConfigReader`. Without prefetching, the provider starts with an empty cache and fetches secrets on demand.

```swift
import Configuration
import ConfigurationAWS

let provider = AWSSecretsManagerProvider(vendor: myVendor)
let config = ConfigReader(provider: provider)

// Fetches from Secrets Manager on first access, then caches the result
let dbHost = await config.string(forKey: "prod/database.host")
```

With the `Soto` trait enabled, you can pass a `SecretsManager` client directly:

```swift
import SotoSecretsManager

let client = AWSClient(/* ... */)
let sm = SecretsManager(client: client)

let provider = AWSSecretsManagerProvider(sotoClient: sm)
let config = ConfigReader(provider: provider)
```

### Prefetching secrets

If you know which secrets you need at startup, you can prefetch them. This loads the secrets eagerly so that synchronous reads work immediately without a network call.

```swift
let provider = try await AWSSecretsManagerProvider(
    vendor: myVendor,
    prefetchSecretNames: ["prod/database", "prod/api-keys"]
)
let config = ConfigReader(provider: provider)

// Available immediately from the prefetched cache
let dbHost = config.string(forKey: "prod/database.host")
```

### Cache TTL

The provider caches secret values to avoid hitting Secrets Manager on every read. The default TTL is 5 minutes. You can configure this at init:

```swift
let provider = AWSSecretsManagerProvider(
    vendor: myVendor,
    cacheTTL: .seconds(60)
)
```

When using the async `fetchValue` path (or reading through `ConfigReader`'s async accessors), the provider checks whether the cached value has expired. If it has, it fetches a fresh copy from Secrets Manager before returning. Synchronous reads always return whatever is currently in the cache.

### Polling with Service Lifecycle

For long-running services, the provider can poll Secrets Manager on a regular interval to keep prefetched secrets fresh in the background. This is built on [Swift Service Lifecycle](https://github.com/swift-server/swift-service-lifecycle).

Pass a `pollingInterval` at init and add the provider to your `ServiceGroup`:

```swift
import ServiceLifecycle

let provider = try await AWSSecretsManagerProvider(
    vendor: myVendor,
    prefetchSecretNames: ["prod/database", "prod/api-keys"],
    pollingInterval: .seconds(30)
)

let serviceGroup = ServiceGroup(
    services: [provider],
    logger: logger
)

try await serviceGroup.run()
```

The provider will re-fetch each prefetched secret every 30 seconds, and gracefully stop polling when the service group shuts down.

### Watching for changes

The provider supports Swift Configuration's watching API. You can watch a single key or the entire snapshot for changes. Updates are delivered through an `AsyncSequence` whenever a secret value changes after a cache refresh or poll.

Watch a single key:

```swift
try await provider.watchValue(forKey: "prod/database.host", type: .string) { updates in
    for await result in updates {
        let value = try result.get()
        print("host changed: \(value)")
    }
}
```

Watch the full snapshot:

```swift
try await provider.watchSnapshot { snapshots in
    for await snapshot in snapshots {
        // React to any secret changing
    }
}
```

Watchers are typically used together with polling so that changes are detected automatically in the background.

## Contributing

Contributions are welcome. Please open an issue or submit a pull request.

## License

This project is licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for details.