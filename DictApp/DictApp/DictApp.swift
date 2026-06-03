// DictApp.swift
// App entry point. Sets up the database before showing UI.

import SwiftUI

@main
struct DictApp: App {
    @State private var isReady = false
    @State private var setupError: String?
    @StateObject private var localization = LocalizationManager.shared

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
                        Text("error.database.title")
                            .font(.title2.bold())
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                } else {
                    ProgressView("app.loading")
                }
            }
            // Forces SwiftUI to rebuild the tree on language change so
            // already-rendered `Text` nodes re-resolve their catalog keys.
            // `\.locale` alone is not enough — SwiftUI caches localized
            // strings per view identity.
            .id(localization.currentLanguage.code)
            .environment(\.locale, localization.currentLocale)
            // SwiftUI's `\.layoutDirection` is not derived from `\.locale`,
            // so an in-app switch to an RTL language (Arabic) would otherwise
            // render RTL text in an LTR layout. Derive it from the active
            // language's character direction. `LocalizationManager` is
            // untouched; this is composition at the App root and the existing
            // `.id(...)` rebuild makes it apply instantly on a language switch.
            .environment(\.layoutDirection,
                         Locale.Language(identifier: localization.currentLanguage.code)
                             .characterDirection == .rightToLeft ? .rightToLeft : .leftToRight)
            .environmentObject(localization)
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

            // UI-test hook: scrub entries left over from a previous fixture
            // import. The import end-to-end tests assert "no results before
            // import" as a pre-condition, which would spuriously fail if a
            // prior run left fixture entries behind in the persistent DB.
            if CommandLine.arguments.contains("-clearFixtureImports") {
                try? await DatabaseService.shared.clearEntries(fromSource: "test_import_fixture")
            }

            isReady = true
        } catch {
            setupError = error.localizedDescription
        }
    }
}
