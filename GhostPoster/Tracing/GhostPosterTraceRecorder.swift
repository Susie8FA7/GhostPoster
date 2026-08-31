import Combine
import Foundation

@MainActor
final class GhostPosterTraceRecorder: ObservableObject {
#if DEBUG
    static let shared = GhostPosterTraceRecorder(
        isEnabled: UserDefaults.standard.bool(forKey: enabledDefaultsKey),
        persistsEnabledSetting: true
    )
    private static let enabledDefaultsKey = "debugTraceEnabled"
#else
    static let shared = GhostPosterTraceRecorder(isEnabled: false)
#endif

    @Published private(set) var isEnabled: Bool
    @Published private(set) var revision = 0

    private let now: () -> Date
    private let persistsEnabledSetting: Bool
    private var completedSessions: [GhostPosterTraceSession] = []
    private var activeSession: GhostPosterTraceSession?
    private var nextSequence = 1

    init(
        now: @escaping () -> Date = Date.init,
        isEnabled: Bool = true,
        persistsEnabledSetting: Bool = false
    ) {
        self.now = now
        self.isEnabled = isEnabled
        self.persistsEnabledSetting = persistsEnabledSetting
    }

    func setEnabled(_ enabled: Bool) {
#if DEBUG
        isEnabled = enabled
        if persistsEnabledSetting {
            UserDefaults.standard.set(
                enabled,
                forKey: Self.enabledDefaultsKey
            )
        }
        if !enabled {
            clear()
        }
#else
        isEnabled = false
#endif
    }

    func beginSession() {
        guard isEnabled else { return }
        if activeSession != nil {
            finishSession(outcome: "restarted")
        }
        activeSession = GhostPosterTraceSession(
            id: UUID(),
            startedAt: now(),
            endedAt: nil,
            outcome: nil,
            events: []
        )
        nextSequence = 1
        record(name: "session_started")
    }

    func record(
        name: String,
        state: String? = nil,
        scope: String? = nil,
        outcome: String? = nil,
        correctionSource: String? = nil,
        changed: Bool? = nil,
        inputCharacterCount: Int? = nil,
        outputCharacterCount: Int? = nil,
        durationMilliseconds: Int? = nil,
        errorCode: String? = nil
    ) {
        guard isEnabled, activeSession != nil else { return }
        activeSession?.events.append(
            GhostPosterTraceEvent(
                sequence: nextSequence,
                timestamp: now(),
                name: name,
                state: state,
                scope: scope,
                outcome: outcome,
                correctionSource: correctionSource,
                changed: changed,
                inputCharacterCount: inputCharacterCount,
                outputCharacterCount: outputCharacterCount,
                durationMilliseconds: durationMilliseconds,
                errorCode: errorCode
            )
        )
        nextSequence += 1
        revision &+= 1
    }

    func finishSession(outcome: String) {
        guard var session = activeSession else { return }
        record(name: "session_finished", outcome: outcome)
        session = activeSession ?? session
        session.endedAt = now()
        session.outcome = outcome
        completedSessions.append(session)
        activeSession = nil
        revision &+= 1
    }

    func document() -> GhostPosterTraceDocument {
        let sessions = completedSessions + [activeSession].compactMap { $0 }
        return GhostPosterTraceDocument(
            generatedAt: now(),
            sessions: sessions
        )
    }

    func encodedDocument() throws -> Data {
        try JSONEncoder.ghostPosterTraceEncoder().encode(document())
    }

    func formattedDocument() -> String {
        guard let data = try? encodedDocument() else {
            return "JSONの生成に失敗しました。"
        }
        return String(data: data, encoding: .utf8) ?? "JSONの生成に失敗しました。"
    }

    func clear() {
        completedSessions = []
        activeSession = nil
        nextSequence = 1
        revision &+= 1
    }
}
