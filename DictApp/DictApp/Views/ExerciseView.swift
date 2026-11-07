// ExerciseView.swift
// The runs (0131-learning.md, "Exercises" and "Instant feedback", #159):
// the run screen with its close button and progress bar, the three
// questions, the feedback bar and the summary. The views render the
// questions and states `ExerciseRunViewModel` gives them; the summary of a
// trainer, the session and mistakes practice (#161). Match the pairs
// (`MatchPairsView`, #160).

import SwiftUI

/// A run, shown in a `fullScreenCover`. On iPad and in landscape the content
/// is at most 600 pt wide and centred.
struct ExerciseRunView: View {
    static let maxWidth: CGFloat = 600

    @StateObject private var vm: ExerciseRunViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    init(run: ExerciseRunViewModel.Run, lang: String, meaningsLang: String?) {
        _vm = StateObject(wrappedValue: ExerciseRunViewModel(run: run, lang: lang, meaningsLang: meaningsLang))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack {
                if let feedback = vm.feedback {
                    FeedbackBar(feedback: feedback) {
                        Task { await vm.next() }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.2), value: vm.feedback)
        }
        .background(Color(.systemBackground))
        .sensoryFeedback(trigger: vm.feedback) { _, feedback in
            feedback.flatMap { vm.haptic(for: $0.outcome) }
        }
        .onChange(of: vm.feedback) { _, feedback in
            guard let feedback else { return }
            let lines = FeedbackBar.lines(feedback, locale: locale)
            AccessibilityNotification.Announcement([lines.title, lines.detail].compactMap { $0 }.joined(separator: ". ")).post()
        }
        .task {
            await vm.start()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("exercise_view")
    }

    private var header: some View {
        HStack(spacing: 16) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel(Text("exercise.close"))
            .accessibilityIdentifier("exercise_close")

            ProgressView(value: Double(min(vm.answered, max(vm.total, 1))), total: Double(max(vm.total, 1)))
                .accessibilityLabel(Text("exercise.progress \(vm.position) \(vm.total)"))
                .accessibilityValue(Text(verbatim: ""))
                .accessibilityIdentifier("exercise_progress")
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .frame(maxWidth: Self.maxWidth)
    }

    @ViewBuilder
    private var content: some View {
        switch vm.phase {
        case .loading:
            ProgressView()
        case .question:
            if let question = vm.question {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        questionView(question)
                        if let error = vm.errorMessage {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding()
                    .frame(maxWidth: Self.maxWidth, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                // A new question starts at the top, with a fresh field.
                .id(question)
            } else {
                ProgressView()
            }
        case .empty:
            ContentUnavailableView {
                Label("exercise.nothing", systemImage: "checkmark.circle")
            } description: {
                if let error = vm.errorMessage {
                    Text(error)
                }
            }
        case .summary:
            RunSummaryView(summary: vm.summary ?? ReviewSummary(), goal: vm.goalProgress) {
                dismiss()
            }
            .frame(maxWidth: Self.maxWidth)
        }
    }

    @ViewBuilder
    private func questionView(_ question: Question) -> some View {
        if question.isRecognition {
            RecognitionQuestion(question: question, feedback: vm.feedback, answerHints: vm.answerHints) { option in
                Task { await vm.choose(option) }
            }
        } else if question.input == .choice {
            ProductionChoiceQuestion(question: question, feedback: vm.feedback, answerHints: vm.answerHints) { option in
                Task { await vm.choose(option) }
            }
        } else {
            ProductionTypedQuestion(question: question, feedback: vm.feedback, typed: $vm.typed,
                                    onCheck: { Task { await vm.check() } },
                                    onDontKnow: { Task { await vm.dontKnow() } })
        }
    }
}

// MARK: - Questions

/// The word (large) with its endings, its part of speech, a speaker button
/// when the device has a voice (#202), and up to 4 meanings.
struct RecognitionQuestion: View {
    let question: Question
    let feedback: AnswerFeedback?
    let answerHints: Bool
    let onChoose: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                NewWordBadge(isNew: question.isNew)
                HStack(alignment: .firstTextBaseline) {
                    LearnWordText(term: question.prompt, endings: question.promptEndings, lang: question.promptLanguage)
                        .font(.largeTitle.bold())
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("exercise_prompt")
                    Spacer()
                    if let voice = SpeechService.voiceLanguages[question.word.key.lang], SpeechService.hasVoice(for: voice) {
                        Button {
                            SpeechService.shared.speak(question.word.term, language: voice)
                        } label: {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.title2)
                        }
                        .accessibilityLabel(Text("definition.a11y.speakWord"))
                    }
                }
                if !question.word.partOfSpeech.isEmpty {
                    Text(question.word.partOfSpeech)
                        .font(.subheadline)
                        .italic()
                        .foregroundStyle(.secondary)
                }
            }
            OptionList(question: question, feedback: feedback, answerHints: answerHints, onChoose: onChoose)
        }
    }
}

