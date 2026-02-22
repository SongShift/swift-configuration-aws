//
//  ProviderTests.swift
//  swift-configuration-aws
//
//  Created by Ben on 11/16/25.
//

import Testing
@testable import ConfigurationAWS
import ConfigurationTesting

@Suite("Provider Compat")
struct ProviderTests {

    @Test func compatWithPrefetch() async throws {
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

        let vendor = MockVendor(secrets: secrets)
        let provider = try await AWSSecretsManagerProvider(
            vendor: vendor,
            prefetchSecretNames: Array(secrets.keys)
        )
        try await ProviderCompatTest(provider: provider).runTest()
    }

}
