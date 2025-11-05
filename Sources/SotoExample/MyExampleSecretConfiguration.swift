//
//  MyExampleSecretConfiguration.swift
//  swift-configuration-aws
//
//  Created by Ben on 11/5/25.
//  Copyright © 2025 SongShift, LLC. All rights reserved.
//

import Configuration

struct MyExampleSecretConfiguration: Codable {
    let clientId: String
    let clientSecret: String
    
    public init(clientId: String, clientSecret: String) {
        self.clientId = clientId
        self.clientSecret = clientSecret
    }
}

extension MyExampleSecretConfiguration {
    public init(configReader: ConfigReader) async throws {
        self.clientId = try await configReader.fetchRequiredString(forKey: "myExampleSecret.clientId", isSecret: false)
        self.clientSecret = try await configReader.fetchRequiredString(forKey: "myExampleSecret.clientSecret", isSecret: true)
    }
}
