// WordListsView.swift
// Word lists (0130-word-lists.md, #154): the Lists screen, a list's screen
// and New words from, pushed from the Learn home (E4), and Import (#155),
// in a sheet. Views render and call `WordListsViewModel`,
// `WordListViewModel` and `ListImportViewModel`.

import SwiftUI
import UniformTypeIdentifiers

/// The list screens the Learn home pushes. Settings → Learning pushes
/// `NewWordsFromView` itself.
enum WordListRoute: Hashable {
    /// The Lists screen.
    case allLists
    /// A list's screen; My words too.
    case list(WordList)
    case newWordsFrom
}

extension View {
    /// The destinations of `WordListRoute`, for the stack that pushes them.
    func wordListDestinations() -> some View {
        navigationDestination(for: WordListRoute.self) { route in
            switch route {
            case .allLists: WordListsView()
            case let .list(list): WordListView(list: list)
            case .newWordsFrom: NewWordsFromView()
            }
        }
    }
}

// MARK: - Lists screen

/// The lists of the learned languages: a section per language with
/// built-in lists (those of the installed packs), then My lists (My words,
/// then the imports, newest first). A row shows the title, the word count,
/// the progress bar and, while the list is checked, a "Learning" badge. An
/// imported list can be deleted with a swipe, after an alert.
struct WordListsView: View {
    @StateObject private var vm = WordListsViewModel()
    @Environment(\.locale) private var locale
    @Environment(\.layoutDirection) private var layoutDirection
    /// The imported list the delete alert asks about.
    @State private var pendingDelete: WordList?
    /// Import's sheet (#155).
    @State private var showsImport = false

    var body: some View {
        List {
            ForEach(vm.sections) { section in
                Section(WordListsViewModel.sectionTitle(section.kind, locale: locale)) {
                    ForEach(section.lists) { list in
                        NavigationLink(value: WordListRoute.list(list)) {
                            WordListRow(list: list, isChecked: vm.checked.contains(list.id),
                                        progress: vm.progress[list.id])
                        }
                        .accessibilityIdentifier("word_list_row_\(list.id.rawValue)")
                        .swipeActions {
                            if list.kind == .user {
                                // Not `.destructive`: that role removes the
                                // row before the alert is answered.
                                Button("wordLists.delete") {
                                    pendingDelete = list
                                }
                                .tint(.red)
                            }
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("word_lists")
        .navigationTitle("wordLists.title")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showsImport = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(Text("learn.importList"))
                .accessibilityIdentifier("word_list_import_button")
            }
        }
        // The new list shows under My lists once Import closes.
        .sheet(isPresented: $showsImport, onDismiss: {
            Task { await vm.load() }
        }) {
            ListImportView()
                .environment(\.locale, locale)
                .environment(\.layoutDirection, layoutDirection)
        }
        .alert(Text("wordLists.delete.title \(pendingDelete?.title ?? "")"),
               isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
               presenting: pendingDelete) { list in
            Button("wordLists.delete", role: .destructive) {
                Task { await vm.delete(list) }
            }
            Button("common.cancel", role: .cancel) {}
        } message: { _ in
            Text("wordLists.delete.message")
        }
        .task {
            await vm.load()
        }
        .onAppear {
            // Back from a list whose "Learn this list" changed the set.
            vm.refreshChecked()
        }
    }
}

/// A row of the Lists screen: the title, the word count, the progress bar
/// once it is read (0166) and, while the list is checked, a "Learning"
/// badge.
private struct WordListRow: View {
    let list: WordList
    let isChecked: Bool
    let progress: ListProgress?
    @Environment(\.locale) private var locale

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(WordListsViewModel.title(of: list, locale: locale))
                Text("wordLists.count \(list.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("word_list_count_\(list.id.rawValue)")
                if let progress {
                    LabeledListProgressBar(progress: progress, id: "word_list_progress_\(list.id.rawValue)")
                        .padding(.top, 2)
                }
            }
            Spacer()
            if isChecked {
                Text("wordLists.learning")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(.tint.opacity(0.15)))
                    .accessibilityIdentifier("word_list_active_\(list.id.rawValue)")
            }
        }
    }
}

/// A list's progress bar with its numbers for VoiceOver ("1 learned · 5
/// learning · 1,451 new"), which a list row shows under its title; the
/// identifier `id` lets UI tests read them.
struct LabeledListProgressBar: View {
    let progress: ListProgress
    let id: String
    @Environment(\.locale) private var locale

