import UIKit
import XCTest

/// 0130, #155: Import, from the Lists screen's "+" and the Learn home's
/// "Import a list": a file (`-importListFixture <path>` makes "Import a
/// file" read it instead of opening the file picker) or text pasted from
/// Quizlet, its preview, the "Learn %@ via %@?" question for a language not
/// learned, the result, and the Formats help. English UI, `-resetData`, the
/// packs installed from the committed assets. Fixtures: Kirill's committed
/// CSVs and the files next to `DictAppTests.swift`, read through `#filePath`
/// (the simulator shares the Mac's file system).
final class WordListImportTests: XCTestCase {

    var app: XCUIApplication!
    var tabBarPage: TabBarPage!

    private static let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // TestCases
        .deletingLastPathComponent()  // DictAppUITests
        .deletingLastPathComponent()  // DictApp
        .deletingLastPathComponent()  // the repository

    private static func fixture(_ path: String) -> String {
        repository.appendingPathComponent(path).path
    }

    private static let kirillA1 = fixture("Scripts/data/wordlists/ky-ell-a1.csv")
    private static let brokenList = fixture("DictApp/DictAppTests/broken-list.csv")
    private static let ankiExport = fixture("DictApp/DictAppTests/anki-notes-plain-text.txt")
    private static let quizletPaste = fixture("DictApp/DictAppTests/quizlet-paste.txt")

    /// Launch arguments after `-resetData`, per test.
    private var testArguments: [String] {
        if name.contains("testImportKirillsA1") {
            return ["-learningLanguages", "ell", "-importListFixture", Self.kirillA1]
        }
        if name.contains("testBrokenRowShowsInPreview") {
            return ["-learningLanguages", "ell", "-importListFixture", Self.brokenList]
        }
        if name.contains("testImportInANewLanguageAsks") {
            return ["-learningLanguages", "ell", "-importListFixture", Self.ankiExport]
        }
        if name.contains("testImportedListAppearsWithItsCount") { return ["-learningLanguages", "spa"] }
        return ["-learningLanguages", "ell"]
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = LibreDictApp()
        app.launchArguments = ["-disableReviewPrompt", "-resetData"] + testArguments + UITestHelpers.packArguments()
        // Lists of thousands of rows: silence the app's os_log so XCTest's
        // log volume cannot crash it while it scrolls (iOS 17.5, #125).
        app.launchEnvironment["OS_ACTIVITY_MODE"] = "disable"
        // Sim orientation persists across sessions; landscape breaks swipes.
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        tabBarPage = TabBarPage(app: app)
    }

    override func tearDownWithError() throws {
        app = nil
        tabBarPage = nil
    }

    // MARK: - Helpers

    /// Learn tab → home → All lists.
    private func openLists() -> WordListsPage {
        let learnPage = tabBarPage.tapLearnTab()
        XCTAssertTrue(learnPage.waitForHome(timeout: TestData.Timeouts.long), "the Learn home")
        return learnPage.tapAllLists()
    }