/// The meaning, and up to 4 words.
struct ProductionChoiceQuestion: View {
    let question: Question
    let feedback: AnswerFeedback?
    let answerHints: Bool
    let onChoose: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            MeaningPrompt(question: question)
            OptionList(question: question, feedback: feedback, answerHints: answerHints, onChoose: onChoose)
        }
    }
}

/// The meaning, a text field ("Type the word in Greek"), Check and
/// "Don't know", which counts as wrong.
struct ProductionTypedQuestion: View {
    let question: Question
    let feedback: AnswerFeedback?
    @Binding var typed: String
    let onCheck: () -> Void
    let onDontKnow: () -> Void
    @FocusState private var isFocused: Bool
    @Environment(\.locale) private var locale

    private var isEmpty: Bool { typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            MeaningPrompt(question: question)
            TextField(text: $typed, prompt: placeholder) {
                placeholder
            }
            .font(.title3)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .focused($isFocused)
            .onSubmit {
                if !isEmpty { onCheck() }
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 12).strokeBorder(borderColor, lineWidth: 2))
            .disabled(feedback != nil)
            .accessibilityIdentifier("exercise_answer_field")

            if feedback == nil {
                VStack(spacing: 12) {
                    Button(action: onCheck) {
                        Text("exercise.check")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isEmpty)
                    .accessibilityIdentifier("exercise_check")

                    Button(action: onDontKnow) {
                        Text("exercise.dontKnow")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .accessibilityIdentifier("exercise_dont_know")
                }
            }
        }
        .onAppear {
            isFocused = true
        }
    }

    /// "Type the word in Greek"; without a language name for `und`.
    private var placeholder: Text {
        let lang = question.word.key.lang
        guard lang != "und" else { return Text("exercise.typeWord") }
        return Text("exercise.typeIn \(LearnViewModel.languageName(lang, locale: locale))")
    }

    private var borderColor: Color {
        switch feedback?.outcome {
        case .right?, .accent?: return .green
        case .wrong?: return .red
        case nil: return Color(.separator)
        }
    }
}

/// A production prompt: the meaning, as the dictionary or list gives it.
private struct MeaningPrompt: View {
    let question: Question

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            NewWordBadge(isNew: question.isNew)
            Text(AttributedString.learning(question.prompt, lang: question.promptLanguage))
                .font(.title2.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("exercise_prompt")
        }
    }
}

/// "New word" on a card's first question.
private struct NewWordBadge: View {
    let isNew: Bool

    var body: some View {
        if isNew {
            Text("exercise.newWord")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .foregroundStyle(.white)
                .background(Capsule().fill(Color.accentColor))
                .accessibilityIdentifier("exercise_new_badge")
        }
    }
}

/// A word as its list writes it: its endings in the secondary colour.
/// VoiceOver reads it in `lang`'s voice.
struct LearnWordText: View {
    let term: String
    let endings: String
    /// ISO 639-3; nil: the UI language's voice.
    var lang: String?

    var body: some View {
        if endings.isEmpty {
            Text(AttributedString.learning(term, lang: lang))
        } else {
            Text(AttributedString.learning(term, lang: lang))
                + Text(AttributedString.learning(" " + endings, lang: lang)).foregroundStyle(.secondary)
        }
    }
}

extension AttributedString {
    /// `text` tagged with its language (`languageIdentifier`, from ISO
    /// 639-3), so VoiceOver reads a meaning in the meanings language's
    /// voice, σπίτι in Greek in English via Greek (0131, "Meanings").
    static func learning(_ text: String, lang: String?) -> AttributedString {
        var run = AttributedString(text)
        if let lang, let identifier = SpeechService.voiceLanguages[lang] {
            run.languageIdentifier = identifier
        }
        return run
    }
}

// MARK: - Options and feedback

/// The options. Once answered, the right one turns green with a check mark,
/// always, and a wrong choice red with a cross: colour is never the only
/// signal.
private struct OptionList: View {
    let question: Question
    let feedback: AnswerFeedback?
    let answerHints: Bool
    let onChoose: (Int) -> Void

