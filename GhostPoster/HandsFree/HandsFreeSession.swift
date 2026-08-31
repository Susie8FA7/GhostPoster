import AVFAudio
import Combine
import Foundation
import UIKit

@MainActor
final class HandsFreeSession: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var state: HandsFreeState = .idle
    @Published var title = ""
    @Published var body = ""
    @Published var referenceURL = ""
    @Published var tags: [String] = []
    @Published private(set) var statusMessage = "開始ボタンを押すか、Siriから起動してください。"
    @Published private(set) var shouldPost = false
    @Published private(set) var readAloudRequestID = 0
    @Published private(set) var titleWasAIRefined = false
    @Published private(set) var bodyWasAIRefined = false
    @Published private(set) var isRefiningTranscript = false
    @Published private(set) var correctionChanges: [TranscriptChange] = []

    let voiceInput = VoiceInputManager()
    let traceRecorder = GhostPosterTraceRecorder.shared
    private let synthesizer = AVSpeechSynthesizer()
    private let transcriptCorrector: TranscriptCorrecting = JapaneseTranscriptCorrector()
    private let transcriptRefiner: TranscriptRefining = FoundationModelTranscriptRefiner()
    private var startsListeningAfterSpeech = false
    private var voiceInputChanges: AnyCancellable?
    private var afterSpeechAction: AfterSpeechAction?
    private var isAppendingBody = false
    private var finalRevisionScope: TranscriptChange.Scope?

    override init() {
        super.init()
        synthesizer.delegate = self
        voiceInputChanges = voiceInput.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    func start() {
        guard state == .idle || state == .completed else { return }
        resetContent()
        traceRecorder.beginSession()
        move(to: .title, prompt: "タイトルをどうぞ。")
    }

    func receive(_ result: VoiceRecognitionResult) {
        guard accepts(result.purpose) else { return }
        let transcript = result.purpose == .content
            ? contentWithoutTrailingCommand(result.text)
            : result.text
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            restartEmptyContentInput()
            return
        }

        traceRecorder.record(
            name: "speech_recognition_completed",
            state: state.rawValue,
            scope: traceScope,
            inputCharacterCount: transcript.count
        )

        if let command = HandsFreeCommand(transcript: transcript), handle(command) {
            return
        }

        switch state {
        case .title:
            refineTitle(transcript)
        case .body:
            refineBody(transcript)
        case .referenceURL:
            referenceURL = normalizedURL(transcript)
            announce(
                to: .referenceURLReview,
                message: "参考URLを設定しました。",
                then: .beginTags
            )
        case .tags:
            let corrected = transcriptCorrector.correct(transcript)
            recordCorrection(
                from: transcript,
                to: corrected,
                scope: .tags,
                source: "mechanical"
            )
            tags = parseTags(corrected)
            announce(
                to: .tagsReview,
                message: "タグを設定しました。",
                then: .presentFinalConfirmation
            )
        case .confirmation:
            speak("投稿内容を確認しました。投稿しますか？")
        default:
            break
        }
    }

    private func refineTitle(_ transcript: String) {
        voiceInput.stop()
        let mechanicallyCorrected = transcriptCorrector.correct(transcript)
        recordCorrection(
            from: transcript,
            to: mechanicallyCorrected,
            scope: .title,
            source: "mechanical"
        )
        title = mechanicallyCorrected
        titleWasAIRefined = mechanicallyCorrected != transcript
        move(
            to: .titleReview,
            prompt: "タイトルを入力しました。確定しますか？"
        )
    }

    private func refineBody(_ transcript: String) {
        voiceInput.stop()
        statusMessage = "本文を補正しています。"
        isRefiningTranscript = true
        let mechanicallyCorrected = transcriptCorrector.correct(transcript)
        recordCorrection(
            from: transcript,
            to: mechanicallyCorrected,
            scope: .body,
            source: "mechanical"
        )
        let appendsToExistingBody = isAppendingBody && !body.isEmpty
        isAppendingBody = false
        let refinementStartedAt = Date()
        Task { @MainActor [weak self] in
            guard let self else { return }
            let refinement = await self.transcriptRefiner.refine(mechanicallyCorrected)
            guard self.state == .body else {
                self.isRefiningTranscript = false
                return
            }
            self.isRefiningTranscript = false
            self.recordCorrection(
                from: mechanicallyCorrected,
                to: refinement.text,
                scope: .body,
                source: "foundation_models",
                durationMilliseconds: Int(
                    Date().timeIntervalSince(refinementStartedAt) * 1_000
                )
            )
            self.body = appendsToExistingBody
                ? self.body + "\n" + refinement.text
                : refinement.text
            self.bodyWasAIRefined = self.bodyWasAIRefined
                || mechanicallyCorrected != transcript
                || refinement.wasRefined
            self.move(
                to: .bodyReview,
                prompt: "本文を入力しました。追加しますか、確定しますか？"
            )
        }
    }

    private func recordCorrection(
        from before: String,
        to after: String,
        scope: TranscriptChange.Scope,
        source: String,
        durationMilliseconds: Int? = nil
    ) {
        traceRecorder.record(
            name: "transcript_corrected",
            state: state.rawValue,
            scope: scope.rawValue,
            correctionSource: source,
            changed: before != after,
            inputCharacterCount: before.count,
            outputCharacterCount: after.count,
            durationMilliseconds: durationMilliseconds
        )
        guard before != after else { return }
        correctionChanges.append(
            TranscriptChange(scope: scope, before: before, after: after)
        )
    }

    private func accepts(_ purpose: VoiceRecognitionPurpose) -> Bool {
        switch state {
        case .title, .body, .referenceURL, .tags:
            return purpose == .content
        case .titleReview, .bodyReview, .referenceURLReview, .tagsReview,
             .confirmation:
            return purpose == .command
        default:
            return false
        }
    }

    private func contentWithoutTrailingCommand(_ transcript: String) -> String {
        let pattern = #"(?:[\s、。,.!?！？]*(?:確定|修正)[\s、。,.!?！？]*)$"#
        return transcript
            .replacingOccurrences(
                of: pattern,
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func restartEmptyContentInput() {
        switch state {
        case .title:
            move(to: .title, prompt: "タイトルをもう一度どうぞ。")
        case .body:
            move(to: .body, prompt: "本文をもう一度どうぞ。")
        case .referenceURL:
            move(to: .referenceURL, prompt: "参考URLをもう一度どうぞ。ない場合は、なし、と言ってください。")
        case .tags:
            move(to: .tags, prompt: "タグをもう一度どうぞ。")
        default:
            break
        }
    }

    func cancel() {
        voiceInput.stop()
        synthesizer.stopSpeaking(at: .immediate)
        isRefiningTranscript = false
        correctionChanges = []
        finalRevisionScope = nil
        state = .idle
        shouldPost = false
        statusMessage = "キャンセルしました。"
        traceRecorder.finishSession(outcome: "cancelled")
        speak("キャンセルしました。", thenListen: false)
    }

    func postingStarted() {
        voiceInput.stop()
        state = .posting
        shouldPost = false
        statusMessage = "Ghostへ下書きを作成しています…"
        traceRecorder.record(
            name: "ghost_draft_started",
            state: state.rawValue
        )
    }

    func postingFinished(title: String) {
        state = .completed
        statusMessage = "下書きを作成しました: \(title)"
        traceRecorder.record(
            name: "ghost_draft_finished",
            state: state.rawValue,
            outcome: "succeeded"
        )
        traceRecorder.finishSession(outcome: "succeeded")
        speak("Ghostに下書きを保存しました。", thenListen: false)
    }

    func postingFailed(_ message: String) {
        state = .confirmation
        statusMessage = "投稿に失敗しました: \(message)"
        traceRecorder.record(
            name: "ghost_draft_finished",
            state: state.rawValue,
            outcome: "failed",
            errorCode: "ghost_draft_failed"
        )
        speak("投稿に失敗しました。もう一度投稿するか、キャンセルと言ってください。")
    }

    private func handle(_ command: HandsFreeCommand) -> Bool {
        switch command {
        case .cancel:
            cancel()
        case .redoTitle:
            correctionChanges.removeAll { $0.scope == .title }
            title = ""
            move(to: .title, prompt: "タイトルをもう一度どうぞ。")
        case .reviseTitle where state == .confirmation:
            beginFinalRevision(of: .title)
        case .reviseBody where state == .confirmation:
            beginFinalRevision(of: .body)
        case .reviseTags where state == .confirmation:
            beginFinalRevision(of: .tags)
        case .addBody:
            isAppendingBody = true
            move(to: .body, prompt: "追加する本文をどうぞ。")
        case .accept:
            return acceptReviewedValue()
        case .revise:
            return reviseCurrentValue()
        case .readAloud where state == .confirmation:
            readPostAloud()
        case .noURL where state == .referenceURL || state == .referenceURLReview:
            referenceURL = ""
            announce(
                to: .referenceURLReview,
                message: "参考URLを設定しました。",
                then: .beginTags
            )
        case .confirm:
            presentConfirmation()
        case .post where state == .confirmation:
            shouldPost = true
            statusMessage = "投稿を開始します。"
        default:
            return false
        }
        return true
    }

    private func move(to newState: HandsFreeState, prompt: String) {
        voiceInput.stop()
        afterSpeechAction = nil
        state = newState
        traceRecorder.record(name: "state_changed", state: newState.rawValue)
        statusMessage = prompt
        speak(prompt)
    }

    private func announce(
        to newState: HandsFreeState,
        message: String,
        then action: AfterSpeechAction
    ) {
        voiceInput.stop()
        state = newState
        traceRecorder.record(name: "state_changed", state: newState.rawValue)
        statusMessage = message
        afterSpeechAction = action
        speak(message, thenListen: false)
    }

    private func beginReferenceURLStep() {
        if let url = MarkdownFormatter.referenceURL(
            from: UIPasteboard.general.string
        ) {
            referenceURL = url.absoluteString
            announce(
                to: .referenceURLReview,
                message: "参考URLを設定しました。",
                then: .beginTags
            )
        } else {
            referenceURL = ""
            move(
                to: .referenceURL,
                prompt: "クリップボードにHTTPまたはHTTPSのURLがありません。参考URLを話すか、なし、と言ってください。"
            )
        }
    }

    private func acceptReviewedValue() -> Bool {
        switch state {
        case .titleReview:
            if completeFinalRevision(of: .title) { return true }
            transcriptRefiner.prewarm()
            move(to: .body, prompt: "本文をどうぞ。")
        case .bodyReview:
            if completeFinalRevision(of: .body) { return true }
            beginReferenceURLStep()
        case .referenceURLReview:
            move(to: .tags, prompt: "タグをどうぞ。タグなし、と言ってもかまいません。")
        case .tagsReview:
            if completeFinalRevision(of: .tags) { return true }
            presentConfirmation()
        default:
            return false
        }
        return true
    }

    private func beginFinalRevision(of scope: TranscriptChange.Scope) {
        finalRevisionScope = scope
        correctionChanges.removeAll { $0.scope == scope }

        switch scope {
        case .title:
            title = ""
            move(to: .title, prompt: "修正したタイトルをどうぞ。")
        case .body:
            isAppendingBody = false
            body = ""
            move(to: .body, prompt: "修正した本文をどうぞ。")
        case .tags:
            tags = []
            move(to: .tags, prompt: "修正したタグをどうぞ。")
        }
    }

    private func completeFinalRevision(of scope: TranscriptChange.Scope) -> Bool {
        guard finalRevisionScope == scope else { return false }
        finalRevisionScope = nil
        presentConfirmation()
        return true
    }

    private func reviseCurrentValue() -> Bool {
        switch state {
        case .titleReview:
            correctionChanges.removeAll { $0.scope == .title }
            title = ""
            move(to: .title, prompt: "修正したタイトルをどうぞ。")
        case .bodyReview:
            correctionChanges.removeAll { $0.scope == .body }
            isAppendingBody = false
            body = ""
            move(to: .body, prompt: "修正した本文をどうぞ。")
        case .referenceURLReview:
            referenceURL = ""
            move(to: .referenceURL, prompt: "修正した参考URLをどうぞ。ない場合は、なし、と言ってください。")
        case .tagsReview:
            correctionChanges.removeAll { $0.scope == .tags }
            tags = []
            move(to: .tags, prompt: "修正したタグをどうぞ。")
        default:
            return false
        }
        return true
    }

    private func presentConfirmation() {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            move(to: .title, prompt: "タイトルが空です。タイトルをどうぞ。")
            return
        }
        state = .confirmation
        traceRecorder.record(name: "state_changed", state: state.rawValue)
        statusMessage = "投稿内容を確認しました。投稿しますか？"
        speak(statusMessage)
    }

    private func readPostAloud() {
        let urlSummary = referenceURL.isEmpty ? "参考URLなし" : "参考URLあり"
        let tagSummary = tags.isEmpty ? "タグなし" : "タグ、\(tags.joined(separator: "、"))"
        let speechText = "タイトル。\(title)。本文。\(body)。\(urlSummary)。\(tagSummary)。"
        readAloudRequestID &+= 1
        traceRecorder.record(
            name: "read_aloud_requested",
            state: state.rawValue
        )
        let requestID = readAloudRequestID

        Task { @MainActor [weak self] in
            // Give GUIDE01 time to render the confirmation content before
            // speech starts.
            try? await Task.sleep(for: .milliseconds(800))
            guard let self,
                  self.state == .confirmation,
                  self.readAloudRequestID == requestID else { return }
            self.speak(speechText)
        }
    }

    private func speak(_ text: String, thenListen: Bool = true) {
        voiceInput.stop()
        synthesizer.stopSpeaking(at: .immediate)
        startsListeningAfterSpeech = thenListen
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(
            .playback,
            mode: .spokenAudio,
            options: [.duckOthers]
        )
        try? audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "ja-JP")
        utterance.rate = 0.48
        synthesizer.speak(utterance)
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            if let action = self.afterSpeechAction {
                self.afterSpeechAction = nil
                switch action {
                case .beginTags:
                    self.move(to: .tags, prompt: "タグをどうぞ。タグなし、と言ってもかまいません。")
                case .presentFinalConfirmation:
                    if self.finalRevisionScope == .tags {
                        self.finalRevisionScope = nil
                    }
                    self.presentConfirmation()
                }
                return
            }
            guard self.startsListeningAfterSpeech,
                  self.state != .posting,
                  self.state != .completed,
                  self.state != .idle else { return }
            self.startsListeningAfterSpeech = false
            let purpose = self.recognitionPurposeForCurrentState
            self.voiceInput.start(
                silenceTimeout: self.silenceTimeoutForCurrentState,
                immediatePhrases: purpose == .command ? self.commandPhrases : [],
                purpose: purpose
            )
        }
    }

    private var silenceTimeoutForCurrentState: TimeInterval {
        state == .body ? 10 : 5
    }

    private var recognitionPurposeForCurrentState: VoiceRecognitionPurpose {
        switch state {
        case .title, .body, .referenceURL, .tags:
            return .content
        default:
            return .command
        }
    }

    private var traceScope: String {
        switch state {
        case .title, .titleReview: "title"
        case .body, .bodyReview: "body"
        case .referenceURL, .referenceURLReview: "reference_url"
        case .tags, .tagsReview: "tags"
        default: "command"
        }
    }

    private var commandPhrases: Set<String> {
        [
                    "確定", "修正", "本文追加", "タイトルやり直し",
                    "タイトル修正", "本文修正", "タグ修正",
                    "URLなし", "なし", "確認", "読み上げ", "投稿", "キャンセル"
        ]
    }

    private func resetContent() {
        title = ""
        body = ""
        referenceURL = ""
        tags = []
        shouldPost = false
        isAppendingBody = false
        finalRevisionScope = nil
        titleWasAIRefined = false
        bodyWasAIRefined = false
        isRefiningTranscript = false
        correctionChanges = []
    }

    private func parseTags(_ transcript: String) -> [String] {
        let normalized = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if ["タグなし", "なし", "ありません"].contains(normalized) { return [] }
        return normalized
            .components(separatedBy: CharacterSet(charactersIn: "、,，\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func normalizedURL(_ transcript: String) -> String {
        transcript
            .replacingOccurrences(of: "エイチティーティーピーエス", with: "https")
            .replacingOccurrences(of: "エイチティーティーピー", with: "http")
            .replacingOccurrences(of: "コロン", with: ":")
            .replacingOccurrences(of: "スラッシュ", with: "/")
            .replacingOccurrences(of: "ドット", with: ".")
            .replacingOccurrences(of: " ", with: "")
    }
}

private enum AfterSpeechAction {
    case beginTags
    case presentFinalConfirmation
}
