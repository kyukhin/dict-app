#!/usr/bin/env python3
"""
build_grammar.py
The grammar reference, a static data step of `build_dictionaries.py`
(docs/specs/0133-grammar.md, "Topic files" and "Build step"). Its DDL is
`grammar_schema.sql`, which the unit tests read too.

Sources: `Scripts/data/grammar/<explain_lang>/<topic id>.md`, one Markdown
file per topic and explanation language (ISO 639-3 directory names: `eng`,
`rus`). The top-level files (README, checklist, review drafts) are not
topics. A file is front matter (`key: value` lines between `---` lines,
lists comma-separated) and a body of a fixed shape: `# Title`; the rule
(paragraphs and `- ` lists); one to three tables, each a ```forms block or
a pipe table, optionally after a caption line in bold; `## Examples` (3 to
5 items: a Greek line, then its translation on the indented next line);
`## Watch out` (1 or 2 items).

The step:
  1. reads every topic file (NFC) and parses it;
  2. renders each ```forms block from `lemma`, `paradigm` and `tagset`
     (`build_forms.py`) into a pipe table, after a comment with its
     parameters, which the app skips and the cross-check test reads:
         <!-- forms words=γράφω,διαβάζω tense=aorist voice=active -->
         <!-- forms words=δρόμος,Αθήνα pos=noun,name rows=nominative.singular,accusative.singular -->
         <!-- forms words=καλός pos=adj genders=masculine,feminine,neuter rows=nominative.singular,… -->
     A verb table has one voice (`voice`, else the words' common main voice)
     and the persons as rows; a nominal table has the (case.number) rows
     and one `pos` per word (noun, else a proper noun; adj with `genders`).
     A block without a caption line before it gets one: its `title`, else
     the tense name, "Noun endings" or "Adjective endings", in the file's
     explanation language;
  3. writes `grammar_topic`, `grammar_text` and `grammar_link` in sorted
     order, and one `data_source` row per taught language with topics
     (`libredict-grammar-<lang>`, version the date of the last review);
  4. writes the review document `Scripts/reports/grammar-review.md`;
  then raises if a gate failed, so the build fails. Nothing stores a
  timestamp: the same sources and forms give the same rows.

Usage (from the repository root):
    python3 Scripts/build_grammar.py --self-check
        offline: renders the forms of Scripts/fixtures/kaikki-el-sample.jsonl,
        builds the fixture topics of Scripts/fixtures/grammar/ (one valid
        topic, one invalid topic per gate) and builds twice
    python3 Scripts/build_grammar.py --standalone out.sqlite \\
            --dictionary Scripts/.cache/dictionaries-full.sqlite [--allow-unreviewed]
        the grammar tables alone against a built full file, plus the review
        document, in seconds; `--source` and `--report` read and write
        elsewhere. The committed pack is always built without
        `--allow-unreviewed` (`build_dictionaries.py --verify`).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sqlite3
import sys
import tempfile
import unicodedata
import urllib.parse
from contextlib import closing
from dataclasses import dataclass, field
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_greek import normalize_greek  # noqa: E402  (the one Greek folding, #87)

SCRIPTS_DIR = Path(__file__).resolve().parent
SOURCE_DIR = SCRIPTS_DIR / "data" / "grammar"
REPORT = SCRIPTS_DIR / "reports" / "grammar-review.md"
FIXTURES = SCRIPTS_DIR / "fixtures" / "grammar"

SCHEMA = (SCRIPTS_DIR / "grammar_schema.sql").read_text(encoding="utf-8")
TABLES = ("grammar_topic", "grammar_text", "grammar_link")
SIZE_LIMIT = 1_000_000  # bytes, the three tables with their indexes (#171)
REPOSITORY_URL = "https://github.com/kyukhin/dict-app/tree/master/Scripts/data/grammar"

# Taught languages: the explanation languages every topic needs (the vias of
# the language's pairs; 2.0: Greek via English and via Russian, 0131).
LANGUAGES = {
    "ell": {"name": "Greek", "explain": ("eng", "rus")},
}
# The fallback language: every topic has it (Reading, 0133).
FALLBACK = "eng"

# Rendered labels and the translation script, per explanation language. A
# file in a language without labels fails. Tense names are E5's
# `ConjugationTense.title` (#144's labels, the mood and its aspect joined by
# " · "); row headers as the drafted written tables write them.
EXPLAIN = {
    "eng": {
        "name": "English",
        "script": "LATIN",
        "tenses": {
            "present": "Present", "imperfect": "Imperfect", "aorist": "Aorist", "future": "Future",
            "imperativeContinuous": "Imperative · continuous", "imperativeSimple": "Imperative · simple",
            "futureContinuous": "Future continuous", "perfect": "Perfect", "pluperfect": "Pluperfect",
            "futurePerfect": "Future perfect", "subjunctiveContinuous": "Subjunctive · continuous",
            "subjunctiveSimple": "Subjunctive · simple",
        },
        "cases": {"nominative": "Nominative", "genitive": "Genitive", "accusative": "Accusative",
                  "vocative": "Vocative"},
        "numbers": {"singular": "singular", "plural": "plural"},
        "row": "{case} {number}",
        "genders": {"masculine": "Masculine", "feminine": "Feminine", "neuter": "Neuter"},
        "nouns": "Noun endings",
        "adjectives": "Adjective endings",
    },
    "rus": {
        "name": "Russian",
        "script": "CYRILLIC",
        "tenses": {
            "present": "Настоящее", "imperfect": "Имперфект", "aorist": "Аорист", "future": "Будущее",
            "imperativeContinuous": "Повелительное · длительное",
            "imperativeSimple": "Повелительное · простое",
            "futureContinuous": "Будущее длительное", "perfect": "Перфект", "pluperfect": "Плюсквамперфект",
            "futurePerfect": "Будущее совершенное", "subjunctiveContinuous": "Сослагательное · длительное",
            "subjunctiveSimple": "Сослагательное · простое",
        },
        "cases": {"nominative": "Именительный", "genitive": "Родительный", "accusative": "Винительный",
                  "vocative": "Звательный"},
        "numbers": {"singular": "ед. ч.", "plural": "мн. ч."},
        "row": "{case}, {number}",
        "genders": {"masculine": "Мужской род", "feminine": "Женский род", "neuter": "Средний род"},
        "nouns": "Окончания существительных",
        "adjectives": "Окончания прилагательных",
    },
}

KEYS = ("id", "lang", "level", "order", "tenses", "classes", "words", "topics")
LIST_KEYS = ("tenses", "classes", "words", "topics")
LEVELS = ("A1", "A2", "B1", "B2", "C1", "C2")
# E5's `ConjugationTense` raw values, in its order (0132).
TENSES = ("present", "imperfect", "aorist", "future", "imperativeContinuous", "imperativeSimple",
          "futureContinuous", "perfect", "pluperfect", "futurePerfect", "subjunctiveContinuous",
          "subjunctiveSimple")
CLASSES = ("verb", "verb.conj1", "verb.conj2", "verb.passive", "noun", "adj")
LINK_KINDS = (("word", "words"), ("topic", "topics"), ("tense", "tenses"), ("class", "classes"))
MAX_WORDS = 12
MAX_RULE_WORDS = 120
# The tenses and classes of 0133's Content table, by topic id, in order:
# #174's links depend on them. They are front matter, which the review hash
# does not cover, so changing one means changing the spec (and this table)
# first. Topics not in the table (later levels, fixtures) are not checked.
CONTENT = {
    "ell-alphabet": ((), ()),
    "ell-articles": ((), ("noun",)),
    "ell-noun-endings": ((), ("noun",)),
    "ell-adjectives": ((), ("adj",)),
    "ell-pronouns": ((), ()),
    "ell-possessives": ((), ()),
    "ell-eimai-echo": (("present",), ()),
    "ell-present-1": (("present",), ("verb.conj1",)),
    "ell-present-2": (("present",), ("verb.conj2",)),
    "ell-negation-questions": ((), ()),
    "ell-se-prepositions": ((), ()),
    "ell-numbers-time": ((), ()),
    "ell-aorist-regular": (("aorist",), ("verb",)),
    "ell-aorist-irregular": (("aorist",), ()),
    "ell-future": (("future",), ("verb",)),
    "ell-na-perfective": (("subjunctiveSimple",), ("verb",)),
    "ell-imperative": (("imperativeSimple", "imperativeContinuous"), ("verb",)),
}

EXAMPLES_HEADING = "## Examples"
WATCH_OUT_HEADING = "## Watch out"
# One bold span: "**Most verbs**", not a rule line "**ο** and **η**".
CAPTION = re.compile(r"\*\*[^*]+\*\*")
FORMS_KEYS = ("words", "tense", "voice", "rows", "genders", "headers", "title")

# ---------------------------------------------------------------------------
# Paradigms: a port of #144's ParadigmLayout and E5's ConjugationTense.forms
# ---------------------------------------------------------------------------

PERSONS = ("1sg", "2sg", "3sg", "1pl", "2pl", "3pl")
PRONOUNS = dict(zip(PERSONS, ("εγώ", "εσύ", "αυτός", "εμείς", "εσείς", "αυτοί")))
HAVE = dict(zip(PERSONS, ("έχω", "έχεις", "έχει", "έχουμε", "έχετε", "έχουν")))
HAD = dict(zip(PERSONS, ("είχα", "είχες", "είχε", "είχαμε", "είχατε", "είχαν")))
IMPERATIVE_PERSONS = ("2sg", "2pl")
HIDDEN = frozenset({"rare", "archaic", "dated"})
CASES = ("nominative", "genitive", "accusative", "vocative")
NUMBERS = ("singular", "plural")
GENDERS = ("masculine", "feminine", "neuter")
NON_INDICATIVE = frozenset({"subjunctive", "optative", "conditional"})
FINITE = ("present", "imperfect", "aorist", "dependent", "imperativeContinuous", "imperativeSimple")
DEFAULT_ROWS = (("nominative", "singular"), ("accusative", "singular"),
                ("nominative", "plural"), ("accusative", "plural"))


def person_of(tags: frozenset) -> str | None:
    """`ParadigmLayout.Person(tags:)`: one person and one number."""
    found = [i for i, p in enumerate(("first-person", "second-person", "third-person")) if p in tags]
    singular, plural = "singular" in tags, "plural" in tags
    if len(found) != 1 or singular == plural:
        return None
    return PERSONS[found[0] + (3 if plural else 0)]


def verb_slot(tags: frozenset) -> tuple[str, str, str | None] | None:
    """`ParadigmLayout.verbSlot`: (voice, slot, person) of a verb cell, or
    None for a hidden cell or one that matches no slot."""
    if tags & HIDDEN:
        return None
    voice = "passive" if "passive" in tags else "active"
    if "infinitive-aorist" in tags:
        return voice, "infinitive", None
    if "participle" in tags:
        declined = bool(tags & frozenset(CASES + GENDERS + NUMBERS))
        if declined and not {"nominative", "masculine", "singular"} <= tags:
            return None
        if "present" in tags:
            return voice, "present_participle", None
        if voice == "passive" and ("past" in tags or "perfect" in tags):
            return voice, "past_participle", None
        return None
    person = person_of(tags)
    if person is None:
        return None
    if "imperative" in tags:
        if person not in IMPERATIVE_PERSONS:
            return None
        if "imperfective" in tags:
            return voice, "imperativeContinuous", person
        if "perfective" in tags:
            return voice, "imperativeSimple", person
        return None
    if "dependent" in tags:
        return voice, "dependent", person
    if "imperfect" in tags:
        return voice, "imperfect", person
    if {"past", "perfective"} <= tags:
        return voice, "aorist", person
    if "present" in tags and not tags & NON_INDICATIVE:
        return voice, "present", person
    return None


def voice_forms(cells: list[tuple[str, frozenset]]) -> dict[str, dict[tuple[str, str | None], list[str]]]:
    """`ParadigmLayout.voiceForms`: per voice, the forms of each (slot,
    person) in table order, without repeats."""
    voices: dict[str, dict[tuple[str, str | None], list[str]]] = {}
    for form, tags in cells:
        match = verb_slot(tags)
        if match is None:
            continue
        voice, slot, person = match
        forms = voices.setdefault(voice, {}).setdefault((slot, person), [])
        if form not in forms:
            forms.append(form)
    return voices


def main_voice(voices: dict) -> str:
    """`ParadigmLayout.mainVoice`: passive for a verb with a passive present
    and no active one (έρχομαι)."""
    def has_present(voice: str) -> bool:
        return any(voices.get(voice, {}).get(("present", p)) for p in PERSONS)
    return "passive" if not has_present("active") and has_present("passive") else "active"


def tense_forms(voice: dict, tense: str, person: str) -> list[str]:
    """E5's `ConjugationTense.forms`: the cells of the simple tenses, #144's
    generated forms for the others, and the θα / να + present fallback of a
    voice with a present and no dependent form (Kirill, 2026-11-04)."""
    def cells(slot: str, p: str | None = person) -> list[str]:
        return voice.get((slot, p), [])
    lacks_dependent = (any(cells("present", p) for p in PERSONS)
                       and not any(cells("dependent", p) for p in PERSONS))
    persons = {p for (slot, p), forms in voice.items() if slot in FINITE and forms}

    def perfect(aux: dict) -> list[str]:
        return [aux[person] + " " + f for f in cells("infinitive", None)] if person in persons else []

    if tense in ("present", "imperfect", "aorist", "imperativeContinuous", "imperativeSimple"):
        return cells(tense)
    if tense == "future":
        return ["θα " + f for f in cells("present" if lacks_dependent else "dependent")]
    if tense == "subjunctiveSimple":
        return ["να " + f for f in cells("present" if lacks_dependent else "dependent")]
    if tense == "futureContinuous":
        return [] if lacks_dependent else ["θα " + f for f in cells("present")]
    if tense == "subjunctiveContinuous":
        return [] if lacks_dependent else ["να " + f for f in cells("present")]
    if tense == "perfect":
        return perfect(HAVE)
    if tense == "pluperfect":
        return perfect(HAD)
    if tense == "futurePerfect":
        return ["θα " + f for f in perfect(HAVE)]
    raise ValueError(tense)


def tense_persons(tense: str) -> tuple[str, ...]:
    return IMPERATIVE_PERSONS if tense in ("imperativeContinuous", "imperativeSimple") else PERSONS


def single(options: tuple[str, ...], tags: frozenset) -> str | None:
    found = [o for o in options if o in tags]
    return found[0] if len(found) == 1 else None


def nominal_forms(cells: list[tuple[str, frozenset]], adjective: bool) -> dict[tuple, list[str]]:
    """#144's nominal slots: (case, number) for a noun, (case, number,
    gender) for an adjective, without hidden and degree cells."""
    slots: dict[tuple, list[str]] = {}
    for form, tags in cells:
        if tags & HIDDEN or "comparative" in tags or "superlative" in tags:
            continue
        key = (single(CASES, tags), single(NUMBERS, tags)) + ((single(GENDERS, tags),) if adjective else ())
        if None in key:
            continue
        forms = slots.setdefault(key, [])
        if form not in forms:
            forms.append(form)
    return slots


class Paradigms:
    """The paradigm cells of a lemma, read from the forms tables."""

    def __init__(self, conn: sqlite3.Connection):
        self.conn = conn
        self.cache: dict[tuple[str, str, str], list | None] = {}

    def cells(self, lang: str, word: str, pos: str) -> list[tuple[str, frozenset]] | None:
        key = (lang, word, pos)
        if key not in self.cache:
            row = self.conn.execute("SELECT id FROM lemma WHERE lang = ? AND word = ? AND pos = ?", key).fetchone()
            self.cache[key] = None if row is None else [
                (form, frozenset(tags.split())) for form, tags in self.conn.execute(
                    "SELECT p.form, t.tags FROM paradigm p JOIN tagset t ON t.id = p.tagset_id "
                    "WHERE p.lemma_id = ? ORDER BY p.ord", row)]
        return self.cache[key]


# ---------------------------------------------------------------------------
# Text helpers
# ---------------------------------------------------------------------------

def nfc(s: str) -> str:
    return unicodedata.normalize("NFC", s)


def script(ch: str) -> str:
    """GREEK, LATIN, CYRILLIC or another script's first name word."""
    return unicodedata.name(ch, "UNKNOWN").split(" ")[0]


