import Foundation

/// Ghostの標準コンテンツ形式であるLexical JSONを生成します。
/// 各入力行を独立したparagraph nodeにすることで、Ghost側で改行が
/// 空白へ正規化されることを防ぎます。
enum GhostLexicalRenderer {
    static func render(
        _ text: String,
        bookmark: GhostBookmarkMetadata? = nil,
        referenceURL: URL? = nil
    ) throws -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).map(String.init)

        var nodes = lines.map { line in
            LexicalNode.paragraph(
                LexicalParagraph(
                    children: line.isEmpty ? [] : [LexicalText(text: line)]
                )
            )
        }
        if let referenceURL {
            nodes.append(
                .paragraph(
                    LexicalParagraph(
                        children: [LexicalText(text: "参考URL：")]
                    )
                )
            )
            if let bookmark {
                nodes.append(.bookmark(LexicalBookmark(bookmark)))
            } else {
                nodes.append(
                    .paragraph(
                        LexicalParagraph(
                            children: [LexicalText(text: referenceURL.absoluteString)]
                        )
                    )
                )
            }
        }
        let document = LexicalDocument(
            root: LexicalRoot(children: nodes)
        )
        let data = try JSONEncoder().encode(document)
        guard let lexical = String(data: data, encoding: .utf8) else {
            throw GhostLexicalRenderError.encodingFailed
        }
        return lexical
    }
}

private struct LexicalDocument: Encodable {
    let root: LexicalRoot
}

private struct LexicalRoot: Encodable {
    let children: [LexicalNode]
    let direction = "ltr"
    let format = ""
    let indent = 0
    let type = "root"
    let version = 1
}

private enum LexicalNode: Encodable {
    case paragraph(LexicalParagraph)
    case bookmark(LexicalBookmark)

    func encode(to encoder: Encoder) throws {
        switch self {
        case .paragraph(let paragraph):
            try paragraph.encode(to: encoder)
        case .bookmark(let bookmark):
            try bookmark.encode(to: encoder)
        }
    }
}

private struct LexicalParagraph: Encodable {
    let children: [LexicalText]
    let direction = "ltr"
    let format = ""
    let indent = 0
    let type = "paragraph"
    let version = 1
}

private struct LexicalText: Encodable {
    let detail = 0
    let format = 0
    let mode = "normal"
    let style = ""
    let text: String
    let type = "extended-text"
    let version = 1
}

/// GhostのBookmarkNode.exportJSON()と同じフィールド構造です。
private struct LexicalBookmark: Encodable {
    let type = "bookmark"
    let version = 1
    let url: String
    let metadata: Metadata
    let caption = ""

    init(_ bookmark: GhostBookmarkMetadata) {
        url = bookmark.url.absoluteString
        metadata = Metadata(
            icon: bookmark.icon,
            title: bookmark.title,
            description: bookmark.description,
            author: bookmark.author,
            publisher: bookmark.publisher,
            thumbnail: bookmark.thumbnail
        )
    }

    struct Metadata: Encodable {
        let icon: String
        let title: String
        let description: String
        let author: String
        let publisher: String
        let thumbnail: String
    }
}

enum GhostLexicalRenderError: LocalizedError {
    case encodingFailed

    var errorDescription: String? {
        "Ghost用の本文データを生成できませんでした。"
    }
}
