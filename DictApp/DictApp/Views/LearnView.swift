// LearnView.swift
// The Learn tab (0131-learning.md, #158): the pair picker while no
// language is learned, else the Learn home. E3's list screens (#154) open
// from its Lists section and its My words row. Later tickets add their
// sections to the home.

import SwiftUI

struct LearnView: View {
    @StateObject private var vm = LearnViewModel()
    @Environment(\.locale) private var locale

    var body: some View {
        NavigationStack {
            Group {
                if !vm.isLoaded {
                    ProgressView()
                } else if vm.learned.isEmpty {
                    LanguagePickerView(pairs: vm.pickerRows, withLists: vm.languagesWithLists,
                                       downloadSizes: vm.downloadSizes) { pair in
                        Task { await vm.choose(pair, locale: locale) }
                    }
                } else {
                    home
                }
            }
            .navigationTitle("learn.title")
            .wordListDestinations()
            .navigationDestination(for: DictionaryEntry.self) { entry in
                DefinitionView(entry: entry)
            }
            .task {
                await vm.load(locale: locale)
            }
        }
    }

    private var home: some View {
        List {
            if vm.learned.count > 1, let language = vm.language {
                Section {
                    LearningLanguagePicker(languages: vm.learned, selection: Binding(
                        get: { language },
                        set: { lang in Task { await vm.select(lang) } }
                    ))
                }
            }
            Section("learn.today") {
                // #164 adds the daily goal ring and the streak here, #161 Start.
                today
            }
            // #161 adds Practise mistakes, #159 and #160 the Trainers.
            lists
            Section {
                NavigationLink(value: WordListRoute.list(vm.myWordsList)) {
                    LabeledContent("learn.myWords") {
                        Text(vm.myWordsCount, format: .number)
                    }
                }
                .accessibilityIdentifier("learn_my_words_row")
            }
            // #164 adds Statistics.
        }
        .accessibilityIdentifier("learn_view")
    }

    @ViewBuilder
    private var today: some View {
        switch vm.today {
        case let .counts(due, newLeft)?:
            // "12 words due · 6 new words left today", on two lines when narrow.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    dueText(due)
                    Text(verbatim: "·")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    newText(newLeft)
                }
                VStack(alignment: .leading, spacing: 4) {
                    dueText(due)
                    newText(newLeft)
                }
            }
        case .allDone?:
            Text("learn.allDone")
                .accessibilityIdentifier("learn_all_done")
        case .chooseLists?:
            Text("learn.empty.withLists")
            NavigationLink(value: WordListRoute.newWordsFrom) {
                Text("learn.chooseLists")
            }
            .accessibilityIdentifier("learn_choose_lists")
        case .addWords?:
            // ponytail: opens E3's Import in #155
            Button("learn.importList") {}
                .disabled(true)
                .accessibilityIdentifier("learn_import_list")
            Text("learn.addWordsHint")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("learn_add_words_hint")
        case nil:
            ProgressView()
        }
    }

    /// E3's lists (0130, #154): the chosen language's checked lists, "New
    /// words from" once Today no longer offers "Choose lists", and "All
    /// lists". #164 adds each list's progress bar.
    private var lists: some View {
        Section("wordLists.title") {
            ForEach(vm.checkedLists) { list in
                NavigationLink(value: WordListRoute.list(list)) {
                    Text(WordListsViewModel.title(of: list, locale: locale))
                }
                .accessibilityIdentifier("learn_list_row_\(list.id.rawValue)")
            }
            if vm.showsNewWordsFrom {
                NavigationLink(value: WordListRoute.newWordsFrom) {
                    Text("newWordsFrom.title")
                }
                .accessibilityIdentifier("learn_new_words_from_row")
            }
            NavigationLink(value: WordListRoute.allLists) {
                Text("learn.allLists")
            }
            .accessibilityIdentifier("learn_all_lists_row")
        }
    }

    private func dueText(_ count: Int) -> some View {
        Text("learn.today.due \(count)")
            .accessibilityIdentifier("learn_due_count")
    }

    private func newText(_ count: Int) -> some View {
        Text("learn.today.newLeft \(count)")
            .accessibilityIdentifier("learn_new_count")
    }
}

// MARK: - Language picker

/// "Which language do you want to learn?" (0131, Languages and pairs): a
/// row per pair, "Greek via English", the pairs of languages with built-in
/// lists first, captioned "With word lists", then the others. Under a row,
/// a limited pair's warning and the size still to download. The Learn tab
/// shows it while no language is learned; #162 pushes it from "Add a
/// language".
struct LanguagePickerView: View {
    /// In order: `LearningPairs.pickerRows`.
    let pairs: [LearningPair]
    let withLists: Set<String>
    /// Bytes to download per pair; 0 or absent: no size line.
    let downloadSizes: [LearningPair: Int64]
    let onChoose: (LearningPair) -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        let listed = pairs.filter { withLists.contains($0.lang) }
        let others = pairs.filter { !withLists.contains($0.lang) }
        List {
            Section {
                ForEach(listed.isEmpty ? others : listed, id: \.self) { row($0) }
            } header: {
                VStack(alignment: .leading, spacing: 12) {
                    Text("learn.picker.title")
                        .font(.title3.bold())
                        .foregroundStyle(.primary)
                        .textCase(nil)
                        .accessibilityAddTraits(.isHeader)
                    if !listed.isEmpty {
                        Text("learn.picker.withLists")
                    }
                }
            }
            if !listed.isEmpty && !others.isEmpty {
                Section {
                    ForEach(others, id: \.self) { row($0) }
                }
            }
        }
        .accessibilityIdentifier("language_picker")
    }

    /// The pair's button, then its notes as their own elements, so VoiceOver
    /// reads them and UI tests find them.
    private func row(_ pair: LearningPair) -> some View {
        let id = "\(pair.lang)-\(pair.via)"
        let size = downloadSizes[pair] ?? 0
        return VStack(alignment: .leading, spacing: 4) {
            Button {
                onChoose(pair)
            } label: {
                Text(LearnViewModel.pairName(pair, locale: locale))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("language_picker_row_\(id)")
            LimitedPairNote(pair: pair)
                .accessibilityIdentifier("language_picker_limited_\(id)")
            if size > 0 {
                Text("learn.picker.download \(size.formatted(.byteCount(style: .file).locale(locale)))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("language_picker_size_\(id)")
            }
        }
    }
}

/// A limited pair's warning, "Words are practised in English.", with an
/// info icon hidden from VoiceOver so the text carries it; nothing for a
/// full pair. Under the picker's rows, and under #162's Settings rows.
struct LimitedPairNote: View {
    let pair: LearningPair
    @Environment(\.locale) private var locale

    var body: some View {
        if let warning = LearnViewModel.limitedWarning(pair, locale: locale) {
            Label {
                Text(warning)
            } icon: {
                Image(systemName: "info.circle")
                    .accessibilityHidden(true)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Language switch

/// The Learn home's switch between the learned languages, shown with two or
/// more; E10's statistics screen reuses it.
struct LearningLanguagePicker: View {
    let languages: [String]
    @Binding var selection: String
    @Environment(\.locale) private var locale

    var body: some View {
        Picker("learn.language", selection: $selection) {
            ForEach(languages, id: \.self) { lang in
                Text(LearnViewModel.languageName(lang, locale: locale)).tag(lang)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("learn_language_switch")
    }
}
