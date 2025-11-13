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

public final class AWSSecretsManagerProvider: ConfigProvider, Sendable {
    private let _vendor: AWSSecretsManagerVendor
    
    
    struct Storage {
        var snapshot: AWSSecretsManagerProviderSnapshot
        
        // Taken from https://github.com/apple/swift-configuration/blob/0.2.0/Sources/Configuration/Providers/Common/ReloadingFileProviderCore.swift
        var valueWatchers: [AbsoluteConfigKey: [UUID: AsyncStream<Result<LookupResult, any Error>>.Continuation]]
        var snapshotWatchers: [UUID: AsyncStream<AWSSecretsManagerProviderSnapshot>.Continuation]

        var lastUpdatedAt: [String: TimeInterval]
    }
    
    private let storage: Mutex<Storage>
        
    let _pollingInterval: Duration?
    let _prefetchSecretNames: [String]
    
    public init(vendor: AWSSecretsManagerVendor) {
        self._vendor = vendor
        self.storage = .init(Storage(
            snapshot: AWSSecretsManagerProviderSnapshot(values: [:]),
            valueWatchers: [:],
            snapshotWatchers: [:],
            lastUpdatedAt: [:]
        ))
        self._prefetchSecretNames = []
        self._pollingInterval = nil
    }
    
    public init(vendor: AWSSecretsManagerVendor, prefetchSecretNames: [String], pollingInterval: Duration? = nil) async throws {
        self._vendor = vendor
        self._pollingInterval = pollingInterval
        self._prefetchSecretNames = prefetchSecretNames
        
        let (initialValues, lastUpdatedAt) = try await withThrowingTaskGroup(of: (String, [String: Sendable]?, TimeInterval?).self) { taskGroup in
            for prefetchSecretName in prefetchSecretNames {
                taskGroup.addTask {
                    guard let secretValueLookup = try await vendor.fetchSecretValue(forKey: prefetchSecretName) else {
                        return (prefetchSecretName, nil, nil)
                    }
                    
                    guard let secretLookupDict = try? JSONSerialization.jsonObject(with: Data(secretValueLookup.utf8), options: []) as? [String: Sendable] else {
                        return (prefetchSecretName, nil, nil)
                    }
                    return (prefetchSecretName, secretLookupDict, Date().timeIntervalSince1970)
                }
            }
            
            var initialValues: [String: [String: Sendable]] = [:]
            var lastUpdatedAt: [String: TimeInterval] = [:]
            for try await result in taskGroup {
                initialValues[result.0] = result.1
                lastUpdatedAt[result.0] = result.2
            }
            return (initialValues, lastUpdatedAt)
        }
        
        self.storage = .init(Storage(
            snapshot: AWSSecretsManagerProviderSnapshot(values: initialValues),
            valueWatchers: [:],
            snapshotWatchers: [:],
            lastUpdatedAt: lastUpdatedAt
        ))
    }
    
    // MARK: - ConfigProvider conformance
    
    public let providerName: String = "AWSSecretsManagerProvider"
    
    public func value(forKey key: Configuration.AbsoluteConfigKey, type: Configuration.ConfigType) throws -> Configuration.LookupResult {
        try storage.withLock { storage in
            try storage.snapshot.value(forKey: key, type: type)
        }
    }
    
    public func fetchValue(forKey key: Configuration.AbsoluteConfigKey, type: Configuration.ConfigType) async throws -> Configuration.LookupResult {
        
        try await reloadSecretIfNeeded(secretName: key.components.first!)
        return try value(forKey: key, type: type)
    }
    
