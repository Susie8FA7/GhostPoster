import Foundation

public enum TraceImportError: LocalizedError, Equatable {
    case unreadableFile(String)
    case invalidJSON(String)
    case unsupportedFormat(String)
    case unsupportedVersion(String)
    case invalidEventSequence(sessionID: UUID)

    public var errorDescription: String? {
        switch self {
        case .unreadableFile(let message):
            "Traceファイルを読み込めません: \(message)"
        case .invalidJSON(let message):
            "Trace JSONを解析できません: \(message)"
        case .unsupportedFormat(let format):
            "未対応のTrace形式です: \(format)"
        case .unsupportedVersion(let version):
            "未対応のTrace形式バージョンです: \(version)"
        case .invalidEventSequence(let sessionID):
            "イベントのsequenceが不正です: \(sessionID.uuidString)"
        }
    }
}

public struct TraceSummary: Equatable, Sendable {
    public let sessionCount: Int
    public let eventCount: Int
    public let succeededSessionCount: Int
    public let failedSessionCount: Int
    public let correctionCount: Int
    public let changedCorrectionCount: Int
    public let foundationModelsDurationMilliseconds: Int

    public var description: String {
        """
        GhostPoster Trace Format 1.0
        Sessions: \(sessionCount)
        Events: \(eventCount)
        Succeeded sessions: \(succeededSessionCount)
        Failed sessions: \(failedSessionCount)
        Corrections: \(correctionCount)
        Changed corrections: \(changedCorrectionCount)
        Foundation Models total duration: \(foundationModelsDurationMilliseconds) ms
        """
    }
}

public enum TraceImporter {
    public static func load(from url: URL) throws -> TraceDocument {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw TraceImportError.unreadableFile(error.localizedDescription)
        }
        return try decode(data)
    }

    public static func decode(_ data: Data) throws -> TraceDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let document: TraceDocument
        do {
            document = try decoder.decode(TraceDocument.self, from: data)
        } catch {
            throw TraceImportError.invalidJSON(error.localizedDescription)
        }

        guard document.format == "ghostposter-trace" else {
            throw TraceImportError.unsupportedFormat(document.format)
        }
        guard document.formatVersion == "1.0" else {
            throw TraceImportError.unsupportedVersion(document.formatVersion)
        }
        for session in document.sessions {
            let expected = Array(1...session.events.count)
            guard session.events.map(\.sequence) == expected else {
                throw TraceImportError.invalidEventSequence(sessionID: session.id)
            }
        }
        return document
    }

    public static func summarize(_ document: TraceDocument) -> TraceSummary {
        let events = document.sessions.flatMap(\.events)
        let corrections = events.filter { $0.name == "transcript_corrected" }
        return TraceSummary(
            sessionCount: document.sessions.count,
            eventCount: events.count,
            succeededSessionCount: document.sessions.filter {
                $0.outcome == "succeeded"
            }.count,
            failedSessionCount: document.sessions.filter {
                $0.outcome == "failed"
            }.count,
            correctionCount: corrections.count,
            changedCorrectionCount: corrections.filter {
                $0.changed == true
            }.count,
            foundationModelsDurationMilliseconds: corrections
                .filter { $0.correctionSource == "foundation_models" }
                .compactMap(\.durationMilliseconds)
                .reduce(0, +)
        )
    }
}
