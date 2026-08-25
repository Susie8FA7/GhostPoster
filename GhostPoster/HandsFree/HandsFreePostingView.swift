import SwiftUI

struct HandsFreePostingView: View {
    @ObservedObject var settings: GhostSettings
    let startsAutomatically: Bool
    @StateObject private var session = HandsFreeSession()
    @StateObject private var guide01 = Guide01ConnectionManager()
    @State private var resultURL: URL?

    var body: some View {
        Form {
            Section {
                HStack {
                    Image(systemName: session.voiceInput.isRecording ? "waveform.circle.fill" : "waveform.circle")
                        .font(.title)
                        .foregroundStyle(session.voiceInput.isRecording ? Color.red : Color.accentColor)
                        .symbolEffect(.pulse, isActive: session.voiceInput.isRecording)
                    VStack(alignment: .leading) {
                        Text(stateLabel)
                            .font(.headline)
                        Text(session.statusMessage)
                            .font(.subheadline)
                    }
                }

                if session.state == .idle || session.state == .completed {
                    Button("ハンズフリー投稿を開始") {
                        resultURL = nil
                        session.start()
                    }
                } else if session.state != .posting {
                    Button("キャンセル", role: .destructive) {
                        session.cancel()
                    }
                }
            }

            Section("GUIDE01") {
                LabeledContent("接続", value: guide01.state.label)
                if case .failed(let message) = guide01.state {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if guide01.state.canRetry {
                    Button("GUIDE01へ再接続") {
                        guide01.retry()
                    }
                }
            }

            Section("認識内容") {
                LabeledContent("タイトル", value: session.title.isEmpty ? "—" : session.title)
                LabeledContent("本文", value: session.body.isEmpty ? "—" : session.body)
                LabeledContent("参考URL", value: session.referenceURL.isEmpty ? "なし" : session.referenceURL)
                LabeledContent("タグ", value: session.tags.isEmpty ? "なし" : session.tags.joined(separator: ", "))
            }

            Section("利用できる音声コマンド") {
                Text("「確定」「修正」「追加」「タイトルやり直し」「なし」「確認」「読み上げ」「投稿」「キャンセル」が使えます。全文は最終確認で「読み上げ」と言った時だけ読み上げます。")
                    .font(.footnote)
            }

            if let error = session.voiceInput.errorMessage {
                Section {
                    Text(error).foregroundStyle(.red)
                }
            }

            if let resultURL {
                Section {
                    Link("Ghostで下書きを開く", destination: resultURL)
                }
            }
        }
        .navigationTitle("ハンズフリー投稿")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: session.voiceInput.finalResult) { _, result in
            if let result { session.receive(result) }
        }
        .onChange(of: session.shouldPost) { _, shouldPost in
            if shouldPost { createDraft() }
        }
        .onChange(of: session.state) { _, state in
            guide01.display(Guide01StatusPresenter.message(for: state))
        }
        .onAppear {
            guide01.display(Guide01StatusPresenter.message(for: session.state))
            guide01.start()
            if startsAutomatically { session.start() }
        }
        .onDisappear {
            session.voiceInput.stop()
            guide01.stop()
        }
    }

    init(settings: GhostSettings, startsAutomatically: Bool = false) {
        self.settings = settings
        self.startsAutomatically = startsAutomatically
    }

    private var stateLabel: String {
        switch session.state {
        case .idle: "待機中"
        case .title: "タイトルを聞いています"
        case .titleReview: "タイトルを確認しています"
        case .body: "本文を聞いています"
        case .bodyReview: "本文を確認しています"
        case .referenceURL: "参考URLを聞いています"
        case .referenceURLReview: "参考URLを確認しています"
        case .tags: "タグを聞いています"
        case .tagsReview: "タグを確認しています"
        case .confirmation: "内容確認"
        case .posting: "投稿中"
        case .completed: "完了"
        }
    }

    private func createDraft() {
        guard let baseURL = settings.validatedGhostURL,
              settings.isAdminAPIKeyValid,
              settings.isCloudflareAccessConfigured else {
            session.postingFailed("SettingsでGhost接続情報を設定してください。")
            return
        }

        session.postingStarted()
        let title = session.title
        let tags = session.tags
        let markdown = MarkdownFormatter.format(
            MarkdownPost(
                title: title,
                body: session.body,
                referenceURL: MarkdownFormatter.referenceURL(from: session.referenceURL)
            )
        )

        Task {
            do {
                let referenceURL = MarkdownFormatter.referenceURL(
                    from: session.referenceURL
                )
                let bookmark: GhostBookmarkMetadata?
                if let referenceURL {
                    bookmark = await GhostBookmarkMetadataFetcher.fetch(for: referenceURL)
                } else {
                    bookmark = nil
                }
                let lexical = try GhostLexicalRenderer.render(
                    session.body,
                    bookmark: bookmark,
                    referenceURL: referenceURL
                )
                let client = GhostClient(
                    baseURL: baseURL,
                    adminAPIKey: settings.adminAPIKey,
                    cloudflareAccessClientID: settings.cloudflareAccessClientID,
                    cloudflareAccessClientSecret: settings.cloudflareAccessClientSecret
                )
                let created = try await client.createDraft(
                    title: markdown.title,
                    lexical: lexical,
                    tags: tags
                )
                resultURL = created.url.flatMap(URL.init(string:))
                session.postingFinished(title: created.title)
            } catch {
                session.postingFailed(error.localizedDescription)
            }
        }
    }
}
