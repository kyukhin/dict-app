// SettingsView.swift
// Settings view with UI language selection, dictionary management and the
// Learning section with its Languages screen (0131, #162).

import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @StateObject private var learningVM = LearningSettingsViewModel()
    @StateObject private var supportVM = SupportViewModel()
    @Environment(\.openURL) private var openURL
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            Form {
                uiLanguageSection
                sortingSection
                dictionaryManagementSection
                LearningSettingsSection(vm: learningVM)
                supportSection
                aboutSection
                versionSection
            }
            .navigationTitle("settings.title")
            // 0131, #162: the learning values, which the Learn tab may have
            // changed, and the notification permission, which iOS Settings may have.
            .task {
                await learningVM.load(locale: locale)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await learningVM.refreshAuthorization() }
                }
            }
            .sheet(isPresented: $supportVM.isPresentingMail) {
                MailComposeView(
                    recipient: SupportService.shared.recipient,
                    subject: SupportService.shared.subject(),
                    body: SupportService.shared.bodyTemplate(),
                    onFinish: supportVM.handleMailDidFinish
                )
            }
            .alert(item: $supportVM.mailUnavailableAlert) { reason in
                Alert(
                    title: Text("support.mailUnavailable.title"),
                    message: Text(reason.localizedBodyKey),
                    primaryButton: .default(
                        Text("support.mailUnavailable.copyAddress"),
                        action: { UIPasteboard.general.string = SupportService.shared.recipient }
                    ),
                    secondaryButton: .cancel()
                )
            }
        }
    }

    private var uiLanguageSection: some View {
        Section("settings.language.section") {
            // `Picker(.navigationLink)` renders empty rows in the pushed list
            // on iPad iOS 17.5 regardless of whether the row content is a
            // single Text, an HStack, or a Text-concatenation. Replace the
            // picker with an explicit `NavigationLink` to a custom selector
            // view so we control the row rendering directly.
            NavigationLink {
                UILanguagePickerView(
                    languages: viewModel.availableUILanguages,
                    selection: viewModel.selectedUILanguage,
                    onSelect: { viewModel.updateUILanguage($0) }
                )
            } label: {
                LabeledContent {
                    Text(verbatim: viewModel.selectedUILanguage.nativeName)
                } label: {
                    Text("settings.language.picker")
                }
            }
            .accessibilityIdentifier("ui_language_link")
        }
    }

    /// Result-sorting picker (Issue #6) — placed between the language and
    /// dictionaries sections so the picker and the reorderable list read as a
    /// unit. `.relevance` is the default.
    private var sortingSection: some View {
        Section("settings.sorting.section") {
            Picker("settings.sorting.mode", selection: $viewModel.resultSortMode) {
                Text("settings.sorting.relevance").tag(ResultSortMode.relevance)
                Text("settings.sorting.preferred").tag(ResultSortMode.preferredDictionary)
            }
            .accessibilityIdentifier("result_sort_mode_picker")
        }
    }

    /// Dictionary Order (Issue #6), Languages (#243: download and remove
    /// language packs) and Manage Dictionaries (import + per-dict detail).
    private var dictionaryManagementSection: some View {
        Section("settings.dictionaries.section") {
            NavigationLink {
                DictionaryOrderView(vm: viewModel)
            } label: {
                Label("settings.dictionaryOrder.title", systemImage: "arrow.up.arrow.down")
            }
            .accessibilityIdentifier("dictionary_order_link")

            NavigationLink {
                LanguagesView()
            } label: {
                Label("languages.title", systemImage: "globe")
            }
            .accessibilityIdentifier("dictionary_languages_link")

            NavigationLink {
                ManageDictionariesView()
            } label: {
                Label("settings.manageDictionaries", systemImage: "books.vertical")
            }
            .accessibilityIdentifier("manage_dictionaries_link")
        }
    }

    private var aboutSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "text.book.closed.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading) {
                        // App name — not translated.
                        Text(verbatim: "LibreDict")
                            .font(.title2.bold())
                        Text("about.tagline")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Text("about.description")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        } header: {
            Text("about.section")
        }
    }

    private var supportSection: some View {
        Section("settings.support.section") {
            Button("settings.support.reportBug") {
                supportVM.startReportFlow(openURL: openURL)
            }
            .accessibilityIdentifier("report_bug_button")
            // Issue #81: user-initiated "Write a review" deep link, alongside the
            // other outward-facing Support actions. Independent of #12's
            // heuristic-driven prompt.
            if let reviewURL = AppConstants.writeReviewURL {
                Link(destination: reviewURL) {
                    Label("settings.writeReview", systemImage: "star")
                }
                .accessibilityIdentifier("settings_write_review_link")
            }
            NavigationLink("settings.support.credits") {
                CreditsView()
            }
            .accessibilityIdentifier("settings_credits_link")
        }
    }

    private var versionSection: some View {
        Section {
            LabeledContent("settings.version", value: AppVersion.current.displayString)
                .accessibilityIdentifier("version_value")
            Text("settings.licenseNote")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

/// Push-style language selector. Replaces the previous
/// `Picker(.pickerStyle(.navigationLink))` which renders empty rows on
/// iPad iOS 17.5. A plain `List` of `Button`s gives us full control over
/// the row layout (localized name + native name + checkmark).
private struct UILanguagePickerView: View {
    let languages: [UILanguage]
    let selection: UILanguage
    let onSelect: (UILanguage) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(languages) { language in
            Button {
                // A different language rebuilds the whole tree (`.id(code)` at
                // the App root), which discards this pushed screen. Popping it
                // in the same tap makes UIKit free the old tab controller while
                // the pop is in flight: EXC_BAD_ACCESS in
                // `-[UIViewController dealloc]` on iOS 17. Pop only when nothing
                // is rebuilt.
                if language == selection {
                    dismiss()
                } else {
                    onSelect(language)
                }
            } label: {
                HStack {
                    Text(LocalizedStringKey(language.displayKey))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(verbatim: language.nativeName)
                        .foregroundStyle(.secondary)
                    if language == selection {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                            .padding(.leading, 4)
                    }
                }
            }
            .accessibilityIdentifier("ui_language_option_\(language.code)")
        }
        .navigationTitle("settings.language.picker")
    }
}

// MARK: - Learning (0131, #162)

/// The Learning section: the learned languages, new words per day, E3's
/// New words from (0130, #154), the daily goal, the new words order, typed
/// answers, sounds, haptics and the daily reminder.
struct LearningSettingsSection: View {
    @ObservedObject var vm: LearningSettingsViewModel
    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL

    var body: some View {
        Section {
            NavigationLink {
                LearningLanguagesView(vm: vm)
            } label: {
                // An empty value would blank the row's accessibility label.
                let names = vm.learnedNames(locale: locale)
                if names.isEmpty {
                    Text("settings.learning.languages")
                } else {
                    LabeledContent("settings.learning.languages") {
                        Text(names)
                    }
                }
            }
            .accessibilityIdentifier("settings_learning_languages")

            Stepper(value: $vm.newPerDay, in: SettingsService.learningNewPerDayRange) {
                LabeledContent("settings.learning.newPerDay") {
                    Text(vm.newPerDay, format: .number)
                }
            }
            .accessibilityIdentifier("settings_learning_new_per_day")

            NavigationLink {
                NewWordsFromView()
            } label: {
                Text("newWordsFrom.title")
            }
            .accessibilityIdentifier("settings_learning_new_words_from")

            Stepper(value: $vm.dailyGoal, in: SettingsService.learningDailyGoalRange, step: 5) {
                LabeledContent("settings.learning.goal") {
                    Text("settings.learning.goal.value \(vm.dailyGoal)")
                }
            }
            .accessibilityIdentifier("settings_learning_goal")

            Picker("settings.learning.order", selection: $vm.newOrder) {
                Text("settings.learning.order.frequency").tag(NewWordOrder.frequency)
                Text("settings.learning.order.random").tag(NewWordOrder.random)
            }
            .accessibilityIdentifier("settings_learning_order")

            Picker("settings.learning.answerMode", selection: $vm.answerMode) {
                Text("settings.learning.answerMode.strict").tag(AnswerMode.strict)
                Text("settings.learning.answerMode.lenient").tag(AnswerMode.lenient)
                Text("settings.learning.answerMode.choice").tag(AnswerMode.choice)
            }
            .accessibilityIdentifier("settings_learning_answer_mode")

            Toggle("settings.learning.sounds", isOn: $vm.sounds)
                .accessibilityIdentifier("settings_learning_sounds")
            if vm.supportsHaptics {
                Toggle("settings.learning.haptics", isOn: $vm.haptics)
                    .accessibilityIdentifier("settings_learning_haptics")
            }

            Toggle("settings.learning.reminder", isOn: Binding(
                get: { vm.reminderOn },
                set: { on in Task { await vm.setReminder(on) } }
            ))
            .accessibilityIdentifier("settings_learning_reminder")
            if vm.reminderOn {
                DatePicker("settings.learning.reminder.time", selection: Binding(
                    get: { LearningSettingsViewModel.date(ofMinutes: vm.reminderTime) },
                    set: { date in Task { await vm.setReminderTime(LearningSettingsViewModel.minutes(of: date)) } }
                ), displayedComponents: .hourAndMinute)
                .accessibilityIdentifier("settings_learning_reminder_time")
            }
        } header: {
            Text("settings.learning.section")
        } footer: {
            if vm.notificationsDenied {
                VStack(alignment: .leading, spacing: 6) {
                    Text("settings.learning.reminder.denied")
                    Button("settings.learning.reminder.openSettings") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                            openURL(url)
                        }
                    }
                    .font(.footnote)
                    .accessibilityIdentifier("settings_learning_reminder_open_settings")
                }
            }
        }
    }
}

