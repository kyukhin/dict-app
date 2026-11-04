// Models.swift
// Core data models for the dictionary app.

import Foundation
import GRDB

// MARK: - DictionaryEntry

struct DictionaryEntry: Codable, Identifiable, Equatable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var word: String
    var definition: String
    var phonetic: String
    var pos: String            // part of speech
    var source: String
    var createdAt: String?

    static let databaseTableName = "entries"

    enum Columns: String, ColumnExpression {
        case id, word, definition, phonetic, pos, source, createdAt = "created_at"
    }

    // Custom coding keys to bridge snake_case SQL <-> camelCase Swift.
    enum CodingKeys: String, CodingKey {
        case id
        case word
        case definition
        case phonetic
        case pos
        case source
        case createdAt = "created_at"
    }

    /// Human-readable source label for display (the search-result badge).
    /// Bilingual bundled sources show direction + provider (Issue #87):
    /// en dash U+2013, then " · " (U+00B7 between spaces), then `FD` / `WN`.
    /// The visible text stays untranslated; VoiceOver reads the localized
    /// `SettingsViewModel.badgeAccessibilityLabel(forSource:locale:)`.
    var sourceLabel: String {
        switch source {
        case "wordnet":          return "WordNet"
        case "openrussian":      return "OpenRussian"
        // Badge is space-constrained; the full name lives in
        // `dict_metadata.display_name` (Settings + DictionaryDetailView).
        case "freedict-eng-spa": return "En\u{2013}Es \u{00B7} FD"
        case "wordnet-spa-eng":  return "Es\u{2013}En \u{00B7} WN"
        case "wordnet-arb-eng":  return "Ar\u{2013}En \u{00B7} WN"
        case "freedict-ell-eng": return "El\u{2013}En \u{00B7} FD"
        case "wordnet-ell-eng":  return "El\u{2013}En \u{00B7} WN"
        case "freedict-eng-ell": return "En\u{2013}El \u{00B7} FD"
        case "wordnet-eng-ell":  return "En\u{2013}El \u{00B7} WN"
        default:                 return source.capitalized
        }
    }
}

// MARK: - HistoryItem

/// `Hashable` so Search's Recent words can push it (`NavigationLink(value:)`).
struct HistoryItem: Codable, Identifiable, Hashable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var word: String
    /// Dictionary source of the entry that was last viewed for this word
    /// (Issue #6). Defaults to "" for rows migrated before `history.source`
    /// existed — those render the neutral `Sources/default` stripe until
    /// the word is viewed again.
    var source: String = ""
    var lookedAt: String?

    static let databaseTableName = "history"

    enum CodingKeys: String, CodingKey {
        case id
        case word
        case source
        case lookedAt = "looked_at"
    }
}

// MARK: - ResultSortMode (Issue #6)

/// How search results are ordered. `.relevance` is FTS rank (the default);
/// `.preferredDictionary` surfaces the top-N of each enabled dictionary in the
/// user's configured order, then a relevance tail (see `DatabaseService`).
enum ResultSortMode: String {
    case relevance
    case preferredDictionary
}

// MARK: - EntryKey (Issue #138)

/// The stable key of a dictionary entry: its source ID and its headword as
/// stored. User data (History, My words) points at entries by this key,
/// never by a row id, so it survives a new dictionary file. Resolution is
/// case-insensitive on `word` (`DatabaseService.entry(for:)`).
struct EntryKey: Hashable, Sendable {
    let source: String
    let word: String

    init(source: String, word: String) {
        self.source = source
        self.word = word
    }

    init(_ entry: DictionaryEntry) {
        self.init(source: entry.source, word: entry.word)
    }
}

// MARK: - WordKey (0130)

/// A word's learning identity (0130-word-lists.md, "For E4 and E10"): its
/// language and the word, so one word in two lists or two dictionaries is
/// one word. `lang` is ISO 639-3 (`und` when unknown). `word` is the word as
/// stored with only A–Z lowercased, as SQLite's `lower()` and `NOCASE` do,
/// so Swift equality matches SQL. No Unicode normalisation: list terms are
/// stored in NFC, but some dictionary headwords are not, and SQL could not
/// normalise them.
struct WordKey: Hashable, Sendable {
    let lang: String
    let word: String

    init(lang: String, word: String) {
        self.lang = lang
        self.word = String(String.UnicodeScalarView(word.unicodeScalars.map { scalar in
            ("A"..."Z").contains(scalar) ? Unicode.Scalar(UInt8(scalar.value) + 0x20) : scalar
        }))
    }
}

extension DatabaseService {
    /// The `WordKey` of a dictionary entry: its source's headword language
    /// (`und` when unknown) and its word. For the Learn button and E4's
    /// enrolment of My words (0130, "For E4 and E10").
    func wordKey(for key: EntryKey) async throws -> WordKey {
        WordKey(lang: try await sourceLanguage(of: key.source) ?? "und", word: key.word)
    }
}

// MARK: - DictionarySchemas (0237)

// ponytail: replaced by #241
/// A source's language for the My words key (0130, 0131): `source,
/// from_lang` rows of the bundle's `dict_metadata`. #241 adds
/// `dict.catalog_source`, so a pack not yet downloaded keeps its language.
enum DictionarySchemas {
    static let sourceLanguageSQL = "SELECT source, from_lang FROM dict.dict_metadata"
}

// MARK: - Search by any form (Issue #142)

/// Why the form step added a row to Search: the query is an inflected form
/// of `lemma` (0136-word-forms.md, "Search path"). Captioned by
/// `FormCaption`; never persisted.
struct FormMatch: Hashable, Sendable {
    /// What the form step knows about the query as a form of the lemma.
    enum Analysis: Hashable, Sendable {
        /// Greek: the Wiktextract tags of the form's caption tag set
        /// (`dict.form_lookup.tagset_id`), e.g. aorist 1sg is `active
        /// first-person indicative past perfective singular`.
        case greek(tags: Set<String>)
        /// English (Issue #143): how `Morphy` found the lemma, its part of
        /// speech, the detachment rule (`nil`: WordNet's exception list)
        /// and the query's ending the caption names (`Morphy.Analysis`).
        case english(pos: Morphy.PartOfSpeech, rule: Morphy.Rule?, suffix: String)
    }

    /// The lemma's headword (NFC), e.g. γράφω.
    let lemma: String
    let analysis: Analysis
}

/// One Search row: an entry, plus the form match that brought it in when
/// the query is an inflected form of its headword (Issue #142). Its
/// identity is the entry id, unique across the dictionary file and the
/// imports (#129).
struct SearchResult: Identifiable, Hashable, Sendable {
    let entry: DictionaryEntry
    var formMatch: FormMatch?

    init(entry: DictionaryEntry, formMatch: FormMatch? = nil) {
        self.entry = entry
        self.formMatch = formMatch
    }

    var id: Int64? { entry.id }
}

// MARK: - Morphy (Issue #143)

/// WordNet 3.0's morphy, ported (0136-word-forms.md, "Morphy (#143)"): the
/// lemmas an inflected English word is a form of (went → go, dogs → dog).
/// Pure: `DatabaseService` reads the word's lines of WordNet's exception
/// lists (`dict.morphy_exception`) and which rule bases are single-word
/// WordNet lemmas (`dict.morphy_lemma`), and passes them in.
enum Morphy {
    /// A WordNet part of speech; the raw value is `morphy_exception.pos`.
    /// The cases are in candidate order.
    enum PartOfSpeech: String, CaseIterable, Hashable, Sendable {
        case verb = "v", noun = "n", adjective = "a", adverb = "r"

        /// Its bit in `morphy_lemma.pos_mask`.
        var maskBit: Int {
            switch self {
            case .noun: return 1
            case .verb: return 2
            case .adjective: return 4
            case .adverb: return 8
            }
        }
    }

    /// A detachment rule: a word ending in `detach` may be a form of the
    /// word with `attach` in its place (cities: ies → y).
    struct Rule: Hashable, Sendable {
        let detach: String
        let attach: String
    }

    /// A line of WordNet's exception lists for the word: it is a form of
    /// `base` as `pos` (went: verb, go).
    struct Exception: Hashable, Sendable {
        let pos: PartOfSpeech
        let base: String
    }

    /// One lemma of the word.
    struct Analysis: Hashable, Sendable {
        let base: String
        let pos: PartOfSpeech
        /// The detachment rule that gave `base`; `nil` for an exception.
        let rule: Rule?
        /// The word's ending its caption names: "ing" for a verb, "er" or
        /// "est" for an adjective or adverb, else "".
        let suffix: String
    }

    /// WordNet's detachment rules, in its order. Adverbs have none.
    static let rules: [PartOfSpeech: [Rule]] = {
        let table: [PartOfSpeech: [(String, String)]] = [
            .noun: [("s", ""), ("ses", "s"), ("xes", "x"), ("zes", "z"), ("ches", "ch"), ("shes", "sh"),
                    ("men", "man"), ("ies", "y")],
            .verb: [("s", ""), ("ies", "y"), ("es", "e"), ("es", ""), ("ed", "e"), ("ed", ""), ("ing", "e"), ("ing", "")],
            .adjective: [("er", ""), ("est", ""), ("er", "e"), ("est", "e")],
        ]
        return table.mapValues { $0.map { Rule(detach: $0.0, attach: $0.1) } }
    }()

