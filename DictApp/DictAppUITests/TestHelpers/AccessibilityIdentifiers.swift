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
        /// "No results for …" (`ContentUnavailableView.search`).
        static let noResults = "search_no_results"

        // Issue #145 — the dictionary chips under the search field.
        /// The row, a container named "Dictionaries".
        static let chipsRow = "dictionary_chips"
        /// The "All" chip. Pair keys use `custom:` for imports, so an import
        /// named `all` never collides with it.
        static let allChip = "dictionary_chip_all"
        /// A pair chip, by pair key (`TestData.Pairs`), e.g. `dictionary_chip_eng-spa`.
        static func chip(pair: String) -> String {
            return "dictionary_chip_\(pair)"
        }
        /// "Only this" in a chip's long-press menu.
        static let onlyThisMenuItem = "dictionary_chip_only_this"
        /// "Choose a dictionary", shown instead of results when every chip is off.
        static let noDictionariesHint = "search_no_dictionaries"

        /// Issue #142 — the caption under a row the query found as an
        /// inflected form of its headword ("aorist 1sg of γράφω"). Its
        /// `label` is the VoiceOver text ("aorist, εγώ of γράφω").
        static let formCaption = "form_caption"
    }

    // MARK: - Definition View
    struct Definition {
        static let definitionView = "definition_view"
        static let bookmarkButton = "bookmark_button"
        static let definitionContent = "definition_content"
    }

    // MARK: - Inflection table (Issue #144)
    //
    // On the Definition screen of a Greek headword (0136-word-forms.md,
    // "Tables (#144)"). A cell's `label` is its VoiceOver text ("aorist, εγώ,
    // έγραψα"); headers are hidden from VoiceOver and have no id.
    struct Inflection {
        static let table = "inflection_table"
        static let allFormsButton = "inflection_all_forms_button"
        /// The lemma under the title when the table is another lemma's (πάω → πηγαίνω).
        static let linkedLemma = "inflection_linked_lemma"
        /// A verb cell: `inflection_cell_active_aorist_1sg`.
        static func verbCell(voice: String = "active", slot: String, person: String) -> String {
            return "inflection_cell_\(voice)_\(slot)_\(person)"
        }
        /// A participle or the infinitive: `inflection_cell_active_present_participle`.
        static func nonfiniteCell(voice: String = "active", slot: String) -> String {
            return "inflection_cell_\(voice)_\(slot)"
        }
        /// A noun or adjective cell: `inflection_cell_genitive_singular[_masculine]`.
        static func nominalCell(case grammaticalCase: String, number: String, gender: String? = nil) -> String {
            return "inflection_cell_\(grammaticalCase)_\(number)" + (gender.map { "_\($0)" } ?? "")
        }
        /// `inflection_cell_comparative`, `inflection_cell_superlative`.
        static func degreeCell(_ degree: String) -> String {
            return "inflection_cell_\(degree)"
        }
        /// The Credits row in Settings › Support, and the Wiktionary line on Credits.
        static let creditsLink = "settings_credits_link"
        static let creditsWiktionary = "credits_wiktionary"
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

    // MARK: - Languages (Issue #243)
    //
    // Settings → Dictionaries → Languages (0237, "UI"). Per-row ids take the
    // pack id (`ell`, `eng-lists`), or `eng` for the bundled English row.
    struct Languages {
        /// The Settings row.
        static let link = "dictionary_languages_link"
        static let screen = "languages_screen"
        /// "More languages" in Dictionary Order's footer.
        static let moreLanguages = "dictionary_order_more_languages"
        /// The toolbar's Edit / Done, in the in-app language.
        static let edit = "languages_edit"
        /// The row's name.
        static func row(_ id: String) -> String { "pack_row_\(id)" }
        static func download(_ id: String) -> String { "pack_download_\(id)" }
        /// The bar while waiting, downloading or installing; its value is
        /// the text under it ("3.1 of 6.9 MB", "Waiting").
        static func progress(_ id: String) -> String { "pack_progress_\(id)" }
        static func cancel(_ id: String) -> String { "pack_cancel_\(id)" }
        /// The swipe action.
        static func remove(_ id: String) -> String { "pack_remove_\(id)" }
        static func update(_ id: String) -> String { "pack_update_\(id)" }
        static func retry(_ id: String) -> String { "pack_retry_\(id)" }
        static func error(_ id: String) -> String { "pack_error_\(id)" }
        /// "Installed · 56.3 MB".
        static func installed(_ id: String) -> String { "pack_installed_\(id)" }
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
