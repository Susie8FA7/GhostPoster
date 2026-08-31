import Foundation

struct GhostPosterTraceDocument: Codable, Equatable, Sendable {
    static let currentFormatVersion = "1.0"

    let format: String
    let formatVersion: String
    let generatedAt: Date
    let sessions: [GhostPosterTraceSession]

    init(
        generatedAt: Date,
        sessions: [GhostPosterTraceSession]
    ) {
        format = "ghostposter-trace"
        formatVersion = Self.currentFormatVersion
        self.generatedAt = generatedAt
        self.sessions = sessions
    }
}

struct GhostPosterTraceSession: Codable, Equatable, Sendable {
    let id: UUID
    let startedAt: Date
    var endedAt: Date?
    var outcome: String?
    var events: [GhostPosterTraceEvent]
}

struct GhostPosterTraceEvent: Codable, Equatable, Sendable {
    let sequence: Int
    let timestamp: Date
    let name: String
    var state: String?
    var scope: String?
    var outcome: String?
    var correctionSource: String?
    var changed: Bool?
    var inputCharacterCount: Int?
    var outputCharacterCount: Int?
    var durationMilliseconds: Int?
    var errorCode: String?
}

extension JSONEncoder {
    static func ghostPosterTraceEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }
}