    /// The noise guard: a rule's noun or adjective base needs this many
    /// letters (was ↛ wa, as ↛ a, us ↛ u, has ↛ ha). Verbs keep shorter
    /// bases (goes → go).
    static let minimumNominalBaseLength = 3

    /// Every base the detachment rules give `word`, in candidate order,
    /// after the noise guard and before the lemma check.
    static func detachments(of word: String) -> [Analysis] {
        PartOfSpeech.allCases.flatMap { pos in
            (rules[pos] ?? []).compactMap { rule -> Analysis? in
                guard word.hasSuffix(rule.detach) else { return nil }
                let base = String(word.dropLast(rule.detach.count)) + rule.attach
                guard !base.isEmpty, pos == .verb || base.count >= minimumNominalBaseLength else { return nil }
                return Analysis(base: base, pos: pos, rule: rule, suffix: suffix(of: word, as: pos))
            }
        }
    }

    /// The rule bases of `word`, each once: what `morphy_lemma` is asked for.
    static func ruleBases(of word: String) -> [String] {
        var seen = Set<String>()
        return detachments(of: word).map(\.base).filter { seen.insert($0).inserted }
    }

    /// The lemmas of `token`, WordNet 3.0's morphy:
    /// 0. lowercase it (`lowercased()` ignores the locale);
    /// 1. for each part of speech in the order verb, noun, adjective,
    ///    adverb: all its `exceptions` if it has any (went → go; better →
    ///    good, well), else the first detachment rule, in `rules` order,
    ///    whose base `lemmas` (word → `pos_mask`) has for that part of speech,
    ///    as NLTK's `morphy()` takes it: hoping → hope, not hop (Kirill,
    ///    2026-11-02);
    /// 2. without the word itself and repeated bases: a base keeps its first
    ///    part of speech, so goes is the verb go's form (Kirill, 2026-11-01),
    ///    though `noun.exc` lists it as the plural of the noun go.
    static func analyses(of token: String, exceptions: [Exception], lemmas: [String: Int]) -> [Analysis] {
        let word = token.lowercased()
        let detached = detachments(of: word)
        let found = PartOfSpeech.allCases.flatMap { pos -> [Analysis] in
            let own = exceptions.filter { $0.pos == pos }
            guard own.isEmpty else {
                return own.map { Analysis(base: $0.base, pos: pos, rule: nil, suffix: suffix(of: word, as: pos)) }
            }
            let hit = detached.first { $0.pos == pos && (lemmas[$0.base] ?? 0) & pos.maskBit != 0 }
            return hit.map { [$0] } ?? []
        }
        var seen: Set<String> = [word]
        return found.filter { seen.insert($0.base).inserted }
    }

    /// The ending of `word` that its caption as `pos` names.
    private static func suffix(of word: String, as pos: PartOfSpeech) -> String {
        switch pos {
        case .verb: return word.hasSuffix("ing") ? "ing" : ""
        case .adjective, .adverb: return word.hasSuffix("est") ? "est" : word.hasSuffix("er") ? "er" : ""
        case .noun: return ""
        }
    }
}

// MARK: - DictionaryFile (Issue #140)

/// The bundled, read-only dictionary file `dictionaries.sqlite`, written by
/// `Scripts/build_dictionaries.py` and attached as `dict`.
enum DictionaryFile {
    static let resourceName = "dictionaries"
    static let resourceExtension = "sqlite"

    /// The file's `PRAGMA user_version`. The app and the file ship together,
    /// so nothing checks it at runtime; a unit test checks the bundled file.
    /// A changed table shape bumps it and `FORMAT_VERSION` in the build script.
    static let formatVersion = 3
}

// MARK: - Word forms: inflection tables (Issue #144)
//
// The Definition screen's Greek inflection tables (0136-word-forms.md,
// "Inflection tables" and "Tables (#144)"). Pure: no SQL, no SwiftUI.
// `DatabaseService.inflection(for:)` reads a `LemmaParadigm`, `ParadigmLayout`
// maps its cells to slots and builds the `InflectionTable` that
// `InflectionTableView` (DefinitionView.swift) renders.

/// One `dict.paradigm` cell: a form and its Wiktextract tag set.
struct ParadigmCell: Equatable, Sendable {
    let form: String
    let tags: Set<String>

    init(form: String, tags: Set<String>) {
        self.form = form
        self.tags = tags
    }

    /// `tags` as `dict.tagset.tags` stores them: space-separated.
    init(form: String, tags: String) {
        self.init(form: form, tags: Set(tags.split(separator: " ").map(String.init)))
    }
}

/// The table of one Greek lemma, as `DatabaseService.inflection(for:)` reads it.
struct LemmaParadigm: Equatable, Sendable {
    /// The lemma whose table this is (NFC).
    let word: String
    /// Its Wiktextract part of speech: `verb`, `noun`, `adj` or `name`.
    let pos: String
    /// The cells in table order (`dict.paradigm.ord`).
    let cells: [ParadigmCell]
    /// The entry's own lemma has no table, and this is the lemma it is an
    /// alternative or form of (πάω → πηγαίνω): the view names it under the title.
    let isLinked: Bool
}

/// Which lemma's table an entry shows ("Which table" in 0136-word-forms.md).
enum InflectionLookup {
    /// The sources whose entries get a table: Greek headwords.
    static let sources: Set<String> = ["freedict-ell-eng", "wordnet-ell-eng"]

    /// The parts of speech with a table. An entry without a `pos` tries them all.
    static let posOrder = ["verb", "noun", "adj", "name"]

    /// A `dict.lemma` row.
    struct Lemma: Equatable, Sendable {
        let id: Int64
        let word: String
        let pos: String
    }

    /// A lemma that a table-less lemma's word is a form of, and whether that
    /// lemma's table holds the word itself.
    struct Link: Equatable, Sendable {
        let lemma: Lemma
        let holdsHeadword: Bool
    }

    /// The Wiktextract parts of speech of an entry's `pos` labels, in the
    /// entry's own order, without repeats: noun → noun, adjective or
    /// adjective satellite → adj, verb → verb, proper noun → name. Other
    /// labels have no table.
    static func lemmaPOS(forEntryPOS pos: String) -> [String] {
        var result: [String] = []
        for label in pos.split(separator: ",") {
            let mapped: String?
            switch label.trimmingCharacters(in: .whitespaces).lowercased() {
            case "noun": mapped = "noun"
            case "adjective", "adjective satellite": mapped = "adj"
            case "verb": mapped = "verb"
            case "proper noun": mapped = "name"
            default: mapped = nil
            }
            if let mapped, !result.contains(mapped) { result.append(mapped) }
        }
        return result
    }

    /// How a lemma's word matches the entry's (Kirill, 2026-11-01).
    enum Match: Sendable {
        /// Spelled exactly as the headword.
        case exact
        /// The same but for case or a diaeresis: Ταύρος and ταύρος, Μάϊος and
        /// Μάιος, ΕΛΙΑ and ελιά (capitals carry no accent).
        case near
    }

    /// How `lemmaWord` matches `entryWord`, or nil when only folding makes
    /// them meet: an accent elsewhere is another word (Σόφια is not σοφία,
    /// αλκή not άλκη).
    static func match(_ lemmaWord: String, _ entryWord: String) -> Match? {
        // `==` on String is canonical equivalence, so NFC and NFD agree.
        if lemmaWord == entryWord { return .exact }
        // A word in capitals is written without accents.
        if isAllCaps(lemmaWord) || isAllCaps(entryWord) {
            return Search.foldGreek(lemmaWord) == Search.foldGreek(entryWord) ? .near : nil
        }
        return nearKey(lemmaWord) == nearKey(entryWord) ? .near : nil
    }

    private static func isAllCaps(_ word: String) -> Bool {
        word.contains(where: \.isLetter) && !word.contains(where: \.isLowercase)
    }

    /// `word` lowercase, without diaeresis, with σ for the final sigma.
    private static func nearKey(_ word: String) -> String {
        let scalars = word.lowercased().decomposedStringWithCanonicalMapping.unicodeScalars
            .filter { $0 != "\u{0308}" }
            .map { $0 == "\u{03C2}" ? "\u{03C3}" : $0 }
        return String(String.UnicodeScalarView(scalars)).precomposedStringWithCanonicalMapping
    }

    /// The lemmas of part of speech `pos` among `candidates` (the lemmas whose
    /// folded word is the entry's) that match the entry's word as `kinds`.
    static func lemmas(ofPOS pos: String, entryWord: String, candidates: [Lemma], matching kinds: Set<Match>) -> [Lemma] {
        candidates.filter { lemma in
            lemma.pos == pos && match(lemma.word, entryWord).map(kinds.contains) == true
        }
    }

