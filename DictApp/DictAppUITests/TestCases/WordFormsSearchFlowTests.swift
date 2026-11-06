import XCTest

/// Issue #142 — search by an inflected Greek form (0136-word-forms.md,
/// "Search by any form"): the lemma's rows follow the exact matches, each
/// with a caption under the headword (`form_caption`). Opening one opens and
/// records the lemma.
///
/// - Captions are read by identifier; their `label` is the VoiceOver text,
///   with the person as the Greek pronoun ("aorist, εγώ of γράφω").
/// - Greek is typed through `SearchPage.searchFor`. If "search field should
///   contain typed term" fails, check the simulator's hardware-keyboard
///   setting first.
/// - English forms (#143, WordNet morphy): `testEnglishIrregularQuery`.
final class WordFormsSearchFlowTests: XCTestCase {

    var app: XCUIApplication!
    var tabBarPage: TabBarPage!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments.append("-disableReviewPrompt")
        // Issue #237: every language pack, installed from the committed assets.
        app.launchArguments += UITestHelpers.packArguments()
        app.launchArguments.append("-resetData")

        // iOS 26 "Enable Dictation?" springboard alert — tap a dismissal button
        // instead of XCUI's default (which opens a blocking privacy sheet).
        addUIInterruptionMonitor(withDescription: "Enable Dictation alert") { alert in
            for label in ["Not Now", "Cancel", "Don't Enable", "Don't Allow", "Enable Dictation"] {
                let button = alert.buttons[label]
                if button.exists {
                    button.tap()
                    return true
                }
            }
            return false
        }

        // Force portrait — sim orientation persists across sessions on Intel
        // x86_64, and landscape no-ops swipeUp against SwiftUI Form/List.
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        tabBarPage = TabBarPage(app: app)
    }

    override func tearDownWithError() throws {
        app = nil
        tabBarPage = nil
    }

    // MARK: - Tests

    /// `έγραψα` (no headword of its own) → the first row is γράφω from a
    /// Greek → English dictionary, captioned "aorist 1sg of γράφω"; it opens
    /// γράφω, and History records γράφω, not the typed form.
    func testInflectedGreekQuery() throws {
        let search = tabBarPage.tapSearchTab()
        search.searchFor("έγραψα")
        XCTAssertTrue(search.waitForResults(), "'έγραψα' must return results")
        waitForFirstResult(word: "γράφω", sources: greekToEnglish, query: "έγραψα")

        // The γράφω row's own caption: a `firstMatch` here could resolve in
        // another row (#143).
        let caption = firstCell.staticTexts.matching(identifier: AccessibilityIdentifiers.Search.formCaption).element
        XCTAssertTrue(caption.waitForExistence(timeout: TestData.Timeouts.medium), "the lemma row carries its caption")
        XCTAssertEqual(caption.label, "aorist, εγώ of γράφω", "VoiceOver reads the person as the Greek pronoun")

        let definition = search.tapSearchResult(at: 0)
        XCTAssertTrue(definition.waitForDefinitionToLoad(), "definition view must load")
        XCTAssertTrue(app.navigationBars["γράφω"].waitForExistence(timeout: TestData.Timeouts.medium),
                      "the lemma's definition opens")

        let history = tabBarPage.tapHistoryTab()
        XCTAssertTrue(history.waitForHistoryToLoad(), "History must load")
        XCTAssertTrue(history.verifyHistoryContainsWord("γράφω"), "History records the lemma")
        XCTAssertFalse(history.verifyHistoryContainsWord("έγραψα"), "not the typed form")
    }

    /// QA: the caption follows the UI language. For each language the app
    /// relaunches with `-AppleLanguages`, and έγραψα's first row γράφω reads
    /// "aorist 1sg of γράφω" in that language, spoken with the Greek pronoun
    /// ("аорист, εγώ от γράφω"). The Arabic label carries bidi controls (RLM,
    /// the lemma isolated), so labels are compared without them. A screenshot
    /// of the results is attached per language.
    func testCaptionInEachUILanguage() throws {
        let spoken: [(code: String, label: String)] = [
            ("en", "aorist, εγώ of γράφω"),
            ("ru", "аорист, εγώ от γράφω"),
            ("es", "aoristo, εγώ de γράφω"),
            ("el", "αόριστος, εγώ του γράφω"),
            ("ar", "الماضي البسيط, εγώ من γράφω"),
        ]
        let bidiControls: Set<Unicode.Scalar> = ["\u{200E}", "\u{200F}", "\u{2066}", "\u{2067}", "\u{2068}", "\u{2069}"]
        for (code, label) in spoken {
            app.terminate()
            app = XCUIApplication()
            app.launchArguments = ["-disableReviewPrompt", "-resetData", "-AppleLanguages", "(\(code))", "-AppleLocale", code] + UITestHelpers.packArguments()
            app.launch()
            XCTAssertTrue(app.waitForDictionariesReady(), "\(code): Search after launch")

            SearchPage(app: app).searchFor("έγραψα")
            waitForFirstResult(word: "γράφω", sources: greekToEnglish, query: "έγραψα (\(code))")
            let caption = firstCell.staticTexts.matching(identifier: AccessibilityIdentifiers.Search.formCaption).element
            XCTAssertTrue(caption.waitForExistence(timeout: TestData.Timeouts.medium), "\(code): the caption")
            let visible = String(String.UnicodeScalarView(caption.label.unicodeScalars.filter { !bidiControls.contains($0) }))
            XCTAssertEqual(visible, label, "\(code): the caption's VoiceOver text")

            // With the keyboard up: dismissing it finds two "Search" keys on
            // the Arabic iPadOS 26 keyboard.
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "egrapsa-\(code)"
            shot.lifetime = .keepAlways
            add(shot)
        }
    }

    // MARK: - Helpers

    private let greekToEnglish = [TestData.Sources.freedictEllEng, TestData.Sources.wordnetEllEng]

    private var firstCell: XCUIElement { app.collectionViews.firstMatch.cells.element(boundBy: 0) }

    /// Whether `cell` itself shows `source`'s badge. Counted within the cell:
    /// a `firstMatch` after `cells.element(boundBy:)` can resolve in another
    /// cell (#143).
    private func hasBadge(_ cell: XCUIElement, source: String) -> Bool {
        cell.descendants(matching: .any).matching(identifier: AccessibilityIdentifiers.Search.sourceBadge(source: source))
            .count > 0
    }

    /// Polls until the first result row is `word` with one of `sources`'
    /// badges: right after typing, the list can still show a partial query's
    /// results for one debounce cycle.
    private func waitForFirstResult(word: String, sources: [String], query: String, timeout: TimeInterval = 10,
                                    file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(timeout)
        var matched = false
        repeat {
            let cell = firstCell
            matched = cell.exists
                && cell.staticTexts.matching(NSPredicate(format: "label == %@", word)).count > 0
                && sources.contains { hasBadge(cell, source: $0) }
            if matched { break }
            Thread.sleep(forTimeInterval: 0.2)
        } while Date() < deadline
        XCTAssertTrue(matched, "'\(query)': first result must be '\(word)' from \(sources)", file: file, line: line)
    }
}

