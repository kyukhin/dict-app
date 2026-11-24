#!/usr/bin/env python3
"""
drill_cells.py
The cells of the Greek conjugation drill: every (verb, facet, person) the
drill can ask (docs/specs/0134-example-sentences.md, "Drill examples",
Cells; docs/specs/0132-conjugation-drill.md). `build_examples.py` gives each
cell one sentence (#364).

A port of the app's rules, with the Swift names, so the build's cell list is
exactly the drill's:
  - `verb_slot` and `VoiceForms` are `ParadigmLayout.verbSlot(of:)` and
    `ParadigmLayout.VoiceForms` (Models.swift);
  - `ConjugationTense.forms`, `DrillLevel.facets(mainVoice:hasPassive:)`,
    `DrillVerb.make`, `DrillVerb.droppingSharedPassives` and
    `ConjugationQuestionBuilder.questions(verb:level:)` (Learning.swift);
  - `drill_verbs` is `DatabaseService.drillVerbs(lists:meaningsLang:)` over
    the three Greek lists, with its link rule (`linkedLemmasSQL`,
    `InflectionLookup.chooseLink`, `linkFits`).

The Swift unit tests `DrillExampleDataTests.testCellKeysAreDrillCells` and
`testSpansHoldTheCellsForm` read the committed Greek pack with the app's own
pool, so a drift between the two fails them.

A cell's key is `<word>|<facet>|<person>` in NFC (0132's `DrillExampleKey`):
`κάνω|imperativeSimple.active|2sg`.

Usage (from the repository root): the cell counts of a full or Greek file,
    python3 Scripts/drill_cells.py path/to/dictionaries-full.sqlite
"""

from __future__ import annotations

import collections
import os
import sqlite3
import sys
import unicodedata
from dataclasses import dataclass, field

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_greek import normalize_greek  # noqa: E402  (`Search.foldGreek`)

SERIES = "ky-ell"  # `DrillScope.series`
LISTS = ("ky-ell-a1", "ky-ell-a2", "ky-ell-b1")  # `DrillScope.lists`, in level order

# `ParadigmLayout.Person`, in table order.
PERSONS = ("1sg", "2sg", "3sg", "1pl", "2pl", "3pl")
HAVE = dict(zip(PERSONS, ("έχω", "έχεις", "έχει", "έχουμε", "έχετε", "έχουν")))
HAD = dict(zip(PERSONS, ("είχα", "είχες", "είχε", "είχαμε", "είχατε", "είχαν")))
ACTIVE, PASSIVE = "active", "passive"

# `ConjugationTense.allCases`, the tables' order.
TENSES = ("present", "imperfect", "aorist", "future", "imperativeContinuous", "imperativeSimple",
          "futureContinuous", "perfect", "pluperfect", "futurePerfect", "subjunctiveContinuous",
          "subjunctiveSimple")
# `DrillLevel`.
LEVELS = ("A1", "A2", "B1", "B2")
DISTRACTORS = 3  # `ConjugationQuestionBuilder.distractorCount`

HIDDEN_TAGS = frozenset({"rare", "archaic", "dated"})
CASE_TAGS = ("nominative", "genitive", "accusative", "vocative")
GENDER_TAGS = ("masculine", "feminine", "neuter")
NON_INDICATIVE_MOODS = frozenset({"subjunctive", "optative", "conditional"})

