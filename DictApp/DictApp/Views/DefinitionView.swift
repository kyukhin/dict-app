// DefinitionView.swift
// Detailed word view with Markdown rendering and TTS.

import SwiftUI
import StoreKit   // Issue #12: AppStore.requestReview(in:)
import UIKit      // Issue #12: UIWindowScene for the scene-based review request

struct DefinitionView: View {
    @StateObject private var vm: DefinitionViewModel
    /// The in-app language, for the inflection table's labels (Issue #144).
    @Environment(\.locale) private var locale
    @Environment(\.layoutDirection) private var layoutDirection
    /// False in the drill's Rule sheet (0133, #174): no Practise there.
    @Environment(\.allowsPractise) private var allowsPractise

    init(entry: DictionaryEntry) {
        _vm = StateObject(wrappedValue: DefinitionViewModel(entry: entry))
    }

    /// The active foreground window scene — required by the scene-based review API.
    private static var activeWindowScene: UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Word header
                HStack(alignment: .firstTextBaseline) {
                    Text(vm.entry.word)
                        .font(.largeTitle.bold())

                    Spacer()

                    if vm.canSpeak {
                        Button {
                            vm.speak()
                        } label: {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.title2)
                        }
                        .accessibilityLabel(Text("definition.a11y.speakWord"))
                    }
                }

                // Phonetic
                if !vm.entry.phonetic.isEmpty {
                    Text(vm.entry.phonetic)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                // Part of speech
                if !vm.entry.pos.isEmpty {
                    Text(vm.entry.pos)
                        .font(.subheadline)
                        .italic()
                        .foregroundStyle(.secondary)
                }

                // 0166, #165: the word's learning status, under the part of speech.
                let statusLines = vm.statusLines(locale: locale)
                if !statusLines.isEmpty {
                    LearningStatusView(lines: statusLines)
                }

                Divider()

                // Definition with Markdown rendering
                Text(markdownDefinition)
                    .font(.body)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("definition_content")

                // 0134, #178: real sentences with the word, above the table.
                if !vm.examples.isEmpty {
                    Divider()
                    ExamplesSection(examples: vm.examples)
                }

                // Issue #144: how a Greek headword inflects.
                if let table = vm.inflectionTable {
                    Divider()
                    InflectionTableView(table: table)
                    // 0132, #168: Practise under a verb's table.
                    if allowsPractise, table.kind == .conjugation, let verb = vm.drillVerb {
                        practiseButton(verb)
                    }
                }

                // 0133, #174: the grammar topics of a Greek headword.
                if !vm.grammarTopics.isEmpty {
                    Divider()
                    grammarSection
                }
            }
            .padding()
        }
        .accessibilityIdentifier("definition_view")
        .navigationTitle(vm.entry.word)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ReadingModeToolbarButton()
                // 0131, #158: the Learn button, where the bookmark star was.
                Button {
                    Task { await vm.toggleLearn() }
                } label: {
                    Image(systemName: vm.learnAction == .learn ? "graduationcap" : "graduationcap.fill")
                }
                .accessibilityLabel(Text(learnButtonLabel))
                .accessibilityIdentifier("learn_button")
            }
        }
        .readingModeHint()
        .alert(Text(questionTitle),
               isPresented: Binding(get: { vm.question != nil },
                                    set: { if !$0 { vm.question = nil } }),
               presenting: vm.question) { question in
            Button("common.yes") {
                Task { await vm.answer(question, yes: true) }
            }
            Button("common.no") {
                Task { await vm.answer(question, yes: false) }
            }
        } message: { question in
            // A limited pair's warning: "Words are practised in English."
            if case let .pair(pair) = question, let warning = LearnViewModel.limitedWarning(pair, locale: locale) {
                Text(warning)
            }
        }
        .task {
            await vm.loadInflection(locale: locale)
        }
        .task {
            await vm.loadExamples()
        }
        .task {
            await vm.onAppear()
            // Issue #12: viewing a definition is a "successful search". Bump the
            // counter, then prompt for a review if the heuristic is satisfied.
            let review = ReviewRequestService.shared
            review.recordDefinitionView()
            if review.shouldRequestReview() {
                // NOTE: SwiftUI's `@Environment(\.requestReview)` does NOT present
                // from a NavigationLink-pushed view (Apple-forum 739656; also flaky
                // on iOS 26.x). The scene-based StoreKit API does. Apple still
                // manages the actual presentation and its annual cap.
                // Only consume the attempt when the scene-resolved API is
                // actually invoked — a nil scene would otherwise burn the
                // latch without ever showing the prompt (#80 review).
                if let scene = Self.activeWindowScene {
                    review.markPromptFired()
                    AppStore.requestReview(in: scene)
                }
            }
        }
    }

    /// 0132, #168: a bordered "Practise" that drills this verb at once, or
    /// asks "Learn Greek via English?" first while Greek is not learned;
    /// No cancels the drill. The run covers the screen.
    private func practiseButton(_ verb: DrillVerb) -> some View {
        Button {
            Task { await vm.practise() }
        } label: {
            Text("drill.practise")
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(Text(verbatim: DrillText.practiseLabel(verb.citation, locale: locale)))
        .accessibilityIdentifier("drill_practise_button")
        .alert(Text(vm.practiseQuestion.map { LearnViewModel.learnPairQuestion($0, locale: locale) } ?? ""),
               isPresented: Binding(get: { vm.practiseQuestion != nil },
                                    set: { if !$0 { vm.practiseQuestion = nil } }),
               presenting: vm.practiseQuestion) { _ in
            Button("common.yes") {
                Task { await vm.answerPractise(yes: true) }
            }
            Button("common.no") {
                Task { await vm.answerPractise(yes: false) }
            }
        } message: { pair in
            // A limited pair's warning: "Words are practised in English."
            if let warning = LearnViewModel.limitedWarning(pair, locale: locale) {
                Text(warning)
            }
        }
        .fullScreenCover(item: $vm.practiseRun) { run in
            ConjugationRunView(mode: .verb(run.verb, level: run.level), meaningsLang: run.meaningsLang)
                .environment(\.locale, locale)
                .environment(\.layoutDirection, layoutDirection)
        }
    }

    /// 0133, #174: "Grammar", one row per topic that applies to the entry,
    /// titled in Greek's explanation language. A row pushes the topic in the
    /// same stack (a tab's, or the drill's Rule sheet).
    private var grammarSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("grammar.title")
                .font(.title3.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(vm.grammarTopics) { topic in
                    NavigationLink {
                        GrammarTopicView(id: topic.id)
                    } label: {
                        GrammarLinkRow(title: GrammarDocument.taggingGreek(AttributedString(topic.title)),
                                       subtitle: nil, isLink: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("definition_grammar_topic_\(topic.id)")
                    if topic.id != vm.grammarTopics.last?.id { Divider() }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("definition_grammar_section")
    }

    private var learnButtonLabel: LocalizedStringKey {
        switch vm.learnAction {
        case .learn: return "definition.a11y.learn"
        case .stopLearning: return "definition.a11y.stopLearning"
        case .removeFromMyWords: return "definition.a11y.removeFromMyWords"
        }
    }

    /// "Learn Spanish via English?", or 0130's "Learn lists in other
    /// languages?" for a language without a pair.
    private var questionTitle: String {
        switch vm.question {
        case let .pair(pair)?: return LearnViewModel.learnPairQuestion(pair, locale: locale)
        case .other?: return SettingsViewModel.localizedBundle(for: locale)
            .localizedString(forKey: "listImport.learnOther", value: nil, table: nil)
        case nil: return ""
        }
    }

    /// Parse the definition string as Markdown so **bold**, *italic*, and
    /// numbered lists render properly instead of showing raw syntax.
    private var markdownDefinition: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        if let parsed = try? AttributedString(markdown: vm.entry.definition, options: options) {
            return parsed
        }
        return AttributedString(vm.entry.definition)
    }
}

// MARK: - 0166, #165: a word's learning status

/// `WordStatusText`'s lines: the stage and the next review, then the cards
/// and the mistakes in the secondary colour. VoiceOver reads them as one
/// element.
struct LearningStatusView: View {
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                Text(verbatim: line)
                    .font(index == 0 ? .subheadline.weight(.semibold) : .subheadline)
                    .foregroundStyle(index == 0 ? HierarchicalShapeStyle.primary : .secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("learning_status")
    }
}

// MARK: - 0133: Practise allowed (#172, #174)

private struct AllowsPractiseKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// False in the drill's Rule sheet (0133, #174): a grammar topic and a
    /// Definition opened from it show no Practise there; the topic itself
    /// still shows.
    var allowsPractise: Bool {
        get { self[AllowsPractiseKey.self] }
        set { self[AllowsPractiseKey.self] = newValue }
    }
}

// MARK: - Issue #5: Reading Mode toolbar button (shared by Search, Definition and the grammar topic)

struct ReadingModeToolbarButton: View {
    @ObservedObject private var readingMode = ReadingModeService.shared
    @Environment(\.locale) private var locale
    /// #315: bumped on each turn-on, so only turning on bounces the bulb.
    @State private var turnOns = 0

    /// #315: amber on a light toolbar, where system yellow fades into white;
    /// system yellow in dark.
    private static let onColor = Color(uiColor: UIColor {
        $0.userInterfaceStyle == .dark ? .systemYellow : UIColor(red: 0.85, green: 0.6, blue: 0, alpha: 1)
    })

    var body: some View {
        Button {
            readingMode.toggle()
            guard readingMode.isEnabled else { return }
            turnOns += 1
            AccessibilityNotification.Announcement(
                SettingsViewModel.localizedString("readingMode.hint", locale: locale)).post()
        } label: {
            Image(systemName: readingMode.isEnabled ? "lightbulb.max.fill" : "lightbulb")
                .symbolEffect(.bounce, value: turnOns)
        }
        // Off: the toolbar's own colour.
        .tint(readingMode.isEnabled ? Self.onColor : nil)
        .accessibilityLabel(Text(readingMode.isEnabled ? "readingMode.a11y.disable"
                                                       : "readingMode.a11y.enable"))
        .accessibilityAddTraits(readingMode.isEnabled ? .isSelected : [])
        .accessibilityIdentifier("reading_mode_toggle")
    }
}

extension View {
    /// #315: "The screen stays on" at the top of a screen with the Reading
    /// Mode button, while `ReadingModeService.showsHint`. It takes no taps.
    func readingModeHint() -> some View {
        overlay(alignment: .top) { ReadingModeHint() }
    }
}

private struct ReadingModeHint: View {
    @ObservedObject private var readingMode = ReadingModeService.shared

    var body: some View {
        ZStack {
            if readingMode.showsHint {
                Text("readingMode.hint")
                    .font(.subheadline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 8)
                    .transition(.opacity)
                    .accessibilityIdentifier("reading_mode_hint")
            }
        }
        .animation(.default, value: readingMode.showsHint)
        .allowsHitTesting(false)
    }
}

// MARK: - 0134, #178: example sentences
//
// Shared with learning's example sheet (`ExerciseView.swift`). Leading and
// trailing only, so Arabic mirrors the section; a Greek or English sentence
// keeps its own direction (its first strong letter decides), and the byline
// starts with U+200F in Arabic.

/// The Examples section: up to 5 examples, 3 at first. "More examples"
/// shows the rest and becomes "Fewer examples"; hidden with 3 or fewer.
/// The state is not stored, as with "All forms".
struct ExamplesSection: View {
    static let visibleCount = 3

    let examples: [ExampleSentence]
    @State private var showsAll = false
    @Environment(\.locale) private var locale

    var body: some View {
        let uiLanguage = LearningPairs.code(ofUILanguage: locale.language.languageCode?.identifier ?? locale.identifier)
        let shown = showsAll ? examples : Array(examples.prefix(Self.visibleCount))
        VStack(alignment: .leading, spacing: 16) {
            Text("examples.title")
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("examples_title")
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, example in
                ExampleSentenceView(example: ShownExample(sentence: example,
                                                          translation: ExampleText.translation(for: example,
                                                                                               uiLanguage: uiLanguage)),
                                    number: index + 1)
            }
            if examples.count > Self.visibleCount {
                Button {
                    showsAll.toggle()
                } label: {
                    Text(showsAll ? LocalizedStringKey("examples.fewer") : LocalizedStringKey("examples.more"))
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("examples_more_button")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("examples_section")
    }
}

/// One example: the sentence with the word's form in bold and the accent
/// colour (selectable, like the definition), its translation in the
/// secondary colour, and the byline in small print. VoiceOver reads it as
/// one element: the sentence and the translation in their own voices, then
/// "From Tatoeba: Zeus and Shishir". `number` (from 1, in display order)
/// numbers the identifiers.
struct ExampleSentenceView: View {
    let example: ShownExample
    let number: Int
    @Environment(\.locale) private var locale

    var body: some View {
        let bundle = SettingsViewModel.localizedBundle(for: locale)
        VStack(alignment: .leading, spacing: 4) {
            Text(ExampleText.sentence(example.sentence))
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .accessibilityIdentifier("example_sentence_\(number)")
            if let translation = example.translation {
                Text(ExampleText.spoken(translation.text, lang: translation.lang))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("example_translation_\(number)")
            }
            Text(verbatim: ExampleText.byline(example.sentence, translation: example.translation, bundle: bundle))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("example_byline_\(number)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(ExampleText.accessibilityLabel(example.sentence, translation: example.translation,
                                                                bundle: bundle, locale: locale)))
        .accessibilityIdentifier("example_\(number)")
    }
}

extension ExampleText {
    /// The sentence as shown: the word's form (`form`, in Unicode scalars)
    /// bold and in the accent colour; the text tagged with its language, so
    /// VoiceOver reads it in that voice, as #144's cells do. A span that does
    /// not fit the text (never, per the build's gates) gives the plain text.
    static func sentence(_ example: ExampleSentence) -> AttributedString {
        var text = spoken(example.text, lang: example.lang)
        let count = example.text.unicodeScalars.count
        guard example.form.lowerBound >= 0, !example.form.isEmpty, example.form.upperBound <= count else {
            return text
        }
        let scalars = text.unicodeScalars
        let start = scalars.index(scalars.startIndex, offsetBy: example.form.lowerBound)
        let end = scalars.index(start, offsetBy: example.form.count)
        text[start..<end].inlinePresentationIntent = .stronglyEmphasized
        text[start..<end].foregroundColor = .accentColor
        return text
    }
}

// MARK: - Issue #144: inflection tables
//
// Renders an `InflectionTable` (Models.swift) as built: no grammar here.
// Layout uses leading/trailing only, so Arabic mirrors it and the pronoun
// column lands on the right; Greek forms still read left to right.

struct InflectionTableView: View {
    let table: InflectionTable
    /// "All forms" is open. Not stored: every Definition screen starts closed.
    @State private var showsAllForms = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                Text(table.kind == .conjugation
                     ? LocalizedStringKey("forms.section.conjugation")
                     : LocalizedStringKey("forms.section.declension"))
                    .font(.title3.bold())
                    .accessibilityAddTraits(.isHeader)
                if let lemma = table.linkedLemma {
                    Text(verbatim: lemma)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("inflection_linked_lemma")
                }
            }

            ForEach(table.mainSections) { InflectionSectionView(section: $0) }

            if !table.moreSections.isEmpty {
                Button {
                    showsAllForms.toggle()
                } label: {
                    Text(showsAllForms ? LocalizedStringKey("forms.button.mainForms")
                                       : LocalizedStringKey("forms.button.allForms"))
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("inflection_all_forms_button")

                if showsAllForms {
                    ForEach(table.moreSections) { InflectionSectionView(section: $0) }
                }
            }

            Text("forms.source")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inflection_table")
    }
}

/// One section, in the widest rendering that fits: the full grid, bands of
/// two columns, or one block per column (narrow screens, large text). A
/// cell's variants stay on one line when that fits, else one per line. When
/// even a block is too wide (accessibility text sizes), each row label goes
/// above its forms, so the screen never scrolls sideways. A grammar topic
/// draws its tables with it too (0133, #172).
struct InflectionSectionView: View {
    let section: InflectionTable.Section

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let heading = section.heading {
                Text(verbatim: heading)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
            }
            if let title = section.title {
                Text(verbatim: title)
                    .font(.subheadline.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
            }
            let all = Array(section.columns.indices)
            ViewThatFits(in: .horizontal) {
                InflectionGrid(section: section, columns: all, stacksVariants: false)
                InflectionGrid(section: section, columns: all, stacksVariants: true)
                InflectionBands(section: section, perBand: 2, stacksVariants: false)
                InflectionBands(section: section, perBand: 2, stacksVariants: true)
                InflectionBands(section: section, perBand: 1, stacksVariants: true)
                InflectionStack(section: section)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// The section's columns cut into bands of `perBand`, each a grid with the
/// row headers. One per band is the block rendering.
private struct InflectionBands: View {
    let section: InflectionTable.Section
    let perBand: Int
    let stacksVariants: Bool

    var body: some View {
        let starts = Array(stride(from: 0, to: section.columns.count, by: perBand))
        VStack(alignment: .leading, spacing: 14) {
            ForEach(starts, id: \.self) { start in
                InflectionGrid(section: section,
                               columns: Array(start..<min(start + perBand, section.columns.count)),
                               stacksVariants: stacksVariants)
            }
        }
    }
}

/// A grid of the section's `columns`: headers hidden from VoiceOver, each
/// data cell one element that reads "column, row, form".
private struct InflectionGrid: View {
    let section: InflectionTable.Section
    let columns: [Int]
    let stacksVariants: Bool

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 6) {
            if section.showsColumnHeaders {
                GridRow {
                    if section.showsRowHeaders {
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    }
                    ForEach(columns, id: \.self) { index in
                        Text(verbatim: section.columns[index].title)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .fixedSize()
                            .accessibilityHidden(true)
                    }
                }
            }
            ForEach(section.rows) { row in
                GridRow {
                    if section.showsRowHeaders {
                        Text(verbatim: row.header?.title ?? "")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize()
                            .accessibilityHidden(true)
                    }
                    ForEach(columns, id: \.self) { index in
                        InflectionCellView(cell: row.cells[index], stacksVariants: stacksVariants, wraps: false)
                    }
                }
            }
        }
    }
}

/// The last resort: one block per column, each row label above its forms,
/// every text free to wrap. A grid row (Accusative | σπιτιού) does not fit
/// an iPhone at the largest accessibility sizes.
private struct InflectionStack: View {
    let section: InflectionTable.Section

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(section.columns.indices, id: \.self) { index in
                VStack(alignment: .leading, spacing: 8) {
                    if !section.columns[index].title.isEmpty {
                        Text(verbatim: section.columns[index].title)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                    ForEach(section.rows) { row in
                        VStack(alignment: .leading, spacing: 0) {
                            if let header = row.header {
                                Text(verbatim: header.title)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .accessibilityHidden(true)
                            }
                            InflectionCellView(cell: row.cells[index], stacksVariants: true, wraps: true)
                        }
                    }
                }
            }
        }
    }
}

/// One text, so VoiceOver finds one element with the composed label.
private struct InflectionCellView: View {
    let cell: InflectionTable.Cell
    let stacksVariants: Bool
    let wraps: Bool

    var body: some View {
        Text(verbatim: stacksVariants ? cell.stackedText : cell.text)
            .fixedSize(horizontal: !wraps, vertical: true)
            .accessibilityLabel(Text(cell.accessibilityLabel))
            .accessibilityIdentifier(cell.id)
    }
}