// MARK: - Issue #143: search by inflected English form

extension WordFormsSearchFlowTests {
    /// `went` (WordNet morphy): its own row from En–El · FD comes first,
    /// uncaptioned, then go, captioned "form of go", which VoiceOver reads as
    /// shown; that row opens go. The caption queries count within one cell:
    /// a `firstMatch` after `cells.element(boundBy:)` can resolve in another
    /// cell.
    func testEnglishIrregularQuery() throws {
        let search = tabBarPage.tapSearchTab()
        search.searchFor("went")
        XCTAssertTrue(search.waitForResults(), "'went' must return results")
        waitForFirstResult(word: "went", sources: [TestData.Sources.freedictEngEll], query: "went")
        let formCaption = AccessibilityIdentifiers.Search.formCaption
        XCTAssertEqual(firstCell.staticTexts.matching(identifier: formCaption).count, 0, "went's own row has no caption")

        let lemmaCell = app.collectionViews.firstMatch.cells.element(boundBy: 1)
        let caption = lemmaCell.staticTexts.matching(identifier: formCaption).element
        XCTAssertTrue(caption.waitForExistence(timeout: TestData.Timeouts.medium), "the second row carries a caption")
        XCTAssertEqual(lemmaCell.staticTexts.matching(NSPredicate(format: "label == %@", "go")).count, 1,
                       "the second row is go")
        XCTAssertEqual(caption.label, "form of go")

        let definition = search.tapSearchResult(at: 1)
        XCTAssertTrue(definition.waitForDefinitionToLoad(), "definition view must load")
        XCTAssertTrue(app.navigationBars["go"].waitForExistence(timeout: TestData.Timeouts.medium),
                      "go's definition opens")
    }

    /// QA: an English caption follows the UI language too. cities has no
    /// row of its own, so its first row is city, captioned "plural of city"
    /// in each language (Arabic compared without its bidi controls). A
    /// screenshot of the results is attached per language.
    func testEnglishCaptionInEachUILanguage() throws {
        let spoken: [(code: String, label: String)] = [
            ("en", "plural of city"),
            ("ru", "мн. ч. от city"),
            ("es", "pl. de city"),
            ("el", "πληθυντικός του city"),
            ("ar", "الجمع من city"),
        ]
        let english = [TestData.Sources.wordnet, TestData.Sources.freedictEngSpa, TestData.Sources.freedictEngEll,
                       TestData.Sources.wordnetEngEll]
        let bidiControls: Set<Unicode.Scalar> = ["\u{200E}", "\u{200F}", "\u{2066}", "\u{2067}", "\u{2068}", "\u{2069}"]
        for (code, label) in spoken {
            app.terminate()
            app = XCUIApplication()
            app.launchArguments = ["-disableReviewPrompt", "-resetData", "-AppleLanguages", "(\(code))", "-AppleLocale", code] + UITestHelpers.packArguments()
            app.launch()
            XCTAssertTrue(app.waitForDictionariesReady(), "\(code): Search after launch")

            SearchPage(app: app).searchFor("cities")
            waitForFirstResult(word: "city", sources: english, query: "cities (\(code))")
            let caption = firstCell.staticTexts.matching(identifier: AccessibilityIdentifiers.Search.formCaption).element
            XCTAssertTrue(caption.waitForExistence(timeout: TestData.Timeouts.medium), "\(code): the caption")
            let visible = String(String.UnicodeScalarView(caption.label.unicodeScalars.filter { !bidiControls.contains($0) }))
            XCTAssertEqual(visible, label, "\(code): the caption's VoiceOver text")

            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "cities-\(code)"
            shot.lifetime = .keepAlways
            add(shot)
        }
    }
}
