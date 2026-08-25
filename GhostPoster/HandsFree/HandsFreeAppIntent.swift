import AppIntents
import Foundation

enum HandsFreeLaunchRequest {
    private static let key = "startHandsFreePosting"
    static let notification = Notification.Name("StartHandsFreePosting")

    static func request() {
        UserDefaults.standard.set(true, forKey: key)
        UserDefaults.standard.synchronize()
        NotificationCenter.default.post(name: notification, object: nil)
    }

    static func consume() -> Bool {
        let requested = UserDefaults.standard.bool(forKey: key)
        if requested {
            UserDefaults.standard.set(false, forKey: key)
            UserDefaults.standard.synchronize()
        }
        return requested
    }
}

struct StartHandsFreePostingIntent: AppIntent {
    static let title: LocalizedStringResource = "ハンズフリー投稿"
    static let description = IntentDescription("GhostPosterを起動して、音声だけでGhostの下書きを作成します。")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        HandsFreeLaunchRequest.request()
        return .result()
    }
}

struct GhostPosterShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartHandsFreePostingIntent(),
            phrases: [
                "\(.applicationName)でブログ下書き",
                "\(.applicationName)で下書き投稿"
            ],
            shortTitle: "ハンズフリー投稿",
            systemImageName: "waveform"
        )
    }
}
