import XCTest

/// The statistics screen (0166, #164): one list of blocks under the
/// language switch. Values are read from the elements' labels; a calendar
/// day's mark from its value.
class StatisticsPage: BasePage {
    private typealias IDs = AccessibilityIdentifiers.Statistics

    func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    var view: XCUIElement { element(IDs.view) }
    var empty: XCUIElement { element(IDs.empty) }
    var languageSwitch: XCUIElement { app.segmentedControls[IDs.languageSwitch].firstMatch }
    var chart: XCUIElement { element(IDs.chart30d) }
    var tenseChart: XCUIElement { element(IDs.tenseChart) }

    /// The screen, with its numbers loaded (or the empty state).
    func waitForScreen(timeout: TimeInterval = TestData.Timeouts.long) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if element(IDs.todayExercises).exists || empty.exists { return true }
            Thread.sleep(forTimeInterval: 0.15)
        } while Date() < deadline
        return false
    }

    /// The label of `identifier`, scrolled into view first.
    func label(_ identifier: String) -> String {
        let target = element(identifier)
        app.scrollToElement(target)
        return target.label
    }

    /// Scrolls `identifier` into view; returns whether it is there.
    @discardableResult
    func reveal(_ identifier: String) -> Bool {
        app.scrollToElement(element(identifier))
    }

    /// Waits until `identifier`'s label is `label`.
    func waitForLabel(_ identifier: String, toBe label: String, timeout: TimeInterval = TestData.Timeouts.medium) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label),
                                                    object: element(identifier))
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Taps the switch's segment labelled `name` ("English").
    func selectLanguage(named name: String) {
        XCTAssertTrue(languageSwitch.waitForExistence(timeout: TestData.Timeouts.medium), "the language switch")
        app.scrollToElement(languageSwitch)
        languageSwitch.buttons[name].tap()
    }

    /// The calendar days whose mark is `mark` (`met`, `frozen`, `missed`, `open`).
    func days(marked mark: String) -> [XCUIElement] {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'stats_streak_day_' AND value == %@", mark))
            .allElementsBoundByIndex
    }

    /// Where the 30-day chart's tallest bar is, from 0 (the chart's left
    /// edge) to 1 (its right edge), read from a screenshot: the pixel column
    /// whose topmost saturated pixel is highest. Bars of days with the goal
    /// met are in the accent colour (blue); the axis, its labels, the grid
    /// and the goal line are grey. Nil without a coloured pixel.
    func tallestBarPosition() -> CGFloat? {
        guard let image = chart.screenshot().image.cgImage else { return nil }
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var tallest: (x: Int, top: Int)?
        for x in 0..<width {
            // Row 0 of the buffer is the top of the image.
            for y in 0..<height {
                let i = (y * width + x) * 4
                let channels = [Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2])]
                guard channels.max()! - channels.min()! > 80 else { continue }
                if y < tallest?.top ?? height { tallest = (x, y) }
                break
            }
        }
        return tallest.map { CGFloat($0.x) / CGFloat(width) }
    }
}
