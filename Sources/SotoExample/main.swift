//
//  main.swift
//  swift-configuration-aws
//
//  Created by Ben on 11/5/25.
//  Copyright © 2025 SongShift, LLC. All rights reserved.
//

import Configuration
import ConfigurationAWS
import SotoSecretsManager

let sotoSecretsManager = SecretsManager(client: .init(), region: .useast2)

let awsSecretsManagerProvider = AWSSecretsManagerProvider(vendor: sotoSecretsManager)
let configReader = ConfigReader(provider: awsSecretsManagerProvider)

do {
    let myExample = try await MyExampleSecretConfiguration(configReader: configReader)
    
    // Obviously we should not log secrets in reality :)
    print(myExample)
} catch {
    print("Failed to read configuration: \(error)")
}
