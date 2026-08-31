import Foundation
import Security

public struct LangfuseConfiguration: Equatable, Sendable {
    public let baseURL: URL
    public let publicKey: String
    public let secretKey: String

    public init(baseURL: URL, publicKey: String, secretKey: String) {
        self.baseURL = baseURL
        self.publicKey = publicKey
        self.secretKey = secretKey
    }
}

public enum LangfuseConfigurationError: LocalizedError, Equatable {
    case invalidBaseURL
    case missingBaseURL
    case missingPublicKey
    case missingSecretKey
    case cannotCreateApplicationSupportDirectory(String)
    case cannotReadConfiguration(String)
    case cannotWriteConfiguration(String)
    case keychainFailure(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            "Langfuse Base URLが正しくありません。"
        case .missingBaseURL:
            "Langfuse Base URLが未設定です。configureを実行してください。"
        case .missingPublicKey:
            "Langfuse Public Keyが未設定です。configureを実行してください。"
        case .missingSecretKey:
            "Langfuse Secret Keyが未設定です。configureを実行してください。"
        case .cannotCreateApplicationSupportDirectory(let message):
            "設定ディレクトリを作成できません: \(message)"
        case .cannotReadConfiguration(let message):
            "設定ファイルを読み込めません: \(message)"
        case .cannotWriteConfiguration(let message):
            "設定ファイルを保存できません: \(message)"
        case .keychainFailure(let status):
            "macOS Keychainの操作に失敗しました: \(status)"
        }
    }
}

public final class LangfuseConfigurationStore: @unchecked Sendable {
    public static let defaultBaseURL = URL(string: "https://jp.cloud.langfuse.com")!

    private struct StoredConfiguration: Codable {
        let baseURL: String
    }

    private enum KeychainAccount {
        static let publicKey = "langfuse-public-key"
        static let secretKey = "langfuse-secret-key"
    }

    private let configurationURL: URL
    private let keychainService: String

    public init(
        configurationURL: URL? = nil,
        keychainService: String = "app.ghostposter.trace-importer.langfuse"
    ) {
        if let configurationURL {
            self.configurationURL = configurationURL
        } else {
            let applicationSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!
            self.configurationURL = applicationSupport
                .appendingPathComponent("GhostPosterTraceImporter", isDirectory: true)
                .appendingPathComponent("config.json", isDirectory: false)
        }
        self.keychainService = keychainService
    }

    public func save(
        baseURL: URL,
        publicKey: String,
        secretKey: String
    ) throws {
        guard Self.isValidBaseURL(baseURL) else {
            throw LangfuseConfigurationError.invalidBaseURL
        }
        let directory = configurationURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        } catch {
            throw LangfuseConfigurationError
                .cannotCreateApplicationSupportDirectory(error.localizedDescription)
        }
        do {
            let data = try JSONEncoder().encode(
                StoredConfiguration(baseURL: baseURL.absoluteString)
            )
            try data.write(to: configurationURL, options: .atomic)
        } catch {
            throw LangfuseConfigurationError
                .cannotWriteConfiguration(error.localizedDescription)
        }
        try saveKeychain(publicKey, account: KeychainAccount.publicKey)
        try saveKeychain(secretKey, account: KeychainAccount.secretKey)
    }

    public func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> LangfuseConfiguration {
        let storedBaseURL = try readStoredBaseURL()
        let baseURLString = environment["LANGFUSE_BASE_URL"]
            ?? storedBaseURL?.absoluteString
        guard let baseURLString else {
            throw LangfuseConfigurationError.missingBaseURL
        }
        guard let baseURL = URL(string: baseURLString),
              Self.isValidBaseURL(baseURL) else {
            throw LangfuseConfigurationError.invalidBaseURL
        }

        let publicKey: String?
        if let environmentPublicKey = environment["LANGFUSE_PUBLIC_KEY"] {
            publicKey = environmentPublicKey
        } else {
            publicKey = try readKeychain(account: KeychainAccount.publicKey)
        }
        guard let publicKey, !publicKey.isEmpty else {
            throw LangfuseConfigurationError.missingPublicKey
        }
        let secretKey: String?
        if let environmentSecretKey = environment["LANGFUSE_SECRET_KEY"] {
            secretKey = environmentSecretKey
        } else {
            secretKey = try readKeychain(account: KeychainAccount.secretKey)
        }
        guard let secretKey, !secretKey.isEmpty else {
            throw LangfuseConfigurationError.missingSecretKey
        }
        return LangfuseConfiguration(
            baseURL: baseURL,
            publicKey: publicKey,
            secretKey: secretKey
        )
    }

    public func status() throws -> (baseURL: URL?, hasPublicKey: Bool, hasSecretKey: Bool) {
        (
            try readStoredBaseURL(),
            try readKeychain(account: KeychainAccount.publicKey) != nil,
            try readKeychain(account: KeychainAccount.secretKey) != nil
        )
    }

    public func clear() throws {
        try? FileManager.default.removeItem(at: configurationURL)
        try deleteKeychain(account: KeychainAccount.publicKey)
        try deleteKeychain(account: KeychainAccount.secretKey)
    }

    public static func isValidBaseURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil,
              url.user == nil,
              url.password == nil else { return false }
        return true
    }

    private func readStoredBaseURL() throws -> URL? {
        guard FileManager.default.fileExists(atPath: configurationURL.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: configurationURL)
            let stored = try JSONDecoder().decode(StoredConfiguration.self, from: data)
            return URL(string: stored.baseURL)
        } catch {
            throw LangfuseConfigurationError
                .cannotReadConfiguration(error.localizedDescription)
        }
    }

    private func saveKeychain(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let query = keychainQuery(account: account)
        SecItemDelete(query as CFDictionary)
        var insert = query
        insert[kSecValueData as String] = data
        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw LangfuseConfigurationError.keychainFailure(status)
        }
    }

    private func readKeychain(account: String) throws -> String? {
        var query = keychainQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw LangfuseConfigurationError.keychainFailure(status)
        }
        return value
    }

    private func deleteKeychain(account: String) throws {
        let status = SecItemDelete(keychainQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw LangfuseConfigurationError.keychainFailure(status)
        }
    }

    private func keychainQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account
        ]
    }
}
