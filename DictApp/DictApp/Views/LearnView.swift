// BookmarksView.swift

import SwiftUI

struct BookmarksView: View {
    @StateObject private var vm = BookmarksViewModel()
    @Environment(\.locale) private var locale

    var body: some View {
        NavigationStack {
            Group {
                if vm.rows.isEmpty {
                    ContentUnavailableView(
                        "bookmarks.empty.title",
                        systemImage: "bookmark",
                        description: Text("bookmarks.empty.description")
                    )
                } else {
                    List {
                        ForEach(vm.rows) { row in
                            if let entry = row.entry {
                                NavigationLink(value: entry) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(entry.word)
                                            .font(.headline)
                                        Text(strippedSnippet(entry.definition))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            } else {
                                // #245: its pack is not installed; the row
                                // opens the "not downloaded" view.
                                NavigationLink {
                                    EntryDestination(key: row.key)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(row.key.word)
                                            .font(.headline)
                                        if let pack = NotDownloaded.pack(ofSource: row.key.source, catalog: .shared) {
                                            Text(verbatim: PackTexts.notDownloadedSearch(pack, locale: locale))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                }
                            }
                        }
                        .onDelete { offsets in
                            let removed = offsets.map { vm.rows[$0].key }
                            Task {
                                for key in removed {
                                    await vm.remove(key)
                                }
                            }
                        }
                    }
                    .accessibilityIdentifier("bookmarks_list")
                }
            }
            .navigationTitle("bookmarks.title")
            .navigationDestination(for: DictionaryEntry.self) { entry in
                DefinitionView(entry: entry)
            }
            .task {
                await vm.load()
            }
        }
    }

    private func strippedSnippet(_ text: String) -> String {
        String(text.prefix(100))
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}
