// CreditsView.swift
// Static credits and acknowledgments view

import SwiftUI

struct CreditsView: View {
    var body: some View {
        List {
            Section("credits.app.section") {
                Text("credits.app.description")
            }
            Section("credits.dataSources.section") {
                Text("credits.dataSources.wordnet")
                Text("credits.dataSources.openrussian")
                Text("credits.dataSources.freedict")
                Text("credits.dataSources.spanishWordnet")
                Text("credits.dataSources.arabicWordnet")
                Text("credits.dataSources.greekWordnet")
                // Issue #144: the Greek word forms and inflection tables (0136).
                Text("credits.dataSources.wiktionary")
                    .accessibilityIdentifier("credits_wiktionary")
                // Issue #152: the Greek word lists and the frequencies that order new words (0130).
                Text("credits.dataSources.greekLists")
                    .accessibilityIdentifier("credits_greek_lists")
                // Issue #153: the English word lists, CEFR-J (A1–B2) and Octanove (C1–C2), with their citations (0130).
                Text("credits.dataSources.cefrj")
                    .accessibilityIdentifier("credits_cefrj")
                Text("credits.dataSources.octanove")
                    .accessibilityIdentifier("credits_octanove")
                Text("credits.dataSources.frequencyWords")
                    .accessibilityIdentifier("credits_frequency_words")
            }
            Section("credits.licenses.section") {
                Text("credits.licenses.placeholder")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("credits.title")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        CreditsView()
    }
}
