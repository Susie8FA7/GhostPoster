import Foundation

struct Guide01StatusMessage: Equatable {
    let title: String
    let content: String
    var fontSize: UInt8 = 32
    var showsStatusBar = true

    var displayText: String {
        "\(title)\n\(content)"
    }
}

enum Guide01StatusPresenter {
    static func scrollingMessages(
        for message: Guide01StatusMessage,
        charactersPerLine: Int = 18,
        visibleContentLines: Int = 4
    ) -> [Guide01StatusMessage] {
        guard charactersPerLine > 0, visibleContentLines > 0 else {
            return [message]
        }

        let lines = message.content
            .split(separator: "\n", omittingEmptySubsequences: false)
            .flatMap { line -> [String] in
                let characters = Array(line)
                guard !characters.isEmpty else { return [""] }
                return stride(from: 0, to: characters.count, by: charactersPerLine)
                    .map { start in
                        String(characters[start..<min(start + charactersPerLine, characters.count)])
                    }
            }

        guard lines.count > visibleContentLines else { return [message] }

        return (0...(lines.count - visibleContentLines)).map { start in
            Guide01StatusMessage(
                title: message.title,
                content: lines[start..<(start + visibleContentLines)]
                    .joined(separator: "\n"),
                fontSize: message.fontSize,
                showsStatusBar: message.showsStatusBar
            )
        }
    }

    static func readAloudMessage(
        title: String,
        body: String,
        hasReferenceURL: Bool,
        tags: [String]
    ) -> Guide01StatusMessage {
        let urlSummary = hasReferenceURL ? "参考URLあり" : "参考URLなし"
        let tagSummary = tags.isEmpty ? "なし" : tags.joined(separator: "、")

        return Guide01StatusMessage(
            title: "投稿内容",
            content: """
            タイトル
            \(title)
            本文
            \(body)
            \(urlSummary)
            タグ
            \(tagSummary)
            """,
            fontSize: 20,
            showsStatusBar: false
        )
    }

    static func message(for state: HandsFreeState) -> Guide01StatusMessage {
        switch state {
        case .idle:
            Guide01StatusMessage(
                title: "ハンズフリー投稿",
                content: "開始できます"
            )
        case .title:
            Guide01StatusMessage(
                title: "タイトル入力",
                content: "タイトルを話してください"
            )
        case .titleReview:
            Guide01StatusMessage(
                title: "タイトルを入力しました",
                content: "タイトルを確定、または修正"
            )
        case .body:
            Guide01StatusMessage(
                title: "本文入力",
                content: "本文を話してください"
            )
        case .bodyReview:
            Guide01StatusMessage(
                title: "本文を入力しました",
                content: "本文を追加、または確定"
            )
        case .referenceURL:
            Guide01StatusMessage(
                title: "参考URL入力",
                content: "参考URLを話す、またはなし"
            )
        case .referenceURLReview:
            Guide01StatusMessage(
                title: "参考URL",
                content: "参考URLを設定しました"
            )
        case .tags:
            Guide01StatusMessage(
                title: "タグ入力",
                content: "タグを話す、またはタグなし"
            )
        case .tagsReview:
            Guide01StatusMessage(
                title: "タグ",
                content: "タグを設定しました"
            )
        case .confirmation:
            Guide01StatusMessage(
                title: "最終確認",
                content: "投稿、読み上げ、またはキャンセル"
            )
        case .posting:
            Guide01StatusMessage(
                title: "GhostPoster",
                content: "Ghostへ保存しています"
            )
        case .completed:
            Guide01StatusMessage(
                title: "GhostPoster",
                content: "下書きを保存しました"
            )
        }
    }
}
