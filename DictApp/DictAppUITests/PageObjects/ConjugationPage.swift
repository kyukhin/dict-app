import XCTest

/// The conjugation drill (0132, #168): the Conjugation screen, pushed from
/// the Learn home's Trainers row; its run, in E4's run shell (`ExercisePage`:
/// the close button, progress, options, feedback bar and summary); and
/// Practise under a Greek verb's table on the Definition screen. With
/// `-learningAnswerHints` the right option's value is `answer`.
final class ConjugationPage: BasePage {
    private typealias IDs = AccessibilityIdentifiers.Conjugation

    /// The Greek pronouns of the tense line and the table, by person.
    static let persons = ["εγώ": "1sg", "εσύ": "2sg", "αυτός": "3sg", "εμείς": "1pl", "εσείς": "2pl", "αυτοί": "3pl"]

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    // MARK: - The Conjugation screen

    var screen: XCUIElement { element(IDs.screen) }
    var lists: XCUIElement { element(IDs.lists) }
    var verbCount: XCUIElement { element(IDs.verbCount) }
    var tensesPicker: XCUIElement { app.segmentedControls[IDs.tensesPicker].firstMatch }
    var startButton: XCUIElement { app.buttons[IDs.startButton].firstMatch }
    var noLists: XCUIElement { element(IDs.noLists) }
    var chooseLists: XCUIElement { element(IDs.chooseLists) }
    var needsGreek: XCUIElement { element(IDs.needsGreek) }
    var downloadGreek: XCUIElement { app.buttons[IDs.downloadGreek].firstMatch }

    /// The segment of "Tenses up to" labelled `level` ("A1", "Α1" in Greek).
    func segment(_ level: String) -> XCUIElement {
        tensesPicker.buttons[level]
    }

    /// The segments, left to right.
    var segmentLabels: [String] {
        tensesPicker.buttons.allElementsBoundByIndex.sorted { $0.frame.minX < $1.frame.minX }.map(\.label)
    }

    /// A tense of the level, by `ConjugationTense` raw value.
    func tense(_ tense: String) -> XCUIElement { element(IDs.tense(tense)) }

    // MARK: - The run

    var run: ExercisePage { ExercisePage(app: app) }
    var promptVerb: XCUIElement { element(IDs.promptVerb) }
    var promptTranslation: XCUIElement { element(IDs.promptTranslation) }
    var promptTense: XCUIElement { element(IDs.promptTense) }
    var passiveNote: XCUIElement { element(IDs.passiveNote) }
    var tenseTable: XCUIElement { element(IDs.tenseTable) }

    func tenseRow(_ person: String) -> XCUIElement { element(IDs.tenseRow(person)) }
    func summaryTense(_ tense: String) -> XCUIElement { element(IDs.summaryTense(tense)) }

    /// The person the question asks, from the tense line's last word.
    var askedPerson: String? {
        let words = promptTense.label.unicodeScalars.filter { !["\u{200F}", "\u{2068}", "\u{2069}"].contains($0) }
        let label = String(String.UnicodeScalarView(words))
        guard let last = label.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\u{060C}" }).last else { return nil }
        return Self.persons[String(last)]
    }

    // MARK: - Definition

    var practiseButton: XCUIElement { app.buttons[IDs.practiseButton].firstMatch }

    // MARK: - Actions

    /// Start: the run of the checked lists' verbs.
    @discardableResult
    func start() -> ExercisePage {
        XCTAssertTrue(app.scrollToElement(startButton), "Start")
        startButton.tap()
        let page = run
        XCTAssertTrue(page.view.waitForExistence(timeout: TestData.Timeouts.medium), "the run")
        return page
    }

    /// Practise on the Definition screen.
    @discardableResult
    func practise() -> ExercisePage {
        XCTAssertTrue(practiseButton.waitForExistence(timeout: TestData.Timeouts.long), "Practise")
        XCTAssertTrue(app.scrollToElement(practiseButton), "Practise is reachable")
        practiseButton.tap()
        return run
    }

    /// Waits for a question (its verb shown, no feedback bar) or the
    /// summary: true for a question, false for the summary or nothing.
    func waitForQuestion(timeout: TimeInterval = TestData.Timeouts.long) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if run.summary.exists { return false }
            if promptVerb.exists && !run.feedback.exists { return true }
            Thread.sleep(forTimeInterval: 0.15)
        } while Date() < deadline
        return false
    }

    /// Answers the question shown, right or wrong, and returns the outcome
    /// the feedback bar reports (`right`, `wrong`).
    @discardableResult
    func answer(right: Bool) -> String? {
        XCTAssertNotNil(run.choose(right: right), "an option marked as the answer")
        return run.waitForFeedback()
    }

    // MARK: - Verification

    /// QA (#168): where a tense row draws its forms and its pronoun, read
    /// from the row's screenshot, in points from the row's left edge. A row
    /// is one VoiceOver element, so its parts have no frames: the forms are
    /// in the primary colour (`strong`: pixels far from the background), the
    /// pronoun in the secondary one (`ink`: any text pixel, forms included).
    func inkColumns(of row: XCUIElement) -> (strong: ClosedRange<CGFloat>, ink: ClosedRange<CGFloat>)? {
        guard let image = row.screenshot().image.cgImage, image.width > 0, image.height > 0,
              row.frame.width > 0 else { return nil }
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        func luminance(_ x: Int, _ y: Int) -> Int {
            let i = (y * width + x) * 4
            return (Int(pixels[i]) * 299 + Int(pixels[i + 1]) * 587 + Int(pixels[i + 2]) * 114) / 1000
        }
        // The background is the most common luminance.
        var counts = [Int](repeating: 0, count: 256)
        for y in 0..<height { for x in 0..<width { counts[luminance(x, y)] += 1 } }
        let background = counts.indices.max { counts[$0] < counts[$1] } ?? 255
        var strong: [Int] = [], ink: [Int] = []
        for x in 0..<width {
            let contrast = (0..<height).map { abs(luminance(x, $0) - background) }.max() ?? 0
            if contrast > 190 { strong.append(x) }
            if contrast > 60 { ink.append(x) }
        }
        guard let strongFirst = strong.first, let strongLast = strong.last,
              let inkFirst = ink.first, let inkLast = ink.last else { return nil }
        let scale = CGFloat(width) / row.frame.width
        return (CGFloat(strongFirst) / scale...CGFloat(strongLast) / scale, CGFloat(inkFirst) / scale...CGFloat(inkLast) / scale)
    }

    func waitForScreen(timeout: TimeInterval = TestData.Timeouts.medium) -> Bool {
        screen.waitForExistence(timeout: timeout)
    }

    /// Waits until `element`'s `key` (`label`, `value`) equals `text`.
    func wait(for element: XCUIElement, _ key: String = "label", toBe text: String,
              timeout: TimeInterval = TestData.Timeouts.medium) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "\(key) == %@", text), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}
