// DictApp.swift
// App entry point. Opens the user database, with the bundled dictionary file
// attached, before showing UI (Issue #138).

import SwiftUI
import UserNotifications

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

    init() {
        // 0131, #162: a reminder's tap opens the Learn tab. Set before
        // launch ends, so a tap that launches the app is not lost.
        UNUserNotificationCenter.current().delegate = NotificationTapHandler.shared
    }

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
                // 0131, #162: the reminders follow today's goal and the
                // week ahead on every return to the foreground.
                if newPhase == .active, isReady {
                    Task { await LearningReminder.shared.reschedule() }
                }
            }
        }
    }

    /// Issue #138: opening the user database (the dictionary file is
    /// attached, nothing is unpacked) and migrating it takes milliseconds,
    /// so Search is ready with every dictionary when the UI shows. A 1.x
    /// database moves in the background (Issue #139). Issue #237: then a
    /// scan of the packs folder picks each language pack's file, which is
    /// attached next to the bundle (0237, "Launch").
    private func initializeDatabase() async {
        // `.task` runs once per scene: a second iPad window must not reopen the
        // pool. The window shares `isReady` / `setupError`, so it simply waits
        // for them.
        guard !databaseInitStarted else { return }
        databaseInitStarted = true
        do {
            #if DEBUG
            // UI-test hook: a deterministic fresh install without uninstalling.
            // Also deletes a 1.x database, so no legacy data moves in (#139).
            if CommandLine.arguments.contains("-resetDatabase") {
                DatabaseService.removeDatabaseFiles()
            }
            // Issue #237: no pack installed, no download in progress.
            if CommandLine.arguments.contains("-resetPacks") {
                PackFiles.removeAll()
            }
            // Issue #244: a 1.x install about to update. The fixture becomes
            // the 1.x database on an empty user database, and the keys 1.x
            // never wrote are cleared, so this launch moves it and offers
            // the packs of the dictionaries that were enabled.
            if let fixture = Self.argument(after: "-legacyFixture") {
                try DatabaseService.installLegacyFixture(URL(fileURLWithPath: fixture))
                SettingsService.shared.packsOffered = false
                SettingsService.shared.packsInstalled = []
            }
            #endif
            // Issue #237 (0237, "Launch"): the pool with the bundle and every
            // pack name on the stub, then the launch scan, which reads the
            // catalog through the pool and attaches the usable packs in one
            // re-attach before any reader is busy.
            try await DatabaseService.shared.setup()
            try await PackService.shared.prepare()

            #if DEBUG
            // UI-test hooks. Release builds ignore these launch arguments.
            if CommandLine.arguments.contains("-resetData") {
                try await DatabaseService.shared.clearMyWords()
                try await DatabaseService.shared.clearHistory()
                // 0130: imported word lists and the lists new words come
                // from. The install's shuffle seed stays.
                try await DatabaseService.shared.clearUserLists()
                SettingsService.shared.learningListIDs = []
                // 0131: the learning tables and the `learning_*` keys.
                try await DatabaseService.shared.clearLearning()
                SettingsService.shared.resetLearning()
                await LearningReminder.shared.removeAll()
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

            // 0131, Test seams: a learning fixture written after the reset,
            // which also sets its languages, each with its default via; or
            // the learned languages and their vias alone
            // (`-learningLanguages ell,eng:spa`), skipping the picker.
            if let name = Self.argument(after: "-learningFixture"),
               let languages = try await DatabaseService.shared.writeLearningFixture(name, today: LearningClock().today) {
                SettingsService.shared.learningLanguages = languages
                for lang in languages {
                    SettingsService.shared.learningVia[lang] = try await LearningLanguageService.shared.pair(for: lang)?.via
                }
            }
            if let argument = Self.argument(after: "-learningLanguages") {
                SettingsService.shared.setLearningLanguages(argument: argument)
            }
            // The lists new words come from (`-learningLists user-fixture-ell`),
            // until E3's New words from screen (#154) can check them.
            if let argument = Self.argument(after: "-learningLists") {
                SettingsService.shared.learningListIDs = Set(argument.split(separator: ",").map {
                    WordListID(rawValue: String($0))
                })
            }

            // UI-test hook: scrub the rows and the `imported_sources` row left
            // over from a previous fixture import. The import end-to-end tests
            // assert "no results before import" as a pre-condition, which would
            // spuriously fail if a prior run left fixture entries behind in
            // the persistent DB.
            if CommandLine.arguments.contains("-clearFixtureImports") {
                try? await DatabaseService.shared.clearEntries(fromSource: "test_import_fixture")
            }

            // Issue #237: the first-launch sheet does not show, of any kind
            // (#244: launch skips the offer below too).
            if CommandLine.arguments.contains("-skipWelcome") {
                SettingsService.shared.packsOffered = true
            }

            // Issue #242: every download is answered from the committed
            // assets (the `-packFixtures` folder, else the source tree's
            // `Packs/`), never the network, in a mode: ok, slow, offline,
            // failOnce, http404, corrupt, noSpace, expiredResume.
            if let mode = Self.argument(after: "-packDownloads").flatMap(PackFixtureURLProtocol.Mode.init(rawValue:)) {
                let assets = Self.argument(after: "-packFixtures").map { URL(fileURLWithPath: $0) }
                await PackService.shared.useFixtureDownloads(mode, assets: assets)
            }

            // Issue #237, last of the hooks: install packs from the committed
            // assets through the install path, with no network.
            if let packs = Self.argument(after: "-installPacks"), let assets = Self.argument(after: "-packFixtures") {
                try await PackService.shared.installFixtures(packs, from: URL(fileURLWithPath: assets))
            }
            #endif

            // Issue #92: migrate per-source prefs to the pair invariants
            // (enabled-if-any, contiguous pair members) before the first search
            // can read them. Runs after the `-resetData` block (nil / nil is a
            // no-op). The sources of `dict_metadata` are enough: custom
            // imports are singleton pairs and never need sibling expansion,
            // and this avoids a full `entries` scan at launch. Issue #237: the
            // installed dictionaries and the catalog's, so a pack that is not
            // installed keeps its place and switch.
            let installedSources = try await DatabaseService.shared.fetchMetadata().map(\.source)
            let catalogSources = PackCatalog.shared.sources.map(\.source)
            let knownSources = installedSources + catalogSources.filter { !installedSources.contains($0) }
            SettingsService.shared.normalizeDictionaryPreferences(knownSources: knownSources)

            // Issue #244: whether the first-launch sheet shows, and which
            // kind: decided before the 1.x move deletes its file and before
            // any screen stores a dictionary order. A failed read offers
            // nothing now; the next launch decides again.
            #if DEBUG
            let skipWelcome = CommandLine.arguments.contains("-skipWelcome")
            #else
            let skipWelcome = false
            #endif
            if !skipWelcome {
                let legacyFound = FileManager.default.fileExists(atPath: DatabaseService.legacyDatabaseURL().path)
                PackOffer.launchSheet = try? await PackOffer.atLaunch(legacyDatabaseFound: legacyFound)
            }

            // Issue #139: a 1.x database moves into the user database as a
            // detached utility task. Started just before the UI shows, so
            // every user-data call from the first frame waits for it (Search
            // does not), and on the pool opened above.
            await DatabaseService.shared.startLegacyMigration()

            isReady = true
            await LearningReminder.shared.reschedule()
        } catch {
            setupError = error.localizedDescription
        }
    }

    #if DEBUG
    /// The launch argument that follows `flag`, if any.
    private static func argument(after flag: String) -> String? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
    #endif
}
