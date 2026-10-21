import XCTest

/// UI coverage for Issue #88: the app presents a fully localized **Greek**
/// interface. Tabs are reached through `app.tabButton(_:)`: by index in a tab
/// bar (Search 0, History 1, Bookmarks 2, Settings 3; Greek is LTR), by SF
/// Symbol on the iPadOS 26 tab strip, as in `SpanishLocalizationTests`.
///
/// Launch path: `-AppleLanguages (el) -resetData`. `-resetData` drops any
/// persisted in-app language inside `LocalizationManager.init` (#74), so the
/// device language decides and the launch is deterministic. With the process
/// language Greek, system chrome (search Cancel, back buttons) is Greek too,
/// so the English leak sweep covers it. Only `testLanguagePickerOffersGreek`
/// persists a language, and it restores English in a teardown block.
///
/// - No `TabBarPage.tap*Tab` (each tap checks the Greek label and title here)
///   and no `SearchPage` helpers that match English system labels.
/// - Section headers are matched after folding case, accents and final sigma:
///   iOS uppercases grouped-list headers and Greek uppercase drops the tonos.
/// - Screenshots of every main screen are attached (`.keepAlways`) for the
///   truncation / overlap review.
final class GreekLocalizationTests: XCTestCase {

    private var app: XCUIApplication!

    /// Pinned Greek tab labels (DESIGN_DOC.md §4b).
    enum GreekTab {
        static let search = "Αναζήτηση"
        static let history = "Ιστορικό"
        static let bookmarks = "Σελιδοδείκτες"
        static let settings = "Ρυθμίσεις"
    }

    /// The shared tabs (index 0–3); Greek labels and titles in the extension
    /// at the end of this file.
    private typealias Tab = TabBarPage.Tab

    /// English UI values of the screens under test (en catalog), plus the
    /// system words a Greek process must not show. Compared case-insensitively
    /// and exactly, so a gloss such as "dog" never trips it.
    private static let englishDenylist: Set<String> = [
        "search", "history", "bookmarks", "settings", "dictionary", "recent", "search words...",
        "interface language", "language", "result sorting", "sort by", "relevance", "preferred dictionary first",
        "dictionaries", "dictionary order", "manage dictionaries", "about", "offline dictionary",
        "learning mode", "coming soon", "support", "report a bug", "write a review", "credits", "version",
        "no history", "no bookmarks", "clear", "direction", "source id", "entries", "license",
        "turn on reading mode", "turn off reading mode", "speak word", "add bookmark", "remove bookmark",
        "loading dictionary...", "loading…", "back", "cancel", "greek – english",
    ]

