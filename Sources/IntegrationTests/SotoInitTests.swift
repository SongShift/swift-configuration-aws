//
//  SotoInitTests.swift
//
//  Created by Ben Rosen on 2/22/26.
//  Copyright © 2026 SongShift, LLC. All rights reserved.
//

#if Soto
import Configuration
import Testing
@testable import ConfigurationAWS

@Suite("Soto Convenience Initializers")
struct SotoInitTests {
    @Test func initWithPrefetchAndAllParams() async throws {
        let env = LocalStackTestEnvironment()
        let name = uniqueSecretName()
        defer { Task { try? await env.shutdown() } }

        _ = try await env.secretsManager.createSecret(
            name: name,
            secretString: #"{"greeting":"hello"}"#
        )
        defer { Task { try? await env.secretsManager.deleteSecret(
            forceDeleteWithoutRecovery: true,
            secretId: name
        ) } }

        let provider = try await AWSSecretsManagerProvider(
            sotoClient: env.secretsManager,
            prefetchSecretNames: [name],
            pollingInterval: .seconds(5),
            cacheTTL: .seconds(60)
        )

        #expect(provider._pollingInterval == .seconds(5))
        #expect(provider.cacheTTL == .seconds(60))

        let result = try provider.value(forKey: configKey("\(name).greeting"), type: .string)
        #expect(result.value?.content == .string("hello"))
    }

    @Test func initWithoutPrefetch() async throws {
        let env = LocalStackTestEnvironment()
        let name = uniqueSecretName()
        defer { Task { try? await env.shutdown() } }

        _ = try await env.secretsManager.createSecret(name: name, secretString: #"{"key":"val"}"#)
        defer { Task { try? await env.secretsManager.deleteSecret(
            forceDeleteWithoutRecovery: true,
            secretId: name
        ) } }

        let provider = AWSSecretsManagerProvider(
            sotoClient: env.secretsManager,
            cacheTTL: .seconds(120)
        )

        #expect(provider.cacheTTL == .seconds(120))

        // Async fetch should work
        let result = try await provider.fetchValue(forKey: configKey("\(name).key"), type: .string)
        #expect(result.value?.content == .string("val"))
    }
}
#endif