    var body: some View {
        ListProgressBar(progress: progress)
            .accessibilityRepresentation {
                Text(verbatim: WordListsViewModel.progressText(progress, locale: locale))
            }
            .accessibilityIdentifier(id)
    }
}

/// Learned, learning and new words of a list, from the leading edge. The
/// numbers next to it carry it for VoiceOver.
struct ListProgressBar: View {
    let progress: ListProgress

    var body: some View {
        GeometryReader { geometry in
            let total = CGFloat(max(progress.total, 1))
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.green)
                    .frame(width: geometry.size.width * CGFloat(progress.learned) / total)
                Rectangle()
                    .fill(Color.accentColor.opacity(0.6))
                    .frame(width: geometry.size.width * CGFloat(progress.learning) / total)
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
            }
        }
        .frame(height: 8)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}

// MARK: - New words from

/// The lists new words come from (0130): every list of a learned language
/// but My words, in the Lists screen's sections and order, each with a
/// checkmark while checked. A tap checks or unchecks it.
struct NewWordsFromView: View {
    @StateObject private var vm = WordListsViewModel()
    @Environment(\.locale) private var locale

    var body: some View {
        List {
            Section {
            } header: {
                Text("newWordsFrom.header")
                    .textCase(nil)
            }
            ForEach(vm.newWordsFromSections) { section in
                Section(WordListsViewModel.sectionTitle(section.kind, locale: locale)) {
                    ForEach(section.lists) { list in
                        row(list)
                    }
                }
            }
            if vm.isLoaded && !vm.hasCheckedList {
                Section {
                } footer: {
                    Text("newWordsFrom.none")
                        .accessibilityIdentifier("new_words_from_none")
                }
            }
        }
        .accessibilityIdentifier("new_words_from")
        .navigationTitle("newWordsFrom.title")
        .task {
            await vm.load()
        }
    }

