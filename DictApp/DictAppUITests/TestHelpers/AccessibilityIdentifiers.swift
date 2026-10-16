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
        /// Issue #6 — per-source colour stripe on a Search/History row.
        static func sourceStripe(source: String) -> String {
            return "source_stripe_\(source)"
        }
    }

    // MARK: - Definition View
    struct Definition {
        static let definitionView = "definition_view"
        static let bookmarkButton = "bookmark_button"
        static let definitionContent = "definition_content"
    }

    // MARK: - Reading Mode (Issue #5)
    struct ReadingMode {
        /// Cup-and-saucer toolbar toggle shared by the Search root and Definition.
        static let toggle = "reading_mode_toggle"
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

    // MARK: - Settings View
    struct Settings {
        static let manageDictionariesLink = "manage_dictionaries_link"
        static let dictionaryOrderLink = "dictionary_order_link"      // Issue #6
        static let resultSortModePicker = "result_sort_mode_picker"  // Issue #6
        static let versionValue = "version_value"
        /// Issue #92 — one toggle per language pair (`TestData.Pairs`), e.g.
        /// `dictionary_toggle_eng-spa` covers both `freedict-eng-spa` and
        /// `wordnet-spa-eng`.
        static func dictionaryToggle(pair: String) -> String {
            return "dictionary_toggle_\(pair)"
        }
        /// Issue #6 / #92 — a pair row in the reorderable DictionaryOrderView
        /// list (identifier lives on the leading `Text`).
        static func dictionaryOrderRow(pair: String) -> String {
            return "dictionary_order_row_\(pair)"
        }
    }

    // MARK: - Manage Dictionaries View
    struct ManageDictionaries {
        static let importButton = "import_dictionary_button"
        static let importResultMessage = "import_result_message"
    }
}
