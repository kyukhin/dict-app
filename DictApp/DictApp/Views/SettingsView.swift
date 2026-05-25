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
            Picker(selection: Binding(
                get: { viewModel.selectedUILanguage },
                set: { viewModel.updateUILanguage($0) }
            )) {
                ForEach(viewModel.availableUILanguages) { language in
                    HStack {
                        // `displayKey` resolves to the language name in the
                        // *current* UI language; `nativeName` stays in the
                        // language's own script.
                        Text(LocalizedStringKey(language.displayKey))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer()
                        Text(language.nativeName)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .tag(language)
                }
            } label: {
                Text("settings.language.picker")
            }
            .pickerStyle(.navigationLink)
        }
    }

    private var dictionaryManagementSection: some View {
        Section("settings.dictionaries.section") {
            if viewModel.dictionaries.isEmpty {
                Text("common.loading")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.dictionaries) { dict in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(dict.displayName)
                                .font(.body)
                            // Plural-aware key resolved by the String Catalog
                            // via CLDR rules for the active locale.
                            Text("dictionary.entries.count \(dict.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle(isOn: Binding(
                            get: { dict.isEnabled },
                            set: { _ in viewModel.toggleDictionary(source: dict.source) }
                        )) { EmptyView() }
                        .labelsHidden()
                        .accessibilityIdentifier("dictionary_toggle_\(dict.source)")
                    }
                }
            }

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
            NavigationLink("settings.support.credits") {
                CreditsView()
            }
        }
    }

    private var versionSection: some View {
        Section {
            LabeledContent("settings.version", value: "1.0")
            Text("settings.licenseNote")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
