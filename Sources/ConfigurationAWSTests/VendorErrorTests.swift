import Configuration
import Testing
@testable import ConfigurationAWS

@Suite("Vendor Errors")
struct VendorErrorTests {
    @Test func vendorThrowsDuringFetchValue() async throws {
        let vendor = MockVendor { _ in throw TestError.simulatedFailure }
        let provider = AWSSecretsManagerProvider(vendor: vendor)

        await #expect(throws: TestError.self) {
            _ = try await provider.fetchValue(forKey: configKey("secret.field"), type: .string)
        }
    }

    @Test func vendorThrowsDuringReloadKeepsOldCache() async throws {
        let clock = TestClock()
        let vendor = MockVendor(secrets: ["secret": #"{"field": "cached"}"#])
        let provider = try await _AWSSecretsManagerProvider(
            vendor: vendor,
            clock: clock,
            prefetchSecretNames: ["secret"],
            cacheTTL: .seconds(10)
        )

        // Verify initial cache
        let initial = try provider.value(forKey: configKey("secret.field"), type: .string)
        #expect(initial.value?.content == .string("cached"))

        // Expire cache and make vendor throw on next fetch
        await vendor.setError(TestError.simulatedFailure, forKey: "secret")
        clock.advance(by: .seconds(11))
        do {
            _ = try await provider.fetchValue(forKey: configKey("secret.field"), type: .string)
        } catch {
            // Expected
        }

        // Old cached value should still be there
        let afterError = try provider.value(forKey: configKey("secret.field"), type: .string)
        #expect(afterError.value?.content == .string("cached"))
    }

    @Test func vendorReturnsNilForUnknownSecret() async throws {
        let vendor = MockVendor { _ in nil }
        let provider = AWSSecretsManagerProvider(vendor: vendor)

        let result = try await provider.fetchValue(
            forKey: configKey("unknown.field"),
            type: .string
        )
        #expect(result.value == nil)
    }

    @Test func vendorReturnsNonDictJSON() async throws {
        let vendor = MockVendor(secrets: [
            "secret": "[1,2,3]",
        ])
        let provider = AWSSecretsManagerProvider(vendor: vendor)

        let result = try await provider.fetchValue(forKey: configKey("secret.field"), type: .string)
        #expect(result.value == nil)
    }

    @Test func vendorReturnsEmptyString() async throws {
        let vendor = MockVendor(secrets: [
            "secret": "",
        ])
        let provider = AWSSecretsManagerProvider(vendor: vendor)

        let result = try await provider.fetchValue(forKey: configKey("secret.field"), type: .string)
        #expect(result.value == nil)
    }
}
