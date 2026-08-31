import Foundation

public struct OTLPExportRequest: Codable, Equatable, Sendable {
    public let resourceSpans: [OTLPResourceSpans]
}

public struct OTLPResourceSpans: Codable, Equatable, Sendable {
    public let resource: OTLPResource
    public let scopeSpans: [OTLPScopeSpans]
}

public struct OTLPResource: Codable, Equatable, Sendable {
    public let attributes: [OTLPAttribute]
}

public struct OTLPScopeSpans: Codable, Equatable, Sendable {
    public let scope: OTLPScope
    public let spans: [OTLPSpan]
}

public struct OTLPScope: Codable, Equatable, Sendable {
    public let name: String
    public let version: String
}

public struct OTLPSpan: Codable, Equatable, Sendable {
    public let traceId: String
    public let spanId: String
    public let parentSpanId: String?
    public let name: String
    public let kind: Int
    public let startTimeUnixNano: String
    public let endTimeUnixNano: String
    public let attributes: [OTLPAttribute]
    public let status: OTLPStatus
}

public struct OTLPStatus: Codable, Equatable, Sendable {
    public let code: Int
    public let message: String?
}

public struct OTLPAttribute: Codable, Equatable, Sendable {
    public let key: String
    public let value: OTLPAnyValue
}

public struct OTLPAnyValue: Codable, Equatable, Sendable {
    public let stringValue: String?
    public let boolValue: Bool?
    public let intValue: String?
    public let arrayValue: OTLPArrayValue?

    public static func string(_ value: String) -> Self {
        Self(stringValue: value, boolValue: nil, intValue: nil, arrayValue: nil)
    }

    public static func bool(_ value: Bool) -> Self {
        Self(stringValue: nil, boolValue: value, intValue: nil, arrayValue: nil)
    }

    public static func int(_ value: Int) -> Self {
        Self(stringValue: nil, boolValue: nil, intValue: String(value), arrayValue: nil)
    }

    public static func strings(_ values: [String]) -> Self {
        Self(
            stringValue: nil,
            boolValue: nil,
            intValue: nil,
            arrayValue: OTLPArrayValue(values: values.map(Self.string))
        )
    }
}

public struct OTLPArrayValue: Codable, Equatable, Sendable {
    public let values: [OTLPAnyValue]
}

public enum OpenTelemetryMapper {
    public static func map(_ document: TraceDocument) -> OTLPExportRequest {
        let spans = document.sessions.flatMap {
            makeSpans(for: $0, document: document)
        }
        return OTLPExportRequest(
            resourceSpans: [
                OTLPResourceSpans(
                    resource: OTLPResource(attributes: [
                        attribute("service.name", .string("ghostposter-trace-importer")),
                        attribute("service.version", .string("1.0")),
                        attribute("telemetry.sdk.language", .string("swift"))
                    ]),
                    scopeSpans: [
                        OTLPScopeSpans(
                            scope: OTLPScope(
                                name: "app.ghostposter.trace-importer",
                                version: "1.0"
                            ),
                            spans: spans
                        )
                    ]
                )
            ]
        )
    }

    public static func encodedJSON(
        _ request: OTLPExportRequest,
        prettyPrinted: Bool = false
    ) throws -> Data {
        let encoder = JSONEncoder()
        if prettyPrinted {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        }
        return try encoder.encode(request)
    }