def letters(text: str) -> list[str]:
    return [ch for ch in text if ch.isalpha()]


def has_greek(text: str) -> bool:
    return any(script(ch) == "GREEK" for ch in letters(text))


def lookalikes(text: str) -> list[str]:
    """Latin or Cyrillic letters in Greek text: "Latin 'o'"."""
    found = []
    for ch in letters(text):
        name = script(ch)
        if name in ("LATIN", "CYRILLIC"):
            label = f"{name.capitalize()} {ch!r}"
            if label not in found:
                found.append(label)
    return found


def mixed_words(text: str) -> list[str]:
    """The words of `text` that mix Greek with Latin or Cyrillic letters
    (τo, тο): a written table's cells mix English or Russian text with
    Greek words, so they are checked word by word."""
    return [w for w in re.findall(r"[^\W\d_]+", text) if has_greek(w) and lookalikes(w)]


MARKS = re.compile(r"[*~`]")


def word_count(lines: list[str]) -> int:
    """Words of the rule, as the app counts them (`GrammarDocument.ruleWordCount`):
    whitespace-separated tokens with a letter in them, after removing the
    Markdown marks."""
    return sum(1 for line in lines for token in MARKS.sub("", line).split() if any(c.isalpha() for c in token))


def split_list(value: str) -> list[str]:
    return [item.strip() for item in value.split(",") if item.strip()]


def table_cells(line: str) -> list[str]:
    """The cells of a pipe-table line."""
    inner = line.strip()
    if inner.startswith("|"):
        inner = inner[1:]
    if inner.endswith("|"):
        inner = inner[:-1]
    return [cell.strip() for cell in inner.split("|")]


