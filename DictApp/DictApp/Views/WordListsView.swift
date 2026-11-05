// WordListsView.swift
// Word lists (0130-word-lists.md, #154): the Lists screen, a list's screen
// and New words from, pushed from the Learn home (E4). Views render and
// call `WordListsViewModel` and `WordListViewModel`; #155 adds the import
// screens here.

import SwiftUI

/// The list screens the Learn home pushes (and #162's Learning settings).
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
/// built-in lists, then My lists (My words, then the imports, newest
/// first). A row shows the title, the word count and, while the list is
/// checked, a "Learning" badge. An imported list can be deleted with a
/// swipe, after an alert.
struct WordListsView: View {
    @StateObject private var vm = WordListsViewModel()
    @Environment(\.locale) private var locale
    /// The imported list the delete alert asks about.
    @State private var pendingDelete: WordList?

    var body: some View {
        List {
            ForEach(vm.sections) { section in
                Section(WordListsViewModel.sectionTitle(section.kind, locale: locale)) {
                    ForEach(section.lists) { list in
                        NavigationLink(value: WordListRoute.list(list)) {
                            WordListRow(list: list, isChecked: vm.checked.contains(list.id))
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
                // ponytail: opens Import in #155
                Button {} label: {
                    Image(systemName: "plus")
                }
                .disabled(true)
                .accessibilityLabel(Text("learn.importList"))
                .accessibilityIdentifier("word_list_import_button")
            }
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

/// A row of the Lists screen. #164 adds the list's progress bar
/// (`ListProgress`, 0166).
private struct WordListRow: View {
    let list: WordList
    let isChecked: Bool
    @Environment(\.locale) private var locale

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(WordListsViewModel.title(of: list, locale: locale))
                Text("wordLists.count \(list.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("word_list_count_\(list.id.rawValue)")
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
        NavigationLink(value: row.entry) {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.entry.word)
                    .font(.headline)
                Text(Self.snippet(row.entry.definition))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityLabel(Text(row.entry.word))
        .accessibilityValue(Text(Self.snippet(row.entry.definition)))
        .accessibilityIdentifier("word_list_item")
        .swipeActions {
            Button("definition.a11y.stopLearning", role: .destructive) {
                Task { await vm.stopLearning(row) }
            }
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
