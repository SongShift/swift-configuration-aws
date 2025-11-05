//
//  AWSSecretsManagerVendor.swift
//  swift-configuration-aws
//
//  Created by Ben on 11/5/25.
//  Copyright © 2025 SongShift, LLC. All rights reserved.
//

public protocol AWSSecretsManagerVendor: Sendable {
    func fetchSecretValue(forKey key: String) async throws -> String?
}
