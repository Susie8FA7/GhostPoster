import Foundation

struct Guide01StatusMessage: Equatable {
    let title: String
    let content: String

    var displayText: String {
        "\(title)\n\(content)"
    }
}

enum Guide01StatusPresenter {
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