SEPARATOR_CELL = re.compile(r":?-{3,}:?")


# ---------------------------------------------------------------------------
# Parsing
# ---------------------------------------------------------------------------

@dataclass
class Part:
    """A block of the body, in order: blank, text (rule), caption, forms,
    table, heading, example, watch."""
    kind: str
    lines: list[str]
    line_no: int
    params: dict = field(default_factory=dict)


@dataclass
class Text:
    """One topic file: a topic in one explanation language."""
    path: Path
    explain: str
    front: dict[str, str]
    title: str = ""
    parts: list[Part] = field(default_factory=list)
    body: str = ""            # as stored: the Markdown after the title, forms rendered
    rule_words: int = 0
    tables: int = 0
    examples: list[tuple[str, str]] = field(default_factory=list)
    watch_out: int = 0

    @property
    def name(self) -> str:
        return f"{self.explain}/{self.path.name}"

    @property
    def sha256(self) -> str:
        return hashlib.sha256((self.title + "\n" + self.body).encode("utf-8")).hexdigest()


@dataclass
class Topic:
    id: str
    lang: str
    level: str
    order: int
    links: dict[str, list[str]]       # words, topics, tenses, classes
    texts: dict[str, Text]            # by explanation language


def read_front(path: Path, explain: str, errors: list[str]) -> Text | None:
    """The front matter and the body lines of one file."""
    text = nfc(path.read_text(encoding="utf-8")).replace("\r\n", "\n")
    lines = text.split("\n")
    name = f"{explain}/{path.name}"
    if not lines or lines[0].strip() != "---":
        errors.append(f"{name}: no front matter (a '---' first line)")
        return None
    try:
        end = next(i for i in range(1, len(lines)) if lines[i].strip() == "---")
    except StopIteration:
        errors.append(f"{name}: the front matter has no closing '---'")
        return None
    front: dict[str, str] = {}
    for line in lines[1:end]:
        if not line.strip():
            continue
        m = re.fullmatch(r"([A-Za-z_]+):(.*)", line.strip())
        if not m:
            errors.append(f"{name}: front matter line {line!r} is not 'key: value'")
            continue
        key, value = m.group(1), m.group(2).strip()
        if key not in KEYS:
            errors.append(f"{name}: unknown front matter key {key!r}")
        elif key in front:
            errors.append(f"{name}: front matter key {key!r} given twice")
        else:
            front[key] = value
    result = Text(path, explain, front)
    result.parts = parse_body(lines[end + 1:], end + 2, name, errors, result)
    return result


def parse_body(lines: list[str], first_line: int, name: str, errors: list[str], text: Text) -> list[Part]:
    """Splits the body into parts and checks their order (spec, "Body")."""
    parts: list[Part] = []
    i, n = 0, len(lines)
    while i < n and not lines[i].strip():
        i += 1
    if i < n and lines[i].startswith("# ") and lines[i][2:].strip():
        text.title = lines[i][2:].strip()
        i += 1
    else:
        errors.append(f"{name}: no '# Title' line first")
    section = "rule"
    headings: list[str] = []
    while i < n:
        line, stripped, line_no = lines[i], lines[i].strip(), first_line + i
        if not stripped:
            parts.append(Part("blank", [line], line_no))
            i += 1
            continue
        if line.startswith("#"):
            if stripped in (EXAMPLES_HEADING, WATCH_OUT_HEADING):
                section = "examples" if stripped == EXAMPLES_HEADING else "watch"
                headings.append(stripped)
            else:
                errors.append(f"{name}: line {line_no}: unknown heading {stripped!r}")
            parts.append(Part("heading", [line], line_no))
            i += 1
            continue
        if section in ("rule", "tables"):
            if stripped.startswith("```"):
                end = next((j for j in range(i + 1, n) if lines[j].strip() == "```"), None)
                if stripped != "```forms" or end is None:
                    errors.append(f"{name}: line {line_no}: only closed ```forms blocks are allowed")
                    i = n if end is None else end + 1
                    continue
                parts.append(Part("forms", lines[i:end + 1], line_no, parse_forms(lines[i + 1:end], name, line_no,
                                                                                  errors)))
                section = "tables"
                i = end + 1
                continue
            if stripped.startswith("|"):
                end = i
                while end < n and lines[end].strip().startswith("|"):
                    end += 1
                parts.append(Part("table", lines[i:end], line_no))
                section = "tables"
                i = end
                continue
            if CAPTION.fullmatch(stripped):
                parts.append(Part("caption", [line], line_no))
                section = "tables"
                i += 1
                continue
            if section == "tables":
                errors.append(f"{name}: line {line_no}: text after the tables (the rule comes before them; "
                              f"a caption is a line in bold)")
            parts.append(Part("text", [line], line_no))
            i += 1
            continue
        if not line.startswith("- "):
            heading = EXAMPLES_HEADING if section == "examples" else WATCH_OUT_HEADING
            errors.append(f"{name}: line {line_no}: not a '- ' item under {heading!r}")
            i += 1
            continue
        end = i + 1
        while end < n and lines[end].strip() and lines[end][0] in " \t":
            end += 1
        parts.append(Part("example" if section == "examples" else "watch", lines[i:end], line_no))
        i = end
    missing = [h for h in (EXAMPLES_HEADING, WATCH_OUT_HEADING) if h not in headings]
    if missing:
        errors.append(f"{name}: no {' and no '.join(repr(h) for h in missing)}")
    elif headings != [EXAMPLES_HEADING, WATCH_OUT_HEADING]:
        errors.append(f"{name}: blocks out of order: the title, the rule, the tables, "
                      f"{EXAMPLES_HEADING!r}, then {WATCH_OUT_HEADING!r}, each once")
    return parts


def parse_forms(lines: list[str], name: str, line_no: int, errors: list[str]) -> dict:
    """A ```forms block's keys (spec, "Forms blocks")."""
    params: dict[str, str] = {}
    where = f"{name}: line {line_no}: forms block"
    before = len(errors)
    for line in lines:
        if not line.strip():
            continue
        m = re.fullmatch(r"([a-z]+):(.*)", line.strip())
        if not m or m.group(1) not in FORMS_KEYS:
            errors.append(f"{where}: unknown line {line.strip()!r}")
            continue
        params[m.group(1)] = m.group(2).strip()
    words = split_list(params.get("words", ""))
    if not 1 <= len(words) <= 3:
        errors.append(f"{where}: needs 1 to 3 words, has {len(words)}")
    tense = params.get("tense")
    if tense is not None and tense not in TENSES:
        errors.append(f"{where}: unknown tense {tense!r}")
    if "voice" in params and (tense is None or params["voice"] not in ("active", "passive")):
        errors.append(f"{where}: voice is 'active' or 'passive', with a tense")
    rows: list[tuple[str, str]] = []
    if "rows" in params:
        for row in split_list(params["rows"]):
            pair = tuple(row.split())
            if len(pair) != 2 or pair[0] not in CASES or pair[1] not in NUMBERS:
                errors.append(f"{where}: unknown row {row!r} (a case and a number: 'nominative singular')")
            else:
                rows.append(pair)
    genders = split_list(params.get("genders", ""))
    if any(g not in GENDERS for g in genders):
        errors.append(f"{where}: genders are masculine, feminine, neuter")
    if tense is not None and ("rows" in params or genders):
        errors.append(f"{where}: rows and genders are for nouns and adjectives, not with a tense")
    if genders and len(words) != 1:
        errors.append(f"{where}: genders are the columns of one adjective")
    columns = len(genders) if genders else len(words)
    headers = split_list(params.get("headers", ""))
    if "headers" in params and len(headers) != columns:
        errors.append(f"{where}: {len(headers)} headers for {columns} columns")
    for word in [w for text in words + headers for w in mixed_words(text)]:
        errors.append(f"{where}: {', '.join(lookalikes(word))} in Greek text {word!r}")
    return {"words": words, "tense": tense, "voice": params.get("voice"), "rows": rows or list(DEFAULT_ROWS),
            "genders": genders, "headers": headers, "title": params.get("title"), "ok": len(errors) == before}


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------