    var body: some View {
        VStack(spacing: 12) {
            ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                OptionButton(option: option, lang: question.optionLanguage, state: state(of: index)) {
                    onChoose(index)
                }
                .allowsHitTesting(feedback == nil)
                .accessibilityValue(accessibilityValue(of: index))
                .accessibilityIdentifier("exercise_option_\(index)")
            }
        }
    }

    private func state(of index: Int) -> OptionButton.Mark {
        guard let feedback else { return .open }
        if index == question.rightIndex { return .right }
        return index == feedback.chosenIndex ? .wrong : .closed
    }

    private func accessibilityValue(of index: Int) -> Text {
        switch state(of: index) {
        case .right: return Text("exercise.a11y.correct")
        case .wrong: return Text("exercise.a11y.wrong")
        case .open where answerHints && index == question.rightIndex: return Text(verbatim: "answer")
        case .open, .closed: return Text(verbatim: "")
        }
    }
}

private struct OptionButton: View {
    enum Mark {
        /// Waiting for an answer.
        case open
        case right
        /// The wrong choice.
        case wrong
        /// Another option, after the answer.
        case closed
    }

    let option: Question.Option
    /// The option's language: the meanings language or the word's.
    let lang: String?
    let state: Mark
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                LearnWordText(term: option.text, endings: option.endings, lang: lang)
                    .font(.body)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let symbol {
                    Image(systemName: symbol)
                        .font(.title3)
                        .foregroundStyle(tint)
                        .accessibilityHidden(true)
                }
            }
            .padding()
            .frame(minHeight: 52)
            .background(RoundedRectangle(cornerRadius: 12).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(tint, lineWidth: state == .open ? 1 : 2))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var symbol: String? {
        switch state {
        case .right: return "checkmark.circle.fill"
        case .wrong: return "xmark.circle.fill"
        case .open, .closed: return nil
        }
    }

    private var tint: Color {
        switch state {
        case .right: return .green
        case .wrong: return .red
        case .open, .closed: return Color(.separator)
        }
    }

    private var fill: Color {
        switch state {
        case .right: return .green.opacity(0.15)
        case .wrong: return .red.opacity(0.15)
        case .open, .closed: return Color(.secondarySystemBackground)
        }
    }
}

/// Slides up on an answer: "Right!" or "Right answer: write", and Continue.
struct FeedbackBar: View {
    let feedback: AnswerFeedback
    let onContinue: () -> Void
    @Environment(\.locale) private var locale

    private var isRight: Bool { feedback.outcome.isRight }

    var body: some View {
        let lines = Self.lines(feedback, locale: locale)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: isRight ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(isRight ? Color.green : Color.red)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: lines.title)
                        .font(.headline)
                    if let detail = lines.detail {
                        Text(verbatim: detail)
                            .font(.subheadline)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            Button(action: onContinue) {
                Text("exercise.continue")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(isRight ? .green : .red)
            .accessibilityIdentifier("exercise_continue")
        }
        .padding()
        .frame(maxWidth: ExerciseRunView.maxWidth, alignment: .leading)
        .frame(maxWidth: .infinity)
        .background {
            Rectangle()
                .fill((isRight ? Color.green : Color.red).opacity(0.12))
                .background(.bar)
                .ignoresSafeArea(edges: .bottom)
        }
        .accessibilityElement(children: .contain)
        .accessibilityValue(Text(verbatim: feedback.outcome.rawValue))
        .accessibilityIdentifier("exercise_feedback")
    }

    /// The bar's text, also announced by VoiceOver. The word or meaning is
    /// isolated (FSI…PDI), so a Greek word keeps left to right in Arabic.
    static func lines(_ feedback: AnswerFeedback, locale: Locale) -> (title: String, detail: String?) {
        let bundle = SettingsViewModel.localizedBundle(for: locale)
        let mark = locale.language.characterDirection == .rightToLeft ? "\u{200F}" : ""
        func text(_ key: String, _ argument: String? = nil) -> String {
            let format = bundle.localizedString(forKey: key, value: key, table: nil)
            guard let argument else { return format }
            return mark + String(format: format, locale: locale, "\u{2068}\(argument)\u{2069}")
        }
        switch feedback.outcome {
        case .right:
            return (text("exercise.right"), nil)
        case .accent:
            return (text("exercise.right"), text("exercise.mindAccent %@", feedback.rightAnswer))
        case .wrong:
            return (text(feedback.mindTheAccent ? "exercise.mindAccent %@" : "exercise.rightAnswer %@", feedback.rightAnswer), nil)
        }
    }
}

// MARK: - Summary

