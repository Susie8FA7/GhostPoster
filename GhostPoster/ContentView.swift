import SwiftUI

struct ContentView: View {
    @StateObject private var settings = GhostSettings()

    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    DraftPreviewView(settings: settings)
                } label: {
                    Label("投稿テスト", systemImage: "doc.text")
                }

                NavigationLink {
                    SettingsView(settings: settings)
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
            .navigationTitle("GhostPoster")
        }
    }
}
