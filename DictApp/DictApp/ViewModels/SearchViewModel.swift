// SearchViewModel.swift
// Debounced search-as-you-type against the SQLite FTS5 index.

import Foundation
import Combine

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query: String = ""
    /// Search rows; a lemma row carries its `FormMatch` (Issue #142).
    @Published var results: [SearchResult] = []
    @Published var recentWords: [HistoryItem] = []
    @Published var isSearching: Bool = false
    @Published var errorMessage: String?

    /// The dictionary chips under the search field (Issue #145): the same
    /// pair list and setting as Settings → Dictionary Order.
    let selection: DictionarySelection

    /// With a query and every pair off, Search shows "Choose a dictionary"
    /// instead of results (Issue #145). An empty field keeps Recent words.
    var showsNoDictionariesHint: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty && selection.noneEnabled
    }

    private var searchTask: Task<Void, Never>?
    private let debounceInterval: Duration = .milliseconds(150)

    private let db: DatabaseService
    private let settings: SettingsService
    private var cancellables: Set<AnyCancellable> = []

    /// What a chip change is compared on: the pairs' order, states, sources
    /// and entry counts. A struct because tuples are not `Equatable`. An
    /// import named like a bundled source (#105) keeps the pair's source IDs,
    /// since the dictionary file has every bundled ID; only the count shows it.
    private struct PairState: Equatable {
        let id: String
        let isEnabled: Bool
        let sourceIDs: [String]
        let count: Int
    }

    /// A `nil` selection is `.shared` for the app's settings, or a new one
    /// over a test's own settings (`DictionarySelection.owning`).
    init(db: DatabaseService = .shared,
         settings: SettingsService = .shared,
         selection: DictionarySelection? = nil) {
        self.db = db
        self.settings = settings
        self.selection = selection ?? .owning(settings, db: db)

        // Issue #139: Search answers from the dictionary file while a 1.x
        // database moves in. When the move commits, re-run the current query
        // once, so the moved imports show without retyping. A no-op on an
        // empty query.
        NotificationCenter.default.publisher(for: LegacyMigration.didCommit)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshIfNeeded() }
            .store(in: &cancellables)

        // Issue #145: a chip (or a Settings switch, a reorder, an import that
        // reloads the list) re-runs the current query at once. The selection writes the store before it
        // publishes, so `onQueryChanged` reads the new setting; the debounce
        // folds quick taps into one query. A title-only change (language
        // switch) re-runs nothing.
        self.selection.$pairs
            .map { $0.map { PairState(id: $0.id, isEnabled: $0.isEnabled, sourceIDs: $0.pair.sourceIDs, count: $0.count) } }
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in self?.refreshIfNeeded() }
            .store(in: &cancellables)
        // The hint reads the selection, so re-render with it.
        self.selection.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    func loadRecent() async {
        recentWords = (try? await db.fetchHistory(limit: 10)) ?? []
    }

    /// Call this from `.onChange(of: query)` in the view.
    func onQueryChanged() {
        searchTask?.cancel()

        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            results = []
            isSearching = false
            return
        }

        isSearching = true

        // Capture the relevant settings at the moment the query fires (Issue #6:
        // also the sort mode + dictionary order). nil enabledSources means "all
        // enabled" (first-launch default); empty set means "none enabled".
        let enabledSources: Set<String>? = settings.enabledSources
        let mode = settings.resultSortMode
        let order = settings.dictionaryOrder ?? []
        // Issue #92: preferred mode buckets per language pair, so split the
        // source order into pair groups (pure, no DB) at keystroke time.
        let groups = DictionaryGrouping.sourceGroups(order: order)

        searchTask = Task { [trimmed, db, enabledSources, mode, order, groups] in
            // Debounce: wait briefly so we don't hammer the DB on every keystroke.
            try? await Task.sleep(for: debounceInterval)
            guard !Task.isCancelled else { return }

            do {
                let found: [SearchResult]
                if mode == .preferredDictionary, !order.isEmpty {
                    // nil enabledSources = all enabled → all known (ordered) sources.
                    let effectiveEnabled = enabledSources ?? Set(order)
                    found = try await db.searchPreferredResults(
                        query: trimmed, groups: groups, enabledSources: effectiveEnabled
                    )
                } else {
                    found = try await db.searchResults(query: trimmed, enabledSources: enabledSources)
                }
                guard !Task.isCancelled else { return }
                self.results = found
                self.errorMessage = nil
            } catch {
                guard !Task.isCancelled else { return }
                self.errorMessage = error.localizedDescription
            }
            self.isSearching = false
        }
    }

    /// Re-runs the current query (Issue #6 §3d) so returning to Search after a
    /// sort-mode / dictionary-order change in Settings reflects it without
    /// retyping, and at once after a chip change (Issue #145). No-ops on an
    /// empty query, so it does NOT fire (or double-fire) on initial view
    /// load — the field starts empty.
    func refreshIfNeeded() {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        onQueryChanged()
    }
}