/// The end of a run: exercises, right answers in %, new words, reviewed
/// words and time, from the run's log rows (`ReviewSummary`), and the daily
/// goal's progress (E10).
struct RunSummaryView: View {
    let summary: ReviewSummary
    let goal: GoalProgress?
    let onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text("run.summary.title")
                    .font(.title.bold())
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: 12) {
                    row("run.summary.exercises", id: "run_summary_exercises") {
                        Text(summary.exercises, format: .number)
                    }
                    row("run.summary.accuracy", id: "run_summary_accuracy") {
                        Text(summary.accuracy ?? 0, format: .percent.precision(.fractionLength(0)))
                    }
                    row("run.summary.newWords", id: "run_summary_new_words") { Text(summary.newWords, format: .number) }
                    row("run.summary.reviewed", id: "run_summary_reviewed") {
                        Text(summary.reviewedWords, format: .number)
                    }
                    row("run.summary.time", id: "run_summary_time") {
                        Text(Duration.milliseconds(summary.timeMs), format: .time(pattern: .minuteSecond))
                    }
                    if let goal {
                        row("run.summary.goal", id: "run_summary_goal") {
                            Text("run.summary.goal.value \(goal.answered) \(goal.goal)")
                        }
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
                Button(action: onDone) {
                    Text("run.summary.done")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("run_summary_done")
            }
            .padding()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("run_summary")
    }

    /// A number; `id` on its value, for UI tests.
    private func row(_ title: LocalizedStringKey, id: String, @ViewBuilder value: () -> Text) -> some View {
        LabeledContent {
            value()
                .monospacedDigit()
                .accessibilityIdentifier(id)
        } label: {
            Text(title)
        }
    }
}

// MARK: - Match the pairs (#160)

/// Match the pairs, in a `fullScreenCover`: the close button and the timer,
/// then the words and their meanings in two columns, the words on the
/// leading side (the right in Arabic). A tap selects a tile, a tap in the
/// other column grades the pair: a right pair disappears, a wrong one
/// flashes red with a cross. At the end, the round's time and mistakes,
/// with Next round and Done. The content is at most 600 pt wide, centred.
struct MatchPairsView: View {
    @StateObject private var vm: MatchPairsViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    init(lang: String, meaningsLang: String?) {
        _vm = StateObject(wrappedValue: MatchPairsViewModel(lang: lang, meaningsLang: meaningsLang))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(.systemBackground))
        .sensoryFeedback(trigger: vm.feedback) { _, feedback in
            feedback.flatMap { vm.haptic(for: $0.outcome) }
        }
        .onChange(of: vm.feedback) { _, feedback in
            guard let feedback else { return }
            let key = feedback.outcome.isRight ? "match.a11y.matched" : "match.a11y.notAPair"
            let bundle = SettingsViewModel.localizedBundle(for: locale)
            AccessibilityNotification.Announcement(bundle.localizedString(forKey: key, value: key, table: nil)).post()
        }
        .task {
            await vm.start()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("match_view")
    }

