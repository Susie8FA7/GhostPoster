import AVFAudio
import Combine
import Foundation
import Speech

enum VoiceRecognitionPurpose: Equatable, Sendable {
    case content
    case command
}

struct VoiceRecognitionResult: Equatable, Sendable {
    let sessionID: UUID
    let purpose: VoiceRecognitionPurpose
    let text: String
}

@MainActor
final class VoiceInputManager: ObservableObject {
    @Published private(set) var transcript = ""
    @Published private(set) var finalTranscript = ""
    @Published private(set) var finalResult: VoiceRecognitionResult?
    @Published private(set) var isRecording = false
    @Published private(set) var errorMessage: String?

    private let audioEngine = AVAudioEngine()
    private let speechRecognizer = SFSpeechRecognizer(
        locale: Locale(identifier: "ja-JP")
    )
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var silenceTask: Task<Void, Never>?
    private var silenceTimeout: TimeInterval?
    private var immediatePhrases: Set<String> = []
    private var activeSessionID: UUID?
    private var pendingSessionID: UUID?

    func start(
        silenceTimeout: TimeInterval? = nil,
        immediatePhrases: Set<String> = [],
        purpose: VoiceRecognitionPurpose = .content
    ) {
        guard !isRecording else { return }
        errorMessage = nil
        self.silenceTimeout = silenceTimeout
        self.immediatePhrases = immediatePhrases
        let sessionID = UUID()
        pendingSessionID = sessionID

        Task {
            guard await requestPermissions() else { return }
            guard pendingSessionID == sessionID else { return }
            do {
                try startRecording(sessionID: sessionID, purpose: purpose)
            } catch {
                errorMessage = error.localizedDescription
                stop()
            }
        }
    }

    func stop() {
        activeSessionID = nil
        pendingSessionID = nil
        silenceTask?.cancel()
        silenceTask = nil
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }

    private func startRecording(
        sessionID: UUID,
        purpose: VoiceRecognitionPurpose
    ) throws {
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            throw VoiceInputError.recognizerUnavailable
        }

        stop()
        transcript = ""
        finalTranscript = ""
        finalResult = nil
        activeSessionID = sessionID

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(
            .playAndRecord,
            mode: .measurement,
            options: [.duckOthers, .defaultToSpeaker]
        )
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        request.contextualStrings = [
            // 日本語ブログ入力で使う構成・表記
            "タイトル", "本文", "見出し", "小見出し", "段落",
            "概要", "要約", "結論", "補足", "関連記事",
            "箇条書き", "引用", "リンク", "タグ",
            "句点", "読点", "改行", "半角スペース",

            // Ghost投稿で頻出する固有語
            "Ghost", "Ghost Admin API", "GhostPoster", "ゴーストポスター",
            "GUIDE01",
            "Markdown", "Feature Image", "下書き", "ブログ記事",

            // 数字・年月など誤認識しやすい表現（サンプル）
            "2024年", "令和6年",
            "1月", "2月", "3月", "4月", "5月", "6月",
            "7月", "8月", "9月", "10月", "11月", "12月",

            // 技術ブログで使う固有語（サンプル）
            "サンプルプロジェクト",
            "Web API",
            "GitHub",
            "Swift",
            "SwiftUI",
            "Apple Intelligence",
            "Foundation Models",
            "阪神タイガース",
            "巨人",
            "勝敗",
            "3連戦",
            "3タテ",
            "マジック点灯",
            "マジックナンバー",
            "M21",
            "iOS",
            "macOS"
        ] + immediatePhrases.sorted()
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(
            onBus: 0,
            bufferSize: 1_024,
            format: format
        ) { [weak request] buffer, _ in
            request?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true

        recognitionTask = speechRecognizer.recognitionTask(
            with: request
        ) { [weak self] result, error in
            Task { @MainActor in
                guard let self, self.activeSessionID == sessionID else { return }
                if let result {
                    let recognizedText = result.bestTranscription.formattedString
                    self.transcript = recognizedText
                    if let immediatePhrase = self.recognizedImmediatePhrase(recognizedText) {
                        self.commit(immediatePhrase, sessionID: sessionID, purpose: purpose)
                        return
                    }
                    if result.isFinal {
                        self.commit(recognizedText, sessionID: sessionID, purpose: purpose)
                    } else {
                        self.scheduleSilenceCommit(sessionID: sessionID, purpose: purpose)
                    }
                }
                if let error, self.isRecording {
                    self.errorMessage = error.localizedDescription
                    self.stop()
                }
            }
        }
    }

    private func scheduleSilenceCommit(
        sessionID: UUID,
        purpose: VoiceRecognitionPurpose
    ) {
        silenceTask?.cancel()
        guard let silenceTimeout, !transcript.isEmpty else { return }

        silenceTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(silenceTimeout))
                guard !Task.isCancelled,
                      let self,
                      self.isRecording,
                      self.activeSessionID == sessionID else { return }
                self.commit(self.transcript, sessionID: sessionID, purpose: purpose)
            } catch {
                // A newer partial result resets the silence interval.
            }
        }
    }

    private func recognizedImmediatePhrase(_ text: String) -> String? {
        let punctuation = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        let normalized = text.trimmingCharacters(in: punctuation)
        return immediatePhrases.contains(normalized) ? normalized : nil
    }

    private func commit(
        _ text: String,
        sessionID: UUID,
        purpose: VoiceRecognitionPurpose
    ) {
        guard activeSessionID == sessionID else { return }
        let committed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !committed.isEmpty else { return }
        finalTranscript = committed
        finalResult = VoiceRecognitionResult(
            sessionID: sessionID,
            purpose: purpose,
            text: committed
        )
        stop()
    }

    private func requestPermissions() async -> Bool {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else {
            errorMessage = "音声認識の使用が許可されていません。"
            return false
        }

        let microphoneAllowed = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { allowed in
                continuation.resume(returning: allowed)
            }
        }
        guard microphoneAllowed else {
            errorMessage = "マイクの使用が許可されていません。"
            return false
        }
        return true
    }
}

enum VoiceInputError: LocalizedError {
    case recognizerUnavailable

    var errorDescription: String? {
        "現在、音声認識を利用できません。"
    }
}
