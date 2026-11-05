// LearnView.swift
// The Learn tab (0131-learning.md, #158): the pair picker while no
// language is learned, else the Learn home. E3's list screens (#154) open
// from its Lists section and its My words row. Later tickets add their
// sections to the home.

import SwiftUI

struct LearnView: View {
    @StateObject private var vm = LearnViewModel()
    @Environment(\.locale) private var locale
    @Environment(\.layoutDirection) private var layoutDirection
    /// The run in the full-screen cover: the session, mistakes, a trainer
    /// or match the pairs.
    @State private var running: RunRequest?

    /// A run in `lang`, the chosen language, with its pair's meanings
    /// language (nil without a pair).
    struct RunRequest: Identifiable {
        enum Kind {
            /// The questions of a trainer, the session or mistakes.
            case questions(ExerciseRunViewModel.Run)
            /// Match the pairs (#160).
            case match
        }

        let id = UUID()
        let kind: Kind
        let lang: String
        let meaningsLang: String?
    }

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
            // 0237: a pack installed or removed brings its lists or takes
            // them away.
            .onReceive(NotificationCenter.default.publisher(for: PackService.didChange, object: PackService.shared)) { _ in
                Task { await vm.load(locale: locale) }
            }
            .fullScreenCover(item: $running, onDismiss: {
                Task { await vm.load(locale: locale) }
            }) { request in
                Group {
                    switch request.kind {
                    case let .questions(run):
                        ExerciseRunView(run: run, lang: request.lang, meaningsLang: request.meaningsLang)
                    case .match:
                        MatchPairsView(lang: request.lang, meaningsLang: request.meaningsLang)
                    }
                }
                .environment(\.locale, locale)
                .environment(\.layoutDirection, layoutDirection)
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
                // #164 adds the daily goal ring and the streak here.
                today
                if case .counts? = vm.today {
                    Button {
                        start(.session)
                    } label: {
                        Text("learn.start")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("learn_start_button")
                }
            }
            if vm.mistakeCount > 0 {
                Section {
                    Button {
                        start(.mistakes)
                    } label: {
                        Label("learn.mistakes \(vm.mistakeCount)", systemImage: "arrow.uturn.backward.circle")
                    }
                    .accessibilityIdentifier("learn_mistakes_row")
                }
            }
            Section {
                trainerRow(.recognition, title: "learn.trainer.recognition", symbol: "eye",
                           id: "learn_trainer_recognition")
                trainerRow(.production, title: "learn.trainer.production", symbol: "pencil",
                           id: "learn_trainer_production")
                matchRow
                // E5 adds Conjugation.
            } header: {
                Text("learn.trainers")
            } footer: {
                if !vm.canTrain {
                    Text("learn.trainers.disabled")
                }
            }
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

    /// Opens `run` in the chosen language, with its pair's meanings language.
    private func start(_ run: ExerciseRunViewModel.Run) {
        open(.questions(run))
    }

    private func open(_ kind: RunRequest.Kind) {
        guard let language = vm.language else { return }
        running = RunRequest(kind: kind, lang: language, meaningsLang: vm.pair?.meaningsLang)
    }

    /// Match the pairs (#160): disabled with "Learn 5 words first" while
    /// the chosen language has fewer than 5 words to match. With nothing to
    /// learn, the section's footer says it for every trainer.
    private var matchRow: some View {
        Button {
            open(.match)
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("learn.trainer.match")
                    if vm.canTrain && !vm.canMatch {
                        Text("learn.trainer.match.disabled \(MatchRound.size)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } icon: {
                Image(systemName: "square.grid.2x2")
            }
        }
        .disabled(!vm.canMatch)
        .accessibilityIdentifier("learn_trainer_match")
    }

    /// A trainer: 10 items of its own direction in the chosen language.
    private func trainerRow(_ kind: CardKind, title: LocalizedStringKey, symbol: String, id: String) -> some View {
        Button {
            start(.trainer(kind))
        } label: {
            Label(title, systemImage: symbol)
        }
        .disabled(!vm.canTrain)
        .accessibilityIdentifier(id)
    }

    /// E3's lists (0130, #154): the chosen language's checked lists with
    /// their progress (0166), "New words from" once Today no longer offers
    /// "Choose lists", and "All lists".
    private var lists: some View {
        Section("wordLists.title") {
            ForEach(vm.checkedLists) { list in
                NavigationLink(value: WordListRoute.list(list)) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(WordListsViewModel.title(of: list, locale: locale))
                        if let progress = vm.listProgress[list.id] {
                            LabeledListProgressBar(progress: progress, id: "learn_list_progress_\(list.id.rawValue)")
                        }
                    }
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
