import XCTest

/// UI coverage for Issue #9: the app must present a fully localized **Arabic**
/// interface, mirror its layout right-to-left, and render mixed LTR/RTL content
/// (Latin + Arabic in one cell) correctly.
///
/// Launch strategy (differs from `SpanishLocalizationTests`):
///   * Arabic is driven via the `-AppleLanguages ("ar")` launch argument rather
///     than the in-app picker. This works on a fresh simulator (CI) because no
///     in-app UI language is persisted; on a developer device that previously
///     selected a different language in the picker, the persisted choice will
///     still win for the current launch — the same bleed the Spanish suite
///     documents (`LocalizationManager` snapshots the persisted language at
///     init, before any launch-time reset runs). Re-running locally after a
///     language switch may require a clean install.
///   * The mixed-script cell is exercised against a **real** `wordnet-arb-eng`
///     row (Issue #10 ships the Arabic dictionary), not a synthetic fixture:
///     searching a high-frequency English headword surfaces a result whose
///     definition mixes an Arabic translation with the English gloss.
///
/// Tab navigation is **by visible (Arabic) label**, never by index: under RTL
/// the tab order mirrors, so the index trick `SpanishLocalizationTests` relies
/// on is unsafe here (DESIGN_DOC.md §3). It is *not* by accessibility identifier
/// either — the `*_tab` identifiers sit on each tab's content container, not on
/// the tab-bar button (same reality `SpanishLocalizationTests` documents), so a
/// `tabBar.buttons["settings_tab"]` lookup resolves nothing. The localized label
/// is the order-independent, RTL-safe handle the buttons actually expose.
///
/// `tearDown` restores English so a persisted Arabic selection can't bleed
/// into suites that assert on English labels.
final class ArabicLocalizationTests: XCTestCase {

    private var app: XCUIApplication!

    /// Native tab labels in Arabic, for leakage / presence assertions.
    /// (search / history / bookmarks / settings)
    enum ArabicTab {
        static let search = "بحث"
        static let history = "السجل"
        static let bookmarks = "المرجعيات"
        static let settings = "الإعدادات"
    }