# `DrillVerb.noImperative` (#362): the card words of the verbs the drill
# never asks, offers or shows an imperative, in either voice. The same 83
# words as the Swift set; `testNoImperativeMatchesThePythonPort` fails on a
# drift.
NO_IMPERATIVE = frozenset(unicodedata.normalize("NFC", word) for word in """
    θέλω μπορώ αρέσω νομίζω σημαίνω απορώ
    υπάρχω αρκώ μοιάζω κοστίζω διαρκώ λήγω αποτελώ αντιστοιχώ περισσεύω κατοικώ
    πεινάω διψάω πονάω αρρωσταίνω νυστάζω κρυώνω πεθαίνω
    ξημερώνω
    επιθυμώ ελπίζω ενδιαφέρω συμπαθώ φοβάμαι χρειάζομαι νευριάζω τρελαίνομαι
    λείπω περιλαμβάνω
    παθαίνω πνίγομαι γεννάω αργώ καταφέρνω
    αστράφτω
    εννοώ ανησυχώ βαριέμαι απελπίζομαι αγχώνομαι ενοχλώ αισιοδοξώ
    αξίζω ανήκω χρωστάω διαφέρω εξαρτώμαι αποτελούμαι προέρχομαι συμβολίζω χωράω
    ιδρώνω αιμορραγώ ζαλίζομαι χασμουριέμαι γερνάω σαπίζω αναρρώνω κουράζομαι
    γεννιέμαι κινδυνεύω φταίω βρομάω
    δύω πνέω
    ακούγομαι συνεχίζομαι δημιουργούμαι συμπεριλαμβάνομαι αναπτύσσομαι παράγομαι
    βραβεύομαι εκδηλώνομαι συζητιέμαι καταστρέφομαι διατηρούμαι παρασκευάζομαι
    θεραπεύομαι
    """.split())
IMPERATIVES = frozenset({"imperativeContinuous", "imperativeSimple"})


def nfc(s: str) -> str:
    return unicodedata.normalize("NFC", s)


def swift_lower(s: str) -> str:
    """Swift's `lowercased()`: scalar by scalar, so a final Σ gives σ, not ς."""
    return "".join(ch.lower() for ch in s)


def fold(form: str) -> str:
    """`ConjugationQuestionBuilder.fold`: lowercased, NFD without nonspacing
    marks, ς as σ."""
    return "".join(c for c in unicodedata.normalize("NFD", swift_lower(form))
                   if unicodedata.category(c) != "Mn").replace("ς", "σ")


def list_word(term: str) -> str:
    """`DrillVerb.listWord`: without parenthesised parts and punctuation,
    lowercased, in NFC, its words joined by one space."""
    depth, kept = 0, []
    for ch in swift_lower(nfc(term)):
        if ch == "(":
            depth += 1
            continue
        if ch == ")":
            depth = max(depth - 1, 0)
            continue
        if depth == 0 and not unicodedata.category(ch).startswith("P"):
            kept.append(ch)
    return " ".join("".join(kept).split())


# ---------------------------------------------------------------------------
# ParadigmLayout: slots and voice forms (Models.swift)
# ---------------------------------------------------------------------------

def person_of(tags: frozenset[str]) -> str | None:
    """`Person(tags:)`: one person and one number."""
    found = [i for i, p in enumerate(("first-person", "second-person", "third-person")) if p in tags]
    singular, plural = "singular" in tags, "plural" in tags
    if len(found) != 1 or singular == plural:
        return None
    return PERSONS[found[0] + (3 if plural else 0)]


def verb_slot(tags: frozenset[str]) -> tuple[str, tuple] | None:
    """`ParadigmLayout.verbSlot(of:)`: (voice, ("finite", slot, person)) or
    (voice, ("nonfinite", slot)); None for a hidden cell or no slot."""
    if tags & HIDDEN_TAGS:
        return None
    voice = PASSIVE if "passive" in tags else ACTIVE
    if "infinitive-aorist" in tags:
        return voice, ("nonfinite", "infinitive")
    if "participle" in tags:
        declined = not tags.isdisjoint(CASE_TAGS + GENDER_TAGS + ("singular", "plural"))
        if declined and not {"nominative", "masculine", "singular"} <= tags:
            return None
        if "present" in tags:
            return voice, ("nonfinite", "presentParticiple")
        if voice == PASSIVE and ("past" in tags or "perfect" in tags):
            return voice, ("nonfinite", "pastParticiple")
        return None
    person = person_of(tags)
    if person is None:
        return None
    if "imperative" in tags:
        if person not in ("2sg", "2pl"):
            return None
        if "imperfective" in tags:
            return voice, ("finite", "imperativeContinuous", person)
        if "perfective" in tags:
            return voice, ("finite", "imperativeSimple", person)
        return None
    if "dependent" in tags:
        return voice, ("finite", "dependent", person)
    if "imperfect" in tags:
        return voice, ("finite", "imperfect", person)
    if {"past", "perfective"} <= tags:
        return voice, ("finite", "aorist", person)
    if "present" in tags and tags.isdisjoint(NON_INDICATIVE_MOODS):
        return voice, ("finite", "present", person)
    return None


