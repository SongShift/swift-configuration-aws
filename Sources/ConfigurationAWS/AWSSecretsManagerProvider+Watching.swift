//
//  AWSSecretsManagerProvider+Watching.swift
//  swift-configuration-aws
//
//  Created by Ben Rosen on 11/5/25.
//  Copyright © 2025 SongShift, LLC. All rights reserved.
//

import Configuration

// MARK: - Secret change broadcasting
extension _AWSSecretsManagerProvider {

    /// Notifies observers after a single secret has been refreshed from Secrets Manager.
    /// We scope notification to only the key paths rooted under the changed secret name.
    func broadcastSecretChange(secretName: String, oldSnapshot: AWSSecretsManagerProviderSnapshot, newSnapshot: AWSSecretsManagerProviderSnapshot) {
        let (affectedKeyUpdates, snapshotObservers) = storage.withLock { storage in
            // Only inspect observers whose key path is rooted under the refreshed secret
            var updates: [(result: Result<LookupResult, any Error>, observers: [AsyncStream<Result<LookupResult, any Error>>.Continuation])] = []
            for (key, observers) in storage.secretKeyObservers {
                guard key.components.first == secretName, !observers.isEmpty else { continue }

                let previous = try? oldSnapshot.value(forKey: key, type: .string)
                let current = try? newSnapshot.value(forKey: key, type: .string)
                guard previous != current else { continue }

                let latestResult = Result { try newSnapshot.value(forKey: key, type: .string) }
                updates.append((latestResult, Array(observers.values)))
            }

            return (updates, Array(storage.secretSnapshotObservers.values))
        }

        for entry in affectedKeyUpdates {
            for observer in entry.observers {
                observer.yield(entry.result)
            }
        }

        for observer in snapshotObservers {
            observer.yield(newSnapshot)
        }
    }
}
