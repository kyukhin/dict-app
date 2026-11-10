import XCTest

/// #180: Credits, opened from the row right under the version in Settings,
/// lists every data source the app ships with its license, GRDB.swift under
/// Software with its MIT text, and the Licenses section names each license
/// with its URL. English UI, no packs: the lines
/// are in the app whether a pack is installed or not (0237). Arabic is
/// `ArabicLocalizationTests.testCreditsRightToLeft`.
final class CreditsFlowTests: XCTestCase {
    private typealias IDs = AccessibilityIdentifiers.Credits

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = LibreDictApp()
        app.launchArguments += ["-disableReviewPrompt", "-resetData", UITestHelpers.skipWelcome]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        XCTAssertTrue(app.waitForDictionariesReady(), "Search screen after launch")
    }

    override func tearDownWithError() throws {
        app = nil
    }

    /// The Credits row sits right under the version; Credits lists the 13
    /// data source lines, each naming its license, the GRDB.swift row, which
    /// opens its license verbatim, and the 8 licenses, each with its URL.
    /// The placeholder is gone.
    func testCreditsListEverySourceAndLicense() throws {
        _ = TabBarPage(app: app).tapSettingsTab()
        let link = app.descendants(matching: .any)[IDs.link].firstMatch
        XCTAssertTrue(app.scrollToElement(link), "the Credits row in Settings")
        let version = app.descendants(matching: .any)[AccessibilityIdentifiers.Settings.versionValue].firstMatch
        XCTAssertTrue(version.exists, "the version row")
        XCTAssertGreaterThanOrEqual(link.frame.minY, version.frame.maxY - 1, "Credits is under the version")
        XCTAssertLessThan(link.frame.minY - version.frame.maxY, 20, "right under it")
        link.tap()
        XCTAssertTrue(app.navigationBars["Credits"].waitForExistence(timeout: TestData.Timeouts.medium))

        let wordnet = app.staticTexts[IDs.line("wordnet")]
        XCTAssertTrue(wordnet.waitForExistence(timeout: TestData.Timeouts.medium), "the WordNet line")
        XCTAssertEqual(wordnet.label, "WordNet — Princeton University, WordNet 3.0 License")
        let licenseNames = Dictionary(uniqueKeysWithValues: IDs.licenses.map { ($0.id, $0.name) })
        let named: [String: String] = [
            "wordnet": "wordnet", "openrussian": "cc_by_sa_4_0", "freedict": "cc_by_sa_3_0",
            "spanish_wordnet": "cc_by_3_0", "arabic_wordnet": "cc_by_sa_3_0", "greek_wordnet": "apache_2_0",
            "wiktionary": "cc_by_sa_4_0", "greek_lists": "cc_by_sa_4_0", "octanove": "cc_by_sa_4_0",
            "frequency_words": "cc_by_sa_4_0", "tatoeba": "cc_by_2_0_fr", "greek_grammar": "cc_by_sa_4_0",
        ]
        for id in IDs.lines {
            let line = app.staticTexts[IDs.line(id)]
            XCTAssertTrue(app.scrollToElement(line), "the \(id) line")
            if let license = named[id].flatMap({ licenseNames[$0] }) {
                XCTAssertTrue(line.label.contains(license), "\(id) names \(license): \(line.label)")
            } else {
                XCTAssertTrue(line.label.hasPrefix("The CEFR-J Wordlist Version 1.5."), "the citation: \(line.label)")
            }
        }

        let grdb = app.descendants(matching: .any)[IDs.grdb].firstMatch
        XCTAssertTrue(app.scrollToElement(grdb), "the GRDB.swift row under Software")
        XCTAssertTrue(grdb.label.contains("GRDB.swift by Gwendal Roué, MIT License"), grdb.label)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "Software")).firstMatch.exists,
                      "the Software header")
        grdb.tap()
        XCTAssertTrue(app.navigationBars["GRDB.swift"].waitForExistence(timeout: TestData.Timeouts.medium),
                      "the license screen")
        let text = app.staticTexts[IDs.softwareLicenseText]
        XCTAssertTrue(text.waitForExistence(timeout: TestData.Timeouts.medium), "the license text")
        XCTAssertTrue(text.label.hasPrefix("Copyright (C) 2015-2024 Gwendal Roué"), "the copyright line")
        XCTAssertTrue(text.label.contains("The above copyright notice and this permission notice shall be included"),
                      "the permission notice")
        attachScreenshot("GRDB.swift license")
        // The back button carries the previous title: tap it by position.
        app.navigationBars.firstMatch.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Credits"].waitForExistence(timeout: TestData.Timeouts.medium))

        let header = app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "Licenses")).firstMatch
        XCTAssertTrue(app.scrollToElement(header), "the Licenses section")
        for license in IDs.licenses {
            let row = app.descendants(matching: .any)[IDs.license(license.id)].firstMatch
            XCTAssertTrue(app.scrollToElement(row), "the \(license.name) row")
            XCTAssertTrue(row.label.contains(license.name), "\(license.id): \(row.label)")
            XCTAssertTrue(row.label.contains(license.url), "\(license.id): \(row.label)")
            let name = row.staticTexts[license.name]
            XCTAssertTrue(name.exists, "\(license.id): the name")
            // Nearer the left edge than the right (the row inset is 40 pt on iOS 17).
            let window = app.windows.firstMatch.frame
            XCTAssertLessThan(name.frame.minX - window.minX, window.maxX - name.frame.maxX,
                              "LTR: \(license.name) on the left; \(name.frame)")
        }
        XCTAssertFalse(app.staticTexts["Full license information coming soon."].exists, "no placeholder")
        attachScreenshot("credits, licenses")
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