@dataclass
class VoiceForms:
    """`ParadigmLayout.VoiceForms`: the forms of one voice by slot, in table
    order, without repeats. Equal as the Swift struct is."""
    finite: dict = field(default_factory=dict)  # slot -> person -> [form]
    nonfinite: dict = field(default_factory=dict)  # slot -> [form]

    def add(self, form: str, slot: tuple) -> None:
        if slot[0] == "finite":
            forms = self.finite.setdefault(slot[1], {}).setdefault(slot[2], [])
        else:
            forms = self.nonfinite.setdefault(slot[1], [])
        if form not in forms:
            forms.append(form)

    def forms(self, slot: str, person: str | None = None) -> list[str]:
        if person is None:
            return self.nonfinite.get(slot, [])
        return self.finite.get(slot, {}).get(person, [])

    @property
    def persons(self) -> set[str]:
        return {p for by_person in self.finite.values() for p, forms in by_person.items() if forms}

    def has(self, slot: str) -> bool:
        return any(self.forms(slot, p) for p in PERSONS)

    # Generated forms (#144).
    def future(self, p: str) -> list[str]:
        return ["θα " + f for f in self.forms("dependent", p)]

    def future_continuous(self, p: str) -> list[str]:
        return ["θα " + f for f in self.forms("present", p)]

    def subjunctive_continuous(self, p: str) -> list[str]:
        return ["να " + f for f in self.forms("present", p)]

    def subjunctive_simple(self, p: str) -> list[str]:
        return ["να " + f for f in self.forms("dependent", p)]

    def perfect(self, p: str) -> list[str]:
        return [HAVE[p] + " " + f for f in self.forms("infinitive")] if p in self.persons else []

    def pluperfect(self, p: str) -> list[str]:
        return [HAD[p] + " " + f for f in self.forms("infinitive")] if p in self.persons else []

    def future_perfect(self, p: str) -> list[str]:
        return ["θα " + f for f in self.perfect(p)]


def voice_forms(cells: list[tuple[str, frozenset[str]]]) -> dict[str, VoiceForms]:
    """`ParadigmLayout.voiceForms`: the forms of each voice that has any."""
    voices: dict[str, VoiceForms] = {}
    for form, tags in cells:
        match = verb_slot(tags)
        if match:
            voices.setdefault(match[0], VoiceForms()).add(form, match[1])
    return voices


def main_voice(voices: dict[str, VoiceForms]) -> str:
    """`ParadigmLayout.mainVoice`: passive when there is no active present
    and a passive one."""
    def has_present(voice: str) -> bool:
        return voice in voices and voices[voice].has("present")
    return PASSIVE if not has_present(ACTIVE) and has_present(PASSIVE) else ACTIVE


# ---------------------------------------------------------------------------
# Tenses, facets, levels (Learning.swift)
# ---------------------------------------------------------------------------

def tense_persons(tense: str) -> tuple[str, ...]:
    """`ConjugationTense.persons`."""
    return ("2sg", "2pl") if tense.startswith("imperative") else PERSONS


def lacks_dependent(voice: VoiceForms) -> bool:
    """`ConjugationTense.lacksDependent`: a present and no dependent form."""
    return voice.has("present") and not voice.has("dependent")


def tense_forms(tense: str, voice: VoiceForms, person: str, lacks: bool) -> list[str]:
    """`ConjugationTense.forms(_:_:lacksDependent:)`."""
    if tense in ("present", "imperfect", "aorist", "imperativeContinuous", "imperativeSimple"):
        return voice.forms(tense, person)
    if tense == "future":
        return voice.future_continuous(person) if lacks else voice.future(person)
    if tense == "subjunctiveSimple":
        return voice.subjunctive_continuous(person) if lacks else voice.subjunctive_simple(person)
    if tense == "futureContinuous":
        return [] if lacks else voice.future_continuous(person)
    if tense == "subjunctiveContinuous":
        return [] if lacks else voice.subjunctive_continuous(person)
    if tense == "perfect":
        return voice.perfect(person)
    if tense == "pluperfect":
        return voice.pluperfect(person)
    return voice.future_perfect(person)  # futurePerfect


