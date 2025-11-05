//
//  SotoSecretsManager+Vendor.swift
//  swift-configuration-aws
//
//  Created by Ben on 11/5/25.
//  Copyright © 2025 SongShift, LLC. All rights reserved.
//

import SotoSecretsManager
import ConfigurationAWS

extension SecretsManager: AWSSecretsManagerVendor {
    public func fetchSecretValue(forKey key: String) async throws -> String? {
        do {
            return try await self.getSecretValue(SecretsManager.GetSecretValueRequest(secretId: key)).secretString
        } catch {
            if let error = error as? SecretsManagerErrorType,
               error == .resourceNotFoundException {
                return nil
            }
            throw error
        }
    }
}
