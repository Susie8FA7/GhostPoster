import Foundation

struct TranscriptChange: Equatable, Sendable {
    enum Scope: Equatable, Sendable {
        case title
        case body
        case tags
    }

    let scope: Scope
    let before: String
    let after: String

    var beforeSnippet: String {
        Self.snippet(for: before, comparedWith: after)
    }

    var afterSnippet: String {
        Self.snippet(for: after, comparedWith: before)
    }

    private static func snippet(
        for text: String,
        comparedWith other: String,
        context: Int = 6
    ) -> String {
        let characters = Array(text)
        let otherCharacters = Array(other)
        let sharedLimit = min(characters.count, otherCharacters.count)

        var prefixCount = 0
        while prefixCount < sharedLimit,
              characters[prefixCount] == otherCharacters[prefixCount] {
            prefixCount += 1
        }

        var suffixCount = 0
        while suffixCount < sharedLimit - prefixCount,
              characters[characters.count - suffixCount - 1]
                == otherCharacters[otherCharacters.count - suffixCount - 1] {
            suffixCount += 1
        }

        let start = max(0, prefixCount - context)
        let changedEnd = max(prefixCount, characters.count - suffixCount)
        let end = min(characters.count, changedEnd + context)
        let content = String(characters[start..<end])
        return (start > 0 ? "…" : "")
            + (content.isEmpty ? "（削除）" : content)
            + (end < characters.count ? "…" : "")
    }
}