// MARK: - Form captions (Issue #142)

/// The caption under a lemma row on Search, "aorist 1sg of γράφω"
/// (0136-word-forms.md, "Caption"). Pure: the labels come from the form's
/// tag set, the strings from the in-app language's lproj.
enum FormCaption {
    /// One part of a caption. The raw value is its catalog key.
    enum Label: String, CaseIterable {
        case present = "forms.tense.present"
        case imperfect = "forms.tense.imperfect"
        case aorist = "forms.tense.aorist"
        case dependent = "forms.tense.dependent"
        case imperative = "forms.mood.imperative"
        case continuous = "forms.aspect.continuous"
        case simple = "forms.aspect.simple"
        case passive = "forms.voice.passive"
        case participle = "forms.nonfinite.participle"
        case infinitive = "forms.nonfinite.infinitive"
        case nominative = "forms.case.nominative"
        case genitive = "forms.case.genitive"
        case accusative = "forms.case.accusative"
        case vocative = "forms.case.vocative"
        case singular = "forms.number.singular"
        case plural = "forms.number.plural"
        case masculine = "forms.gender.masculine"
        case feminine = "forms.gender.feminine"
        case neuter = "forms.gender.neuter"
        case comparative = "forms.degree.comparative"
        case superlative = "forms.degree.superlative"
        case firstSingular = "forms.person.1sg"
        case secondSingular = "forms.person.2sg"
        case thirdSingular = "forms.person.3sg"
        case firstPlural = "forms.person.1pl"
        case secondPlural = "forms.person.2pl"
        case thirdPlural = "forms.person.3pl"
        case alternative = "forms.alternative"
        case form = "forms.form"

        /// The Greek pronoun VoiceOver reads for a person-number label, the
        /// word the inflection tables show (Greek, never translated).
        var pronoun: String? {
            switch self {
            case .firstSingular: return "εγώ"
            case .secondSingular: return "εσύ"
            case .thirdSingular: return "αυτός"
            case .firstPlural: return "εμείς"
            case .secondPlural: return "εσείς"
            case .thirdPlural: return "αυτοί"
            default: return nil
            }
        }
    }

    /// The caption the user sees: "aorist 1sg of γράφω".
    static func text(for match: FormMatch, locale: Locale) -> String {
        let labels = labels(for: match).map { SettingsViewModel.localizedString($0.rawValue, locale: locale) }
        return caption(labels.joined(separator: " "), lemma: match.lemma, locale: locale)
    }

    /// What VoiceOver reads: the person as its Greek pronoun and a pause
    /// between the labels, "aorist, εγώ of γράφω".
    static func accessibilityText(for match: FormMatch, locale: Locale) -> String {
        let labels = labels(for: match).map { $0.pronoun ?? SettingsViewModel.localizedString($0.rawValue, locale: locale) }
        return caption(labels.joined(separator: ", "), lemma: match.lemma, locale: locale)
    }

