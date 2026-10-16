// DictionaryOrderView.swift
// Combined enable/disable + drag-to-reorder dictionary list (Issue #6), pushed
// from Settings → Dictionaries.

import SwiftUI

/// One combined list (drag handle leading, toggle trailing) on a dedicated
/// pushed screen. A dedicated `List` scoped to active `editMode` shows always-on
/// drag grips cleanly; forcing the whole Settings `Form` into edit mode would
/// instead put delete-circles on every row (§1b). Disabled dictionaries stay in
/// the order (greyed, still draggable).
///
/// Rows are language pairs (Issue #92): one row, one toggle and one drag slot
/// per pair, e.g. "Spanish – English" covering both translation directions.
/// The caption is the pair's summed entry count; provider / direction /
/// license live behind the (i) button (#91, `dictionary_info_<pairKey>`),
/// which pushes `DictionaryDetailView` onto the Settings `NavigationStack`.
///
/// The list reloads each time the screen appears (Issue #105), so a dictionary
/// imported on Manage Dictionaries shows up without a relaunch. The view only
/// triggers the reload; `SettingsViewModel.loadDictionaries()` owns the logic.
struct DictionaryOrderView: View {
    @ObservedObject var vm: SettingsViewModel
    @State private var infoItem: DictionaryItem?
    @Environment(\.locale) private var locale

    var body: some View {
        List {
            ForEach(vm.orderedDictionaries) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.displayName)
                            .font(.body)
                            // Row identifier lives on the leading label, NOT the
                            // HStack: a container-level identifier propagates onto
                            // the row's switch and shadows the Toggle's own
                            // `dictionary_toggle_*` id (Issue #6). The label is a
                            // stable drag handle and frame anchor for the order list.
                            .accessibilityIdentifier("dictionary_order_row_\(item.id)")
                        Text("dictionary.entries.count \(item.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    // Borderless: a default-style Button in a List row makes the
                    // whole row its hit target; borderless confines it to the
                    // icon so title, toggle and drag grip keep their behaviour.
                    Button { infoItem = item } label: {
                        Image(systemName: "info.circle")
                            .frame(width: 32, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(SettingsViewModel.infoButtonLabel(for: item.displayName, locale: locale))
                    .accessibilityIdentifier("dictionary_info_\(item.id)")
                    Toggle(isOn: vm.binding(for: item.id)) { EmptyView() }
                        .labelsHidden()
                        .accessibilityIdentifier("dictionary_toggle_\(item.id)")
                }
            }
            .onMove { from, to in vm.movePair(from: from, to: to) }
        }
        // On the List, never inside the lazy ForEach.
        .navigationDestination(item: $infoItem) { item in
            DictionaryDetailView(pair: item.pair, title: item.displayName)
                .environment(\.editMode, .constant(.inactive))   // don't inherit the order list's forced edit mode
        }
        // #105: pick up imports / removals made elsewhere. Cancelled on disappear.
        .task { await vm.loadDictionaries() }
        .environment(\.editMode, .constant(.active))   // always-on drag grips, no Edit button
        .accessibilityIdentifier("dictionary_order_view")   // screen-level handle so page-object can waitForExistence before interacting (#6 review)
        .navigationTitle("settings.dictionaryOrder.title")
    }
}
