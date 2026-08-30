import Foundation

/// Public, non-personal examples of terms whose canonical spelling matters.
/// Keep user-specific names and private vocabulary outside the repository.
enum TranscriptCorrectionDictionary {
    static let replacements: [String: String] = [
        "Appleインテリジェンス": "Apple Intelligence",
        "アップルインテリジェンス": "Apple Intelligence",
        "ゴーストポスター": "ゴーストポスター",
        "ゴースト": "Ghost",
        "ガイドゼロワン": "GUIDE01"
    ]

    static func apply(to transcript: String) -> String {
        let alternatives = replacements.keys
            .sorted { $0.count > $1.count }
            .map(NSRegularExpression.escapedPattern(for:))
            .joined(separator: "|")
        guard let expression = try? NSRegularExpression(pattern: alternatives) else {
            return transcript
        }

        var result = transcript
        let matches = expression.matches(
            in: transcript,
            range: NSRange(transcript.startIndex..., in: transcript)
        )
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let source = String(result[range])
            if let replacement = replacements[source] {
                result.replaceSubrange(range, with: replacement)
            }
        }
        return result
    }
}
