//
//  TestEnvironment.swift
//
//  Created by Ben Rosen on 2/22/26.
//  Copyright © 2026 SongShift, LLC. All rights reserved.
//

#if Soto
import Configuration
import Foundation
import SotoSecretsManager

struct LocalStackTestEnvironment {
    let awsClient: AWSClient
    let secretsManager: SecretsManager

    init() {
        let endpoint = ProcessInfo.processInfo.environment["LOCALSTACK_ENDPOINT"]
            ?? "http://localhost:4566"
        self.awsClient = AWSClient(
            credentialProvider: .static(accessKeyId: "test", secretAccessKey: "test")
        )
        self.secretsManager = SecretsManager(
            client: self.awsClient,
            region: .useast1,
            endpoint: endpoint
        )
    }

    func shutdown() async throws {
        try await self.awsClient.shutdown()
    }
}

func uniqueSecretName() -> String {
    "test-\(UUID().uuidString)"
}

func configKey(_ dotSeparated: String) -> AbsoluteConfigKey {
    AbsoluteConfigKey(dotSeparated.split(separator: ".").map(String.init))
}
#endif
