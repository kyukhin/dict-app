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
        .navigationTitle("manageDictionaries.title")
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.json, .database, UTType(filenameExtension: "sqlite")].compactMap { $0 },
            allowsMultipleSelection: false,
            onCompletion: viewModel.handleImport
        )
    }

    private var importDictionarySection: some View {
        Section("manageDictionaries.import.section") {
            Button {
                handleImportTap()
            } label: {
                Label("manageDictionaries.import.button", systemImage: "square.and.arrow.down")
            }
            .disabled(viewModel.isImporting)
            .accessibilityIdentifier("import_dictionary_button")

            if viewModel.isImporting {
                ProgressView("manageDictionaries.import.inProgress")
            }

            if let result = viewModel.importResult {
                // Already a localized string from the view-model (built via
                // the String Catalog so plurals and interpolation are
                // already applied for the active locale).
                Text(verbatim: result)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("import_result_message")
            }
        }
    }

    private var supportedFormatsSection: some View {
        Section("manageDictionaries.formats.section") {
            Text("manageDictionaries.formats.json")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("manageDictionaries.formats.sqlite")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Routes the import-button tap. Normally presents the system file
    /// picker; under the UI-test launch arg `-importFixtureViaCallback:json`
    /// (or `:sqlite`) it short-circuits to the bundled fixture so end-to-end
    /// tests can exercise the real import-and-search path without driving
    /// `UIDocumentPickerViewController` (which is unreliable in CI).
    private func handleImportTap() {
        let args = CommandLine.arguments
        if let arg = args.first(where: { $0.hasPrefix("-importFixtureViaCallback:") }) {
            let ext = String(arg.dropFirst("-importFixtureViaCallback:".count))
            if let url = Bundle.main.url(forResource: "test_import_fixture", withExtension: ext) {
                viewModel.handleImport(result: .success([url]))
                return
            }
        }
        showImporter = true
    }
}
