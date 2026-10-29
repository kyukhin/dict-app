// SearchView.swift
// Main search interface with search-as-you-type.

import SwiftUI

struct SearchView: View {
    @StateObject private var vm = SearchViewModel()

    var body: some View {
        NavigationStack {
            List {
                if vm.query.isEmpty {
                    if !vm.recentWords.isEmpty {
                        Section("search.recent.title") {
                            // Issue #138: a Recent word reopens its stored source, as in History.
                            ForEach(vm.recentWords) { item in
                                NavigationLink(value: item) {
                                    Label(item.word, systemImage: "clock")
                                        .font(.body)
                                }
                            }
                        }
                    }
                } else if vm.results.isEmpty && !vm.isSearching {
                    ContentUnavailableView.search(text: vm.query)
                        .accessibilityIdentifier("search_no_results")
                } else {
                    ForEach(vm.results) { entry in
                        NavigationLink(value: entry) {
                            SourceStripeRow(source: entry.source) {
                                EntryRow(entry: entry)
                            }
                        }
                        .listRowInsets(EdgeInsets())   // stripe reaches the leading edge (#6 §4c)
                    }
                }
            }
            .navigationTitle("search.title")
            .modifier(SearchFieldPlacement(text: $vm.query))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ReadingModeToolbarButton()
                }
            }
            .onChange(of: vm.query) {
                vm.onQueryChanged()
            }
            .overlay {
                if vm.isSearching && !vm.query.isEmpty {
                    ProgressView()
                }
            }
            .navigationDestination(for: DictionaryEntry.self) { entry in
                DefinitionView(entry: entry)
            }
            .navigationDestination(for: HistoryItem.self) { item in
                HistoryDestination(item: item)
            }
            .task {
                await vm.loadRecent()
            }
            .onAppear {
                // Re-run the current query so a sort-mode / dictionary-order
                // change made in the Settings tab is reflected on return without
                // retyping (#6 §3d). No-ops when the field is empty, so it does
                // not fire on initial load.
                vm.refreshIfNeeded()
            }
        }
    }
}

// MARK: - Search field placement (Issue #120)

/// `.searchable` for the Search root. On iPad with iOS 26 the field sits in a
/// drawer under the title at all times and keeps the navigation bar while a
/// query is in it; everywhere else it is today's default placement. The gate
/// is the only difference between platforms.
///
/// Why iPad iOS 26 needs it: the floating tab strip lives in the navigation
/// bar there, and with the default placement two system behaviours each hide
/// it for as long as the field holds text: the integrated field expands over
/// the strip's row, and the search controller hides the bar while presented.
/// `.navigationBarDrawer(displayMode: .always)` fixes the first,
/// `.avoidHidingContent` the second; neither is enough on its own. Gated by
/// device, not width, so Split View resizes never move an active search.
private struct SearchFieldPlacement: ViewModifier {
    @Binding var text: String

    func body(content: Content) -> some View {
        if #available(iOS 26, *), UIDevice.current.userInterfaceIdiom == .pad {
            content
                .searchable(text: $text,
                            placement: .navigationBarDrawer(displayMode: .always),
                            prompt: Text("search.prompt"))
                .searchPresentationToolbarBehavior(.avoidHidingContent)
        } else {
            content.searchable(text: $text, prompt: Text("search.prompt"))
        }
    }
}

// MARK: - Row

/// A single search result row showing word, source badge, and definition snippet.
private struct EntryRow: View {
    let entry: DictionaryEntry
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.word)
                    .font(.headline)
                Text(entry.sourceLabel)
                    .font(.system(size: 9, weight: .medium))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.quaternary)
                    .clipShape(Capsule())
                    // Issue #87: VoiceOver reads "Greek to English, FreeDict",
                    // not the abbreviations; a custom import keeps its text.
                    .accessibilityLabel(badgeAccessibilityLabel)
                    .accessibilityIdentifier("source_badge_\(entry.source)")
            }
            if !entry.phonetic.isEmpty {
                Text(entry.phonetic)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if !entry.pos.isEmpty {
                Text(entry.pos)
                    .font(.caption2)
                    .foregroundStyle(.tint)
            }
            Text(definitionSnippet)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
    }

    private var badgeAccessibilityLabel: String {
        SettingsViewModel.badgeAccessibilityLabel(forSource: entry.source, locale: locale) ?? entry.sourceLabel
    }

    private var definitionSnippet: String {
        String(entry.definition.prefix(200))
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}
