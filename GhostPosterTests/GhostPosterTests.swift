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

    @Test func guide01ReadAloudMessageShowsConfirmationContentWithoutURL() {
        let message = Guide01StatusPresenter.readAloudMessage(
            title: "テストタイトル",
            body: "一行目\n二行目",
            hasReferenceURL: true,
            tags: ["Swift", "日記"]
        )

        #expect(message.title == "投稿内容")
        #expect(message.content == """
        タイトル
        テストタイトル
        本文
        一行目
        二行目
        参考URLあり
        タグ
        Swift、日記
        """)
        #expect(message.content.contains("https://") == false)
        #expect(message.fontSize == 20)
        #expect(message.showsStatusBar == false)

        let messageWithoutOptionalContent = Guide01StatusPresenter.readAloudMessage(
            title: "タイトル",
            body: "本文",
            hasReferenceURL: false,
            tags: []
        )
        #expect(messageWithoutOptionalContent.content.contains("参考URLなし"))
        #expect(messageWithoutOptionalContent.content.hasSuffix("タグ\nなし"))
    }

    @Test func guide01LongReadAloudMessageScrollsOneLineAtATime() {
        let message = Guide01StatusMessage(
            title: "投稿内容",
            content: "一二三四五六七八九十\n次の行",
            fontSize: 20
        )
        let frames = Guide01StatusPresenter.scrollingMessages(
            for: message,
            charactersPerLine: 4,
            visibleContentLines: 2
        )

        #expect(frames.map(\.content) == [
            "一二三四\n五六七八",
            "五六七八\n九十",
            "九十\n次の行"
        ])
        #expect(frames.allSatisfy { $0.title == "投稿内容" })
        #expect(frames.allSatisfy { $0.fontSize == 20 })
        #expect(frames.allSatisfy { $0.showsStatusBar })
    }

    @Test func guide01ShortReadAloudMessageDoesNotScroll() {
        let message = Guide01StatusMessage(
            title: "投稿内容",
            content: "短い本文",
            fontSize: 20
        )

        #expect(Guide01StatusPresenter.scrollingMessages(for: message) == [message])
    }

    @Test func guide01DefaultScrollFramesStayWithinSafeBLEPayloadSize() {
        let message = Guide01StatusMessage(
            title: "投稿内容",
            content: String(repeating: "日本語の長い本文です。", count: 80),
            fontSize: 20
        )
        let frames = Guide01StatusPresenter.scrollingMessages(for: message)

        #expect(frames.count > 1)
        #expect(frames.allSatisfy { $0.displayText.utf8.count <= 400 })
    }

}
