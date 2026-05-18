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

    /// Handles the result of `.fileImporter`. Today this is a stub matching
    /// the previous behavior in `SettingsView` — actual import wiring is
    /// tracked separately. The signature is intentionally compatible with
    /// SwiftUI's `fileImporter(onCompletion:)` closure.
    func handleImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            print("Import attempted: \(urls)")
        case .failure(let error):
            importResult = error.localizedDescription
        }
    }
}