    private func row(_ list: WordList) -> some View {
        let isChecked = vm.checked.contains(list.id)
        return Button {
            vm.toggleChecked(list.id)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(WordListsViewModel.title(of: list, locale: locale))
                        .foregroundStyle(.primary)
                    Text("wordLists.count \(list.count)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isChecked {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(isChecked ? .isSelected : [])
        .accessibilityIdentifier("new_words_from_row_\(list.id.rawValue)")
    }
}

// MARK: - A list's screen

/// A list's screen: its count and "Learn this list" at the top, then its
/// words alphabetical, a section per level when it has several. A word with
/// a dictionary entry opens its Definition; a standalone word only shows
/// its translation. My words shows its entries' snippets, newest first,
/// with Stop learning on the swipe.
struct WordListView: View {
    @StateObject private var vm: WordListViewModel
    @Environment(\.locale) private var locale

    init(list: WordList) {
        _vm = StateObject(wrappedValue: WordListViewModel(list: list))
    }

    var body: some View {
        Group {
            if vm.list.kind == .myWords && vm.isLoaded && vm.myWords.isEmpty {
                ContentUnavailableView(
                    "learn.myWords",
                    systemImage: "graduationcap",
                    description: Text("learn.myWords.empty")
                )
            } else {
                List {
                    Section {
                        Text("wordLists.count \(vm.count)")
                            .foregroundStyle(.secondary)
                        if vm.canLearn {
                            learnButton
                        }
                    }
                    if vm.list.kind == .myWords {
                        ForEach(vm.myWords) { row in
                            myWordsRow(row)
                        }
                    } else {
                        ForEach(vm.sections) { section in
                            Section {
                                ForEach(section.rows) { row in
                                    wordRow(row)
                                }
                            } header: {
                                if vm.sections.count > 1 && section.levelOrder != 0 {
                                    Text(WordListsViewModel.levelName(section.level, locale: locale))
                                }
                            }
                        }
                    }
                }
                .accessibilityIdentifier("word_list_items")
            }
        }
        .navigationTitle(WordListsViewModel.title(of: vm.list, locale: locale))
        .task {
            await vm.load()
        }
    }

    /// "Learn this list", then "Learning this list" with a checkmark.
    private var learnButton: some View {
        Button {
            vm.toggleLearning()
        } label: {
            if vm.isChecked {
                Label("wordLists.learningThisList", systemImage: "checkmark")
            } else {
                Text("wordLists.learnThisList")
            }
        }
        .accessibilityIdentifier("word_list_learn_button")
    }

    /// A word with an entry opens its Definition, through the pair's
    /// dictionaries; a standalone word opens nothing. VoiceOver reads the
    /// term, then its meaning.
    @ViewBuilder
    private func wordRow(_ row: WordListViewModel.Row) -> some View {
        if row.item.headword != nil {
            NavigationLink {
                ListWordDefinitionView { await vm.entry(for: row.item) }
            } label: {
                WordRowContent(row: row)
            }
            .accessibilityLabel(Text(row.item.term))
            .accessibilityValue(Text(row.meaning))
            .accessibilityIdentifier("word_list_item")
        } else {
            WordRowContent(row: row)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text(row.item.term))
                .accessibilityValue(Text(row.meaning))
                .accessibilityIdentifier("word_list_item")
        }
    }

    /// My words: the word and a one-line snippet of its entry, as the
    /// Bookmarks tab had.
    private func myWordsRow(_ row: MyWordsEntry) -> some View {
        myWordsLink(row)
            .accessibilityIdentifier("word_list_item")
            .swipeActions {
                Button("definition.a11y.stopLearning", role: .destructive) {
                    Task { await vm.stopLearning(row) }
                }
            }
    }

    /// A row with an entry opens its Definition; one whose pack is not
    /// installed (#245) says so and opens the "not downloaded" view.
    @ViewBuilder
    private func myWordsLink(_ row: MyWordsEntry) -> some View {
        if let entry = row.entry {
            NavigationLink(value: entry) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.word)
                        .font(.headline)
                    Text(Self.snippet(entry.definition))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .accessibilityLabel(Text(entry.word))
            .accessibilityValue(Text(Self.snippet(entry.definition)))
        } else {
            let caption = NotDownloaded.pack(ofSource: row.key.source, catalog: .shared)
                .map { PackTexts.notDownloadedSearch($0, locale: locale) } ?? ""
            NavigationLink {
                EntryDestination(key: row.key)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.key.word)
                        .font(.headline)
                    Text(verbatim: caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .accessibilityLabel(Text(row.key.word))
            .accessibilityValue(Text(verbatim: caption))
        }
    }

    private static func snippet(_ text: String) -> String {
        String(text.prefix(100))
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}

/// A word row: the term as the list writes it with its endings in the
/// secondary colour (`αγάπη η`), and its meaning under it.
private struct WordRowContent: View {
    let row: WordListViewModel.Row

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if row.item.endings.isEmpty {
                Text(row.item.term)
            } else {
                Text(row.item.term) + Text(" " + row.item.endings).foregroundStyle(.secondary)
            }
            if !row.meaning.isEmpty {
                Text(row.meaning)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("word_list_item_translation")
            }
        }
    }
}

/// A list word's Definition: its entry is looked up when the row is
/// tapped, not for every row of the list.
private struct ListWordDefinitionView: View {
    let resolve: () async -> DictionaryEntry?
    @State private var entry: DictionaryEntry?
    @State private var isResolved = false

    var body: some View {
        if let entry {
            DefinitionView(entry: entry)
        } else if isResolved {
            ContentUnavailableView("search.notFound.title", systemImage: "book.closed")
        } else {
            ProgressView()
                .task {
                    entry = await resolve()
                    isResolved = true
                }
        }
    }
}

// MARK: - Import (#155)

/// Import (0130, "Import"), in a sheet from the Lists screen's "+" and the
/// Learn home's "Import a list": "Import a file" (CSV, TSV or TXT through
/// the file picker) or "Paste text", a "Formats" help, then the preview and
/// the result.
struct ListImportView: View {
    @StateObject private var vm = ListImportViewModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var path: [Step] = []
    @State private var showsPicker = false

