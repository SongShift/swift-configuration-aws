//
//  WatcherTests.swift
//
//  Created by Ben Rosen on 2/22/26.
//  Copyright © 2026 SongShift, LLC. All rights reserved.
//

#if Soto
import Configuration
import Testing
@testable import ConfigurationAWS

@Suite("Watchers")
struct WatcherTests {
    @Test func watchValueReceivesInitialValue() async throws {
        let env = LocalStackTestEnvironment()
        let name = uniqueSecretName()
        defer { Task { try? await env.shutdown() } }

        _ = try await env.secretsManager.createSecret(
            name: name,
            secretString: #"{"field":"watched"}"#
        )
        defer { Task { try? await env.secretsManager.deleteSecret(
            forceDeleteWithoutRecovery: true,
            secretId: name
        ) } }

        let provider = try await AWSSecretsManagerProvider(
            vendor: env.secretsManager,
            prefetchSecretNames: [name]
        )

        let result: Result<LookupResult, any Error> = try await provider.watchValue(
            forKey: configKey("\(name).field"),
            type: .string
        ) { updates in
            for await value in updates {
                return value
            }
            fatalError("Stream ended unexpectedly")
        }

        let lookupResult = try result.get()
        #expect(lookupResult.value?.content == .string("watched"))
        #expect(lookupResult.value?.isSecret == true)
    }

