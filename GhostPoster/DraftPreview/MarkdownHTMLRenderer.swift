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

        // AttributedStringからHTMLへ変換すると段落間の空行が失われるため、
        // 参考URLセクションの区切りはHTMLとして明示します。
        html = html.replacingOccurrences(
            of: "参考URL：",
            with: "<br><br>参考URL："
        )
        return html
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