def render_forms(params: dict, lang: str, labels: dict, paradigms: Paradigms,
                 where: str, errors: list[str]) -> list[str] | None:
    """The comment and the pipe table of a forms block, or None (with the
    reasons in `errors`) when a word has no lemma or a cell is empty."""
    words, tense = params["words"], params["tense"]
    failed = False
    if tense is not None:
        voices_of = []
        for word in words:
            cells = paradigms.cells(lang, word, "verb")
            if not cells:
                errors.append(f"{where}: {word} has no verb table")
                failed = True
                continue
            voices_of.append((word, voice_forms(cells)))
        if failed:
            return None
        voice = params["voice"]
        if voice is None:
            mains = {main_voice(v) for _, v in voices_of}
            if len(mains) > 1:
                errors.append(f"{where}: the words have different main voices; set voice")
                return None
            voice = mains.pop()
        rows = [[PRONOUNS[person]] for person in tense_persons(tense)]
        for word, voices in voices_of:
            missing = []
            for row, person in zip(rows, tense_persons(tense)):
                forms = tense_forms(voices.get(voice, {}), tense, person)
                if not forms:
                    missing.append(PRONOUNS[person])
                row.append(" / ".join(forms))
            if missing:
                errors.append(f"{where}: {word} has no {voice} {tense} form for {', '.join(missing)}")
                failed = True
        comment = f"<!-- forms words={','.join(words)} tense={tense} voice={voice} -->"
    else:
        adjective = bool(params["genders"])
        poses, columns = [], []
        for word in words:
            found = None
            for pos in (("adj",) if adjective else ("noun", "name")):
                cells = paradigms.cells(lang, word, pos)
                if cells and nominal_forms(cells, adjective):
                    found = (pos, nominal_forms(cells, adjective))
                    break
            if found is None:
                errors.append(f"{where}: {word} has no {'adjective' if adjective else 'noun'} table")
                failed = True
                continue
            poses.append(found[0])
            if adjective:
                columns += [(g, lambda c, n, g=g, slots=found[1]: slots.get((c, n, g), [])) for g in params["genders"]]
            else:
                columns.append((word, lambda c, n, slots=found[1]: slots.get((c, n), [])))
        if failed:
            return None
        rows = [[labels["row"].format(case=labels["cases"][case], number=labels["numbers"][number])]
                for case, number in params["rows"]]
        for column, forms_of in columns:
            missing = []
            for row, (case, number) in zip(rows, params["rows"]):
                forms = forms_of(case, number)
                if not forms:
                    missing.append(f"{case} {number}")
                row.append(" / ".join(forms))
            if missing:
                name = f"{words[0]} ({column})" if adjective else column
                errors.append(f"{where}: {name} has no {', '.join(missing)}")
                failed = True
        comment = (f"<!-- forms words={','.join(words)} pos={','.join(poses)}"
                   + (f" genders={','.join(params['genders'])}" if adjective else "")
                   + f" rows={','.join(c + '.' + n for c, n in params['rows'])} -->")
    if failed:
        return None
    if params["headers"]:
        header = params["headers"]
    elif params["genders"]:
        header = [labels["genders"][g] for g in params["genders"]]
    else:
        header = words
    table = ["| | " + " | ".join(header) + " |", "|---" * (len(header) + 1) + "|"]
    table += ["| " + " | ".join(row) + " |" for row in rows]
    return [comment] + table


def default_caption(params: dict, labels: dict) -> str:
    if params["title"]:
        return params["title"]
    if params["tense"]:
        return labels["tenses"][params["tense"]]
    return labels["adjectives"] if params["genders"] else labels["nouns"]


def render(text: Text, lang: str, paradigms: Paradigms, errors: list[str]) -> None:
    """Fills `text.body` and its figures, and checks the body gates."""
    labels = EXPLAIN[text.explain]
    out: list[str] = []
    rule: list[str] = []
    previous: Part | None = None
    for index, part in enumerate(text.parts):
        if part.kind == "forms":
            where = f"{text.name}: line {part.line_no}: forms block"
            captioned = previous is not None and previous.kind == "caption"
            if captioned and part.params["title"]:
                errors.append(f"{where}: a caption line and a title")
            rendered = None
            if part.params["ok"]:
                rendered = render_forms(part.params, lang, labels, paradigms, where, errors)
            if not captioned and part.params["ok"]:
                out += [f"**{default_caption(part.params, labels)}**", ""]
            out += rendered or part.lines
            text.tables += 1
        else:
            out += part.lines
            if part.kind == "table":
                check_pipe_table(part, text, errors)
                text.tables += 1
            elif part.kind == "text":
                rule.append(part.lines[0])
            elif part.kind == "caption":
                following = next((p for p in text.parts[index + 1:] if p.kind != "blank"), None)
                if following is None or following.kind not in ("forms", "table"):
                    errors.append(f"{text.name}: line {part.line_no}: a caption line with no table after it")
            elif part.kind == "example":
                check_example(part, text, errors)
            elif part.kind == "watch":
                text.watch_out += 1
        if part.kind != "blank":
            previous = part
    while out and not out[0].strip():
        out.pop(0)
    while out and not out[-1].strip():
        out.pop()
    text.body = "\n".join(out)
    text.rule_words = word_count(rule)
    if not text.rule_words:
        errors.append(f"{text.name}: no rule")
    elif text.rule_words > MAX_RULE_WORDS:
        errors.append(f"{text.name}: the rule has {text.rule_words} words, at most {MAX_RULE_WORDS}")
    if not 1 <= text.tables <= 3:
        errors.append(f"{text.name}: {text.tables} tables, needs 1 to 3")
    if not 3 <= len(text.examples) <= 5:
        errors.append(f"{text.name}: {len(text.examples)} examples, needs 3 to 5")
    if not 1 <= text.watch_out <= 2:
        errors.append(f"{text.name}: {text.watch_out} Watch out items, needs 1 or 2")


def check_pipe_table(part: Part, text: Text, errors: list[str]) -> None:
    where = f"{text.name}: line {part.line_no}: table"
    rows = [table_cells(line) for line in part.lines]
    if len(rows) < 3 or not all(SEPARATOR_CELL.fullmatch(cell) for cell in rows[1]):
        errors.append(f"{where}: needs a header row, a '|---|' row and at least one row")
        return
    if any(len(row) != len(rows[0]) for row in rows):
        errors.append(f"{where}: rows of different lengths")
    for row in rows[:1] + rows[2:]:
        for cell in row:
            for word in mixed_words(cell):
                errors.append(f"{where}: {', '.join(lookalikes(word))} in Greek text {word!r}")


def check_example(part: Part, text: Text, errors: list[str]) -> None:
    where = f"{text.name}: line {part.line_no}: example"
    greek = part.lines[0][2:].strip()
    translations = [line.strip() for line in part.lines[1:]]
    if len(translations) != 1:
        errors.append(f"{where}: needs one translation line under it, has {len(translations)}")
    if not has_greek(greek):
        errors.append(f"{where}: the first line has no Greek letters")
    elif lookalikes(greek):
        errors.append(f"{where}: {', '.join(lookalikes(greek))} in Greek text {greek!r}")
    translation = translations[0] if translations else ""
    wanted = EXPLAIN[text.explain]["script"]
    other = sorted({script(ch) for ch in letters(translation)} - {wanted})
    if translations and (not letters(translation) or other):
        errors.append(f"{where}: the translation must be in {wanted.capitalize()} letters"
                      + (f", has {', '.join(o.capitalize() for o in other)}" if other else ""))
    text.examples.append((greek, translation))


# ---------------------------------------------------------------------------
# The step
# ---------------------------------------------------------------------------

@dataclass
class Result:
    topics: list[Topic]
    errors: list[str]
    reviewed: dict[tuple[str, str], str]      # (topic id, sha256) -> date
    sizes: dict[str, int] = field(default_factory=dict)


def read_reviewed(path: Path, errors: list[str]) -> dict[tuple[str, str], str]:
    """`reviewed.tsv`: topic id, sha256, date per line; '#' comments and a
    header line are skipped."""
    reviewed: dict[tuple[str, str], str] = {}
    if not path.is_file():
        return reviewed
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip() or line.startswith("#") or line.startswith("topic"):
            continue
        cells = line.split("\t")
        if len(cells) != 3 or not re.fullmatch(r"[0-9a-f]{64}", cells[1]) \
                or not re.fullmatch(r"\d{4}-\d{2}-\d{2}", cells[2]):
            errors.append(f"{path.name}: line {number}: needs 'topic id<TAB>sha256<TAB>YYYY-MM-DD'")
            continue
        reviewed[(cells[0], cells[1])] = cells[2]
    return reviewed