def main_level(tense: str, voice: str) -> int:
    """`DrillLevel.mainLevel(of:voice:)`, as an index of `LEVELS`."""
    level = {"present": 0, "aorist": 0, "future": 0, "subjunctiveSimple": 0, "imperativeSimple": 0,
             "imperfect": 2, "futureContinuous": 2, "subjunctiveContinuous": 2, "imperativeContinuous": 2,
             "perfect": 3, "pluperfect": 3, "futurePerfect": 3}[tense]
    return max(level, 1) if voice == PASSIVE else level


def passive_level(tense: str) -> int:
    """`DrillLevel.passiveLevel(of:)`."""
    return {"present": 1, "futureContinuous": 2, "subjunctiveContinuous": 2}.get(tense, 3)


Facet = tuple  # (tense, voice): `ConjugationFacet`


def facet_raw(facet: Facet) -> str:
    """`ConjugationFacet.rawValue`: `<tense>.<voice>`."""
    return f"{facet[0]}.{facet[1]}"


def level_facets(level: int, main: str, has_passive: bool) -> list[Facet]:
    """`DrillLevel.facets(mainVoice:hasPassive:)`."""
    result = [(t, main) for t in TENSES if main_level(t, main) <= level]
    if main == ACTIVE and has_passive:
        result += [(t, PASSIVE) for t in TENSES if passive_level(t) <= level]
    return result


# ---------------------------------------------------------------------------
# DrillVerb (Learning.swift)
# ---------------------------------------------------------------------------

@dataclass
class Cell:
    forms: list[str]  # in table order; the first is the one offered
    keys: list[str]  # each form folded


class DrillVerb:
    def __init__(self, word: str, citation: str, list_level: int | None, rank: int | None, seq: int,
                 main: str, voices: dict[str, VoiceForms], impersonal: bool):
        self.word, self.citation = word, citation
        self.list_level, self.rank, self.seq = list_level, rank, seq
        self.main, self.voices, self.impersonal = main, voices, impersonal
        self.cells: dict[Facet, dict[str, Cell]] = {}
        asks_imperative = word not in NO_IMPERATIVE  # #362
        for voice, vf in voices.items():
            lacks = lacks_dependent(vf)
            for tense in TENSES:
                if not asks_imperative and tense in IMPERATIVES:
                    continue
                for person in tense_persons(tense):
                    if impersonal and person != "3sg":
                        continue
                    forms = tense_forms(tense, vf, person, lacks)
                    if forms:
                        self.cells.setdefault((tense, voice), {})[person] = Cell(forms, [fold(f) for f in forms])

    @property
    def has_passive(self) -> bool:
        return self.main == ACTIVE and PASSIVE in self.voices

    def cell(self, facet: Facet, person: str) -> Cell | None:
        return self.cells.get(facet, {}).get(person)

    def facet_level(self, facet: Facet) -> int:
        """The tense level that adds `facet` for this verb (an index of `LEVELS`)."""
        return main_level(facet[0], facet[1]) if facet[1] == self.main else passive_level(facet[0])


def facets_of(verb: DrillVerb, level: int) -> list[Facet]:
    """`ConjugationQuestionBuilder.facets(of:level:)`: in the voices drilled."""
    return [f for f in level_facets(level, verb.main, verb.has_passive) if f[1] in verb.voices]


def outside(facets: list[Facet], voice: str) -> list[Facet]:
    return [(t, voice) for t in TENSES if (t, voice) not in facets]


class AskRule:
    """`ConjugationQuestionBuilder.AskRule`."""

    def __init__(self, verb: DrillVerb, level: int):
        self.verb, self.level_facets = verb, facets_of(verb, level)
        self.cited = ("present", verb.main)
        self.cited_person = "3sg" if verb.impersonal else "1sg"
        self._keys: dict[str, set[str]] = {}

    def builds(self, facet: Facet, person: str) -> bool:
        if self.verb.impersonal and person != "3sg":
            return False
        if facet == self.cited and person == self.cited_person:
            return False
        cell = self.verb.cell(facet, person)
        if cell is None:
            return False
        candidates = self.keys(facet[1])
        if len(candidates) >= len(cell.keys) + DISTRACTORS:
            return True
        return len(candidates) - len(set(cell.keys) & candidates) >= DISTRACTORS

    def keys(self, voice: str) -> set[str]:
        if voice not in self._keys:
            self._keys[voice] = {c.keys[0] for f in self.level_facets + outside(self.level_facets, voice)
                                 for p in PERSONS if (c := self.verb.cell(f, p))}
        return self._keys[voice]


