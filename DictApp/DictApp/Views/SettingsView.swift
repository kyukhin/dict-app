// SettingsView.swift
// Settings view with UI language selection and dictionary management

import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()

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
            Button("settings.support.reportBug") { }
                .disabled(true)
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
