import Foundation

public struct TraceDocument: Decodable, Equatable, Sendable {
    public let format: String
    public let formatVersion: String
    public let generatedAt: Date
    public let sessions: [TraceSession]
}

public struct TraceSession: Decodable, Equatable, Sendable {
    public let id: UUID
    public let startedAt: Date
    public let endedAt: Date?
    public let outcome: String?
    public let events: [TraceEvent]
}

public struct TraceEvent: Decodable, Equatable, Sendable {
    public let sequence: Int
    public let timestamp: Date
    public let name: String
    public let state: String?
    public let scope: String?
    public let outcome: String?
    public let correctionSource: String?
    public let changed: Bool?
    public let inputCharacterCount: Int?
    public let outputCharacterCount: Int?
    public let durationMilliseconds: Int?
    public let errorCode: String?
}