    /// Arabic-Indic digits (٠–٩). Used to assert locale-formatted numbers.
    private static let arabicIndicDigits = "٠١٢٣٤٥٦٧٨٩"

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(ar)"]
        app.launchArguments += ["-AppleLocale", "ar"]
        app.launchArguments.append("-resetData")
        // Force portrait — sim orientation persists across sessions on Intel x86_64,
        // and landscape no-ops swipeUp against SwiftUI Form/List scroll views.
        // See project memory project_xcuitest_orientation_landscape_swipe.
        XCUIDevice.shared.orientation = .portrait
        app.launch()
    }

    override func tearDownWithError() throws {
        // Leave the app in English so a persisted Arabic selection can't bleed
        // into suites that assert on English labels.
        if let app, app.state == .runningForeground {
            app.terminate()
        }
        let cleanup = XCUIApplication()
        cleanup.launchArguments += ["-AppleLanguages", "(en)"]
        cleanup.launchArguments.append("-resetData")
        cleanup.launch()
        cleanup.terminate()
        app = nil
    }

    // MARK: - Tests

    /// AC1 — Arabic is selectable and the app switches to an Arabic UI.
    /// On an `-AppleLanguages (ar)` launch the tab bar must read its Arabic
    /// labels, proving `LocalizationManager` resolved `ar` and the catalog
    /// localized against it.
    func testAppLaunchesInArabic() throws {
        // Generous timeout: the first launch of the run pays the one-time
        // ~306k-row seed, during which the app shows a ProgressView and the
        // tab bar has not yet appeared.
        XCTAssertTrue(
            tabButton(label: ArabicTab.settings).waitForExistence(timeout: 60),
            "On an Arabic launch the tab bar must show the Arabic Settings label '\(ArabicTab.settings)'"
        )
        XCTAssertTrue(
            tabButton(label: ArabicTab.search).exists,
            "The tab bar must show the Arabic Search label '\(ArabicTab.search)'"
        )
    }

    /// AC2 — No English leakage. The tab bar reads Arabic with no English left
    /// behind, and the Settings screen renders Arabic chrome (nav title,
    /// language section, "Dictionaries" section header).
    func testNoEnglishLeakage() throws {
        for arabic in [ArabicTab.search, ArabicTab.history, ArabicTab.bookmarks, ArabicTab.settings] {
            XCTAssertTrue(
                tabButton(label: arabic).waitForExistence(timeout: 10),
                "Tab bar must show the Arabic label '\(arabic)'"
            )
        }
        // Wait for each English button to disappear rather than sampling
        // immediately — the `.id(lang)` rebuild can still be tearing down the
        // previous tree, so an instant `.exists` check can catch a button
        // mid-transition.
        let gone = NSPredicate(format: "exists == FALSE")
        for english in ["Search", "History", "Bookmarks", "Settings"] {
            expectation(for: gone, evaluatedWith: tabButton(label: english), handler: nil)
        }
        waitForExpectations(timeout: 5) { error in
            XCTAssertNil(error, "English tab labels must not appear in the Arabic UI")
        }

        // Settings chrome in Arabic.
        tapTab(ArabicTab.settings)
        XCTAssertTrue(
            app.navigationBars[ArabicTab.settings].waitForExistence(timeout: 5),
            "Settings navigation title must read the Arabic '\(ArabicTab.settings)'"
        )
        // Language section header ("لغة الواجهة") + Dictionaries header ("القواميس").
        XCTAssertTrue(
            staticTextContaining("لغة الواجهة"),
            "Settings must show the Arabic UI-language section header"
        )
        XCTAssertTrue(
            staticTextContaining("القواميس"),
            "Settings must show the Arabic 'Dictionaries' section header"
        )
        // And no English section headers leaking through.
        XCTAssertFalse(
            staticTextContaining("Dictionaries", timeout: 1),
            "English 'Dictionaries' header must not appear in the Arabic UI"
        )
    }

    /// AC3 — Layout mirrors RTL. XCUITest exposes no `layoutDirection` API, so
    /// assert it behaviorally: in `DefinitionView` the word/`Spacer()`/speaker
    /// `HStack` mirrors, putting the speaker control on the leading (right) edge
    /// — i.e. laid out to the *left* of the headword. `speaker.minX < word.minX`
    /// holds under RTL and is the inverse of the LTR layout.
    func testLayoutIsRightToLeft() throws {
        openBookDefinition()

        let defView = app.descendants(matching: .any)["definition_view"]
        XCTAssertTrue(defView.waitForExistence(timeout: 10), "DefinitionView must appear")

        let headword = defView.staticTexts["book"].firstMatch
        XCTAssertTrue(headword.waitForExistence(timeout: 5), "Headword 'book' must be visible")

        // Speaker button carries the Arabic accessibility label "نطق الكلمة".
        let speaker = defView.buttons["نطق الكلمة"]
        XCTAssertTrue(speaker.waitForExistence(timeout: 5), "Speaker control must be present")

        XCTAssertLessThan(
            speaker.frame.minX, headword.frame.minX,
            "Under RTL the speaker control must be laid out to the left of the headword (mirrored HStack)"
        )
    }

    /// AC4 — Mixed LTR/RTL in one cell, against a **real** `wordnet-arb-eng`
    /// row (Issue #10 ships the Arabic dictionary; #9's bidi fixture is retired).
    ///
    /// An Arabic-WordNet row is itself mixed-script: an Arabic headword with an
    /// English gloss. We can't type Arabic reliably, and an English query ranks
    /// these gloss-only matches far below the English headwords — so we isolate
    /// the source by disabling the other four dictionaries, which makes a common
    /// English word ("water", near-certain to appear in Arabic glosses) return
    /// only `wordnet-arb-eng` rows. The top result cell then carries an Arabic
    /// headword run *and* a Latin run (the "Ar–En" badge + English gloss) — the
    /// mixed-bidi property, asserted without pinning a single volatile lemma.
    func testMixedScriptCellRenders() throws {
        // Absorb the one-time ~306k-row seed import on a cold first launch
        // (the app shows a ProgressView until the tab bar appears). Without
        // this, `tapTab`'s shorter wait can fire before the UI is ready when
        // this test runs first / in isolation.
        XCTAssertTrue(tabButton(label: ArabicTab.settings).waitForExistence(timeout: 60),
                      "Tab bar must appear once seeding completes")

        tapTab(ArabicTab.settings)

        // The enable/disable toggles moved onto the pushed DictionaryOrderView
        // (Issue #6, §1b) — open it before querying any toggle.
        let settings = SettingsPage(app: app)
        XCTAssertTrue(settings.openDictionaryOrder(),
                      "Dictionary-order screen (toggles) must be reachable from Settings")

        // Source-exists guard (§5): if the Arabic dictionary wasn't bundled
        // (e.g. a `--skip-arabic-wordnet` build), fail here with a clear cause
        // rather than later with a confusing render assertion.
        let arabicToggle = app.switches["dictionary_toggle_wordnet-arb-eng"]
        XCTAssertTrue(
            app.scrollToElement(arabicToggle),
            "The 'wordnet-arb-eng' source is missing from the seed — was it built with --skip-arabic-wordnet?"
        )

        // Isolate the Arabic source so an English query surfaces its rows.
        for other in ["wordnet", "openrussian", "freedict-eng-spa", "wordnet-spa-eng"] {
            settings.tapToggle(source: other)
        }

        tapTab(ArabicTab.search)
        search(for: "water")

        // The first result cell carries the "Ar–En" badge (Latin) — its
        // existence proves a real wordnet-arb-eng row rendered. The dash is
        // U+2013, matching DictionaryEntry.sourceLabel.
        let arabicCell = app.cells.containing(
            NSPredicate(format: "label CONTAINS %@", "Ar–En")
        ).firstMatch
        XCTAssertTrue(
            arabicCell.waitForExistence(timeout: 10),
            "With only Arabic enabled, a result cell must render with the 'Ar–En' badge"
        )

        // The same cell must also contain an Arabic-script run (the headword):
        // both scripts in one cell is the mixed-bidi property AC4 requires.
        // The cell's own `.label` can be empty (SwiftUI List cells don't always
        // concatenate their children), so inspect the descendant texts.
        let texts = arabicCell.staticTexts.allElementsBoundByIndex.map { $0.label }
        let hasArabic = texts.contains { label in
            label.unicodeScalars.contains { (0x0600...0x06FF).contains($0.value) }
        }
        let hasLatin = texts.contains { label in
            label.contains { $0.isASCII && $0.isLetter }
        }
        XCTAssertTrue(hasArabic,
                      "Result cell must contain an Arabic-script run (the headword). Texts: \(texts)")
        XCTAssertTrue(hasLatin,
                      "Result cell must also contain a Latin run (badge / English gloss). Texts: \(texts)")
    }

    /// AC4 (numerals) — the entry count renders correctly within the Arabic
    /// (RTL) sentence: a single contiguous, non-jumbled number token sits
    /// beside the localized Arabic "entries" word.
    ///
    /// NOTE (correction to DESIGN_DOC.md §2): §2 assumed `Locale(identifier:
    /// "ar")` defaults to the `arab` numbering system (Arabic-Indic ٠١٢٣). It
    /// does **not** — bare `ar` resolves to `latn` on this platform (only
    /// region-qualified locales like `ar-EG`/`ar-SA` default to `arab`). The
    /// app builds a region-less `Locale("ar")` in `LocalizationManager`, so
    /// counts render in Western digits. That is acceptable for AC4: AC4
    /// requires numerals not be jumbled/reversed in the mixed-bidi line, not a
    /// specific digit system. Forcing Arabic-Indic would require the very
    /// LocalizationManager / NumberFormatter changes §2 itself rules out, and
    /// `ar-u-nu-arab` does not format cleanly here either. The digit *system*
    /// is therefore a product follow-up, not a #9 defect.
    func testEntryCountRendersCorrectlyInArabicContext() throws {
        tapTab(ArabicTab.settings)

        // Per-source entry-count rows moved onto the pushed DictionaryOrderView
        // (Issue #6, §1b).
        XCTAssertTrue(SettingsPage(app: app).openDictionaryOrder(),
                      "Dictionary-order screen (entry-count rows) must be reachable from Settings")

        // Count rows share the Arabic "entries" root "مدخل" across all plural
        // forms (مدخل / مدخلان / مدخلات / مدخلاً).
        let countRow = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "مدخل")
        ).firstMatch
        XCTAssertTrue(
            countRow.waitForExistence(timeout: 10),
            "Settings must show at least one per-source entry-count row"
        )

        let label = countRow.label

        // The Arabic "entries" word must be present (string is localized).
        XCTAssertTrue(label.contains("مدخل"),
                      "Entry-count row '\(label)' must contain the Arabic 'entries' word")

        // The number must appear as exactly one contiguous run of digits
        // (with optional grouping separators) — proof the mixed LTR-number /
        // RTL-text line did not split, reverse, or interleave the numerals.
        // Accepts either Western (latn) or Arabic-Indic (arab) digits.
        let digitClass = "0-9" + Self.arabicIndicDigits
        let numberToken = "[\(digitClass)][\(digitClass).,\u{066B}\u{066C}]*"
        let matches = (try? NSRegularExpression(pattern: numberToken))
            .map { regex -> Int in
                let range = NSRange(label.startIndex..., in: label)
                return regex.numberOfMatches(in: label, range: range)
            } ?? 0
        XCTAssertEqual(matches, 1,
            "Entry-count row '\(label)' must contain exactly one contiguous, non-jumbled number token")
    }

    // MARK: - Flow helpers

    /// Searches `term` from the (default) Search tab. Tolerates the iOS 26
    /// first-run "Siri, Dictation & Privacy" sheet that overlays `.searchable`.
    private func search(for term: String) {
        dismissSiriPrivacyNoticeIfPresent()
        let field = app.searchFields.firstMatch
        // 60s — absorbs the one-time ~306k-row cold seed; matches
        // testMixedScriptCellRenders and SpanishLocalizationTests, post-#54.
        XCTAssertTrue(field.waitForExistence(timeout: 60), "Search field must exist")
        field.tap()
        dismissSiriPrivacyNoticeIfPresent()
        // Re-resolve in case the privacy sheet dismissal re-laid out the field.
        let resolved = app.searchFields.firstMatch
        resolved.typeText(term)
    }

    /// Searches "book" and opens its definition. "book" is Latin so XCUITest
    /// types it reliably (Arabic input is not reliable).
    private func openBookDefinition() {
        search(for: "book")
        let cell = app.cells.containing(
            NSPredicate(format: "label CONTAINS[c] %@", "book")
        ).firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 10),
                      "Search for 'book' must return the real WordNet 'book' entry")
        cell.tap()
    }

    /// Closes the first-run Siri privacy sheet if it grabbed the screen. Its
    /// navigation-bar title is system-localized; match it by either language.
    private func dismissSiriPrivacyNoticeIfPresent() {
        for title in ["Siri, Dictation & Privacy", "Siri والإملاء والخصوصية"] {
            let nav = app.navigationBars[title]
            if nav.waitForExistence(timeout: 1.0) {
                nav.buttons.firstMatch.tap()
                return
            }
        }
    }

    // MARK: - Navigation helpers (RTL-safe: by label, never by index)

    /// The tab bar, waited into existence.
    private var tabBar: XCUIElement {
        let bar = app.tabBars.firstMatch
        // 60s — absorbs the one-time ~306k-row cold seed; matches
        // testMixedScriptCellRenders and SpanishLocalizationTests, post-#54.
        _ = bar.waitForExistence(timeout: 60)
        return bar
    }

    /// A tab-bar button by its visible (localized Arabic) label. The `*_tab`
    /// accessibility identifiers live on the tab *content*, not the button, so
    /// the label is the handle the button actually exposes.
    private func tabButton(label: String) -> XCUIElement {
        tabBar.buttons[label]
    }

    /// Coordinate tap (skips the AX `scrollToVisible` that can fail on iOS 26
    /// tab-bar buttons), keyed by localized label rather than index.
    private func tapTab(_ label: String) {
        let button = tabButton(label: label)
        _ = button.waitForExistence(timeout: 5)
        button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    /// True if any static text's label contains `substring` (case- and
    /// diacritic-insensitive) within the timeout.
    private func staticTextContaining(_ substring: String, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS[cd] %@", substring)
        return app.staticTexts.matching(predicate).firstMatch.waitForExistence(timeout: timeout)
    }
}
