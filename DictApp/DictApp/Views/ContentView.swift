// ContentView.swift
// Root tab view: Search · Learn · History · Settings (0131, #158). Each
// window keeps its own tab; a reminder's tap opens Learn through
// `AppRouter` (#162).

import SwiftUI

struct ContentView: View {
    @State private var selection: AppRouter.Tab = .search

    /// The first-launch sheet launch decided on (#245, `PackOffer`): the
    /// first window that appears takes it, so on iPad it shows in one.
    @State private var welcome: WelcomeViewModel?

    var body: some View {
        TabView(selection: $selection) {
            SearchView()
                .tabItem {
                    Label("tab.search", systemImage: "magnifyingglass")
                }
                .tag(AppRouter.Tab.search)
                .accessibilityIdentifier("search_tab")

            LearnView()
                .tabItem {
                    Label("tab.learn", systemImage: "graduationcap")
                }
                .tag(AppRouter.Tab.learn)
                .accessibilityIdentifier("learn_tab")

            HistoryView()
                .tabItem {
                    Label("tab.history", systemImage: "clock")
                }
                .tag(AppRouter.Tab.history)
                .accessibilityIdentifier("history_tab")

            SettingsView()
                .tabItem {
                    Label("tab.settings", systemImage: "gearshape")
                }
                .tag(AppRouter.Tab.settings)
                .accessibilityIdentifier("settings_tab")
        }
        .onReceive(AppRouter.shared.$request.compactMap { $0 }) { tab in
            selection = tab
            AppRouter.shared.taken()
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
