//
//  CacheTTLTests.swift
//
//  Created by Ben Rosen on 2/22/26.
//  Copyright © 2026 SongShift, LLC. All rights reserved.
//

#if Soto
import Configuration
import Foundation
import Testing
@testable import ConfigurationAWS

@Suite("Cache TTL")
struct CacheTTLTests {
    @Test func cacheTTLRespectsExpiry() async throws {
        let env = LocalStackTestEnvironment()
        let name = uniqueSecretName()
        defer { Task { try? await env.shutdown() } }

        _ = try await env.secretsManager.createSecret(
            name: name,
            secretString: #"{"val":"original"}"#
        )
        defer { Task { try? await env.secretsManager.deleteSecret(
            forceDeleteWithoutRecovery: true,
            secretId: name
        ) } }

        let provider = try await AWSSecretsManagerProvider(
            vendor: env.secretsManager,
            prefetchSecretNames: [name],
            cacheTTL: .milliseconds(500)
        )

        // Initial value from prefetch
        let initial = try await provider.fetchValue(forKey: configKey("\(name).val"), type: .string)
        #expect(initial.value?.content == .string("original"))

        // Update the secret in LocalStack
        _ = try await env.secretsManager.putSecretValue(
            secretId: name,
            secretString: #"{"val":"updated"}"#
        )

        // Immediately should still return cached value
        let cached = try await provider.fetchValue(forKey: configKey("\(name).val"), type: .string)
        #expect(cached.value?.content == .string("original"))

        // Wait for cache to expire
        try await Task.sleep(for: .milliseconds(600))

        // Now should fetch the updated value
        let refreshed = try await provider.fetchValue(
            forKey: configKey("\(name).val"),
            type: .string
        )
        #expect(refreshed.value?.content == .string("updated"))
    }

    @Test func deletedSecretPreservesOldCache() async throws {
        let env = LocalStackTestEnvironment()
        let name = uniqueSecretName()
        defer { Task { try? await env.shutdown() } }

        _ = try await env.secretsManager.createSecret(
            name: name,
            secretString: #"{"key":"cached"}"#
        )

        let provider = try await AWSSecretsManagerProvider(
            vendor: env.secretsManager,
            prefetchSecretNames: [name],
            cacheTTL: .milliseconds(200)
        )

        let initial = try provider.value(forKey: configKey("\(name).key"), type: .string)
        #expect(initial.value?.content == .string("cached"))

        // Delete the secret in LocalStack, then expire cache
        _ = try await env.secretsManager.deleteSecret(
            forceDeleteWithoutRecovery: true,
            secretId: name
        )
        try await Task.sleep(for: .milliseconds(300))

        // fetchValue triggers reload — vendor returns nil, old cached value preserved
        let afterDelete = try await provider.fetchValue(
            forKey: configKey("\(name).key"),
            type: .string
        )
        #expect(afterDelete.value?.content == .string("cached"))
    }

    @Test func prefetchNonexistentSecretYieldsNil() async throws {
        let env = LocalStackTestEnvironment()
        defer { Task { try? await env.shutdown() } }

        let provider = try await AWSSecretsManagerProvider(
            vendor: env.secretsManager,
            prefetchSecretNames: ["does-not-exist-\(UUID())"]
        )

        let result = try provider.value(
            forKey: configKey("does-not-exist-\(UUID()).field"),
            type: .string
        )
        #expect(result.value == nil)
    }
}
#endif
