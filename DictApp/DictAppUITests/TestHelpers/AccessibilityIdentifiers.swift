import Foundation

struct AccessibilityIdentifiers {

    // MARK: - Tab Bar
    struct TabBar {
        // Tab **content** ids: `ContentView` puts them on each tab's root view
        // (`SearchView()`…), not on the tab buttons, so they never match a
        // button. `searchTab` is the language-independent "Search screen is
        // up" anchor (`XCUIApplication.waitForDictionariesReady`).
        static let searchTab = "search_tab"
        static let learnTab = "learn_tab"
        static let historyTab = "history_tab"
        static let settingsTab = "settings_tab"

        // iPadOS 26 tab-button identifiers (Issue #104): the floating tab strip
        // has no `UITabBar`, and its buttons carry the tab's SF Symbol as their
        // identifier. Must match `ContentView`'s `.tabItem` `systemImage`s.
        static let searchSymbol = "magnifyingglass"
        static let learnSymbol = "graduationcap"
        static let historySymbol = "clock"
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
        /// 0131, #158: the Learn button, where the bookmark star was. Its
        /// label is "Learn", "Stop learning" or "Remove from My words".
        static let learnButton = "learn_button"
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

    // MARK: - Learn tab (0131, #158)
    struct Learn {
        /// The home's list, once a language is learned.
        static let view = "learn_view"
        static let dueCount = "learn_due_count"
        static let newCount = "learn_new_count"
        static let allDone = "learn_all_done"
        static let myWordsRow = "learn_my_words_row"
        /// The segmented switch; its segments are labelled by language name.
        static let languageSwitch = "learn_language_switch"
        static let importList = "learn_import_list"
        static let addWordsHint = "learn_add_words_hint"
        /// "Which language do you want to learn?", while none is learned.
        static let languagePicker = "language_picker"
        /// A picker row, a pair by ISO 639-3 codes: `language_picker_row_ell-eng`.
        static func languagePickerRow(_ lang: String, via: String) -> String {
            return "language_picker_row_\(lang)-\(via)"
        }
        /// A limited pair's warning under its row: `language_picker_limited_ell-rus`.
        static func languagePickerLimited(_ lang: String, via: String) -> String {
            return "language_picker_limited_\(lang)-\(via)"
        }
        /// The size to download under a row, only when something is missing.
        static func languagePickerSize(_ lang: String, via: String) -> String {
            return "language_picker_size_\(lang)-\(via)"
        }
        /// The Trainers section (#159).
        static let trainerRecognition = "learn_trainer_recognition"
        static let trainerProduction = "learn_trainer_production"
    }

    // MARK: - Exercises (0131, #159)
    struct Exercise {
        static let view = "exercise_view"
        static let close = "exercise_close"
        static let progress = "exercise_progress"
        static let prompt = "exercise_prompt"
        static let newBadge = "exercise_new_badge"
        /// `exercise_option_0` … `exercise_option_3`.
        static func option(_ index: Int) -> String {
            return "exercise_option_\(index)"
        }
        static let answerField = "exercise_answer_field"
        static let check = "exercise_check"
        static let dontKnow = "exercise_dont_know"
        /// Its value is the outcome: `right`, `accent` or `wrong`.
        static let feedback = "exercise_feedback"
        static let continueButton = "exercise_continue"
        static let summary = "run_summary"
        static let summaryDone = "run_summary_done"
    }

    // MARK: - My words (0131, #158: the former Bookmarks list)
    struct MyWords {
        static let list = "my_words_list"
        static func item(word: String) -> String {
            return "my_words_item_\(word)"
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
