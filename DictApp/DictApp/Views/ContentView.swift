// ContentView.swift
// Root tab view: Search · Learn · History · Settings (0131, #158).

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            SearchView()
                .tabItem {
                    Label("tab.search", systemImage: "magnifyingglass")
                }
                .accessibilityIdentifier("search_tab")

            LearnView()
                .tabItem {
                    Label("tab.learn", systemImage: "graduationcap")
                }
                .accessibilityIdentifier("learn_tab")

            HistoryView()
                .tabItem {
                    Label("tab.history", systemImage: "clock")
                }
                .accessibilityIdentifier("history_tab")

            SettingsView()
                .tabItem {
                    Label("tab.settings", systemImage: "gearshape")
                }
                .accessibilityIdentifier("settings_tab")
        }
    }
}
