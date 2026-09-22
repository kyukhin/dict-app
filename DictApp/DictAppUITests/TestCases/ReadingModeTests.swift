import XCTest

/// Issue #5 — Reading Mode (keep screen awake).
///
/// What XCUITest can verify: the cup-and-saucer toggle is present in the
/// top-right toolbar of the Search root and of a pushed Definition, flips its
/// `.isSelected` trait on tap, keeps its state across the Search → Definition
/// push (both screens observe the same `ReadingModeService.shared`), and is
/// reset when the app is backgrounded (`scenePhase == .background`) and
/// re-activated.
///
/// What it cannot verify: `UIApplication.isIdleTimerDisabled` itself is not
/// exposed through the accessibility tree. That contract is covered by
/// `ReadingModeServiceTests` (DictAppTests) through the `IdleTimerControlling`
/// seam, which is the only write site of the flag.
final class ReadingModeTests: XCTestCase {

    private var app: XCUIApplication!
    private var tabBarPage: TabBarPage!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-resetData", "-disableReviewPrompt"]
        // Force portrait — sim orientation persists across sessions on Intel
        // x86_64 (see BookmarkFlowTests); the frame assertions below assume it.
        XCUIDevice.shared.orientation = .portrait
        app.launch()

        // `-resetData` on a fresh sim triggers the one-time ~306k-row cold seed
        // (ProgressView until done). 120s mirrors DictionaryOrderDefaultTests.
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 120),
                      "Tab bar must appear once the cold seed completes")
        tabBarPage = TabBarPage(app: app)
    }

    override func tearDownWithError() throws {
        app = nil
        tabBarPage = nil
    }

    // MARK: - Helpers

    /// Enables reading mode on the Search root and pushes the definition of a
    /// known seed word, returning the Definition page object.
    private func enableOnRootAndOpenDefinition(_ term: String) -> DefinitionPage {
        let searchPage = tabBarPage.tapSearchTab()
        XCTAssertTrue(searchPage.verifyReadingModeToggleExists(),
                      "Reading mode toggle should exist on the Search root")
        XCTAssertTrue(searchPage.waitForReadingModeSelected(false),
                      "Reading mode must start off on a fresh launch")

        searchPage.tapReadingModeToggle()
        XCTAssertTrue(searchPage.waitForReadingModeSelected(true),
                      "Toggle should be selected after the first tap")

        searchPage.searchFor(term)
        XCTAssertTrue(searchPage.waitForResults(), "Search results should appear for '\(term)'")
        let definitionPage = searchPage.tapSearchResult(at: 0)
        XCTAssertTrue(definitionPage.waitForDefinitionToLoad(), "Definition should load")
        return definitionPage
    }

    // MARK: - Tests

    func testToggleExistsAndFlipsOnSearchRoot() throws {
        let searchPage = tabBarPage.tapSearchTab()

        XCTAssertTrue(searchPage.verifyReadingModeToggleExists(),
                      "Reading mode toggle should exist on the Search root")
        XCTAssertTrue(searchPage.readingModeToggle.isEnabled, "Toggle must be enabled")
        XCTAssertTrue(searchPage.waitForReadingModeSelected(false),
                      "Reading mode must be off on a fresh launch (in-session only, never persisted)")

        // Placement (AC: top-right toolbar): inside the nav bar, trailing half.
        let nav = app.navigationBars.firstMatch
        XCTAssertTrue(nav.waitForExistence(timeout: TestData.Timeouts.medium),
                      "Search root should have a navigation bar")
        let toggleFrame = searchPage.readingModeToggle.frame
        XCTAssertTrue(nav.frame.contains(toggleFrame),
                      "Toggle \(toggleFrame) should sit inside the navigation bar \(nav.frame)")
        XCTAssertGreaterThan(toggleFrame.midX, nav.frame.midX,
                             "Toggle should be in the trailing (right) half of the nav bar in LTR")

        // Off → on.
        searchPage.tapReadingModeToggle()
        XCTAssertTrue(searchPage.waitForReadingModeSelected(true),
                      "Toggle should report selected after enabling")

        // On → off.
        searchPage.tapReadingModeToggle()
        XCTAssertTrue(searchPage.waitForReadingModeSelected(false),
                      "Toggle should report not selected after disabling")

        // Still exactly one toggle on screen after two re-renders.
        XCTAssertEqual(app.buttons.matching(identifier: AccessibilityIdentifiers.ReadingMode.toggle).count, 1,
                       "Exactly one reading mode toggle should be present on the Search root")
    }

    func testStateSurvivesPushAndResetsOnBackground() throws {
        let term = TestData.bookmarkTestWords[0] // "apple"
        let definitionPage = enableOnRootAndOpenDefinition(term)

        // The pushed Definition renders its own button instance bound to the
        // same service, so it must already be selected — no re-tap.
        XCTAssertTrue(definitionPage.verifyReadingModeToggleExists(),
                      "Reading mode toggle should exist on the Definition toolbar")
        XCTAssertTrue(definitionPage.isReadingModeSelected(),
                      "Reading mode must stay on across the Search → Definition push")
        XCTAssertTrue(definitionPage.verifyBookmarkButtonExists(),
                      "Bookmark button must still be present next to the new toggle")

        // Background → foreground: scenePhase .background resets the mode.
        XCUIDevice.shared.press(.home)
        // Wait until the app has actually left the foreground before reactivating.
        let backgrounded = app.wait(for: .runningBackground, timeout: TestData.Timeouts.long)
            || app.wait(for: .runningBackgroundSuspended, timeout: TestData.Timeouts.short)
        XCTAssertTrue(backgrounded, "App should be in the background after pressing Home; state=\(app.state.rawValue)")
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: TestData.Timeouts.long),
                      "App should return to the foreground after activate()")

        // Same Definition is still on top (no relaunch, no -resetData re-run).
        XCTAssertTrue(definitionPage.waitForDefinitionToLoad(timeout: TestData.Timeouts.long),
                      "Definition should still be presented after re-activation")
        XCTAssertTrue(definitionPage.waitForReadingModeSelected(false, timeout: TestData.Timeouts.long),
                      "Reading mode must be off after the app was backgrounded")
        XCTAssertTrue(definitionPage.verifyBookmarkButtonExists(),
                      "Bookmark button must survive the background/foreground cycle")

        // Deliberate re-enable still works after the automatic reset.
        definitionPage.tapReadingModeToggle()
        XCTAssertTrue(definitionPage.waitForReadingModeSelected(true),
                      "User must be able to re-enable reading mode after a background reset")

        // And the state is visible back on the Search root after a pop. The
        // search session is still presented after the pop (query "apple" +
        // Cancel button), which hides the nav bar's trailing items — leave it
        // first so the root toolbar is rendered again.
        let searchPage = definitionPage.navigateBack()
        searchPage.cancelSearch()
        XCTAssertTrue(searchPage.verifyReadingModeToggleExists(),
                      "Toggle should be back on the Search root after popping and leaving search")
        XCTAssertTrue(searchPage.waitForReadingModeSelected(true),
                      "Search root toggle must reflect the state set on Definition")
    }

    func testBookmarkStaysOutermostOnDefinition() throws {
        let term = TestData.bookmarkTestWords[1] // "test"
        let searchPage = tabBarPage.tapSearchTab()
        searchPage.searchFor(term)
        XCTAssertTrue(searchPage.waitForResults(), "Search results should appear for '\(term)'")
        let definitionPage = searchPage.tapSearchResult(at: 0)
        XCTAssertTrue(definitionPage.waitForDefinitionToLoad(), "Definition should load")

        let bookmark = app.buttons[AccessibilityIdentifiers.Definition.bookmarkButton]
        XCTAssertTrue(bookmark.waitForExistence(timeout: TestData.Timeouts.medium),
                      "Bookmark button should exist on Definition")
        XCTAssertTrue(definitionPage.verifyReadingModeToggleExists(),
                      "Reading mode toggle should exist on Definition")

        let toggleFrame = definitionPage.readingModeToggle.frame
        let bookmarkFrame = bookmark.frame
        let nav = app.navigationBars.firstMatch
        XCTAssertTrue(nav.frame.contains(toggleFrame) && nav.frame.contains(bookmarkFrame),
                      "Both toolbar buttons should sit inside the navigation bar")
        // ToolbarItemGroup order guard (en/LTR): reading mode first, bookmark
        // outermost-right, so `bookmark_button`-based suites are unaffected.
        XCTAssertGreaterThanOrEqual(bookmarkFrame.minX, toggleFrame.maxX,
                                    "Bookmark \(bookmarkFrame) must stay to the right of the toggle \(toggleFrame)")
        XCTAssertFalse(toggleFrame.intersects(bookmarkFrame), "Toolbar buttons must not overlap")

        // Reading mode toggle must not hijack the bookmark: toggling one leaves
        // the other's state untouched.
        definitionPage.tapReadingModeToggle()
        XCTAssertTrue(definitionPage.waitForReadingModeSelected(true))
        XCTAssertTrue(bookmark.exists && bookmark.isEnabled,
                      "Bookmark button must remain present and enabled after toggling reading mode")
        XCTAssertFalse(bookmark.isSelected, "Toggling reading mode must not mark the bookmark as selected")
    }
}
