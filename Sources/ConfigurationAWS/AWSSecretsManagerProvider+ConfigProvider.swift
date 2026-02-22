//
//  AWSSecretsManagerProvider+ConfigProvider.swift
//  swift-configuration-aws
//
//  Created by Ben Rosen on 11/5/25.
//  Copyright © 2025 SongShift, LLC. All rights reserved.
//

import Configuration

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

// MARK: - ConfigProvider conformance
extension _AWSSecretsManagerProvider: ConfigProvider {

    public func value(forKey key: AbsoluteConfigKey, type: ConfigType) throws -> LookupResult {
        try storage.withLock { storage in
            try storage.snapshot.value(forKey: key, type: type)
        }
    }

    public func fetchValue(forKey key: AbsoluteConfigKey, type: ConfigType) async throws -> LookupResult {
        try await reloadSecretIfNeeded(secretName: key.components.first!)
        return try value(forKey: key, type: type)
    }

    public func snapshot() -> any ConfigSnapshot {
        storage.withLock { $0.snapshot }
    }

    // MARK: - Secret observation

    public func watchValue<Return: ~Copyable>(forKey key: AbsoluteConfigKey, type: ConfigType, updatesHandler: nonisolated(nonsending) (ConfigUpdatesAsyncSequence<Result<LookupResult, any Error>, Never>) async throws -> Return) async throws -> Return {
        let observerID = UUID()
        let secretUpdates = startObservingSecretKey(observerID: observerID, key: key, type: type)
        defer { stopObservingSecretKey(observerID: observerID, key: key) }
        return try await updatesHandler(.init(secretUpdates))
    }

    public func watchSnapshot<Return: ~Copyable>(updatesHandler: nonisolated(nonsending) (ConfigUpdatesAsyncSequence<any ConfigSnapshot, Never>) async throws -> Return) async throws -> Return {
        let observerID = UUID()
        let secretUpdates = startObservingSecrets(observerID: observerID)
        defer { stopObservingSecrets(observerID: observerID) }
        return try await updatesHandler(.init(secretUpdates.map { $0 }))
    }

    // MARK: - Observer lifecycle

    /// Registers an observer for a specific secret key path, yields the current value, and returns the update stream.
    private func startObservingSecretKey(observerID: UUID, key: AbsoluteConfigKey, type: ConfigType) -> AsyncStream<Result<LookupResult, any Error>> {
        let (stream, continuation) = AsyncStream<Result<LookupResult, any Error>>
            .makeStream(bufferingPolicy: .bufferingNewest(1))
        let currentResult = storage.withLock { storage in
            storage.secretKeyObservers[key, default: [:]][observerID] = continuation
            return Result { try storage.snapshot.value(forKey: key, type: type) }
        }
        continuation.yield(currentResult)
        return stream
    }

    /// Removes the observer and finishes its continuation to cleanly terminate the AsyncStream.
    private func stopObservingSecretKey(observerID: UUID, key: AbsoluteConfigKey) {
        storage.withLock {
            $0.secretKeyObservers[key, default: [:]]
                .removeValue(forKey: observerID)?.finish()
        }
    }

    /// Registers a snapshot observer, yields the current snapshot, and returns the update stream.
    private func startObservingSecrets(observerID: UUID) -> AsyncStream<AWSSecretsManagerProviderSnapshot> {
        let (stream, continuation) = AsyncStream<AWSSecretsManagerProviderSnapshot>
            .makeStream(bufferingPolicy: .bufferingNewest(1))
        let currentSnapshot = storage.withLock { storage in
            storage.secretSnapshotObservers[observerID] = continuation
            return storage.snapshot
        }
        continuation.yield(currentSnapshot)
        return stream
    }

    /// Removes the observer and finishes its continuation to cleanly terminate the AsyncStream.
    private func stopObservingSecrets(observerID: UUID) {
        storage.withLock { $0.secretSnapshotObservers.removeValue(forKey: observerID)?.finish() }
    }
}
