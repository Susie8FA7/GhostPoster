import SwiftUI
#if DEBUG
import UIKit
#endif

struct SettingsView: View {
    @ObservedObject var settings: GhostSettings
    @State private var connectionState: ConnectionState = .idle
#if DEBUG
    @ObservedObject private var traceRecorder = GhostPosterTraceRecorder.shared
    @State private var traceExportFile: TraceExportFile?
    @State private var traceExportError: String?
#endif

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

#if DEBUG
            Section {
                Toggle(
                    "Traceを有効にする",
                    isOn: Binding(
                        get: { traceRecorder.isEnabled },
                        set: { traceRecorder.setEnabled($0) }
                    )
                )

                if traceRecorder.isEnabled {
                    LabeledContent(
                        "セッション",
                        value: "\(traceRecorder.document().sessions.count)"
                    )
                    LabeledContent(
                        "イベント",
                        value: "\(traceEventCount)"
                    )

                    NavigationLink("JSONプレビュー") {
                        TraceDebugView(recorder: traceRecorder)
                    }

                    Button {
                        prepareTraceExport()
                    } label: {
                        Label("Trace JSONを共有", systemImage: "square.and.arrow.up")
                    }
                    .disabled(traceRecorder.document().sessions.isEmpty)

                    Button("Traceを消去", role: .destructive) {
                        traceRecorder.clear()
                    }
                }
            } header: {
                Text("Trace Debug")
            } footer: {
                Text("Debugビルド限定です。本文、タイトル、URL、タグ、認証情報は記録しません。")
            }
#endif
        }
        .navigationTitle("Settings")
#if DEBUG
        .sheet(item: $traceExportFile) { file in
            TraceShareSheet(fileURL: file.url)
        }
        .alert(
            "Trace JSONを書き出せません",
            isPresented: Binding(
                get: { traceExportError != nil },
                set: { if !$0 { traceExportError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                traceExportError = nil
            }
        } message: {
            Text(traceExportError ?? "不明なエラーです。")
        }
#endif
    }

#if DEBUG
    private var traceEventCount: Int {
        traceRecorder.document().sessions.reduce(0) {
            $0 + $1.events.count
        }
    }

    private func prepareTraceExport() {
        do {
            let data = try traceRecorder.encodedDocument()
            let url = try GhostPosterTraceExporter.createFile(data: data)
            traceExportFile = TraceExportFile(url: url)
        } catch {
            traceExportError = error.localizedDescription
        }
    }
#endif

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

#if DEBUG
private struct TraceExportFile: Identifiable {
    let url: URL
    var id: URL { url }
}

private struct TraceShareSheet: UIViewControllerRepresentable {
    let fileURL: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(fileURL: fileURL)
    }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: [fileURL],
            applicationActivities: nil
        )
        controller.completionWithItemsHandler = { _, _, _, _ in
            context.coordinator.cleanup()
        }
        return controller
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}

    static func dismantleUIViewController(
        _ uiViewController: UIActivityViewController,
        coordinator: Coordinator
    ) {
        coordinator.cleanup()
    }

    final class Coordinator {
        private let fileURL: URL
        private var didCleanUp = false

        init(fileURL: URL) {
            self.fileURL = fileURL
        }

        func cleanup() {
            guard !didCleanUp else { return }
            didCleanUp = true
            GhostPosterTraceExporter.removeFile(at: fileURL)
        }
    }
}

private struct TraceDebugView: View {
    @ObservedObject var recorder: GhostPosterTraceRecorder

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            Text(recorder.formattedDocument())
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle("Trace JSON")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("消去", role: .destructive) {
                recorder.clear()
            }
        }
    }
}
#endif

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
