// SettingsView.swift
// Settings view with UI language selection and dictionary management

import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @State private var showImporter = false

    var body: some View {
        NavigationStack {
            Form {
                // UI Language Section (NEW)
                uiLanguageSection

                // Dictionary Management Section (Refactored)
                dictionaryManagementSection

                // Learning Mode Section (stub)
                learningModeSection

                // Reading Mode Section (stub)
                readingModeSection

                // Support Section (stub)
                supportSection

                // Import Dictionary Section
                importDictionarySection

                // Supported Formats Section
                supportedFormatsSection

                // About Section (Existing, refined)
                aboutSection

                // Version Section
                versionSection
            }
            .navigationTitle("Settings")
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.json, .database, UTType(filenameExtension: "sqlite")].compactMap { $0 },
                allowsMultipleSelection: false
            ) { result in
                // Import functionality temporarily disabled
                print("Import attempted: \(result)")
            }
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
            if viewModel.sourceStats.isEmpty {
                Text("Loading…")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.sourceStats) { stat in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stat.displayName)
                                .font(.body)
                            Text("\(stat.count.formatted()) entries")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
        }
    }

    private var importDictionarySection: some View {
        Section("Import Dictionary") {
            Button {
                showImporter = true
            } label: {
                Label("Import File (.json or .sqlite)", systemImage: "square.and.arrow.down")
            }
            .disabled(viewModel.isImporting)

            if viewModel.isImporting {
                ProgressView("Importing...")
            }

            if let result = viewModel.importResult {
                Text(result)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var supportedFormatsSection: some View {
        Section("Supported Formats") {
            Text("**JSON** — array of objects with `word` and `definition` keys. Optional: `phonetic`, `pos`.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("**SQLite** — must contain an `entries` table with columns: word, definition, phonetic, pos, source.")
                .font(.caption)
                .foregroundStyle(.secondary)
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

    // MARK: - New Stub Sections

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
