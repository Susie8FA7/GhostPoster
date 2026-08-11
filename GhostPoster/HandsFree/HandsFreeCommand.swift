import Foundation

enum HandsFreeCommand: Equatable {
    case addBody
    case redoTitle
    case accept
    case revise
    case readAloud
    case noURL
    case confirm
    case post
    case cancel

    init?(transcript: String) {
        let value = transcript
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "。", with: "")
            .replacingOccurrences(of: "、", with: "")
            .replacingOccurrences(of: " ", with: "")

        switch value {
        case "本文追加", "追加": self = .addBody
        case "タイトルやり直し", "タイトルをやり直し": self = .redoTitle
        case "確定": self = .accept
        case "修正", "やり直し": self = .revise
        case "読み上げ": self = .readAloud
        case "URLなし", "ユーアールエルなし", "なし": self = .noURL
        case "確認": self = .confirm
        case "投稿": self = .post
        case "キャンセル": self = .cancel
        default: return nil
        }
    }
}

enum HandsFreeState: String, CaseIterable {
    case idle
    case title
    case titleReview
    case body
    case bodyReview
    case referenceURL
    case referenceURLReview
    case tags
    case tagsReview
    case confirmation
    case posting
    case completed
}