    /// The table an entry shows ("Which table", Kirill, 2026-10-31 and
    /// 2026-11-01). `table` gives a lemma's table, or nil when it has none;
    /// `link` gives the table of the one lemma of a part of speech that the
    /// entry's word is a form or an alternative of, or nil for none or several.
    /// A lemma matches the word exactly or near (`Match`); one that differs in
    /// its accents never does.
    /// - An entry with parts of speech tries its labels in its own order.
    ///   1. A lemma spelled exactly as the headword, of any of its labels, comes
    ///      first; a noun label also takes the proper noun so spelled (WordNet's
    ///      noun Κίνα shows Κίνα, not κίνα).
    ///   2. Then the first label whose near lemmas have a table ("adjective,
    ///      noun": the adjective's). A noun label with no noun lemma takes the
    ///      near proper nouns of a capitalized word (Ταύρος: ταύρος, ρώμη: not
    ///      Ρώμη); a label with no lemma at all takes `link` (μέρα: ημέρα).
    ///   Several tables at one step: no table.
    /// - An entry without one shows the table when exactly one lemma of any
    ///   part of speech has one, exact lemmas first; several: no table.
    static func choose<Table: Equatable>(entryWord: String, entryPOS: String, candidates: [Lemma],
                                         table: (Lemma) throws -> Table?,
                                         link: (String) throws -> Table? = { _ in nil }) rethrows -> Table? {
        func tables(_ lemmas: [Lemma]) throws -> [Table] {
            var found: [Table] = []
            for lemma in lemmas {
                if let value = try table(lemma), !found.contains(value) { found.append(value) }
            }
            return found
        }
        func of(_ pos: String, _ kinds: Set<Match>) -> [Lemma] {
            lemmas(ofPOS: pos, entryWord: entryWord, candidates: candidates, matching: kinds)
        }
        let labels = lemmaPOS(forEntryPOS: entryPOS)
        if labels.isEmpty {
            guard entryPOS.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            for kind in [Match.exact, .near] {
                let all = try tables(posOrder.flatMap { of($0, [kind]) })
                if all.count == 1 { return all[0] }
                if all.count > 1 { return nil }
            }
            return nil
        }
        // 1. A lemma spelled as the headword beats every other.
        for pos in labels {
            for group in [of(pos, [.exact])] + (pos == "noun" ? [of("name", [.exact])] : []) {
                let found = try tables(group)
                if found.count == 1 { return found[0] }
                if found.count > 1 { return nil }
            }
        }
        // 2. Near lemmas, the proper noun, the link.
        for pos in labels {
            let own = of(pos, [.exact, .near])
            var group = of(pos, [.near])
            if own.isEmpty, pos == "noun" {
                // A near proper noun stands only for a capitalized word: ρώμη
                // (vigour) is not Ρώμη.
                group = entryWord.first?.isUppercase == true ? of("name", [.near]) : []
            }
            var found = try tables(group)
            if found.isEmpty, own.isEmpty, let linked = try link(pos) { found = [linked] }
            if found.count == 1 { return found[0] }
            if found.count > 1 { return nil }
        }
        return nil
    }

    /// The lemma whose table a table-less lemma shows: the only link, else
    /// the only one whose table holds the word itself; otherwise none.
    static func chooseLink(_ links: [Link]) -> Lemma? {
        if links.count == 1 { return links[0].lemma }
        let holding = links.filter(\.holdsHeadword)
        return holding.count == 1 ? holding[0].lemma : nil
    }

    /// Whether a linked lemma's `forms` are a table for `word`: they hold the
    /// word itself, or no form that folds like it. A form that only folds
    /// like the word is another word's (μετρό and μέτρο, συνεδρία and
    /// συνέδρια); with no such form the link comes from the word's own page
    /// (μέρα, alternative of ημέρα).
    static func linkFits(word: String, forms: [String]) -> Bool {
        let key = Search.foldGreek(word)
        return forms.contains(word) || !forms.contains { Search.foldGreek($0) == key }
    }

    /// `linkFits(word:forms:)` for a linked lemma of part of speech `pos` with
    /// `cells`, and, for a noun, adjective or proper noun whose table holds the
    /// word, the word is one of its nominatives (Kirill, 2026-11-01): καφέ is
    /// no headword form of καφές, πράγματα is one of πράγμα. Verbs link as before.
    static func linkFits(word: String, pos: String, cells: [ParadigmCell]) -> Bool {
        guard linkFits(word: word, forms: cells.map(\.form)) else { return false }
        guard pos != "verb" else { return true }
        let own = cells.filter { $0.form == word }
        return own.isEmpty || own.contains { $0.tags.contains("nominative") }
    }
}

/// A grammatical label of the tables, from the string catalog: lowercase as
/// in running text ("aorist"), or capitalized as a header ("Aorist").
enum FormLabel: String, CaseIterable, Sendable {
    case present, imperfect, aorist, future, futureContinuous, perfect, pluperfect, futurePerfect
    case subjunctive, imperative
    case continuous, simple
    case active, passive
    case presentParticiple, pastParticiple, perfectParticiple, infinitive
    case nominative, genitive, accusative, vocative
    case singular, plural
    case masculine, feminine, neuter
    case comparative, superlative

    /// The catalog key, `forms.<group>.<name>`.
    var key: String {
        let group: String
        switch self {
        case .present, .imperfect, .aorist, .future, .futureContinuous, .perfect, .pluperfect, .futurePerfect:
            group = "tense"
        case .subjunctive, .imperative: group = "mood"
        case .continuous, .simple: group = "aspect"
        case .active, .passive: group = "voice"
        case .presentParticiple, .pastParticiple, .perfectParticiple, .infinitive: group = "nonfinite"
        case .nominative, .genitive, .accusative, .vocative: group = "case"
        case .singular, .plural: group = "number"
        case .masculine, .feminine, .neuter: group = "gender"
        case .comparative, .superlative: group = "degree"
        }
        return "forms.\(group).\(rawValue)"
    }

    /// The label in the in-app language of `locale`, as in running text.
    func text(locale: Locale) -> String {
        SettingsViewModel.localizedString(key, locale: locale)
    }

    /// The label as a header or title: its first letter capitalized.
    func title(locale: Locale) -> String {
        let text = text(locale: locale)
        guard let first = text.first else { return text }
        // No locale: Greek uppercasing in `el` would drop the accent (Ά → Α).
        return String(first).uppercased() + text.dropFirst()
    }
}

/// A Greek inflection table, ready to render: sections of rows and columns
/// whose texts are already localized. Empty rows, columns and sections are
/// gone; a single missing cell has no forms and shows "—".
struct InflectionTable: Equatable {
    enum Kind: Equatable {
        case conjugation, declension
    }

    let kind: Kind
    /// The lemma whose table this is, when it is not the entry's own (πηγαίνω
    /// for πάω): shown under the title.
    let linkedLemma: String?
    let sections: [Section]

    /// The default view.
    var mainSections: [Section] { sections.filter(\.isMain) }
    /// What "All forms" adds below it.
    var moreSections: [Section] { sections.filter { !$0.isMain } }

    struct Section: Identifiable, Equatable {
        let id: String
        /// A voice heading ("Passive") over the first section of the other voice.
        let heading: String?
        /// "Imperative", "Singular", …; nil for a section that needs none.
        let title: String?
        let isMain: Bool
        /// Column headers. A section of labelled rows has one untitled column.
        let columns: [Header]
        let rows: [Row]

        var showsColumnHeaders: Bool { columns.contains { !$0.title.isEmpty } }
        var showsRowHeaders: Bool { rows.contains { $0.header != nil } }
    }

    /// A column or row header: a capitalized label, or a Greek pronoun.
    struct Header: Identifiable, Equatable {
        let id: String
        let title: String
    }

    struct Row: Identifiable, Equatable {
        let id: String
        let header: Header?
        /// One per column of the section.
        let cells: [Cell]
    }

    struct Cell: Identifiable, Equatable {
        /// The accessibility identifier, `inflection_cell_…`.
        let id: String
        /// Several forms are variants of one slot; none is a missing form.
        let forms: [String]
        /// "aorist, εγώ, έγραψα": column, row, form. Greek runs carry the `el`
        /// language attribute, so VoiceOver speaks them with the Greek voice.
        let accessibilityLabel: AttributedString

        static let missing = "—"

        var text: String { forms.isEmpty ? Self.missing : forms.joined(separator: " / ") }
        /// `text` broken after each slash, one form per line, for a narrow grid.
        var stackedText: String { forms.count > 1 ? forms.joined(separator: " /\n") : text }
        var accessibilityText: String { String(accessibilityLabel.characters) }
    }
}

/// Maps a lemma's cells to the slots of its table and builds the localized
/// `InflectionTable` (0136-word-forms.md, "Tables (#144)"). Periphrastic forms
/// (θα, να, έχω, είχα, έχοντας + a form) are generated here, never stored.
enum ParadigmLayout {