    private var header: some View {
        HStack(spacing: 16) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel(Text("exercise.close"))
            .accessibilityIdentifier("exercise_close")
            Spacer()
            if vm.phase == .playing || vm.phase == .finished {
                TimelineView(.periodic(from: vm.startedAt, by: 1)) { context in
                    let elapsed = vm.elapsed(at: context.date)
                    Label {
                        Text(elapsed, format: .time(pattern: .minuteSecond))
                    } icon: {
                        Image(systemName: "timer")
                    }
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("match.time"))
                    .accessibilityValue(Text(elapsed, format: .time(pattern: .minuteSecond)))
                    .accessibilityAddTraits(.updatesFrequently)
                    .accessibilityIdentifier("match_timer")
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .frame(maxWidth: ExerciseRunView.maxWidth)
    }

    @ViewBuilder
    private var content: some View {
        switch vm.phase {
        case .loading:
            ProgressView()
        case .unavailable:
            ContentUnavailableView {
                Label("learn.trainer.match.disabled \(MatchRound.size)", systemImage: "square.grid.2x2")
            } description: {
                if let error = vm.errorMessage {
                    Text(error)
                }
            }
        case .playing:
            if let round = vm.round {
                board(round)
            }
        case .finished:
            MatchResultView(time: vm.elapsed(at: Date()), mistakes: vm.round?.mistakes ?? 0) {
                Task { await vm.nextRound() }
            } onDone: {
                dismiss()
            }
            .frame(maxWidth: ExerciseRunView.maxWidth)
        }
    }

    /// The two columns, each tile as tall as the others of its column.
    private func board(_ round: MatchRound) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("match.prompt")
                    .font(.title2.bold())
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                HStack(alignment: .top, spacing: 12) {
                    column(round, words: true)
                    column(round, words: false)
                }
                .fixedSize(horizontal: false, vertical: true)
                .animation(.easeOut(duration: 0.2), value: round)
                .animation(.easeOut(duration: 0.2), value: vm.flashing)
                if let error = vm.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .padding()
            .frame(maxWidth: ExerciseRunView.maxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    /// The words (`match_word_0…4`) or the meanings (`match_meaning_0…4`),
    /// top to bottom. A matched tile keeps its place, hidden.
    private func column(_ round: MatchRound, words: Bool) -> some View {
        let order = words ? round.wordColumn : round.meaningColumn
        return VStack(spacing: 12) {
            ForEach(Array(order.enumerated()), id: \.offset) { position, index in
                let tile: MatchRound.Tile = words ? .word(position) : .meaning(position)
                let word = round.words[index]
                MatchTile(text: words ? word.term : word.meaning, endings: words ? word.endings : "",
                          lang: words ? word.key.lang : vm.meaningsLang, mark: mark(of: tile, index, in: round),
                          value: hint(for: tile, index, in: round),
                          identifier: words ? "match_word_\(position)" : "match_meaning_\(position)") {
                    Task { await vm.tap(tile) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(words ? "match.words" : "match.meanings"))
    }

    private func mark(of tile: MatchRound.Tile, _ index: Int, in round: MatchRound) -> MatchTile.Mark {
        if round.matched.contains(index) { return .matched }
        if vm.flashing.contains(tile) { return .wrong }
        return round.selection == tile ? .selected : .open
    }

    /// `-learningAnswerHints`: while a tile is selected, its pair in the
    /// other column has the value `answer`.
    private func hint(for tile: MatchRound.Tile, _ index: Int, in round: MatchRound) -> Text {
        guard vm.answerHints, let selected = round.selection, selected.isWord != tile.isWord,
              round.word(at: selected) == index else { return Text(verbatim: "") }
        return Text(verbatim: "answer")
    }
}

/// A tile: a word with its endings, or a meaning. Selected, it has a
/// thicker accent border and VoiceOver's "Selected"; a wrong pair's tiles
/// turn red with a cross; a matched tile fades out, keeping its place, and
/// leaves VoiceOver.
private struct MatchTile: View {
    enum Mark {
        case open, selected, wrong, matched
    }

    let text: String
    let endings: String
    /// The text's language, for VoiceOver's voice; nil: the UI language's.
    let lang: String?
    let mark: Mark
    /// The accessibility value: `answer` under `-learningAnswerHints`.
    let value: Text
    let identifier: String
    let action: () -> Void

    var body: some View {
        if mark == .matched {
            // Not a button any more: hidden from sight and from VoiceOver.
            face
                .hidden()
                .accessibilityHidden(true)
        } else {
            Button(action: action) {
                face
            }
            .buttonStyle(.plain)
            .accessibilityValue(value)
            .accessibilityAddTraits(mark == .selected ? .isSelected : [])
            .accessibilityIdentifier(identifier)
        }
    }

    private var face: some View {
        HStack(spacing: 6) {
            LearnWordText(term: text, endings: endings, lang: lang)
                .font(.body)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if mark == .wrong {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 52, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(fill))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(tint, lineWidth: mark == .open ? 1 : 2))
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }

    private var tint: Color {
        switch mark {
        case .selected: return .accentColor
        case .wrong: return .red
        case .open, .matched: return Color(.separator)
        }
    }

    private var fill: Color {
        switch mark {
        case .selected: return Color.accentColor.opacity(0.15)
        case .wrong: return .red.opacity(0.15)
        case .open, .matched: return Color(.secondarySystemBackground)
        }
    }
}

/// The end of a round: its time and mistakes, Next round and Done.
private struct MatchResultView: View {
    let time: Duration
    let mistakes: Int
    let onNextRound: () -> Void
    let onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text("match.result.title")
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: 12) {
                    LabeledContent {
                        Text(time, format: .time(pattern: .minuteSecond))
                            .monospacedDigit()
                            .accessibilityIdentifier("match_result_time")
                    } label: {
                        Text("match.time")
                    }
                    LabeledContent {
                        Text(mistakes, format: .number)
                            .monospacedDigit()
                            .accessibilityIdentifier("match_result_mistakes")
                    } label: {
                        Text("match.result.mistakes")
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
                VStack(spacing: 12) {
                    Button(action: onNextRound) {
                        Text("match.nextRound")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("match_next_round")
                    Button(action: onDone) {
                        Text("match.done")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .accessibilityIdentifier("match_done")
                }
            }
            .padding()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("match_result")
    }
}
