import SwiftUI

struct VoiceInputButton: View {
    let isRecording: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isRecording ? "stop.circle.fill" : "mic.circle.fill")
                .font(.title2)
                .foregroundStyle(isRecording ? Color.red : Color.accentColor)
                .accessibilityLabel(isRecording ? "音声入力を停止" : "音声入力を開始")
        }
        .buttonStyle(.plain)
    }
}
