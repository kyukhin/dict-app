// ContentView.swift
// Root tab view.

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            SearchView()
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .accessibilityIdentifier("search_tab")

            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock")
                }
                .accessibilityIdentifier("history_tab")

            BookmarksView()
                .tabItem {
                    Label("Bookmarks", systemImage: "bookmark")
                }
                .accessibilityIdentifier("bookmarks_tab")

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .accessibilityIdentifier("settings_tab")
        }
    }
}
