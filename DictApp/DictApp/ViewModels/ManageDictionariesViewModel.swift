// ManageDictionariesViewModel.swift
// State for the Manage Dictionaries screen: file-import flow and (in the
// future) remote-download / delete affordances driven by issue #11.
//
// Pulled out of SettingsViewModel as part of issue #26 so that the
// settings screen only owns state it directly displays.

import Foundation
import Combine

@MainActor
final class ManageDictionariesViewModel: ObservableObject {
    @Published var isImporting = false
    @Published var importResult: String?

    /// Handles the result of `.fileImporter`. Dispatches to JSON or SQLite
    /// import based on file extension, copies/streams the picked file into
    /// the app database, and reports the row count (or error) via
    /// `importResult`. Compatible with SwiftUI's `fileImporter(onCompletion:)`.
    func handleImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task { await performImport(url: url) }
        case .failure(let error):
            importResult = error.localizedDescription
        }
    }

    private func performImport(url: URL) async {
        isImporting = true
        defer { isImporting = false }

        // Document-picker URLs are security-scoped — must bracket the read.
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

        let source = url.deletingPathExtension().lastPathComponent
        do {
            let count: Int
            switch url.pathExtension.lowercased() {
            case "json":
                count = try await DatabaseService.shared.importJSON(at: url, source: source)
            case "sqlite", "db":
                count = try await DatabaseService.shared.importSQLite(at: url, source: source)
            default:
                importResult = "Unsupported file type: .\(url.pathExtension)"
                return
            }
            importResult = "Imported \(count) entries from \(source)"
        } catch {
            importResult = error.localizedDescription
        }
    }
}
