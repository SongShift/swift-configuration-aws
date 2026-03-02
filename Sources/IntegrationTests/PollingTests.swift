//
//  PollingTests.swift
//
//  Created by Ben Rosen on 2/22/26.
//  Copyright © 2026 SongShift, LLC. All rights reserved.
//

#if Soto
import Configuration
import Testing
@testable import ConfigurationAWS

@Suite("Polling")
struct PollingTests {
    @Test func pollingPicksUpSecretChanges() async throws {
        let env = LocalStackTestEnvironment()
        let name = uniqueSecretName()
        defer { Task { try? await env.shutdown() } }

        _ = try await env.secretsManager.createSecret(
            name: name,
            secretString: #"{"v":"original"}"#
        )
        defer { Task { try? await env.secretsManager.deleteSecret(
            forceDeleteWithoutRecovery: true,
            secretId: name
        ) } }

        let provider = try await AWSSecretsManagerProvider(
            vendor: env.secretsManager,
            prefetchSecretNames: [name],
            pollingInterval: .milliseconds(200),
            cacheTTL: .seconds(300)
        )

        // Verify initial value
        let initial = try provider.value(forKey: configKey("\(name).v"), type: .string)
        #expect(initial.value?.content == .string("original"))

        // Update the secret in LocalStack
        _ = try await env.secretsManager.putSecretValue(
            secretId: name,
            secretString: #"{"v":"polled"}"#
        )

        // Start polling in background, wait for at least one poll cycle
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await provider.run()
            }

            // Wait enough time for at least one poll to execute
            try await Task.sleep(for: .milliseconds(500))

            // Polling uses overrideCacheTTL, so it should have picked up the change
            let polled = try provider.value(forKey: configKey("\(name).v"), type: .string)
            #expect(polled.value?.content == .string("polled"))

            group.cancelAll()
        }
    }

    @Test func runReturnsImmediatelyWithoutPollingInterval() async throws {
        let env = LocalStackTestEnvironment()
        defer { Task { try? await env.shutdown() } }

        let provider = AWSSecretsManagerProvider(vendor: env.secretsManager)

        // run() should return immediately when no polling interval is set
        try await provider.run()
    }

    @Test(.timeLimit(.minutes(1)))
    func pollingNotifiesWatchers() async throws {
        let env = LocalStackTestEnvironment()
        let name = uniqueSecretName()
        defer { Task { try? await env.shutdown() } }

        _ = try await env.secretsManager.createSecret(name: name, secretString: #"{"f":"initial"}"#)
        defer { Task { try? await env.secretsManager.deleteSecret(
            forceDeleteWithoutRecovery: true,
            secretId: name
        ) } }

        let provider = try await AWSSecretsManagerProvider(
            vendor: env.secretsManager,
            prefetchSecretNames: [name],
            pollingInterval: .milliseconds(200),
            cacheTTL: .seconds(300)
        )

        try await confirmation("watcher notified via polling") { confirm in
            try await withThrowingTaskGroup(of: Void.self) { group in
                // Start polling
                group.addTask {
                    try await provider.run()
                }

                // Start watcher
                group.addTask {
                    try await provider.watchValue(
                        forKey: configKey("\(name).f"),
                        type: .string
                    ) { updates in
                        var isFirst = true
                        for await value in updates {
                            if isFirst {
                                isFirst = false
                                continue
                            }
                            let content = try value.get().value?.content
                            #expect(content == .string("polled"))
                            confirm()
                            return
                        }
                    }
                }

                // Wait for watcher to register, then update secret
                try await Task.sleep(for: .milliseconds(100))
                _ = try await env.secretsManager.putSecretValue(
                    secretId: name,
                    secretString: #"{"f":"polled"}"#
                )

                // Wait for polling to pick up the change
                try await Task.sleep(for: .milliseconds(600))
                group.cancelAll()
            }
        }
    }
}
#endif
