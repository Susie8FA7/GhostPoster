import Foundation
import Combine

@MainActor
final class GhostSettings: ObservableObject {
    private enum Keys {
        static let ghostURL = "ghostURL"
        static let adminAPIKey = "ghostAdminAPIKey"
        static let cloudflareAccessClientID = "cloudflareAccessClientID"
        static let cloudflareAccessClientSecret = "cloudflareAccessClientSecret"
    }

    @Published var ghostURL: String {
        didSet {
            guard ghostURL != oldValue else { return }
            try? KeychainStore.save(ghostURL, for: Keys.ghostURL)
        }
    }

    @Published var adminAPIKey: String {
        didSet {
            guard adminAPIKey != oldValue else { return }
            try? KeychainStore.save(adminAPIKey, for: Keys.adminAPIKey)
        }
    }

    @Published var cloudflareAccessClientID: String {
        didSet {
            guard cloudflareAccessClientID != oldValue else { return }
            try? KeychainStore.save(
                cloudflareAccessClientID,
                for: Keys.cloudflareAccessClientID
            )
        }
    }

    @Published var cloudflareAccessClientSecret: String {
        didSet {
            guard cloudflareAccessClientSecret != oldValue else { return }
            try? KeychainStore.save(
                cloudflareAccessClientSecret,
                for: Keys.cloudflareAccessClientSecret
            )
        }
    }

    init() {
        ghostURL = (try? KeychainStore.read(for: Keys.ghostURL)) ?? ""
        adminAPIKey = (try? KeychainStore.read(for: Keys.adminAPIKey)) ?? ""
        cloudflareAccessClientID = (
            try? KeychainStore.read(for: Keys.cloudflareAccessClientID)
        ) ?? ""
        cloudflareAccessClientSecret = (
            try? KeychainStore.read(for: Keys.cloudflareAccessClientSecret)
        ) ?? ""
    }

    var validatedGhostURL: URL? {
        let value = ghostURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            return nil
        }
        return url
    }

    var isAdminAPIKeyValid: Bool {
        let parts = adminAPIKey
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        return parts[0].count == 24 && parts[1].count == 64 && parts.allSatisfy {
            $0.allSatisfy(\.isHexDigit)
        }
    }

    var isCloudflareAccessConfigured: Bool {
        !cloudflareAccessClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !cloudflareAccessClientSecret.isEmpty
    }
}
