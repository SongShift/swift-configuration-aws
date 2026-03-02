//
//  TypeConversionTests.swift
//
//  Created by Ben Rosen on 2/22/26.
//  Copyright © 2026 SongShift, LLC. All rights reserved.
//

#if Soto
import Configuration
import Testing
@testable import ConfigurationAWS

@Suite("Type Conversions")
struct TypeConversionTests {
    @Test func typesRoundTripThroughRealJSON() async throws {
        let env = LocalStackTestEnvironment()
        let name = uniqueSecretName()
        defer { Task { try? await env.shutdown() } }

        let json = """
        {"port":5432,"rate":0.75,"enabled":true,"tags":["swift","aws","config"],"ports":[80,443,8080]}
        """
        _ = try await env.secretsManager.createSecret(name: name, secretString: json)
        defer { Task { try? await env.secretsManager.deleteSecret(
            forceDeleteWithoutRecovery: true,
            secretId: name
        ) } }

        let provider = try await AWSSecretsManagerProvider(
            vendor: env.secretsManager,
            prefetchSecretNames: [name]
        )

        let intResult = try provider.value(forKey: configKey("\(name).port"), type: .int)
        #expect(intResult.value?.content == .int(5432))

        let doubleResult = try provider.value(forKey: configKey("\(name).rate"), type: .double)
        #expect(doubleResult.value?.content == .double(0.75))

        let boolResult = try provider.value(forKey: configKey("\(name).enabled"), type: .bool)
        #expect(boolResult.value?.content == .bool(true))

        let stringArrayResult = try provider.value(
            forKey: configKey("\(name).tags"),
            type: .stringArray
        )
        #expect(stringArrayResult.value?.content == .stringArray(["swift", "aws", "config"]))

        let intArrayResult = try provider.value(forKey: configKey("\(name).ports"), type: .intArray)
        #expect(intArrayResult.value?.content == .intArray([80, 443, 8080]))
    }
}
#endif