    func reloadSecretIfNeeded(secretName: String, overrideCacheTTL: Bool = false) async throws {
        let (cachedSecret, lastUpdatedAt) = storage.withLock({ storage in
            let cachedSecret = storage.snapshot.values[secretName]
            let lastUpdatedAt = storage.lastUpdatedAt[secretName]
            return (cachedSecret, lastUpdatedAt)
        })
        
        // Cache TTL, to be configurable
        if !overrideCacheTTL, let _ = cachedSecret, let lastUpdatedAt, lastUpdatedAt > Date().timeIntervalSince1970 - 300 {
            return
        }
        
        guard let secretValueLookup = try await _vendor.fetchSecretValue(forKey: secretName) else {
            return
        }
        
        guard let secretLookupDict = try? JSONSerialization.jsonObject(with: Data(secretValueLookup.utf8), options: []) as? [String: Sendable] else {
            return
        }
        
        // Taken from https://github.com/apple/swift-configuration/blob/0.2.0/Sources/Configuration/Providers/Common/ReloadingFileProviderCore.swift
        typealias ValueWatchers = [(
            AbsoluteConfigKey,
            Result<LookupResult, any Error>,
            [AsyncStream<Result<LookupResult, any Error>>.Continuation]
        )]
        typealias SnapshotWatchers = (AWSSecretsManagerProviderSnapshot, [AsyncStream<AWSSecretsManagerProviderSnapshot>.Continuation])
        guard
            let (valueWatchersToNotify, snapshotWatchersToNotify) =
                storage
                .withLock({ storage -> (ValueWatchers, SnapshotWatchers)? in
                    if storage.lastUpdatedAt[secretName] != lastUpdatedAt {
                        // Lost the race against another caller, let's not update the cache
                        return nil
                    }
                    
                    let oldSnapshot = storage.snapshot
                    storage.snapshot.values[secretName] = secretLookupDict
                    storage.lastUpdatedAt[secretName] = Date().timeIntervalSince1970
                    
        
                    // Taken from https://github.com/apple/swift-configuration/blob/0.2.0/Sources/Configuration/Providers/Common/ReloadingFileProviderCore.swift
                    let valueWatchers = storage.valueWatchers.compactMap {
                        (key, watchers) -> (
                            AbsoluteConfigKey,
                            Result<LookupResult, any Error>,
                            [AsyncStream<Result<LookupResult, any Error>>.Continuation]
                        )? in
                        guard !watchers.isEmpty else { return nil }

                        // Get old and new values for this key
                        let oldValue = Result { try oldSnapshot.value(forKey: key, type: .string) }
                        let newValue = Result { try storage.snapshot.value(forKey: key, type: .string) }

                        let didChange =
                            switch (oldValue, newValue) {
                            case (.success(let lhs), .success(let rhs)):
                                lhs != rhs
                            case (.failure, .failure):
                                false
                            default:
                                true
                            }

                        // Only notify if the value changed
                        guard didChange else {
                            return nil
                        }
                        return (key, newValue, Array(watchers.values))
                    }

                    let snapshotWatchers = (storage.snapshot, Array(storage.snapshotWatchers.values))
                    return (valueWatchers, snapshotWatchers)
                
        }) else {
            return
        }
        // Taken from https://github.com/apple/swift-configuration/blob/0.2.0/Sources/Configuration/Providers/Common/ReloadingFileProviderCore.swift
        
        // Notify value watchers
        for (_, valueUpdate, watchers) in valueWatchersToNotify {
            for watcher in watchers {
                watcher.yield(valueUpdate)
            }
        }

        // Notify snapshot watchers
        for watcher in snapshotWatchersToNotify.1 {
            watcher.yield(snapshotWatchersToNotify.0)
        }
    }
    
    // This is taken from https://github.com/apple/swift-configuration/blob/0.2.0/Sources/Configuration/Providers/Common/ReloadingFileProviderCore.swift
    public func watchValue<Return>(forKey key: Configuration.AbsoluteConfigKey, type: Configuration.ConfigType, updatesHandler: (Configuration.ConfigUpdatesAsyncSequence<Result<Configuration.LookupResult, any Error>, Never>) async throws -> Return) async throws -> Return {

        let (stream, continuation) = AsyncStream<Result<LookupResult, any Error>>
            .makeStream(bufferingPolicy: .bufferingNewest(1))
        let id = UUID()

        // Add watcher and get initial value
        let initialValue: Result<LookupResult, any Error> = storage.withLock { storage in
            storage.valueWatchers[key, default: [:]][id] = continuation
            return .init {
                try storage.snapshot.value(forKey: key, type: type)
            }
        }
        defer {
            storage.withLock { storage in
                storage.valueWatchers[key, default: [:]][id] = nil
            }
        }

        // Send initial value
        continuation.yield(initialValue)
        return try await updatesHandler(.init(stream))

    }
    
    // This is taken from https://github.com/apple/swift-configuration/blob/0.2.0/Sources/Configuration/Providers/Common/ReloadingFileProviderCore.swift
    public func watchSnapshot<Return>(updatesHandler: (ConfigUpdatesAsyncSequence<any ConfigSnapshotProtocol, Never>) async throws -> Return) async throws -> Return {
        let (stream, continuation) = AsyncStream<AWSSecretsManagerProviderSnapshot>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let id = UUID()

        // Add watcher and get initial snapshot
        let initialSnapshot = storage.withLock { storage in
            storage.snapshotWatchers[id] = continuation
            return storage.snapshot
        }
        defer {
            // Clean up watcher
            storage.withLock { storage in
                storage.snapshotWatchers[id] = nil
            }
        }

        // Send initial snapshot
        continuation.yield(initialSnapshot)
        return try await updatesHandler(.init(stream.map { $0 }))
    }
    
    public func snapshot() -> any Configuration.ConfigSnapshotProtocol {
        storage.withLock { $0.snapshot }
    }
}