    /// An untranslated key rendering as itself (`settings.title`,
    /// `dictionary.entries.count 5`).
    private static let rawKeyPattern = try? NSRegularExpression(pattern: #"^[a-z][A-Za-z]*(\.[A-Za-z]+)+( .*)?$"#)

    /// "147.229" / "1.234": `el` groups thousands with a dot.
    private static let greekGroupedNumber = #"\d{1,3}(\.\d{3})+"#

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments.append("-disableReviewPrompt")
        app.launchArguments.append("-resetData")
        app.launchArguments += ["-AppleLanguages", "(el)"]
        app.launchArguments += ["-AppleLocale", "el"]
        // The Greek (i) detail carries two ~9 KB Apache texts: silence the
        // app's os_log so XCTest's log volume cannot crash it (iOS 17.5).
        app.launchEnvironment["OS_ACTIVITY_MODE"] = "disable"

        // iOS 26 "Enable Dictation?" alert: dismiss instead of XCUI's default
        // (which opens a blocking privacy sheet). Springboard alerts follow the
        // device language; in-app ones follow Greek.
        addUIInterruptionMonitor(withDescription: "Enable Dictation alert") { alert in
            for label in ["Not Now", "Cancel", "Don't Enable", "Don't Allow",
                          "Όχι τώρα", "Ακύρωση", "Να μην επιτρέπεται", "Να μην ενεργοποιηθεί"] {
                let button = alert.buttons[label]
                if button.exists {
                    button.tap()
                    return true
                }
            }
            return false
        }

        // Sim orientation persists across sessions; landscape breaks swipes.
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        waitForColdSeed()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Tests

    /// AC1, AC2: the tab bar reads Αναζήτηση / Ιστορικό / Σελιδοδείκτες /
    /// Ρυθμίσεις in that order, and no English tab label is left.
    func testAppLaunchesInGreek() throws {
        for tab in Tab.allCases {
            let button = tabButton(tab)
            XCTAssertTrue(button.waitForExistence(timeout: TestData.Timeouts.long), "tab \(tab.rawValue) must exist")
            XCTAssertEqual(button.label, tab.greekLabel, "tab \(tab.rawValue) must read its Greek label")
        }
        let gone = NSPredicate(format: "exists == FALSE")
        for english in ["Search", "History", "Bookmarks", "Settings"] {
            expectation(for: gone, evaluatedWith: app.tabButton(labeled: english), handler: nil)
        }
        waitForExpectations(timeout: TestData.Timeouts.medium) { error in
            XCTAssertNil(error, "English tab labels must not appear in the Greek UI")
        }
        XCTAssertTrue(app.navigationBars["Λεξικό"].waitForExistence(timeout: TestData.Timeouts.medium),
                      "the app opens on the Search tab, titled 'Λεξικό'")
    }

    /// AC1, picker path: five options with their native names, Greek checked;
    /// switching to English and back flips the whole UI each way.
    func testLanguagePickerOffersGreek() throws {
        // This test persists a language: leave English behind for other suites.
        addTeardownBlock {
            let cleanup = XCUIApplication()
            cleanup.launchArguments += ["-disableReviewPrompt", "-resetData", "-AppleLanguages", "(en)"]
            cleanup.launch()
            cleanup.terminate()
        }

        openLanguagePicker()
        XCTAssertTrue(app.navigationBars["Γλώσσα"].waitForExistence(timeout: TestData.Timeouts.medium),
                      "picker title is 'Γλώσσα'")
        // Localized name (in Greek) + native name per option.
        let expected: [(code: String, greekName: String, nativeName: String)] = [
            ("en", "Αγγλικά", "English"), ("ru", "Ρωσικά", "Русский"), ("es", "Ισπανικά", "Español"),
            ("ar", "Αραβικά", "العربية"), ("el", "Ελληνικά", "Ελληνικά"),
        ]
        var previousY = -CGFloat.infinity
        for row in expected {
            let option = languageOption(row.code)
            XCTAssertTrue(option.waitForExistence(timeout: TestData.Timeouts.medium), "picker must offer '\(row.code)'")
            let texts = option.staticTexts.allElementsBoundByIndex.map(\.label)
            XCTAssertTrue(texts.contains(row.greekName) || option.label.contains(row.greekName),
                          "'\(row.code)' must show its Greek name '\(row.greekName)'; got \(texts) / '\(option.label)'")
            XCTAssertTrue(texts.contains(row.nativeName) || option.label.contains(row.nativeName),
                          "'\(row.code)' must show its native name '\(row.nativeName)'")
            XCTAssertGreaterThan(option.frame.minY, previousY, "options follow the manifest order")
            previousY = option.frame.minY
        }
        attachScreenshot("10-language-picker")
        try assertNoEnglishLeak(on: "language picker")

        // Re-picking the current language only pops back: no rebuild, the UI
        // stays Greek and on the Settings tab.
        languageOption("el").tap()
        XCTAssertTrue(languageOption("el").waitForNonExistence(timeout: TestData.Timeouts.medium),
                      "re-picking Ελληνικά must close the picker")
        XCTAssertTrue(app.navigationBars[GreekTab.settings].waitForExistence(timeout: TestData.Timeouts.medium),
                      "and return to Settings, not to a rebuilt Search tab")
        XCTAssertEqual(tabButton(.settings).label, GreekTab.settings)
        openLanguagePicker()

        // Greek → English.
        languageOption("en").tap()
        XCTAssertTrue(tabButtonLabeled("Settings").waitForExistence(timeout: TestData.Timeouts.long),
                      "after picking English the tab bar must read 'Settings'")
        XCTAssertTrue(tabButtonLabeled(GreekTab.settings).waitForNonExistence(timeout: TestData.Timeouts.medium),
                      "'Ρυθμίσεις' must disappear in the English UI")

        // English → Greek: the root rebuilt (.id(code)), so reopen Settings.
        openLanguagePicker(expectingTitle: "Settings")
        languageOption("el").tap()
        XCTAssertTrue(tabButtonLabeled(GreekTab.settings).waitForExistence(timeout: TestData.Timeouts.long),
                      "after picking Ελληνικά the tab bar must read 'Ρυθμίσεις'")
        XCTAssertTrue(tabButtonLabeled("Settings").waitForNonExistence(timeout: TestData.Timeouts.medium),
                      "'Settings' must disappear in the Greek UI")
        for tab in Tab.allCases {
            XCTAssertEqual(tabButton(tab).label, tab.greekLabel)
        }
        openTab(.settings)
        let link = app.descendants(matching: .any)["ui_language_link"]
        XCTAssertTrue(app.scrollToElement(link), "language row must be reachable")
        XCTAssertTrue(link.label.contains("Ελληνικά") || link.staticTexts["Ελληνικά"].exists,
                      "the language row shows the Greek choice; got '\(link.label)'")
    }

    /// AC2: Settings title, rows, headers and footers in Greek, top to bottom,
    /// with the English / raw-key sweep at both ends.
    func testSettingsScreenIsLocalizedInGreek() throws {
        openTab(.settings)

        let link = app.descendants(matching: .any)["ui_language_link"]
        XCTAssertTrue(link.waitForExistence(timeout: TestData.Timeouts.medium))
        XCTAssertTrue(link.label.contains("Γλώσσα") || link.staticTexts["Γλώσσα"].exists,
                      "language row label 'Γλώσσα'; got '\(link.label)'")
        XCTAssertTrue(link.label.contains("Ελληνικά") || link.staticTexts["Ελληνικά"].exists,
                      "language row value 'Ελληνικά'; got '\(link.label)'")
        for header in ["Γλώσσα διεπαφής", "Ταξινόμηση αποτελεσμάτων", "Λεξικά"] {
            XCTAssertTrue(waitForText(header), "Settings must show the header '\(header)'")
        }
        XCTAssertTrue(waitForText("Ταξινόμηση κατά"), "sort row label")
        XCTAssertTrue(waitForText("Συνάφεια", matchingValues: true), "default sort mode reads 'Συνάφεια'")
        XCTAssertTrue(waitForText("Σειρά λεξικών"), "Dictionary order row")
        XCTAssertTrue(waitForText("Διαχείριση λεξικών"), "Manage dictionaries row")
        attachScreenshot("05-settings-top")
        try assertNoEnglishLeak(on: "Settings (top)")

        for text in ["Λειτουργία εκμάθησης", "Έρχεται σύντομα", "Υποστήριξη", "Αναφορά σφάλματος",
                     "Γράψτε μια κριτική", "Συντελεστές", "Πληροφορίες", "Λεξικό εκτός σύνδεσης", "Έκδοση"] {
            XCTAssertTrue(scrollAndFind(text), "Settings must show '\(text)'")
        }
        XCTAssertTrue(app.scrollToElement(app.descendants(matching: .any)["version_value"].firstMatch),
                      "the version row must be reachable")
        attachScreenshot("06-settings-bottom")
        try assertNoEnglishLeak(on: "Settings (bottom)")
    }

    /// #87 interplay, AC3: Greek pair first, titled "Ελληνικά – Αγγλικά",
    /// every caption a `.`-grouped "… λήμματα", (i) "Λεπτομέρειες: …".
    func testDictionaryOrderPutsGreekPairFirstWithGreekTitles() throws {
        openTab(.settings)
        let settings = SettingsPage(app: app)
        XCTAssertTrue(settings.openDictionaryOrder(), "Dictionary order must open")
        XCTAssertTrue(app.navigationBars["Σειρά λεξικών"].waitForExistence(timeout: TestData.Timeouts.medium))

        let greek = TestData.Pairs.greek
        let greekRow = app.staticTexts[AccessibilityIdentifiers.Settings.dictionaryOrderRow(pair: greek)].firstMatch
        XCTAssertTrue(greekRow.waitForExistence(timeout: TestData.Timeouts.long))
        XCTAssertEqual(settings.currentOrder(of: TestData.Pairs.all).first, greek,
                       "a fresh Greek install lists the Greek pair first")

        let titles: [String: String] = [
            TestData.Pairs.greek: "Ελληνικά – Αγγλικά", TestData.Pairs.english: "Αγγλικά",
            TestData.Pairs.russian: "Ρωσικά – Αγγλικά", TestData.Pairs.spanish: "Ισπανικά – Αγγλικά",
            TestData.Pairs.arabic: "Αραβικά – Αγγλικά",
        ]
        let captions = try orderRowCaptions()
        for pair in TestData.Pairs.all {
            let row = app.staticTexts[AccessibilityIdentifiers.Settings.dictionaryOrderRow(pair: pair)].firstMatch
            XCTAssertTrue(app.scrollToElement(row), "row '\(pair)' must be reachable")
            XCTAssertEqual(row.label, titles[pair], "row '\(pair)' title")
            let caption = try XCTUnwrap(captions[pair], "row '\(pair)' has no caption")
            XCTAssertNotNil(caption.range(of: "^\(Self.greekGroupedNumber) λήμματα$", options: .regularExpression),
                            "row '\(pair)' caption must be a '.'-grouped Greek count; got '\(caption)'")
        }
        XCTAssertTrue(app.scrollToElement(greekRow))
        let info = app.buttons[AccessibilityIdentifiers.Settings.dictionaryInfoButton(pair: greek)].firstMatch
        XCTAssertTrue(info.waitForExistence(timeout: TestData.Timeouts.medium))
        XCTAssertEqual(info.label, "Λεπτομέρειες: Ελληνικά – Αγγλικά")
        attachScreenshot("03-dictionary-order")
        try assertNoEnglishLeak(on: "Dictionary order")
    }

    /// AC2, AC3: the (i) detail of `ell-eng` — Greek title, directions and row
    /// labels, `.`-grouped entry counts, untranslated brand headers.
    func testGreekPairInfoDetailIsLocalized() throws {
        openTab(.settings)
        let page = SettingsPage(app: app).openInfo(pair: TestData.Pairs.greek)
        XCTAssertTrue(page.view.exists, "(i) must push the info detail")
        XCTAssertTrue(app.navigationBars["Ελληνικά – Αγγλικά"].waitForExistence(timeout: TestData.Timeouts.medium))

        let ids = AccessibilityIdentifiers.DictionaryInfo.self
        XCTAssertEqual(page.element(ids.sourceHeader(TestData.Sources.freedictEllEng)).label, "FreeDict",
                       "brand headers are not translated")
        XCTAssertEqual(page.element(ids.direction(TestData.Sources.freedictEllEng)).label, "Ελληνικά → Αγγλικά")
        for label in ["Κατεύθυνση", "Αναγνωριστικό πηγής", "Έκδοση", "Λήμματα"] {
            XCTAssertTrue(waitForText(label), "the detail must show the row label '\(label)'")
        }
        attachScreenshot("04-greek-pair-info")
        try assertNoEnglishLeak(on: "(i) detail", skippingIdentifierPrefixes: [
            "dictionary_info_license_", "dictionary_info_version_", "dictionary_info_source_id_",
        ])

        let expected: [(source: String, brand: String, direction: String)] = [
            (TestData.Sources.freedictEllEng, "FreeDict", "Ελληνικά → Αγγλικά"),
            (TestData.Sources.wordnetEllEng, "WordNet", "Ελληνικά → Αγγλικά"),
            (TestData.Sources.freedictEngEll, "FreeDict", "Αγγλικά → Ελληνικά"),
            (TestData.Sources.wordnetEngEll, "WordNet", "Αγγλικά → Ελληνικά"),
        ]
        for block in expected {
            XCTAssertTrue(page.revealElement(ids.sourceHeader(block.source)), "block for \(block.source)")
            XCTAssertEqual(page.element(ids.sourceHeader(block.source)).label, block.brand)
            XCTAssertTrue(page.revealElement(ids.direction(block.source)))
            XCTAssertEqual(page.element(ids.direction(block.source)).label, block.direction, block.source)
            XCTAssertTrue(page.revealElement(ids.entries(block.source)))
            let entries = page.element(ids.entries(block.source)).label
            XCTAssertNotNil(entries.range(of: "^\(Self.greekGroupedNumber)$", options: .regularExpression),
                            "\(block.source) entries must be '.'-grouped (all Greek sources exceed 999); got '\(entries)'")
            XCTAssertTrue(page.revealElement(ids.license(block.source)), "\(block.source) license")
            // A long license's label row can sit above the fold once its body is centred.
            XCTAssertTrue(waitForText("Άδεια χρήσης", onScreenOnly: false, timeout: TestData.Timeouts.short),
                          "the license row is labeled 'Άδεια χρήσης'")
        }
    }

    /// AC2: Search root, the empty History and Bookmarks, a Greek search for
    /// "σκύλος", its definition, then History and Bookmarks listing it.
    func testSearchHistoryBookmarksAreLocalizedInGreek() throws {
        // Search root.
        XCTAssertTrue(app.navigationBars["Λεξικό"].waitForExistence(timeout: TestData.Timeouts.long))
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: TestData.Timeouts.long))
        XCTAssertEqual(field.placeholderValue, "Αναζήτηση λέξεων…")
        let readingMode = app.buttons[AccessibilityIdentifiers.ReadingMode.toggle].firstMatch
        XCTAssertTrue(readingMode.waitForExistence(timeout: TestData.Timeouts.medium))
        XCTAssertEqual(readingMode.label, "Ενεργοποίηση λειτουργίας ανάγνωσης")
        try assertNoEnglishLeak(on: "Search root")

