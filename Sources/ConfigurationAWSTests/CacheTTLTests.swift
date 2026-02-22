import Configuration
import Testing
@testable import ConfigurationAWS

@Suite("Cache TTL")
struct CacheTTLTests {
    @Test func freshCacheSkipsVendorCall() async throws {
        let clock = TestClock()
        let vendor = MockVendor(secrets: [
            "secret": #"{"field": "value"}"#,
        ])
        let provider = try await _AWSSecretsManagerProvider(
            vendor: vendor,
            clock: clock,
            prefetchSecretNames: ["secret"],
            cacheTTL: .seconds(300)
        )
        await #expect(vendor.callCount == 1)

        // Fetch again immediately — should use cache
        let result = try await provider.fetchValue(forKey: configKey("secret.field"), type: .string)
        #expect(result.value?.content == .string("value"))
        await #expect(vendor.callCount == 1) // No additional call
    }

    @Test func staleCacheTriggersVendorCall() async throws {
        let clock = TestClock()
        let vendor = MockVendor(secrets: [
            "secret": #"{"field": "value"}"#,
        ])
        let provider = try await _AWSSecretsManagerProvider(
            vendor: vendor,
            clock: clock,
            prefetchSecretNames: ["secret"],
            cacheTTL: .seconds(300)
        )
        await #expect(vendor.callCount == 1)

        // Advance past TTL
        clock.advance(by: .seconds(301))
        _ = try await provider.fetchValue(forKey: configKey("secret.field"), type: .string)
        await #expect(vendor.callCount == 2)
    }

    @Test func cacheExactlyAtTTLBoundary() async throws {
        let clock = TestClock()
        let vendor = MockVendor(secrets: [
            "secret": #"{"field": "value"}"#,
        ])
        let provider = try await _AWSSecretsManagerProvider(
            vendor: vendor,
            clock: clock,
            prefetchSecretNames: ["secret"],
            cacheTTL: .seconds(300)
        )

        // Advance to exactly TTL — should still be fresh (< comparison)
        clock.advance(by: .seconds(300))
        _ = try await provider.fetchValue(forKey: configKey("secret.field"), type: .string)
        // Duration from prefetch instant to now == 300s, cacheTTL == 300s
        // 300 < 300 is false, so it should trigger a refetch
        await #expect(vendor.callCount == 2)
    }

    @Test func overrideCacheTTLBypassesFreshCache() async throws {
        let clock = TestClock()
        let vendor = MockVendor(secrets: [
            "secret": #"{"field": "value"}"#,
        ])
        let provider = try await _AWSSecretsManagerProvider(
            vendor: vendor,
            clock: clock,
            prefetchSecretNames: ["secret"],
            cacheTTL: .seconds(300)
        )

        // Force reload even though cache is fresh
        try await provider.reloadSecretIfNeeded(secretName: "secret", overrideCacheTTL: true)
        await #expect(vendor.callCount == 2)
    }

    @Test func emptyCacheAlwaysFetches() async throws {
        let clock = TestClock()
        let vendor = MockVendor(secrets: [
            "secret": #"{"field": "value"}"#,
        ])
        let provider = try await _AWSSecretsManagerProvider(
            vendor: vendor,
            clock: clock,
            cacheTTL: .seconds(300)
        )
        await #expect(vendor.callCount == 0)

        _ = try await provider.fetchValue(forKey: configKey("secret.field"), type: .string)
        await #expect(vendor.callCount == 1)
    }
}