def compile_topics(source: Path, data: sqlite3.Connection, allow_unreviewed: bool,
                   languages: dict = LANGUAGES) -> Result:
    """Reads, parses, renders and checks every topic of `source` against the
    dictionaries and forms in `data`. Never raises for content: the reasons
    are in `Result.errors`."""
    errors: list[str] = []
    texts: list[Text] = []
    explain_dirs = sorted(p for p in source.iterdir() if p.is_dir()) if source.is_dir() else []
    for folder in explain_dirs:
        files = sorted(folder.glob("*.md"))
        if files and folder.name not in EXPLAIN:
            errors.append(f"{folder.name}/: no labels for the explanation language {folder.name!r} "
                          f"(known: {', '.join(EXPLAIN)})")
            continue
        for path in files:
            text = read_front(path, folder.name, errors)
            if text is not None:
                texts.append(text)

    by_id: dict[str, list[Text]] = {}
    for text in texts:
        topic_id = text.front.get("id", "")
        if topic_id != text.path.stem:
            errors.append(f"{text.name}: id {topic_id!r} is not the file name")
        by_id.setdefault(text.path.stem, []).append(text)

    topics: list[Topic] = []
    for topic_id, group in sorted(by_id.items()):
        topic = make_topic(topic_id, group, languages, errors)
        if topic is not None:
            topics.append(topic)

    known = {(t.lang, t.id) for t in topics}
    orders: dict[tuple[str, str, int], str] = {}
    paradigms = Paradigms(data)
    for topic in topics:
        key = (topic.lang, topic.level, topic.order)
        if key in orders:
            errors.append(f"{topic.id}: order {topic.order} of {topic.lang} {topic.level} is taken by {orders[key]}")
        orders.setdefault(key, topic.id)
        check_links(topic, known, data, errors)
        check_content(topic, errors)
        for text in topic.texts.values():
            render(text, topic.lang, paradigms, errors)
            if topic.links["tenses"] and any(p.kind == "table" for p in text.parts):
                errors.append(f"{text.name}: a topic with tenses has no typed table (use a forms block)")

    reviewed = read_reviewed(source / "reviewed.tsv", errors)
    if not allow_unreviewed:
        for topic in topics:
            for explain, text in sorted(topic.texts.items()):
                if (topic.id, text.sha256) not in reviewed:
                    errors.append(f"{text.name}: not reviewed (sha256 {text.sha256} is not in reviewed.tsv)")
    return Result(topics, errors, reviewed)


def make_topic(topic_id: str, group: list[Text], languages: dict, errors: list[str]) -> Topic | None:
    """The topic of one id's files: the front matter gates."""
    first = next((t for t in group if t.explain == FALLBACK), group[0])
    front = first.front
    lang = front.get("lang", "")
    for text in group:
        if text.front != front:
            errors.append(f"{text.name}: front matter differs from {first.name}")
    missing = [k for k in ("id", "lang", "level", "order") if not front.get(k)]
    if missing:
        errors.append(f"{first.name}: no {', '.join(missing)} in the front matter")
        return None
    if lang not in languages:
        errors.append(f"{first.name}: no taught language {lang!r} in build_grammar.LANGUAGES")
        return None
    if not topic_id.startswith(lang + "-"):
        errors.append(f"{first.name}: id {topic_id!r} must start with {lang + '-'!r}")
    if front["level"] not in LEVELS:
        errors.append(f"{first.name}: level {front['level']!r} is not one of {', '.join(LEVELS)}")
    if not re.fullmatch(r"[1-9][0-9]*", front["order"]):
        errors.append(f"{first.name}: order {front['order']!r} is not a positive number")
        return None
    explains = {t.explain for t in group}
    for needed in sorted({FALLBACK, *languages[lang]["explain"]}):
        if needed not in explains:
            errors.append(f"{topic_id}: no {needed} text ({needed}/{topic_id}.md)")
    return Topic(topic_id, lang, front["level"], int(front["order"]),
                 {key: split_list(front.get(key, "")) for key in LIST_KEYS},
                 {t.explain: t for t in group})


def check_links(topic: Topic, known: set, data: sqlite3.Connection, errors: list[str]) -> None:
    """The link gates (spec, "Gates")."""
    links = topic.links
    sources = [s for (s,) in data.execute(
        "SELECT source FROM dict_metadata WHERE from_lang = ? AND to_lang = 'eng' ORDER BY rowid", (topic.lang,))]
    for kind, key in LINK_KINDS:
        repeated = sorted({v for v in links[key] if links[key].count(v) > 1})
        if repeated:
            errors.append(f"{topic.id}: {key} lists {', '.join(repeated)} twice")
    for word in links["words"]:
        if lookalikes(word):
            errors.append(f"{topic.id}: {', '.join(lookalikes(word))} in Greek text {word!r}")
        elif not data.execute(f"SELECT 1 FROM entries WHERE word = ? AND source IN ({','.join('?' * len(sources))})",
                              (word, *sources)).fetchone():
            errors.append(f"{topic.id}: word {word!r} is no headword of a {topic.lang} → eng dictionary")
    for other in links["topics"]:
        if (topic.lang, other) not in known:
            errors.append(f"{topic.id}: topic {other!r} is no {topic.lang} topic")
    for tense in links["tenses"]:
        if tense not in TENSES:
            errors.append(f"{topic.id}: tense {tense!r} is no ConjugationTense")
    for name in links["classes"]:
        if name not in CLASSES:
            errors.append(f"{topic.id}: class {name!r} is not one of {', '.join(CLASSES)}")
    if not links["words"] and not links["topics"]:
        errors.append(f"{topic.id}: no word or topic link")
    if len(links["words"]) > MAX_WORDS:
        errors.append(f"{topic.id}: {len(links['words'])} words, at most {MAX_WORDS}")


def check_content(topic: Topic, errors: list[str]) -> None:
    """A topic of 0133's Content table has exactly its tenses and classes."""
    if topic.id not in CONTENT:
        return
    for key, fixed in zip(("tenses", "classes"), CONTENT[topic.id]):
        if tuple(topic.links[key]) != fixed:
            errors.append(f"{topic.id}: {key} {', '.join(topic.links[key]) or 'none'} differ from 0133's "
                          f"Content ({', '.join(fixed) or 'none'}); change the spec first")


def data_source_row(lang: str, topics: list[Topic], reviewed: dict) -> dict:
    dates = [reviewed[(t.id, text.sha256)] for t in topics for text in t.texts.values()
             if (t.id, text.sha256) in reviewed]
    return {"id": f"libredict-grammar-{lang}", "kind": "grammar",
            "display_name": f"{LANGUAGES[lang]['name']} grammar notes (LibreDict)",
            "version": max(dates) if dates else "unreviewed", "license": "CC BY-SA 4.0", "url": REPOSITORY_URL}


def write_tables(conn: sqlite3.Connection, result: Result) -> None:
    """The three tables in key order, and a data_source row per language."""
    topics = sorted(result.topics, key=lambda t: t.id)
    with conn:
        conn.executemany("INSERT INTO grammar_topic(id, lang, level, ord) VALUES (?, ?, ?, ?)",
                         [(t.id, t.lang, t.level, t.order) for t in topics])
        conn.executemany("INSERT INTO grammar_text(topic_id, explain_lang, title, body) VALUES (?, ?, ?, ?)",
                         [(t.id, e, t.texts[e].title, t.texts[e].body) for t in topics for e in sorted(t.texts)])
        links = sorted((t.id, kind, value, order) for t in topics for kind, key in LINK_KINDS
                       for order, value in enumerate(t.links[key], 1))
        conn.executemany("INSERT INTO grammar_link(topic_id, kind, key, ord) VALUES (?, ?, ?, ?)", links)
        for lang in sorted({t.lang for t in topics}):
            conn.execute("INSERT INTO data_source(id, kind, display_name, version, license, url) "
                         "VALUES (:id, :kind, :display_name, :version, :license, :url)",
                         data_source_row(lang, [t for t in topics if t.lang == lang], result.reviewed))


def table_sizes(conn: sqlite3.Connection) -> dict[str, int]:
    """Bytes per grammar table with its indexes (dbstat)."""
    sizes = dict.fromkeys(TABLES, 0)
    for table, size in conn.execute(f"""
            SELECT m.tbl_name, SUM(d.pgsize) FROM dbstat AS d JOIN sqlite_master AS m ON m.name = d.name
            WHERE m.tbl_name IN ({",".join("?" * len(TABLES))}) GROUP BY m.tbl_name""", TABLES):
        sizes[table] = size
    return sizes


def table_hashes(conn: sqlite3.Connection) -> dict[str, tuple[int, str]]:
    """Rows and the sha256 of each grammar table's rows in key order."""
    order = {"grammar_topic": "id", "grammar_text": "topic_id, explain_lang", "grammar_link": "topic_id, kind, key"}
    result = {}
    for table in TABLES:
        digest, rows = hashlib.sha256(), 0
        for row in conn.execute(f"SELECT * FROM {table} ORDER BY {order[table]}"):
            digest.update(json.dumps(row, ensure_ascii=False, separators=(",", ":")).encode() + b"\n")
            rows += 1
        result[table] = (rows, digest.hexdigest())
    return result


class GrammarGateError(RuntimeError):
    def __init__(self, errors: list[str], report: Path | None):
        self.errors = errors
        where = f" (see {report})" if report else ""
        super().__init__(f"Grammar gates failed{where}:\n  - " + "\n  - ".join(errors))


