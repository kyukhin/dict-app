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
/// is the order-independent, RTL-safe handle the buttons actually expose; it is
/// looked up through `app.tabButton(labeled:)`, which also covers the iPadOS 26
/// tab strip (no `UITabBar` there).
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
        app.launchArguments.append("-disableReviewPrompt")
        app.launchArguments += ["-AppleLanguages", "(ar)"]
        app.launchArguments += ["-AppleLocale", "ar"]
        app.launchArguments.append("-resetData")
        // Force portrait — sim orientation persists across sessions on Intel x86_64,
        // and landscape no-ops swipeUp against SwiftUI Form/List scroll views.
        // See project memory project_xcuitest_orientation_landscape_swipe.
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        // Issue #111: once after each launch, so no wait below has to absorb
        // a cold start (the tab bar shows in seconds; the unpack runs behind it).
        XCTAssertTrue(app.waitForDictionariesReady(),
                      "Search screen with every dictionary unpacked after launch")
    }

    override func tearDownWithError() throws {
        // Leave the app in English so a persisted Arabic selection can't bleed
        // into suites that assert on English labels.
        if let app, app.state == .runningForeground {
            app.terminate()
        }
        let cleanup = XCUIApplication()
        cleanup.launchArguments.append("-disableReviewPrompt")
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
        XCTAssertTrue(
            tabButton(label: ArabicTab.settings).waitForExistence(timeout: TestData.Timeouts.long),
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
    /// the source by disabling every other pair, which makes a common
    /// English word ("water", near-certain to appear in Arabic glosses) return
    /// only `wordnet-arb-eng` rows. The top result cell then carries an Arabic
    /// headword run *and* a Latin run (the "Ar–En · WN" badge + English gloss) —
    /// the mixed-bidi property, asserted without pinning a single volatile lemma.
    func testMixedScriptCellRenders() throws {
        XCTAssertTrue(tabButton(label: ArabicTab.settings).waitForExistence(timeout: TestData.Timeouts.long),
                      "Tab bar must appear after launch")

        tapTab(ArabicTab.settings)

        // The enable/disable toggles moved onto the pushed DictionaryOrderView
        // (Issue #6, §1b) — open it before querying any toggle.
        let settings = SettingsPage(app: app)
        XCTAssertTrue(settings.openDictionaryOrder(),
                      "Dictionary-order screen (toggles) must be reachable from Settings")

        // Source-exists guard (§5): if the Arabic dictionary wasn't bundled
        // (e.g. a `--skip-arabic-wordnet` build), fail here with a clear cause
        // rather than later with a confusing render assertion.
        // Issue #92: toggles are per language pair (`arb-eng` = wordnet-arb-eng).
        let arabicToggle = app.switches[
            AccessibilityIdentifiers.Settings.dictionaryToggle(pair: TestData.Pairs.arabic)
        ]
        XCTAssertTrue(
            app.scrollToElement(arabicToggle),
            "The 'wordnet-arb-eng' source (pair '\(TestData.Pairs.arabic)') is missing from the seed — was it built with --skip-arabic-wordnet?"
        )

        // Isolate the Arabic pair so an English query surfaces its rows. The
        // Spanish pair toggle covers both freedict-eng-spa and wordnet-spa-eng;
        // the Greek one (Issue #87) all four Greek sources, whose English
        // headwords would otherwise outrank the Arabic gloss matches.
        for other in [TestData.Pairs.english, TestData.Pairs.russian, TestData.Pairs.spanish,
                      TestData.Pairs.greek] {
            settings.tapToggle(pair: other)
        }

        tapTab(ArabicTab.search)
        search(for: "water")

        // A result cell carries the wordnet-arb-eng badge — its existence
        // proves a real Arabic row rendered. Matched by identifier (Issue
        // #87): the badge's label is its localized VoiceOver text.
        let arabicCell = app.cells.containing(
            .any, identifier: "source_badge_wordnet-arb-eng"
        ).firstMatch
        XCTAssertTrue(
            arabicCell.waitForExistence(timeout: 10),
            "With only Arabic enabled, a result cell must render with the wordnet-arb-eng badge"
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

    /// Issue #119 — pair titles, direction lines and the History caption read
    /// right to left: the non-English language is first (rightmost), the arrow
    /// points from source to target, and a caption starts right to left. Each
    /// title is one `Text` (one AX element, no per-word frames), so the leading
    /// U+200F in the on-screen label plus the CoreText order unit tests
    /// (`ArabicBidiOrderTests`) stand in for a frame comparison; the kept
    /// screenshots are for a human check of the drawn order. The
    /// unsupported-import message is reachable only through the document
    /// picker, so `ArabicBidiOrderTests` covers it alone.
    func testPairTitlesAndDirectionReadRightToLeft() throws {
        let english = "الإنجليزية"
        let arabic = "العربية"
        let spanish = "الإسبانية"

        // History with one entry (-resetData emptied it): opening a definition
        // records the lookup. The caption is the row's non-headword text.
        openBookDefinition()
        XCTAssertTrue(app.descendants(matching: .any)[AccessibilityIdentifiers.Definition.definitionView]
                        .waitForExistence(timeout: TestData.Timeouts.long),
                      "Opening 'book' must push the definition (and record it in History)")
        tapTab(ArabicTab.history)
        let historyRow = app.cells.containing(.staticText, identifier: "book").firstMatch
        XCTAssertTrue(historyRow.waitForExistence(timeout: TestData.Timeouts.long), "History must list 'book'")
        let rowTexts = historyRow.staticTexts.allElementsBoundByIndex.map(\.label)
        let caption = try XCTUnwrap(rowTexts.first { $0 != "book" },
                                    "History row must show a time caption; texts: \(rowTexts)")
        XCTAssertEqual(caption.unicodeScalars.first, "\u{200F}",
                       "Arabic History caption starts with U+200F (RLM), got '\(caption)'")
        attachScreenshot("History (ar)")

        // Dictionary order: every bilingual title leads with the non-English name.
        tapTab(ArabicTab.settings)
        let settings = SettingsPage(app: app)
        XCTAssertTrue(settings.openDictionaryOrder(), "Dictionary order must be reachable from Settings")
        for (pair, name) in [(TestData.Pairs.arabic, arabic), (TestData.Pairs.spanish, spanish),
                             (TestData.Pairs.russian, "الروسية"), (TestData.Pairs.greek, "اليونانية")] {
            let row = app.staticTexts[AccessibilityIdentifiers.Settings.dictionaryOrderRow(pair: pair)]
            XCTAssertTrue(app.scrollToElement(row), "order row '\(pair)' must be reachable")
            XCTAssertEqual(row.label.unicodeScalars.first, "\u{200F}", "\(pair): '\(row.label)'")
            XCTAssertEqual(Self.visible(row.label), "\(name) – \(english)", "\(pair): non-English language first")
        }
        attachScreenshot("Dictionary order (ar)")

        // (i) detail of Arabic – English: title and its single direction line.
        let arabicInfo = settings.openInfo(pair: TestData.Pairs.arabic)
        XCTAssertTrue(arabicInfo.view.exists, "(i) on arb-eng must push the info detail")
        assertDetailTitle(leadingWith: arabic, english: english)
        let arabicDirection = arabicInfo.element(AccessibilityIdentifiers.DictionaryInfo.direction(
            TestData.Sources.wordnetArbEng))
        XCTAssertTrue(arabicDirection.waitForExistence(timeout: TestData.Timeouts.long))
        XCTAssertEqual(arabicDirection.label.unicodeScalars.first, "\u{200F}", arabicDirection.label)
        XCTAssertEqual(Self.visible(arabicDirection.label), "\(arabic) ← \(english)", "Arabic to English")
        attachScreenshot("Dictionary detail arb-eng (ar)")

        // (i) detail of Spanish – English: both directions, source first.
        arabicInfo.goBack()
        let spanishInfo = settings.openInfo(pair: TestData.Pairs.spanish)
        XCTAssertTrue(spanishInfo.view.exists, "(i) on eng-spa must push the info detail")
        assertDetailTitle(leadingWith: spanish, english: english)
        let spaEng = AccessibilityIdentifiers.DictionaryInfo.direction(TestData.Sources.wordnetSpaEng)
        XCTAssertTrue(spanishInfo.element(spaEng).waitForExistence(timeout: TestData.Timeouts.long))
        let spaEngLabel = spanishInfo.element(spaEng).label
        XCTAssertEqual(spaEngLabel.unicodeScalars.first, "\u{200F}", spaEngLabel)
        XCTAssertEqual(Self.visible(spaEngLabel), "\(spanish) ← \(english)", "wordnet-spa-eng: Spanish to English")
        attachScreenshot("Dictionary detail eng-spa (ar)")
        let engSpa = AccessibilityIdentifiers.DictionaryInfo.direction(TestData.Sources.freedictEngSpa)
        XCTAssertTrue(spanishInfo.revealElement(engSpa), "freedict-eng-spa direction must be reachable")
        let engSpaLabel = spanishInfo.element(engSpa).label
        XCTAssertEqual(engSpaLabel.unicodeScalars.first, "\u{200F}", engSpaLabel)
        XCTAssertEqual(Self.visible(engSpaLabel), "\(english) ← \(spanish)", "freedict-eng-spa: English to Spanish")
    }

    /// The pushed detail's navigation bar (its `identifier` is the title)
    /// starts with U+200F and reads "<name> – الإنجليزية" in logical order.
    private func assertDetailTitle(leadingWith name: String, english: String,
                                   file: StaticString = #filePath, line: UInt = #line) {
        let bar = app.navigationBars.matching(NSPredicate(format: "identifier CONTAINS %@", name)).firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: TestData.Timeouts.medium),
                      "detail navigation bar titled with '\(name)' must exist", file: file, line: line)
        XCTAssertEqual(bar.identifier.unicodeScalars.first, "\u{200F}", "title '\(bar.identifier)'",
                       file: file, line: line)
        XCTAssertEqual(Self.visible(bar.identifier), "\(name) – \(english)", file: file, line: line)
    }

    // MARK: - Flow helpers

    /// `s` without U+200F (RLM) and Foundation's U+2068/U+2069 isolates: the
    /// text a reader sees, in logical order.
    private static func visible(_ s: String) -> String {
        let marks: Set<Unicode.Scalar> = ["\u{200F}", "\u{2068}", "\u{2069}"]
        return String(s.unicodeScalars.filter { !marks.contains($0) })
    }

    /// Keeps a full-screen screenshot in the result bundle for a human check.
    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Searches `term` from the (default) Search tab. Tolerates the iOS 26
    /// first-run "Siri, Dictation & Privacy" sheet that overlays `.searchable`.
    private func search(for term: String) {
        dismissSiriPrivacyNoticeIfPresent()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: TestData.Timeouts.long), "Search field must exist")
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

    /// A tab button by its visible (localized Arabic) label, on the tab bar or
    /// the iPadOS 26 tab strip. The `*_tab` accessibility identifiers live on
    /// the tab *content*, not the button, so the label is the order-independent
    /// handle the button exposes.
    private func tabButton(label: String) -> XCUIElement {
        app.tabButton(labeled: label)
    }

    /// Coordinate tap (skips the AX `scrollToVisible` that can fail on iOS 26
    /// tab-bar buttons), keyed by localized label rather than index. On iPad
    /// the keyboard can cover the bottom tab strip after a search and a raw
    /// coordinate tap is swallowed while `.searchable` is active, so dismiss
    /// the keyboard and prefer an element tap there (`TabBarPage`, #76).
    private func tapTab(_ label: String) {
        let button = tabButton(label: label)
        _ = button.waitForExistence(timeout: 5)
        if app.keyboards.count > 0 {
            app.keyboards.firstMatch.swipeDown()
            let gone = NSPredicate(format: "count == 0")
            _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: gone, object: app.keyboards)],
                               timeout: 2)
        }
        if UIDevice.current.userInterfaceIdiom == .pad && button.isHittable {
            button.tap()
        } else {
            button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }

    /// True if any static text's label contains `substring` (case- and
    /// diacritic-insensitive) within the timeout.
    private func staticTextContaining(_ substring: String, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS[cd] %@", substring)
        return app.staticTexts.matching(predicate).firstMatch.waitForExistence(timeout: timeout)
    }
}
