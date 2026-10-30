# Quick dictionary switching on Search

> Spec written by Claude (AI) for LibreDict.
> Status: Implemented (approved by Kirill on 2026-10-30) · Epic: #146 · Tickets: #145 · Updated: 2026-10-31

Read [0000-overview.md](0000-overview.md) first. This epic changes the Search screen and how the Dictionary Order list is held in memory. It adds no data, no preference key and no migration. E1 ([0129](0129-dictionary-file.md)) and E2 ([0136](0136-word-forms.md)) change the same search path: see "Search, preferred mode, E1 and E2".

## Why

Dictionaries are switched on and off only in Settings → Dictionary Order. Typical use changes this several times a day: reading an English book, English only; studying Greek, English off; just curious, everything on. Each change costs 4 to 7 taps and two tab switches today. This epic puts the same switches on the Search screen.

## Behaviour

### The chips row

- A row of chips sits at the top of the Search screen, under the search field. It stays there while the results scroll, while the keyboard is up, and with an empty field (Recent words).
- "All" comes first, then one chip per Dictionary Order row, in the Dictionary Order sequence. Reordering rows in Settings reorders the chips. The chips themselves cannot be dragged.
- A chip's label is its row's title in Dictionary Order: "English", "Russian – English", "Greek – English". An imported dictionary shows its source name.
- A filled chip is on, an outlined chip is off.
- **Tap** a pair chip: it turns on or off. The results refresh at once. The query, the keyboard and the field focus stay.
- **"All"** is filled when every pair is on. Tapping it turns every pair on and stores "everything on", with `enabled_sources` absent. Tapped when it is filled, it changes nothing on screen but still removes an explicit full set, which the Settings switches store (see Decisions).
- **Long press** a pair chip: a menu with one item, "Only this". It turns that pair on and every other pair off. On iPad a secondary click opens the same menu.
- **Every pair off**: with a query, the hint "Choose a dictionary" ("Turn on at least one dictionary above.") replaces the results. With an empty field, Recent words stay.
- The chips are the Settings switches, not a temporary filter. A change shows in Settings at once, a change in Settings shows on the chips at once, and both survive a relaunch.
- Recent words and History are not filtered by the chips.

| Task | 1.4.0 | 2.0.0 |
|---|---|---|
| Only English | Settings → Dictionary Order → 4 switches → Search: 7 taps | Long press "English" → "Only this": 2 |
| English off | Settings → Dictionary Order → 1 switch → Search: 4 taps | Tap "English": 1 |
| Everything | Settings → Dictionary Order → every switch that is off → Search | Tap "All": 1 |
| After a change | The query re-runs when Search reappears | The query re-runs at once |
| Every dictionary off | "No results for …" | "Choose a dictionary" |

### Imported dictionaries, many pairs