def questions(verb: DrillVerb, level: int = 3) -> list[tuple[Facet, list[str]]]:
    """`ConjugationQuestionBuilder.questions(verb:level:)`."""
    rule = AskRule(verb, level)
    out = []
    for facet in rule.level_facets:
        persons = [p for p in tense_persons(facet[0]) if rule.builds(facet, p)]
        if persons:
            out.append((facet, persons))
    return out


def has_question(verb: DrillVerb, level: int = 3) -> bool:
    rule = AskRule(verb, level)
    return any(rule.builds(f, p) for f in rule.level_facets for p in tense_persons(f[0]))


def third_person(list_term: str, voice: VoiceForms | None) -> str | None:
    """`DrillVerb.thirdPerson(listTerm:_:)`."""
    if voice is None:
        return None
    given = list_word(list_term)
    return next((f for f in voice.forms("present", "3sg") if list_word(f) == given), None)


def is_plain_form(list_term: str, verb: DrillVerb) -> bool:
    """`DrillVerb.isPlainForm(listTerm:of:)`."""
    main = verb.voices.get(verb.main)
    if third_person(list_term, main) is not None:
        return False
    given = list_word(list_term)
    return any(list_word(f) == given for f in [verb.citation] + (main.forms("present", "1sg") if main else []))


@dataclass
class Paradigm:
    """`LemmaParadigm`."""
    word: str
    pos: str
    cells: list[tuple[str, frozenset[str]]]
    linked: bool


def make(word: str, paradigm: Paradigm, list_level: int | None = None, rank: int | None = None, seq: int = 0,
         list_term: str | None = None) -> DrillVerb | None:
    """`DrillVerb.make(word:paradigm:translation:listLevel:rank:seq:listTerm:)`."""
    if paradigm.pos != "verb":
        return None
    word = nfc(word)
    every = voice_forms(paradigm.cells)
    linked_voices = set()
    if paradigm.linked:
        for form, tags in paradigm.cells:
            match = verb_slot(tags)
            if form == word and match and match[1][0] == "finite":
                linked_voices.add(match[0])
    voices: dict[str, VoiceForms] = {}
    if not paradigm.linked or ACTIVE in linked_voices:
        key = paradigm.word
        main = main_voice(every)
        if main in every:
            voices[main] = every[main]
        if main == ACTIVE and PASSIVE in every and every[PASSIVE].has("present"):
            voices[PASSIVE] = every[PASSIVE]
        active_persons = every[ACTIVE].persons if ACTIVE in every else set()
        passive = every.get(PASSIVE)
        if main == ACTIVE and list_term is not None and passive is not None and active_persons \
                and active_persons <= {"3sg", "3pl"} \
                and any(list_word(f) == list_word(list_term) for f in passive.forms("present", "1sg")):
            main = PASSIVE
            voices = {PASSIVE: passive}
    elif PASSIVE in linked_voices:
        key, main = word, PASSIVE
        voices = {PASSIVE: every[PASSIVE]} if PASSIVE in every else {}
    else:
        return None
    persons = voices[main].persons if main in voices else set()
    impersonal = bool(persons) and persons <= {"3sg", "3pl"}
    cited = None
    if main in voices:
        cited = next(iter(voices[main].forms("present", "3sg" if impersonal else "1sg")), None)
    if list_term is not None:
        given = third_person(list_term, voices.get(main))
        if given is not None:
            impersonal, cited = True, given
    verb = DrillVerb(key, cited or key, list_level, rank, seq, main, voices, impersonal)
    return verb if has_question(verb) else None


