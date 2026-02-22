import Configuration
import Testing
@testable import ConfigurationAWS

@Suite("Initialization")
struct InitializationTests {
    @Test func simpleInitHasEmptyCache() async throws {
        let vendor = MockVendor(secrets: [:])
        let provider = AWSSecretsManagerProvider(vendor: vendor)
        let result = try provider.value(forKey: configKey("anything.field"), type: .string)
        #expect(result.value == nil)
        await #expect(vendor.callCount == 0)
    }

    @Test func simpleInitProviderName() {
        let vendor = MockVendor(secrets: [:])
        let provider = AWSSecretsManagerProvider(vendor: vendor)
        #expect(provider.providerName == "AWSSecretsManagerProvider")
    }

    @Test func prefetchInitPopulatesCache() async throws {
        let vendor = MockVendor(secrets: [
            "mySecret": #"{"field": "hello"}"#,
        ])
        let provider = try await AWSSecretsManagerProvider(
            vendor: vendor,
            prefetchSecretNames: ["mySecret"]
        )
        let result = try provider.value(forKey: configKey("mySecret.field"), type: .string)
        #expect(result.value?.content == .string("hello"))
    }

    @Test func prefetchInitFetchesOnlyRequestedSecrets() async throws {
        let vendor = MockVendor(secrets: [
            "requested": #"{"f": "v"}"#,
            "other": #"{"f": "v"}"#,
        ])
        _ = try await AWSSecretsManagerProvider(
            vendor: vendor,
            prefetchSecretNames: ["requested"]
        )
        await #expect(vendor.callCount(forKey: "requested") == 1)
        await #expect(vendor.callCount(forKey: "other") == 0)
    }

    @Test func prefetchInitWithVendorError() async {
        let vendor = MockVendor { _ in throw TestError.simulatedFailure }
        await #expect(throws: TestError.self) {
            _ = try await AWSSecretsManagerProvider(
                vendor: vendor,
                prefetchSecretNames: ["secret"]
            )
        }
    }

    @Test func prefetchInitVendorReturnsNil() async throws {
        let vendor = MockVendor { _ in nil }
        let provider = try await AWSSecretsManagerProvider(
            vendor: vendor,
            prefetchSecretNames: ["secret"]
        )
        let result = try provider.value(forKey: configKey("secret.field"), type: .string)
        #expect(result.value == nil)
    }

    @Test func prefetchInitVendorReturnsInvalidJSON() async throws {
        let vendor = MockVendor(secrets: [
            "secret": "not valid json",
        ])
        let provider = try await AWSSecretsManagerProvider(
            vendor: vendor,
            prefetchSecretNames: ["secret"]
        )
        let result = try provider.value(forKey: configKey("secret.field"), type: .string)
        #expect(result.value == nil)
    }

    @Test func prefetchInitStoresPollingInterval() async throws {
        let vendor = MockVendor(secrets: [:])
        let provider = try await AWSSecretsManagerProvider(
            vendor: vendor,
            prefetchSecretNames: [],
            pollingInterval: .seconds(60)
        )
        #expect(provider._pollingInterval == .seconds(60))
    }
}
