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

            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock")
                }

            BookmarksView()
                .tabItem {
                    Label("Bookmarks", systemImage: "bookmark")
                }

            DictionaryManagerView()
                .tabItem {
                    Label("Manage", systemImage: "books.vertical")
                }
        }
    }
}