    /// The screens Import pushes.
    enum Step: Hashable {
        case paste, preview, help
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    Button {
                        importFile()
                    } label: {
                        Label("listImport.file", systemImage: "doc")
                    }
                    .disabled(vm.isWorking)
                    .accessibilityIdentifier("list_import_file")
                    NavigationLink(value: Step.paste) {
                        Label("listImport.paste", systemImage: "doc.on.clipboard")
                    }
                    .accessibilityIdentifier("list_import_paste")
                } footer: {
                    if let failure = vm.failure {
                        ListImportFailureText(failure: failure)
                    }
                }
                Section {
                    NavigationLink(value: Step.help) {
                        Label("listImport.formats", systemImage: "questionmark.circle")
                    }
                    .accessibilityIdentifier("list_import_formats")
                }
            }
            .navigationTitle("learn.importList")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
            }
            .navigationDestination(for: Step.self) { step in
                switch step {
                case .paste:
                    ListImportPasteView(vm: vm) { path.append(.preview) }
                case .preview:
                    ListImportPreviewView(vm: vm) { dismiss() }
                case .help:
                    ListImportHelpView()
                }
            }
            .fileImporter(isPresented: $showsPicker,
                          allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText, .text]) { result in
                guard case let .success(url) = result else { return }
                open(url)
            }
        }
    }

    /// The file picker, or the `-importListFixture` file in UI tests.
    private func importFile() {
        #if DEBUG
        if let url = ListImportViewModel.fixtureURL {
            open(url)
            return
        }
        #endif
        showsPicker = true
    }

    private func open(_ url: URL) {
        Task {
            if await vm.open(fileAt: url) { path.append(.preview) }
        }
    }
}

/// Why a file gives no preview, in red.
private struct ListImportFailureText: View {
    let failure: ListImportViewModel.Failure

    var body: some View {
        Group {
            switch failure {
            case .encoding: Text("listImport.error.encoding")
            case .tooBig: Text("listImport.error.tooBig")
            case let .unreadable(message): Text(verbatim: message)
            }
        }
        .foregroundStyle(.red)
        .accessibilityIdentifier("list_import_failure")
    }
}

/// "Paste text": a text box with a Paste button, for a set exported from
/// Quizlet. SwiftUI's `PasteButton` reads the pasteboard without iOS's
/// paste alert.
private struct ListImportPasteView: View {
    @ObservedObject var vm: ListImportViewModel
    let onPreview: () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        Form {
            Section {
                TextEditor(text: $vm.pastedText)
                    .frame(minHeight: 180)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityLabel(Text("listImport.paste"))
                    .accessibilityIdentifier("list_import_text")
                // Centred: the row is the button's accessibility frame, so a
                // tap at the row's centre (VoiceOver, UI tests) reaches it.
                PasteButton(payloadType: String.self) { strings in
                    let text = strings.joined(separator: "\n")
                    Task { @MainActor in vm.pastedText = text }
                }
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("list_import_paste_button")
            } footer: {
                Text("listImport.paste.hint")
            }
            if let failure = vm.failure {
                Section {
                    ListImportFailureText(failure: failure)
                }
            }
        }
        .navigationTitle("listImport.paste")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("listImport.next") {
                    let name = WordListsViewModel.localized("listImport.pastedName", locale: locale)
                    Task {
                        if await vm.openPasted(name: name) { onPreview() }
                    }
                }
                .disabled(vm.isWorking || vm.pastedText.allSatisfy(\.isWhitespace))
                .accessibilityIdentifier("list_import_next")
            }
        }
    }
}

