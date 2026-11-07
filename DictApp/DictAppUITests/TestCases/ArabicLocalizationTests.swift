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
    /// (search / learn / history / settings)
    enum ArabicTab {
        static let search = "بحث"
        static let learn = "تعلّم"
        static let history = "السجل"
        static let settings = "الإعدادات"
    }

    /// Arabic-Indic digits (٠–٩). Used to assert locale-formatted numbers.
    private static let arabicIndicDigits = "٠١٢٣٤٥٦٧٨٩"

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments.append("-disableReviewPrompt")
        // Issue #237: every language pack, installed from the committed assets.
        app.launchArguments += UITestHelpers.packArguments()
        app.launchArguments += ["-AppleLanguages", "(ar)"]
        app.launchArguments += ["-AppleLocale", "ar"]
        app.launchArguments.append("-resetData")
        // 0130, #154: Greek learned, its lists in the Greek pack.
        if name.contains("testWordListsAreRightToLeft") {
            app.launchArguments += ["-learningLanguages", "ell"]
        }
        // Force portrait — sim orientation persists across sessions on Intel x86_64,
        // and landscape no-ops swipeUp against SwiftUI Form/List scroll views.
        // See project memory project_xcuitest_orientation_landscape_swipe.
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        // Once after each launch, so no wait below has to absorb a cold start.
        XCTAssertTrue(app.waitForDictionariesReady(),
                      "Search screen after launch")
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
        for arabic in [ArabicTab.search, ArabicTab.learn, ArabicTab.history, ArabicTab.settings] {
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
        for english in ["Search", "Learn", "History", "Settings"] {
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

    /// Issue #145: the Search chips mirror. "All" sits right of the first
    /// pair chip, and each chip reads its Arabic Dictionary Order title.
    func testChipsReadRightToLeft() throws {
        let search = SearchPage(app: app)
        XCTAssertTrue(search.waitForChips(), "the chips row must show on Search")
        let order = search.chipOrder(of: TestData.Pairs.all)
        XCTAssertEqual(order.count, TestData.Pairs.all.count, "one chip per bundled pair")
        XCTAssertEqual(order.first, TestData.Pairs.arabic, "the Arabic pair leads by the #74 default")
        let firstPair = search.chip(try XCTUnwrap(order.first))
        XCTAssertGreaterThanOrEqual(search.allChip.frame.minX, firstPair.frame.maxX - 1,
                                    "'All' is right of the first pair chip")
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThan(search.allChip.frame.maxX, window.maxX - 40,
                             "the row starts at the right edge: 'All' is the rightmost chip on screen")
        XCTAssertEqual(search.allChip.label, "كل القواميس")
        var chipLabels: [String: String] = [:]
        for pair in TestData.Pairs.all {
            chipLabels[pair] = search.chip(pair).label
        }
        attachScreenshot("Search chips (ar)")

        tapTab(ArabicTab.settings)
        let settings = SettingsPage(app: app)
        XCTAssertTrue(settings.openDictionaryOrder(), "Dictionary order must be reachable from Settings")
        for pair in TestData.Pairs.all {
            let row = app.staticTexts[AccessibilityIdentifiers.Settings.dictionaryOrderRow(pair: pair)]
            XCTAssertTrue(app.scrollToElement(row), "order row '\(pair)' must be reachable")
            XCTAssertEqual(chipLabels[pair], row.label, "chip '\(pair)' reads its Dictionary Order title")
        }
    }

    /// Issue #144: the inflection table mirrors. The title and the VoiceOver
    /// labels are Arabic, the tense columns run right to left (Present right
    /// of Imperfect) with the pronoun column on the right, and the Greek
    /// forms keep their own order.
    func testInflectionTableIsRightToLeft() throws {
        typealias IDs = AccessibilityIdentifiers.Inflection
        search(for: "γράφω")
        let row = app.collectionViews.firstMatch.cells
            .containing(.any, identifier: AccessibilityIdentifiers.Search.sourceBadge(source: TestData.Sources.freedictEllEng))
            .containing(NSPredicate(format: "label == %@", "γράφω"))
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: TestData.Timeouts.long), "'γράφω' must list the FreeDict entry")
        app.dismissKeyboardIfPresent()
        row.tap()
        let page = InflectionTablePage(app: app)
        XCTAssertTrue(page.table.waitForExistence(timeout: TestData.Timeouts.long), "γράφω must show its table")
        XCTAssertTrue(page.table.staticTexts["تصريف الفعل"].exists, "the title reads 'تصريف الفعل'")

        let present = page.cell(IDs.verbCell(slot: "present", person: "1sg"))
        let imperfect = page.cell(IDs.verbCell(slot: "imperfect", person: "1sg"))
        XCTAssertEqual(present.label, "المضارع\u{060C} εγώ\u{060C} γράφω")
        XCTAssertEqual(page.cell(IDs.verbCell(slot: "aorist", person: "1sg")).label, "الماضي البسيط\u{060C} εγώ\u{060C} έγραψα")
        XCTAssertTrue(page.reveal(present))
        XCTAssertGreaterThan(present.frame.minX, imperfect.frame.maxX, "Present is right of Imperfect")
        // Headers are hidden from VoiceOver; where XCUITest still lists the
        // pronoun, it must sit right of the forms.
        let pronoun = page.table.staticTexts["εγώ"].firstMatch
        if pronoun.exists {
            XCTAssertGreaterThan(pronoun.frame.minX, present.frame.maxX, "the pronoun column is on the right")
        }
        XCTAssertEqual(page.allFormsButton.label, "كل الصيغ")
        attachScreenshot("γράφω (ar), main forms")

        page.tapAllForms()
        let passive = page.cell(IDs.verbCell(voice: "passive", slot: "aorist", person: "1sg"))
        XCTAssertTrue(passive.waitForExistence(timeout: TestData.Timeouts.medium))
        XCTAssertEqual(passive.label, "المبني للمجهول\u{060C} الماضي البسيط\u{060C} εγώ\u{060C} γράφτηκα / γράφηκα")
        XCTAssertEqual(page.allFormsButton.label, "الصيغ الرئيسية")
        XCTAssertTrue(page.reveal(passive))
        attachScreenshot("γράφω (ar), all forms")
    }

    /// 0131, #158: the Learn tab in Arabic, mirrored. The picker asks in
    /// Arabic and names the pairs in Arabic; on γράφω the Learn button
    /// reads "تعلّم", sits left of the reading-mode toggle (the trailing
    /// toolbar mirrors) and asks "تعلّم اليونانية عبر الإنجليزية؟"; "نعم" learns Greek, and
    /// the home's My words row reads right to left.
    func testLearnTabRightToLeft() throws {
        tapTab(ArabicTab.learn)
        let learnPage = LearnPage(app: app)
        XCTAssertTrue(learnPage.waitForPicker(), "no learned language: the picker")
        XCTAssertTrue(staticTextContaining("ما اللغة التي تريد تعلّمها"), "the picker's question in Arabic")
        XCTAssertEqual(Self.visible(learnPage.pickerRow("ell", via: "eng").label), "اليونانية عبر الإنجليزية")
        XCTAssertEqual(Self.visible(learnPage.pickerRow("eng", via: "eng").label), "الإنجليزية عبر الإنجليزية")
        attachScreenshot("learn picker (ar)")

        tapTab(ArabicTab.search)
        search(for: "γράφω")
        let row = app.collectionViews.firstMatch.cells
            .containing(.any, identifier: AccessibilityIdentifiers.Search.sourceBadge(source: TestData.Sources.freedictEllEng))
            .containing(NSPredicate(format: "label == %@", "γράφω"))
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: TestData.Timeouts.long), "'γράφω' must list the FreeDict entry")
        app.dismissKeyboardIfPresent()
        row.tap()
        let learn = app.buttons[AccessibilityIdentifiers.Definition.learnButton].firstMatch
        XCTAssertTrue(learn.waitForExistence(timeout: TestData.Timeouts.long))
        XCTAssertEqual(learn.label, "تعلّم")
        let toggle = app.buttons[AccessibilityIdentifiers.ReadingMode.toggle].firstMatch
        XCTAssertLessThanOrEqual(learn.frame.maxX, toggle.frame.minX + 1,
                                 "RTL: the Learn button is outermost, on the left")
        learn.tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: TestData.Timeouts.medium), "Learn on a Greek word asks")
        // Foundation wraps the language name in U+2068/U+2069 isolates.
        let texts = alert.staticTexts.allElementsBoundByIndex.map { Self.visible($0.label) }
        XCTAssertTrue(texts.contains("تعلّم اليونانية عبر الإنجليزية؟"),
                      "the alert reads 'تعلّم اليونانية عبر الإنجليزية؟'; got \(texts)")
        alert.buttons["نعم"].tap()
        XCTAssertTrue(learnPage.waitForLabel(of: learn, toBe: "إيقاف التعلّم"), "after Yes: 'إيقاف التعلّم'")

        tapTab(ArabicTab.learn)
        learnPage.popToRoot()
        XCTAssertTrue(learnPage.waitForHome(), "Greek learned: the home")
        // Below the goal ring (#164) and the Lists section (#154).
        app.scrollToElement(learnPage.myWordsRow)
        let title = learnPage.myWordsRow.staticTexts["كلماتي"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: TestData.Timeouts.medium), "the My words row reads 'كلماتي'")
        let count = learnPage.myWordsRow.staticTexts["1"].firstMatch
        if count.exists {
            XCTAssertGreaterThan(title.frame.minX, count.frame.maxX, "RTL: the title on the right, the count on the left")
        } else {
            XCTAssertGreaterThan(title.frame.midX, app.windows.firstMatch.frame.midX, "RTL: the title on the right")
        }
        attachScreenshot("learn home (ar)")
    }

    /// 0131, #161: Start and mistakes practice in Arabic, mirrored. The home
    /// reads "ابدأ" and "تدرّب على الأخطاء · …"; after the two mistakes, the
    /// summary's titles sit right of their values. Bare `ar` formats numbers
    /// in Arabic-Indic digits on iOS 17.5 and in Western ones on iOS 26, so
    /// the values are compared in Western digits (as
    /// `testEntryCountRendersCorrectlyInArabicContext` accepts both).
    func testSessionRightToLeft() throws {
        app.terminate()
        app.launchArguments += ["-learningFixture", "mistakes", "-learningAnswerHints", "-learningSeed", "161",
                                "-learning_answer_mode", "choice"]
        app.launch()
        XCTAssertTrue(app.waitForDictionariesReady(), "Search screen after launch")
        tapTab(ArabicTab.learn)
        let learnPage = LearnPage(app: app)
        XCTAssertTrue(learnPage.waitForHome(timeout: TestData.Timeouts.long), "the Learn home")
        XCTAssertTrue(learnPage.startButton.waitForExistence(timeout: TestData.Timeouts.medium), "Start")
        XCTAssertEqual(learnPage.startButton.label, "ابدأ")
        XCTAssertTrue(learnPage.mistakesRow.waitForExistence(timeout: TestData.Timeouts.medium), "the mistakes row")
        XCTAssertTrue(Self.visible(learnPage.mistakesRow.label).hasPrefix("تدرّب على الأخطاء"), learnPage.mistakesRow.label)
        attachScreenshot("learn home with Start (ar)")

        let run = learnPage.openMistakes()
        for question in 1...2 {
            XCTAssertTrue(run.waitForQuestionOrSummary(), "question \(question)")
            XCTAssertNotNil(run.choose(right: true), "question \(question): the answer hint")
            XCTAssertEqual(run.waitForFeedback(), "right")
            run.tapContinue()
        }
        XCTAssertTrue(run.summary.waitForExistence(timeout: TestData.Timeouts.long), "the summary")
        XCTAssertEqual(Self.westernDigits(run.summaryValue(AccessibilityIdentifiers.Exercise.summaryExercises)), "2")
        let goal = app.descendants(matching: .any)[AccessibilityIdentifiers.Exercise.summaryGoal].firstMatch
        XCTAssertEqual(Self.westernDigits(Self.visible(goal.label)), "3 من 20",
                       "today's mistake and the two answers, of 20")
        let title = app.staticTexts["الهدف اليومي"].firstMatch
        XCTAssertTrue(title.exists, "the goal row's title in Arabic")
        XCTAssertGreaterThan(title.frame.minX, goal.frame.maxX, "RTL: the title on the right, the value on the left")
        attachScreenshot("run summary (ar)")
    }

    /// 0131, #160: match the pairs in Arabic, mirrored: the row reads
    /// "طابِق الأزواج", the words stand in the right column and the meanings
    /// in the left one, the Greek words read as written, and a right pair
    /// leaves the board.
    func testMatchPairsRightToLeft() throws {
        app.terminate()
        app.launchArguments += ["-learningFixture", "due", "-learningAnswerHints", "-learningSeed", "160"]
        app.launch()
        XCTAssertTrue(app.waitForDictionariesReady(), "Search screen after launch")
        tapTab(ArabicTab.learn)
        let learnPage = LearnPage(app: app)
        XCTAssertTrue(learnPage.waitForHome(timeout: TestData.Timeouts.long), "the Learn home")
        XCTAssertTrue(learnPage.trainerMatch.waitForExistence(timeout: TestData.Timeouts.medium), "the Match the pairs row")
        XCTAssertEqual(learnPage.trainerMatch.label, "طابِق الأزواج")

        let match = learnPage.openMatch()
        XCTAssertTrue(match.waitForBoard(), "the board")
        XCTAssertTrue(staticTextContaining("اضغط على الأزواج المتطابقة"), "the instruction in Arabic")
        let greek: Set<String> = ["γράφω", "σπίτι", "νερό", "καλός", "είμαι"]
        XCTAssertEqual(Set(match.words.map(\.label)), greek, "the Greek words as written")
        for position in 0..<5 {
            XCTAssertGreaterThan(match.word(position).frame.minX, match.meaning(position).frame.maxX,
                                 "RTL: word \(position) right of meaning \(position)")
        }
        attachScreenshot("match the pairs (ar)")

        let word = match.word(0)
        XCTAssertNotNil(match.pair(word, right: true), "a right pair")
        XCTAssertTrue(match.waitForGone(word), "the pair leaves the board")
        XCTAssertEqual(match.words.count, 4)
    }

    /// 0130, #154: the list screens in Arabic, mirrored. "كل القوائم" opens
    /// "القوائم"; Greek A1's title and count sit on the right; its screen
    /// reads "تعلّم هذه القائمة" with its words on the right; New words from
    /// reads "كلمات جديدة من".
    func testWordListsAreRightToLeft() throws {
        tapTab(ArabicTab.learn)
        let learnPage = LearnPage(app: app)
        XCTAssertTrue(learnPage.waitForHome(timeout: TestData.Timeouts.long), "Greek learned: the home")
        let page = learnPage.tapAllLists()
        XCTAssertTrue(app.navigationBars["القوائم"].waitForExistence(timeout: TestData.Timeouts.medium))
        let midX = app.windows.firstMatch.frame.midX
        let row = page.row("ky-ell-a1")
        XCTAssertTrue(row.waitForExistence(timeout: TestData.Timeouts.medium), "Greek A1's row")
        let title = row.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "اليونانية")).firstMatch
        XCTAssertTrue(title.exists, "Greek A1's title in Arabic")
        XCTAssertGreaterThan(title.frame.midX, midX, "RTL: the title on the right")
        let count = page.count("ky-ell-a1")
        XCTAssertTrue(count.label.contains("كلمة"), "the count in Arabic; got '\(count.label)'")
        XCTAssertGreaterThan(count.frame.maxX, midX, "RTL: the count under the title, on the right")
        XCTAssertTrue(staticTextContaining("قوائمي") || app.scrollToElement(page.row("my-words")), "the My lists section")
        attachScreenshot("lists (ar)")

        XCTAssertTrue(app.scrollToElement(page.row("ky-ell-a1")))
        page.openList("ky-ell-a1")
        XCTAssertEqual(page.learnButton.label, "تعلّم هذه القائمة")
        let word = page.word("αγάπη")
        XCTAssertTrue(word.waitForExistence(timeout: TestData.Timeouts.medium))
        XCTAssertTrue(page.wait(for: word, "value", toBe: "love"), "Kirill's translation, never translated")
        let term = page.listScreen.staticTexts["αγάπη η"].firstMatch
        XCTAssertTrue(term.exists, "the term with its ending")
        XCTAssertGreaterThan(term.frame.minX, midX, "RTL: the term on the right")
        attachScreenshot("list (ar)")
        page.goBack()
        page.goBack()

        learnPage.tapChooseLists()
        XCTAssertTrue(app.navigationBars["كلمات جديدة من"].waitForExistence(timeout: TestData.Timeouts.medium))
        attachScreenshot("new words from (ar)")
    }

    /// 0166, #164: Statistics in Arabic, mirrored. The title reads
    /// "الإحصاءات"; under the 30-day chart "اليوم" (today) is on the left and
    /// the oldest day on the right, so today's bar is at the left edge; the
    /// chart's summary starts with U+200F; the calendar's Monday is on the right.
    func testStatisticsRightToLeft() throws {
        app.terminate()
        app.launchArguments += ["-learningFixture", "stats"]
        app.launch()
        XCTAssertTrue(app.waitForDictionariesReady(), "Search screen after launch")
        tapTab(ArabicTab.learn)
        let learnPage = LearnPage(app: app)
        XCTAssertTrue(learnPage.waitForHome(timeout: TestData.Timeouts.long), "the Learn home")
        let stats = learnPage.openStatistics()
        let ids = AccessibilityIdentifiers.Statistics.self
        XCTAssertTrue(app.navigationBars["الإحصاءات"].waitForExistence(timeout: TestData.Timeouts.medium),
                      "the title in Arabic")
        XCTAssertTrue(stats.reveal(ids.chart30d), "the chart")
        XCTAssertEqual(stats.chart.label.unicodeScalars.first, "\u{200F}", stats.chart.label)
        XCTAssertTrue(Self.visible(stats.chart.label).hasPrefix("آخر 30 يومًا: "), stats.chart.label)
        let start = stats.element(ids.chartStart), end = stats.element(ids.chartEnd)
        XCTAssertEqual(end.label, "اليوم")
        XCTAssertLessThan(end.frame.maxX, start.frame.minX, "RTL: today on the left, the oldest day on the right")
        XCTAssertLessThan(end.frame.midX, stats.chart.frame.midX, "'Today' under the chart's left half")
        let tallest = try XCTUnwrap(stats.tallestBarPosition(), "the chart's bars")
        XCTAssertLessThan(tallest, 0.3, "RTL: yesterday's bar, the tallest, at the left edge next to today's")
        attachScreenshot("statistics chart (ar)")

        // Last week's Monday and Tuesday, both in the calendar.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        var date = Date()
        if calendar.component(.hour, from: date) < 4 { date = calendar.date(byAdding: .day, value: -1, to: date)! }
        let sinceMonday = (calendar.component(.weekday, from: date) + 5) % 7
        let monday = calendar.date(byAdding: .day, value: -sinceMonday - 7, to: date)!
        func id(_ day: Date) -> String {
            let parts = calendar.dateComponents([.year, .month, .day], from: day)
            return ids.streakDay(String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!))
        }
        XCTAssertTrue(stats.reveal(id(monday)), "the calendar")
        let mondayCell = stats.element(id(monday))
        let tuesdayCell = stats.element(id(calendar.date(byAdding: .day, value: 1, to: monday)!))
        XCTAssertGreaterThan(mondayCell.frame.minX, tuesdayCell.frame.maxX, "RTL: Monday on the right")
        let sundayCell = stats.element(id(calendar.date(byAdding: .day, value: 6, to: monday)!))
        XCTAssertEqual(sundayCell.frame.midY, mondayCell.frame.midY, accuracy: 2, "a week runs Monday to Sunday")
        XCTAssertLessThan(sundayCell.frame.maxX, tuesdayCell.frame.minX, "RTL: Sunday on the left")
        XCTAssertEqual(mondayCell.label.unicodeScalars.first, "\u{200F}", mondayCell.label)
        attachScreenshot("statistics calendar (ar)")
    }

    /// Issue #243: the Languages screen mirrors. Each row's name is right of
    /// its status, and the composed status starts with U+200F.
    func testLanguagesScreenIsRightToLeft() throws {
        typealias IDs = AccessibilityIdentifiers.Languages
        tapTab(ArabicTab.settings)
        let languages = LanguagesPage(app: app)
        XCTAssertTrue(languages.open(), "Settings → Languages must open")
        XCTAssertTrue(app.navigationBars["اللغات"].waitForExistence(timeout: TestData.Timeouts.medium),
                      "the title reads 'اللغات'")

        let english = app.staticTexts[IDs.row("eng")]
        XCTAssertEqual(english.label, "الإنجليزية")
        let included = app.cells.containing(.staticText, identifier: IDs.row("eng")).staticTexts["مضمّنة"]
        XCTAssertTrue(included.exists, "English is 'مضمّنة'")
        XCTAssertGreaterThan(english.frame.minX, included.frame.maxX, "the name is right of its status")

        let greek = app.staticTexts[IDs.row("ell")]
        XCTAssertTrue(app.scrollToElement(greek), "the Greek row must be reachable")
        XCTAssertEqual(greek.label, "اليونانية")
        let installed = app.staticTexts[IDs.installed("ell")]
        XCTAssertTrue(installed.exists, "Greek is installed (`-installPacks all`)")
        XCTAssertEqual(installed.label.unicodeScalars.first, "\u{200F}", installed.label)
        XCTAssertTrue(Self.visible(installed.label).hasPrefix("مثبّت · "), installed.label)
        XCTAssertTrue(installed.label.contains("60.6") || installed.label.contains("٦٠٫٦"),
                      "the installed size, one number: \(installed.label)")
        XCTAssertGreaterThan(greek.frame.minX, installed.frame.maxX, "the name is right of its status")
        attachScreenshot("Languages (ar)")
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

    /// `s` with its Arabic-Indic digits (٠–٩) as Western ones (0–9).
    private static func westernDigits(_ s: String) -> String {
        String(s.map { character in
            guard let index = arabicIndicDigits.firstIndex(of: character) else { return character }
            return Character(String(arabicIndicDigits.distance(from: arabicIndicDigits.startIndex, to: index)))
        })
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