    /// The table of `paradigm` in the in-app language of `locale`, or nil
    /// when no cell fits a slot (the screen then shows no table).
    static func table(for paradigm: LemmaParadigm, locale: Locale) -> InflectionTable? {
        let labels = Labels(locale: locale)
        let isVerb = paradigm.pos == "verb"
        let sections: [InflectionTable.Section]
        switch paradigm.pos {
        case "verb": sections = conjugation(paradigm.cells, labels: labels)
        case "adj": sections = adjectiveDeclension(paradigm.cells, labels: labels)
        case "noun", "name": sections = nounDeclension(paradigm.cells, labels: labels)
        default: sections = []
        }
        guard !sections.isEmpty else { return nil }
        return InflectionTable(kind: isVerb ? .conjugation : .declension,
                               linkedLemma: paradigm.isLinked ? paradigm.word : nil,
                               sections: sections)
    }

    /// Whether `paradigm` has any cell that fits a slot, i.e. would show a table.
    static func hasTable(_ paradigm: LemmaParadigm) -> Bool {
        table(for: paradigm, locale: Locale(identifier: "en")) != nil
    }

    /// Cells tagged so are hidden from tables; they stay searchable.
    static let hiddenTags: Set<String> = ["rare", "archaic", "dated"]

    // MARK: Persons and voices

    enum Voice: String, CaseIterable, Sendable {
        case active, passive

        var label: FormLabel { self == .active ? .active : .passive }
    }

    /// A person and number, the row of a verb table.
    enum Person: String, CaseIterable, Sendable {
        case firstSingular = "1sg", secondSingular = "2sg", thirdSingular = "3sg"
        case firstPlural = "1pl", secondPlural = "2pl", thirdPlural = "3pl"

        /// The row label: a Greek pronoun, never translated.
        var pronoun: String {
            ["εγώ", "εσύ", "αυτός", "εμείς", "εσείς", "αυτοί"][index]
        }

        /// The perfect's auxiliary (έχω γράψει).
        var have: String {
            ["έχω", "έχεις", "έχει", "έχουμε", "έχετε", "έχουν"][index]
        }

        /// The pluperfect's auxiliary (είχα γράψει).
        var had: String {
            ["είχα", "είχες", "είχε", "είχαμε", "είχατε", "είχαν"][index]
        }

        private var index: Int { Self.allCases.firstIndex(of: self) ?? 0 }

        /// The person of a cell tagged with one person and one number.
        init?(tags: Set<String>) {
            let persons = ["first-person", "second-person", "third-person"]
            let found = persons.indices.filter { tags.contains(persons[$0]) }
            let singular = tags.contains("singular"), plural = tags.contains("plural")
            guard found.count == 1, singular != plural else { return nil }
            self = Self.allCases[found[0] + (plural ? 3 : 0)]
        }
    }

    // MARK: Verb slots

    /// A finite slot read from the cells.
    enum FiniteSlot: Hashable, Sendable {
        case present, imperfect, aorist, dependent, imperativeContinuous, imperativeSimple
    }

    /// A nonfinite slot. The perfect participle is generated.
    enum NonfiniteSlot: String, CaseIterable, Sendable {
        case presentParticiple = "present_participle"
        case pastParticiple = "past_participle"
        case perfectParticiple = "perfect_participle"
        case infinitive

        var label: FormLabel {
            switch self {
            case .presentParticiple: return .presentParticiple
            case .pastParticiple: return .pastParticiple
            case .perfectParticiple: return .perfectParticiple
            case .infinitive: return .infinitive
            }
        }
    }

    enum VerbSlot: Hashable, Sendable {
        case finite(FiniteSlot, Person)
        case nonfinite(NonfiniteSlot)
    }

    private static let caseTags = ["nominative", "genitive", "accusative", "vocative"]
    private static let genderTags = ["masculine", "feminine", "neuter"]

    /// The voice and slot of a verb cell, or nil for a hidden cell or one
    /// that matches no slot:
    /// - voice: `passive` → passive, otherwise active;
    /// - present: `present`, indicative or with no mood, not `dependent`; imperfect:
    ///   `imperfect`; aorist: `past perfective`; dependent: `dependent`;
    /// - imperative continuous/simple: `imperative` with
    ///   `imperfective`/`perfective`, 2sg and 2pl only;
    /// - aorist infinitive: `infinitive-aorist`;
    /// - participles: `participle` with `present`, or in the passive with
    ///   `past` or `perfect` (γραμμένος); a declined participle only as its
    ///   nominative masculine singular.
    static func verbSlot(of tags: Set<String>) -> (voice: Voice, slot: VerbSlot)? {
        guard tags.isDisjoint(with: hiddenTags) else { return nil }
        let voice: Voice = tags.contains("passive") ? .passive : .active
        if tags.contains("infinitive-aorist") { return (voice, .nonfinite(.infinitive)) }
        if tags.contains("participle") {
            let declined = !tags.isDisjoint(with: caseTags + genderTags + ["singular", "plural"])
            if declined, !tags.isSuperset(of: ["nominative", "masculine", "singular"]) { return nil }
            if tags.contains("present") { return (voice, .nonfinite(.presentParticiple)) }
            if voice == .passive, tags.contains("past") || tags.contains("perfect") {
                return (voice, .nonfinite(.pastParticiple))
            }
            return nil
        }
        guard let person = Person(tags: tags) else { return nil }
        if tags.contains("imperative") {
            guard person == .secondSingular || person == .secondPlural else { return nil }
            if tags.contains("imperfective") { return (voice, .finite(.imperativeContinuous, person)) }
            if tags.contains("perfective") { return (voice, .finite(.imperativeSimple, person)) }
            return nil
        }
        if tags.contains("dependent") { return (voice, .finite(.dependent, person)) }
        if tags.contains("imperfect") { return (voice, .finite(.imperfect, person)) }
        if tags.isSuperset(of: ["past", "perfective"]) { return (voice, .finite(.aorist, person)) }
        // Wiktionary's present-only template (πρόκειται, οφείλω, αφορά) tags
        // its cells `present` with no mood.
        if tags.contains("present"), tags.isDisjoint(with: Self.nonIndicativeMoods) {
            return (voice, .finite(.present, person))
        }
        return nil
    }

    /// Moods whose present is no indicative present.
    private static let nonIndicativeMoods: Set<String> = ["subjunctive", "optative", "conditional"]

    /// The forms of one voice by slot, in table order, without repeats.
    struct VoiceForms: Equatable {
        private(set) var finite: [FiniteSlot: [Person: [String]]] = [:]
        private(set) var nonfinite: [NonfiniteSlot: [String]] = [:]

        var isEmpty: Bool { finite.isEmpty && nonfinite.isEmpty }

        mutating func add(_ form: String, to slot: VerbSlot) {
            switch slot {
            case let .finite(finiteSlot, person):
                var forms = finite[finiteSlot, default: [:]][person, default: []]
                if !forms.contains(form) { forms.append(form) }
                finite[finiteSlot, default: [:]][person] = forms
            case let .nonfinite(nonfiniteSlot):
                var forms = nonfinite[nonfiniteSlot, default: []]
                if !forms.contains(form) { forms.append(form) }
                nonfinite[nonfiniteSlot] = forms
            }
        }

        func forms(_ slot: FiniteSlot, _ person: Person) -> [String] {
            finite[slot]?[person] ?? []
        }

        func forms(_ slot: NonfiniteSlot) -> [String] {
            nonfinite[slot] ?? []
        }

        /// The persons with a finite form. The periphrastic perfects are
        /// built only for them: προκύπτει has no εγώ, so no "έχω προκύψει".
        var persons: Set<Person> {
            Set(finite.values.flatMap { $0.filter { !$0.value.isEmpty }.keys })
        }

        // Generated forms, one per variant of the source cell.

        /// θα + dependent: θα γράψω.
        func future(_ person: Person) -> [String] { forms(.dependent, person).map { "θα " + $0 } }
        /// θα + present: θα γράφω.
        func futureContinuous(_ person: Person) -> [String] { forms(.present, person).map { "θα " + $0 } }
        /// να + present: να γράφω.
        func subjunctiveContinuous(_ person: Person) -> [String] { forms(.present, person).map { "να " + $0 } }
        /// να + dependent: να γράψω.
        func subjunctiveSimple(_ person: Person) -> [String] { forms(.dependent, person).map { "να " + $0 } }
        /// έχω + aorist infinitive: έχω γράψει.
        func perfect(_ person: Person) -> [String] {
            guard persons.contains(person) else { return [] }
            return forms(.infinitive).map { person.have + " " + $0 }
        }
        /// είχα + aorist infinitive: είχα γράψει.
        func pluperfect(_ person: Person) -> [String] {
            guard persons.contains(person) else { return [] }
            return forms(.infinitive).map { person.had + " " + $0 }
        }
        /// θα + perfect: θα έχω γράψει.
        func futurePerfect(_ person: Person) -> [String] { perfect(person).map { "θα " + $0 } }
        /// έχοντας + aorist infinitive: έχοντας γράψει.
        var perfectParticiple: [String] { forms(.infinitive).map { "έχοντας " + $0 } }
    }