def run(conn: sqlite3.Connection, data: sqlite3.Connection, source: Path = SOURCE_DIR,
        report_path: Path | None = REPORT, allow_unreviewed: bool = False,
        size_limit: int = SIZE_LIMIT, languages: dict = LANGUAGES) -> Result:
    """Builds the grammar tables into `conn` from the topics of `source`,
    reading the dictionaries and forms from `data`; writes the review
    document; raises `GrammarGateError` if a gate failed."""
    result = compile_topics(source, data, allow_unreviewed, languages)
    if not result.errors:
        write_tables(conn, result)
        try:
            result.sizes = table_sizes(conn)
        except sqlite3.OperationalError as error:
            raise RuntimeError(f"The size gate needs SQLite with dbstat: {error}") from error
        total = sum(result.sizes.values())
        if total > size_limit:
            result.errors.append(f"the grammar tables are {total:,} bytes, at most {size_limit:,}")
    if report_path is not None:
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(review(result, data, size_limit), encoding="utf-8")
    texts = sum(len(t.texts) for t in result.topics)
    print(f"  {len(result.topics)} topics, {texts} texts from {source}")
    if result.sizes:
        print("  " + ", ".join(f"{t} {s:,} B" for t, s in result.sizes.items())
              + f"; total {sum(result.sizes.values()):,} B (at most {size_limit:,})")
    if report_path is not None:
        print(f"  review document: {report_path}")
    if result.errors:
        raise GrammarGateError(result.errors, report_path)
    return result


def build(conn: sqlite3.Connection, cache_dir: Path) -> None:
    """The `STEPS` entry point of build_dictionaries.py: runs after the
    dictionaries, the forms and the lists, and reads them from `conn`.
    Never with `--allow-unreviewed`."""
    run(conn, conn)


# ---------------------------------------------------------------------------
# Review document
# ---------------------------------------------------------------------------

def first_sense(definition: str) -> str:
    """The first numbered sense of a definition, without WordNet's gloss."""
    for line in definition.splitlines():
        m = re.match(r"\s*1\.\s+(.*)", line)
        if m:
            return m.group(1).split(" — ")[0].strip()
    return definition.strip().splitlines()[0] if definition.strip() else ""


def list_words(data: sqlite3.Connection, lang: str) -> set[str]:
    """The folded words of the language's A1 and A2 lists (E3), empty until
    #152 fills them."""
    if not data.execute("SELECT 1 FROM sqlite_master WHERE name = 'wordlist_item'").fetchone():
        return set()
    return {normalize_greek(w) for (w,) in data.execute(
        "SELECT COALESCE(headword, term) FROM wordlist_item WHERE level IN ('A1', 'A2') "
        "AND series IN (SELECT series FROM wordlist WHERE lang = ?)", (lang,))}


def outside_lists(greek_lines: list[str], data: sqlite3.Connection, words: set[str]) -> list[str]:
    """The example words that are no form of a list word."""
    found: list[str] = []
    for line in greek_lines:
        for token in re.findall(r"[^\W\d_]+", line):
            key = normalize_greek(token)
            if key in words or token in found:
                continue
            lemmas = {normalize_greek(w) for (w,) in data.execute(
                "SELECT l.word FROM form_lookup f JOIN lemma l ON l.id = f.lemma_id WHERE f.form_norm = ?", (key,))}
            if not lemmas & words:
                found.append(token)
    return found


def review(result: Result, data: sqlite3.Connection, size_limit: int) -> str:
    """The review document: every topic as the app shows it, in every
    explanation language, with its gate figures and review state."""
    topics = sorted(result.topics, key=lambda t: (t.lang, LEVELS.index(t.level) if t.level in LEVELS else 99,
                                                  t.order, t.id))
    texts = [(t, e, t.texts[e]) for t in topics for e in sorted(t.texts)]
    unreviewed = [(t, e, x) for t, e, x in texts if (t.id, x.sha256) not in result.reviewed]
    out = [
        "# Grammar topics: review",
        "",
        "Written by `Scripts/build_grammar.py` (docs/specs/0133-grammar.md, \"Build step\"); do not edit it. "
        "Each topic as the app shows it, in every explanation language, with its forms tables rendered from the "
        "Wiktionary word forms. A text marked **not reviewed** has a hash that is not in "
        "`Scripts/data/grammar/reviewed.tsv`.",
        "",
    ]
    if not topics:
        out += ["No topics yet: `Scripts/data/grammar/<explain_lang>/` holds none (#173).", ""]
    else:
        size = sum(result.sizes.values())
        out += [f"{len(topics)} topics, {len(texts)} texts, {len(unreviewed)} not reviewed. "
                + (f"Grammar tables {size:,} bytes (dbstat), at most {size_limit:,}." if size else
                   "Tables not written (a gate failed).")]
        out.append("")
    if result.errors:
        out += ["## Gate failures", ""] + [f"- {e}" for e in result.errors] + [""]

    titles = {t.id: (t.texts.get(FALLBACK) or next(iter(t.texts.values()))).title for t in topics}
    for lang in sorted({t.lang for t in topics}):
        sources = data.execute("SELECT source, display_name FROM dict_metadata WHERE from_lang = ? "
                               "AND to_lang = 'eng' ORDER BY rowid", (lang,)).fetchall()
        lists = list_words(data, lang)
        out += [f"## {LANGUAGES[lang]['name']}", ""]
        if not lists:
            out += [f"The {LANGUAGES[lang]['name']} A1 and A2 lists are empty, so example words are not "
                    "checked against them.", ""]
        for topic in [t for t in topics if t.lang == lang]:
            out += review_topic(topic, sources, titles, lists, result.reviewed, data)

    if texts:
        out += ["## Text hashes", "",
                "A reviewed text gets a line `<topic id><TAB><sha256><TAB><review date>` in `reviewed.tsv`.", "",
                "| Topic | Text | sha256 | Reviewed |", "|---|---|---|---|"]
        out += [f"| `{topic.id}` | {explain} | `{text.sha256}` | "
                f"{result.reviewed.get((topic.id, text.sha256), 'no')} |" for topic, explain, text in texts]
        out.append("")
    return "\n".join(out)


def review_topic(topic: Topic, sources: list, titles: dict, lists: set, reviewed: dict,
                 data: sqlite3.Connection) -> list[str]:
    explains = sorted(topic.texts)
    state = [e for e in explains if (topic.id, topic.texts[e].sha256) not in reviewed]
    out = [f"### {topic.level} · {topic.order}. {titles[topic.id]}", "",
           f"`{topic.id}`" + (f" · **not reviewed**: {', '.join(state)}" if state else " · reviewed"), "",
           "| | " + " | ".join(explains) + " |", "|---" * (len(explains) + 1) + "|"]
    figures = (("Rule words", lambda x: x.rule_words), ("Tables", lambda x: x.tables),
               ("Examples", lambda x: len(x.examples)), ("Watch out", lambda x: x.watch_out),
               ("sha256", lambda x: f"`{x.sha256[:12]}`"))
    for name, value in figures:
        out.append(f"| {name} | " + " | ".join(str(value(topic.texts[e])) for e in explains) + " |")
    out.append("")
    links = topic.links
    if links["words"]:
        out.append("Words:")
        for word in links["words"]:
            senses = []
            for source, display in sources:
                row = data.execute("SELECT definition FROM entries WHERE word = ? AND source = ?",
                                   (word, source)).fetchone()
                if row:
                    senses.append(f"{first_sense(row[0])} ({display})")
            out.append(f"- {word}: " + ("; ".join(senses) or "no entry"))
        out.append("")
    if links["topics"]:
        out.append("Related topics: " + ", ".join(f"`{t}` {titles.get(t, '?')}" for t in links["topics"]))
        out.append("")
    extra = [f"Tenses: {', '.join(links['tenses'])}" if links["tenses"] else "",
             f"Classes: {', '.join(links['classes'])}" if links["classes"] else ""]
    if any(extra):
        out += [". ".join(e for e in extra if e) + ".", ""]
    if lists:
        base = topic.texts.get(FALLBACK) or next(iter(topic.texts.values()))
        outside = outside_lists([g for g, _ in base.examples], data, lists)
        out += [f"Example words in no {LANGUAGES[topic.lang]['name']} A1 or A2 list: "
                + (", ".join(outside) if outside else "none") + ".", ""]
    for explain in explains:
        text = topic.texts[explain]
        out += [f"#### {EXPLAIN[explain]['name']}: {text.title}", ""]
        for line in text.body.split("\n"):
            out.append("##" + line if line.strip() in (EXAMPLES_HEADING, WATCH_OUT_HEADING) else line)
        out.append("")
    return out


# ---------------------------------------------------------------------------
# Standalone and self-check
# ---------------------------------------------------------------------------

def new_database(path: str) -> sqlite3.Connection:
    """A file with the dictionary file's core schema plus `SCHEMA`."""
    from build_dictionaries import SCHEMA as CORE_SCHEMA
    conn = sqlite3.connect(path)
    conn.execute("PRAGMA page_size = 4096")
    conn.execute("PRAGMA journal_mode = DELETE")
    conn.executescript(CORE_SCHEMA)
    conn.executescript(SCHEMA)
    return conn


def read_only(path: Path) -> sqlite3.Connection:
    return sqlite3.connect(f"file:{urllib.parse.quote(str(path.resolve()))}?mode=ro", uri=True)


