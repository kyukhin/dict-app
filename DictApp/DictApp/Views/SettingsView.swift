// SettingsView.swift
// Settings view with UI language selection and dictionary management

import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()

    var body: some View {
        NavigationStack {
            Form {
                // UI Language Section
                uiLanguageSection

                // Dictionary Management Section
                dictionaryManagementSection

                // Learning Mode Section (stub)
                learningModeSection

                // Reading Mode Section (stub)
                readingModeSection

                // Support Section (stub)
                supportSection

                // About Section
                aboutSection

                // Version Section
                versionSection
            }
            .navigationTitle("Settings")
        }
    }

    private var uiLanguageSection: some View {
        Section("Interface Language") {
            Picker("Language", selection: Binding(
                get: { viewModel.selectedUILanguage },
                set: { viewModel.updateUILanguage($0) }
            )) {
                ForEach(viewModel.availableUILanguages) { language in
                    HStack {
                        Text(language.displayName)
                        Spacer()
                        Text(language.nativeName)
                            .foregroundStyle(.secondary)
                    }
                    .tag(language)
                }
            }
            .pickerStyle(.navigationLink)
        }
    }

    private var dictionaryManagementSection: some View {
        Section("Dictionaries") {
            if viewModel.dictionaries.isEmpty {
                Text("Loading…")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.dictionaries) { dict in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(dict.displayName)
                                .font(.body)
                            Text("\(dict.count.formatted()) entries")
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
                Label("Manage Dictionaries", systemImage: "books.vertical")
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
                        Text("LibreDict")
                            .font(.title2.bold())
                        Text("Offline Dictionary")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Text("An open-source, offline-first dictionary application. All lookups are performed locally using SQLite FTS5 full-text search. No internet connection required.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        } header: {
            Text("About")
        }
    }

    // MARK: - Stub Sections

    private var learningModeSection: some View {
        Section("Learning Mode") {
            Label("Coming Soon", systemImage: "brain")
                .foregroundStyle(.secondary)
        }
    }

    private var readingModeSection: some View {
        Section("Reading Mode") {
            Label("Coming Soon", systemImage: "book")
                .foregroundStyle(.secondary)
        }
    }

    private var supportSection: some View {
        Section("Support") {
            Button("Report a Bug") { }
                .disabled(true)
            NavigationLink("Credits") {
                CreditsView()
            }
        }
    }

    private var versionSection: some View {
        Section {
            LabeledContent("Version", value: "1.0")
            Text("This app uses data from public-domain and openly licensed dictionary projects. Each dictionary retains its original license.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
