//
//  AWSSecretsManagerProvider+ServiceLifecycle.swift
//  swift-configuration-aws
//
//  Created by Ben on 11/13/25.
//  Copyright © 2025 SongShift, LLC. All rights reserved.
//

import ServiceLifecycle
import AsyncAlgorithms

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

// MARK: - Swift Service Lifecycle
extension AWSSecretsManagerProvider: Service {
    
    public func run() async throws {
        guard let _pollingInterval else { return }
        for try await _ in AsyncTimerSequence(interval: Duration.seconds(1), clock: .continuous).cancelOnGracefulShutdown() {
            do {
                try await withThrowingDiscardingTaskGroup { taskGroup in
                    for prefetchSecretName in _prefetchSecretNames {
                        taskGroup.addTask {
                            try await self.reloadSecretIfNeeded(secretName: prefetchSecretName, overrideCacheTTL: true)
                        }
                    }
                }
            } catch {
                print("Failed while polling: \(error)")
            }
        }
    }
}