    /// The forms of each voice that has any.
    static func voiceForms(_ cells: [ParadigmCell]) -> [Voice: VoiceForms] {
        var voices: [Voice: VoiceForms] = [:]
        for cell in cells {
            guard let match = verbSlot(of: cell.tags) else { continue }
            voices[match.voice, default: VoiceForms()].add(cell.form, to: match.slot)
        }
        return voices
    }

    /// The main voice: active, or passive when the verb has no active present
    /// and a passive one (deponents such as έρχομαι).
    static func mainVoice(_ voices: [Voice: VoiceForms]) -> Voice {
        let hasPresent = { (voice: Voice) in
            Person.allCases.contains { !(voices[voice]?.forms(.present, $0).isEmpty ?? true) }
        }
        return !hasPresent(.active) && hasPresent(.passive) ? .passive : .active
    }

    // MARK: Conjugation

    /// A column of a verb grid: its id slug, header, the labels VoiceOver
    /// reads before the row, and its forms per person.
    private struct VerbColumn {
        let slug: String
        let header: FormLabel
        let spoken: [FormLabel]
        let forms: (Person) -> [String]

        init(_ slug: String, _ header: FormLabel, spoken: [FormLabel]? = nil, _ forms: @escaping (Person) -> [String]) {
            self.slug = slug
            self.header = header
            self.spoken = spoken ?? [header]
            self.forms = forms
        }
    }

    /// The verb sections: the main voice's default view (Present, Imperfect,
    /// Aorist, Future; the imperative), then under "All forms" the rest of
    /// the main voice and everything of the other voice.
    static func conjugation(_ cells: [ParadigmCell], labels: Labels) -> [InflectionTable.Section] {
        let voices = voiceForms(cells)
        let main = mainVoice(voices)
        var sections: [InflectionTable.Section] = []
        if let forms = voices[main] {
            sections += voiceSections(forms, voice: main, isMainVoice: true, labels: labels)
        }
        let other: Voice = main == .active ? .passive : .active
        if let forms = voices[other], !forms.isEmpty {
            var otherSections = voiceSections(forms, voice: other, isMainVoice: false, labels: labels)
            if let first = otherSections.first {
                otherSections[0] = InflectionTable.Section(
                    id: first.id, heading: other.label.title(locale: labels.locale), title: first.title,
                    isMain: false, columns: first.columns, rows: first.rows)
            }
            sections += otherSections
        }
        // A verb with nothing for the default view shows all it has at once.
        if !sections.contains(where: \.isMain) {
            sections = sections.map {
                InflectionTable.Section(id: $0.id, heading: $0.heading, title: $0.title, isMain: true,
                                        columns: $0.columns, rows: $0.rows)
            }
        }
        return sections
    }

    private static func voiceSections(_ forms: VoiceForms, voice: Voice, isMainVoice: Bool,
                                      labels: Labels) -> [InflectionTable.Section] {
        let present = VerbColumn("present", .present) { forms.forms(.present, $0) }
        let imperfect = VerbColumn("imperfect", .imperfect) { forms.forms(.imperfect, $0) }
        let aorist = VerbColumn("aorist", .aorist) { forms.forms(.aorist, $0) }
        let future = VerbColumn("future", .future) { forms.future($0) }
        let futureContinuous = VerbColumn("future_continuous", .futureContinuous) { forms.futureContinuous($0) }
        let perfect = VerbColumn("perfect", .perfect) { forms.perfect($0) }
        let pluperfect = VerbColumn("pluperfect", .pluperfect) { forms.pluperfect($0) }
        let futurePerfect = VerbColumn("future_perfect", .futurePerfect) { forms.futurePerfect($0) }
        let imperative = [
            VerbColumn("imperative_continuous", .continuous, spoken: [.imperative, .continuous]) {
                forms.forms(.imperativeContinuous, $0)
            },
            VerbColumn("imperative_simple", .simple, spoken: [.imperative, .simple]) {
                forms.forms(.imperativeSimple, $0)
            },
        ]
        let subjunctive = [
            VerbColumn("subjunctive_continuous", .continuous, spoken: [.subjunctive, .continuous]) {
                forms.subjunctiveContinuous($0)
            },
            VerbColumn("subjunctive_simple", .simple, spoken: [.subjunctive, .simple]) {
                forms.subjunctiveSimple($0)
            },
        ]
        // The other voice is named before each cell; the main voice is not.
        let prefix = isMainVoice ? nil : voice.label
        let persons = Person.allCases
        let imperativePersons: [Person] = [.secondSingular, .secondPlural]
        let v = voice.rawValue
        // Both voices have the same shape: four tenses, the imperative, four
        // more tenses. For the main voice the first two are the default view.
        let sections: [InflectionTable.Section?] = [
            verbGrid(id: "\(v)_indicative", title: nil, isMain: isMainVoice, voice: voice, prefix: prefix,
                     columns: [present, imperfect, aorist, future], persons: persons, labels: labels),
            verbGrid(id: "\(v)_imperative", title: labels.title(.imperative), isMain: isMainVoice, voice: voice,
                     prefix: prefix, columns: imperative, persons: imperativePersons, labels: labels),
            verbGrid(id: "\(v)_more", title: nil, isMain: false, voice: voice, prefix: prefix,
                     columns: [futureContinuous, perfect, pluperfect, futurePerfect], persons: persons, labels: labels),
            verbGrid(id: "\(v)_subjunctive", title: labels.title(.subjunctive), isMain: false,
                     voice: voice, prefix: prefix, columns: subjunctive, persons: persons, labels: labels),
            nonfiniteSection(forms, voice: voice, prefix: prefix, labels: labels),
        ]
        return sections.compactMap { $0 }
    }

    /// Persons × columns, without empty rows and columns.
    private static func verbGrid(id: String, title: String?, isMain: Bool, voice: Voice, prefix: FormLabel?,
                                 columns: [VerbColumn], persons: [Person],
                                 labels: Labels) -> InflectionTable.Section? {
        let filled = columns.filter { column in persons.contains { !column.forms($0).isEmpty } }
        let rows = persons.filter { person in filled.contains { !$0.forms(person).isEmpty } }
        guard !filled.isEmpty, !rows.isEmpty else { return nil }
        return InflectionTable.Section(
            id: id, heading: nil, title: title, isMain: isMain,
            columns: filled.map { InflectionTable.Header(id: $0.slug, title: labels.title($0.header)) },
            rows: rows.map { person in
                InflectionTable.Row(
                    id: person.rawValue,
                    header: InflectionTable.Header(id: person.rawValue, title: person.pronoun),
                    cells: filled.map { column in
                        // "aorist, εγώ, έγραψα"; the other voice first names itself.
                        let spoken = (prefix.map { [$0] } ?? []) + column.spoken
                        return labels.cell(
                            id: "inflection_cell_\(voice.rawValue)_\(column.slug)_\(person.rawValue)",
                            forms: column.forms(person),
                            labels: spoken.map { labels.text($0) },
                            greek: [person.pronoun])
                    })
            })
    }

    /// Participles and the aorist infinitive: labelled rows, one column.
    private static func nonfiniteSection(_ forms: VoiceForms, voice: Voice, prefix: FormLabel?,
                                         labels: Labels) -> InflectionTable.Section? {
        let rows: [InflectionTable.Row] = NonfiniteSlot.allCases.compactMap { slot in
            let values = slot == .perfectParticiple ? forms.perfectParticiple : forms.forms(slot)
            guard !values.isEmpty else { return nil }
            let spoken = (prefix.map { [$0] } ?? []) + [slot.label]
            return InflectionTable.Row(
                id: slot.rawValue,
                header: InflectionTable.Header(id: slot.rawValue, title: labels.title(slot.label)),
                cells: [labels.cell(id: "inflection_cell_\(voice.rawValue)_\(slot.rawValue)", forms: values,
                                    labels: spoken.map { labels.text($0) }, greek: [])])
        }
        guard !rows.isEmpty else { return nil }
        return InflectionTable.Section(id: "\(voice.rawValue)_nonfinite", heading: nil,
                                       title: labels.nonfiniteTitle, isMain: false,
                                       columns: [InflectionTable.Header(id: "form", title: "")], rows: rows)
    }

    // MARK: Declension

    static let cases: [FormLabel] = [.nominative, .genitive, .accusative, .vocative]
    static let numbers: [FormLabel] = [.singular, .plural]
    static let genders: [FormLabel] = [.masculine, .feminine, .neuter]

    /// The one label of `options` among `tags`, or nil for none or several.
    private static func single(_ options: [FormLabel], in tags: Set<String>) -> FormLabel? {
        let found = options.filter { tags.contains($0.rawValue) }
        return found.count == 1 ? found[0] : nil
    }

    private static func isDegree(_ tags: Set<String>) -> Bool {
        tags.contains("comparative") || tags.contains("superlative")
    }

    /// Forms by key, in table order, without repeats.
    private struct Slots<Key: Hashable> {
        private(set) var forms: [Key: [String]] = [:]

