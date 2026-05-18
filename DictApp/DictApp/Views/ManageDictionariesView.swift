// ManageDictionariesView.swift
// Settings → Dictionaries → "Manage Dictionaries" destination.
//
// Hosts the dictionary-content operations that don't belong on the top
// Settings screen: file import, supported-format reference, and (per the
// design doc) future remote-download / delete affordances from issue #11.

import SwiftUI
import UniformTypeIdentifiers

struct ManageDictionariesView: View {
    @StateObject private var viewModel = ManageDictionariesViewModel()
    @State private var showImporter = false

    var body: some View {
        Form {
            importDictionarySection
            supportedFormatsSection
        }
        .navigationTitle("Manage Dictionaries")
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.json, .database, UTType(filenameExtension: "sqlite")].compactMap { $0 },
            allowsMultipleSelection: false,
            onCompletion: viewModel.handleImport
        )
    }

    private var importDictionarySection: some View {
        Section("Import Dictionary") {
            Button {
                showImporter = true
            } label: {
                Label("Import File (.json or .sqlite)", systemImage: "square.and.arrow.down")
            }
            .disabled(viewModel.isImporting)
            .accessibilityIdentifier("import_dictionary_button")

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
}