    /// `forms.caption`: "%1$@ of %2$@". For a right-to-left language the
    /// catalog value starts with U+200F, and Foundation isolates the lemma
    /// (FSI … PDI), as in #119.
    private static func caption(_ labels: String, lemma: String, locale: Locale) -> String {
        String(localized: "forms.caption \(labels) \(lemma)",
               bundle: SettingsViewModel.localizedBundle(for: locale), locale: locale)
    }

    static func labels(for match: FormMatch) -> [Label] {
        switch match.analysis {
        case .greek(let tags): return labels(forGreekTags: tags)
        }
    }

    /// The labels of a Greek form, in caption order:
    /// - `alternative`: "alternative form";
    /// - participle, or aorist infinitive;
    /// - finite verbs: tense or mood (present, imperfect, aorist, dependent,
    ///   imperative continuous or simple), "passive" if tagged, then person
    ///   and number (1sg … 3pl);
    /// - nominals: comparative or superlative if tagged, case, number, then
    ///   gender if tagged (adjectives, articles, pronouns);
    /// - nothing recognised: "form".
    static func labels(forGreekTags tags: Set<String>) -> [Label] {
        if tags.contains("alternative") { return [.alternative] }
        if tags.contains("participle") { return [.participle] }
        if tags.contains("infinitive-aorist") { return [.infinitive] }

        let person = personNumber(tags)
        if let tense = tenseOrMood(tags) {
            return tense + (tags.contains("passive") ? [.passive] : []) + (person.map { [$0] } ?? [])
        }
        if let person {
            return (tags.contains("passive") ? [.passive] : []) + [person]
        }

        let degree: [Label] = tags.contains("comparative") ? [.comparative]
            : tags.contains("superlative") ? [.superlative] : []
        let cases: [(String, Label)] = [("nominative", .nominative), ("genitive", .genitive),
                                        ("accusative", .accusative), ("vocative", .vocative)]
        if let grammaticalCase = cases.first(where: { tags.contains($0.0) })?.1 {
            let numbers: [(String, Label)] = [("singular", .singular), ("plural", .plural)]
            let genders: [(String, Label)] = [("masculine", .masculine), ("feminine", .feminine), ("neuter", .neuter)]
            return degree + [grammaticalCase]
                + numbers.filter { tags.contains($0.0) }.prefix(1).map(\.1)
                + genders.filter { tags.contains($0.0) }.prefix(1).map(\.1)
        }
        return degree.isEmpty ? [.form] : degree
    }

    /// Tense or mood of a finite verb form, or `nil`. The aorist is Wiktextract's
    /// `past perfective`, the imperfect its `imperfect` (or `past imperfective`).
    private static func tenseOrMood(_ tags: Set<String>) -> [Label]? {
        if tags.contains("imperative") {
            return [.imperative] + (tags.contains("imperfective") ? [.continuous]
                                    : tags.contains("perfective") ? [.simple] : [])
        }
        if tags.contains("dependent") { return [.dependent] }
        if tags.contains("imperfect") { return [.imperfect] }
        if tags.contains("past") {
            if tags.contains("perfective") { return [.aorist] }
            if tags.contains("imperfective") { return [.imperfect] }
        }
        if tags.contains("present") { return [.present] }
        return nil
    }

    /// 1sg … 3pl, when the form has both a person and a number.
    private static func personNumber(_ tags: Set<String>) -> Label? {
        let plural = tags.contains("plural")
        guard plural || tags.contains("singular") else { return nil }
        if tags.contains("first-person") { return plural ? .firstPlural : .firstSingular }
        if tags.contains("second-person") { return plural ? .secondPlural : .secondSingular }
        if tags.contains("third-person") { return plural ? .thirdPlural : .thirdSingular }
        return nil
    }
}
