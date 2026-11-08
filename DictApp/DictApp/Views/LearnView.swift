// LearnView.swift
// The Learn tab (0131-learning.md, #158): the pair picker while no
// language is learned, else the Learn home. E3's list screens (#154) open
// from its Lists section and its My words row. Later tickets add their
// sections to the home: the daily goal ring, the streak and Statistics
// (0166, #164).

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
            Text("learn.allDone")
                .accessibilityIdentifier("learn_all_done")
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
