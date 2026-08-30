import Foundation

protocol TranscriptCorrecting {
    func correct(_ transcript: String) -> String
}

/// 音声認識結果を読み上げ確認しやすい文章へ整えます。
/// 外部の補正サービスを追加する場合は、この型を差し替えます。
struct JapaneseTranscriptCorrector: TranscriptCorrecting {
    func correct(_ transcript: String) -> String {
        let normalized = transcript
            .replacingOccurrences(of: "半角スペース", with: " ")
            .replacingOccurrences(of: "　", with: " ")
            .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+([、。！？])"#, with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return TranscriptCorrectionDictionary.apply(
            to: normalizeSpokenDates(in: normalized)
        )
    }

    private func normalizeSpokenDates(in text: String) -> String {
        let pattern = #"([0-9０-９]{4})年([0-9０-９]{1,2})月([0-9０-９]{1,2})日(?:日|月|火|水|木|金|土)曜日"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return text
        }

        var result = text
        let matches = expression.matches(
            in: text,
            range: NSRange(text.startIndex..., in: text)
        )
        for match in matches.reversed() {
            guard let wholeRange = Range(match.range(at: 0), in: result),
                  let year = number(in: result, range: match.range(at: 1)),
                  let month = number(in: result, range: match.range(at: 2)),
                  let day = number(in: result, range: match.range(at: 3)),
                  let date = Calendar(identifier: .gregorian).date(
                    from: DateComponents(year: year, month: month, day: day)
                  ) else { continue }

            let weekdaySymbols = ["日", "月", "火", "水", "木", "金", "土"]
            let weekday = Calendar(identifier: .gregorian).component(.weekday, from: date)
            let replacement = String(
                format: "%04d/%02d/%02d(%@)",
                year,
                month,
                day,
                weekdaySymbols[weekday - 1]
            )
            result.replaceSubrange(wholeRange, with: replacement)
        }
        return result
    }

    private func number(in text: String, range: NSRange) -> Int? {
        guard let range = Range(range, in: text) else { return nil }
        let normalized = String(text[range]).applyingTransform(
            .fullwidthToHalfwidth,
            reverse: false
        )
        return normalized.flatMap(Int.init)
    }
}
