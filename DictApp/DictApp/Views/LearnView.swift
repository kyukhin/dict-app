// LearnView.swift
// The Learn tab (0131-learning.md, #158): the pair picker while no
// language is learned, else the Learn home. E3's list screens (#154) open
// from its Lists section and its My words row. Later tickets add their
// sections to the home: the daily goal ring, the streak and Statistics
// (0166, #164); the Conjugation trainer and its screen (0132, #168). The
// Grammar section, the Grammar screen and a grammar topic (0133, #172).

import SwiftUI

struct LearnView: View {
    @StateObject private var vm = LearnViewModel()
    @Environment(\.locale) private var locale
    @Environment(\.layoutDirection) private var layoutDirection
    /// The run in the full-screen cover: the session, mistakes, a trainer
    /// or match the pairs.
    @State private var running: RunRequest?
    /// The pushed screens: E3's list screens, Statistics, a Definition.
    @State private var path = NavigationPath()
    /// E3's Import (#155), for a language without lists.
    @State private var showsImport = false

    /// The screens the home pushes besides E3's (`WordListRoute`).
    enum Route: Hashable {
        /// 0166, #164: from the ring, the streak or the Statistics row.
        case statistics
        /// 0132, #168: the Conjugation screen, from its Trainers row.
        case conjugation
        /// 0133, #172: the Grammar screen of a language.
        case grammar(String)
    }

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
        NavigationStack(path: $path) {
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
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .statistics: StatisticsView()
                case .conjugation: ConjugationStartView()
                case let .grammar(lang): GrammarTopicsView(lang: lang)
                }
            }
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
            // Back on the home: Statistics may have switched the language,
            // a Definition may have changed what is learned.
            .onChange(of: path.count) { old, new in
                if new < old { Task { await vm.load(locale: locale) } }
            }
            .sheet(isPresented: $showsImport, onDismiss: {
                Task { await vm.load(locale: locale) }
            }) {
                ListImportView()
                    .environment(\.locale, locale)
                    .environment(\.layoutDirection, layoutDirection)
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
            // A failed choice or load (#260): shown until dismissed.
            .alert(Text(verbatim: vm.errorMessage ?? ""), isPresented: Binding(
                get: { vm.errorMessage != nil },
                set: { if !$0 { vm.errorMessage = nil } }
            )) {}
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
            PairInstallSection(packs: vm.pairPacks) {
                vm.retryInstall()
            }
            Section("learn.today") {
                goalAndStreak
                today
                if let left = vm.lessonLeft {
                    // #296: a lesson closed early; its value is the items left.
                    Button {
                        start(.session)
                    } label: {
                        Text("learn.continueLesson \(left)")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityValue(Text(verbatim: "\(left)"))
                    .accessibilityIdentifier("learn_continue_button")
                } else if case .counts? = vm.today {
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
                if vm.canTrain, let level = vm.drillLevel {
                    conjugationRow(level)
                }
            } header: {
                Text("learn.trainers")
            } footer: {
                if !vm.canTrain {
                    Text("learn.trainers.disabled")
                }
            }
            // 0132: "Learn a few words first" is not the drill's. While the
            // other trainers are off, its row follows their footer.
            if !vm.canTrain, let level = vm.drillLevel {
                Section {
                    conjugationRow(level)
                }
            }
            lists
            grammar
            Section {
                NavigationLink(value: WordListRoute.list(vm.myWordsList)) {
                    LabeledContent("learn.myWords") {
                        Text(vm.myWordsCount, format: .number)
                    }
                }
                .accessibilityIdentifier("learn_my_words_row")
            }
            Section {
                NavigationLink(value: Route.statistics) {
                    Label("stats.title", systemImage: "chart.bar.xaxis")
                }
                .accessibilityIdentifier("learn_statistics_row")
            }
        }
        .accessibilityIdentifier("learn_view")
    }

    /// The daily goal ring and the streak (0166, #164): every language.
    /// Both open Statistics.
    @ViewBuilder
    private var goalAndStreak: some View {
        if let goal = vm.goal, let streak = vm.streak {
            HStack(spacing: 16) {
                Button {
                    path.append(Route.statistics)
                } label: {
                    GoalRingView(progress: goal)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: LearnViewModel.goalLabel(goal, locale: locale)))
                .accessibilityValue(Text(verbatim: "\(goal.answered)/\(goal.goal)"))
                .accessibilityIdentifier("learn_goal_ring")
                Spacer()
                Button {
                    path.append(Route.statistics)
                } label: {
                    StreakBadge(streak: streak, isGoalMet: goal.isMet)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: LearnViewModel.streakLabel(streak, locale: locale)))
                .accessibilityValue(Text(verbatim: "\(streak.current)"))
                .accessibilityIdentifier("learn_streak")
            }
            .padding(.vertical, 4)
        }
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
            // A lesson to continue is not "all done" (#296).
            if vm.lessonLeft == nil {
                Text("learn.allDone")
                    .accessibilityIdentifier("learn_all_done")
            }
        case .chooseLists?:
            Text("learn.empty.withLists")
            NavigationLink(value: WordListRoute.newWordsFrom) {
                Text("learn.chooseLists")
            }
            .accessibilityIdentifier("learn_choose_lists")
        case .addWords?:
            Button("learn.importList") {
                showsImport = true
            }
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

    /// 0132, #168: "Conjugation · A2", with the drill's tense level; shown
    /// while Greek is chosen, with or without words in learning. It opens
    /// the Conjugation screen.
    private func conjugationRow(_ level: DrillLevel) -> some View {
        NavigationLink(value: Route.conjugation) {
            LabeledContent {
                Text(verbatim: DrillText.levelName(level, locale: locale))
            } label: {
                Label("drill.title", systemImage: "tablecells")
            }
        }
        .accessibilityLabel(Text("drill.title"))
        .accessibilityValue(Text(verbatim: DrillText.levelName(level, locale: locale)))
        .accessibilityIdentifier("learn_trainer_conjugation")
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

    /// 0133, #172: "Grammar · 17 topics", while the chosen language has
    /// topics (Greek, with the Greek pack). VoiceOver reads the count as
    /// the row's value.
    @ViewBuilder
    private var grammar: some View {
        if vm.grammarTopicCount > 0, let language = vm.language {
            Section("grammar.title") {
                NavigationLink(value: Route.grammar(language)) {
                    LabeledContent {
                        Text("grammar.topicCount \(vm.grammarTopicCount)")
                            .accessibilityHidden(true)
                    } label: {
                        Text("grammar.title")
                    }
                }
                .accessibilityValue(Text("grammar.topicCount \(vm.grammarTopicCount)"))
                .accessibilityIdentifier("learn_grammar_row")
            }
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

// MARK: - Conjugation drill (0132, #168)

/// The Conjugation screen: "Verbs from Greek A1, Greek A2 · 253 verbs",
/// "Tenses up to" (the highest checked list's level up to B2, remembered),
/// the tenses of that level with their accuracy over the last 30 days, and
/// Start, which presents the run. Without the Greek pack, Download first;
/// without a checked Greek list, "Choose lists" (E3's New words from).
struct ConjugationStartView: View {
    @StateObject private var vm = ConjugationDrillViewModel()
    @ObservedObject private var packStatus = PackStatusModel.shared
    @Environment(\.locale) private var locale
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var running: RunRequest?

    /// A session of `pool` at `level`.
    struct RunRequest: Identifiable {
        let id = UUID()
        let pool: [DrillVerb]
        let level: DrillLevel
        let meaningsLang: String
    }

    var body: some View {
        List {
            switch vm.state {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity)
            case .needsGreek:
                needsGreek
            case .noLists:
                noLists
            case .ready:
                ready
            }
            if let error = vm.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .accessibilityIdentifier("drill_start")
        .navigationTitle("drill.title")
        // Again on every return: a list checked on New words from shows at once.
        .onAppear {
            Task { await vm.load() }
        }
        .onReceive(NotificationCenter.default.publisher(for: PackService.didChange, object: PackService.shared)) { _ in
            Task { await vm.load() }
        }
        .fullScreenCover(item: $running, onDismiss: {
            Task { await vm.load() }
        }) { request in
            ConjugationRunView(mode: .session(pool: request.pool, level: request.level),
                               meaningsLang: request.meaningsLang)
                .environment(\.locale, locale)
                .environment(\.layoutDirection, layoutDirection)
        }
    }

    @ViewBuilder
    private var ready: some View {
        Section {
            // "Verbs from Greek A1 · 189 verbs", on two lines when narrow.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    listsText
                    Text(verbatim: "·")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    countText
                }
                VStack(alignment: .leading, spacing: 4) {
                    listsText
                    countText
                }
            }
        }
        Section {
            Picker("drill.tensesUpTo", selection: Binding(get: { vm.level }, set: { vm.setLevel($0) })) {
                ForEach(vm.offeredLevels, id: \.self) { level in
                    Text(verbatim: DrillText.levelName(level, locale: locale)).tag(level)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("drill_tenses_picker")
            ForEach(vm.tenses, id: \.self) { tense in
                tenseRow(tense)
            }
        } header: {
            Text("drill.tensesUpTo")
        }
        Section {
            Button {
                running = RunRequest(pool: vm.pool, level: vm.level, meaningsLang: vm.meaningsLang)
            } label: {
                Text("learn.start")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(vm.verbCount == 0)
            .accessibilityIdentifier("drill_start_button")
        }
    }

    private var listsText: some View {
        Text(verbatim: DrillText.verbsFrom(vm.lists, locale: locale))
            .accessibilityIdentifier("drill_lists")
    }

    private var countText: some View {
        Text("drill.verbCount \(vm.verbCount)")
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("drill_verb_count")
    }

    /// "Aorist · 82%": the value is the accuracy, empty before any answer.
    private func tenseRow(_ tense: ConjugationTense) -> some View {
        let title = tense.title(locale: locale)
        let accuracy = vm.accuracy[tense]?.accuracy.map { ChartSummary.percent($0, locale) } ?? ""
        return LabeledContent {
            Text(verbatim: accuracy)
                .monospacedDigit()
        } label: {
            Text(verbatim: title)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityValue(Text(verbatim: accuracy))
        .accessibilityIdentifier("drill_tense_\(tense.rawValue)")
    }

    /// No Greek list checked: the drill's verbs come from them.
    private var noLists: some View {
        Section {
            Text("drill.noLists")
                .accessibilityIdentifier("drill_no_lists")
            NavigationLink(value: WordListRoute.newWordsFrom) {
                Text("learn.chooseLists")
            }
            .accessibilityIdentifier("drill_choose_lists")
        }
    }

    /// No usable Greek pack (0237): Download, with its progress, or why it
    /// failed and Try again. Cards and progress stay.
    private var needsGreek: some View {
        Section {
            Text("drill.needsGreek")
                .accessibilityIdentifier("drill_needs_greek")
            switch packStatus.state(of: .ell) {
            case .waiting:
                progress(0, text: SettingsViewModel.localizedString("languages.waiting", locale: locale))
            case let .downloading(received, total):
                progress(total > 0 ? Double(received) / Double(total) : 0,
                         text: PackTexts.progress(received: received, total: total, locale: locale))
            case .installing:
                progress(1, text: SettingsViewModel.localizedString("languages.installing", locale: locale))
            case let .failed(error):
                if let reason = PackTexts.error(error, name: greekName, space: greekSize, locale: locale) {
                    Text(verbatim: reason)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                downloadButton(Text("languages.retry"))
            case .notInstalled, .installed, .updateAvailable, .updateRequired:
                downloadButton(Text(verbatim: PackTexts.download(PackCatalog.shared.pack(.ell)?.size ?? 0,
                                                                 locale: locale)))
            }
        }
    }

    private var greekName: String { PackTexts.languageName(ConjugationPlanner.lang, locale: locale) }

    /// The asset and the installed file, which a full disk must hold.
    private var greekSize: Int64 {
        guard let pack = PackCatalog.shared.pack(.ell) else { return 0 }
        return pack.size + pack.fileSize
    }

    private func downloadButton(_ title: Text) -> some View {
        Button {
            Task { await vm.download() }
        } label: {
            title
        }
        .accessibilityIdentifier("drill_download_greek")
    }

    /// The download's bar, with its text under it; VoiceOver reads the text
    /// as the bar's value.
    private func progress(_ fraction: Double, text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ProgressView(value: min(max(fraction, 0), 1))
                .accessibilityLabel(Text(verbatim: greekName))
                .accessibilityValue(Text(verbatim: text))
                .accessibilityIdentifier("drill_download_progress")
            Text(verbatim: text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .accessibilityHidden(true)
        }
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

/// The chosen pair's install on the Learn home (0237, "Learning a pair";
/// 0131), in its own section while `PairInstallRow` shows something.
struct PairInstallSection: View {
    let packs: [PackID]
    let onRetry: () -> Void
    @ObservedObject var status: PackStatusModel = .shared

    var body: some View {
        if PairInstallRow.shown(packs, status: status) != nil {
            Section {
                PairInstallRow(packs: packs, onRetry: onRetry, status: status)
            }
        }
    }
}

/// A pair's install (0237, "Learning a pair"): its first pack on its way,
/// "Greek" with "Downloading…" and the progress, or failed, with Try again;
/// nothing once every pack is installed, or for a pack nobody asked for.
/// On the Learn home and under a language in Settings → Learning →
/// Languages.
struct PairInstallRow: View {
    let packs: [PackID]
    let onRetry: () -> Void
    @ObservedObject var status: PackStatusModel = .shared
    @Environment(\.locale) private var locale

    var body: some View {
        if let (id, state) = Self.shown(packs, status: status) {
            VStack(alignment: .leading, spacing: 8) {
                // The row's id on its title, not the stack: a container id
                // would shadow the Try again button's.
                Text(LearnViewModel.languageName(PackCatalog.shared.pack(id)?.lang ?? "und", locale: locale))
                    .font(.headline)
                    .accessibilityIdentifier("learn_install_row")
                if case .failed = state {
                    Text("learn.install.failed")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("learn_install_error")
                    Button("learn.install.retry", action: onRetry)
                        .accessibilityIdentifier("learn_install_retry")
                } else {
                    Text("learn.install.downloading")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if case let .downloading(received, total) = state, total > 0 {
                        ProgressView(value: Double(received), total: Double(total))
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    /// The first of `packs` waiting, downloading, installing or failed.
    static func shown(_ packs: [PackID], status: PackStatusModel) -> (PackID, PackState)? {
        for id in packs {
            let state = status.state(of: id)
            switch state {
            case .waiting, .downloading, .installing, .failed: return (id, state)
            case .notInstalled, .installed, .updateAvailable, .updateRequired: continue
            }
        }
        return nil
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
/// more; E10's statistics screen reuses it with its own identifier.
struct LearningLanguagePicker: View {
    let languages: [String]
    @Binding var selection: String
    var identifier = "learn_language_switch"
    @Environment(\.locale) private var locale

    var body: some View {
        Picker("learn.language", selection: $selection) {
            ForEach(languages, id: \.self) { lang in
                Text(LearnViewModel.languageName(lang, locale: locale)).tag(lang)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier(identifier)
    }
}

// MARK: - Daily goal and streak (0166, #164)

/// Today's exercises in every language against the daily goal: a ring that
/// fills, "12/20" inside, and a check mark once the goal is met.
struct GoalRingView: View {
    let progress: GoalProgress
    @Environment(\.locale) private var locale

    var body: some View {
        let fraction = progress.goal > 0 ? min(Double(progress.answered) / Double(progress.goal), 1) : 1
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: 6)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if progress.isMet {
                Image(systemName: "checkmark")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.accentColor)
            } else {
                Text(verbatim: "\(progress.answered.formatted(.number.locale(locale)))/\(progress.goal.formatted(.number.locale(locale)))")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(8)
            }
        }
        .frame(width: 56, height: 56)
    }
}

/// The streak's flame, grey until today's goal is met, and the freezes in
/// stock, 0 to 3, next to a snowflake.
struct StreakBadge: View {
    let streak: StreakState
    let isGoalMet: Bool

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(isGoalMet ? Color.orange : Color.secondary)
                Text(streak.current, format: .number)
            }
            HStack(spacing: 4) {
                Image(systemName: "snowflake")
                    .foregroundStyle(.cyan)
                Text(streak.freezes, format: .number)
            }
        }
        .font(.title3.weight(.semibold))
        .monospacedDigit()
    }
}

// MARK: - Grammar (0133, #172)

/// The Grammar screen: one section per level, lowest first, a row per
/// topic titled in the explanation language, and "Topics are explained in
/// English." on top when a topic fell back to English. Rows push the topic
/// with destination links, so the screen works in any stack.
struct GrammarTopicsView: View {
    @StateObject private var vm: GrammarTopicsViewModel
    @Environment(\.locale) private var locale

    init(lang: String) {
        _vm = StateObject(wrappedValue: GrammarTopicsViewModel(lang: lang))
    }

    var body: some View {
        List {
            if vm.showsEnglishNote {
                Section {
                    GrammarEnglishNote()
                }
            }
            ForEach(vm.levels) { level in
                Section {
                    ForEach(level.topics) { topic in
                        NavigationLink {
                            GrammarTopicView(id: topic.id)
                        } label: {
                            Text(GrammarDocument.taggingGreek(AttributedString(topic.title)))
                        }
                        .accessibilityIdentifier("grammar_topic_row_\(topic.id)")
                    }
                } header: {
                    Text(verbatim: WordListsViewModel.levelName(level.level, locale: locale))
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("grammar_level_\(level.level)")
                }
            }
        }
        .overlay {
            if !vm.isLoaded { ProgressView() }
        }
        .accessibilityIdentifier("grammar_topics")
        .navigationTitle("grammar.title")
        .task { await vm.load() }
        .alert(Text(verbatim: vm.errorMessage ?? ""), isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {}
    }
}

/// "Topics are explained in English.", in the UI language, with an info
/// icon hidden from VoiceOver.
struct GrammarEnglishNote: View {
    var body: some View {
        Label {
            Text("grammar.inEnglish")
        } icon: {
            Image(systemName: "info.circle")
                .accessibilityHidden(true)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("grammar_english_note")
    }
}

/// A grammar topic, top to bottom: the title and level, the rule, the
/// tables (#144's section view and its fallbacks), Examples, Watch out,
/// Practise for a topic about tenses, Words and Related topics. The topic's
/// own text (title, rule, tables, examples, Watch out) is laid out left to
/// right, also in Arabic; headings, Practise and the link rows follow the
/// UI. A column of at most 700 pt, centred. Links push with destination
/// links, so the screen works in any tab's stack and in a sheet.
struct GrammarTopicView: View {
    @StateObject private var vm: GrammarTopicViewModel
    @Environment(\.locale) private var locale
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.allowsPractise) private var allowsPractise

    init(id: String) {
        _vm = StateObject(wrappedValue: GrammarTopicViewModel(id: id))
    }

    var body: some View {
        Group {
            switch vm.state {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .unavailable:
                ContentUnavailableView {
                    Label("grammar.unavailable", systemImage: "book.closed")
                }
                .accessibilityIdentifier("grammar_unavailable")
            case .ready:
                content
            }
        }
        .navigationTitle(Text(vm.title))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ReadingModeToolbarButton()
            }
        }
        .task {
            vm.allowsPractise = allowsPractise
            await vm.load()
        }
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
        .alert(Text("grammar.practise.noLists"), isPresented: $vm.asksForLists) {
            Button(GrammarTopicViewModel.greekA1Title(locale: locale)) {
                Task { await vm.practiseGreekA1() }
            }
            Button("learn.chooseLists") {
                vm.chooseLists()
            }
        }
        .navigationDestination(isPresented: $vm.showsNewWordsFrom) {
            NewWordsFromView()
        }
        // E5's drill of the topic's tenses covers the screen.
        .fullScreenCover(item: $vm.practiseRun) { run in
            ConjugationRunView(mode: .tenses(run.tenses, pool: run.pool, level: run.level),
                               meaningsLang: run.meaningsLang)
                .environment(\.locale, locale)
                .environment(\.layoutDirection, layoutDirection)
        }
        .alert(Text(verbatim: vm.errorMessage ?? ""), isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {}
    }

    private var content: some View {
        let rule = vm.blocks.prefix { $0.isRule }
        let rest = vm.blocks.dropFirst(rule.count)
        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if vm.showsEnglishNote {
                    GrammarEnglishNote()
                }
                VStack(alignment: .leading, spacing: 20) {
                    header
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(rule.enumerated()), id: \.offset) { _, block in
                            GrammarTextBlock(block: block)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("grammar_rule")
                }
                .environment(\.layoutDirection, .leftToRight)
                ForEach(Array(rest.enumerated()), id: \.offset) { _, block in
                    restBlock(block)
                }
                practise
                words
                related
            }
            .padding()
            .frame(maxWidth: 700, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("grammar_topic")
    }

    /// The title, then the level ("Α1" in a Greek UI).
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(vm.title)
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("grammar_topic_title")
            if let level = vm.topic?.summary.level {
                Text(verbatim: WordListsViewModel.levelName(level, locale: locale))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("grammar_topic_level")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func restBlock(_ block: GrammarBlock) -> some View {
        switch block {
        case let .caption(text):
            Text(text)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
                .environment(\.layoutDirection, .leftToRight)
        case let .table(section):
            InflectionSectionView(section: section)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier(section.id)
                .environment(\.layoutDirection, .leftToRight)
        case let .examples(examples):
            VStack(alignment: .leading, spacing: 12) {
                heading("grammar.section.examples")
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(examples.enumerated()), id: \.offset) { index, example in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(example.greek)
                            Text(example.translation)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(example.accessibilityLabel))
                        .accessibilityIdentifier("grammar_example_\(index + 1)")
                    }
                }
                .environment(\.layoutDirection, .leftToRight)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("grammar_examples")
            }
        case let .watchOut(items):
            VStack(alignment: .leading, spacing: 12) {
                heading("grammar.section.watchOut")
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        Label {
                            Text(item)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .accessibilityHidden(true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .environment(\.layoutDirection, .leftToRight)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("grammar_watch_out")
            }
        case .paragraph, .bullets:
            GrammarTextBlock(block: block)
                .environment(\.layoutDirection, .leftToRight)
        }
    }

    /// "Practise · Aorist": E5's drill of the topic's tenses.
    @ViewBuilder
    private var practise: some View {
        if allowsPractise && !vm.practiseTenses.isEmpty {
            Button {
                Task { await vm.practise() }
            } label: {
                Text(verbatim: GrammarTopicViewModel.practiseTitle(vm.practiseTenses, locale: locale))
            }
            .buttonStyle(.bordered)
            .accessibilityValue(Text(verbatim: vm.practiseTenses.map(\.rawValue).joined(separator: ",")))
            .accessibilityIdentifier("grammar_practise_button")
        }
    }

    /// The topic's words, each with its short meaning; a tap opens its
    /// Definition.
    @ViewBuilder
    private var words: some View {
        if !vm.words.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                heading("grammar.section.words")
                VStack(spacing: 0) {
                    ForEach(vm.words) { row in
                        if let entry = row.entry {
                            NavigationLink {
                                DefinitionView(entry: entry)
                            } label: {
                                GrammarLinkRow(title: AttributedString.learning(row.word, lang: vm.lang),
                                               subtitle: row.meaning.isEmpty ? nil
                                                   : AttributedString.learning(row.meaning,
                                                                               lang: vm.meaningsLang),
                                               isLink: true)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("grammar_word_\(row.word)")
                        } else {
                            GrammarLinkRow(title: AttributedString.learning(row.word, lang: vm.lang),
                                           subtitle: row.meaning.isEmpty ? nil
                                               : AttributedString.learning(row.meaning, lang: vm.meaningsLang),
                                           isLink: false)
                                .accessibilityIdentifier("grammar_word_\(row.word)")
                        }
                        if row.id != vm.words.last?.id { Divider() }
                    }
                }
            }
        }
    }

    /// Related topics; a tap opens the topic.
    @ViewBuilder
    private var related: some View {
        if let related = vm.topic?.related, !related.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                heading("grammar.section.related")
                VStack(spacing: 0) {
                    ForEach(related) { topic in
                        NavigationLink {
                            GrammarTopicView(id: topic.id)
                        } label: {
                            GrammarLinkRow(title: GrammarDocument.taggingGreek(AttributedString(topic.title)),
                                           subtitle: nil, isLink: true)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("grammar_related_\(topic.id)")
                        if topic.id != related.last?.id { Divider() }
                    }
                }
            }
        }
    }

    private func heading(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.title3.bold())
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A paragraph or a `- ` list of a topic's rule.
private struct GrammarTextBlock: View {
    let block: GrammarBlock

    var body: some View {
        switch block {
        case let .paragraph(text):
            Text(text)
                .frame(maxWidth: .infinity, alignment: .leading)
        case let .bullets(items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(verbatim: "•")
                            .accessibilityHidden(true)
                        Text(item)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        case .caption, .table, .examples, .watchOut:
            EmptyView()
        }
    }
}

/// A Words or Related topics row: its text, a secondary line, and a
/// chevron that mirrors in Arabic. Definition's Grammar rows too (#174).
struct GrammarLinkRow: View {
    let title: AttributedString
    let subtitle: AttributedString?
    let isLink: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if isLink {
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
