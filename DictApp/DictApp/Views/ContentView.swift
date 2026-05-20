// ContentView.swift
// Root tab view.

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            SearchView()
                .tabItem {
                    Label("tab.search", systemImage: "magnifyingglass")
                }
                .accessibilityIdentifier("search_tab")

            HistoryView()
                .tabItem {
                    Label("tab.history", systemImage: "clock")
                }
                .accessibilityIdentifier("history_tab")

            BookmarksView()
                .tabItem {
                    Label("tab.bookmarks", systemImage: "bookmark")
                }
                .accessibilityIdentifier("bookmarks_tab")

            SettingsView()
                .tabItem {
                    Label("tab.settings", systemImage: "gearshape")
                }
                .accessibilityIdentifier("settings_tab")
        }
    }
}
