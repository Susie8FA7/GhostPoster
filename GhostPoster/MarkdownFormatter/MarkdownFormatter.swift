import Foundation

enum MarkdownFormatter {
    /// ショートカット版と同じ形式の投稿データを生成します。
    ///
    /// 参考URLがある場合の本文末尾:
    ///
    /// ```text
    /// 本文
    ///
    /// 参考URL:
    /// https://example.com/article
    /// ```
    static func format(_ post: MarkdownPost) -> FormattedMarkdownPost {
        let title = post.title.trimmingCharacters(in: .whitespacesAndNewlines)
        var markdown = post.body.trimmingCharacters(in: .whitespacesAndNewlines)

        if let referenceURL = post.referenceURL {
            let reference = """
            参考URL：
            \(referenceURL.absoluteString)
            """

            markdown = markdown.isEmpty
                ? reference
                : "\(markdown)\n\n\(reference)"
        }

        return FormattedMarkdownPost(
            title: title,
            markdown: markdown
        )
    }

    /// クリップボードの文字列がHTTP(S) URLなら参考URLとして返します。
    static func referenceURL(from clipboardText: String?) -> URL? {
        guard let value = clipboardText?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            return nil
        }

        return url
    }
}
