import XCTest

/// Issue #325: Definition's speaker reads the search target. Opened from a
/// Search row whose headword the query matched, an entry with a
/// translation in another language reads the translation's first sense
/// line; a one-language dictionary reads the headword. The button's
/// `value` is the text it reads.
final class SpeakerTargetTests: XCTestCase {

    var app: XCUIApplication!
    var tabBarPage: TabBarPage!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = LibreDictApp()
        app.launchArguments.append("-disableReviewPrompt")
        app.launchArguments += UITestHelpers.packArguments("ell")
        app.launchArguments.append("-resetData")

        // iOS 26 "Enable Dictation?" springboard alert.
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

        XCUIDevice.shared.orientation = .portrait
        app.launch()
        tabBarPage = TabBarPage(app: app)
    }

    override func tearDownWithError() throws {
        app = nil
        tabBarPage = nil
    }

    /// hello: the En–El row reads its Greek translation, the WordNet row hello.
    func testSpeakerReadsTheSearchTarget() throws {
        let search = tabBarPage.tapSearchTab()
        search.searchFor("hello")
        XCTAssertTrue(search.waitForResults(), "'hello' must return results")

        let enEl = search.tapResult(word: "hello", source: TestData.Sources.freedictEngEll)
        XCTAssertTrue(enEl.waitForDefinitionToLoad(), "the En–El definition loads")
        XCTAssertEqual(spokenText(enEl), "εμπρός, γεία σας, γεία σου", "En–El hello reads its Greek translation")

        let back = enEl.navigateBack()
        XCTAssertTrue(back.waitForResults(), "the results are back")
        let wordnet = back.tapResult(word: "hello", source: TestData.Sources.wordnet)
        XCTAssertTrue(wordnet.waitForDefinitionToLoad(), "the WordNet definition loads")
        XCTAssertEqual(spokenText(wordnet), "hello", "WordNet hello reads the headword")
    }

    /// The same En–El hello reopened from History reads its headword: no
    /// Search row opened it, so the speaker reads as before #325.
    func testHistoryReadsTheHeadword() throws {
        let search = tabBarPage.tapSearchTab()
        search.searchFor("hello")
        XCTAssertTrue(search.waitForResults(), "'hello' must return results")
        let fromSearch = search.tapResult(word: "hello", source: TestData.Sources.freedictEngEll)
        XCTAssertTrue(fromSearch.waitForDefinitionToLoad(), "the En–El definition loads")
        XCTAssertEqual(spokenText(fromSearch), "εμπρός, γεία σας, γεία σου", "from Search: the Greek translation")

        let history = tabBarPage.tapHistoryTab()
        XCTAssertTrue(history.waitForHistoryToLoad(), "History should load")
        let fromHistory = history.tapHistoryItem(at: 0)
        XCTAssertTrue(fromHistory.waitForDefinitionToLoad(), "the definition loads from History")
        XCTAssertTrue(fromHistory.verifyDefinitionContainsText("εμπρ"), "History reopens the En–El entry")
        XCTAssertEqual(spokenText(fromHistory), "hello", "from History: the headword")
    }

    /// The speaker's `value`, NFC.
    private func spokenText(_ page: DefinitionPage) -> String {
        ((page.speakButton.value as? String) ?? "").precomposedStringWithCanonicalMapping
    }
}
