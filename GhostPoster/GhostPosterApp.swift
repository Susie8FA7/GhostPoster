//
//  GhostPosterApp.swift
//  GhostPoster
//
//

import AppIntents
import SwiftUI

@main
struct GhostPosterApp: App {
    init() {
        GhostPosterShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