/// Settings → Learning → Languages: each learned language with its via,
/// as a menu when it has two or more pairs, a limited pair's warning, and
/// Stop learning; then "Add a language", the picker without the learned
/// languages.
struct LearningLanguagesView: View {
    @ObservedObject var vm: LearningSettingsViewModel
    @Environment(\.locale) private var locale
    /// The language "Stop learning %@?" asks about.
    @State private var stopping: String?

    var body: some View {
        List {
            ForEach(vm.languages) { row in
                Section {
                    viaRow(row)
                    if let pair = row.pair, pair.isLimited {
                        LimitedPairNote(pair: pair)
                            .accessibilityIdentifier("learning_language_limited_\(row.lang)")
                    }
                    Button("settings.learning.stopLanguage", role: .destructive) {
                        stopping = row.lang
                    }
                    .accessibilityIdentifier("learning_language_stop_\(row.lang)")
                }
            }
            Section {
                // Kept when every language is learned, only disabled, so
                // the last one added does not remove the link it came from.
                NavigationLink {
                    AddLearningLanguageView(vm: vm)
                } label: {
                    Label("settings.learning.addLanguage", systemImage: "plus")
                }
                .disabled(vm.addable.isEmpty)
                .accessibilityIdentifier("learning_language_add")
            }
        }
        .navigationTitle("settings.learning.languages")
        .accessibilityIdentifier("settings_learning_languages_view")
        .alert(Text(stopTitle),
               isPresented: Binding(get: { stopping != nil }, set: { if !$0 { stopping = nil } }),
               presenting: stopping) { lang in
            Button("settings.learning.stopLanguage", role: .destructive) {
                Task { await vm.stop(lang, locale: locale) }
            }
            Button("common.cancel", role: .cancel) {}
        } message: { _ in
            Text("settings.learning.stopLanguage.message")
        }
        .task {
            await vm.load(locale: locale)
        }
    }

