import XCTest

class SearchPage: BasePage {

    // UI Elements
    private var searchField: XCUIElement {
        // SwiftUI search fields are accessible via searchFields collection
        app.searchFields.firstMatch
    }

    private var resultsList: XCUIElement {
        // Try multiple approaches to find the results list
        if app.tables[AccessibilityIdentifiers.Search.resultsList].exists {
            return app.tables[AccessibilityIdentifiers.Search.resultsList]
        }
        // Fallback to any table or list
        if app.tables.firstMatch.exists {
            return app.tables.firstMatch
        }
        return app.collectionViews.firstMatch
    }

    // MARK: - Polling helper

    /// Polls `condition` until it returns true or `timeout` elapses, at the
    /// same ~0.15s cadence `waitForResults` uses. Returns the final value of
    /// `condition` (true if it became satisfied, false on timeout).
    ///
    /// Kept `private` to `SearchPage` deliberately (Issue #56, DESIGN_DOC §3):
    /// `BasePage` is owned by `SettingsPage` work in flight (#55), so promoting
    /// a shared primitive there now would invite merge contention. If another
    /// page object wants the same helper, promote it in that follow-up.
    private func waitForCondition(timeout: TimeInterval = TestData.Timeouts.medium,
                                  _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.15)
        }
        return condition()
    }

    // MARK: - Search Actions

    func searchFor(_ term: String) {
        // On a slow simulator the search hierarchy may still be re-resolving
        // after a `navigateBack` pop when a looping test calls `searchFor`
        // again. Tapping `searchField.firstMatch` before it resolves makes the
        // *tap itself* throw ("No matches found … SearchField"). Wait for the
        // field to exist before tapping. Resolves immediately on arm64, where
        // the field is already present (Issue #56).
        XCTAssertTrue(searchField.waitForExistence(timeout: TestData.Timeouts.medium),
                      "Search field should exist before tapping")
        searchField.tap()
        // Clear any existing query deterministically before typing. The old
        // `clearAndTypeText` relied on `doubleTap()` "select all", which is
        // flaky on a UISearchField (it selects a word, not the field) and
        // intermittently fails to clear — so a second search concatenates onto
        // the first (e.g. "word" + "example" → "wordexample"), a bogus query
        // that returns no results. The search field's "Clear text" button is
        // deterministic; it only exists when the field is non-empty.
        let clearButton = searchField.buttons["Clear text"]
        if clearButton.waitForExistence(timeout: 1.0) {
            clearButton.tap()
            if app.usesFloatingTabStrip {
                // iPadOS 26: "Clear text" ends the search and drops focus
                // (there is no Cancel button), so focus the field again.
                // iPhone and iPad 17.x keep focus.
                searchField.tap()
            }
        }
        searchField.typeText(term)
        // Don't return until the typed query has actually landed in the field,
        // so a caller's subsequent `waitForResults` samples the right query and
        // not a half-typed transient. Immediate on arm64 (value already set).
        XCTAssertTrue(waitForCondition { self.verifySearchFieldContains(term) },
                      "Search field should contain the typed term '\(term)' after typing")
    }

    func clearSearch() {
        let clearButton = searchField.buttons["Clear text"]
        if clearButton.waitForExistence(timeout: 1.0) {
            clearButton.tap()
        } else {
            searchField.tap()
            searchField.clearAndTypeText("")
        }
    }

    /// Dismisses the on-screen keyboard so the tab bar becomes hittable.
    /// On iPhone the keyboard overlays the tab bar after a `.searchable()`
    /// search, so a tab tap would land on a key instead. One implementation
    /// for every page: `XCUIApplication.dismissKeyboardIfPresent()`.
    func dismissKeyboard() {
        app.dismissKeyboardIfPresent()
    }

    /// On first use of `.searchable()` iOS 26 surfaces a full-screen
    /// "Siri, Dictation & Privacy" notice that overlays the entire app and
    /// silently intercepts subsequent taps on the tab bar. This method
    /// detects and closes that sheet so tests can carry on.
    func dismissSiriPrivacyNoticeIfPresent() {
        let nav = app.navigationBars["Siri, Dictation & Privacy"]
        guard nav.waitForExistence(timeout: 1.0) else { return }
        // The sheet has a Close button (system "close" symbol) in its
        // navigation bar — tap it via the first button on that bar.
        let close = nav.buttons.firstMatch
        if close.exists {
            close.tap()
        }
    }

    /// Leaves the active `.searchable()` session via the search bar's dismiss
    /// button (clears the query and drops focus). While a search is presented
    /// SwiftUI renders only the search field and that button in the navigation
    /// bar and hides the trailing toolbar items, so any test that asserts on a
    /// root toolbar button (e.g. `reading_mode_toggle`, Issue #5) after a
    /// `navigateBack()` pop must call this first. The button is labelled
    /// "Cancel" on iOS 17/18 and "Close" on iOS 26 (verified from the AX
    /// hierarchy on the 26.4 sim). No-op when no search is active.
    func cancelSearch() {
        let nav = app.navigationBars.firstMatch
        for label in ["Cancel", "Close"] {
            let dismiss = nav.buttons[label]
            if dismiss.waitForExistence(timeout: 1.0) {
                dismiss.tap()
                _ = dismiss.waitForNonExistence(timeout: TestData.Timeouts.short)
                _ = app.keyboards.firstMatch.waitForNonExistence(timeout: TestData.Timeouts.short)
                return
            }
        }
        dismissKeyboard()
    }

    /// Convenience: clears anything that could be blocking the tab bar after
    /// a `.searchable()` interaction (keyboard + Siri privacy sheet).
    func clearOverlaysBeforeTabSwitch() {
        dismissSiriPrivacyNoticeIfPresent()
        dismissKeyboard()
    }

    // MARK: - Results Interaction

    @discardableResult
    func tapSearchResult(at index: Int) -> DefinitionPage {
        let cells = resultsList.cells
        XCTAssertTrue(cells.count > index, "Search result at index \(index) does not exist")

        let cell = cells.element(boundBy: index)
        XCTAssertTrue(cell.waitForExistence(timeout: TestData.Timeouts.medium))
        cell.tap()

        return DefinitionPage(app: app)
    }

    @discardableResult
    func tapSearchResultWithId(_ id: String) -> DefinitionPage {
        let resultElement = app.cells[AccessibilityIdentifiers.Search.searchResult(id: id)]
        XCTAssertTrue(resultElement.waitForExistence(timeout: TestData.Timeouts.medium))
        resultElement.tap()

        return DefinitionPage(app: app)
    }

    // MARK: - Verification Methods

    func verifySearchFieldExists() -> Bool {
        // Bounded retry, not a synchronous sample: callers invoke this right
        // after `navigateBack()`, and on a slow simulator the search field
        // hasn't re-resolved post-pop yet. `waitForExistence` returns the
        // instant it appears (immediate on arm64) (Issue #56).
        return searchField.waitForExistence(timeout: TestData.Timeouts.medium)
    }

    /// Whether the search field holds the keyboard focus (Issue #145: a chip
    /// tap keeps it).
    func searchFieldHasFocus() -> Bool {
        searchField.exists && (searchField.value(forKey: "hasKeyboardFocus") as? Bool ?? false)
    }

    func verifySearchFieldContains(_ text: String) -> Bool {
        let value = searchField.value as? String ?? ""
        if text.isEmpty {
            // Empty field may show placeholder text instead of ""
            return value.isEmpty || value == searchField.placeholderValue
        }
        return value == text
    }

    func verifyResultsListExists() -> Bool {
        return resultsList.exists
    }

    func verifyResultsCount(greaterThan count: Int) -> Bool {
        return resultsList.cells.count > count
    }

    func verifyResultsCount(equalTo count: Int) -> Bool {
        return resultsList.cells.count == count
    }

    func verifyNoResults() -> Bool {
        return resultsList.cells.count == 0
    }

    func verifyResultContainsText(_ text: String, at index: Int) -> Bool {
        let cells = resultsList.cells
        guard cells.count > index else { return false }

        let cell = cells.element(boundBy: index)
        return cell.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", text)).count > 0
    }

    /// Issue #87: whether the result cell at `index` carries the badge of
    /// `source`, matched by `source_badge_<source>` (the badge's `label` is
    /// its localized VoiceOver text, so never match the visible text).
    func verifyResultHasBadge(source: String, at index: Int) -> Bool {
        let cells = resultsList.cells
        guard cells.count > index else { return false }
        return cells.element(boundBy: index)
            .descendants(matching: .any)[AccessibilityIdentifiers.Search.sourceBadge(source: source)]
            .exists
    }

    func getResultsCount() -> Int {
        return resultsList.cells.count
    }

    /// Headwords of the first `limit` rendered result cells, from the top of
    /// the list. Compare signatures, not `cells.count`, across a tab switch:
    /// the lazy `List` exposes only the rows it has rendered.
    func resultSignature(limit: Int = 3) -> [String] {
        let cells = resultsList.cells
        return (0..<min(limit, cells.count)).map { index in
            let headword = cells.element(boundBy: index).staticTexts.firstMatch
            return headword.exists ? headword.label : ""
        }
    }

    func waitForResults(timeout: TimeInterval = TestData.Timeouts.medium) -> Bool {
        // The "no results" state renders SearchView's ContentUnavailableView as
        // a single List cell, so `cells.count > 0` alone is a false positive —
        // and a caller would then tap that non-navigating cell and fail later
        // with a confusing "Definition should load" timeout. Require a real
        // result cell: at least one cell AND the no-results marker absent.
        //
        // Issue #56: when this is called right after a `navigateBack` pop, the
        // search view re-resolves and can briefly re-render its
        // ContentUnavailableView (query re-applied, results re-debouncing) — a
        // *transient* no-results flash. Two guards make this robust without
        // weakening #52's fast-fail on a genuinely bogus concatenated query:
        //   (a) first let the search field settle (sub-second when already
        //       present — i.e. the pop transition has completed);
        //   (b) treat the no-results marker as definitive only when it is
        //       STABLE across two consecutive ~0.15s polls. A real bad query
        //       shows a persistent marker → still fails fast (~0.3s, the #52
        //       behavior); a transition flash clears within one poll → no
        //       longer misclassified, so we keep waiting for the real cells.
        _ = searchField.waitForExistence(timeout: TestData.Timeouts.short)

        // Issue #145: "Choose a dictionary" is a list cell too, and also means
        // "no results"; treat either marker the same way.
        let noResults = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier IN %@",
            [AccessibilityIdentifiers.Search.noResults, AccessibilityIdentifiers.Search.noDictionariesHint]
        )).firstMatch
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !noResults.exists && resultsList.cells.count > 0 {
                return true                                 // real result cell(s)
            }
            if noResults.exists {
                // Possible transient flash — require the marker to persist one
                // more poll before declaring a definitive no-results.
                Thread.sleep(forTimeInterval: 0.15)
                if noResults.exists { return false }        // stable → genuinely no results (#52)
                continue                                    // flashed and cleared → keep waiting
            }
            Thread.sleep(forTimeInterval: 0.15)             // settle through the debounce
        }
        return resultsList.cells.count > 0 && !noResults.exists
    }

    /// Waits for the `ContentUnavailableView` that SearchView renders inside
    /// its List when `results` is empty and `query` is non-empty.
    ///
    /// We can't use `cells.count == 0` because the ContentUnavailableView is
    /// rendered as one cell inside the SwiftUI List — a "no results" state
    /// looks like one cell, not zero. Instead we look for the explicit
    /// accessibility identifier added in `SearchView.swift`.
    func waitForNoResults(timeout: TimeInterval = TestData.Timeouts.medium) -> Bool {
        let marker = app.descendants(matching: .any)["search_no_results"]
        return marker.waitForExistence(timeout: timeout)
    }

    func verifyContentUnavailableShown() -> Bool {
        return app.descendants(matching: .any)["search_no_results"].exists
    }

    /// No result row on screen: no source badge, which only result rows carry.
    func verifyNoResultCells() -> Bool {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "source_badge_"))
            .count == 0
    }

    // MARK: - Dictionary chips (Issue #145)
    //
    // Chips are found by id with any element type: a pair chip is a SwiftUI
    // `Toggle` (value 1 or 0, like the Settings switches), "All" a `Button`
    // with the selected trait. The row scrolls sideways; it is scrolled by
    // geometry, never through `isHittable`. Pair keys are `TestData.Pairs`.

    /// The row: a container named "Dictionaries".
    var chipsRow: XCUIElement {
        app.descendants(matching: .any).matching(identifier: AccessibilityIdentifiers.Search.chipsRow).firstMatch
    }

    var allChip: XCUIElement {
        app.descendants(matching: .any).matching(identifier: AccessibilityIdentifiers.Search.allChip).firstMatch
    }

    func chip(_ pair: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: AccessibilityIdentifiers.Search.chip(pair: pair)).firstMatch
    }

    /// Waits until the row has loaded (it shows once the pair list is in).
    @discardableResult
    func waitForChips(timeout: TimeInterval = TestData.Timeouts.long) -> Bool {
        allChip.waitForExistence(timeout: timeout)
    }

    /// The horizontal scroll view that holds the chips: the row's full
    /// width. The "Dictionaries" container (`chipsRow`) is the chips inside
    /// it, as wide as their content. On iOS 26 this scroll view's frame
    /// reaches up under the navigation bar, so only its width is meaningful.
    var chipsScrollView: XCUIElement {
        app.scrollViews.containing(.any, identifier: AccessibilityIdentifiers.Search.allChip).firstMatch
    }

    /// Drags the row sideways until `element`'s centre is inside the window.
    /// Works left to right and right to left: the direction comes from where
    /// the chip lies, not from the language. Each drag runs along the chips,
    /// moves 70% of the width and holds before lifting, so there is no
    /// momentum and a chip's centre cannot be skipped. It never swipes at the
    /// row's centre, which lies off screen at large text sizes.
    @discardableResult
    func revealChip(_ element: XCUIElement, maxSwipes: Int = 10) -> Bool {
        guard waitForChips(), element.waitForExistence(timeout: TestData.Timeouts.medium) else { return false }
        let window = app.windows.firstMatch.frame
        func revealed() -> Bool {
            let frame = element.frame
            guard frame.width > 1, frame.height > 1 else { return false }
            return window.contains(CGPoint(x: frame.midX, y: frame.midY))
        }
        let origin = app.coordinate(withNormalizedOffset: .zero)
        for _ in 0..<maxSwipes {
            if revealed() { return true }
            let y = element.frame.midY
            let right = origin.withOffset(CGVector(dx: window.minX + window.width * 0.85, dy: y))
            let left = origin.withOffset(CGVector(dx: window.minX + window.width * 0.15, dy: y))
            let (from, to) = element.frame.midX > window.midX ? (right, left) : (left, right)
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        return revealed()
    }

    /// The chip's on state from its switch value (1 or 0); `nil` if it is
    /// missing or carries no switch value.
    func isChipOn(_ pair: String) -> Bool? {
        let element = chip(pair)
        guard element.exists else { return nil }
        return Self.switchValue(element.value)
    }

    func isAllSelected() -> Bool {
        allChip.exists && allChip.isSelected
    }

    /// Taps a pair chip and checks that it flipped.
    func tapChip(_ pair: String, file: StaticString = #filePath, line: UInt = #line) {
        let element = chip(pair)
        XCTAssertTrue(revealChip(element), "chip '\(pair)' must be reachable in the row", file: file, line: line)
        let before = isChipOn(pair)
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(waitForCondition(timeout: TestData.Timeouts.short) { self.isChipOn(pair) != before },
                      "chip '\(pair)' did not change state after a tap (was \(String(describing: before)))",
                      file: file, line: line)
    }

    /// Taps "All" and checks that it ends up selected.
    func tapAllChip(file: StaticString = #filePath, line: UInt = #line) {
        let element = allChip
        XCTAssertTrue(revealChip(element), "'All' must be reachable in the row", file: file, line: line)
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(waitForCondition(timeout: TestData.Timeouts.short) { self.isAllSelected() },
                      "'All' must be selected after a tap", file: file, line: line)
    }

    /// Long press on a pair chip, then "Only this" in its menu: by id, with
    /// the English label as a fallback.
    func onlyThis(_ pair: String, file: StaticString = #filePath, line: UInt = #line) {
        let element = chip(pair)
        XCTAssertTrue(revealChip(element), "chip '\(pair)' must be reachable in the row", file: file, line: line)
        element.press(forDuration: 1.0)
        let byID = app.descendants(matching: .any)
            .matching(identifier: AccessibilityIdentifiers.Search.onlyThisMenuItem).firstMatch
        let byLabel = app.buttons["Only this"].firstMatch
        var item = byID
        if !byID.waitForExistence(timeout: TestData.Timeouts.medium) {
            item = byLabel
        }
        XCTAssertTrue(item.waitForExistence(timeout: TestData.Timeouts.short),
                      "the long-press menu of '\(pair)' must offer 'Only this'", file: file, line: line)
        item.tap()
        XCTAssertTrue(waitForCondition(timeout: TestData.Timeouts.medium) { !item.exists && self.isChipOn(pair) == true },
                      "after 'Only this' the menu closes and '\(pair)' is on", file: file, line: line)
    }

    /// Pair keys in reading order: left to right by `frame.minX`, or right
    /// to left by descending `frame.maxX` when "All" sits at the right edge
    /// (Arabic). Pairs without a chip are left out.
    func chipOrder(of pairs: [String]) -> [String] {
        let present = pairs.map { ($0, chip($0)) }.filter { $0.1.exists }
        let all = allChip
        let rightToLeft = all.exists && present.contains { all.frame.midX > $0.1.frame.midX }
        return present
            .sorted { rightToLeft ? $0.1.frame.maxX > $1.1.frame.maxX : $0.1.frame.minX < $1.1.frame.minX }
            .map(\.0)
    }

    /// Waits for "Choose a dictionary", shown instead of results when every
    /// chip is off and the field holds a query.
    func waitForNoDictionariesHint(timeout: TimeInterval = TestData.Timeouts.medium) -> Bool {
        app.descendants(matching: .any)[AccessibilityIdentifiers.Search.noDictionariesHint]
            .waitForExistence(timeout: timeout)
    }

    /// A switch's XCUITest value as a Bool: "1"/"0" (also true/false, on/off).
    static func switchValue(_ value: Any?) -> Bool? {
        if let string = value as? String {
            switch string.lowercased() {
            case "1", "true", "on": return true
            case "0", "false", "off": return false
            default: return nil
            }
        }
        if let number = value as? NSNumber { return number.boolValue }
        return nil
    }
}