        // Empty states (-resetData cleared both).
        openTab(.history)
        XCTAssertTrue(waitForText("Χωρίς ιστορικό"), "History empty title")
        XCTAssertTrue(waitForText("Οι λέξεις που αναζητάτε θα εμφανίζονται εδώ."), "History empty description")
        attachScreenshot("07a-history-empty")
        try assertNoEnglishLeak(on: "History (empty)")
        openTab(.bookmarks)
        XCTAssertTrue(waitForText("Χωρίς σελιδοδείκτες"), "Bookmarks empty title")
        XCTAssertTrue(waitForText("Προσθέστε λέξεις στους σελιδοδείκτες για να τις αποθηκεύσετε εδώ."),
                      "Bookmarks empty description")
        attachScreenshot("08a-bookmarks-empty")
        try assertNoEnglishLeak(on: "Bookmarks (empty)")

        // Greek search.
        openTab(.search)
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: TestData.Timeouts.long))
        search.tap()
        dismissSiriPrivacyNoticeIfPresent()
        app.searchFields.firstMatch.typeText("σκύλος")
        let typed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "σκύλος"),
                                              object: app.searchFields.firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [typed], timeout: TestData.Timeouts.medium), .completed,
                       "search field must contain the typed term (hardware keyboard must be off)")
        let results = app.collectionViews.firstMatch
        let greekCell = results.cells
            .containing(.any, identifier: AccessibilityIdentifiers.Search.sourceBadge(source: TestData.Sources.freedictEllEng))
            .containing(NSPredicate(format: "label == %@", "σκύλος"))
            .firstMatch
        XCTAssertTrue(greekCell.waitForExistence(timeout: TestData.Timeouts.long),
                      "'σκύλος' must list the FreeDict Greek → English entry")
        let badge = greekCell.descendants(matching: .any)[
            AccessibilityIdentifiers.Search.sourceBadge(source: TestData.Sources.freedictEllEng)].firstMatch
        XCTAssertEqual(badge.label, "Ελληνικά προς Αγγλικά, FreeDict", "badge VoiceOver label is Greek")
        dismissKeyboardIfPresent()
        attachScreenshot("01-search-results-skylos")

        // Definition.
        greekCell.tap()
        let definition = app.descendants(matching: .any)[AccessibilityIdentifiers.Definition.definitionView].firstMatch
        XCTAssertTrue(definition.waitForExistence(timeout: TestData.Timeouts.long), "definition must open")
        XCTAssertTrue(app.navigationBars["σκύλος"].waitForExistence(timeout: TestData.Timeouts.medium))
        XCTAssertTrue(definition.buttons["Εκφώνηση λέξης"].waitForExistence(timeout: TestData.Timeouts.medium),
                      "speaker button is labeled 'Εκφώνηση λέξης'")
        let bookmark = app.buttons[AccessibilityIdentifiers.Definition.bookmarkButton].firstMatch
        XCTAssertTrue(bookmark.waitForExistence(timeout: TestData.Timeouts.medium))
        XCTAssertEqual(bookmark.label, "Προσθήκη σελιδοδείκτη")
        let content = app.descendants(matching: .any)[AccessibilityIdentifiers.Definition.definitionContent].firstMatch
        XCTAssertTrue(content.label.contains("dog"), "definition shows the English gloss; got '\(content.label.prefix(80))'")
        attachScreenshot("02-definition-skylos")
        try assertNoEnglishLeak(on: "Definition", skippingIdentifierPrefixes: ["definition_content"])
        bookmark.tap()
        XCTAssertTrue(waitForLabel(of: bookmark, toBe: "Αφαίρεση σελιδοδείκτη"),
                      "after bookmarking the button reads 'Αφαίρεση σελιδοδείκτη'; got '\(bookmark.label)'")

        // History lists the lookup.
        openTab(.history)
        let historyItem = app.descendants(matching: .any)[AccessibilityIdentifiers.History.historyItem(word: "σκύλος")].firstMatch
        XCTAssertTrue(historyItem.waitForExistence(timeout: TestData.Timeouts.long), "History must list σκύλος")
        XCTAssertTrue(app.navigationBars["Ιστορικό"].buttons["Εκκαθάριση"].waitForExistence(timeout: TestData.Timeouts.medium),
                      "History toolbar button reads 'Εκκαθάριση'")
        attachScreenshot("07-history")
        try assertNoEnglishLeak(on: "History", skippingCellContent: true)

        // Bookmarks lists the bookmark.
        openTab(.bookmarks)
        let list = app.descendants(matching: .any)[AccessibilityIdentifiers.Bookmarks.bookmarksList].firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: TestData.Timeouts.long), "Bookmarks must list the bookmark")
        XCTAssertTrue(list.staticTexts["σκύλος"].waitForExistence(timeout: TestData.Timeouts.medium))
        attachScreenshot("08-bookmarks")
        try assertNoEnglishLeak(on: "Bookmarks", skippingCellContent: true)
    }

    // MARK: - Launch

    /// The one launch wait. While the loading screen shows (a few ms since
    /// Issue #111) it must be Greek; captured once if seen. Then waits until
    /// every bundled dictionary is unpacked, before any search or count.
    private func waitForColdSeed() {
        let tabBar = app.tabButton(.search)
        let greekLoading = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Φόρτωση λεξικού…")).firstMatch
        let englishLoading = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Loading dictionary...")).firstMatch
        let deadline = Date().addingTimeInterval(TabBarPage.coldSeedTimeout)
        var capturedLoading = false
        while !tabBar.exists && Date() < deadline {
            XCTAssertFalse(englishLoading.exists, "the cold-seed screen must not read 'Loading dictionary...'")
            if !capturedLoading && greekLoading.exists {
                capturedLoading = true
                attachScreenshot("00-loading")
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertTrue(tabBar.waitForExistence(timeout: 1), "tab bar after the cold seed")
        XCTAssertTrue(app.waitForDictionariesReady(),
                      "Search screen with every dictionary unpacked after launch")
    }

    // MARK: - Navigation

    private func tabButton(_ tab: Tab) -> XCUIElement {
        app.tabButton(tab)
    }

    private func tabButtonLabeled(_ label: String) -> XCUIElement {
        app.tabButton(labeled: label)
    }

    /// Taps a tab after checking its Greek label, then waits for its Greek
    /// root title. Coordinate tap (iOS 26 `scrollToVisible` failure, and the
    /// iPadOS 26 tab strip); on an iPad tab bar an element tap once the
    /// keyboard is gone (#76).
    private func openTab(_ tab: Tab, file: StaticString = #filePath, line: UInt = #line) {
        let button = tabButton(tab)
        XCTAssertTrue(button.waitForExistence(timeout: TestData.Timeouts.long), "tab \(tab.rawValue)", file: file, line: line)
        XCTAssertEqual(button.label, tab.greekLabel, "tab \(tab.rawValue) label", file: file, line: line)
        dismissKeyboardIfPresent()
        if UIDevice.current.userInterfaceIdiom == .pad && !app.usesFloatingTabStrip && button.isHittable {
            button.tap()
        } else {
            button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        XCTAssertTrue(app.navigationBars[tab.greekTitle].waitForExistence(timeout: TestData.Timeouts.long),
                      "tab \(tab.rawValue) root must be titled '\(tab.greekTitle)'", file: file, line: line)
    }

    /// Settings → language row → picker.
    private func openLanguagePicker(expectingTitle title: String = GreekTab.settings) {
        let settings = app.tabButton(.settings)
        XCTAssertTrue(settings.waitForExistence(timeout: TestData.Timeouts.long))
        settings.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: TestData.Timeouts.long), "Settings '\(title)'")
        let link = app.descendants(matching: .any)["ui_language_link"]
        XCTAssertTrue(app.scrollToElement(link), "language row must be reachable")
        link.tap()
        XCTAssertTrue(languageOption("el").waitForExistence(timeout: TestData.Timeouts.medium), "picker must open")
    }

    private func languageOption(_ code: String) -> XCUIElement {
        app.descendants(matching: .any)["ui_language_option_\(code)"].firstMatch
    }

    /// Hides the software keyboard (it covers the tab bar). Key labels follow
    /// the process language, so try Greek and English, then a list drag.
    private func dismissKeyboardIfPresent() {
        let keyboard = app.keyboards.firstMatch
        guard keyboard.exists else { return }
        for label in ["Αναζήτηση", "αναζήτηση", "Search", "search", "Απόκρυψη πληκτρολογίου", "Hide keyboard"] {
            let key = keyboard.buttons[label]
            if key.exists {
                key.tap()
                if keyboard.waitForNonExistence(timeout: TestData.Timeouts.short) { return }
            }
        }
        app.collectionViews.firstMatch.swipeDown()
        _ = keyboard.waitForNonExistence(timeout: TestData.Timeouts.short)
    }

    /// iOS 26 first-run "Siri, Dictation & Privacy" sheet over `.searchable`;
    /// its title is system-localized, so match the "Siri" prefix.
    private func dismissSiriPrivacyNoticeIfPresent() {
        let sheet = app.navigationBars.matching(
            NSPredicate(format: "identifier BEGINSWITH 'Siri' OR label BEGINSWITH 'Siri'")).firstMatch
        if sheet.waitForExistence(timeout: 1.0), sheet.buttons.firstMatch.exists {
            sheet.buttons.firstMatch.tap()
        }
    }

    // MARK: - Text checks

    /// Case-, accent- and final-sigma-insensitive form: iOS uppercases section
    /// headers and Greek uppercase drops the tonos ("ΓΛΩΣΣΑ ΔΙΕΠΑΦΗΣ").
    private static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "el"))
            .replacingOccurrences(of: "ς", with: "σ")
    }

    private struct SeenElement {
        let type: XCUIElement.ElementType
        let label: String
        let value: String
        let identifier: String
    }

    /// One AX snapshot of the app's elements (keyboard excluded), by default
    /// only those on screen. Subtrees whose identifier starts with a skipped
    /// prefix are dropped, as is cell content when asked.
    private func onScreenElements(onScreenOnly: Bool = true, skippingCellContent: Bool = false,
                                  skippingIdentifierPrefixes: [String] = []) throws -> [SeenElement] {
        let root = try app.snapshot()
        let screen = root.frame
        var seen: [SeenElement] = []
        func walk(_ node: XCUIElementSnapshot, inCell: Bool) {
            if node.elementType == .keyboard { return }
            if skippingIdentifierPrefixes.contains(where: { node.identifier.hasPrefix($0) }) { return }
            let isCell = node.elementType == .cell
            let visible = node.frame.width > 1 && node.frame.height > 1 && screen.intersects(node.frame)
            if visible || !onScreenOnly, !(skippingCellContent && (inCell || isCell)) {
                seen.append(SeenElement(type: node.elementType, label: node.label,
                                        value: (node.value as? String) ?? "", identifier: node.identifier))
            }
            for child in node.children { walk(child, inCell: inCell || isCell) }
        }
        walk(root, inCell: false)
        return seen
    }

    /// Polls the screen for an element whose folded label (or value) equals
    /// the folded `text`.
    private func waitForText(_ text: String, matchingValues: Bool = false, onScreenOnly: Bool = true,
                             timeout: TimeInterval = TestData.Timeouts.medium) -> Bool {
        let needle = Self.fold(text)
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let elements = (try? onScreenElements(onScreenOnly: onScreenOnly)) ?? []
            if elements.contains(where: { Self.fold($0.label) == needle || (matchingValues && Self.fold($0.value) == needle) }) {
                return true
            }
            Thread.sleep(forTimeInterval: 0.25)
        } while Date() < deadline
        return false
    }

    /// Finds `text` anywhere in the Settings form's AX tree, swiping down the
    /// form and then back up to materialise lazy rows (geometry only, never
    /// `isHittable`).
    private func scrollAndFind(_ text: String) -> Bool {
        if waitForText(text, onScreenOnly: false, timeout: 1) { return true }
        let form = app.collectionViews.firstMatch
        for _ in 0..<6 {
            form.swipeUp()
            if waitForText(text, onScreenOnly: false, timeout: 1) { return true }
        }
        for _ in 0..<8 {
            form.swipeDown()
            if waitForText(text, onScreenOnly: false, timeout: 1) { return true }
        }
        return false
    }

    private func waitForLabel(of element: XCUIElement, toBe label: String,
                              timeout: TimeInterval = TestData.Timeouts.medium) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Captions of the Dictionary order rows, keyed by pair: the cell that
    /// carries `dictionary_order_row_<pair>` and its other static text.
    private func orderRowCaptions() throws -> [String: String] {
        let root = try app.snapshot()
        var captions: [String: String] = [:]
        func texts(_ node: XCUIElementSnapshot) -> [XCUIElementSnapshot] {
            (node.elementType == .staticText ? [node] : []) + node.children.flatMap(texts)
        }
        func walk(_ node: XCUIElementSnapshot) {
            if node.elementType == .cell {
                let cellTexts = texts(node)
                let prefix = "dictionary_order_row_"
                if let title = cellTexts.first(where: { $0.identifier.hasPrefix(prefix) }) {
                    let pair = String(title.identifier.dropFirst(prefix.count))
                    captions[pair] = cellTexts.first { !$0.identifier.hasPrefix(prefix) && !$0.label.isEmpty }?.label
                }
                return
            }
            node.children.forEach(walk)
        }
        walk(root)
        return captions
    }

    /// AC2 sweep: no on-screen label equals an English UI value (or starts
    /// with "Details for "), and none renders a raw catalog key.
    private func assertNoEnglishLeak(on screen: String, skippingCellContent: Bool = false,
                                     skippingIdentifierPrefixes: [String] = [],
                                     file: StaticString = #filePath, line: UInt = #line) throws {
        let elements = try onScreenElements(skippingCellContent: skippingCellContent,
                                            skippingIdentifierPrefixes: skippingIdentifierPrefixes)
        XCTAssertFalse(elements.isEmpty, "\(screen): nothing on screen to sweep", file: file, line: line)
        let swept: [XCUIElement.ElementType] = [.staticText, .button, .navigationBar, .cell]
        for element in elements where !element.label.isEmpty && swept.contains(element.type) {
            let label = element.label.trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertFalse(Self.englishDenylist.contains(label.lowercased()),
                           "\(screen): English UI text '\(label)' (\(element.identifier))", file: file, line: line)
            XCTAssertFalse(label.hasPrefix("Details for "), "\(screen): English (i) label '\(label)'", file: file, line: line)
            let range = NSRange(label.startIndex..., in: label)
            XCTAssertNil(Self.rawKeyPattern?.firstMatch(in: label, range: range),
                         "\(screen): raw catalog key '\(label)' (\(element.identifier))", file: file, line: line)
        }
    }

    // MARK: - Screenshots

    /// Lets transitions settle, then attaches a full-screen capture.
    private func attachScreenshot(_ name: String) {
        Thread.sleep(forTimeInterval: 0.8)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "el-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private extension TabBarPage.Tab {
    var greekLabel: String {
        typealias Labels = GreekLocalizationTests.GreekTab
        return [Labels.search, Labels.history, Labels.bookmarks, Labels.settings][rawValue]
    }

    /// Navigation title of the tab's root screen.
    var greekTitle: String {
        ["Λεξικό", "Ιστορικό", "Σελιδοδείκτες", "Ρυθμίσεις"][rawValue]
    }
}
