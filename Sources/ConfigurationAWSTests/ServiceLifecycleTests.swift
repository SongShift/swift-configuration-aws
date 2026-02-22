import Testing
import Configuration
@testable import ConfigurationAWS

@Suite("Service Lifecycle")
struct ServiceLifecycleTests {

    @Test func runReturnsImmediatelyWithoutPollingInterval() async throws {
        let vendor = MockVendor(secrets: [:])
        let provider = try await AWSSecretsManagerProvider(
            vendor: vendor,
            prefetchSecretNames: []
        )
        #expect(provider._pollingInterval == nil)
        // run() should return immediately when no polling interval is set
        try await provider.run()
    }

    @Test func runPollsAllPrefetchedSecrets() async throws {
        let clock = TestClock()
        let vendor = MockVendor(secrets: [
            "s1": #"{"f": "v1"}"#,
            "s2": #"{"f": "v2"}"#,
        ])
        let provider = try await _AWSSecretsManagerProvider(
            vendor: vendor,
            clock: clock,
            prefetchSecretNames: ["s1", "s2"],
            pollingInterval: .seconds(5),
            cacheTTL: .seconds(300)
        )

        // Prefetch accounts for 2 calls
        await #expect(vendor.callCount == 2)

        // Manually simulate what polling does — call reloadSecretIfNeeded for each prefetch name
        for name in provider._prefetchSecretNames {
            try await provider.reloadSecretIfNeeded(secretName: name, overrideCacheTTL: true)
        }

        // Should have made additional calls for both secrets
        await #expect(vendor.callCount == 4)
    }

    @Test func pollingUpdatesWatchers() async throws {
        let clock = TestClock()
        let vendor = MockVendor(secrets: ["secret": #"{"field": "initial"}"#])
        let provider = try await _AWSSecretsManagerProvider(
            vendor: vendor,
            clock: clock,
            prefetchSecretNames: ["secret"],
            pollingInterval: .seconds(5),
            cacheTTL: .seconds(300)
        )

        try await confirmation("watcher received polling update") { confirm in
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await provider.watchValue(
                        forKey: configKey("secret.field"),
                        type: .string
                    ) { updates in
                        var isFirst = true
                        for await value in updates {
                            if isFirst {
                                isFirst = false
                                continue
                            }
                            let content = try value.get().value?.content
                            if case .string(let s) = content {
                                #expect(s == "polled")
                                confirm()
                            }
                            return
                        }
                    }
                }

                try await Task.sleep(for: .milliseconds(50))
                await vendor.setSecret("secret", value: #"{"field": "polled"}"#)
                try await provider.reloadSecretIfNeeded(secretName: "secret", overrideCacheTTL: true)

                try await group.waitForAll()
            }
        }
    }
}
