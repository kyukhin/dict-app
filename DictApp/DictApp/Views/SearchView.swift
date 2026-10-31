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
                } else if vm.showsNoDictionariesHint {
                    // Issue #145: every chip is off, so nothing is searched.
                    ContentUnavailableView {
                        Label("search.noDictionaries.title", systemImage: "books.vertical")
                    } description: {
                        Text("search.noDictionaries.description")
                    }
                    .accessibilityIdentifier("search_no_dictionaries")
                } else if vm.results.isEmpty && !vm.isSearching {
                    ContentUnavailableView.search(text: vm.query)
                        .accessibilityIdentifier("search_no_results")
                } else {
                    ForEach(vm.results) { result in
                        // Issue #142: a lemma row opens and records the lemma's entry.
                        NavigationLink(value: result.entry) {
                            SourceStripeRow(source: result.entry.source) {
                                EntryRow(entry: result.entry, formMatch: result.formMatch)
                            }
                        }
                        .listRowInsets(EdgeInsets())   // stripe reaches the leading edge (#6 §4c)
                    }
                }
            }
            // Issue #145: the chips stay pinned under the search field while
            // the results scroll, with the keyboard up and with an empty field.
            .safeAreaInset(edge: .top, spacing: 0) {
                DictionaryChipsRow(selection: vm.selection)
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
                await vm.selection.loadIfNeeded()
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

// MARK: - Dictionary chips (Issue #145)

/// "All", then one chip per Dictionary Order pair, in that order. The chips
/// are the Settings switches: they render `DictionarySelection.pairs` and
/// change it only through its methods. One line that scrolls sideways; an
/// `HStack`, not a lazy stack, so every chip exists for VoiceOver and
/// XCUITest. Hidden until the pair list has loaded.
private struct DictionaryChipsRow: View {
    @ObservedObject var selection: DictionarySelection
    @Environment(\.locale) private var locale

    var body: some View {
        if selection.isLoaded {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        allChip
                        ForEach(selection.pairs) { item in
                            pairChip(item)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    // The container is the chips, inside the scroll view: on
                    // iOS 26 the scroll view's own frame reaches up under the
                    // navigation bar, and a container around it takes that
                    // frame, covering the title and the search field.
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(Text("search.chips.label"))
                    .accessibilityIdentifier("dictionary_chips")
                }
                Divider()
            }
            // Only behind the row: by default a style background extends into
            // the safe area, up over the navigation bar, and on iOS 26 it
            // covers the large title and the iPad tab strip.
            .background(.bar, ignoresSafeAreaEdges: [])
        }
    }

    /// Filled when every pair is on; a tap turns every pair on.
    private var allChip: some View {
        Button {
            selection.enableAll()
        } label: {
            Text("search.chips.all")
                .modifier(ChipShape(isOn: selection.allEnabled))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("search.chips.all.a11y"))
        .accessibilityAddTraits(selection.allEnabled ? .isSelected : [])
        .accessibilityIdentifier("dictionary_chip_all")
    }

    /// A switch that reads "English, on". Long press (secondary click on
    /// iPad) and the VoiceOver Actions rotor offer "Only this".
    private func pairChip(_ item: DictionaryItem) -> some View {
        let onlyThis = SettingsViewModel.localizedString("search.chips.onlyThis", locale: locale)
        return Toggle(item.displayName, isOn: Binding(
            get: { item.isEnabled },
            set: { selection.setEnabled($0, pair: item.id) }
        ))
        .toggleStyle(ChipToggleStyle())
        .contentShape(.contextMenuPreview, Capsule())
        .contextMenu {
            Button {
                selection.enableOnly(pair: item.id)
            } label: {
                Text(verbatim: onlyThis)
            }
            .accessibilityIdentifier("dictionary_chip_only_this")
        }
        .accessibilityAction(named: Text(verbatim: onlyThis)) {
            selection.enableOnly(pair: item.id)
        }
        .accessibilityIdentifier("dictionary_chip_\(item.id)")
    }
}

/// A capsule filled with the tint when on, outlined when off. The `Toggle`
/// keeps its switch semantics; the style only draws it.
private struct ChipToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            configuration.label
                .modifier(ChipShape(isOn: configuration.isOn))
        }
        .buttonStyle(.plain)
    }
}

/// The chip look shared by "All" and the pair chips. Labels never wrap or
/// truncate; with large Dynamic Type the row grows taller.
private struct ChipShape: ViewModifier {
    let isOn: Bool

    func body(content: Content) -> some View {
        content
            .font(.subheadline.weight(.medium))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .background {
                Capsule().fill(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear))
            }
            .overlay {
                Capsule().strokeBorder(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary), lineWidth: 1)
            }
            .contentShape(Capsule())
            .hoverEffect()
    }
}

// MARK: - Row

/// A single search result row showing word, source badge, and definition snippet.
/// A lemma row also shows its form caption under the headword (Issue #142).
private struct EntryRow: View {
    let entry: DictionaryEntry
    var formMatch: FormMatch?
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
            if let formMatch {
                // "aorist 1sg of γράφω"; VoiceOver reads the person as the
                // Greek pronoun, "aorist, εγώ of γράφω".
                Text(verbatim: FormCaption.text(for: formMatch, locale: locale))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text(verbatim: FormCaption.accessibilityText(for: formMatch, locale: locale)))
                    .accessibilityIdentifier("form_caption")
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
