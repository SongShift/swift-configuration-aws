//
//  AWSSecretsManagerProvider.swift
//  swift-configuration-aws
//
//  Created by Ben Rosen on 11/5/25.
//  Copyright © 2025 SongShift, LLC. All rights reserved.
//

import Configuration
import Synchronization

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

public typealias AWSSecretsManagerProvider = _AWSSecretsManagerProvider<ContinuousClock>

public final class _AWSSecretsManagerProvider<C: Clock & Sendable>: Sendable where C.Duration == Duration {
    let _vendor: AWSSecretsManagerVendor
    let clock: C
    let cacheTTL: Duration

    struct Storage {
        var snapshot: AWSSecretsManagerProviderSnapshot
        var secretKeyObservers: [AbsoluteConfigKey: [UUID: AsyncStream<Result<LookupResult, any Error>>.Continuation]]
        var secretSnapshotObservers: [UUID: AsyncStream<AWSSecretsManagerProviderSnapshot>.Continuation]
        var lastUpdatedAt: [String: C.Instant]
    }

    let storage: Mutex<Storage>

    let _pollingInterval: Duration?
    let _prefetchSecretNames: [String]

    public let providerName: String = "AWSSecretsManagerProvider"

    // MARK: - Initializers

    public init(vendor: AWSSecretsManagerVendor, cacheTTL: Duration = .seconds(300)) where C == ContinuousClock {
        self._vendor = vendor
        self.clock = ContinuousClock()
        self.cacheTTL = cacheTTL
        self.storage = .init(Storage(
            snapshot: AWSSecretsManagerProviderSnapshot(values: [:]),
            secretKeyObservers: [:],
            secretSnapshotObservers: [:],
            lastUpdatedAt: [:]
        ))
        self._prefetchSecretNames = []
        self._pollingInterval = nil
    }

    public init(vendor: AWSSecretsManagerVendor, prefetchSecretNames: [String], pollingInterval: Duration? = nil, cacheTTL: Duration = .seconds(300)) async throws where C == ContinuousClock {
        self._vendor = vendor
        self.clock = ContinuousClock()
        self.cacheTTL = cacheTTL
        self._pollingInterval = pollingInterval
        self._prefetchSecretNames = prefetchSecretNames

        let (initialValues, lastUpdatedAt) = try await Self.prefetchSecrets(prefetchSecretNames, vendor: vendor, clock: self.clock)
        self.storage = .init(Storage(
            snapshot: AWSSecretsManagerProviderSnapshot(values: initialValues),
            secretKeyObservers: [:],
            secretSnapshotObservers: [:],
            lastUpdatedAt: lastUpdatedAt
        ))
    }

    init(vendor: AWSSecretsManagerVendor, clock: C, prefetchSecretNames: [String] = [], pollingInterval: Duration? = nil, cacheTTL: Duration = .seconds(300)) async throws {
        self._vendor = vendor
        self.clock = clock
        self.cacheTTL = cacheTTL
        self._pollingInterval = pollingInterval
        self._prefetchSecretNames = prefetchSecretNames

        let (initialValues, lastUpdatedAt) = try await Self.prefetchSecrets(prefetchSecretNames, vendor: vendor, clock: clock)
        self.storage = .init(Storage(
            snapshot: AWSSecretsManagerProviderSnapshot(values: initialValues),
            secretKeyObservers: [:],
            secretSnapshotObservers: [:],
            lastUpdatedAt: lastUpdatedAt
        ))
    }

    // MARK: - Prefetch helper

    private static func prefetchSecrets(
        _ names: [String], vendor: AWSSecretsManagerVendor, clock: C
    ) async throws -> (values: [String: [String: Sendable]], timestamps: [String: C.Instant]) {
        try await withThrowingTaskGroup(of: (String, [String: Sendable]?, C.Instant?).self) { taskGroup in
            for name in names {
                taskGroup.addTask {
                    guard let secretValueLookup = try await vendor.fetchSecretValue(forKey: name) else {
                        return (name, nil, nil)
                    }
                    guard let secretLookupDict = try? JSONSerialization.jsonObject(with: Data(secretValueLookup.utf8), options: []) as? [String: Sendable] else {
                        return (name, nil, nil)
                    }
                    return (name, secretLookupDict, clock.now)
                }
            }

            var values: [String: [String: Sendable]] = [:]
            var timestamps: [String: C.Instant] = [:]
            for try await (name, dict, instant) in taskGroup {
                values[name] = dict
                timestamps[name] = instant
            }
            return (values, timestamps)
        }
    }

    // MARK: - Cache reload engine

    func reloadSecretIfNeeded(secretName: String, overrideCacheTTL: Bool = false) async throws {
        let (lastUpdatedAt, hasCachedValue) = storage.withLock { storage in
            (storage.lastUpdatedAt[secretName], storage.snapshot.values[secretName] != nil)
        }

        // Single lock read for both timestamp and cached-value presence to avoid a TOCTOU gap.
        if !overrideCacheTTL,
           let lastUpdatedAt,
           hasCachedValue,
           lastUpdatedAt.duration(to: clock.now) < cacheTTL {
            return
        }

        // Update lastUpdatedAt even on nil/non-JSON results so the TTL cooldown prevents repeated vendor calls.
        guard let secretValueLookup = try await _vendor.fetchSecretValue(forKey: secretName) else {
            storage.withLock { $0.lastUpdatedAt[secretName] = clock.now }
            return
        }

        guard let secretLookupDict = try? JSONSerialization.jsonObject(with: Data(secretValueLookup.utf8), options: []) as? [String: Sendable] else {
            storage.withLock { $0.lastUpdatedAt[secretName] = clock.now }
            return
        }

        let snapshots = storage.withLock { storage -> (old: AWSSecretsManagerProviderSnapshot, new: AWSSecretsManagerProviderSnapshot)? in
            if storage.lastUpdatedAt[secretName] != lastUpdatedAt {
                // Lost the race against another caller
                return nil
            }

            let oldSnapshot = storage.snapshot
            storage.snapshot.values[secretName] = secretLookupDict
            storage.lastUpdatedAt[secretName] = clock.now
            return (oldSnapshot, storage.snapshot)
        }

        guard let snapshots else { return }
        broadcastSecretChange(secretName: secretName, oldSnapshot: snapshots.old, newSnapshot: snapshots.new)
    }
}
