//
//  FetchValueTests.swift
//
//  Created by Ben Rosen on 2/22/26.
//  Copyright © 2026 SongShift, LLC. All rights reserved.
//

#if Soto
import Configuration
import Foundation
import Testing
@testable import ConfigurationAWS

@Suite("Fetch Value")
struct FetchValueTests {
    @Test func fetchValueRoundTrip() async throws {
        let env = LocalStackTestEnvironment()
        let name = uniqueSecretName()
        defer { Task { try? await env.shutdown() } }

        _ = try await env.secretsManager.createSecret(
            name: name,
            secretString: #"{"db_host":"localhost","db_port":5432}"#
        )
        defer { Task { try? await env.secretsManager.deleteSecret(
            forceDeleteWithoutRecovery: true,
            secretId: name
        ) } }

        let provider = AWSSecretsManagerProvider(vendor: env.secretsManager)
        let key = configKey("\(name).db_host")
        let result = try await provider.fetchValue(forKey: key, type: .string)

        #expect(result.value?.content == .string("localhost"))
        #expect(result.value?.isSecret == true)
        #expect(result.encodedKey == key.description)
        #expect(provider.providerName == "AWSSecretsManagerProvider")
    }

    @Test func prefetchPopulatesCache() async throws {
        let env = LocalStackTestEnvironment()
        let name = uniqueSecretName()
        defer { Task { try? await env.shutdown() } }

        _ = try await env.secretsManager.createSecret(
            name: name,
            secretString: #"{"token":"abc123"}"#
        )
        defer { Task { try? await env.secretsManager.deleteSecret(
            forceDeleteWithoutRecovery: true,
            secretId: name
        ) } }

        let provider = try await AWSSecretsManagerProvider(
            vendor: env.secretsManager,
            prefetchSecretNames: [name]
        )

        // Sync access should work without an async fetch since the secret was prefetched
        let result = try provider.value(forKey: configKey("\(name).token"), type: .string)
        #expect(result.value?.content == .string("abc123"))
    }

    @Test func returnsNilForMissingSecret() async throws {
        let env = LocalStackTestEnvironment()
        defer { Task { try? await env.shutdown() } }

        let provider = AWSSecretsManagerProvider(vendor: env.secretsManager)
        let result = try await provider.fetchValue(
            forKey: configKey("nonexistent-\(UUID()).field"),
            type: .string
        )
        #expect(result.value == nil)
    }

    @Test func syncValueReturnsNilBeforeFetch() async throws {
        let env = LocalStackTestEnvironment()
        let name = uniqueSecretName()
        defer { Task { try? await env.shutdown() } }

        _ = try await env.secretsManager.createSecret(name: name, secretString: #"{"key":"val"}"#)
        defer { Task { try? await env.secretsManager.deleteSecret(
            forceDeleteWithoutRecovery: true,
            secretId: name
        ) } }

        let provider = AWSSecretsManagerProvider(vendor: env.secretsManager)

        // Sync access before any fetch returns nil
        let before = try provider.value(forKey: configKey("\(name).key"), type: .string)
        #expect(before.value == nil)

        // After async fetch, sync access works
        _ = try await provider.fetchValue(forKey: configKey("\(name).key"), type: .string)
        let after = try provider.value(forKey: configKey("\(name).key"), type: .string)
        #expect(after.value?.content == .string("val"))
    }

    @Test func nestedKeyTraversal() async throws {
        let env = LocalStackTestEnvironment()
        let name = uniqueSecretName()
        defer { Task { try? await env.shutdown() } }

        let json = #"{"a":{"b":{"c":"deep_value"}}}"#
        _ = try await env.secretsManager.createSecret(name: name, secretString: json)
        defer { Task { try? await env.secretsManager.deleteSecret(
            forceDeleteWithoutRecovery: true,
            secretId: name
        ) } }

        let provider = AWSSecretsManagerProvider(vendor: env.secretsManager)
        let result = try await provider.fetchValue(
            forKey: configKey("\(name).a.b.c"),
            type: .string
        )
        #expect(result.value?.content == .string("deep_value"))
    }

    @Test func missingIntermediateKeyReturnsNil() async throws {
        let env = LocalStackTestEnvironment()
        let name = uniqueSecretName()
        defer { Task { try? await env.shutdown() } }

        _ = try await env.secretsManager.createSecret(name: name, secretString: #"{"a":"value"}"#)
        defer { Task { try? await env.secretsManager.deleteSecret(
            forceDeleteWithoutRecovery: true,
            secretId: name
        ) } }

        let provider = try await AWSSecretsManagerProvider(
            vendor: env.secretsManager,
            prefetchSecretNames: [name]
        )

        let result = try provider.value(
            forKey: configKey("\(name).missing.nested.field"),
            type: .string
        )
        #expect(result.value == nil)
    }

    @Test func multipleSecretsPrefetchAndAccess() async throws {
        let env = LocalStackTestEnvironment()
        let name1 = uniqueSecretName()
        let name2 = uniqueSecretName()
        defer { Task { try? await env.shutdown() } }

        _ = try await env.secretsManager.createSecret(
            name: name1,
            secretString: #"{"user":"alice"}"#
        )
        _ = try await env.secretsManager.createSecret(name: name2, secretString: #"{"user":"bob"}"#)
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

        let r1 = try provider.value(forKey: configKey("\(name1).user"), type: .string)
        let r2 = try provider.value(forKey: configKey("\(name2).user"), type: .string)
        #expect(r1.value?.content == .string("alice"))
        #expect(r2.value?.content == .string("bob"))
    }
}
#endif