        mutating func add(_ form: String, at key: Key) {
            var values = forms[key, default: []]
            if !values.contains(form) { values.append(form) }
            forms[key] = values
        }

        subscript(key: Key) -> [String] { forms[key] ?? [] }
    }

    private struct NominalKey: Hashable {
        let grammaticalCase: FormLabel
        let number: FormLabel
        let gender: FormLabel?
    }

    /// Nouns: case × number. Gender tags are ignored.
    static func nounDeclension(_ cells: [ParadigmCell], labels: Labels) -> [InflectionTable.Section] {
        var slots = Slots<NominalKey>()
        for cell in cells where cell.tags.isDisjoint(with: hiddenTags) && !isDegree(cell.tags) {
            guard let grammaticalCase = single(cases, in: cell.tags),
                  let number = single(numbers, in: cell.tags) else { continue }
            slots.add(cell.form, at: NominalKey(grammaticalCase: grammaticalCase, number: number, gender: nil))
        }
        let section = nominalGrid(id: "declension", title: nil, columns: numbers, labels: labels) { row, column in
            NominalKey(grammaticalCase: row, number: column, gender: nil)
        } forms: { slots[$0] }
        return [section].compactMap { $0 }
    }

    /// Adjectives: case × gender, one block for the singular and one for the
    /// plural, then the comparative and superlative. Only cells without a
    /// degree tag fill the blocks, so a lemma that keeps only its degree
    /// tables (γόνιμος) shows no positive grid.
    static func adjectiveDeclension(_ cells: [ParadigmCell], labels: Labels) -> [InflectionTable.Section] {
        var slots = Slots<NominalKey>()
        var degrees = Slots<FormLabel>()
        for cell in cells where cell.tags.isDisjoint(with: hiddenTags) {
            if isDegree(cell.tags) {
                if let degree = degree(of: cell) { degrees.add(cell.form, at: degree) }
                continue
            }
            guard let grammaticalCase = single(cases, in: cell.tags),
                  let number = single(numbers, in: cell.tags),
                  let gender = single(genders, in: cell.tags) else { continue }
            slots.add(cell.form, at: NominalKey(grammaticalCase: grammaticalCase, number: number, gender: gender))
        }
        var sections = numbers.map { number in
            nominalGrid(id: number.rawValue, title: labels.title(number), columns: genders, labels: labels) { row, column in
                NominalKey(grammaticalCase: row, number: number, gender: column)
            } forms: { slots[$0] }
        }
        let degreeRows: [InflectionTable.Row] = [FormLabel.comparative, .superlative].compactMap { degree in
            let values = degrees[degree]
            guard !values.isEmpty else { return nil }
            return InflectionTable.Row(
                id: degree.rawValue,
                header: InflectionTable.Header(id: degree.rawValue, title: labels.title(degree)),
                cells: [labels.cell(id: "inflection_cell_\(degree.rawValue)", forms: values,
                                    labels: [labels.text(degree)], greek: [])])
        }
        if !degreeRows.isEmpty {
            sections.append(InflectionTable.Section(id: "degrees", heading: nil, title: nil, isMain: true,
                                                    columns: [InflectionTable.Header(id: "form", title: "")],
                                                    rows: degreeRows))
        }
        return sections.compactMap { $0 }
    }

    /// The degree of an adjective cell, for its nominative masculine singular
    /// only. The snapshot tags every degree cell both `comparative` and
    /// `superlative`; then a form in -τερος is the comparative (ωραιότερος,
    /// καλύτερος) and any other the superlative (ωραιότατος, μέγιστος).
    static func degree(of cell: ParadigmCell) -> FormLabel? {
        guard cell.tags.isSuperset(of: ["nominative", "masculine", "singular"]) else { return nil }
        switch (cell.tags.contains("comparative"), cell.tags.contains("superlative")) {
        case (true, false): return .comparative
        case (false, true): return .superlative
        case (true, true): return Search.foldGreek(cell.form).hasSuffix("τεροσ") ? .comparative : .superlative
        case (false, false): return nil
        }
    }

    /// Cases × `columns`, without empty rows and columns.
    private static func nominalGrid(id: String, title: String?, columns: [FormLabel], labels: Labels,
                                    key: (FormLabel, FormLabel) -> NominalKey,
                                    forms: (NominalKey) -> [String]) -> InflectionTable.Section? {
        let filled = columns.filter { column in cases.contains { !forms(key($0, column)).isEmpty } }
        let rows = cases.filter { row in filled.contains { !forms(key(row, $0)).isEmpty } }
        guard !filled.isEmpty, !rows.isEmpty else { return nil }
        return InflectionTable.Section(
            id: id, heading: nil, title: title, isMain: true,
            columns: filled.map { InflectionTable.Header(id: $0.rawValue, title: labels.title($0)) },
            rows: rows.map { row in
                InflectionTable.Row(
                    id: row.rawValue,
                    header: InflectionTable.Header(id: row.rawValue, title: labels.title(row)),
                    cells: filled.map { column in
                        let slot = key(row, column)
                        // "genitive, singular[, masculine], καλού"; the id
                        // names the case, the number, then the gender.
                        let spoken = [slot.grammaticalCase, slot.number] + (slot.gender.map { [$0] } ?? [])
                        return labels.cell(id: "inflection_cell_" + spoken.map(\.rawValue).joined(separator: "_"),
                                           forms: forms(slot), labels: spoken.map { labels.text($0) }, greek: [])
                    })
            })
    }

    // MARK: Labels

    /// The localized texts of one table.
    struct Labels {
        let locale: Locale

        func text(_ label: FormLabel) -> String { label.text(locale: locale) }
        func title(_ label: FormLabel) -> String { label.title(locale: locale) }

        var nonfiniteTitle: String { SettingsViewModel.localizedString("forms.section.nonfinite", locale: locale) }
        var noForm: String { SettingsViewModel.localizedString("forms.a11y.noForm", locale: locale) }

        /// Arabic joins the spoken parts with the Arabic comma.
        var separator: String { locale.language.languageCode?.identifier == "ar" ? "\u{060C} " : ", " }

        /// A cell whose VoiceOver label reads `labels`, then the `greek` parts
        /// (the pronoun), then its forms, or "no form".
        func cell(id: String, forms: [String], labels: [String], greek: [String]) -> InflectionTable.Cell {
            var parts: [(text: String, isGreek: Bool)] = labels.map { ($0, false) } + greek.map { ($0, true) }
            parts.append(forms.isEmpty ? (noForm, false) : (forms.joined(separator: " / "), true))
            var label = AttributedString()
            for (index, part) in parts.enumerated() {
                if index > 0 { label += AttributedString(separator) }
                var run = AttributedString(part.text)
                if part.isGreek { run.languageIdentifier = "el" }
                label += run
            }
            return InflectionTable.Cell(id: id, forms: forms, accessibilityLabel: label)
        }
    }
}

// MARK: - DictMetadata

/// One `dict.dict_metadata` row: a bundled dictionary (Issue #138).
struct DictMetadata: Codable, Identifiable, Equatable, FetchableRecord {
    var source: String
    var displayName: String
    var version: String
    var license: String
    var url: String
    var wordCount: Int
    var description: String

    var id: String { source }

    enum CodingKeys: String, CodingKey {
        case source
        case displayName = "display_name"
        case version
        case license
        case url
        case wordCount = "word_count"
        case description
    }
}

// MARK: - SourceStat (lightweight per-source count)

struct SourceStat: Identifiable, Hashable {
    var id: String { source }
    let source: String
    let displayName: String
    let count: Int
    /// From `dict_metadata` (Issue #92); `""` for custom imports, which have
    /// no metadata row. Defaulted so the memberwise init stays source-compatible.
    var license: String = ""
    var version: String = ""

    /// Provider name derived from the source ID (`wordnet`, `freedict`, …);
    /// the raw ID for custom imports. See `DictionaryGrouping.parse(sourceID:)`.
    var provider: String { DictionaryGrouping.parse(sourceID: source).provider }

    /// Translation direction (ISO-639-3) for bilingual bundled sources;
    /// `nil` for monolingual and custom sources.
    var direction: (from: String, to: String)? {
        let languages = DictionaryGrouping.parse(sourceID: source).languages
        guard languages.count == 2 else { return nil }
        return (from: languages[0], to: languages[1])
    }
}

// MARK: - DictionaryPair (Issue #92)

/// A language pair as shown on the Dictionary Order screen: one row, one
/// toggle, one drag slot. Bundled sources that serve the same pair of
/// languages in either direction (e.g. `freedict-eng-spa` and
/// `wordnet-spa-eng`) share one pair; monolingual and custom sources are
/// single-member pairs. `sources` is the #91 detail-view API: each member
/// exposes provider / direction / license / version on its own.
struct DictionaryPair: Identifiable, Hashable {
    /// Pair key from `DictionaryGrouping.pairKey(forSource:)`
    /// (`eng`, `eng-spa`, `custom:<id>`). Runtime-only, never persisted.
    let id: String
    /// ISO-639-3 codes, sorted; empty for custom sources.
    let languages: [String]
    let isCustom: Bool
    /// Underlying sources in canonical (user-order) order.
    let sources: [SourceStat]

