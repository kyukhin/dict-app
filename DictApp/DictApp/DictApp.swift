// DictApp.swift
// App entry point. Sets up the database before showing UI.

import SwiftUI

@main
struct DictApp: App {
    @State private var isReady = false
    @State private var setupError: String?

    var body: some Scene {
        WindowGroup {
            Group {
                if isReady {
                    ContentView()
                } else if let error = setupError {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(.red)
                        Text("Database Error")
                            .font(.title2.bold())
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                } else {
                    ProgressView("Loading dictionary...")
                }
            }
            .task {
                await initializeDatabase()
            }
        }
    }

    private func initializeDatabase() async {
        do {
            try await DatabaseService.shared.setup()
            try await DatabaseService.shared.seedIfNeeded()

            // Check for test reset flag
            if CommandLine.arguments.contains("-resetData") {
                try await DatabaseService.shared.clearAllBookmarks()
                try await DatabaseService.shared.clearHistory()
                // Reset per-source enable/disable preference to first-launch default.
                SettingsService.shared.enabledSources = nil
            }

            isReady = true
        } catch {
            setupError = error.localizedDescription
        }
    }
}