def standalone(output: Path, dictionary: Path, source: Path, report: Path, allow_unreviewed: bool) -> int:
    if not dictionary.is_file():
        sys.exit(f"{dictionary} does not exist: build it with build_dictionaries.py")
    output.unlink(missing_ok=True)
    conn = new_database(str(output))
    data = read_only(dictionary)
    try:
        run(conn, data, source, report, allow_unreviewed)
        conn.execute("VACUUM")
    except GrammarGateError as error:
        conn.close()
        output.unlink(missing_ok=True)
        print(error)
        return 1
    finally:
        data.close()
    hashes = table_hashes(conn)
    conn.close()
    for table, (rows, digest) in hashes.items():
        print(f"  {table:<14} {rows:>5} rows  {digest}")
    print(f"Wrote {output} ({output.stat().st_size:,} bytes)")
    return 0


# Self-check: the fixture topics and the reason each invalid one fails with
# (a part of its one error). Each invalid case is built together with the
# valid topic. A case folder without a rus/ file is built with English texts
# required only, so its one file shows its one reason; the cases about the
# Russian texts have their rus/ files.
VALID = FIXTURES / "valid"
INVALID = FIXTURES / "invalid"
INVALID_CASES = {
    "unknown-key": "unknown front matter key 'colour'",
    "id-not-file-name": "is not the file name",
    "id-without-language": "must start with 'ell-'",
    "bad-level": "level 'A0' is not one of",
    "order-taken": "order 1 of ell A1 is taken",
    "front-matter-differs": "front matter differs from eng/ell-front-matter-differs.md",
    "no-russian-text": "no rus text",
    "no-english-text": "no eng text",
    "unknown-explanation-language": "no labels for the explanation language 'fra'",
    "no-title": "no '# Title' line first",
    "long-rule": "the rule has 121 words, at most 120",
    "no-table": "0 tables, needs 1 to 3",
    "four-tables": "4 tables, needs 1 to 3",
    "two-examples": "2 examples, needs 3 to 5",
    "no-translation": "needs one translation line under it, has 0",
    "example-not-greek": "the first line has no Greek letters",
    "translation-script": "the translation must be in Cyrillic letters, has Latin",
    "three-watch-outs": "3 Watch out items, needs 1 or 2",
    "blocks-out-of-order": "blocks out of order",
    "text-after-tables": "text after the tables",
    "unknown-word": "word 'γράφως' is no headword",
    "unknown-topic": "topic 'ell-nothing' is no ell topic",
    "unknown-tense": "tense 'past' is no ConjugationTense",
    "unknown-class": "class 'verb.conj3' is not one of",
    "no-links": "no word or topic link",
    "thirteen-words": "13 words, at most 12",
    "no-lemma": "κάνος has no noun table",
    "empty-cell": "έχω has no active aorist form for εγώ",
    "typed-verb-table": "a topic with tenses has no typed table",
    "latin-lookalike": "Latin 'o' in Greek text",
    "cyrillic-lookalike": "Cyrillic 'о' in Greek text 'τо'",
    "no-rule": "no rule",
    "six-examples": "6 examples, needs 3 to 5",
    "no-watch-out-items": "0 Watch out items, needs 1 or 2",
    "wrong-part-of-speech": "σπίτι has no verb table",
    "unaccented-word": "word 'γραφω' is no headword",
    "content-differs": "classes verb.conj1 differ from 0133's Content (verb)",
}


def fixture_database() -> sqlite3.Connection:
    """The forms of the kaikki sample and the headwords of the fixture
    topics, in memory."""
    import build_forms
    conn = new_database(":memory:")
    conn.executescript(build_forms.SCHEMA)
    conn.executescript((SCRIPTS_DIR / "wordlists_schema.sql").read_text(encoding="utf-8"))
    lines = build_forms.FIXTURE.read_text(encoding="utf-8").splitlines()
    build_forms.write_tables(conn, build_forms.collect(lines, build_forms.read_allowlist()), "self-check")
    conn.execute("INSERT INTO dict_metadata(source, display_name, from_lang, to_lang) "
                 "VALUES ('freedict-ell-eng', 'Greek – English (FreeDict)', 'ell', 'eng')")
    headwords = ["γράφω", "σπίτι", "καλός", "βλέπω", "κάνω", "έχω", "πηγαίνω", "ο", "η", "το", "ένας", "δύο",
                 "τρία", "τέσσερα", "πέντε", "έξι", "επτά", "οκτώ", "εννέα", "δέκα", "έντεκα", "δώδεκα",
                 "δεκατρία"]
    conn.executemany("INSERT INTO entries(word, word_normalized, definition, source) "
                     "VALUES (?, ?, '1. test', 'freedict-ell-eng')",
                     [(w, normalize_greek(w)) for w in headwords])
    return conn


def merged_source(folders: list[Path], into: Path) -> Path:
    """The topic files of `folders` in one source folder, with their
    top-level files (the valid topic's README), which are no topics."""
    for folder in folders:
        for path in sorted(folder.glob("*.md")) + sorted(folder.glob("*/*.md")):
            target = into / path.relative_to(folder)
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(path.read_bytes())
    return into


