// DefinitionView.swift
// Detailed word view with Markdown rendering and TTS.

import SwiftUI
import StoreKit   // Issue #12: AppStore.requestReview(in:)
import UIKit      // Issue #12: UIWindowScene for the scene-based review request

struct DefinitionView: View {
    @StateObject private var vm: DefinitionViewModel
    /// The in-app language, for the inflection table's labels (Issue #144).
    @Environment(\.locale) private var locale

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

                // Issue #144: how a Greek headword inflects.
                if let table = vm.inflectionTable {
                    Divider()
                    InflectionTableView(table: table)
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

// MARK: - Issue #5: Reading Mode toolbar button (shared by SearchView + DefinitionView)

struct ReadingModeToolbarButton: View {
    @ObservedObject private var readingMode = ReadingModeService.shared

    var body: some View {
        Button {
            readingMode.toggle()
        } label: {
            Image(systemName: readingMode.isEnabled ? "book.fill" : "book")
        }
        .accessibilityLabel(Text(readingMode.isEnabled ? "readingMode.a11y.disable"
                                                       : "readingMode.a11y.enable"))
        .accessibilityAddTraits(readingMode.isEnabled ? .isSelected : [])
        .accessibilityIdentifier("reading_mode_toggle")
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
/// above its forms, so the screen never scrolls sideways.
private struct InflectionSectionView: View {
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
