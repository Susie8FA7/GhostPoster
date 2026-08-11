import Foundation

struct GhostBookmarkMetadata: Sendable {
    let url: URL
    let icon: String
    let title: String
    let description: String
    let author: String
    let publisher: String
    let thumbnail: String

    static func fallback(for url: URL) -> Self {
        let publisher = url.host ?? url.absoluteString
        return Self(
            url: url,
            icon: "",
            title: publisher,
            description: "",
            author: "",
            publisher: publisher,
            thumbnail: ""
        )
    }
}

enum GhostBookmarkMetadataFetcher {
    static func fetch(
        for url: URL,
        session: URLSession = .shared
    ) async -> GhostBookmarkMetadata? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await session.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              (200..<400).contains(httpResponse.statusCode),
              let html = decodeHTML(data) else {
            return nil
        }

        let metadata = metaValues(in: html)
        let title = firstNonempty(
            metadata["og:title"],
            metadata["twitter:title"],
            titleElement(in: html),
            url.host
        ) ?? url.absoluteString
        let publisher = firstNonempty(
            metadata["og:site_name"],
            metadata["application-name"],
            url.host
        ) ?? ""

        return GhostBookmarkMetadata(
            url: url,
            icon: absoluteURLString(
                firstNonempty(metadata["icon"], metadata["shortcut icon"]),
                relativeTo: url
            ),
            title: decodeHTMLEntities(title),
            description: decodeHTMLEntities(
                firstNonempty(
                    metadata["og:description"],
                    metadata["description"],
                    metadata["twitter:description"]
                ) ?? ""
            ),
            author: decodeHTMLEntities(metadata["author"] ?? ""),
            publisher: decodeHTMLEntities(publisher),
            thumbnail: absoluteURLString(
                firstNonempty(
                    metadata["og:image"],
                    metadata["twitter:image"],
                    metadata["twitter:image:src"]
                ),
                relativeTo: url
            )
        )
    }

    private static func metaValues(in html: String) -> [String: String] {
        var values: [String: String] = [:]
        for tag in matches(#"<meta\b[^>]*>"#, in: html) {
            let attributes = attributes(in: tag)
            guard let key = (attributes["property"] ?? attributes["name"])?
                .lowercased(),
                  let content = attributes["content"],
                  !content.isEmpty else { continue }
            values[key] = content
        }

        for tag in matches(#"<link\b[^>]*>"#, in: html) {
            let attributes = attributes(in: tag)
            guard let relation = attributes["rel"]?.lowercased(),
                  relation.contains("icon"),
                  let href = attributes["href"],
                  !href.isEmpty else { continue }
            values[relation] = href
            if values["icon"] == nil { values["icon"] = href }
        }
        return values
    }

    private static func attributes(in tag: String) -> [String: String] {
        let pattern = #"([A-Za-z_:][A-Za-z0-9_:.-]*)\s*=\s*(["'])(.*?)\2"#
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return [:] }

        let range = NSRange(tag.startIndex..<tag.endIndex, in: tag)
        var result: [String: String] = [:]
        for match in regex.matches(in: tag, range: range) {
            guard let nameRange = Range(match.range(at: 1), in: tag),
                  let valueRange = Range(match.range(at: 3), in: tag) else { continue }
            result[String(tag[nameRange]).lowercased()] = String(tag[valueRange])
        }
        return result
    }

    private static func titleElement(in html: String) -> String? {
        guard let value = matches(#"<title\b[^>]*>(.*?)</title>"#, in: html, capture: 1).first else {
            return nil
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func matches(
        _ pattern: String,
        in text: String,
        capture: Int = 0
    ) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard capture < match.numberOfRanges,
                  let valueRange = Range(match.range(at: capture), in: text) else { return nil }
            return String(text[valueRange])
        }
    }

    private static func decodeHTML(_ data: Data) -> String? {
        String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .shiftJIS)
            ?? String(data: data, encoding: .japaneseEUC)
    }

    private static func absoluteURLString(
        _ value: String?,
        relativeTo baseURL: URL
    ) -> String {
        guard let value,
              let url = URL(
                string: decodeHTMLEntities(value),
                relativeTo: baseURL
              )?.absoluteURL else { return "" }
        return url.absoluteString
    }

    private static func firstNonempty(_ values: String?...) -> String? {
        for value in values {
            if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return nil
    }

    private static func decodeHTMLEntities(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