    @Test func watchValueNotifiedOnSecretChange() async throws {
        let env = LocalStackTestEnvironment()
        let name = uniqueSecretName()
        defer { Task { try? await env.shutdown() } }

        _ = try await env.secretsManager.createSecret(
            name: name,
            secretString: #"{"field":"before"}"#
        )
        defer { Task { try? await env.secretsManager.deleteSecret(
            forceDeleteWithoutRecovery: true,
            secretId: name
        ) } }

        let provider = try await AWSSecretsManagerProvider(
            vendor: env.secretsManager,
            prefetchSecretNames: [name],
            cacheTTL: .milliseconds(200)
        )

        try await confirmation("watcher received update") { confirm in
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await provider.watchValue(
                        forKey: configKey("\(name).field"),
                        type: .string
                    ) { updates in
                        var isFirst = true
                        for await value in updates {
                            if isFirst {
                                isFirst = false
                                continue // Skip initial value
                            }
                            let content = try value.get().value?.content
                            #expect(content == .string("after"))
                            confirm()
                            return
                        }
                    }
                }

                // Wait for watcher to register, then update the secret
                try await Task.sleep(for: .milliseconds(50))
                _ = try await env.secretsManager.putSecretValue(
                    secretId: name,
                    secretString: #"{"field":"after"}"#
                )

                // Wait for cache to expire, then trigger a reload
                try await Task.sleep(for: .milliseconds(300))
                try await provider.reloadSecretIfNeeded(
                    secretName: name,
                    overrideCacheTTL: true
                )

                try await group.waitForAll()
            }
        }
    }

    @Test func watchSnapshotReceivesInitialSnapshot() async throws {
        let env = LocalStackTestEnvironment()
        let name = uniqueSecretName()
        defer { Task { try? await env.shutdown() } }

        _ = try await env.secretsManager.createSecret(name: name, secretString: #"{"key":"snap"}"#)
        defer { Task { try? await env.secretsManager.deleteSecret(
            forceDeleteWithoutRecovery: true,
            secretId: name
        ) } }

        let provider = try await AWSSecretsManagerProvider(
            vendor: env.secretsManager,
            prefetchSecretNames: [name]
        )

        let snapshot: any ConfigSnapshot = try await provider.watchSnapshot { updates in
            for await snapshot in updates {
                return snapshot
            }
            fatalError("Stream ended unexpectedly")
        }

        let result = try snapshot.value(forKey: configKey("\(name).key"), type: .string)
        #expect(result.value?.content == .string("snap"))
    }

    @Test func watchSnapshotNotifiedOnSecretChange() async throws {
        let env = LocalStackTestEnvironment()
        let name = uniqueSecretName()
        defer { Task { try? await env.shutdown() } }

        _ = try await env.secretsManager.createSecret(name: name, secretString: #"{"key":"v1"}"#)
        defer { Task { try? await env.secretsManager.deleteSecret(
            forceDeleteWithoutRecovery: true,
            secretId: name
        ) } }

        let provider = try await AWSSecretsManagerProvider(
            vendor: env.secretsManager,
            prefetchSecretNames: [name]
        )

        try await confirmation("snapshot watcher received update") { confirm in
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await provider.watchSnapshot { updates in
                        var count = 0
                        for await snapshot in updates {
                            count += 1
                            if count >= 2 {
                                // Second snapshot should reflect the updated value
                                let result = try snapshot.value(
                                    forKey: configKey("\(name).key"),
                                    type: .string
                                )
                                #expect(result.value?.content == .string("v2"))
                                confirm()
                                return
                            }
                        }
                    }
                }

                try await Task.sleep(for: .milliseconds(50))
                _ = try await env.secretsManager.putSecretValue(
                    secretId: name,
                    secretString: #"{"key":"v2"}"#
                )
                try await provider.reloadSecretIfNeeded(
                    secretName: name,
                    overrideCacheTTL: true
                )

                try await group.waitForAll()
            }
        }
    }

    @Test func watcherCleanupAfterHandlerReturns() async throws {
        let env = LocalStackTestEnvironment()
        let name = uniqueSecretName()
        defer { Task { try? await env.shutdown() } }

        _ = try await env.secretsManager.createSecret(name: name, secretString: #"{"f":"v"}"#)
        defer { Task { try? await env.secretsManager.deleteSecret(
            forceDeleteWithoutRecovery: true,
            secretId: name
        ) } }

        let provider = try await AWSSecretsManagerProvider(
            vendor: env.secretsManager,
            prefetchSecretNames: [name]
        )

        // Watch and immediately return after first value
        let _: Result<LookupResult, any Error> = try await provider.watchValue(
            forKey: configKey("\(name).f"),
            type: .string
        ) { updates in
            for await value in updates {
                return value
            }
            fatalError("Stream ended unexpectedly")
        }

        // Subsequent reloads should not crash after watcher is cleaned up
        _ = try await env.secretsManager.putSecretValue(
            secretId: name,
            secretString: #"{"f":"new"}"#
        )
        try await provider.reloadSecretIfNeeded(secretName: name, overrideCacheTTL: true)

        let result = try provider.value(forKey: configKey("\(name).f"), type: .string)
        #expect(result.value?.content == .string("new"))
    }

    @Test func watchValueForUnprefetchedKeyReceivesNil() async throws {
        let env = LocalStackTestEnvironment()
        defer { Task { try? await env.shutdown() } }

        let provider = AWSSecretsManagerProvider(vendor: env.secretsManager)

        let result: Result<LookupResult, any Error> = try await provider.watchValue(
            forKey: configKey("nonexistent.field"),
            type: .string
        ) { updates in
            for await value in updates {
                return value
            }
            fatalError("Stream ended unexpectedly")
        }

        let lookupResult = try result.get()
        #expect(lookupResult.value == nil)
    }

    @Test func watcherNotNotifiedForUnchangedSecret() async throws {
        let env = LocalStackTestEnvironment()
        let name1 = uniqueSecretName()
        let name2 = uniqueSecretName()
        defer { Task { try? await env.shutdown() } }

        _ = try await env.secretsManager.createSecret(name: name1, secretString: #"{"f":"v1"}"#)
        _ = try await env.secretsManager.createSecret(name: name2, secretString: #"{"f":"v2"}"#)
        defer {
            Task {
                _ = try? await env.secretsManager.deleteSecret(
                    forceDeleteWithoutRecovery: true,
                    secretId: name1
                )
                _ = try? await env.secretsManager.deleteSecret(
                    forceDeleteWithoutRecovery: true,
                    secretId: name2
                )
            }
        }

        let provider = try await AWSSecretsManagerProvider(
            vendor: env.secretsManager,
            prefetchSecretNames: [name1, name2]
        )

        // Watch secret1, but only change secret2
        await confirmation(
            "watcher NOT notified for unchanged secret",
            expectedCount: 0
        ) { confirm in
            try? await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await provider.watchValue(
                        forKey: configKey("\(name1).f"),
                        type: .string
                    ) { updates in
                        var isFirst = true
                        for await _ in updates {
                            if isFirst {
                                isFirst = false
                                continue
                            }
                            // Should never reach here since we only changed name2
                            confirm()
                            return
                        }
                    }
                }

                try await Task.sleep(for: .milliseconds(50))

                // Update secret2 only, reload secret2 only
                _ = try await env.secretsManager.putSecretValue(
                    secretId: name2,
                    secretString: #"{"f":"changed"}"#
                )
                try await provider.reloadSecretIfNeeded(
                    secretName: name2,
                    overrideCacheTTL: true
                )

                // Give watcher time to potentially fire (it shouldn't)
                try await Task.sleep(for: .milliseconds(100))
                group.cancelAll()
            }
        }
    }
}
#endif
