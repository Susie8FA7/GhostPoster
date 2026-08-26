import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: GhostSettings
    @State private var connectionState: ConnectionState = .idle

    var body: some View {
        Form {
            Section {
                TextField("Ghost URL", text: $settings.ghostURL)
#if os(iOS)
                    .textInputAutocapitalization(.never)
#endif
                    .autocorrectionDisabled()

                SecureField(
                    "Admin API Key",
                    text: $settings.adminAPIKey
                )
#if os(iOS)
                    .textInputAutocapitalization(.never)
#endif
                    .autocorrectionDisabled()
            } header: {
                Text("Ghost")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    if !settings.ghostURL.isEmpty &&
                        settings.validatedGhostURL == nil {
                        Text("有効なGhostサイトURLを入力してください。")
                            .foregroundStyle(.red)
                    }
                    if !settings.adminAPIKey.isEmpty &&
                        !settings.isAdminAPIKeyValid {
                        Text("Admin API Key は ID:SECRET の形式で入力してください。")
                            .foregroundStyle(.red)
                    }
                }
            }

            Section {
                TextField(
                    "Client ID",
                    text: $settings.cloudflareAccessClientID
                )
#if os(iOS)
                    .textInputAutocapitalization(.never)
#endif
                    .autocorrectionDisabled()

                SecureField(
                    "Client Secret",
                    text: $settings.cloudflareAccessClientSecret
                )
#if os(iOS)
                    .textInputAutocapitalization(.never)
#endif
                    .autocorrectionDisabled()
            } header: {
                Text("Cloudflare Access")
            } footer: {
                Text("Cloudflare Zero Trustで発行したService Tokenを入力します。")
            }

            Section {
                Button {
                    testConnection()
                } label: {
                    HStack {
                        Text("接続をテスト")
                        Spacer()
                        if connectionState.isTesting {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                .disabled(!canTestConnection)

                switch connectionState {
                case .idle:
                    LabeledContent("結果", value: "未実行")

                case .testing:
                    LabeledContent("結果", value: "接続中…")

                case .success(let siteTitle):
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("接続成功")
                            Text(siteTitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }

                case .failure(let message):
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("接続失敗")
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    } icon: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
            } header: {
                Text("Connection Test")
            } footer: {
                if !hasRequiredCredentials {
                    Text("Admin API KeyとCloudflare Accessの認証情報を入力してください。")
                }
            }

            Section("Third-Party Licenses") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("GUIDE01 SDK")
                        .font(.headline)
                    Text("Protocol library 2.0.0")
                    Text("Copyright 2026 HappyLifeCreators K.K.")
                    Text("Apache License 2.0")
                }
                .font(.footnote)
            }
        }
        .navigationTitle("Settings")
    }

    private var canTestConnection: Bool {
        hasRequiredCredentials && !connectionState.isTesting
    }

    private var hasRequiredCredentials: Bool {
        settings.validatedGhostURL != nil
            && settings.isAdminAPIKeyValid
            && settings.isCloudflareAccessConfigured
    }

    private func testConnection() {
        connectionState = .testing

        Task {
            do {
                guard let baseURL = settings.validatedGhostURL else {
                    return
                }
                let client = GhostClient(
                    baseURL: baseURL,
                    adminAPIKey: settings.adminAPIKey,
                    cloudflareAccessClientID: settings.cloudflareAccessClientID,
                    cloudflareAccessClientSecret: settings.cloudflareAccessClientSecret
                )
                let site = try await client.fetchSite()
                connectionState = .success(siteTitle: site.title)
            } catch {
                connectionState = .failure(
                    message: error.localizedDescription
                )
            }
        }
    }
}

private enum ConnectionState {
    case idle
    case testing
    case success(siteTitle: String)
    case failure(message: String)

    var isTesting: Bool {
        if case .testing = self {
            return true
        }
        return false
    }
}

#Preview {
    NavigationStack {
        SettingsView(settings: GhostSettings())
    }
}
