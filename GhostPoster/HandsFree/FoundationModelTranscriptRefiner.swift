import Foundation
import FoundationModels

struct TranscriptRefinement: Equatable, Sendable {
    let text: String
    let wasRefined: Bool
}

@MainActor
protocol TranscriptRefining {
    func prewarm()
    func refine(_ transcript: String) async -> TranscriptRefinement
}

@MainActor
final class FoundationModelTranscriptRefiner: TranscriptRefining {
    private let model = SystemLanguageModel.default
    private lazy var session = LanguageModelSession(
        model: model,
        instructions: """
        あなたは日本語音声認識結果の校正器です。
        前後の文脈を読み、音声認識に由来する同音異義語、漢字変換、固有名詞、表記揺れを修正してください。
        文脈からほぼ確実に判断できる短い語の欠落は補ってかまいません。
        意味、文体、語調、情報量、改行は変更しません。
        要約、加筆、言い換え、表現改善はしません。
        YYYY/MM/DD(曜)形式の日付は変更しません。
        スポーツの記事では「勝敗」「3タテ」「マジック点灯」など、文脈に合う通常の表現を使います。
        マジックナンバーは文脈に応じて「M21」のように表記します。
        文脈から判断できない箇所だけ原文を維持してください。
        """
    )

    func prewarm() {
        guard model.isAvailable else { return }
        session.prewarm()
    }

    func refine(_ transcript: String) async -> TranscriptRefinement {
        let fallback = TranscriptRefinement(text: transcript, wasRefined: false)
        guard model.isAvailable else { return fallback }

        do {
            let response = try await session.respond(
                to: """
                次の音声認識結果を、意味や文体を維持したまま文脈に沿って校正してください。
                説明や引用符を付けず、校正後の文章だけを返してください。

                \(transcript)
                """
            )
            let candidate = response.content
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            guard Self.isConservativeCorrection(candidate, of: transcript) else {
                return fallback
            }
            return TranscriptRefinement(
                text: candidate,
                wasRefined: candidate != transcript
            )
        } catch {
            return fallback
        }
    }

    static func isConservativeCorrection(
        _ candidate: String,
        of original: String
    ) -> Bool {
        guard !candidate.isEmpty else { return false }
        guard candidate.filter({ $0 == "\n" }).count
                == original.filter({ $0 == "\n" }).count else { return false }

        let originalCount = max(original.count, 1)
        let ratio = Double(candidate.count) / Double(originalCount)
        guard (0.75...1.25).contains(ratio) else { return false }

        return digitRuns(in: candidate) == digitRuns(in: original)
    }

    private static func digitRuns(in text: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: #"[0-9０-９]+"#) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        return expression.matches(in: text, range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: text) else { return nil }
            return String(text[swiftRange])
        }
    }
}
