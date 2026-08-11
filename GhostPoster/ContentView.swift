import SwiftUI

struct ContentView: View {
    @StateObject private var settings = GhostSettings()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showsHandsFree = false

    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    DraftPreviewView(settings: settings)
                } label: {
                    Label("投稿テスト", systemImage: "doc.text")
                }

                NavigationLink {
                    HandsFreePostingView(settings: settings)
                } label: {
                    Label("ハンズフリー投稿", systemImage: "waveform")
                }

                NavigationLink {
                    SettingsView(settings: settings)
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
            .navigationTitle("GhostPoster")
            .navigationDestination(isPresented: $showsHandsFree) {
                HandsFreePostingView(settings: settings, startsAutomatically: true)
            }
            .task {
                await openHandsFreeIfRequestedWithRetries()
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: HandsFreeLaunchRequest.notification
                )
            ) { _ in
                openHandsFreeIfRequested()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task {
                        await openHandsFreeIfRequestedWithRetries()
                    }
                }
            }
        }
    }

    private func openHandsFreeIfRequested() {
        guard HandsFreeLaunchRequest.consume() else { return }
        showsHandsFree = true
    }

    /// App Intentの実行完了とアプリのactive化は順序が保証されないため、
    /// 起動直後だけ短時間再確認して画面遷移要求の取りこぼしを防ぎます。
    private func openHandsFreeIfRequestedWithRetries() async {
        for delay in [0, 200_000_000, 600_000_000, 1_200_000_000] as [UInt64] {
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }
            guard !Task.isCancelled else { return }
            if HandsFreeLaunchRequest.consume() {
                showsHandsFree = true
                return
            }
        }
    }
}
