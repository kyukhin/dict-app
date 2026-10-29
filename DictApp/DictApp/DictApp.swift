// DictApp.swift
// App entry point. Opens the user database, with the bundled dictionary file
// attached, before showing UI (Issue #138).

import SwiftUI

@main
struct DictApp: App {
    @State private var isReady = false
    @State private var setupError: String?
    // One database initialization per app, not per window (PR #116 review).
    @State private var databaseInitStarted = false
    @StateObject private var localization = LocalizationManager.shared

    // Issue #12: cumulative active-foreground time feeds the review-prompt
    // heuristic. The service tracks the active-interval start itself (and counts
    // the in-progress interval live), so we only forward scene-phase edges.
    @Environment(\.scenePhase) private var scenePhase

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
                // Launch begins an .active interval; onChange only fires on
                // *transitions*, so the initial foreground is started here.
                ReviewRequestService.shared.foregroundDidBecomeActive()
                await initializeDatabase()
            }
            // Issue #12: forward scene-phase edges so the service accumulates
            // only `.active` time (it banks the interval on resign and counts
            // the running interval live).
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    ReviewRequestService.shared.foregroundDidBecomeActive()
                } else {
                    ReviewRequestService.shared.foregroundDidResignActive()
                }
                // Issue #5: reset Reading Mode on real backgrounding only.
                if newPhase == .background {
                    ReadingModeService.shared.sceneDidEnterBackground()
                }
            }
        }
    }

    /// Issue #138: opening the user database (the dictionary file is
    /// attached, nothing is unpacked) and migrating it takes milliseconds,
    /// so Search is ready with every dictionary when the UI shows.
    private func initializeDatabase() async {
        // `.task` runs once per scene: a second iPad window must not reopen the
        // pool. The window shares `isReady` / `setupError`, so it simply waits
        // for them.
        guard !databaseInitStarted else { return }
        databaseInitStarted = true
        do {
            #if DEBUG
            // UI-test hook: a deterministic fresh install without uninstalling.
            // Also deletes a 1.x database, so no legacy data comes back (#139).
            if CommandLine.arguments.contains("-resetDatabase") {
                DatabaseService.removeDatabaseFiles()
            }
            #endif
            try await DatabaseService.shared.setup()

            #if DEBUG
            // UI-test hooks. Release builds ignore these launch arguments.
            if CommandLine.arguments.contains("-resetData") {
                try await DatabaseService.shared.clearMyWords()
                try await DatabaseService.shared.clearHistory()
                // Reset per-source enable/disable preference to first-launch default.
                SettingsService.shared.enabledSources = nil
                // Issue #74: also drop the persisted dictionary order so the
                // UI-language default is re-derived on this launch (a prior
                // reorder test would otherwise pin the order for the whole sim
                // install). `SettingsViewModel` is created after `isReady`, so
                // this runs before the first `loadDictionaries()`.
                SettingsService.shared.dictionaryOrder = nil
                // Issue #12: clear review-prompt counters so UI-test runs start
                // clean (they persist across launches and would otherwise
                // accumulate past the threshold mid-suite).
                ReviewRequestService.shared.resetPersistedState()
            }

            // UI-test hook: scrub the rows and the `imported_sources` row left
            // over from a previous fixture import. The import end-to-end tests
            // assert "no results before import" as a pre-condition, which would
            // spuriously fail if a prior run left fixture entries behind in
            // the persistent DB.
            if CommandLine.arguments.contains("-clearFixtureImports") {
                try? await DatabaseService.shared.clearEntries(fromSource: "test_import_fixture")
            }
            #endif

            // Issue #92: migrate per-source prefs to the pair invariants
            // (enabled-if-any, contiguous pair members) before the first search
            // can read them. Runs after the `-resetData` block (nil / nil is a
            // no-op). The bundled sources from `dict.dict_metadata` are enough:
            // custom imports are singleton pairs and never need sibling
            // expansion, and this avoids a full `entries` scan at launch.
            let knownSources = try await DatabaseService.shared.fetchMetadata().map(\.source)
            SettingsService.shared.normalizeDictionaryPreferences(knownSources: knownSources)

            isReady = true
        } catch {
            setupError = error.localizedDescription
        }
    }
}
