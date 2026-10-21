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
                            ForEach(vm.recentWords) { item in
                                NavigationLink(value: item.word) {
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
            // Issue #111: progress of the background unpack, just above the
            // tab bar (above the keyboard while typing). At the bottom, its
            // appearing and disappearing never moves the result rows.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                UnpackProgressBar(fraction: vm.unpackFraction)
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
            .navigationDestination(for: String.self) { word in
                HistoryWordDestination(word: word)
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

// MARK: - Unpack progress (Issue #111)

/// "Preparing dictionaries… 35%" on the bar material while the bundled
/// dictionaries are unpacked; nothing when `fraction` is `nil`. The percent
/// is formatted with the in-app locale from the environment (Arabic digits,
/// "35 %" in Spanish), so the catalog string carries no number.
private struct UnpackProgressBar: View {
    let fraction: Double?

    var body: some View {
        ZStack {
            if let fraction {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("search.unpacking.title")
                    Text(fraction, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
                .padding(.horizontal)
                .frame(maxWidth: .infinity)
                .background(.bar)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("search.unpacking.title"))
                .accessibilityValue(Text(fraction, format: .percent.precision(.fractionLength(0))))
                .accessibilityAddTraits(.updatesFrequently)
                .accessibilityIdentifier("dictionary_unpack_progress")
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: fraction == nil)
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

// MARK: - History word destination

/// Looks up a word from history and shows its definition.
private struct HistoryWordDestination: View {
    let word: String
    @State private var entry: DictionaryEntry?
    @State private var loaded = false

    var body: some View {
        Group {
            if let entry {
                DefinitionView(entry: entry)
            } else if loaded {
                ContentUnavailableView(
                    "search.notFound.title",
                    systemImage: "magnifyingglass",
                    description: Text("search.notFound.description \(word)")
                )
            } else {
                ProgressView()
            }
        }
        .task {
            entry = try? await DatabaseService.shared.lookup(word: word)
            if entry == nil {
                let results = (try? await DatabaseService.shared.search(query: word, limit: 1)) ?? []
                entry = results.first
            }
            loaded = true
        }
    }
}