def dropping_shared_passives(verbs: list[DrillVerb]) -> list[DrillVerb]:
    """`DrillVerb.droppingSharedPassives`: an active verb drops its passive
    when a verb of the pool drills that same passive as its own."""
    own: dict[str, list[VoiceForms]] = {}
    for verb in verbs:
        if verb.main == PASSIVE and PASSIVE in verb.voices:
            passive = verb.voices[PASSIVE]
            own.setdefault(next(iter(passive.forms("present", "1sg")), ""), []).append(passive)
    if not own:
        return verbs
    result = []
    for verb in verbs:
        passive = verb.voices.get(PASSIVE)
        if not (verb.has_passive and passive is not None
                and passive in own.get(next(iter(passive.forms("present", "1sg")), ""), [])):
            result.append(verb)
            continue
        active = DrillVerb(verb.word, verb.citation, verb.list_level, verb.rank, verb.seq, verb.main,
                           {v: f for v, f in verb.voices.items() if v == ACTIVE}, verb.impersonal)
        if has_question(active):
            result.append(active)
    return result


# ---------------------------------------------------------------------------
# The pool (DatabaseService.drillVerbs)
# ---------------------------------------------------------------------------

LINKED_LEMMAS_SQL = """
    SELECT id, word, pos, holds_headword FROM (
        SELECT l.id, l.word, l.pos,
               EXISTS (SELECT 1 FROM paradigm h WHERE h.lemma_id = l.id AND h.form = ?) AS holds_headword,
               EXISTS (SELECT 1 FROM form_link k WHERE k.form = ? AND k.lemma_id = l.id) AS spells_link
        FROM form_lookup f JOIN lemma l ON l.id = f.lemma_id
        WHERE f.form_norm = ? AND f.lemma_id <> ? AND l.pos = ?
          AND EXISTS (SELECT 1 FROM paradigm p WHERE p.lemma_id = l.id)
    )
    WHERE holds_headword OR spells_link
    ORDER BY word
    """

ITEMS_SQL = """
    SELECT COALESCE(i.headword, i.term) AS word, i.term, i.level_ord, i.rank, i.seq,
           l.id AS lemma_id, l.word AS lemma_word,
           EXISTS (SELECT 1 FROM paradigm p WHERE p.lemma_id = l.id) AS has_cells,
           EXISTS (SELECT 1 FROM lemma o
                   WHERE o.lang = 'ell' AND o.word = COALESCE(i.headword, i.term) AND o.pos <> 'verb') AS other_pos
    FROM wordlist_item i
    LEFT JOIN lemma l ON l.lang = 'ell' AND l.word = COALESCE(i.headword, i.term) AND l.pos = 'verb'
    WHERE i.series = ? AND i.level_ord IN ({levels})
    """

NO_RANK = sys.maxsize


def choose_link(links: list[tuple]) -> tuple | None:
    """`InflectionLookup.chooseLink`: the only link, else the only one whose
    table holds the word."""
    if len(links) == 1:
        return links[0]
    holding = [link for link in links if link[3]]
    return holding[0] if len(holding) == 1 else None


def link_fits(word: str, forms: list[str]) -> bool:
    """`InflectionLookup.linkFits` for a verb."""
    key = normalize_greek(word)
    return word in forms or not any(normalize_greek(f) == key for f in forms)


