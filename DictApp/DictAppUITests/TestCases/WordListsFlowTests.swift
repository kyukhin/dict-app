import XCTest

/// 0130, #154: the Lists screen, a list's screen and New words from,
/// reached from the Learn home. English UI, `-resetData`, then
/// `-wordListFixture lists`: the imported "Greek fixture" (σπίτι το, γράφω,
/// έχει αέρα at A1, αγάπη η at A2, βιβλίο without a level or translation)
/// and the newer "English fixture" (house, water).
///
/// From the test plan, the built-in lists' rows and counts
/// (`testBuiltInListsShowTheirCounts`, `testGreekB1ShowsAllItsWords`) wait
/// for #152 and 0237's install of the packs; the meanings from the pair's
/// dictionary (`testEnglishListMeaningsFollowTheVia`) for #159's `meanings`
/// and the packs; New words from feeding Start for #161.
final class WordListsFlowTests: XCTestCase {

    var app: XCUIApplication!
    var tabBarPage: TabBarPage!

    private let greek = "user-fixture-greek"
    private let english = "user-fixture-english"

    /// Greek only for the learned-languages test, else Greek and English.
    private var learned: String {
        name.contains("testListsFollowLearnedLanguages") || name.contains("testChooseListsOpensNewWordsFrom")
            ? "ell" : "ell,eng"
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-disableReviewPrompt", "-resetData", "-learningLanguages", learned,
                               "-wordListFixture", "lists"]
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
        XCTAssertTrue(learnPage.waitForHome(), "the Learn home")
        return learnPage.tapAllLists()
    }

    /// The Lists screen → list `id`.
    private func openList(_ id: String) -> WordListsPage {
        let page = openLists()
        page.openList(id)
        return page
    }

    // MARK: - Tests

    /// `-learningLanguages ell`: My lists holds My words and the Greek
    /// import with its count, not the English one; the "+" is there.
    func testListsFollowLearnedLanguages() throws {
        let page = openLists()
        XCTAssertTrue(page.row("my-words").waitForExistence(timeout: TestData.Timeouts.medium), "My words")
        XCTAssertTrue(page.row(greek).exists, "the Greek import")
        XCTAssertFalse(page.row(english).exists, "English is not learned: its import hides")
        XCTAssertEqual(page.count(greek).label, "5 words")
        XCTAssertEqual(page.count("my-words").label, "0 words")
        XCTAssertTrue(page.importButton.exists, "the + of Import (#155)")
        XCTAssertLessThan(page.row("my-words").frame.minY, page.row(greek).frame.minY, "My words first")
        XCTAssertTrue(app.navigationBars["Lists"].exists, "titled Lists")
    }

    /// Greek and English learned: both imports, newest first, with counts.
    func testImportedListsShowTheirCounts() throws {
        let page = openLists()
        XCTAssertTrue(page.row(english).waitForExistence(timeout: TestData.Timeouts.medium))
        XCTAssertEqual(page.count(english).label, "2 words")
        XCTAssertEqual(page.count(greek).label, "5 words")
        XCTAssertLessThan(page.row(english).frame.minY, page.row(greek).frame.minY, "the newer import first")
    }

    /// A list's screen: its count, Learn this list, the words alphabetical
    /// in a section per level (A1, A2, then none), each with its meaning.
    func testListShowsItsWordsByLevel() throws {
        let page = openList(greek)
        XCTAssertTrue(app.navigationBars["Greek fixture"].waitForExistence(timeout: TestData.Timeouts.medium))
        XCTAssertTrue(app.staticTexts["5 words"].exists, "the count at the top")
        XCTAssertEqual(page.learnButton.label, "Learn this list")
        let terms = ["γράφω", "έχει αέρα", "σπίτι", "αγάπη", "βιβλίο"]
        for term in terms {
            XCTAssertTrue(page.word(term).waitForExistence(timeout: TestData.Timeouts.medium), term)
        }
        let tops = terms.map { page.word($0).frame.minY }
        XCTAssertEqual(tops, tops.sorted(), "A1 alphabetical, then A2, then the word without a level")
        XCTAssertEqual(page.word("σπίτι").value as? String, "house", "the import's translation")
        XCTAssertEqual(page.word("βιβλίο").value as? String, "noun", "no translation: the part of speech")
        XCTAssertTrue(app.staticTexts["A1"].exists && app.staticTexts["A2"].exists, "a header per level")
    }

    /// σπίτι opens its Definition.
    func testTapOpensDefinition() throws {
        let page = openList(greek)
        page.tapWord("σπίτι")
        let definition = DefinitionPage(app: app)
        XCTAssertTrue(definition.waitForDefinitionToLoad(), "σπίτι opens its Definition")
        XCTAssertTrue(app.navigationBars["σπίτι"].waitForExistence(timeout: TestData.Timeouts.medium))
        XCTAssertTrue(definition.verifyDefinitionContainsText("house"), "El–En · FD's entry, the pair's first")
    }

    /// έχει αέρα shows "it is windy", is no button and pushes nothing.
    func testStandaloneWordShowsItsTranslation() throws {
        let page = openList(greek)
        let windy = page.word("έχει αέρα")
        XCTAssertTrue(windy.waitForExistence(timeout: TestData.Timeouts.medium))
        XCTAssertEqual(windy.value as? String, "it is windy")
        XCTAssertFalse(app.buttons.matching(identifier: AccessibilityIdentifiers.WordLists.item)
                        .matching(NSPredicate(format: "label == %@", "έχει αέρα")).firstMatch.exists,
                       "no chevron: not a button")
        windy.tap()
        XCTAssertFalse(app.descendants(matching: .any)[AccessibilityIdentifiers.Definition.definitionView]
                        .waitForExistence(timeout: TestData.Timeouts.short), "tapping it pushes nothing")
        XCTAssertTrue(page.listScreen.exists)
    }

    /// Learn this list on Greek, then English: both rows carry the badge
    /// and the button reads "Learning this list"; a second tap on English
    /// removes its badge; Greek's survives a relaunch.
    func testLearnThisListAddsTheBadge() throws {
        let page = openList(greek)
        page.learnButton.tap()
        XCTAssertTrue(page.wait(for: page.learnButton, toBe: "Learning this list"))
        page.goBack()
        XCTAssertTrue(page.badge(greek).waitForExistence(timeout: TestData.Timeouts.medium), "Greek's badge")
        XCTAssertEqual(page.badge(greek).label, "Learning")

        page.openList(english)
        page.learnButton.tap()
        XCTAssertTrue(page.wait(for: page.learnButton, toBe: "Learning this list"))
        page.goBack()
        XCTAssertTrue(page.badge(english).waitForExistence(timeout: TestData.Timeouts.medium), "English's badge")
        XCTAssertTrue(page.badge(greek).exists)

        page.openList(english)
        XCTAssertTrue(page.wait(for: page.learnButton, toBe: "Learning this list"))
        page.learnButton.tap()
        XCTAssertTrue(page.wait(for: page.learnButton, toBe: "Learn this list"), "a second tap unchecks")
        page.goBack()
        XCTAssertTrue(page.badge(english).waitForNonExistence(timeout: TestData.Timeouts.medium), "English's badge goes")
        XCTAssertTrue(page.badge(greek).exists)

        app.terminate()
        app.launchArguments = ["-disableReviewPrompt"]
        app.launch()
        tabBarPage = TabBarPage(app: app)
        let relaunched = openLists()
        XCTAssertTrue(relaunched.badge(greek).waitForExistence(timeout: TestData.Timeouts.medium), "kept after a relaunch")
        XCTAssertFalse(relaunched.badge(english).exists)
    }

    /// Greek only: "Choose lists" opens New words from with the Greek
    /// import, unchecked, and the footer; checking it hides the footer;
    /// back home, the Lists section shows it with "New words from", and
    /// Today counts its 5 new words.
    func testChooseListsOpensNewWordsFrom() throws {
        let learnPage = tabBarPage.tapLearnTab()
        XCTAssertTrue(learnPage.waitForHome())
        XCTAssertFalse(learnPage.newWordsFromRow.exists, "Today offers Choose lists instead")
        let page = learnPage.tapChooseLists()
        let row = page.newWordsFromRow(greek)
        XCTAssertTrue(row.waitForExistence(timeout: TestData.Timeouts.medium))
        XCTAssertFalse(page.newWordsFromRow(english).exists, "English is not learned")
        XCTAssertFalse(page.newWordsFromRow("my-words").exists, "My words is not on it")
        XCTAssertFalse(row.isSelected)
        XCTAssertTrue(page.noneChecked.exists, "No list checked.")
        XCTAssertTrue(app.staticTexts["Lower levels come first: A1, then A2 and up. Lists without levels come last."].exists)

        row.tap()
        XCTAssertTrue(page.wait(for: row, selected: true), "checked")
        XCTAssertTrue(page.noneChecked.waitForNonExistence(timeout: TestData.Timeouts.medium))
        page.goBack()

        XCTAssertTrue(learnPage.listRow(greek).waitForExistence(timeout: TestData.Timeouts.medium),
                      "the Lists section shows the checked list")
        XCTAssertTrue(learnPage.newWordsFromRow.exists, "and New words from")
        XCTAssertFalse(learnPage.chooseLists.exists)
        XCTAssertTrue(learnPage.waitForLabel(of: learnPage.newCount, toBe: "5 new words left today"))
    }

    /// New words from lists both languages' imports; a second tap unchecks.
    func testNewWordsFromChecksAndUnchecks() throws {
        let learnPage = tabBarPage.tapLearnTab()
        XCTAssertTrue(learnPage.waitForHome())
        let page = learnPage.tapChooseLists()
        let greekRow = page.newWordsFromRow(greek)
        let englishRow = page.newWordsFromRow(english)
        XCTAssertTrue(greekRow.waitForExistence(timeout: TestData.Timeouts.medium))
        XCTAssertTrue(englishRow.exists)
        englishRow.tap()
        greekRow.tap()
        XCTAssertTrue(page.wait(for: greekRow, selected: true))
        XCTAssertTrue(page.wait(for: englishRow, selected: true))
        englishRow.tap()
        XCTAssertTrue(page.wait(for: englishRow, selected: false), "a second tap unchecks")
        page.goBack()
        let lists = learnPage.tapAllLists()
        XCTAssertTrue(lists.badge(greek).waitForExistence(timeout: TestData.Timeouts.medium))
        XCTAssertFalse(lists.badge(english).exists)
    }

    /// Swipe to delete an imported list, after an alert; Cancel keeps it.
    func testDeleteImportedList() throws {
        let page = openLists()
        page.swipeToDelete(greek)
        let alert = app.alerts["Delete “Greek fixture”?"]
        XCTAssertTrue(alert.waitForExistence(timeout: TestData.Timeouts.medium), "the alert asks first")
        XCTAssertTrue(alert.staticTexts["Progress on its words is kept."].exists)
        alert.buttons["Cancel"].tap()
        XCTAssertTrue(page.row(greek).waitForExistence(timeout: TestData.Timeouts.medium), "Cancel keeps it")

        page.swipeToDelete(greek)
        XCTAssertTrue(alert.waitForExistence(timeout: TestData.Timeouts.medium))
        alert.buttons["Delete"].tap()
        XCTAssertTrue(page.row(greek).waitForNonExistence(timeout: TestData.Timeouts.medium), "Delete removes it")
        XCTAssertTrue(page.row(english).exists)
    }

    /// My words opens its list screen: no Learn this list, its words with
    /// a snippet of their entry.
    func testMyWordsIsAList() throws {
        let search = tabBarPage.tapSearchTab()
        search.searchFor("γράφω")
        XCTAssertTrue(search.waitForResults())
        let definition = search.tapResult(word: "γράφω", source: TestData.Sources.freedictEllEng)
        XCTAssertTrue(definition.waitForDefinitionToLoad())
        definition.learn()

        let myWords = tabBarPage.tapLearnTab().tapMyWords()
        XCTAssertTrue(myWords.waitForWord("γράφω"))
        let page = WordListsPage(app: app)
        XCTAssertTrue(page.listScreen.exists, "E3's list screen")
        XCTAssertFalse(page.learnButton.exists, "My words has no Learn this list")
        XCTAssertEqual(page.word("γράφω").value as? String, "verb 1. write", "a snippet of its entry")
    }
}
