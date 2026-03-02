//
//  VendorTests.swift
//
//  Created by Ben Rosen on 2/22/26.
//  Copyright © 2026 SongShift, LLC. All rights reserved.
//

#if Soto
import Foundation
import Testing
@testable import ConfigurationAWS

@Suite("Soto Vendor")
struct VendorTests {
    @Test func fetchesExistingSecret() async throws {
        let env = LocalStackTestEnvironment()
        let name = uniqueSecretName()
        defer { Task { try? await env.shutdown() } }

        _ = try await env.secretsManager.createSecret(name: name, secretString: #"{"key":"value"}"#)
        defer { Task { try? await env.secretsManager.deleteSecret(
            forceDeleteWithoutRecovery: true,
            secretId: name
        ) } }

        let result = try await env.secretsManager.fetchSecretValue(forKey: name)
        #expect(result == #"{"key":"value"}"#)
    }

    @Test func returnsNilForNonexistentSecret() async throws {
        let env = LocalStackTestEnvironment()
        defer { Task { try? await env.shutdown() } }

        let result = try await env.secretsManager.fetchSecretValue(forKey: "nonexistent-\(UUID())")
        #expect(result == nil)
    }
}
#endif