/// The preview before anything is saved: the list's name (editable), its
/// language and delimiter (changeable), the columns found, "1,457 words ·
/// 39 merged · 0 rows with errors", every broken row with its line, its
/// text and the reason, and the first 50 words. Import asks "Learn %@ via
/// %@?" for a language not learned, saves, and shows the result.
private struct ListImportPreviewView: View {
    @ObservedObject var vm: ListImportViewModel
    let onDone: () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        Group {
            if let outcome = vm.outcome {
                result(outcome)
            } else if let preview = vm.preview {
                form(preview)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("learn.importList")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(vm.outcome != nil)
        .alert(Text(questionTitle),
               isPresented: Binding(get: { vm.question != nil }, set: { if !$0 { vm.question = nil } }),
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
        .alert(Text(verbatim: vm.errorMessage ?? ""),
               isPresented: Binding(get: { vm.errorMessage != nil }, set: { if !$0 { vm.errorMessage = nil } })) {
            Button("common.cancel", role: .cancel) {}
        }
    }

    /// "Learn Spanish via English?", or "Learn lists in other languages?".
    private var questionTitle: String {
        switch vm.question {
        case let .pair(pair)?: return LearnViewModel.learnPairQuestion(pair, locale: locale)
        case .other?: return WordListsViewModel.localized("listImport.learnOther", locale: locale)
        case nil: return ""
        }
    }

    private func form(_ preview: ListImportPreview) -> some View {
        Form {
            Section {
                LabeledContent {
                    TextField("listImport.name", text: $vm.name)
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("list_import_name")
                } label: {
                    Text("listImport.name")
                }
                Picker("listImport.language", selection: Binding(
                    get: { vm.language },
                    set: { lang in Task { await vm.setLanguage(lang) } }
                )) {
                    ForEach(ListImportViewModel.languages, id: \.self) { lang in
                        Text(verbatim: LearnViewModel.languageName(lang, locale: locale)).tag(lang)
                    }
                }
                .accessibilityIdentifier("list_import_language")
                Picker("listImport.delimiter", selection: Binding(
                    get: { vm.delimiter },
                    set: { delimiter in Task { await vm.setDelimiter(delimiter) } }
                )) {
                    ForEach(vm.delimiterChoices, id: \.self) { delimiter in
                        Text(verbatim: ListImportViewModel.delimiterName(delimiter, locale: locale)).tag(delimiter)
                    }
                }
                .accessibilityIdentifier("list_import_delimiter")
                LabeledContent {
                    Text(verbatim: ListImportViewModel.columnsText(preview.parse.columns, locale: locale))
                } label: {
                    Text("listImport.columns")
                }
            }
            Section {
                Text(verbatim: ListImportViewModel.summary(preview, locale: locale))
                    .accessibilityIdentifier("list_import_summary")
            }
            if !preview.parse.broken.isEmpty {
                Section("listImport.section.errors") {
                    ForEach(preview.parse.broken, id: \.self) { row in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("listImport.line \(row.line)")
                                .font(.subheadline.weight(.semibold))
                            Text(verbatim: row.text)
                                .font(.subheadline.monospaced())
                                .lineLimit(2)
                            Text(verbatim: ListImportViewModel.problemText(row.problem, locale: locale))
                                .font(.subheadline)
                                .foregroundStyle(.red)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("list_import_error_row")
                    }
                }
            }
            Section("listImport.section.words") {
                ForEach(preview.words.prefix(ListText.previewCount), id: \.word.seq) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        if item.word.endings.isEmpty {
                            Text(verbatim: item.word.term)
                        } else {
                            Text(verbatim: item.word.term)
                                + Text(verbatim: " " + item.word.endings).foregroundStyle(.secondary)
                        }
                        if !item.word.translation.isEmpty {
                            Text(verbatim: item.word.translation)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .accessibilityIdentifier("list_import_preview")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("listImport.confirm") {
                    Task { await vm.confirm() }
                }
                .disabled(!vm.canImport)
                .accessibilityIdentifier("list_import_confirm")
            }
        }
    }

    /// "Imported 1,457 words, 1,371 found in the dictionaries", and Done.
    private func result(_ outcome: ListImportViewModel.Outcome) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text(verbatim: ListImportViewModel.outcomeText(outcome, locale: locale))
                .font(.title3)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("list_import_result")
            Button("listImport.done", action: onDone)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("list_import_done")
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// "Formats" (Kirill, 2026-11-03): the formats Import reads, each with an
/// example kept as it is (a CSV with `term,translation,level`, an Anki
/// plain-text export, text pasted from Quizlet).
struct ListImportHelpView: View {
    static let csvExample = """
        term,translation,level
        σπίτι,house,A1
        γράφω,to write,A1
        θάλασσα,sea,A2
        """

    static let ankiExample = """
        #separator:tab
        #html:true
        #tags column:3
        σπίτι\thouse<br>home\tnoun
        γράφω\tto write\tverb
        """

    static let quizletExample = """
        σπίτι\thouse
        γράφω\tto write
        """

    var body: some View {
        List {
            section("listImport.help.csv", example: Self.csvExample)
            section("listImport.help.anki", example: Self.ankiExample)
            section("listImport.help.quizlet", example: Self.quizletExample)
            Section {
                Text("listImport.help.columns")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("list_import_help")
        .navigationTitle("listImport.help.title")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func section(_ title: LocalizedStringKey, example: String) -> some View {
        Section {
            Text(title)
            // An example reads left to right in every UI language.
            Text(verbatim: example.replacingOccurrences(of: "\t", with: "    "))
                .font(.callout.monospaced())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(.secondarySystemBackground)))
                .environment(\.layoutDirection, .leftToRight)
                .accessibilityIdentifier("list_import_example")
        }
    }
}
