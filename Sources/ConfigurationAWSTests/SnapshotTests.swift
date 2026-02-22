import Configuration
import Testing
@testable import ConfigurationAWS

@Suite("AWSSecretsManagerProviderSnapshot")
struct SnapshotTests {
    @Test func singleComponentKey() throws {
        // Key ["secret"] with JSON {"secret": "val"} — last component == secret name
        let snapshot = AWSSecretsManagerProviderSnapshot(values: [
            "secret": ["secret": "val"],
        ])
        let result = try snapshot.value(forKey: configKey("secret"), type: .string)
        #expect(result.value?.content == .string("val"))
    }

    @Test func twoComponentKey() throws {
        let snapshot = AWSSecretsManagerProviderSnapshot(values: [
            "mySecret": ["field": "hello"],
        ])
        let result = try snapshot.value(forKey: configKey("mySecret.field"), type: .string)
        #expect(result.value?.content == .string("hello"))
    }

    @Test func deeplyNestedKey() throws {
        let snapshot = AWSSecretsManagerProviderSnapshot(values: [
            "root": ["a": ["b": ["c": "deep"]] as [String: Sendable]] as [String: Sendable],
        ])
        let result = try snapshot.value(forKey: configKey("root.a.b.c"), type: .string)
        #expect(result.value?.content == .string("deep"))
    }

    @Test func missingSecretReturnsNil() throws {
        let snapshot = AWSSecretsManagerProviderSnapshot(values: [:])
        let result = try snapshot.value(forKey: configKey("nonexistent.field"), type: .string)
        #expect(result.value == nil)
    }

    @Test func missingIntermediateKeyReturnsNil() throws {
        let snapshot = AWSSecretsManagerProviderSnapshot(values: [
            "secret": ["a": "value"],
        ])
        let result = try snapshot.value(forKey: configKey("secret.missing.field"), type: .string)
        #expect(result.value == nil)
    }

    @Test func emptyKeyComponentsReturnsNil() throws {
        let snapshot = AWSSecretsManagerProviderSnapshot(values: [
            "secret": ["field": "value"],
        ])
        let result = try snapshot.value(forKey: AbsoluteConfigKey([]), type: .string)
        #expect(result.value == nil)
    }

    @Test func encodedKeyMatchesKeyDescription() throws {
        let key = configKey("mySecret.field")
        let snapshot = AWSSecretsManagerProviderSnapshot(values: [
            "mySecret": ["field": "hello"],
        ])
        let result = try snapshot.value(forKey: key, type: .string)
        #expect(result.encodedKey == key.description)
    }

    @Test func providerNameIsCorrect() {
        let snapshot = AWSSecretsManagerProviderSnapshot(values: [:])
        #expect(snapshot.providerName == "AWSSecretsManagerProvider")
    }

    @Test func snapshotIsValueType() throws {
        var original = AWSSecretsManagerProviderSnapshot(values: [
            "s": ["f": "original"],
        ])
        let copy = original
        original.values["s"] = ["f": "mutated"]

        let copyResult = try copy.value(forKey: configKey("s.f"), type: .string)
        #expect(copyResult.value?.content == .string("original"))

        let originalResult = try original.value(forKey: configKey("s.f"), type: .string)
        #expect(originalResult.value?.content == .string("mutated"))
    }
}