def self_check() -> int:
    """Renders the fixture forms, builds the valid topic twice and every
    invalid topic once, and checks the results."""
    checks: list[tuple[str, bool]] = []
    data = fixture_database()
    paradigms = Paradigms(data)

    def verb(word: str, tense: str, person: str, voice: str = "active") -> str:
        return " / ".join(tense_forms(voice_forms(paradigms.cells("ell", word, "verb"))[voice], tense, person))

    def noun(word: str, case: str, number: str, pos: str = "noun") -> str:
        return " / ".join(nominal_forms(paradigms.cells("ell", word, pos), False).get((case, number), []))

    def adjective(word: str, case: str, number: str, gender: str) -> str:
        return " / ".join(nominal_forms(paradigms.cells("ell", word, "adj"), True).get((case, number, gender), []))

    checks += [
        ("γράφω aorist: έγραψα, γράψαμε, έγραψαν / γράψαν / γράψανε (variants in table order)",
         (verb("γράφω", "aorist", "1sg"), verb("γράφω", "aorist", "1pl"), verb("γράφω", "aorist", "3pl"))
         == ("έγραψα", "γράψαμε", "έγραψαν / γράψαν / γράψανε")),
        ("γράφω future: θα γράψω", verb("γράφω", "future", "1sg") == "θα γράψω"),
        ("γράφω imperative simple: γράψε, γράψτε / γράφτε; only εσύ and εσείς",
         (verb("γράφω", "imperativeSimple", "2sg"), verb("γράφω", "imperativeSimple", "2pl"))
         == ("γράψε", "γράψτε / γράφτε") and tense_persons("imperativeSimple") == ("2sg", "2pl")),
        ("γράφω subjunctive simple: να γράψω", verb("γράφω", "subjunctiveSimple", "1sg") == "να γράψω"),
        ("γράφω perfect: έχω γράψει", verb("γράφω", "perfect", "1sg") == "έχω γράψει"),
        ("έχω, no dependent form: θα έχω, να έχω, no future continuous",
         [verb("έχω", tense, "1sg") for tense in ("future", "subjunctiveSimple", "futureContinuous")]
         == ["θα έχω", "να έχω", ""]),
        ("πηγαίνω aorist: πήγα; βλέπω: είδα", verb("πηγαίνω", "aorist", "1sg").split(" / ")[0] == "πήγα"
         and verb("βλέπω", "aorist", "1sg").split(" / ")[0] == "είδα"),
        ("θυμάμαι: main voice passive",
         main_voice(voice_forms(paradigms.cells("ell", "θυμάμαι", "verb"))) == "passive"),
        ("σπίτι: σπίτι, σπιτιού, σπίτια",
         [noun("σπίτι", case, number) for case, number in
          (("nominative", "singular"), ("genitive", "singular"), ("nominative", "plural"))]
         == ["σπίτι", "σπιτιού", "σπίτια"]),
        ("καλός: καλός, καλή, καλό; καλούς",
         [adjective("καλός", "nominative", "singular", gender) for gender in GENDERS]
         + [adjective("καλός", "accusative", "plural", "masculine")] == ["καλός", "καλή", "καλό", "καλούς"]),
        ("the rule word count skips marks and letterless tokens",
         word_count(["- -ος, *έγραψα*, ~~εδιάβασα~~ — 1, 2 and **3**"]) == 4),
        ("a caption is one bold span, not a rule line that starts and ends in bold",
         bool(CAPTION.fullmatch("**Most verbs**")) and not CAPTION.fullmatch("**ο** and **η**")),
    ]

    with tempfile.TemporaryDirectory() as folder:
        valid = merged_source([VALID], Path(folder) / "valid")
        # Valid, reviewed by a reviewed.tsv of its own hashes; twice.
        first = compile_topics(valid, data, allow_unreviewed=True)
        checks.append(("the valid topic passes every gate but the review: "
                       + ("; ".join(first.errors) or "no error"), not first.errors))
        checks.append(("the top-level README.md is no topic",
                       (valid / "README.md").is_file() and [t.id for t in first.topics] == ["ell-valid"]))
        texts = {e: t for topic in first.topics for e, t in topic.texts.items()}
        rows = [f"ell-valid\t{t.sha256}\t2026-11-0{i}" for i, t in enumerate(texts.values(), 5)]
        (valid / "reviewed.tsv").write_text("topic_id\tsha256\tdate\n" + "\n".join(rows) + "\n", encoding="utf-8")
        hashes = []
        for _ in range(2):
            conn = new_database(":memory:")
            run(conn, data, valid, None)
            hashes.append(table_hashes(conn))
            source_row = conn.execute("SELECT id, kind, version, license FROM data_source").fetchall()
        checks.append(("two builds give equal table hashes", hashes[0] == hashes[1]))
        checks.append(("one topic, two texts, its links", [h[0] for h in hashes[0].values()] == [1, 2, 7]))
        checks.append(("the data_source row, versioned by the last review",
                       source_row == [("libredict-grammar-ell", "grammar", "2026-11-06", "CC BY-SA 4.0")]))
        eng, rus = texts["eng"], texts["rus"]
        checks += [
            ("the forms comment of a verb table",
             "<!-- forms words=γράφω,βλέπω,κάνω tense=aorist voice=active -->" in eng.body),
            ("the aorist rows: | εγώ | έγραψα | …",
             f"| εγώ | έγραψα | {verb('βλέπω', 'aorist', '1sg')} | {verb('κάνω', 'aorist', '1sg')} |" in eng.body),
            ("a noun table with a genitive row, its header from headers",
             "<!-- forms words=σπίτι pos=noun rows=nominative.singular,genitive.singular,nominative.plural -->"
             in eng.body and "| | το σπίτι |" in eng.body and "| Genitive singular | σπιτιού |" in eng.body),
            ("an adjective table by gender, with a default caption",
             "**Adjective endings**" in eng.body and "| | Masculine | Feminine | Neuter |" in eng.body
             and "| Nominative singular | καλός | καλή | καλό |" in eng.body),
            ("Russian row headers and captions",
             all(line in rus.body for line in (
                 "| Именительный, ед. ч. | καλός | καλή | καλό |", "| | Мужской род | Женский род | Средний род |",
                 "**Окончания прилагательных**", "| Родительный, ед. ч. | σπιτιού |"))),
            ("the body starts after the title and keeps the markers",
             not eng.body.startswith("#") and "\n## Examples\n" in eng.body and "\n## Watch out\n" in eng.body),
        ]

        # The real step into a full file with a Greek A1 list, then the real
        # cut (packs.json): the rows the app reads land in the Greek pack only.
        import build_morphy
        import cut_packs
        full_path = Path(folder) / "full.sqlite"
        full = sqlite3.connect(full_path)
        data.commit()  # a backup waits for the source's open transaction
        data.backup(full)
        full.executescript(build_morphy.SCHEMA)  # the bundle's whole tables
        full.execute("INSERT INTO wordlist(id, lang, series, level, level_ord, word_count, data_source) "
                     "VALUES ('ky-ell-a1', 'ell', 'ky-ell', 'A1', 1, 3, 'ky-ell')")
        full.executemany("INSERT INTO wordlist_item(series, term, headword, level, level_ord, seq, sort_key) "
                         "VALUES ('ky-ell', ?, ?, 'A1', 1, ?, ?)",
                         [(w, w, i, w) for i, w in enumerate(("γράφω", "σπίτι", "καλός"))])
        full.commit()
        report = Path(folder) / "grammar-review.md"
        run(full, full, valid, report)
        full.close()
        ddl, data_tables, names = cut_packs.schema_of(full_path)
        _, _, bundle, packs, _ = cut_packs.load_map()
        cuts = {o.name: cut_packs.cut(full_path, o, Path(folder) / f"{o.name}.sqlite", ddl, data_tables, names)
                for o in [bundle] + packs}
        grammar = {name: [c.counts[t] for t in TABLES] for name, c in cuts.items()}
        credits = {}
        for name, c in cuts.items():
            with closing(sqlite3.connect(c.path)) as conn:
                credits[name] = [r for (r,) in conn.execute("SELECT id FROM data_source WHERE kind = 'grammar'")]
        pack = sqlite3.connect(cuts["ell"].path)
        checks.append(("the cut puts the topic, its texts, links and credit in the Greek pack only",
                       grammar.pop("ell") == [1, 2, 7] and all(v == [0, 0, 0] for v in grammar.values())
                       and credits.pop("ell") == ["libredict-grammar-ell"] and not any(credits.values())))
        checks.append(("the Greek pack's rows are the step's: the Russian text, the word links in order, headwords",
                       pack.execute("SELECT title, body FROM grammar_text WHERE topic_id = 'ell-valid' "
                                    "AND explain_lang = 'rus'").fetchone() == (rus.title, rus.body)
                       and pack.execute("SELECT group_concat(key, ',') FROM (SELECT key FROM grammar_link "
                                        "WHERE kind = 'word' AND key IN (SELECT word FROM entries) ORDER BY ord)"
                                        ).fetchone() == ("γράφω,σπίτι,καλός",)))
        pack.close()
        document = report.read_text(encoding="utf-8")
        checks.append(("the review document: state, words with their first sense, both texts, list words",
                       all(line in document.split("\n") for line in (
                           "`ell-valid` · reviewed", "- γράφω: test (Greek – English (FreeDict))",
                           "#### Russian: " + rus.title, "| εγώ | έγραψα | είδα | έκανα / έκαμα |",
                           # έγραψα is a form of γράφω, a list word; είδα of βλέπω, which is in no list
                           "Example words in no Greek A1 or A2 list: Χθες, ένα, γράμμα, Το, είναι, μεγάλο, Είδα, "
                           "έναν, φίλο."))))
        os.remove(valid / "reviewed.tsv")
        unreviewed = compile_topics(valid, data, allow_unreviewed=False)
        checks.append(("an unreviewed text fails without --allow-unreviewed",
                       len(unreviewed.errors) == 2 and all("not reviewed" in e for e in unreviewed.errors)))
        try:
            run(new_database(":memory:"), data, valid, None, allow_unreviewed=True, size_limit=1_000)
            checks.append(("tables over the size limit fail", False))
        except GrammarGateError as error:
            checks.append(("tables over the size limit fail", any("at most 1,000" in e for e in error.errors)))

        cases = sorted(p.name for p in INVALID.iterdir() if p.is_dir())
        checks.append(("one fixture folder per invalid case", cases == sorted(INVALID_CASES)))
        english_only = {lang: {**config, "explain": (FALLBACK,)} for lang, config in LANGUAGES.items()}
        for case in cases:
            source = merged_source([VALID, INVALID / case], Path(folder) / case)
            needs_russian = (INVALID / case / "rus").is_dir() or case == "no-russian-text"
            result = compile_topics(source, data, allow_unreviewed=True,
                                    languages=LANGUAGES if needs_russian else english_only)
            reason = INVALID_CASES.get(case, "?")
            ok = len(result.errors) == 1 and reason in result.errors[0]
            checks.append((f"invalid {case}: " + ("; ".join(result.errors) or "no error"), ok))
        # The long rule less one word: 120 words pass.
        source = merged_source([VALID, INVALID / "long-rule"], Path(folder) / "rule-of-120")
        path = source / "eng" / "ell-long-rule.md"
        path.write_text(path.read_text(encoding="utf-8").replace(" word.", ".", 1), encoding="utf-8")
        result = compile_topics(source, data, allow_unreviewed=True, languages=english_only)
        checks.append(("a rule of 120 words passes: " + ("; ".join(result.errors) or "no error"), not result.errors))

    failed = [name for name, ok in checks if not ok]
    for name, ok in checks:
        print(f"  {'ok  ' if ok else 'FAIL'} {name}")
    if failed:
        print(f"FAILED: {len(failed)} of {len(checks)} checks")
        return 1
    print(f"OK: grammar self-check passed ({len(checks)} checks).")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--self-check", action="store_true", help="Offline check on the fixtures.")
    mode.add_argument("--standalone", type=Path, metavar="OUT",
                      help="Build the grammar tables alone into OUT, with the review document.")
    parser.add_argument("--dictionary", type=Path,
                        help="With --standalone: the built full file whose dictionaries and forms the topics use "
                             "(default: dictionaries-full.sqlite in Scripts/.cache).")
    parser.add_argument("--source", type=Path, default=SOURCE_DIR,
                        help="The topic sources (default: Scripts/data/grammar).")
    parser.add_argument("--report", type=Path, default=REPORT,
                        help="Where to write the review document (default: Scripts/reports/grammar-review.md).")
    parser.add_argument("--allow-unreviewed", action="store_true",
                        help="Skip the review gate while drafting. Never for the committed pack.")
    args = parser.parse_args()
    if args.self_check:
        return self_check()
    import inputs
    dictionary = args.dictionary or inputs.DEFAULT_CACHE_DIR / "dictionaries-full.sqlite"
    return standalone(args.standalone.resolve(), dictionary.resolve(), args.source.resolve(),
                      args.report.resolve(), args.allow_unreviewed)


if __name__ == "__main__":
    sys.exit(main())