    private static func makeSpans(
        for session: TraceSession,
        document: TraceDocument
    ) -> [OTLPSpan] {
        let traceID = session.id.uuidString
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
        let rootSpanID = spanID(for: "\(session.id.uuidString):root")
        let commonAttributes = traceAttributes(
            for: session,
            formatVersion: document.formatVersion
        )
        let lastTimestamp = session.events.last?.timestamp ?? session.startedAt
        let rootEnd = max(session.endedAt ?? lastTimestamp, session.startedAt)
        let root = OTLPSpan(
            traceId: traceID,
            spanId: rootSpanID,
            parentSpanId: nil,
            name: "ghostposter.hands_free_session",
            kind: 1,
            startTimeUnixNano: unixNanoseconds(session.startedAt),
            endTimeUnixNano: unixNanoseconds(ensuringAfter: rootEnd, start: session.startedAt),
            attributes: commonAttributes + optionalAttributes([
                ("ghostposter.session.outcome", session.outcome.map(OTLPAnyValue.string)),
                ("ghostposter.session.event_count", .int(session.events.count))
            ]),
            status: status(for: session.outcome)
        )

        let children = session.events.map { event in
            let start: Date
            let end: Date
            if let durationMilliseconds = event.durationMilliseconds {
                end = event.timestamp
                start = end.addingTimeInterval(
                    -Double(max(durationMilliseconds, 1)) / 1_000
                )
            } else {
                start = event.timestamp
                end = start.addingTimeInterval(0.001)
            }
            return OTLPSpan(
                traceId: traceID,
                spanId: spanID(for: "\(session.id.uuidString):\(event.sequence)"),
                parentSpanId: rootSpanID,
                name: "ghostposter.\(event.name)",
                kind: 1,
                startTimeUnixNano: unixNanoseconds(start),
                endTimeUnixNano: unixNanoseconds(end),
                attributes: commonAttributes + eventAttributes(event),
                status: status(for: event.outcome)
            )
        }
        return [root] + children
    }

    private static func traceAttributes(
        for session: TraceSession,
        formatVersion: String
    ) -> [OTLPAttribute] {
        [
            attribute("langfuse.trace.name", .string("ghostposter-hands-free-posting")),
            attribute("langfuse.session.id", .string(session.id.uuidString)),
            attribute("langfuse.trace.tags", .strings(["ghostposter", "trace-format-\(formatVersion)"])),
            attribute("langfuse.trace.metadata.format_version", .string(formatVersion)),
            attribute("ghostposter.privacy.content_included", .bool(false))
        ]
    }

    private static func eventAttributes(_ event: TraceEvent) -> [OTLPAttribute] {
        optionalAttributes([
            ("ghostposter.event.sequence", .int(event.sequence)),
            ("ghostposter.event.name", .string(event.name)),
            ("ghostposter.state", event.state.map(OTLPAnyValue.string)),
            ("ghostposter.scope", event.scope.map(OTLPAnyValue.string)),
            ("ghostposter.outcome", event.outcome.map(OTLPAnyValue.string)),
            ("ghostposter.correction.source", event.correctionSource.map(OTLPAnyValue.string)),
            ("ghostposter.correction.changed", event.changed.map(OTLPAnyValue.bool)),
            ("ghostposter.input_character_count", event.inputCharacterCount.map(OTLPAnyValue.int)),
            ("ghostposter.output_character_count", event.outputCharacterCount.map(OTLPAnyValue.int)),
            ("ghostposter.duration_milliseconds", event.durationMilliseconds.map(OTLPAnyValue.int)),
            ("ghostposter.error.code", event.errorCode.map(OTLPAnyValue.string))
        ])
    }

    private static func optionalAttributes(
        _ values: [(String, OTLPAnyValue?)]
    ) -> [OTLPAttribute] {
        values.compactMap { key, value in
            value.map { attribute(key, $0) }
        }
    }

    private static func attribute(
        _ key: String,
        _ value: OTLPAnyValue
    ) -> OTLPAttribute {
        OTLPAttribute(key: key, value: value)
    }

    private static func status(for outcome: String?) -> OTLPStatus {
        switch outcome {
        case "failed": OTLPStatus(code: 2, message: "failed")
        case "succeeded": OTLPStatus(code: 1, message: nil)
        default: OTLPStatus(code: 0, message: nil)
        }
    }

    private static func unixNanoseconds(_ date: Date) -> String {
        let milliseconds = UInt64(
            (max(0, date.timeIntervalSince1970) * 1_000).rounded()
        )
        return String(milliseconds * 1_000_000)
    }

    private static func unixNanoseconds(
        ensuringAfter end: Date,
        start: Date
    ) -> String {
        unixNanoseconds(end > start ? end : start.addingTimeInterval(0.001))
    }

    private static func spanID(for value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }
}
