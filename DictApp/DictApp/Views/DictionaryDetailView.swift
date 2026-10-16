// DictionaryDetailView.swift
// Info detail for one Dictionary order row (Issue #91): every underlying
// source of the pair stacked, one section each.

import SwiftUI

/// Pure renderer of an already-loaded `DictionaryPair`: no DB access, no view
/// model. Single-source rows are pairs with one source (same code path).
/// Strings resolve through `SettingsViewModel`'s in-app-language helpers so
/// they follow `LocalizationManager`, not the device language.
struct DictionaryDetailView: View {
    let pair: DictionaryPair
    /// Localised pair title, e.g. "Spanish – English".
    let title: String

    @Environment(\.locale) private var locale

    var body: some View {
        List {
            ForEach(SettingsViewModel.infoSources(for: pair)) { stat in
                Section {
                    rows(for: stat)
                } header: {
                    Text(verbatim: SettingsViewModel.infoBlockTitle(for: stat))
                        .textCase(nil)
                        .accessibilityIdentifier("dictionary_info_source_\(stat.source)")
                } footer: {
                    if stat.license.isEmpty && stat.version.isEmpty {
                        Text(verbatim: label("dictionaryInfo.noMetadata"))
                            .accessibilityIdentifier("dictionary_info_no_metadata_\(stat.source)")
                    }
                }
            }
        }
        .accessibilityIdentifier("dictionary_info_view")
        .navigationTitle(title)
    }

    @ViewBuilder
    private func rows(for stat: SourceStat) -> some View {
        if let summary = SettingsViewModel.languageSummary(for: stat, locale: locale) {
            let key = stat.direction == nil ? "dictionaryInfo.language" : "dictionaryInfo.direction"
            row(key, value: summary, id: "dictionary_info_direction_\(stat.source)")
        }
        row("dictionaryInfo.sourceID", value: stat.source, id: "dictionary_info_source_id_\(stat.source)")
        if !stat.version.isEmpty {
            row("dictionaryInfo.version", value: stat.version, id: "dictionary_info_version_\(stat.source)")
        }
        row("dictionaryInfo.entries",
            value: stat.count.formatted(.number.locale(locale)),
            id: "dictionary_info_entries_\(stat.source)")
        if !stat.license.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: label("dictionaryInfo.license"))
                Text(verbatim: stat.license)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("dictionary_info_license_\(stat.source)")
            }
        }
    }

    /// Label/value row with the identifier on the value leaf, not the
    /// container (a container id would shadow it, #6).
    private func row(_ key: String, value: String, id: String) -> some View {
        LabeledContent {
            Text(verbatim: value)
                .accessibilityIdentifier(id)
        } label: {
            Text(verbatim: label(key))
        }
    }

    private func label(_ key: String) -> String {
        SettingsViewModel.localizedString(key, locale: locale)
    }
}
