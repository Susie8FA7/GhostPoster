import Foundation
import XCTest
@testable import GhostPosterTraceImportCore

final class TraceImporterTests: XCTestCase {
    func testImportsAndSummarizesVersionOneTrace() throws {
        let data = Data(Self.validTrace.utf8)
        let document = try TraceImporter.decode(data)
        let summary = TraceImporter.summarize(document)

        XCTAssertEqual(summary.sessionCount, 1)
        XCTAssertEqual(summary.eventCount, 3)
        XCTAssertEqual(summary.succeededSessionCount, 1)
        XCTAssertEqual(summary.correctionCount, 1)
        XCTAssertEqual(summary.changedCorrectionCount, 1)
        XCTAssertEqual(summary.foundationModelsDurationMilliseconds, 420)
    }

    func testRejectsUnknownVersion() throws {
        let data = Data(
            Self.validTrace.replacingOccurrences(
                of: #""format_version": "1.0""#,
                with: #""format_version": "2.0""#
            ).utf8
        )

        XCTAssertThrowsError(try TraceImporter.decode(data)) { error in
            XCTAssertEqual(
                error as? TraceImportError,
                .unsupportedVersion("2.0")
            )
        }
    }

    func testRejectsNonSequentialEvents() throws {
        let data = Data(
            Self.validTrace.replacingOccurrences(
                of: #""sequence": 2"#,
                with: #""sequence": 4"#
            ).utf8
        )

        XCTAssertThrowsError(try TraceImporter.decode(data)) { error in
            guard case .invalidEventSequence = error as? TraceImportError else {
                return XCTFail("Expected invalidEventSequence, got \(error)")
            }
        }
    }

    func testMapsTraceToPrivacySafeOpenTelemetrySpans() throws {
        let document = try TraceImporter.decode(Data(Self.validTrace.utf8))
        let payload = OpenTelemetryMapper.map(document)
        let spans = try XCTUnwrap(
            payload.resourceSpans.first?.scopeSpans.first?.spans
        )

        XCTAssertEqual(spans.count, 4)
        XCTAssertEqual(spans.first?.name, "ghostposter.hands_free_session")
        XCTAssertEqual(spans.dropFirst().first?.parentSpanId, spans.first?.spanId)

        let data = try OpenTelemetryMapper.encodedJSON(payload)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("ghostposter.correction.source"))
        XCTAssertTrue(json.contains("foundation_models"))
        XCTAssertFalse(json.contains("title"))
        XCTAssertFalse(json.contains("body"))
        XCTAssertFalse(json.contains("reference_url"))
    }

    func testLangfuseRequestUsesV4OpenTelemetryEndpoint() throws {
        let document = try TraceImporter.decode(Data(Self.validTrace.utf8))
        let configuration = LangfuseConfiguration(
            baseURL: URL(string: "https://jp.cloud.langfuse.com")!,
            publicKey: "pk-lf-test",
            secretKey: "sk-lf-test"
        )
        let request = try LangfuseOpenTelemetryClient().makeRequest(
            payload: OpenTelemetryMapper.map(document),
            configuration: configuration
        )

        XCTAssertEqual(
            request.url?.absoluteString,
            "https://jp.cloud.langfuse.com/api/public/otel/v1/traces"
        )
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "x-langfuse-ingestion-version"),
            "4"
        )
        XCTAssertTrue(
            request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Basic ") == true
        )
    }

    func testEnvironmentConfigurationOverridesStoredConfiguration() throws {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("config.json")
        let store = LangfuseConfigurationStore(configurationURL: temporaryURL)
        let configuration = try store.resolve(environment: [
            "LANGFUSE_BASE_URL": "https://us.cloud.langfuse.com",
            "LANGFUSE_PUBLIC_KEY": "pk-lf-env",
            "LANGFUSE_SECRET_KEY": "sk-lf-env"
        ])

        XCTAssertEqual(
            configuration.baseURL.absoluteString,
            "https://us.cloud.langfuse.com"
        )
        XCTAssertEqual(configuration.publicKey, "pk-lf-env")
        XCTAssertEqual(configuration.secretKey, "sk-lf-env")
    }

    private static let validTrace = #"""
    {
      "format": "ghostposter-trace",
      "format_version": "1.0",
      "generated_at": "2026-08-31T00:00:00Z",
      "sessions": [{
        "id": "00000000-0000-0000-0000-000000000001",
        "started_at": "2026-08-31T00:00:00Z",
        "ended_at": "2026-08-31T00:01:00Z",
        "outcome": "succeeded",
        "events": [
          {
            "sequence": 1,
            "timestamp": "2026-08-31T00:00:00Z",
            "name": "session_started"
          },
          {
            "sequence": 2,
            "timestamp": "2026-08-31T00:00:20Z",
            "name": "transcript_corrected",
            "correction_source": "foundation_models",
            "changed": true,
            "input_character_count": 18,
            "output_character_count": 19,
            "duration_milliseconds": 420
          },
          {
            "sequence": 3,
            "timestamp": "2026-08-31T00:01:00Z",
            "name": "session_finished",
            "outcome": "succeeded"
          }
        ]
      }]
    }
    """#
}
