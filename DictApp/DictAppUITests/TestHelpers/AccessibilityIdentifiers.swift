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
        /// 0166, #165: the word's learning status under the part of speech,
        /// one element whose label is its lines; absent when the word is not
        /// in learning or is paused.
        static let learningStatus = "learning_status"
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

    // MARK: - Example sentences (0134, #178)
    //
    // On the Definition screen above the inflection table, and in learning's
    // example sheet. An example is one VoiceOver element: its `label` reads
    // the sentence, the translation and "From Tatoeba: Zeus and CH". Numbered
    // ids (1…5 in display order) avoid the `firstMatch`-in-another-cell
    // gotcha (#143).
    struct Examples {
        static let section = "examples_section"
        static let title = "examples_title"
        /// "More examples" / "Fewer examples".
        static let moreButton = "examples_more_button"
        static func example(_ n: Int) -> String { "example_\(n)" }
        static func sentence(_ n: Int) -> String { "example_sentence_\(n)" }
        static func translation(_ n: Int) -> String { "example_translation_\(n)" }
        static func byline(_ n: Int) -> String { "example_byline_\(n)" }
        /// Learning: the sheet, its word and its Continue.
        static let sheet = "example_sheet"
        static let sheetWord = "example_sheet_word"
        static let sheetContinue = "example_sheet_continue"
        /// Learning: the feedback bar's Example button.
        static let exampleButton = "exercise_example_button"
        /// The Tatoeba line on Credits.
        static let creditsTatoeba = "credits_tatoeba"
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
        /// 0130, #154: Today's "Choose lists", which opens New words from.
        static let chooseLists = "learn_choose_lists"
        /// The Lists section: "New words from", "All lists", a checked list.
        static let newWordsFromRow = "learn_new_words_from_row"
        static let allListsRow = "learn_all_lists_row"
        static func listRow(_ id: String) -> String {
            return "learn_list_row_\(id)"
        }
        /// A checked list's progress bar; its label reads its numbers.
        static func listProgress(_ id: String) -> String {
            return "learn_list_progress_\(id)"
        }
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
        /// Match the pairs (#160); disabled with fewer than 5 words.
        static let trainerMatch = "learn_trainer_match"
        /// Today's Start, the daily session (#161); hidden when all is done.
        static let startButton = "learn_start_button"
        /// "Practise mistakes · 2 words" (#161); hidden at 0.
        static let mistakesRow = "learn_mistakes_row"
        /// 0166, #164: the daily goal ring (value `12/20`), the streak
        /// (value `5`) and the Statistics row; each opens Statistics.
        static let goalRing = "learn_goal_ring"
        static let streak = "learn_streak"
        static let statisticsRow = "learn_statistics_row"
        /// 0237: the chosen pair's pack on its way or failed: its language
        /// name, the failure and Try again.
        static let installRow = "learn_install_row"
        static let installError = "learn_install_error"
        static let installRetry = "learn_install_retry"
    }

    // MARK: - Statistics (0166, #164)
    struct Statistics {
        static let view = "stats_view"
        /// The segmented switch, with two or more learned languages.
        static let languageSwitch = "stats_language_switch"
        static let empty = "stats_empty"
        /// Today: exercises of every language, "12 of 20"; the others of the chosen language.
        static let todayExercises = "stats_today_exercises"
        static let todayNew = "stats_today_new"
        static let todayReviewed = "stats_today_reviewed"
        static let todayAccuracy = "stats_today_accuracy"
        static let todayTime = "stats_today_time"
        /// "9 days", "12 days", "2 of 3".
        static let streakCurrent = "stats_streak_current"
        static let streakBest = "stats_streak_best"
        static let streakFreeze = "stats_streak_freeze"
        /// A calendar day, `stats_streak_day_2026-11-04`; its value is
        /// `met`, `frozen`, `missed`, `open` or `none`.
        static func streakDay(_ day: String) -> String { "stats_streak_day_\(day)" }
        /// The 30-day chart, labelled with its VoiceOver summary, and the
        /// dates under it: the oldest day and "Today".
        static let chart30d = "stats_chart_30d"
        static let chartStart = "stats_chart_start"
        static let chartEnd = "stats_chart_end"
        static func list(_ id: String) -> String { "stats_list_\(id)" }
        static func listForecast(_ id: String) -> String { "stats_list_forecast_\(id)" }
        static let accuracyRecognition = "stats_accuracy_recognition"
        static let accuracyProduction = "stats_accuracy_production"
        /// The hardest words from 1.
        static func hardest(_ n: Int) -> String { "stats_hardest_\(n)" }
        /// The tense chart, labelled with its summary, and a tense's accuracy.
        static let tenseChart = "stats_chart_tenses"
        static func tense(_ tense: String) -> String { "stats_tense_\(tense)" }
        static func hardestVerb(_ n: Int) -> String { "stats_hardest_verb_\(n)" }
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
        /// The summary's values (#161).
        static let summaryExercises = "run_summary_exercises"
        static let summaryAccuracy = "run_summary_accuracy"
        static let summaryNewWords = "run_summary_new_words"
        static let summaryReviewed = "run_summary_reviewed"
        static let summaryTime = "run_summary_time"
        static let summaryGoal = "run_summary_goal"
    }

    // MARK: - Conjugation drill (0132, #168)
    //
    // The run itself is E4's (`Exercise`): `exercise_view`, the options,
    // the feedback bar and the summary.
    struct Conjugation {
        /// The Learn home's Trainers row, while Greek is chosen; its value
        /// is the tense level as the UI writes it ("A1"; "Α1" in Greek).
        static let trainerRow = "learn_trainer_conjugation"
        /// The Conjugation screen.
        static let screen = "drill_start"
        /// "Verbs from Greek A1, Greek A2" and "253 verbs".
        static let lists = "drill_lists"
        static let verbCount = "drill_verb_count"
        /// "Tenses up to": its segments are labelled by level.
        static let tensesPicker = "drill_tenses_picker"
        /// A tense of the level, `drill_tense_aorist`; its value is the
        /// accuracy ("82%") or empty.
        static func tense(_ tense: String) -> String { "drill_tense_\(tense)" }
        static let startButton = "drill_start_button"
        /// No Greek list checked.
        static let noLists = "drill_no_lists"
        static let chooseLists = "drill_choose_lists"
        /// No Greek pack.
        static let needsGreek = "drill_needs_greek"
        static let downloadGreek = "drill_download_greek"
        static let downloadProgress = "drill_download_progress"
        /// A question: the verb, its translation, the tense line (its label
        /// "Aorist, εγώ") and the note of a verb with passive forms only.
        static let promptVerb = "drill_prompt_verb"
        static let promptTranslation = "drill_prompt_translation"
        static let promptTense = "drill_prompt_tense"
        static let passiveNote = "drill_passive_note"
        /// The whole tense after an answer; a row `drill_tense_row_1sg`
        /// reads "εγώ, έγραψα", and the asked one has the value `asked`.
        static let tenseTable = "drill_tense_table"
        static func tenseRow(_ person: String) -> String { "drill_tense_row_\(person)" }
        /// The summary's tense, `drill_summary_tense_aorist`, value `4/5`.
        static func summaryTense(_ tense: String) -> String { "drill_summary_tense_\(tense)" }
        /// Practise under a Greek verb's table on the Definition screen.
        static let practiseButton = "drill_practise_button"
    }

    // MARK: - Match the pairs (0131, #160)
    struct Match {
        static let view = "match_view"
        /// Its value is the elapsed time, `m:ss`.
        static let timer = "match_timer"
        /// The word column's tiles from the top, `match_word_0` … `match_word_4`.
        static func word(_ position: Int) -> String {
            return "match_word_\(position)"
        }
        /// The meaning column's tiles from the top, `match_meaning_0` … `match_meaning_4`.
        static func meaning(_ position: Int) -> String {
            return "match_meaning_\(position)"
        }
        /// The round's result, with its time and mistakes.
        static let result = "match_result"
        static let resultTime = "match_result_time"
        static let resultMistakes = "match_result_mistakes"
        static let nextRound = "match_next_round"
        static let done = "match_done"
    }

    // MARK: - My words (0131, #158: the former Bookmarks list; E3's list screen since #154)
    struct MyWords {
        static let list = WordLists.items
        /// A row; its label is the word.
        static let item = WordLists.item
    }

    // MARK: - Word lists (0130, #154)
    struct WordLists {
        /// The Lists screen.
        static let lists = "word_lists"
        static func row(_ id: String) -> String { "word_list_row_\(id)" }
        static func count(_ id: String) -> String { "word_list_count_\(id)" }
        /// The "Learning" badge of a checked list.
        static func active(_ id: String) -> String { "word_list_active_\(id)" }
        /// A row's progress bar (0166); its label: "1 learned · 5 learning · 1,451 new".
        static func progress(_ id: String) -> String { "word_list_progress_\(id)" }
        static let importButton = "word_list_import_button"
        /// A list's screen and a word row (label: the term; value: its meaning).
        static let items = "word_list_items"
        static let item = "word_list_item"
        static let itemTranslation = "word_list_item_translation"
        static let learnButton = "word_list_learn_button"
        /// New words from; a row is selected while its list is checked.
        static let newWordsFrom = "new_words_from"
        static func newWordsFromRow(_ id: String) -> String { "new_words_from_row_\(id)" }
        static let newWordsFromNone = "new_words_from_none"
    }

    // MARK: - List import (0130, #155)
    struct ListImport {
        /// The source choice and the Formats help.
        static let file = "list_import_file"
        static let paste = "list_import_paste"
        static let formats = "list_import_formats"
        static let help = "list_import_help"
        /// An example on the help screen (CSV, Anki, Quizlet).
        static let example = "list_import_example"
        /// Paste text: the text box, SwiftUI's Paste button and Preview.
        static let text = "list_import_text"
        static let pasteButton = "list_import_paste_button"
        static let next = "list_import_next"
        /// The preview.
        static let preview = "list_import_preview"
        static let name = "list_import_name"
        static let language = "list_import_language"
        static let delimiter = "list_import_delimiter"
        static let summary = "list_import_summary"
        static let errorRow = "list_import_error_row"
        static let confirm = "list_import_confirm"
        /// "Save the file as UTF-8 and try again".
        static let failure = "list_import_failure"
        /// The result and its Done.
        static let result = "list_import_result"
        static let done = "list_import_done"
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

    // MARK: - Settings → Learning (0131, #162)
    struct LearningSettings {
        static let languages = "settings_learning_languages"
        static let languagesView = "settings_learning_languages_view"
        static let newPerDay = "settings_learning_new_per_day"
        /// E3's New words from (0130, #154).
        static let newWordsFrom = "settings_learning_new_words_from"
        static let goal = "settings_learning_goal"
        static let order = "settings_learning_order"
        static let answerMode = "settings_learning_answer_mode"
        static let sounds = "settings_learning_sounds"
        static let haptics = "settings_learning_haptics"
        static let reminder = "settings_learning_reminder"
        static let reminderTime = "settings_learning_reminder_time"
        static let addLanguage = "learning_language_add"
        /// The learned language's name, on the Languages screen.
        static func row(_ lang: String) -> String { "learning_language_row_\(lang)" }
        /// Its via: a menu with two or more pairs ("via English"), else text.
        static func via(_ lang: String) -> String { "learning_language_via_\(lang)" }
        /// A limited pair's warning under the via.
        static func limited(_ lang: String) -> String { "learning_language_limited_\(lang)" }
        static func stop(_ lang: String) -> String { "learning_language_stop_\(lang)" }
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
        /// "Installed · 60.6 MB".
        static func installed(_ id: String) -> String { "pack_installed_\(id)" }
    }

    // MARK: - First-launch sheet and "not downloaded" (Issue #245)
    //
    // 0237, "UI". After Download the sheet's rows are `PackRow`s, with the
    // `Languages` ids.
    struct Welcome {
        /// The sheet's list.
        static let sheet = "welcome_sheet"
        /// A language to check; checked, it has the selected trait.
        static func language(_ id: String) -> String { "welcome_language_\(id)" }
        /// "Download 18.8 MB", or "Continue" with nothing checked.
        static let download = "welcome_download"
        static let notNow = "welcome_not_now"
        /// "Import your own dictionary": pushes Manage Dictionaries.
        static let importLink = "welcome_import"
        static let done = "welcome_done"
        /// "Download Greek · 11.9 MB" of the "not downloaded" view and the
        /// Search hint (then "Try again").
        static let notDownloadedDownload = "not_downloaded_download"
        /// The Search hint's text, "Greek is not downloaded."
        static let searchHint = "search_not_downloaded"
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
