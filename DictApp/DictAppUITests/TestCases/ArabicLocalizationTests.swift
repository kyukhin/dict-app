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
///   * `-seedBidiFixture` imports a tiny mixed En/Ar dataset (`bidi_fixture.json`)
///     under the dedicated `bidi_fixture` source so the mixed-script cell can be
///     surfaced by searching the Latin headword "book".
///
/// Tab navigation is **by visible (Arabic) label**, never by index: under RTL
/// the tab order mirrors, so the index trick `SpanishLocalizationTests` relies
/// on is unsafe here (DESIGN_DOC.md §3). It is *not* by accessibility identifier
/// either — the `*_tab` identifiers sit on each tab's content container, not on
/// the tab-bar button (same reality `SpanishLocalizationTests` documents), so a
/// `tabBar.buttons["settings_tab"]` lookup resolves nothing. The localized label
/// is the order-independent, RTL-safe handle the buttons actually expose.
///
/// `tearDown` restores English and scrubs the `bidi_fixture` source via
/// `-clearBidiFixture` so neither a persisted Arabic selection nor the fixture
/// rows bleed into suites that assert on English / the seed dictionary.
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
        app.launchArguments.append("-seedBidiFixture")
        app.launch()
    }

    override func tearDownWithError() throws {
        // Best-effort scrub: relaunch with the clear flag (and back in English)
        // so the fixture rows and the Arabic selection don't outlive the suite.
        if let app, app.state == .runningForeground {
            app.terminate()
        }
        let cleanup = XCUIApplication()
        cleanup.launchArguments += ["-AppleLanguages", "(en)"]
        cleanup.launchArguments.append("-resetData")
        cleanup.launchArguments.append("-clearBidiFixture")
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
        // ~150k-row seed, during which the app shows a ProgressView and the
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

    /// AC4 — Mixed LTR/RTL in one cell. Searching the Latin headword "book"
    /// surfaces the seeded row whose definition mixes Arabic ("كتاب") and Latin
    /// ("a bound set…") in a single cell. Assert both scripts live in one
    /// element's label — proof the cell carries mixed bidi content.
    func testMixedScriptCellRenders() throws {
        search(for: "book")

        let mixed = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@ AND label CONTAINS[c] %@", "كتاب", "bound")
        ).firstMatch
        XCTAssertTrue(
            mixed.waitForExistence(timeout: 10),
            "A single result cell must contain both the Arabic run ('كتاب') and the Latin run ('bound')"
        )
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
        XCTAssertTrue(field.waitForExistence(timeout: 10), "Search field must exist")
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
                      "Search for 'book' must return the seeded fixture row")
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
        _ = bar.waitForExistence(timeout: 10)
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