- Each imported dictionary is its own Dictionary Order row, so it gets its own chip: at the end, switched on, right after the import. A file named like a bundled source joins that pair and adds no chip (#105).
- The row is one line and scrolls sideways. Labels never wrap or truncate. There is no "more" button. On iPad the bundled chips usually fit without scrolling.

### iPhone, iPad, Arabic, VoiceOver, Dynamic Type

- iPhone and iPad, portrait and landscape: the same row across the full width.
- iPadOS 26: the row sits under the search drawer. The floating tab strip stays visible while the field holds a query (#120, unchanged).
- Several iPad windows show the same chip state at the same time.
- Arabic: the row is mirrored. "All" is at the right edge and the row scrolls from the right. Labels are the Arabic Dictionary Order titles (#119).
- VoiceOver:
  - a pair chip reads as a switch, "English, on". Double tap toggles it. "Only this" is in the Actions rotor;
  - "All" reads "All dictionaries", plus "selected" when every pair is on;
  - the row is a container named "Dictionaries".
- Dynamic Type: labels scale up to the largest accessibility size. The row grows taller and still scrolls sideways.

### Decisions

- 2026-10-22 (Kirill): the chips follow the Settings → Dictionary Order sequence and are reordered there. No named presets for now; they come later only if chips are not enough.
- #145: the chips and the Settings switches drive one setting.
- 0129, approved by Kirill on 2026-10-28: the enabled set filters Search only, and History opens its stored source even when that source is off. So the chips leave Recent words and History alone.
- "All" stores "everything on" the way a fresh install does: `enabled_sources` absent. A dictionary that arrives later (an app update) is then on too. The Settings switches keep storing an explicit set, as in 1.4.0.
- With every pair off and an empty field, Recent words stay and no hint shows: they open in their own dictionary anyway.
- No "all off" action. Turning the last chip off does it, and the hint explains the empty screen.
- The long-press menu holds only "Only this": "English off" is one tap, and "All" is a chip.
- The chips decide which dictionaries are searched, never the order of results. "Preferred dictionary first" still follows Dictionary Order.
- 2026-10-30 (Kirill): the row stays pinned under the search field. Switching while looking at results matters more than about 44 pt of list height.

## Design

### One source of truth

The setting stays where it is: `enabled_sources` and `dictionary_order` in `SettingsService` (overview, Preferences). What is new is one in-memory owner of the pair list, shared by Search and Settings.

**`DictionarySelection`**: `@MainActor final class`, `ObservableObject`, `static let shared`, injectable `init(settings:localization:db:)`.
- `pairs: [DictionaryItem]`, published, in the Dictionary Order sequence. Also `isLoaded`, `allEnabled`, and `noneEnabled` (at least one pair, none on).
- `load()`: today's `SettingsViewModel.loadDictionaries()`, moved with its `DatabaseService.shared` calls replaced by the injected `db`. It keeps the #74 default order, the #92 normalisation, the #105 reconcile with the live sources, writes only on change and publishes only on change. `loadIfNeeded()` loads once.
- `setEnabled(_:pair:)`: today's `togglePair`. One write for the whole pair (#92: the sources of a pair share one state).
- `enableOnly(pair:)`: `enabled_sources` becomes the pair's source IDs. One write, none if nothing changes.
- `enableAll()`: removes `enabled_sources`. No write if it is already absent.
- `move(from:to:)`: today's `movePair`.
- It rebuilds each `displayName` when `LocalizationManager.currentLanguage` changes. The shared object survives the root `.id(language)` rebuild that recreates the per-screen view models.

**Sync rules**
1. Every write from the chips and the Dictionary Order screen to the two keys goes through `DictionarySelection`. The import flow follows rule 3.
2. It writes the store first, then publishes `pairs`. `@Published` emits before the property changes, so a subscriber that reads the store already sees the new value. Both screens render `pairs`, so they show the same state and order in the same frame, in every iPad window.
3. Code that writes the keys anywhere else calls `load()` afterwards: the import flow. The DEBUG launch hooks run before the first load. #73 (iCloud, v2.1.0) will call `load()` after an external change.

**Changes**
- `SettingsViewModel` keeps its API (`dictionaries`, `orderedDictionaries`, `loadDictionaries()`, `togglePair`, `binding(for:)`, `movePair`) as forwards to the selection, and re-publishes its changes. `DictionaryOrderView` does not change. `init` gains `selection:` (nil means `.shared`). Tests pass one built on their in-memory store.
- `SearchViewModel` gains `selection:` the same way. It maps `pairs` to `[PairState]` (an `Equatable` struct of `id`, `isEnabled`, the pair's source IDs and its entry count; tuples are not `Equatable`), drops the first value and duplicates, and calls `refreshIfNeeded()` on each change. That re-runs the current query through `onQueryChanged()`, which reads the store as today. Its 150 ms debounce folds quick taps into one query. `showsNoDictionariesHint` is true for a non-empty query when `noneEnabled`.
- `ManageDictionariesViewModel.performImport` awaits `selection.load()` after `enableImportedSource` and `appendImportedSourceToOrder`, on the same selection and settings store it was given (`.shared` in the app). An import that joins an enabled pair keeps the pair's source IDs, which the dictionary file already lists, but raises its entry count, so Search re-runs its query.
- `SearchView`:
  - `.task` also calls `selection.loadIfNeeded()`;
  - `DictionaryChipsRow` goes in `.safeAreaInset(edge: .top, spacing: 0)` on the List, on the `.bar` background, shown once `isLoaded`. It is an `HStack` in a horizontal `ScrollView`, not a lazy stack or a list, so every chip exists for VoiceOver and XCUITest, and `SearchPage.resultsList` still finds the results list. The "Dictionaries" container (label and `dictionary_chips`) is the `HStack`, not the `ScrollView`: on iOS 26 the scroll view's frame reaches up under the navigation bar, and a container around it covers the title and the search field (Kirill, 2026-10-31);
  - the hint is a `ContentUnavailableView` (symbol `books.vertical`) in the List, in place of `search_no_results`.
- A pair chip is a SwiftUI `Toggle` with a custom `ChipToggleStyle` (a capsule, filled with the tint when on, outlined when off), a `.contextMenu` with "Only this", and an `.accessibilityAction(named:)` that runs the same action. The Toggle keeps switch semantics: VoiceOver reads "English, on" and XCUITest reads `value` 1 or 0, as for the Settings switches. If the custom style loses them on a matrix OS, the chip sets the `.isToggle` trait and the value itself.
- "All" is a `Button` with the `.isSelected` trait when every pair is on.

Layering: the views hold no rules. They render `pairs` and call `DictionarySelection`. SQL stays in `DatabaseService`.

**No new files.** `DictionarySelection` goes in `SettingsViewModel.swift`, where its code comes from. The chips go in `SearchView.swift`. Tests go into existing files. So there is no `project.pbxproj` step.

### Search, preferred mode, E1 and E2

- `DatabaseService.search` does not change: it already filters by `source IN (...)` and returns nothing at once for an empty set.
- "Preferred dictionary first": the chips decide which pairs get a bucket, Dictionary Order decides the bucket order. After "All" the stored set is absent, and `SearchViewModel` uses `Set(order)` as today.
- E1 (#138–#140): `fetchSourceStats` keeps its output and lists every imported source by its `imported_entries` count, on or off, so an imported chip that is off keeps its chip and its Dictionary Order row. In Search, the `UNION ALL` branch over `imported_fts` follows the chips, because it is added only when an imported source is on. On the first launch after an upgrade from 1.x, `fetchSourceStats` waits for the move, so the chips appear when it commits (target under 2 s), like the Dictionary Order list.
- E2 (#136): lemma rows come only from enabled dictionaries, so they follow the chips. `results` becomes `[SearchResult]`. The hint does not depend on that type.
- Order of work: #145 depends on neither epic. It landed after E1, so it builds on #138's `fetchSourceStats` and a `SearchView` without the unpack bar. E2 changes `results` and rebases on it.

### Identifiers

| Element | Identifier |
|---|---|
| The row | `dictionary_chips` |
| "All" | `dictionary_chip_all` |
| A pair chip | `dictionary_chip_<pair key>`: `dictionary_chip_eng-spa`, `dictionary_chip_custom:test_import_fixture`. The `custom:` prefix keeps an import named `all` apart from "All" |
| "Only this" menu item | `dictionary_chip_only_this` |
| The hint | `search_no_dictionaries` |

The ids join `AccessibilityIdentifiers.Search`. `SearchPage` gains:
- `chip(_:)`, `tapChip(_:)`, `tapAllChip()`, `isChipOn(_:)` (value 1 or 0), `isAllSelected()`;
- `onlyThis(_:)`: press the chip for 1 s, then tap the menu item by id, with its English label as a fallback;
- `chipOrder(of:)`: pair keys in reading order, sorted by `frame.minX`, or by descending `frame.maxX` when the app runs right to left (Arabic);
- `waitForNoDictionariesHint()`. `waitForResults` also treats the hint as "no results", since the hint is a list cell.

Chips are found by id with any element type, and the row is scrolled by geometry, never through `isHittable`. `revealChip` drags along the chips with no momentum. `chipsRow` is as wide as the chips; `chipsScrollView` gives the row's full width.

### Strings

Six new keys. The implementing agent writes the translations; these are the proposed ones. Chip titles reuse `dictionaryPair.title` and `language.*.name`.

| Key | en | ru | es | ar | el |
|---|---|---|---|---|---|
| `search.chips.label` | Dictionaries | Словари | Diccionarios | القواميس | Λεξικά |
| `search.chips.all` | All | Все | Todos | الكل | Όλα |
| `search.chips.all.a11y` | All dictionaries | Все словари | Todos los diccionarios | كل القواميس | Όλα τα λεξικά |
| `search.chips.onlyThis` | Only this | Только этот | Solo este | هذا فقط | Μόνο αυτό |
| `search.noDictionaries.title` | Choose a dictionary | Выберите словарь | Elige un diccionario | اختر قاموسًا | Επιλέξτε λεξικό |
| `search.noDictionaries.description` | Turn on at least one dictionary above. | Включите хотя бы один словарь выше. | Activa al menos un diccionario arriba. | فعّل قاموسًا واحدًا على الأقل في الأعلى. | Ενεργοποιήστε τουλάχιστον ένα λεξικό παραπάνω. |

### Code map

| Path | Change |
|---|---|
| `DictApp/DictApp/ViewModels/SettingsViewModel.swift` | `DictionarySelection`, with the pair logic moved out of `SettingsViewModel`, which forwards to it |
| `DictApp/DictApp/ViewModels/SearchViewModel.swift` | Re-run on chip changes, `showsNoDictionariesHint` |
| `DictApp/DictApp/ViewModels/ManageDictionariesViewModel.swift` | Reload the selection after an import |
| `DictApp/DictApp/Views/SearchView.swift` | `DictionaryChipsRow`, `ChipToggleStyle`, the hint |
| `DictApp/DictApp/Resources/Localizable.xcstrings` | The six keys |
| `DictApp/DictAppUITests/TestHelpers/AccessibilityIdentifiers.swift`, `DictApp/DictAppUITests/PageObjects/SearchPage.swift` | Ids and page-object methods above |
| `DictApp/DictAppTests/DictAppTests.swift`, the UI suites in the test plan | New tests |
| `docs/specs/0000-overview.md` | Search row and Preferences: the chips share the setting |

## Test plan

Unit tests go in `DictAppTests.swift`: two new classes, `DictionarySelectionTests` (temp database and `InMemoryKeyValueStore`, as in `SettingsViewModelPairTests`) and `QuickSwitchSearchTests`. UI tests go in `DictionaryFilterTests` (English, `-resetData`) unless another suite is named. They run on the four-simulator matrix, one suite per run.

| Acceptance criterion | Test |
|---|---|
| #146: "only English", "English off" and "everything" in one or two taps | UI `DictionaryFilterTests.testThreeCasesInOneOrTwoTaps`: tap English (English off, the rest on, "All" not selected); tap "All" (every chip on, "All" selected); long press English, "Only this" (only English on). After each step `яблоко` shows results only while Russian is on |
| #146, #145: chips and Settings switches always show the same state | Unit `DictionarySelectionTests.testSettingsAndSearchShareOneState`: `SettingsViewModel.togglePair` changes `selection.pairs`, `selection.setEnabled` changes `vm.dictionaries`, one store write each; `testAppViewModelsShareOneSelection` (Search uses `.shared`, a test's own store gets its own selection). UI `testChipAndSettingsSwitchShowTheSameState`: Russian chip off, then the Settings switch is off; Spanish switch off in Settings, then the Spanish chip is off. `testChipStateSurvivesRelaunch`: a pair off and "All" both survive a relaunch |
| #146, #145: chips follow Dictionary Order; after a reorder in Settings they show the new order | Unit `testPairsFollowStoredOrder`, `testMoveReordersPairsAndStoredOrder`. UI `testChipsFollowDictionaryOrder`: `chipOrder` equals `SettingsPage.currentOrder`; after `reorderFirstToLast` in Settings, the chips on Search show the new order |
| #145: a tap toggles the pair and the results refresh at once | Unit `QuickSwitchSearchTests.testChipChangeReRunsQuery` (same query, new results, no keystroke), `testNoRunOnEmptyField`, `testImportJoiningAnEnabledPairReRunsQuery` (a file named like an enabled bundled source: the query runs again and finds its row). UI `testChipTapRefreshesResultsAtOnce`: `яблоко`, tap Russian, `search_no_results` shows without retyping, the field still holds `яблоко` and keeps the focus and the keyboard; tap again, results return |
| #145: "Only this" leaves only that pair; "All" enables every pair | Unit `testEnableOnlyKeepsExactlyThePair` (Greek: its 4 sources; no write when it is already the only one), `testEnableAllRemovesStoredSet` (key absent, every pair on, no write when already absent; an explicit set holding every source, as the Settings switches leave it, is removed too). UI: `testThreeCasesInOneOrTwoTaps`, which also checks the Settings switches after "Only this" |
| #145: with every pair off, the hint and no results | Unit `testAllOffShowsHintOnlyWithQuery`. UI `testAllOffShowsHint`: "Only this" on English, tap English, `search_no_dictionaries` shows and no result cell; tap "All", results return |
| #145, 0129: Recent words and History are not filtered; every pair off with an empty field shows Recent words and no hint | Unit `QuickSwitchSearchTests.testRecentWordsAndHistoryIgnoreTheChips`. UI `testRecentWordsIgnoreTheChips`: a word read in Russian stays in Recent words with every chip off, no hint, and opens its Russian entry |
| #145 (Kirill, 2026-10-30): the row stays pinned under the search field | UI `testChipsStayPinnedUnderTheField`: with an empty field, with the keyboard up, and while the results scroll under the row, the chips stay right under the field; the row's frame starts below the field |
| #145: imported dictionaries get a chip | Unit `DictionarySelectionTests.testImportReloadAppendsPairOn`. UI `ImportDictionaryTests.testImportedDictionaryGetsAChip`: after the JSON fixture import the fixture chip is last and on, `qaflux` is found; chip off, `search_no_results` |
| #145: "Preferred dictionary first" uses the chips | Unit `QuickSwitchSearchTests.testPreferredModeFollowsChips`: "Only this" on `ell-eng` returns only Greek sources, buckets in Dictionary Order |
| #145: all 5 UI languages, Arabic right to left | `testEveryCatalogKeyIsTranslatedInEveryShippedLanguage` (existing); unit `testTitlesFollowLanguageChange`. UI `ArabicLocalizationTests.testChipsReadRightToLeft` ("All" right of the first pair chip and at the right edge, labels equal the Arabic Dictionary Order titles), `GreekLocalizationTests.testChipsAreLocalizedInGreek` ("Όλα τα λεξικά", the Greek pair first by the #88 default, the Greek hint), `SpanishLocalizationTests.testChipsAreLocalizedInSpanish` |
| #145: VoiceOver "English, on" | UI `testChipAccessibility`: a pair chip is a switch and "All" a button, the label is the pair title, the value flips between 1 and 0 with a tap, "All" is `isSelected` only when every chip is on |
| #145: iPad including iPadOS 26; Dynamic Type | UI `iPadSpecificTests.testChipsOnIPad`: with a query the row is under the search field and above the first result in both orientations; on iPadOS 26 the tab strip still shows. `testChipsAtAccessibilityTextSize` (relaunch with `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL`): the last chip is reached by scrolling the row and toggles |
| #145: UI tests green on iPhone and iPad, iOS 17.5 and 26.4 | The matrix run of every suite above, plus `SearchFlowTests` and `NavigationTests`, which prove the row does not break result lookups |
| No regression in Settings | `SettingsViewModelPairTests`, the `DictionaryOrder*Tests` suites and the existing `DictionaryFilterTests` stay green unchanged |

## History

- 2026-10-29: First draft.
- 2026-10-30: Kirill chose the pinned row; the open question is closed. Approved by Kirill.
- 2026-10-30: CodeRabbit review: "All" also clears an explicit full set; the Search pipeline compares an `Equatable` pair snapshot; imported chips that are off stay listed.
- 2026-10-30: CodeRabbit review: "All" wording; `load()` uses the injected `db`; the Search snapshot carries source IDs and the entry count, so an import that joins an enabled pair re-runs the query (source IDs alone stay the same, found in #145).
- 2026-10-30: #145 implementation details. #138 lists imports by their `imported_entries` count, not from `imported_sources`; the result is the same, an import that is off keeps its chip. A `nil` `selection:` is `.shared` only with the app's `SettingsService`: a test that brings its own store gets a selection over it (Settings, Search) or no reload (Manage Dictionaries), so the existing tests run unchanged and the tests of the sharing pass one selection to every view model. `SettingsViewModel.dictionaries` stays `@Published`, re-published from `selection.$pairs`. `move` writes the order before it publishes and writes nothing for a move that changes nothing. The Search pipeline drops duplicates before the first value, so a title-only change (a language switch) re-runs nothing. `PairState` also carries the pair's entry count: the dictionary file has every bundled source ID, so an import named like one (`wordnet-spa-eng.json`) keeps the pair's source IDs and changes only its count; without the count Search did not re-run (`testImportJoiningAnEnabledPairReRunsQuery` failed). The row has a hairline divider under it, and its `.bar` background stays behind the row (`ignoresSafeAreaEdges: []`): by default it extends up over the navigation bar, which on iOS 26 covered the large title and the iPad tab strip. The custom `ToggleStyle` keeps the switch semantics (label, value 1 or 0, the toggle trait, the "Only this" action), checked in the accessibility tree, so the fallback is not needed. Search now loads the list at launch, so `dictionary_order` is stored on the first launch rather than on the first visit to Settings; same value, nothing visible changes.
- 2026-10-30 (QA): matrix on iPhone 15 Pro 17.5, iPhone 17 26.4, iPad Pro M4 17.5 and iPad Pro M5 26.4. Unit: 262 tests, 1 skipped (the opt-in `LIBREDICT_LEGACY_DB` test), green on all four. UI: every suite in its own run with the app uninstalled, green on all four: 109 tests on iPad, 106 plus 3 `iPadSpecificTests` skips on iPhone, plus the 2 template suites.
- 2026-10-30 (QA): `testChipsAtAccessibilityTextSize` failed on iOS 26: the `dictionary_chips` element's frame starts at y=0 (its `ScrollView` extends into the top safe area), so `revealChip` swiped the navigation bar. The row scrolls by touch. `revealChip` now drags along the chips with no momentum; vertical checks use `chipsBand`.
- 2026-10-30 (QA): `DictionaryFilterTests` hit the #125 os_log quarantine crash once on each 17.5 simulator (the crash report: `__LIBTRACE_CLIENT_QUARANTINED_DUE_TO_HIGH_LOGGING_VOLUME__`, then `runtime_issue_os_log_fault_callback`). The suite now sets `OS_ACTIVITY_MODE=disable`: 17/17 on all four. Unrelated re-runs: `DictionaryPairGroupingTests` once on iPhone 17 (the helper's 3 s window under four parallel streams; the recording shows the switch flipped), `VersionDisplayTests` on iPhone 15 Pro (runner timeouts, green after a simulator reboot).
- 2026-10-30 (QA): new tests: unit `testRecentWordsAndHistoryIgnoreTheChips`, `testAppViewModelsShareOneSelection`; UI `testChipsStayPinnedUnderTheField`, `testChipStateSurvivesRelaunch`, `testRecentWordsIgnoreTheChips`, and checks for focus and keyboard after a tap, the switch and button types, "All" at the right edge in Arabic, the row under the field on iPad.
- 2026-10-30 (QA): looked at en and ar, light and dark, iPhone and iPad on 17.5 and 26.4, and at the largest accessibility size: one line, no truncation, mirrored in Arabic, pinned under the field. On iPadOS 26 the large title collapses as the results scroll and the row moves up with the field. The accessibility audit finds only "contrast nearly passed" on the white-on-tint chips. Not checked by a test: "Only this" in the VoiceOver Actions rotor (code: `accessibilityAction(named:)`), the iPad secondary click and several iPad windows.
- 2026-10-31 (QA): Kirill: the row's accessibility frame must cover only the chips. The "Dictionaries" container and `dictionary_chips` moved from the stack around the `ScrollView` onto the chips' `HStack` inside it. On iPhone 17 (26.4) the frame was (0, 0, 402, 274), over the title and the search field; it is now (16, 236, 721, 30), under the field (bottom at 213). Identifiers, labels, RTL order and the layout are unchanged; on 17.5 the frame is now the chips too. `testChipsStayPinnedUnderTheField` asserts the frame starts below the field, `chipsBand` is gone, and `chipsScrollView` checks the full width on iPad. Green on iPhone 17 26.4, iPad M5 26.4 and iPhone 15 Pro 17.5: unit 262 (1 skipped), `DictionaryFilterTests` 17/17, `iPadSpecificTests` (3 on iPad, skipped on iPhone), `ArabicLocalizationTests` 7/7.
