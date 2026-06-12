// DictionaryOrderView.swift
// Combined enable/disable + drag-to-reorder dictionary list (Issue #6), pushed
// from Settings → Dictionaries.

import SwiftUI

/// One combined list (drag handle leading, toggle trailing) on a dedicated
/// pushed screen. A dedicated `List` scoped to active `editMode` shows always-on
/// drag grips cleanly; forcing the whole Settings `Form` into edit mode would
/// instead put delete-circles on every row (§1b). Disabled dictionaries stay in
/// the order (greyed, still draggable).
struct DictionaryOrderView: View {
    @ObservedObject var vm: SettingsViewModel

    var body: some View {
        List {
            ForEach(vm.orderedDictionaries) { dict in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(dict.displayName)
                            .font(.body)
                            // Row identifier lives on the leading label, NOT the
                            // HStack: a container-level identifier propagates onto
                            // the row's switch and shadows the Toggle's own
                            // `dictionary_toggle_*` id (Issue #6). The label is a
                            // stable drag handle and frame anchor for the order list.
                            .accessibilityIdentifier("dictionary_order_row_\(dict.source)")
                        Text("dictionary.entries.count \(dict.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle(isOn: vm.binding(for: dict.source)) { EmptyView() }
                        .labelsHidden()
                        .accessibilityIdentifier("dictionary_toggle_\(dict.source)")
                }
            }
            .onMove { from, to in vm.moveDictionary(from: from, to: to) }
        }
        .environment(\.editMode, .constant(.active))   // always-on drag grips, no Edit button
        .accessibilityIdentifier("dictionary_order_view")   // screen-level handle so page-object can waitForExistence before interacting (#6 review)
        .navigationTitle("settings.dictionaryOrder.title")
    }
}
