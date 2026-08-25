//
//  GhostPosterTests.swift
//  GhostPosterTests
//
//

import Foundation
import Testing
@testable import GhostPoster

struct GhostPosterTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
        // Swift Testing Documentation
        // https://developer.apple.com/documentation/testing
    }

    @Test func lexicalRendererPreservesLinesAsParagraphs() throws {
        let lexical = try GhostLexicalRenderer.render("一行目\n二行目\n\n四行目")
        let data = try #require(lexical.data(using: .utf8))
        let json = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let root = try #require(json["root"] as? [String: Any])
        let paragraphs = try #require(root["children"] as? [[String: Any]])

        #expect(paragraphs.count == 4)
        #expect(paragraphs.allSatisfy { $0["type"] as? String == "paragraph" })
        let emptyParagraphChildren = try #require(
            paragraphs[2]["children"] as? [[String: Any]]
        )
        #expect(emptyParagraphChildren.isEmpty)
    }

    @Test func lexicalRendererAppendsGhostBookmarkNode() throws {
        let url = try #require(URL(string: "https://example.com/article"))
        let lexical = try GhostLexicalRenderer.render(
            "本文",
            bookmark: .fallback(for: url),
            referenceURL: url
        )
        let data = try #require(lexical.data(using: .utf8))
        let json = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let root = try #require(json["root"] as? [String: Any])
        let nodes = try #require(root["children"] as? [[String: Any]])
        let bookmark = try #require(nodes.last)
        let metadata = try #require(bookmark["metadata"] as? [String: Any])

        #expect(nodes.count == 3)
        let referenceLabel = try #require(nodes[1]["children"] as? [[String: Any]])
        #expect(referenceLabel.first?["text"] as? String == "参考URL：")
        #expect(bookmark["type"] as? String == "bookmark")
        #expect(bookmark["version"] as? Int == 1)
        #expect(bookmark["url"] as? String == url.absoluteString)
        #expect(metadata["publisher"] as? String == "example.com")
    }

    @Test func lexicalRendererFallsBackToPlainURL() throws {
        let url = try #require(URL(string: "https://example.com/article"))
        let lexical = try GhostLexicalRenderer.render(
            "本文",
            referenceURL: url
        )
        let data = try #require(lexical.data(using: .utf8))
        let json = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let root = try #require(json["root"] as? [String: Any])
        let nodes = try #require(root["children"] as? [[String: Any]])
        let urlParagraph = try #require(nodes.last)
        let urlChildren = try #require(urlParagraph["children"] as? [[String: Any]])

        #expect(nodes.count == 3)
        #expect(urlParagraph["type"] as? String == "paragraph")
        #expect(urlChildren.first?["text"] as? String == url.absoluteString)
        #expect(nodes.contains { $0["type"] as? String == "bookmark" } == false)
    }

    @Test func guide01StatusDoesNotExposeRecognizedContent() {
        let title = Guide01StatusPresenter.message(for: .titleReview)
        let body = Guide01StatusPresenter.message(for: .bodyReview)
        let confirmation = Guide01StatusPresenter.message(for: .confirmation)

        #expect(title == Guide01StatusMessage(
            title: "タイトルを入力しました",
            content: "タイトルを確定、または修正"
        ))
        #expect(body == Guide01StatusMessage(
            title: "本文を入力しました",
            content: "本文を追加、または確定"
        ))
        #expect(confirmation == Guide01StatusMessage(
            title: "最終確認",
            content: "投稿、読み上げ、またはキャンセル"
        ))
        #expect(title.displayText == "タイトルを入力しました\nタイトルを確定、または修正")
    }

}
