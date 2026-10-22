import Foundation

struct AccessibilityIdentifiers {

    // MARK: - Tab Bar
    struct TabBar {
        // Tab **content** ids: `ContentView` puts them on each tab's root view
        // (`SearchView()`…), not on the tab buttons, so they never match a
        // button. `searchTab` is the language-independent "Search screen is
        // up" anchor (`XCUIApplication.waitForDictionariesReady`).
        static let searchTab = "search_tab"
        static let historyTab = "history_tab"
        static let bookmarksTab = "bookmarks_tab"
        static let settingsTab = "settings_tab"

        // iPadOS 26 tab-button identifiers (Issue #104): the floating tab strip
        // has no `UITabBar`, and its buttons carry the tab's SF Symbol as their
        // identifier. Must match `ContentView`'s `.tabItem` `systemImage`s.
        static let searchSymbol = "magnifyingglass"
        static let historySymbol = "clock"
        static let bookmarksSymbol = "bookmark"
        static let settingsSymbol = "gearshape"
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
        /// Issue #87 — the source badge `Text` on a result row. Read badges
        /// by this id: their `label` is the localized VoiceOver text
        /// ("Greek to English, FreeDict"), not the visible "El–En · FD".
        static func sourceBadge(source: String) -> String {
            return "source_badge_\(source)"
        }
        /// Issue #111 — the "Preparing dictionaries… N%" bar at the bottom of
        /// Search, present only while the bundled dictionaries are unpacked.
        static let dictionaryUnpackProgress = "dictionary_unpack_progress"
    }

    // MARK: - Definition View
    struct Definition {
        static let definitionView = "definition_view"
        static let bookmarkButton = "bookmark_button"
        static let definitionContent = "definition_content"
    }

    // MARK: - Reading Mode (Issue #5)
    struct ReadingMode {
        /// Open-book toolbar toggle shared by the Search root and Definition.
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
        /// Issue #91 — the (i) button on a pair row (on the `Button` itself).
        static func dictionaryInfoButton(pair: String) -> String {
            return "dictionary_info_\(pair)"
        }
    }

    // MARK: - Dictionary Info detail (Issue #91)
    //
    // Per-source ids are keyed by source ID (`TestData.Sources`), not pair key.
    struct DictionaryInfo {
        static let view = "dictionary_info_view"
        /// Section header (provider brand, or the source ID for a custom import).
        static func sourceHeader(_ source: String) -> String { "dictionary_info_source_\(source)" }
        static func direction(_ source: String) -> String { "dictionary_info_direction_\(source)" }
        static func sourceID(_ source: String) -> String { "dictionary_info_source_id_\(source)" }
        static func version(_ source: String) -> String { "dictionary_info_version_\(source)" }
        static func entries(_ source: String) -> String { "dictionary_info_entries_\(source)" }
        /// The license body `Text`.
        static func license(_ source: String) -> String { "dictionary_info_license_\(source)" }
        /// Footer of a custom-import block (no version / license metadata).
        static func noMetadata(_ source: String) -> String { "dictionary_info_no_metadata_\(source)" }
    }

    // MARK: - Manage Dictionaries View
    struct ManageDictionaries {
        static let importButton = "import_dictionary_button"
        static let importResultMessage = "import_result_message"
    }
}
