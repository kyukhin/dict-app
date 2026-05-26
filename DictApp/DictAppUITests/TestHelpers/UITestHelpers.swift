import XCTest

class BasePage {
    let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    func waitForElement(_ identifier: String, timeout: TimeInterval = 5) -> XCUIElement {
        let element = app.otherElements[identifier]
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Element with identifier '\(identifier)' not found within \(timeout) seconds")
        return element
    }

    func waitForButton(_ identifier: String, timeout: TimeInterval = 5) -> XCUIElement {
        let element = app.buttons[identifier]
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Button with identifier '\(identifier)' not found within \(timeout) seconds")
        return element
    }

    func waitForTextField(_ identifier: String, timeout: TimeInterval = 5) -> XCUIElement {
        let element = app.textFields[identifier]
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "TextField with identifier '\(identifier)' not found within \(timeout) seconds")
        return element
    }

    func waitForSearchField(_ identifier: String, timeout: TimeInterval = 5) -> XCUIElement {
        let element = app.searchFields.firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "SearchField not found within \(timeout) seconds")
        return element
    }

    func waitForTable(_ identifier: String, timeout: TimeInterval = 5) -> XCUIElement {
        let element = app.tables[identifier]
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Table with identifier '\(identifier)' not found within \(timeout) seconds")
        return element
    }

    func waitForTabBar(timeout: TimeInterval = 5) -> XCUIElement {
        let element = app.tabBars.firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "TabBar not found within \(timeout) seconds")
        return element
    }
}

extension XCUIElement {
    func clearAndTypeText(_ text: String) {
        guard self.exists else {
            XCTFail("Element does not exist")
            return
        }

        self.tap()
        self.doubleTap()
        self.typeText(text)
    }
}

extension XCUIApplication {
    /// Returns the scroll container backing the current screen — SwiftUI
    /// `Form` is a `UICollectionView` on modern iOS, a `UIScrollView` on
    /// older ones, and `UITableView` on the oldest. Falls back to the app
    /// element so the caller can always issue a swipe somewhere.
    fileprivate var scrollContainer: XCUIElement {
        let candidates: [XCUIElement] = [
            collectionViews.firstMatch,
            scrollViews.firstMatch,
            tables.firstMatch
        ]
        return candidates.first(where: { $0.exists }) ?? self
    }

    /// Scrolls the current scroll container until `element` is both in the
    /// accessibility hierarchy AND hittable, swiping up first then down.
    ///
    /// Why this exists: SwiftUI `Form` virtualises its rows — cells off the
    /// visible region aren't in the XCUI accessibility tree at all, so
    /// `waitForExistence` alone fails. Cells just on the edge of the viewport
    /// register as `.exists` but not `.isHittable`, so a plain existence
    /// check still leads to a no-op tap. This helper handles both:
    ///   1. swipes up to expose content below the fold (the common case);
    ///   2. swipes down as a fallback for the scroll-restoration case where
    ///      the form resumes scrolled past the target.
    ///
    /// Bounded so a regression fails the test rather than spinning forever.
    ///
    /// - Parameters:
    ///   - element: target element. May be a stale or freshly-resolved
    ///     `XCUIElement`; we re-query `.exists`/`.isHittable` each step.
    ///   - container: scrollable container to swipe on. Defaults to the
    ///     first existing collection/scroll/table view; pass an explicit
    ///     container only when there are multiple on screen.
    ///   - maxSwipes: per-direction swipe cap. Default 8 each way.
    /// - Returns: true if `element` ended up hittable; false otherwise.
    @discardableResult
    func scrollToElement(
        _ element: XCUIElement,
        in container: XCUIElement? = nil,
        maxSwipes: Int = 8
    ) -> Bool {
        if element.exists && element.isHittable { return true }

        let scrollable = container ?? scrollContainer

        // Sweep up first — content typically lives below the initial fold.
        for _ in 0..<maxSwipes {
            scrollable.swipeUp()
            if element.exists && element.isHittable { return true }
        }

        // Sweep back down — covers the scene-restoration case where the
        // form resumed scrolled past the target on a warm relaunch.
        for _ in 0..<maxSwipes {
            scrollable.swipeDown()
            if element.exists && element.isHittable { return true }
        }

        return element.exists && element.isHittable
    }
}