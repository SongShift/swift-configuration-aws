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
#endif

public struct AWSSecretsManagerProvider: ConfigProvider {
    public var providerName: String {
        return _snapshot.providerName
    }
    
    /// A snapshot of the internal state.
    private let _snapshot: AWSSecretsManagerProviderSnapshot
    
    private let _vendor: AWSSecretsManagerVendor
    
    public init(vendor: AWSSecretsManagerVendor) {
        self._snapshot = AWSSecretsManagerProviderSnapshot()
        self._vendor = vendor
    }
    
    public func value(forKey key: Configuration.AbsoluteConfigKey, type: Configuration.ConfigType) throws -> Configuration.LookupResult {
        return try _snapshot.value(forKey: key, type: type)
    }
    
    public func fetchValue(forKey key: Configuration.AbsoluteConfigKey, type: Configuration.ConfigType) async throws -> Configuration.LookupResult {
        let encodedKey = SeparatorKeyEncoder.dotSeparated.encode(key)

        let lastTwoComponents = key.components.suffix(2)
        guard lastTwoComponents.count >= 2 else {
            return LookupResult(encodedKey: encodedKey, value: nil)
        }
        let keyName = lastTwoComponents[0]
        let fieldName = lastTwoComponents[1]
        
        guard let secretValue = try await _vendor.fetchSecretValue(forKey: keyName) else {
            return LookupResult(encodedKey: encodedKey, value: nil)
        }
        
        guard let secretLookupDict = try? JSONSerialization.jsonObject(with: Data(secretValue.utf8), options: []) as? [String: String], let secretValue = secretLookupDict[fieldName] else {
            return LookupResult(encodedKey: encodedKey, value: nil)
        }
        
        let resultConfigValue = ConfigValue(.string(secretValue), isSecret: true)
        _snapshot.cache.setValue(resultConfigValue, forKey: key)
        return LookupResult(encodedKey: encodedKey, value: ConfigValue(.string(secretValue), isSecret: true))
    }
    
    public func watchValue<Return>(forKey key: Configuration.AbsoluteConfigKey, type: Configuration.ConfigType, updatesHandler: (Configuration.ConfigUpdatesAsyncSequence<Result<Configuration.LookupResult, any Error>, Never>) async throws -> Return) async throws -> Return {
        try await watchValueFromValue(forKey: key, type: type, updatesHandler: updatesHandler)
    }
    
    public func watchSnapshot<Return>(updatesHandler: (ConfigUpdatesAsyncSequence<any ConfigSnapshotProtocol, Never>) async throws -> Return) async throws -> Return {
        try await watchSnapshotFromSnapshot(updatesHandler: updatesHandler)
    }
    
    public func snapshot() -> any Configuration.ConfigSnapshotProtocol {
        return _snapshot.cache.snapshot()
    }
}

public struct AWSSecretsManagerProviderSnapshot: ConfigSnapshotProtocol {
    public let providerName: String = "AWSSecretsManagerProvider"

    let cache: MutableInMemoryProvider

    public init() {
        self.cache = MutableInMemoryProvider(initialValues: [:])
    }

    public func value(forKey key: Configuration.AbsoluteConfigKey, type: Configuration.ConfigType) throws -> Configuration.LookupResult {
        return try cache.value(forKey: key, type: type)
    }
}
