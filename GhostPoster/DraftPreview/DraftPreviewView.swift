import SwiftUI
import UIKit
import PhotosUI

struct DraftPreviewView: View {
    @ObservedObject var settings: GhostSettings
    @StateObject private var voiceInput = VoiceInputManager()

    @State private var title = ""
    @State private var markdownBody = ""
    @State private var referenceURLText = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var featureImage: UIImage?
    @State private var featureImageJPEGData: Data?
    @State private var isLoadingPhoto = false
    @State private var activeVoiceField: VoiceField?
    @State private var voicePrefix = ""
    @State private var isPosting = false
    @State private var resultMessage: String?
    @State private var createdPostURL: URL?

    var body: some View {
        Form {
            Section {
                HStack(alignment: .firstTextBaseline) {
                    TextField("タイトル", text: $title, axis: .vertical)
                    VoiceInputButton(
                        isRecording: voiceInput.isRecording && activeVoiceField == .title
                    ) {
                        toggleVoiceInput(for: .title)
                    }
                }

                VStack(alignment: .trailing) {
                    TextEditor(text: $markdownBody)
                        .frame(minHeight: 220)
                    VoiceInputButton(
                        isRecording: voiceInput.isRecording && activeVoiceField == .body
                    ) {
                        toggleVoiceInput(for: .body)
                    }
                }

                TextField("参考URL（任意）", text: $referenceURLText)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()

                Button("クリップボードからURLを取得") {
                    if let url = MarkdownFormatter.referenceURL(
                        from: UIPasteboard.general.string
                    ) {
                        referenceURLText = url.absoluteString
                    }
                }

                if let errorMessage = voiceInput.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("投稿内容")
            }

            Section {
                if let previewImage = featureImage {
                    Image(uiImage: previewImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    Button("画像を取り除く", role: .destructive) {
                        selectedPhoto = nil
                        featureImage = nil
                        featureImageJPEGData = nil
                    }
                }

                PhotosPicker(
                    selection: $selectedPhoto,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Label(
                        featureImage == nil ? "写真を選択" : "写真を変更",
                        systemImage: "photo.on.rectangle"
                    )
                }

                if isLoadingPhoto {
                    HStack {
                        ProgressView()
                        Text("写真を読み込み中…")
                    }
                }
            } header: {
                Text("Feature Image")
            } footer: {
                Text("選択した写真はJPEGへ変換し、下書き作成時にGhostへアップロードします。")
            }

            Section {
                Text(formattedPost.markdown.isEmpty ? "本文なし" : formattedPost.markdown)
                    .textSelection(.enabled)
            } header: {
                Text("Markdown Preview")
            }

            Section {
                Button {
                    createDraft()
                } label: {
                    HStack {
                        Text("Ghostに下書きを作成")
                        Spacer()
                        if isPosting {
                            ProgressView().controlSize(.small)
                        }
                    }
                }
                .disabled(!canPost)

                if let resultMessage {
                    Text(resultMessage)
                        .foregroundStyle(createdPostURL == nil ? .red : .green)
                        .textSelection(.enabled)
                }

                if let createdPostURL {
                    Link("Ghostで下書きを開く", destination: createdPostURL)
                }
            } footer: {
                Text("この操作は公開せず、Ghostへstatus=draftで保存します。")
            }
        }
        .navigationTitle("Draft Preview")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: voiceInput.transcript) { _, newValue in
            applyTranscript(newValue)
        }
        .onChange(of: selectedPhoto) { _, newValue in
            loadPhoto(newValue)
        }
        .onDisappear {
            voiceInput.stop()
        }
    }

    private var formattedPost: FormattedMarkdownPost {
        MarkdownFormatter.format(
            MarkdownPost(
                title: title,
                body: markdownBody,
                referenceURL: MarkdownFormatter.referenceURL(from: referenceURLText)
            )
        )
    }

    private var canPost: Bool {
        !formattedPost.title.isEmpty
            && !isPosting
            && !isLoadingPhoto
            && settings.validatedGhostURL != nil
            && settings.isAdminAPIKeyValid
            && settings.isCloudflareAccessConfigured
    }

