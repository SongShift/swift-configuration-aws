//
//  AWSSecretsManagerProvider+Soto.swift
//
//  Created by Ben Rosen on 2/22/26.
//  Copyright © 2026 SongShift, LLC. All rights reserved.
//

#if Soto
import SotoSecretsManager

extension SecretsManager: AWSSecretsManagerVendor {
    public func fetchSecretValue(forKey key: String) async throws -> String? {
        do {
            return try await self
                .getSecretValue(SecretsManager.GetSecretValueRequest(secretId: key))
                .secretString
        } catch {
            if let error = error as? SecretsManagerErrorType,
               error == .resourceNotFoundException {
                return nil
            }
            throw error
        }
    }
}

public extension AWSSecretsManagerProvider {
    convenience init(sotoClient: SecretsManager, cacheTTL: Duration = .seconds(300)) {
        self.init(vendor: sotoClient, cacheTTL: cacheTTL)
    }

    convenience init(
        sotoClient: SecretsManager,
        prefetchSecretNames: [String],
        pollingInterval: Duration? = nil,
        cacheTTL: Duration = .seconds(300)
    ) async throws {
        try await self.init(
            vendor: sotoClient,
            prefetchSecretNames: prefetchSecretNames,
            pollingInterval: pollingInterval,
            cacheTTL: cacheTTL
        )
    }
}
#endif