    var sourceIDs: [String] { sources.map(\.source) }
    var count: Int { sources.reduce(0) { $0 + $1.count } }
}

// MARK: - DictionaryItem (Settings UI model with enabled state)

/// One row of the Dictionary Order screen (Issue #92: pair-level). `Hashable`
/// for `navigationDestination(item:)` (Issue #91).
struct DictionaryItem: Identifiable, Hashable {
    var id: String { pair.id }
    let pair: DictionaryPair
    /// Localised row title, resolved by `SettingsViewModel.displayName(for:locale:)`.
    let displayName: String
    var isEnabled: Bool

    /// Summed entry count across the pair's sources.
    var count: Int { pair.count }
}

// MARK: - Word lists (0130, #151)
//
// 0130-word-lists.md, "Swift": one model for the built-in lists (the
// `wordlist` tables of the dictionary files, 0237), My words (0129's
// `my_words`) and imported lists (`user_list`), the order new words come
// in, and the linking rules. Pure: the SQL is in `DatabaseService`.

/// A word list's permanent id: a built-in list's (`ky-ell-a1` …
/// `cefr-eng-c2`), `my-words`, or `user-<uuid>` for an imported list.
/// User data stores it as text, never a row id.
struct WordListID: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(stringLiteral value: String) {
        self.init(rawValue: value)
    }

    static let myWords = WordListID(rawValue: "my-words")

    var kind: WordList.Kind {
        if self == .myWords { return .myWords }
        return rawValue.hasPrefix("user-") ? .user : .builtIn
    }
}

/// One list, as the Lists screen shows it.
struct WordList: Identifiable, Hashable, Sendable {
    enum Kind: String, Hashable, Sendable {
        case builtIn, myWords, user
    }

    /// My words holds words of every language.
    static let myWordsLanguage = "mul"

    let id: WordListID
    let kind: Kind
    /// ISO 639-3; `und` for Other, `mul` for My words.
    let lang: String
    /// A built-in list's level, `A1` … `C2`; empty for My words and imports.
    let level: String
    /// An imported list's name. Empty for built-in lists and My words, whose
    /// titles the views compose and translate (#154).
    let title: String
    /// Its words: a built-in list's `word_count`, My words' keys, an import's rows.
    let count: Int
}

/// One word of a list. `wordlist_item` and `user_list_item` share their
/// columns, so one function decodes both (`DatabaseService`).
struct WordListItem: Identifiable, Hashable, Sendable {
    /// The list it was read from.
    let listID: WordListID
    /// `WordKey(lang: list language, word: term)`; for My words, the
    /// source's language and the entry's word.
    let key: WordKey
    /// As the list writes it (NFC).
    let term: String
    /// The dictionary headword its Definition opens; nil for a standalone word.
    let headword: String?
    /// The list's translation; may be empty (the English lists, My words).
    let translation: String
    let endings: String
    let partOfSpeech: String
    let tags: String
    let level: String
    /// 1 … 6 = A1 … C2; an import's other level names 7, 8, …; 0 = none.
    let levelOrder: Int
    /// Frequency rank; nil = unranked.
    let rank: Int?
    /// Order in the list's source file (My words: order added).
    let seq: Int
    /// The alphabetical key (`sortKey(of:)`).
    let sortKey: String

    /// A key appears once per list, and once in `nextNewWords`.
    var id: WordKey { key }

    /// The alphabetical key of a term (0130, "List data"): without its
    /// parenthesised parts and punctuation, Greek folded as `Search.foldGreek`
    /// (`normalize_greek`), other scripts lowercased without diacritics.
    /// `build_wordlists.py` writes the same (NFD, combining marks dropped),
    /// so "(ένα) σωρό" sorts under σ and `árbol` with `arbol`.
    static func sortKey(of term: String) -> String {
        let text = String(String.UnicodeScalarView(
            ListLinking.withoutParentheses(term).unicodeScalars.filter { !isPunctuation($0) }))
        let folded = Search.foldGreek(text).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return ListLinking.collapsingWhitespace(folded)
    }

    private static func isPunctuation(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
             .initialPunctuation, .finalPunctuation, .otherPunctuation:
            return true
        default:
            return false
        }
    }
}

/// The order new words come in within a level (the setting is E4's).
enum NewWordOrder: String, CaseIterable, Hashable, Sendable {
    case frequency, random
}

/// "Order of new words" (0130): the order of the items of one language's
/// checked lists. Levels in order across the lists (A1 first, words without
/// a level last), each word once at its lowest level; within a level by
/// frequency with a light shuffle, or shuffled. Deterministic for a seed.
enum LearningOrder {
    /// Places shuffled together in frequency order: the 10 most frequent
    /// words stay in the first 10, the 20 most frequent in the first 20.
    static let window = 10

    /// The arrangement's seed: FNV-1a 64 of "installSeed|ids|order", with
    /// the ids of that language's checked lists sorted and comma-joined, so
    /// checking a list of another language leaves the order unchanged.
    /// Swift's `Hasher` changes per launch, so it cannot be used.
    static func seed(installSeed: UInt64, lists: some Sequence<WordListID>, order: NewWordOrder) -> UInt64 {
        let ids = lists.map(\.rawValue).sorted().joined(separator: ",")
        return fnv1a64("\(installSeed)|\(ids)|\(order.rawValue)")
    }

    /// FNV-1a, 64 bits, over the UTF-8 bytes of `text`.
    static func fnv1a64(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
        }
        return hash
    }

    /// SplitMix64: a small generator whose sequence never changes with the
    /// platform.
    struct SplitMix64: RandomNumberGenerator {
        private var state: UInt64

        init(seed: UInt64) {
            state = seed
        }

        mutating func next() -> UInt64 {
            state &+= 0x9e37_79b9_7f4a_7c15
            var z = state
            z = (z ^ (z >> 30)) &* 0xbf58_476d_1ce4_e5b9
            z = (z ^ (z >> 27)) &* 0x94d0_49bb_1331_11eb
            return z ^ (z >> 31)
        }
    }

    /// The order of `items`, the words of one language's checked lists in
    /// Lists screen order, each list in its own order (`seq`):
    /// 1. one item per key: the lowest level (none counts as the highest),
    ///    then the first list;
    /// 2. levels ascending, words without a level (0) last;
    /// 3. frequency: ranked words by rank, then unranked words in their
    ///    lists' order; each run of 10 places shuffled; then the neighbour
    ///    pass (`separateNeighbours`). Random: the level shuffled.
    static func arrange(_ items: [WordListItem], order: NewWordOrder, seed: UInt64) -> [WordListItem] {
        var generator = SplitMix64(seed: seed)
        return levels(of: unique(items)).flatMap { words -> [WordListItem] in
            var level = words
            switch order {
            case .random:
                shuffle(&level, level.indices, using: &generator)
            case .frequency:
                level = byFrequency(level)
                for start in stride(from: 0, to: level.count, by: window) {
                    shuffle(&level, start..<min(start + window, level.count), using: &generator)
                }
                separateNeighbours(inLevel: &level)
            }
            return level
        }
    }

    /// The neighbour pass over `items` in their order, one level (a run of
    /// one `levelOrder`) at a time, with runs of 10 counted from the level's
    /// first place. A word followed by the next word of its level in
    /// alphabetical order (`sortKey`, then `term`) swaps places with it;
    /// when the pair straddles two runs, the first two words of the later run
    /// swap instead, so no word leaves its run. A swap never creates such a
    /// pair behind the pass, so one pass is enough: afterwards no word is
    /// followed by its alphabetical neighbour, except into a last run of one
    /// word. `DatabaseService.nextNewWords` runs it again once enrolled
    /// words drop out.
    static func separateNeighbours(_ items: [WordListItem]) -> [WordListItem] {
        var result: [WordListItem] = []
        result.reserveCapacity(items.count)
        var start = items.startIndex
        while start < items.endIndex {
            var end = start + 1
            while end < items.endIndex && items[end].levelOrder == items[start].levelOrder { end += 1 }
            var level = Array(items[start..<end])
            separateNeighbours(inLevel: &level)
            result += level
            start = end
        }
        return result
    }

    /// `levelOrder` as a sort key: no level (0) after every level.
    static func levelRank(_ item: WordListItem) -> Int {
        item.levelOrder == 0 ? .max : item.levelOrder
    }

    /// One item per key, in input order: the one with the lowest level, then the first.
    private static func unique(_ items: [WordListItem]) -> [WordListItem] {
        var kept: [WordKey: Int] = [:]
        for (index, item) in items.enumerated() {
            if let other = kept[item.key], levelRank(items[other]) <= levelRank(item) { continue }
            kept[item.key] = index
        }
        let indices = Set(kept.values)
        return items.indices.filter(indices.contains).map { items[$0] }
    }

    /// The levels, ascending, each in input order.
    private static func levels(of items: [WordListItem]) -> [[WordListItem]] {
        Dictionary(grouping: items, by: levelRank).sorted { $0.key < $1.key }.map(\.value)
    }

    /// Ranked words by rank, then unranked words; ties keep their order.
    private static func byFrequency(_ level: [WordListItem]) -> [WordListItem] {
        level.enumerated().sorted { a, b in
            switch (a.element.rank, b.element.rank) {
            case let (x?, y?) where x != y: return x < y
            case (.some, .none): return true
            case (.none, .some): return false
            default: return a.offset < b.offset
            }
        }.map(\.element)
    }

    /// Fisher–Yates over `range`. Its own, so an order never changes with the
    /// standard library's shuffle.
    private static func shuffle(_ items: inout [WordListItem], _ range: Range<Int>, using generator: inout SplitMix64) {
        guard range.count > 1 else { return }
        for i in stride(from: range.upperBound - 1, to: range.lowerBound, by: -1) {
            let j = range.lowerBound + Int(generator.next() % UInt64(i - range.lowerBound + 1))
            items.swapAt(i, j)
        }
    }

    /// The neighbour pass over one level (`separateNeighbours(_:)`).
    private static func separateNeighbours(inLevel level: inout [WordListItem]) {
        guard level.count > 1 else { return }
        // Each place's word's position in the level's alphabetical order.
        var alphabetical = [Int](repeating: 0, count: level.count)
        let sorted = level.indices.sorted {
            (level[$0].sortKey, level[$0].term, $0) < (level[$1].sortKey, level[$1].term, $1)
        }
        for (position, index) in sorted.enumerated() { alphabetical[index] = position }
        for i in 0..<(level.count - 1) where alphabetical[i] + 1 == alphabetical[i + 1] {
            if i / window == (i + 1) / window {
                level.swapAt(i, i + 1)
                alphabetical.swapAt(i, i + 1)
            } else if i + 2 < level.count {
                level.swapAt(i + 1, i + 2)
                alphabetical.swapAt(i + 1, i + 2)
            }
        }
    }
}

