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
