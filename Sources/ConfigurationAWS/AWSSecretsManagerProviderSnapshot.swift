//
//  AWSSecretsManagerProviderSnapshot.swift
//  swift-configuration-aws
//
//  Created by Ben on 11/13/25.
//  Copyright © 2025 SongShift, LLC. All rights reserved.
//

import Configuration
import ServiceLifecycle
import AsyncAlgorithms

public struct AWSSecretsManagerProviderSnapshot: ConfigSnapshotProtocol {
    public let providerName: String = "AWSSecretsManagerProvider"

    var values: [String: [String: Sendable]]
    
    public init(values: [String: [String: Sendable]]) {
        self.values = values
    }

    public func value(forKey key: Configuration.AbsoluteConfigKey, type: Configuration.ConfigType) throws -> Configuration.LookupResult {
        let encodedKey = SeparatorKeyEncoder.dotSeparated.encode(key)

        let keyComponents = key.components
        guard keyComponents.count >= 2 else {
            return LookupResult(encodedKey: encodedKey, value: nil)
        }
        let secretName = keyComponents[0]
        
        let secretLookupDict = values[secretName]

        guard let content = extractConfigContent(from: secretLookupDict, keyComponents: key.components) else {
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
