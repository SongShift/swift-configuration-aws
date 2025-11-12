//
//  AWSSecretsManagerProvider.swift
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
import Synchronization
#endif

public final class AWSSecretsManagerProvider: ConfigProvider, Sendable {
    // MARK: - Struct Members
    
    /// A snapshot of the internal state.
    private let _snapshot: AWSSecretsManagerProviderSnapshot
    
    private let _vendor: AWSSecretsManagerVendor
    
    struct CachedResult {
        let lastUpdatedAt: TimeInterval
        let jsonObject: [String: Sendable]
    }
    
    struct Storage {
        var lastUpdatedAtMapping: [String: CachedResult]
    }
    
    private let _lastUpdatedAtMapping: Mutex<Storage>
    
    public init(vendor: AWSSecretsManagerVendor) {
        self._snapshot = AWSSecretsManagerProviderSnapshot()
        self._vendor = vendor
        self._lastUpdatedAtMapping = .init(Storage(lastUpdatedAtMapping: [:]))
    }
    
    public init(vendor: AWSSecretsManagerVendor, prefetchSecretNames: [String]) async throws {
        self._snapshot = AWSSecretsManagerProviderSnapshot()
        self._vendor = vendor
        self._lastUpdatedAtMapping = .init(Storage(lastUpdatedAtMapping: [:]))
        
        try await withThrowingDiscardingTaskGroup { taskGroup in
            for prefetchSecretName in prefetchSecretNames {
                taskGroup.addTask {
                    let _ = try await self.loadFromSecretsManagerIfNeeded(secretName: prefetchSecretName)
                }
            }
        }
    }
    
    // MARK: - ConfigProvider conformance
    
    public var providerName: String {
        return _snapshot.providerName
    }
    
    public func value(forKey key: Configuration.AbsoluteConfigKey, type: Configuration.ConfigType) throws -> Configuration.LookupResult {
        return try _snapshot.value(forKey: key, type: type)
    }
    
    public func fetchValue(forKey key: Configuration.AbsoluteConfigKey, type: Configuration.ConfigType) async throws -> Configuration.LookupResult {
        let encodedKey = SeparatorKeyEncoder.dotSeparated.encode(key)

        let keyComponents = key.components
        guard keyComponents.count >= 2 else {
            return LookupResult(encodedKey: encodedKey, value: nil)
        }
        let secretName = keyComponents[0]
        
        let secretLookupDict = try await loadFromSecretsManagerIfNeeded(secretName: secretName)

        guard let content = extractConfigContent(from: secretLookupDict, keyComponents: key.components) else {
            return LookupResult(encodedKey: encodedKey, value: nil)
        }

        let resultConfigValue = ConfigValue(content, isSecret: true)
        _snapshot.cache.setValue(resultConfigValue, forKey: key)
        return LookupResult(encodedKey: encodedKey, value: resultConfigValue)
    }
    
    public func watchValue<Return>(forKey key: Configuration.AbsoluteConfigKey, type: Configuration.ConfigType, updatesHandler: (Configuration.ConfigUpdatesAsyncSequence<Result<Configuration.LookupResult, any Error>, Never>) async throws -> Return) async throws -> Return {
        try await _snapshot.cache.watchValue(forKey: key, type: type, updatesHandler: updatesHandler)
    }
    
    public func watchSnapshot<Return>(updatesHandler: (ConfigUpdatesAsyncSequence<any ConfigSnapshotProtocol, Never>) async throws -> Return) async throws -> Return {
        try await _snapshot.cache.watchSnapshot(updatesHandler: updatesHandler)
    }
    
    public func snapshot() -> any Configuration.ConfigSnapshotProtocol {
        return _snapshot.cache.snapshot()
    }
    
    // MARK: Secret Manager Request
    private func loadFromSecretsManagerIfNeeded(secretName: String) async throws -> [String: Sendable]? {
        let cachedSecret = _lastUpdatedAtMapping.withLock({ storage in
            return storage.lastUpdatedAtMapping[secretName]
        })
        
        // Cache TTL, to be configurable
        if let cachedSecret, cachedSecret.lastUpdatedAt > Date().timeIntervalSince1970 - 300 {
            return cachedSecret.jsonObject
        }
        
        guard let secretValueLookup = try await _vendor.fetchSecretValue(forKey: secretName) else {
            return nil
        }
        
        guard let secretLookupDict = try? JSONSerialization.jsonObject(with: Data(secretValueLookup.utf8), options: []) as? [String: Sendable] else {
            return nil
        }
        
        _lastUpdatedAtMapping.withLock { storage in
            if storage.lastUpdatedAtMapping[secretName]?.lastUpdatedAt != cachedSecret?.lastUpdatedAt {
                // Lost the race against another caller, let's not update the cache
                return
            }
            storage.lastUpdatedAtMapping[secretName] = CachedResult(
                lastUpdatedAt: Date().timeIntervalSince1970,
                jsonObject: secretLookupDict
            )
        }

        return secretLookupDict
    }

    // MARK: - Helper Functions

    private func navigateNestedDictionary(_ dictionary: [String: Sendable], keyComponents: ArraySlice<String>) -> [String: Sendable]? {
        var currentDictionary = dictionary
        var remainingComponents = keyComponents

        while !remainingComponents.isEmpty {
            let currentComponent = remainingComponents.removeFirst()

            guard let nextValue = currentDictionary[currentComponent] else {
                return nil
            }

            if let nestedDict = nextValue as? [String: Sendable] {
                currentDictionary = nestedDict
            } else {
                // We've reached a non-dictionary value, return the current dictionary
                // This allows the caller to extract the final value
                return currentDictionary
            }
        }

        return currentDictionary
    }

    private func convertToConfigContent(_ value: Sendable) -> ConfigContent? {
        switch value {
        case let integer as Int:
            return .int(integer)
        case let intArray as [Int]:
            return .intArray(intArray)
        case let double as Double:
            return .double(double)
        case let doubleArray as [Double]:
            return .doubleArray(doubleArray)
        case let bool as Bool:
            return .bool(bool)
        case let boolArray as [Bool]:
            return .boolArray(boolArray)
        case let string as String:
            return .string(string)
        case let stringArray as [String]:
            return .stringArray(stringArray)
        default:
            return nil
        }
    }

    private func extractConfigContent(from dictionary: [String: Sendable]?, keyComponents: [String]) -> ConfigContent? {
        guard let dictionary = dictionary else {
            return nil
        }

        guard let finalDictionary = navigateNestedDictionary(dictionary, keyComponents: keyComponents.dropFirst()) else {
            return nil
        }

        guard let lastKeyComponent = keyComponents.last,
              let secretValue = finalDictionary[lastKeyComponent] else {
            return nil
        }

        return convertToConfigContent(secretValue)
    }
}

public struct AWSSecretsManagerProviderSnapshot: ConfigSnapshotProtocol {
    public let providerName: String = "AWSSecretsManagerProvider"

    // The idea to use this setup with MutableInMemoryProvider is inspired by this PR:
    // https://github.com/vault-courier/vault-courier/pull/57/files#diff-7d50e4a6948e257cb850e6051a78d5b2cc68851018c084712cccd2631921f032R155
    let cache: MutableInMemoryProvider

    public init() {
        self.cache = MutableInMemoryProvider(initialValues: [:])
    }

    public func value(forKey key: Configuration.AbsoluteConfigKey, type: Configuration.ConfigType) throws -> Configuration.LookupResult {
        return try cache.value(forKey: key, type: type)
    }
}
