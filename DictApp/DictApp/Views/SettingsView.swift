// SettingsView.swift
// Settings view with UI language selection and dictionary management

import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @StateObject private var supportVM = SupportViewModel()
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            Form {
                uiLanguageSection
                sortingSection
                dictionaryManagementSection
                learningModeSection
                readingModeSection
                supportSection
                aboutSection
                versionSection
            }
            .navigationTitle("settings.title")
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

    /// Two links (Issue #6): the new combined order+enable list, and the
    /// unchanged Manage Dictionaries (import + per-dict detail).
    private var dictionaryManagementSection: some View {
        Section("settings.dictionaries.section") {
            NavigationLink {
                DictionaryOrderView(vm: viewModel)
            } label: {
                Label("settings.dictionaryOrder.title", systemImage: "arrow.up.arrow.down")
            }
            .accessibilityIdentifier("dictionary_order_link")

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

    // MARK: - Stub Sections

    private var learningModeSection: some View {
        Section("settings.learningMode.section") {
            Label("common.comingSoon", systemImage: "brain")
                .foregroundStyle(.secondary)
        }
    }

    private var readingModeSection: some View {
        Section("settings.readingMode.section") {
            Label("common.comingSoon", systemImage: "book")
                .foregroundStyle(.secondary)
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
                onSelect(language)
                dismiss()
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
