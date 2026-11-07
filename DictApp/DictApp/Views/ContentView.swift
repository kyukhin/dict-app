// ContentView.swift
// Root tab view.

import SwiftUI

struct ContentView: View {
    /// The first-launch sheet launch decided on (#245, `PackOffer`): the
    /// first window that appears takes it, so on iPad it shows in one.
    @State private var welcome: WelcomeViewModel?

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
        .sheet(item: $welcome) { model in
            WelcomeSheet(model: model)
        }
        .onAppear {
            guard welcome == nil, let sheet = PackOffer.launchSheet else { return }
            PackOffer.launchSheet = nil
            welcome = WelcomeViewModel(sheet: sheet)
        }
    }
}
