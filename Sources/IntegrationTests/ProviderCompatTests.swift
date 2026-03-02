//
//  ProviderCompatTests.swift
//
//  Created by Ben Rosen on 2/22/26.
//  Copyright © 2026 SongShift, LLC. All rights reserved.
//

#if Soto
import Configuration
import ConfigurationTesting
import Testing
@testable import ConfigurationAWS

@Suite("Provider Compat")
struct ProviderCompatTests {
    @Test func providerCompatWithPrefetch() async throws {
        let env = LocalStackTestEnvironment()
        defer { Task { try? await env.shutdown() } }

        let secrets: [String: String] = [
            "string": #"{"string": "Hello"}"#,
            "int": #"{"int": 42}"#,
            "double": #"{"double": 3.14}"#,
            "bool": #"{"bool": true}"#,
            "bytes": #"{"bytes": [109, 97, 103, 105, 99]}"#,
            "stringy": #"{"array": ["Hello", "World"]}"#,
            "inty": #"{"array": [42, 24]}"#,
            "doubly": #"{"array": [3.14, 2.72]}"#,
            "booly": #"{"array": [true, false]}"#,
            "byteChunky": #"{"array": [[109, 97, 103, 105, 99], [109, 97, 103, 105, 99, 50]]}"#,
            "other": #"{"string": "Other Hello", "int": 24, "double": 2.72, "bool": false, "bytes": [109, 97, 103, 105, 99, 50], "stringy": {"array": ["Hello", "Swift"]}, "inty": {"array": [16, 32]}, "doubly": {"array": [0.9, 1.8]}, "booly": {"array": [false, true, true]}, "byteChunky": {"array": [[109, 97, 103, 105, 99], [109, 97, 103, 105, 99, 50], [109, 97, 103, 105, 99]]}}"#,
        ]

        // Create all secrets in LocalStack
        let secretNames = Array(secrets.keys)
        for (name, json) in secrets {
            _ = try await env.secretsManager.createSecret(name: name, secretString: json)
        }
        defer {
            Task {
                for name in secretNames {
                    _ = try? await env.secretsManager.deleteSecret(
                        forceDeleteWithoutRecovery: true,
                        secretId: name
                    )
                }
            }
        }

        let provider = try await AWSSecretsManagerProvider(
            vendor: env.secretsManager,
            prefetchSecretNames: secretNames
        )

        // Runs value(), fetchValue(), watchValue(), snapshot(), watchSnapshot()
        try await ProviderCompatTest(provider: provider).runTest()
    }
}
#endif
