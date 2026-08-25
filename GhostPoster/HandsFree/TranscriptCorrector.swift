import Foundation

protocol TranscriptCorrecting {
    func correct(_ transcript: String) -> String
}

/// 音声認識結果を読み上げ確認しやすい文章へ整えます。
/// 外部の補正サービスを追加する場合は、この型を差し替えます。
struct JapaneseTranscriptCorrector: TranscriptCorrecting {
    func correct(_ transcript: String) -> String {
        transcript
            .replacingOccurrences(of: "半角スペース", with: " ")
            .replacingOccurrences(of: "　", with: " ")
            .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+([、。！？])"#, with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