    /// Paste text: the runner puts `text` on the pasteboard, then SwiftUI's
    /// Paste button (no paste alert) and Preview.
    private func paste(_ text: String, into page: ListImportPage) {
        UIPasteboard.general.string = text
        XCTAssertTrue(page.pasteRow.waitForExistence(timeout: TestData.Timeouts.medium), "Paste text")
        page.pasteRow.tap()
        XCTAssertTrue(page.pasteButton.waitForExistence(timeout: TestData.Timeouts.medium), "the Paste button")
        page.pasteButton.tap()
        let first = String(text.prefix { $0 != "\t" })
        let pasted = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", first),
                                               object: page.textBox)
        XCTAssertEqual(XCTWaiter.wait(for: [pasted], timeout: TestData.Timeouts.medium), .completed,
                       "the text box holds the pasteboard's text")
        XCTAssertTrue(page.nextButton.isEnabled)
        page.nextButton.tap()
        XCTAssertTrue(page.preview.waitForExistence(timeout: TestData.Timeouts.long), "the preview")
    }

    // MARK: - Files

    /// #130, #155: Kirill's A1 file imports without edits: the preview
    /// reads "1,457 words · 39 merged · 0 rows with errors", named after the
    /// file, Greek, comma; Import; the list row shows 1,457 words.
    func testImportKirillsA1() throws {
        let lists = openLists()
        let page = lists.openImport()
        page.importFile()
        XCTAssertTrue(page.wait(for: page.summary, toBe: "1,457 words · 39 merged · 0 rows with errors"),
                      "got \(page.summary.label)")
        XCTAssertEqual(page.name.value as? String, "ky-ell-a1", "named after the file")
        XCTAssertTrue(page.language.label.contains("Greek"), "guessed from the script: \(page.language.label)")
        XCTAssertTrue(page.delimiter.label.contains("Comma"), page.delimiter.label)
        XCTAssertTrue(app.staticTexts["Term · Translation · Level · Endings"].exists, "the columns found")
        XCTAssertEqual(page.errorRows.count, 0)

        page.confirm()
        XCTAssertTrue(page.result.waitForExistence(timeout: TestData.Timeouts.long), "the result")
        XCTAssertTrue(page.result.label.hasPrefix("Imported 1,457 words, "), page.result.label)
        XCTAssertTrue(page.result.label.hasSuffix(" found in the dictionaries"), page.result.label)
        page.done()

        let row = lists.importedRows.firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: TestData.Timeouts.medium) || app.scrollToElement(row),
                      "the new list under My lists")
        XCTAssertTrue(app.scrollToElement(row))
        XCTAssertEqual(lists.importedCounts.firstMatch.label, "1,457 words")
        XCTAssertTrue(app.staticTexts["ky-ell-a1"].exists, "titled after the file")
    }

    /// #130, #155: `broken-list.csv`: two broken rows in the preview with
    /// their line numbers, text and reason; Import saves the other four.
    func testBrokenRowShowsInPreview() throws {
        let lists = openLists()
        let page = lists.openImport()
        page.importFile()
        XCTAssertTrue(page.wait(for: page.summary, toBe: "4 words · 0 merged · 2 rows with errors"),
                      "got \(page.summary.label)")
        let rows = page.errorRows
        XCTAssertEqual(rows.count, 2)
        let first = rows.element(boundBy: 0).label, second = rows.element(boundBy: 1).label
        XCTAssertTrue(first.contains("Line 4") && first.contains("No word in this row"), first)
        XCTAssertTrue(second.contains("Line 5") && second.contains("A quote is never closed"), second)
        XCTAssertTrue(second.contains("νερό,\"water"), "the row's text: \(second)")

        page.confirm()
        XCTAssertTrue(page.result.waitForExistence(timeout: TestData.Timeouts.long), "the result")
        XCTAssertTrue(page.result.label.hasPrefix("Imported 4 words, "), page.result.label)
        page.done()
        let row = lists.importedRows.firstMatch
        XCTAssertTrue(app.scrollToElement(row), "the new list")
        XCTAssertEqual(lists.importedCounts.firstMatch.label, "4 words", "the count excludes the broken rows")
    }

    /// #155 (Kirill, 2026-11-03), English UI, Greek learned, an English
    /// file (the Anki export): Import asks "Learn English via English?".
    /// No: saved, not on Lists. Yes on a second import: English joins the
    /// Learn home's switch, and both lists show.
    func testImportInANewLanguageAsks() throws {
        let lists = openLists()
        var page = lists.openImport()
        page.importFile()
        XCTAssertTrue(page.language.label.contains("English"), "guessed from the script: \(page.language.label)")
        XCTAssertTrue(page.wait(for: page.summary, toBe: "5 words · 0 merged · 0 rows with errors"),
                      "got \(page.summary.label)")
        page.confirm()
        let alert = app.alerts["Learn English via English?"]
        XCTAssertTrue(alert.waitForExistence(timeout: TestData.Timeouts.medium), "Import asks first")
        alert.buttons["No"].tap()
        XCTAssertTrue(page.result.waitForExistence(timeout: TestData.Timeouts.long), "No saves the list")
        page.done()
        XCTAssertTrue(app.scrollToElement(lists.row("my-words")), "My lists")
        XCTAssertFalse(lists.importedRows.firstMatch.exists, "English is not learned: the list is hidden")

        page = lists.openImport()
        page.importFile()
        page.confirm()
        XCTAssertTrue(alert.waitForExistence(timeout: TestData.Timeouts.medium), "asked again")
        alert.buttons["Yes"].tap()
        XCTAssertTrue(page.result.waitForExistence(timeout: TestData.Timeouts.long), "Yes saves the list")
        page.done()
        XCTAssertTrue(app.scrollToElement(lists.row("cefr-eng-a1")), "English is learned: its lists show")
        XCTAssertTrue(app.scrollToElement(lists.importedRows.element(boundBy: 1), maxSwipes: 12),
                      "both English imports show")

        let learnPage = LearnPage(app: app)
        learnPage.popToRoot()
        XCTAssertTrue(learnPage.waitForHome(), "the Learn home")
        XCTAssertTrue(learnPage.languageSwitch.waitForExistence(timeout: TestData.Timeouts.medium),
                      "the switch: Greek | English")
        XCTAssertTrue(learnPage.languageSwitch.buttons["English"].exists)
        XCTAssertTrue(learnPage.languageSwitch.buttons["Greek"].exists)
    }

    // MARK: - Paste

    /// #130, #155: a Quizlet export pasted as text: the runner sets the
    /// pasteboard, the Paste button fills the box, Preview shows "5 words",
    /// named "Pasted list"; Import; the list row shows 5 words.
    func testPasteFromQuizlet() throws {
        let text = try String(contentsOfFile: Self.quizletPaste, encoding: .utf8)
        let lists = openLists()
        let page = lists.openImport()
        paste(text, into: page)
        XCTAssertTrue(page.wait(for: page.summary, toBe: "5 words · 0 merged · 0 rows with errors"),
                      "got \(page.summary.label)")
        XCTAssertEqual(page.name.value as? String, "Pasted list")
        XCTAssertTrue(page.delimiter.label.contains("Tab"), page.delimiter.label)
        XCTAssertTrue(page.language.label.contains("Greek"), page.language.label)
        page.confirm()
        XCTAssertTrue(page.result.waitForExistence(timeout: TestData.Timeouts.long), "the result")
        XCTAssertTrue(page.result.label.hasPrefix("Imported 5 words, "), page.result.label)
        page.done()
        XCTAssertTrue(app.scrollToElement(lists.importedRows.firstMatch), "the new list")
        XCTAssertEqual(lists.importedCounts.firstMatch.label, "5 words")
        XCTAssertTrue(app.staticTexts["Pasted list"].exists)
    }

    /// #154, #155, Spanish learned (no built-in lists): the Learn home's
    /// "Import a list" opens Import; a pasted list, guessed English from its
    /// Latin script, is changed to Spanish and imported without a question;
    /// the home then offers "Choose lists" and the Lists screen shows the
    /// list with its count.
    func testImportedListAppearsWithItsCount() throws {
        let learnPage = tabBarPage.tapLearnTab()
        XCTAssertTrue(learnPage.waitForHome(timeout: TestData.Timeouts.long), "the Learn home")
        XCTAssertTrue(learnPage.importList.waitForExistence(timeout: TestData.Timeouts.medium), "Import a list")
        learnPage.importList.tap()
        let page = ListImportPage(app: app)
        XCTAssertTrue(page.waitForSources(), "Import a list opens Import")
        paste("casa\thouse\nperro\tdog\ngato\tcat\n", into: page)
        XCTAssertTrue(page.language.label.contains("English"), "Latin guesses English: \(page.language.label)")
        page.choose("Spanish", in: page.language)
        let spanish = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS 'Spanish'"),
                                                object: page.language)
        XCTAssertEqual(XCTWaiter.wait(for: [spanish], timeout: TestData.Timeouts.medium), .completed)
        page.confirm()
        XCTAssertTrue(page.result.waitForExistence(timeout: TestData.Timeouts.long), "Spanish is learned: no question")
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertTrue(page.result.label.hasPrefix("Imported 3 words, "), page.result.label)
        page.done()

        XCTAssertTrue(learnPage.chooseLists.waitForExistence(timeout: TestData.Timeouts.medium),
                      "Spanish has a list now: Choose lists")
        let lists = learnPage.tapAllLists()
        XCTAssertTrue(app.scrollToElement(lists.importedRows.firstMatch), "the new list")
        XCTAssertEqual(lists.importedCounts.firstMatch.label, "3 words")
        XCTAssertTrue(app.staticTexts["Pasted list"].exists)
    }

    // MARK: - Formats

    /// #155 (Kirill, 2026-11-03): Formats opens the help with its three
    /// examples, kept as they are: a CSV with `term,translation,level`, an
    /// Anki plain-text export, text pasted from Quizlet.
    func testFormatsHelp() throws {
        let page = openLists().openImport()
        XCTAssertTrue(page.formatsRow.waitForExistence(timeout: TestData.Timeouts.medium), "Formats")
        page.formatsRow.tap()
        XCTAssertTrue(page.help.waitForExistence(timeout: TestData.Timeouts.medium), "the Formats help")
        XCTAssertTrue(app.navigationBars["Formats you can import"].exists)
        let examples = app.staticTexts.matching(identifier: AccessibilityIdentifiers.ListImport.example)
        let starts = ["term,translation,level", "#separator:tab", "σπίτι    house"]
        for (index, start) in starts.enumerated() {
            let example = examples.element(boundBy: index)
            XCTAssertTrue(app.scrollToElement(example), "example \(index + 1)")
            XCTAssertTrue(example.label.hasPrefix(start), "example \(index + 1): \(example.label)")
        }
        XCTAssertTrue(app.staticTexts["A Quizlet set exported and pasted as text"].exists)
        XCTAssertTrue(app.staticTexts["An Anki deck exported as “Notes in Plain Text”"].exists)
    }
}
