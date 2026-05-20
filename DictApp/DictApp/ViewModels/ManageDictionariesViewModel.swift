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

    private let localization: LocalizationManager

    /// `LocalizationManager.shared` is `@MainActor`-isolated, so passing it
    /// as a default-value expression would be evaluated in the caller's
    /// context — Swift 6 can't prove every caller is on the main actor.
    /// Accept `nil` and resolve `.shared` inside the `@MainActor`-isolated
    /// body instead.
    init(localization: LocalizationManager? = nil) {
        self.localization = localization ?? .shared
    }

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
                importResult = String(
                    localized: "manageDictionaries.import.result.unsupported \(url.pathExtension)",
                    locale: localization.currentLocale
                )
                return
            }
            // String Catalog handles plural variants for the current locale.
            importResult = String(
                localized: "manageDictionaries.import.result.success \(count) \(source)",
                locale: localization.currentLocale
            )
        } catch {
            importResult = error.localizedDescription
        }
    }
}
