//
//  SnapshotTests.swift
//
//  Created by Ben Rosen on 2/22/26.
//  Copyright © 2026 SongShift, LLC. All rights reserved.
//

#if Soto
import Configuration
import Testing
@testable import ConfigurationAWS

@Suite("Snapshots")
struct SnapshotTests {
    @Test func snapshotRoundTrip() async throws {
        let env = LocalStackTestEnvironment()
        let name = uniqueSecretName()
        defer { Task { try? await env.shutdown() } }

        _ = try await env.secretsManager.createSecret(
            name: name,
            secretString: #"{"a":"1","b":"2"}"#
        )
        defer { Task { try? await env.secretsManager.deleteSecret(
            forceDeleteWithoutRecovery: true,
            secretId: name
        ) } }

        let provider = try await AWSSecretsManagerProvider(
            vendor: env.secretsManager,
            prefetchSecretNames: [name]
        )

        let snapshot = provider.snapshot()
        let a = try snapshot.value(forKey: configKey("\(name).a"), type: .string)
        let b = try snapshot.value(forKey: configKey("\(name).b"), type: .string)
        #expect(a.value?.content == .string("1"))
        #expect(b.value?.content == .string("2"))
    }

    @Test func snapshotReflectsOnDemandFetch() async throws {
        let env = LocalStackTestEnvironment()
        let name = uniqueSecretName()
        defer { Task { try? await env.shutdown() } }

        _ = try await env.secretsManager.createSecret(name: name, secretString: #"{"k":"v"}"#)
        defer { Task { try? await env.secretsManager.deleteSecret(
            forceDeleteWithoutRecovery: true,
            secretId: name
        ) } }

        let provider = AWSSecretsManagerProvider(vendor: env.secretsManager)

        // Snapshot before any fetch is empty
        let emptySnapshot = provider.snapshot()
        let beforeResult = try emptySnapshot.value(forKey: configKey("\(name).k"), type: .string)
        #expect(beforeResult.value == nil)

        // fetchValue populates cache
        _ = try await provider.fetchValue(forKey: configKey("\(name).k"), type: .string)

        // Snapshot after fetch reflects the data
        let populatedSnapshot = provider.snapshot()
        let afterResult = try populatedSnapshot.value(forKey: configKey("\(name).k"), type: .string)
        #expect(afterResult.value?.content == .string("v"))
    }
}
#endif
