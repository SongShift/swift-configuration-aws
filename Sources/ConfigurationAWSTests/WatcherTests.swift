import Testing
import Configuration
@testable import ConfigurationAWS

@Suite("Watchers")
struct WatcherTests {

    @Test func watchValueReceivesInitialValue() async throws {
        let vendor = MockVendor(secrets: [
            "secret": #"{"field": "hello"}"#
        ])
        let provider = try await AWSSecretsManagerProvider(
            vendor: vendor,
            prefetchSecretNames: ["secret"]
        )

        let result: Result<LookupResult, any Error> = try await provider.watchValue(
            forKey: configKey("secret.field"),
            type: .string
        ) { updates in
            for await value in updates {
                return value
            }
            fatalError("Stream ended unexpectedly")
        }

        let lookupResult = try result.get()
        #expect(lookupResult.value?.content == .string("hello"))
    }

    @Test func watchValueNotifiedOnChange() async throws {
        let clock = TestClock()
        let vendor = MockVendor(secrets: ["secret": #"{"field": "initial"}"#])
        let provider = try await _AWSSecretsManagerProvider(
            vendor: vendor,
            clock: clock,
            prefetchSecretNames: ["secret"],
            cacheTTL: .seconds(10)
        )

        try await confirmation("watcher received update") { confirm in
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
                                continue // Skip initial value
                            }
                            let content = try value.get().value?.content
                            if case .string(let s) = content {
                                #expect(s == "updated")
                                confirm()
                            }
                            return
                        }
                    }
                }

                // Wait a bit for watcher to register, then trigger reload with new value
                try await Task.sleep(for: .milliseconds(50))
                await vendor.setSecret("secret", value: #"{"field": "updated"}"#)
                clock.advance(by: .seconds(11))
                try await provider.reloadSecretIfNeeded(secretName: "secret", overrideCacheTTL: true)

                try await group.waitForAll()
            }
        }
    }

    @Test func watchSnapshotReceivesInitialSnapshot() async throws {
        let vendor = MockVendor(secrets: [
            "secret": #"{"field": "hello"}"#
        ])
        let provider = try await AWSSecretsManagerProvider(
            vendor: vendor,
            prefetchSecretNames: ["secret"]
        )

        let snapshot: any ConfigSnapshot = try await provider.watchSnapshot { updates in
            for await snapshot in updates {
                return snapshot
            }
            fatalError("Stream ended unexpectedly")
        }

        let result = try snapshot.value(forKey: configKey("secret.field"), type: .string)
        #expect(result.value?.content == .string("hello"))
    }

    @Test func watchSnapshotAlwaysNotifiedOnReload() async throws {
        let vendor = MockVendor(secrets: [
            "secret": #"{"field": "same"}"#
        ])
        let provider = try await AWSSecretsManagerProvider(
            vendor: vendor,
            prefetchSecretNames: ["secret"]
        )

        try await confirmation("snapshot received on reload") { confirm in
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await provider.watchSnapshot { updates in
                        var count = 0
                        for await _ in updates {
                            count += 1
                            if count >= 2 {
                                confirm()
                                return
                            }
                        }
                    }
                }

                try await Task.sleep(for: .milliseconds(50))
                try await provider.reloadSecretIfNeeded(secretName: "secret", overrideCacheTTL: true)

                try await group.waitForAll()
            }
        }
    }

    @Test func watcherCleanupAfterHandlerReturns() async throws {
        let vendor = MockVendor(secrets: [
            "secret": #"{"field": "value"}"#
        ])
        let provider = try await AWSSecretsManagerProvider(
            vendor: vendor,
            prefetchSecretNames: ["secret"]
        )

        // Watch and immediately return after first value
        let _: Result<LookupResult, any Error> = try await provider.watchValue(
            forKey: configKey("secret.field"),
            type: .string
        ) { updates in
            for await value in updates {
                return value
            }
            fatalError()
        }

        // Subsequent reloads should not crash
        try await provider.reloadSecretIfNeeded(secretName: "secret", overrideCacheTTL: true)
    }
}
