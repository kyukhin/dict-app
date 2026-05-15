import Foundation

struct AccessibilityIdentifiers {

    // MARK: - Tab Bar
    struct TabBar {
        static let searchTab = "search_tab"
        static let historyTab = "history_tab"
        static let bookmarksTab = "bookmarks_tab"
        static let settingsTab = "settings_tab"
    }

    // MARK: - Search View
    struct Search {
        static let searchField = "search_field"
        static let resultsList = "search_results_list"
        static func searchResult(id: String) -> String {
            return "search_result_\(id)"
        }
    }

    // MARK: - Definition View
    struct Definition {
        static let definitionView = "definition_view"
        static let bookmarkButton = "bookmark_button"
        static let definitionContent = "definition_content"
    }

    // MARK: - History View
    struct History {
        static let historyList = "history_list"
        static func historyItem(word: String) -> String {
            return "history_item_\(word)"
        }
    }

    // MARK: - Bookmarks View
    struct Bookmarks {
        static let bookmarksList = "bookmarks_list"
        static func bookmarkItem(id: String) -> String {
            return "bookmark_item_\(id)"
        }
    }
}
