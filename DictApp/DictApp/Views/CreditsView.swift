// CreditsView.swift
// Static credits and acknowledgments view

import SwiftUI

struct CreditsView: View {
    var body: some View {
        List {
            Section("App") {
                Text("LibreDict — Open-source offline dictionary")
            }
            Section("Data Sources") {
                Text("WordNet — Princeton University")
            }
            Section("Licenses") {
                Text("Full license information coming soon.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Credits")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        CreditsView()
    }
}
