import Configuration
import Testing
@testable import ConfigurationAWS

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@Suite("Type Conversion")
struct TypeConversionTests {
    @Test func stringType() throws {
        let snapshot = AWSSecretsManagerProviderSnapshot(values: [
            "s": ["key": "hello"],
        ])
        let result = try snapshot.value(forKey: configKey("s.key"), type: .string)
        #expect(result.value?.content == .string("hello"))
        #expect(result.value?.isSecret == true)
    }

    @Test func intType() throws {
        let snapshot = AWSSecretsManagerProviderSnapshot(values: [
            "s": ["key": 42],
        ])
        let result = try snapshot.value(forKey: configKey("s.key"), type: .int)
        #expect(result.value?.content == .int(42))
    }

    @Test func doubleType() throws {
        let snapshot = AWSSecretsManagerProviderSnapshot(values: [
            "s": ["key": 3.14],
        ])
        let result = try snapshot.value(forKey: configKey("s.key"), type: .double)
        #expect(result.value?.content == .double(3.14))
    }

    @Test func boolType() throws {
        let snapshot = AWSSecretsManagerProviderSnapshot(values: [
            "s": ["key": true],
        ])
        let result = try snapshot.value(forKey: configKey("s.key"), type: .bool)
        #expect(result.value?.content == .bool(true))
    }

    @Test func bytesType() throws {
        let snapshot = AWSSecretsManagerProviderSnapshot(values: [
            "s": ["key": [109, 97, 103] as [Int]],
        ])
        let result = try snapshot.value(forKey: configKey("s.key"), type: .bytes)
        #expect(result.value?.content == .bytes([109, 97, 103]))
    }

    @Test func stringArrayType() throws {
        let snapshot = AWSSecretsManagerProviderSnapshot(values: [
            "s": ["key": ["a", "b"]],
        ])
        let result = try snapshot.value(forKey: configKey("s.key"), type: .stringArray)
        #expect(result.value?.content == .stringArray(["a", "b"]))
    }

    @Test func intArrayType() throws {
        let snapshot = AWSSecretsManagerProviderSnapshot(values: [
            "s": ["key": [1, 2, 3]],
        ])
        let result = try snapshot.value(forKey: configKey("s.key"), type: .intArray)
        #expect(result.value?.content == .intArray([1, 2, 3]))
    }

    @Test func doubleArrayType() throws {
        let snapshot = AWSSecretsManagerProviderSnapshot(values: [
            "s": ["key": [1.1, 2.2]],
        ])
        let result = try snapshot.value(forKey: configKey("s.key"), type: .doubleArray)
        #expect(result.value?.content == .doubleArray([1.1, 2.2]))
    }

    @Test func boolArrayType() throws {
        let snapshot = AWSSecretsManagerProviderSnapshot(values: [
            "s": ["key": [true, false]],
        ])
        let result = try snapshot.value(forKey: configKey("s.key"), type: .boolArray)
        #expect(result.value?.content == .boolArray([true, false]))
    }

    @Test func byteChunkArrayType() throws {
        // byteChunkArray comes from JSONSerialization which produces NSArray of NSArray
        // We need to test via the provider path to get realistic data
        let jsonString = #"{"key": [[109, 97], [103, 105]]}"#
        let dict = try #require(JSONSerialization
            .jsonObject(with: Data(jsonString.utf8)) as? [String: Sendable])
        let snapshot = AWSSecretsManagerProviderSnapshot(values: ["s": dict])
        let result = try snapshot.value(forKey: configKey("s.key"), type: .byteChunkArray)
        #expect(result.value?.content == .byteChunkArray([[109, 97], [103, 105]]))
    }

    @Test func typeMismatchReturnsNil() throws {
        let snapshot = AWSSecretsManagerProviderSnapshot(values: [
            "s": ["key": "hello"],
        ])
        let result = try snapshot.value(forKey: configKey("s.key"), type: .int)
        #expect(result.value == nil)
    }
}