def drill_verbs(reader: sqlite3.Connection, lists: tuple[str, ...] = LISTS) -> list[DrillVerb]:
    """The drill's pool over `lists`, in the app's order."""
    marks = ",".join("?" * len(lists))
    levels = sorted(level for (level,) in reader.execute(
        f"SELECT level_ord FROM wordlist WHERE id IN ({marks}) AND series = ?", (*lists, SERIES)))
    if not levels:
        return []
    items = [row for row in reader.execute(ITEMS_SQL.format(levels=",".join("?" * len(levels))), (SERIES, *levels))
             if row[5] is not None or not row[8]]
    items.sort(key=lambda r: (r[2], NO_RANK if r[3] is None else r[3], r[4]))

    tables: dict[str, tuple[int, str, bool]] = {}  # word -> (lemma id, lemma word, linked)
    looked = set()
    for word, _, _, _, _, lemma_id, lemma_word, has_cells, _ in items:
        if word in looked:
            continue
        looked.add(word)
        if lemma_id is not None and has_cells:
            tables[word] = (lemma_id, lemma_word, False)
            continue
        links = reader.execute(LINKED_LEMMAS_SQL, (word, word, normalize_greek(word),
                                                   -1 if lemma_id is None else lemma_id, "verb")).fetchall()
        chosen = choose_link(links)
        if chosen:
            tables[word] = (chosen[0], chosen[1], True)

    tags: dict[int, frozenset[str]] = {i: frozenset(t for t in s.split(" ") if t)
                                       for i, s in reader.execute("SELECT id, tags FROM tagset")}
    cells: dict[int, list[tuple[str, frozenset[str]]]] = collections.defaultdict(list)
    ids = sorted({t[0] for t in tables.values()})
    for start in range(0, len(ids), 500):
        chunk = ids[start:start + 500]
        for lemma_id, form, tagset_id in reader.execute(
                f"SELECT lemma_id, form, tagset_id FROM paradigm WHERE lemma_id IN ({','.join('?' * len(chunk))}) "
                "ORDER BY lemma_id, ord", chunk):
            cells[lemma_id].append((form, tags.get(tagset_id, frozenset())))

    verbs: list[DrillVerb] = []
    known: dict[str, tuple[int, bool]] = {}
    for word, term, level, rank, seq, _, _, _, _ in items:
        table = tables.get(word)
        if table is None or not cells.get(table[0]):
            continue
        lemma_id, lemma_word, linked = table
        if linked and not link_fits(word, [f for f, _ in cells[lemma_id]]):
            continue
        verb = make(word, Paradigm(lemma_word, "verb", cells[lemma_id], linked), level, rank, seq, term)
        if verb is None:
            continue
        plain = is_plain_form(term, verb)
        if verb.word in known:
            position, was_plain = known[verb.word]
            if not plain or was_plain:
                continue
            verbs[position] = verb
            known[verb.word] = (position, True)
        else:
            known[verb.word] = (len(verbs), plain)
            verbs.append(verb)
    verbs.sort(key=lambda v: (NO_RANK if v.list_level is None else v.list_level,
                              NO_RANK if v.rank is None else v.rank, v.seq))
    return dropping_shared_passives(verbs)


# ---------------------------------------------------------------------------
# The cells
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class DrillCell:
    key: str  # `<word>|<facet>|<person>`, NFC
    verb: str  # the card's word
    tense: str
    voice: str
    person: str
    forms: tuple[str, ...]  # `DrillVerb.forms(facet, person)`, the first one offered
    verb_level: int  # the list: 1 A1, 2 A2, 3 B1
    tense_level: int  # the tense level that adds the facet: 0 A1 … 3 B2
    main_voice: bool  # the verb's main voice (else the passive of a verb with both)

    @property
    def facet(self) -> str:
        return f"{self.tense}.{self.voice}"


def cell_key(word: str, facet: Facet, person: str) -> str:
    """0132's `DrillExampleKey.word(verb:facet:person:)`."""
    return nfc(f"{word}|{facet_raw(facet)}|{person}")


def drill_cells(reader: sqlite3.Connection) -> tuple[list[DrillVerb], list[DrillCell]]:
    """The pool and every cell `questions(verb:level: .b2)` lists, in pool order."""
    pool = drill_verbs(reader)
    cells = []
    for verb in pool:
        for facet, persons in questions(verb, LEVELS.index("B2")):
            for person in persons:
                cells.append(DrillCell(cell_key(verb.word, facet, person), verb.word, facet[0], facet[1], person,
                                       tuple(verb.cell(facet, person).forms), verb.list_level,
                                       verb.facet_level(facet), facet[1] == verb.main))
    return pool, cells


def main() -> int:
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    reader = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
    pool, cells = drill_cells(reader)
    print("verbs per list:", dict(sorted(collections.Counter(v.list_level for v in pool).items())), "total", len(pool))
    print("cells:", len(cells), "per list and tense level:",
          dict(sorted(collections.Counter((c.verb_level, LEVELS[c.tense_level]) for c in cells).items())))
    return 0


if __name__ == "__main__":
    sys.exit(main())
