import Configuration
import Testing
@testable import ConfigurationAWS

@Suite("Race Detection")
struct RaceDetectionTests {
    @Test func concurrentReloadsProduceConsistentState() async throws {
        let vendor = MockVendor(secrets: [
            "secret": #"{"field": "value"}"#,
        ])
        let provider = try await AWSSecretsManagerProvider(
            vendor: vendor,
            prefetchSecretNames: ["secret"]
        )

        // Fire many concurrent reloads — should not crash or produce inconsistent state
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 20 {
                group.addTask {
                    try await provider.reloadSecretIfNeeded(
                        secretName: "secret",
                        overrideCacheTTL: true
                    )
                }
            }
            try await group.waitForAll()
        }

        // Cache should still be consistent
        let result = try provider.value(forKey: configKey("secret.field"), type: .string)
        #expect(result.value?.content == .string("value"))
    }
}
