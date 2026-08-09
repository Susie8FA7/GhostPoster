import Foundation

/// 入力画面からMarkdownFormatterへ渡す値です。
struct MarkdownPost: Sendable, Equatable {
    let title: String
    let body: String
    let referenceURL: URL?

    init(
        title: String,
        body: String,
        referenceURL: URL? = nil
    ) {
        self.title = title
        self.body = body
        self.referenceURL = referenceURL
    }
}

/// DraftPreviewとGhostClientへ渡す完成形です。
struct FormattedMarkdownPost: Sendable, Equatable {
    let title: String
    let markdown: String
}