/// "Linking a word to the dictionaries" (0130): the rules that link a list
/// word to a headword of a dictionary in the list's language. The first
/// rule that finds exactly one headword wins:
/// 1. exact: the term is a headword (SQLite `NOCASE`, which folds only A–Z);
/// 2. cleaned: each of `cleanedVariants(of:)` is a headword;
/// 3. near (Greek): the term or a cleaned variant is a headword but for case
///    and diaeresis, accents kept (`InflectionLookup.match`, #144); of
///    several near headwords the one equal to the lowercased spelling, else
///    none;
/// 4. form, one word only, the term or a cleaned variant: Greek, the lemmas
///    whose table holds its exact spelling, when exactly one of them is a
///    headword; English, the bases of its WordNet exception lines in
///    Morphy's order (verb, noun, adj, adv), the first that is a headword.
/// An accent-folded match alone never links (νομός is not νόμος).
/// `build_wordlists.py` implements the same rules in Python.
enum ListLinking {
    enum Rule: String, Hashable, Sendable {
        case exact, cleaned, near, form
    }

    struct Link: Hashable, Sendable {
        let headword: String
        let rule: Rule
    }

    /// The dictionary reads of one language that linking needs.
    /// `DatabaseService` reads them; tests pass made-up data.
    struct Lookup {
        /// The headwords spelled as the string, SQLite `NOCASE`.
        var headwords: (String) throws -> [String]
        /// At least every headword that folds like the string
        /// (`Search.foldGreek`), with as many scalars: the near candidates.
        var nearCandidates: (String) throws -> [String]
        /// The lemmas a one-word string is a form of, headwords or not:
        /// Greek, those whose table holds its exact spelling; English, the
        /// bases of its exception lines in Morphy's order.
        var formLemmas: (String) throws -> [String]
    }

    /// The link of `term`, a word of a list in `lang`, or nil for a
    /// standalone word.
    static func link(_ term: String, lang: String, lookup: Lookup) throws -> Link? {
        if let headword = try headword(among: lookup.headwords(term), spelledAs: term) {
            return Link(headword: headword, rule: .exact)
        }
        let variants = cleanedVariants(of: term)
        for variant in variants {
            if let headword = try headword(among: lookup.headwords(variant), spelledAs: variant) {
                return Link(headword: headword, rule: .cleaned)
            }
        }
        let spellings = ([term] + variants).filter { $0.contains(where: \.isLetter) }
        if lang == "ell" {
            for spelling in spellings {
                if let headword = try near(spelling, among: lookup.nearCandidates(spelling)) {
                    return Link(headword: headword, rule: .near)
                }
            }
        }
        guard lang == "ell" || lang == "eng" else { return nil }
        for spelling in spellings where isOneWord(spelling) {
            var found: [String] = []
            for lemma in try lookup.formLemmas(spelling) {
                guard let headword = try headword(among: lookup.headwords(lemma), spelledAs: lemma),
                      !found.contains(where: { sameHeadword($0, headword) }) else { continue }
                found.append(headword)
                // English takes the first; Greek needs exactly one.
                if lang == "eng" { break }
            }
            if found.count == 1 { return Link(headword: found[0], rule: .form) }
        }
        return nil
    }

    /// The cleaned spellings of `term`, in the order rule 2 tries them,
    /// without `term` itself, empty ones and repeats:
    /// 1. without trailing `! ? ; .`, and without the quotes and guillemets
    ///    around it (`Ευχαριστώ!` → Ευχαριστώ, `«ναι»` → ναι);
    /// 2. that, without its parenthesised parts (`(Σαουδική) Αραβία` → Αραβία);
    /// 3. that, with the parentheses removed (`Σαουδική Αραβία`).
    static func cleanedVariants(of term: String) -> [String] {
        let stripped = strippingPunctuation(term)
        let candidates = [
            stripped,
            collapsingWhitespace(withoutParentheses(stripped)),
            collapsingWhitespace(stripped.filter { $0 != "(" && $0 != ")" }),
        ]
        var variants: [String] = []
        for variant in candidates where !variant.isEmpty && variant != term && !variants.contains(variant) {
            variants.append(variant)
        }
        return variants
    }

    /// Whether `headword` is near `spelling` (rule 3): the same but for case
    /// or a diaeresis, as #144's `InflectionLookup.match` decides it.
    static func isNear(_ headword: String, _ spelling: String) -> Bool {
        InflectionLookup.match(headword, spelling) != nil
    }

    /// One word: letters without whitespace.
    static func isOneWord(_ spelling: String) -> Bool {
        !spelling.isEmpty && !spelling.contains(where: \.isWhitespace)
    }

    /// `text` without its parenthesised parts; an unclosed one runs to the end.
    static func withoutParentheses(_ text: String) -> String {
        var depth = 0
        var result = ""
        for character in text {
            switch character {
            case "(": depth += 1
            case ")": depth = max(0, depth - 1)
            default: if depth == 0 { result.append(character) }
            }
        }
        return result
    }

    /// `text` trimmed, with each run of whitespace as one space.
    static func collapsingWhitespace(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static let trailingMarks: Set<Character> = ["!", "?", ";", "."]
    private static let quotes: Set<Character> = ["\"", "\u{201C}", "\u{201D}", "\u{201E}", "«", "»", "‹", "›"]
    private static let singleQuotes: Set<Character> = ["'", "\u{2018}", "\u{2019}"]

    /// `term` trimmed, without trailing `! ? ; .` (the Greek question mark
    /// is `;` in NFC), without the double quotes and guillemets at either
    /// end, and without single quotes that wrap it (an apostrophe of
    /// elision, σ', stays).
    private static func strippingPunctuation(_ term: String) -> String {
        var text = Substring(term)
        while true {
            let before = text
            while let last = text.last, last.isWhitespace || trailingMarks.contains(last) || quotes.contains(last) {
                text.removeLast()
            }
            while let first = text.first, first.isWhitespace || quotes.contains(first) {
                text.removeFirst()
            }
            if text.count > 1, let first = text.first, let last = text.last,
               singleQuotes.contains(first), singleQuotes.contains(last) {
                text = text.dropFirst().dropLast()
            }
            if text == before { return String(text) }
        }
    }

    /// The headword of exact matches of `spelling`: they are one headword
    /// under `NOCASE`, so the one spelled as `spelling` if any, else the
    /// first in code point order; nil for none.
    private static func headword(among headwords: [String], spelledAs spelling: String) -> String? {
        headwords.first { $0 == spelling } ?? headwords.min()
    }

    /// The near headword of `spelling` among `candidates` (rule 3).
    private static func near(_ spelling: String, among candidates: [String]) -> String? {
        var near: [String] = []
        for candidate in candidates where isNear(candidate, spelling) && !near.contains(candidate) {
            near.append(candidate)
        }
        if near.count == 1 { return near[0] }
        let lowercased = spelling.lowercased()
        return near.first { $0 == lowercased }
    }

    /// Two headwords that `NOCASE` takes for one.
    private static func sameHeadword(_ a: String, _ b: String) -> Bool {
        WordKey(lang: "", word: a).word == WordKey(lang: "", word: b).word
    }
}
