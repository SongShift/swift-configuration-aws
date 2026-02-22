//
//  AWSSecretsManagerProviderSnapshot.swift
//  swift-configuration-aws
//
//  Created by Ben on 11/13/25.
//  Copyright © 2025 SongShift, LLC. All rights reserved.
//

import Configuration

public struct AWSSecretsManagerProviderSnapshot: ConfigSnapshot {
    public let providerName: String = "AWSSecretsManagerProvider"

    var values: [String: [String: Sendable]]
    
    public init(values: [String: [String: Sendable]]) {
        self.values = values
    }

    public func value(forKey key: Configuration.AbsoluteConfigKey, type: Configuration.ConfigType) throws -> Configuration.LookupResult {
        let encodedKey = key.description

        let keyComponents = key.components
        guard let secretName = keyComponents.first else {
            return LookupResult(encodedKey: encodedKey, value: nil)
        }

        let secretLookupDict = values[secretName]

        guard let content = extractConfigContent(from: secretLookupDict, keyComponents: key.components, type: type) else {
            return LookupResult(encodedKey: encodedKey, value: nil)
        }

        let resultConfigValue = ConfigValue(content, isSecret: true)
        return LookupResult(encodedKey: encodedKey, value: resultConfigValue)
    }
    
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

    private func convertToConfigContent(_ value: Sendable, type: ConfigType) -> ConfigContent? {
        switch type {
        case .string:
            guard let v = value as? String else { return nil }
            return .string(v)
        case .int:
            guard let v = value as? Int else { return nil }
            return .int(v)
        case .double:
            guard let v = value as? Double else { return nil }
            return .double(v)
        case .bool:
            guard let v = value as? Bool else { return nil }
            return .bool(v)
        case .bytes:
            guard let ints = value as? [Int] else { return nil }
            return .bytes(ints.map { UInt8($0) })
        case .stringArray:
            guard let v = value as? [String] else { return nil }
            return .stringArray(v)
        case .intArray:
            guard let v = value as? [Int] else { return nil }
            return .intArray(v)
        case .doubleArray:
            guard let v = value as? [Double] else { return nil }
            return .doubleArray(v)
        case .boolArray:
            guard let v = value as? [Bool] else { return nil }
            return .boolArray(v)
        case .byteChunkArray:
            guard let chunks = value as? [Any] else { return nil }
            var result: [[UInt8]] = []
            for chunk in chunks {
                guard let ints = chunk as? [Int] else { return nil }
                result.append(ints.map { UInt8($0) })
            }
            return .byteChunkArray(result)
        }
    }

    private func extractConfigContent(from dictionary: [String: Sendable]?, keyComponents: [String], type: ConfigType) -> ConfigContent? {
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

        return convertToConfigContent(secretValue, type: type)
    }
}
