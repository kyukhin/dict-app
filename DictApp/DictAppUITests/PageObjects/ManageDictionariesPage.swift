import XCTest

/// Page object for Settings -> Manage Dictionaries.
///
/// Hosts the file-import affordance and (in the future) remote-download
/// controls. Today only the import button is testable from UI; the actual
/// import is a stub.
class ManageDictionariesPage: BasePage {

    // MARK: - UI Elements

    private var importButton: XCUIElement {
        let id = AccessibilityIdentifiers.ManageDictionaries.importButton
        // SwiftUI Button-with-Label exposes as a `button` in XCUI.
        if app.buttons[id].exists { return app.buttons[id] }
        return app.descendants(matching: .any)[id]
    }

    private var navigationTitle: XCUIElement {
        // Verify we actually pushed onto the navigation stack by checking
        // the navigation bar carries the screen's title.
        app.navigationBars["Manage Dictionaries"]
    }

    // MARK: - Verification

    func verifyNavigationTitleVisible(timeout: TimeInterval = TestData.Timeouts.medium) -> Bool {
        return navigationTitle.waitForExistence(timeout: timeout)
    }

    func waitForImportButton(timeout: TimeInterval = TestData.Timeouts.medium) -> Bool {
        return importButton.waitForExistence(timeout: timeout)
    }

    /// True only when the button is present, enabled, and hittable. Each
    /// condition is asserted independently so a failing test points at the
    /// specific reason rather than collapsing them into one boolean.
    func verifyImportButtonInteractive() -> Bool {
        let button = importButton
        XCTAssertTrue(button.exists, "Import button must exist on Manage Dictionaries screen")
        XCTAssertTrue(button.isEnabled, "Import button must be enabled when no import is in flight")
        XCTAssertTrue(button.isHittable, "Import button must be hittable (not obscured by another view)")
        return button.exists && button.isEnabled && button.isHittable
    }

    // MARK: - Actions

    /// Taps the import button. Caller is responsible for handling whatever
    /// system UI (`UIDocumentPickerViewController`) is then presented.
    func tapImportButton() {
        XCTAssertTrue(
            waitForImportButton(timeout: TestData.Timeouts.long),
            "Import button should appear on Manage Dictionaries screen"
        )
        importButton.tap()
    }

    // MARK: - Import result

    private var importResultMessage: XCUIElement {
        app.staticTexts[AccessibilityIdentifiers.ManageDictionaries.importResultMessage]
    }

    /// Waits for the "Imported N entries from …" success message. Returns
    /// the message text on success; `nil` on timeout.
    func waitForImportSuccessMessage(timeout: TimeInterval = 15.0) -> String? {
        guard importResultMessage.waitForExistence(timeout: timeout) else { return nil }
        return importResultMessage.label
    }
}