    private func toggleVoiceInput(for field: VoiceField) {
        if voiceInput.isRecording {
            voiceInput.stop()
            activeVoiceField = nil
            return
        }
        activeVoiceField = field
        voicePrefix = field == .title ? title : markdownBody
        voiceInput.start()
    }

    private func applyTranscript(_ transcript: String) {
        guard let activeVoiceField, !transcript.isEmpty else { return }
        let separator = voicePrefix.isEmpty ? "" : (activeVoiceField == .title ? " " : "\n")
        let combined = voicePrefix + separator + transcript
        if activeVoiceField == .title {
            title = combined
        } else {
            markdownBody = combined
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        isLoadingPhoto = true
        resultMessage = nil

        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let originalImage = UIImage(data: data) else {
                    throw FeatureImageError.loadFailed
                }

                let image = resizeForFeatureImage(originalImage)
                guard let jpegData = image.jpegData(compressionQuality: 0.9) else {
                    throw FeatureImageError.loadFailed
                }

                featureImage = image
                featureImageJPEGData = jpegData
            } catch {
                selectedPhoto = nil
                featureImage = nil
                featureImageJPEGData = nil
                resultMessage = error.localizedDescription
            }
            isLoadingPhoto = false
        }
    }

    /// 短辺が1000pxを超える場合だけ、縦横比を保って縮小します。
    /// 小さい画像を拡大することはありません。
    private func resizeForFeatureImage(_ image: UIImage) -> UIImage {
        let pixelWidth = CGFloat(image.cgImage?.width ?? Int(image.size.width * image.scale))
        let pixelHeight = CGFloat(image.cgImage?.height ?? Int(image.size.height * image.scale))
        let shortSide = min(pixelWidth, pixelHeight)

        guard shortSide > 1_000 else {
            return image
        }

        let ratio = 1_000 / shortSide
        let targetSize = CGSize(
            width: (pixelWidth * ratio).rounded(),
            height: (pixelHeight * ratio).rounded()
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(
            size: targetSize,
            format: format
        ).image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    private func createDraft() {
        voiceInput.stop()
        isPosting = true
        resultMessage = nil
        createdPostURL = nil
        let post = formattedPost

        Task {
            do {
                guard let baseURL = settings.validatedGhostURL else {
                    throw GhostError.invalidURL
                }
                let referenceURL = MarkdownFormatter.referenceURL(
                    from: referenceURLText
                )
                let bookmark: GhostBookmarkMetadata?
                if let referenceURL {
                    bookmark = await GhostBookmarkMetadataFetcher.fetch(for: referenceURL)
                } else {
                    bookmark = nil
                }
                let lexical = try GhostLexicalRenderer.render(
                    markdownBody,
                    bookmark: bookmark,
                    referenceURL: referenceURL
                )
                let client = GhostClient(
                    baseURL: baseURL,
                    adminAPIKey: settings.adminAPIKey,
                    cloudflareAccessClientID: settings.cloudflareAccessClientID,
                    cloudflareAccessClientSecret: settings.cloudflareAccessClientSecret
                )
                let featureImageURL: String?
                if let featureImageJPEGData {
                    featureImageURL = try await client.uploadFeatureImage(
                        jpegData: featureImageJPEGData
                    ).url
                } else {
                    featureImageURL = nil
                }
                let created = try await client.createDraft(
                    title: post.title,
                    lexical: lexical,
                    featureImageURL: featureImageURL,
                    tags: []
                )
                createdPostURL = created.url.flatMap { URL(string: $0) }
                resultMessage = "下書きを作成しました: \(created.title)"
            } catch {
                resultMessage = error.localizedDescription
            }
            isPosting = false
        }
    }
}

private enum FeatureImageError: LocalizedError {
    case loadFailed

    var errorDescription: String? {
        "選択した写真を読み込めませんでした。"
    }
}

private enum VoiceField {
    case title
    case body
}