    /// "Greek · via English": a menu of the vias with two or more pairs,
    /// else the via as text. A menu item is a toggle, which shows the
    /// check mark and, unlike a menu picker's item, a limited pair's
    /// warning under it.
    @ViewBuilder
    private func viaRow(_ row: LearningSettingsViewModel.LanguageRow) -> some View {
        let name = LearnViewModel.languageName(row.lang, locale: locale)
        if row.vias.count > 1, let pair = row.pair {
            LabeledContent {
                Menu {
                    ForEach(row.vias, id: \.via) { option in
                        Toggle(isOn: Binding(
                            get: { option.via == pair.via },
                            set: { on in if on { Task { await vm.setVia(option.via, for: row.lang, locale: locale) } } }
                        )) {
                            Text(viaText(option.via))
                            if let warning = LearnViewModel.limitedWarning(option, locale: locale) {
                                Text(warning)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(viaText(pair.via))
                        Image(systemName: "chevron.up.chevron.down")
                            .imageScale(.small)
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityIdentifier("learning_language_via_\(row.lang)")
            } label: {
                Text(name)
                    .accessibilityIdentifier("learning_language_row_\(row.lang)")
            }
        } else {
            LabeledContent {
                if let pair = row.pair {
                    Text(viaText(pair.via))
                        .accessibilityIdentifier("learning_language_via_\(row.lang)")
                }
            } label: {
                Text(name)
                    .accessibilityIdentifier("learning_language_row_\(row.lang)")
            }
        }
    }

    /// "via English" (`learn.viaLanguage`).
    private func viaText(_ via: String) -> String {
        String(format: SettingsViewModel.localizedString("learn.viaLanguage %@", locale: locale),
               LearnViewModel.languageNameInSentence(via, locale: locale))
    }

    /// "Stop learning Greek?"
    private var stopTitle: String {
        guard let stopping else { return "" }
        return String(format: SettingsViewModel.localizedString("settings.learning.stopLanguage.title %@", locale: locale),
                      LearnViewModel.languageNameInSentence(stopping, locale: locale))
    }
}

/// "Add a language": the Learn tab's picker without the learned
/// languages. Choosing a pair learns it and returns to Languages.
private struct AddLearningLanguageView: View {
    @ObservedObject var vm: LearningSettingsViewModel
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        LanguagePickerView(pairs: vm.addable, withLists: vm.languagesWithLists, downloadSizes: vm.downloadSizes) { pair in
            Task {
                await vm.add(pair, locale: locale)
                dismiss()
            }
        }
        .navigationTitle("settings.learning.addLanguage")
        .navigationBarTitleDisplayMode(.inline)
    }
}
