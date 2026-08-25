import Foundation
import UIKit

enum MarkdownHTMLRenderer {
    static func render(_ markdown: String) throws -> String {
        let markdownWithHardBreaks = preserveLineBreaks(in: markdown)
        let attributed = try AttributedString(
            markdown: markdownWithHardBreaks,
            options: .init(interpretedSyntax: .full)
        )
        let nsAttributed = NSAttributedString(attributed)
        let range = NSRange(location: 0, length: nsAttributed.length)
        let data = try nsAttributed.data(
            from: range,
            documentAttributes: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ]
        )

        guard var html = String(data: data, encoding: .utf8) else {
            throw MarkdownRenderError.encodingFailed
        }

        // Cocoa HTML Writerはhtml/head/style/bodyを含む完全な文書を生成します。
        // Ghostのsource=htmlには本文フラグメントだけを渡し、段落タグが
        // Ghost側の変換で一つにまとめられないようにします。
        html = bodyFragment(from: html)
        html = html.replacingOccurrences(
            of: #"<span\b[^>]*>"#,
            with: "",
            options: .regularExpression
        )
        html = html.replacingOccurrences(of: "</span>", with: "")
        html = html.replacingOccurrences(
            of: #"\sclass="[^"]*""#,
            with: "",
            options: .regularExpression
        )

        // AttributedStringからHTMLへ変換すると段落間の空行が失われるため、
        // 参考URLセクションの区切りはHTMLとして明示します。
        html = html.replacingOccurrences(
            of: "参考URL：",
            with: "<br><br>参考URL："
        )
        return html
    }

    private static func bodyFragment(from html: String) -> String {
        guard let bodyStart = html.range(of: "<body>"),
              let bodyEnd = html.range(
                of: "</body>",
                range: bodyStart.upperBound..<html.endIndex
              ) else {
            return html
        }

        return String(html[bodyStart.upperBound..<bodyEnd.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Markdownでは単独改行が空白として扱われるため、行末へ半角空白2個を
    /// 追加して強制改行にします。空行は段落区切りとしてそのまま残します。
    private static func preserveLineBreaks(in markdown: String) -> String {
        let normalized = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).map(String.init)

        return lines.enumerated().map { index, line in
            guard !line.isEmpty,
                  index + 1 < lines.count,
                  !lines[index + 1].isEmpty else {
                return line
            }
            return line.hasSuffix("  ") ? line : line + "  "
        }.joined(separator: "\n")
    }
}
enum MarkdownRenderError: LocalizedError {
    case encodingFailed

    var errorDescription: String? {
        "MarkdownをHTMLへ変換できませんでした。"
    }
}
