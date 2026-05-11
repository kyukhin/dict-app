// DictionaryManagerView.swift
// Per-dictionary breakdown with tappable rows, file importer, and About info.

import SwiftUI
import UniformTypeIdentifiers

struct DictionaryManagerView: View {
    @State private var showImporter = false
    @State private var importResult: String?
    @State private var sourceStats: [SourceStat] = []
    @State private var totalCount: Int = 0
    @State private var isImporting = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Dictionaries") {
                    if sourceStats.isEmpty {
                        Text("No dictionaries loaded.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(sourceStats) { stat in
                            NavigationLink(value: stat.source) {
                                LabeledContent {
                                    Text(stat.count.formatted())
                                        .monospacedDigit()
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "book.closed")
                                            .foregroundStyle(.tint)
                                        Text(stat.displayName)
                                    }
                                }
                            }
                        }
                        LabeledContent {
                            Text(totalCount.formatted())
                                .monospacedDigit()
                                .bold()
                        } label: {
                            Text("Total")
                                .bold()
                        }
                    }
                }

                Section("Import Dictionary") {
                    Button {
                        showImporter = true
                    } label: {
                        Label("Import File (.json or .sqlite)", systemImage: "square.and.arrow.down")
                    }
                    .disabled(isImporting)

                    if isImporting {
                        ProgressView("Importing...")
                    }

                    if let result = importResult {
                        Text(result)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Supported Formats") {
                    Text("**JSON** — array of objects with `word` and `definition` keys. Optional: `phonetic`, `pos`.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("**SQLite** — must contain an `entries` table with columns: word, definition, phonetic, pos, source.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

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

                Section {
                    LabeledContent("Version", value: "1.0")
                    Text("This app uses data from public-domain and openly licensed dictionary projects. Each dictionary retains its original license.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Manage")
            .navigationDestination(for: String.self) { source in
                DictionaryDetailView(source: source)
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.json, .database, UTType(filenameExtension: "sqlite")].compactMap { $0 },
                allowsMultipleSelection: false
            ) { result in
                Task {
                    await handleImport(result)
                }
            }
            .task {
                await loadStats()
            }
        }
    }

    private func loadStats() async {
        sourceStats = (try? await DatabaseService.shared.fetchSourceStats()) ?? []
        totalCount = sourceStats.reduce(0) { $0 + $1.count }
    }

    private func handleImport(_ result: Result<[URL], Error>) async {
        isImporting = true
        defer { isImporting = false }

        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else {
                importResult = "Could not access the selected file."
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            let ext = url.pathExtension.lowercased()
            let source = url.deletingPathExtension().lastPathComponent

            do {
                let count: Int
                if ext == "json" {
                    count = try await DatabaseService.shared.importJSON(at: url, source: source)
                } else {
                    count = try await DatabaseService.shared.importSQLite(at: url, source: source)
                }
                importResult = "Imported \(count) entries from \(url.lastPathComponent)."
                await loadStats()
            } catch {
                importResult = "Import failed: \(error.localizedDescription)"
            }

        case .failure(let error):
            importResult = "File picker error: \(error.localizedDescription)"
        }
    }
}
