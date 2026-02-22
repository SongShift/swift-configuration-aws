import Testing
import Configuration
@testable import ConfigurationAWS

@Suite("Fetch Value")
struct FetchValueTests {

    @Test func fetchValueOnDemandPopulatesCache() async throws {
        let vendor = MockVendor(secrets: [
            "secret": #"{"field": "hello"}"#
        ])
        let provider = AWSSecretsManagerProvider(vendor: vendor)

        // Sync value is nil before fetch
        let before = try provider.value(forKey: configKey("secret.field"), type: .string)
        #expect(before.value == nil)

        // Async fetch populates cache
        let result = try await provider.fetchValue(forKey: configKey("secret.field"), type: .string)
        #expect(result.value?.content == .string("hello"))

        // Now sync value works
        let after = try provider.value(forKey: configKey("secret.field"), type: .string)
        #expect(after.value?.content == .string("hello"))
    }

    @Test func fetchValueUpdatesStaleCache() async throws {
        let clock = TestClock()
        let vendor = MockVendor(secrets: ["secret": #"{"field": "old"}"#])
        let provider = try await _AWSSecretsManagerProvider(
            vendor: vendor,
            clock: clock,
            prefetchSecretNames: ["secret"],
            cacheTTL: .seconds(10)
        )

        let oldResult = try provider.value(forKey: configKey("secret.field"), type: .string)
        #expect(oldResult.value?.content == .string("old"))

        // Update vendor and expire cache
        await vendor.setSecret("secret", value: #"{"field": "new"}"#)
        clock.advance(by: .seconds(11))

        let newResult = try await provider.fetchValue(forKey: configKey("secret.field"), type: .string)
        #expect(newResult.value?.content == .string("new"))
    }

    @Test func fetchValueWithVendorReturningNilKeepsOldCache() async throws {
        let clock = TestClock()
        let vendor = MockVendor(secrets: ["secret": #"{"field": "cached"}"#])
        let provider = try await _AWSSecretsManagerProvider(
            vendor: vendor,
            clock: clock,
            prefetchSecretNames: ["secret"],
            cacheTTL: .seconds(10)
        )

        await vendor.removeSecret("secret")
        clock.advance(by: .seconds(11))
        let result = try await provider.fetchValue(forKey: configKey("secret.field"), type: .string)
        // Vendor returned nil on refresh, old cached value preserved
        #expect(result.value?.content == .string("cached"))
    }

    @Test func fetchValueWithVendorReturningInvalidJSONKeepsCache() async throws {
        let clock = TestClock()
        let vendor = MockVendor(secrets: ["secret": #"{"field": "cached"}"#])
        let provider = try await _AWSSecretsManagerProvider(
            vendor: vendor,
            clock: clock,
            prefetchSecretNames: ["secret"],
            cacheTTL: .seconds(10)
        )

        await vendor.setSecret("secret", value: "not json")
        clock.advance(by: .seconds(11))
        let result = try await provider.fetchValue(forKey: configKey("secret.field"), type: .string)
        #expect(result.value?.content == .string("cached"))
    }

    @Test func allValuesAreMarkedSecret() async throws {
        let vendor = MockVendor(secrets: [
            "secret": #"{"field": "value"}"#
        ])
        let provider = try await AWSSecretsManagerProvider(
            vendor: vendor,
            prefetchSecretNames: ["secret"]
        )
        let result = try provider.value(forKey: configKey("secret.field"), type: .string)
        #expect(result.value?.isSecret == true)
    }
}
