import ConfigurationAWS

actor MockVendor: AWSSecretsManagerVendor {
    struct Call: Sendable {
        let key: String
    }

    private var secrets: [String: String]
    private let handler: (@Sendable (String) async throws -> String?)?
    private var _calls: [Call] = []

    var calls: [Call] { _calls }
    var callCount: Int { _calls.count }
    func callCount(forKey key: String) -> Int {
        _calls.filter { $0.key == key }.count
    }

    init(handler: @escaping @Sendable (String) async throws -> String?) {
        self.secrets = [:]
        self.handler = handler
    }

    init(secrets: [String: String] = [:]) {
        self.secrets = secrets
        self.handler = nil
    }

    func setSecret(_ key: String, value: String) {
        secrets[key] = value
    }

    func removeSecret(_ key: String) {
        secrets.removeValue(forKey: key)
    }

    private var errors: [String: any Error] = [:]

    func setError(_ error: any Error, forKey key: String) {
        errors[key] = error
    }

    func fetchSecretValue(forKey key: String) async throws -> String? {
        _calls.append(Call(key: key))
        if let handler {
            return try await handler(key)
        }
        if let error = errors[key] { throw error }
        return secrets[key]
    }
}
