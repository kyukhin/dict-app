#!/usr/bin/env python3
"""
drill_examples.py
The tool around the drill-example data files of `Scripts/data/drill-examples/`
(docs/specs/0134-example-sentences.md, "Drill examples", "Data files"). The
build (`build_examples.py`) reads the files but never runs this tool, and stays
offline. Nothing here downloads anything: a generator gets the cells and the
list words, no web content.

Usage (from the repository root):
    python3 Scripts/drill_examples.py --todo [--scope A2/A2] [--source FILE] [--out DIR]
        the open cells of a scope (verb lists up to / tenses up to; the
        default A2/A2 is 2.0's): no sentence in FILE (a built full file or
        Greek pack; default the cache's full file) and not in
        ell-skipped.tsv, with what the generator needs: the cell, its form
        and spellings, the verb, its list term, meaning and level, the tense
        title, voice and person, and its homographs. With --out, DIR/todo.tsv
        and the allowed words, DIR/words-<level>.tsv; else todo.tsv on stdout
    python3 Scripts/drill_examples.py --add FILE
        appends FILE's rows (the data file's columns; `id` ignored, `page`
        and `texts_sha256` optional) to ell.tsv with new ids in their
        source's range; a Wiktionary row without a page gets its entry from
        the pinned subset, a checked row (`check` ok) without a
        `texts_sha256` the hash of its text, English and Russian as added:
        the check was given on those (#371)
    python3 Scripts/drill_examples.py --sample 50 [--base REV] [--source FILE]
        writes Scripts/reports/drill-examples-sample.md: rows that did not
        come from Tatoeba, drawn with a seed taken from ell.tsv's sha256, so
        nobody picks them; the form is highlighted when FILE is there. With
        --base, only the rows a ticket adds: those whose id is not in REV's
        ell.tsv (a git revision, #371)
    python3 Scripts/drill_examples.py --pairs [--source FILE] [--out DIR]
        the cell rows of FILE (a built full file or Greek pack) whose (cell,
        sentence) no verdict covers: neither the data row's own cell nor a
        verdict in ell-readings.tsv, each tied to the Greek, English and
        Russian FILE ships with the sentence (`texts_sha256`). The next batch
        of the check (#371), one row per pair, with the hash its verdict
        line takes; DIR/pairs.tsv, else stdout
"""

from __future__ import annotations

import argparse
import collections
import hashlib
import os
import random
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_examples as bx  # noqa: E402
import drill_cells  # noqa: E402
import inputs  # noqa: E402

DATA = bx.DRILL_DATA
SAMPLE_REPORT = bx.SCRIPTS_DIR / "reports" / "drill-examples-sample.md"
DEFAULT_SOURCE = inputs.DEFAULT_CACHE_DIR / "dictionaries-full.sqlite"
# The drill's tense titles (0132) and persons, as the generator reads them.
TENSE_TITLES = {
    "present": "Present", "imperfect": "Imperfect", "aorist": "Aorist (simple past)",
    "future": "Future: simple form", "imperativeContinuous": "Imperative: continuous form",
    "imperativeSimple": "Imperative: simple form", "futureContinuous": "Future: continuous form",
    "perfect": "Perfect", "pluperfect": "Pluperfect", "futurePerfect": "Future perfect",
    "subjunctiveContinuous": "Subjunctive: continuous form (να)", "subjunctiveSimple": "Subjunctive: simple form (να)",
}
PRONOUNS = dict(zip(drill_cells.PERSONS, ("εγώ", "εσύ", "αυτός", "εμείς", "εσείς", "αυτοί")))
TODO_COLUMNS = ("cell", "form", "forms", "verb", "list_term", "translation", "level", "tense", "voice", "person",
                "homograph", "other_readings")
PAIR_COLUMNS = ("cell", "sentence_id", "texts_sha256", "source", "form", "text", "eng", "rus")


def read_rows() -> list[dict[str, str]]:
    return bx.read_tsv(DATA / bx.DATA_FILE, bx.DATA_COLUMNS)


def write_rows(rows: list[dict[str, str]]) -> None:
    """ell.tsv: the header, then the rows sorted by id."""
    with open(DATA / bx.DATA_FILE, "w", encoding="utf-8", newline="\n") as f:
        f.write("\t".join(bx.DATA_COLUMNS) + "\n")
        for r in sorted(rows, key=lambda r: int(r["id"])):
            f.write("\t".join(r[c] for c in bx.DATA_COLUMNS) + "\n")


def label(key: str) -> str:
    """A cell key as the drill names it: γράφω · Aorist (simple past) · εγώ."""
    verb, facet, person = key.split("|")
    tense, voice = facet.split(".")
    return (f"{verb} · {TENSE_TITLES.get(tense, tense)}" + (" · passive" if voice == "passive" else "")
            + f" · {PRONOUNS.get(person, person)}")


def add(path: Path) -> int:
    rows = read_rows()
    lines = path.read_text(encoding="utf-8").split("\n")
    header = lines[0].split("\t")
    lacking = [c for c in bx.DATA_COLUMNS if c not in header and c not in ("id", "page", "texts_sha256")]
    if lacking:
        sys.exit(f"{path}: no column {', '.join(lacking)}")
    texts = {r["text"] for r in rows}
    # Above every id a reading verdict names too, so a verdict never moves to
    # another sentence when its row was removed (CodeRabbit on #370).
    # ponytail: a removed id nothing names may come back; nothing else keeps ids.
    named = [int(r["sentence_id"]) for r in bx.read_tsv(DATA / bx.READINGS_FILE, bx.READING_COLUMNS)]
    next_id = {source: max([int(r["id"]) for r in rows if r["source"] == source]
                           + [i for i in named if base < i < base + 1_000_000_000], default=base) + 1
               for source, base in bx.SOURCE_IDS.items()}
    pin, added = None, 0
    for number, line in enumerate(lines[1:], 2):
        if not line:
            continue
        fields = dict(zip(header, line.split("\t")))
        row = {c: bx.nfc(fields.get(c, "")) for c in bx.DATA_COLUMNS}
        if row["source"] not in bx.SOURCE_IDS or not row["cell"] or not row["text"]:
            sys.exit(f"{path}:{number}: a source of {' or '.join(bx.SOURCE_IDS)}, a cell and a text are needed")
        if row["text"] in texts:
            sys.exit(f"{path}:{number}: the text is in {bx.DATA_FILE} already")
        if row["source"] == "wiktionary" and not row["page"]:
            pin = pin or bx.wiktionary_examples(bx.kaikki_subset()[0])
            row["page"] = pin.get(row["text"], (0, "", ""))[1]
        if row["check"] == "ok" and not row["texts_sha256"]:
            row["texts_sha256"] = bx.texts_hash(row["text"], row["eng"], row["rus"])
        row["id"] = str(next_id[row["source"]])
        next_id[row["source"]] += 1
        texts.add(row["text"])
        rows.append(row)
        added += 1
    write_rows(rows)
    print(f"Added {added} rows to {DATA / bx.DATA_FILE}; build_examples.py checks them (the form gate)")
    return 0


def todo(source: Path, scope: str, out: Path | None) -> int:
    verbs_up_to, tenses_up_to = scope.upper().split("/")
    verb_level = {"A1": 1, "A2": 2, "B1": 3}[verbs_up_to]
    tense_level = drill_cells.LEVELS.index(tenses_up_to)
    reader = bx.read_only(source)
    pool, cells = drill_cells.drill_cells(reader)
    covered = {w for (w,) in reader.execute("SELECT word FROM example_word WHERE lang = 'ell' AND instr(word, '|') > 0")}
    skipped = {r["cell"] for r in bx.read_tsv(DATA / bx.SKIPPED_FILE, bx.SKIPPED_COLUMNS)}
    homo = bx.homographs(cells)
    by_spelling: dict[str, list[drill_cells.DrillCell]] = collections.defaultdict(list)
    for c in cells:
        for form in dict.fromkeys(c.forms):
            by_spelling[form].append(c)
    verbs = {v.word: v for v in pool}
    items = {seq: (term, meaning) for seq, term, meaning in reader.execute(
        "SELECT seq, term, translation FROM wordlist_item WHERE series = ?", (bx.GREEK_LISTS,))}
    rows = []
    for c in cells:
        if c.verb_level > verb_level or c.tense_level > tense_level or c.key in covered or c.key in skipped:
            continue
        verb = verbs[c.verb]
        term, meaning = items.get(verb.seq, (verb.word, ""))
        reading = any((c.key, form) in homo.reading for form in c.forms)
        kind = ("other-reading" if reading else
                "aspect-only" if any((c.key, form) in homo.aspect for form in c.forms) else "")
        others = "; ".join(sorted({f"{form} = {o.verb} {o.facet} {o.person}" for form in c.forms
                                   for o in by_spelling[form] if o.key != c.key})) if reading else ""
        rows.append((c.key, c.forms[0], " / ".join(c.forms), verb.citation, term, meaning or "",
                     bx.LEVEL_NAMES[c.verb_level], TENSE_TITLES[c.tense], c.voice, PRONOUNS[c.person], kind, others))
    text = "\n".join("\t".join(r) for r in [TODO_COLUMNS, *rows]) + "\n"
    if out is None:
        sys.stdout.write(text)
        return 0
    out.mkdir(parents=True, exist_ok=True)
    (out / "todo.tsv").write_text(text, encoding="utf-8")
    for level in range(1, verb_level + 1):
        words = reader.execute("SELECT term, COALESCE(pos, ''), COALESCE(translation, '') FROM wordlist_item "
                               "WHERE series = ? AND level_ord = ? ORDER BY sort_key", (bx.GREEK_LISTS, level))
        (out / f"words-{bx.LEVEL_NAMES[level]}.tsv").write_text(
            "\n".join("\t".join(r) for r in [("term", "pos", "translation"), *words]) + "\n", encoding="utf-8")
    print(f"{len(rows):,} open cells in {out / 'todo.tsv'}, the allowed words in {out}/words-*.tsv", file=sys.stderr)
    return 0


def base_ids(rev: str) -> set[str]:
    """The ids of ell.tsv at a git revision (#371: the rows a ticket adds
    are the others)."""
    relative = (DATA / bx.DATA_FILE).relative_to(bx.REPO).as_posix()
    shown = subprocess.run(["git", "-C", str(bx.REPO), "show", f"{rev}:{relative}"], capture_output=True, text=True,
                           encoding="utf-8")
    if shown.returncode != 0:
        sys.exit(f"--base {rev}: {shown.stderr.strip()}")
    lines = shown.stdout.split("\n")
    column = lines[0].split("\t").index("id")
    return {line.split("\t")[column] for line in lines[1:] if line}


def sample(count: int, source: Path | None, base: str | None = None) -> int:
    path = DATA / bx.DATA_FILE
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    rows = read_rows()
    if base is not None:
        old = base_ids(base)
        rows = [r for r in rows if r["id"] not in old]
    chosen = sorted(random.Random(int(digest, 16)).sample(rows, min(count, len(rows))), key=lambda r: int(r["id"]))
    forms: dict[str, tuple[str, ...]] = {}
    infinitives: frozenset[str] = frozenset()
    if source is not None and source.is_file():
        reader = bx.read_only(source)
        forms = {c.key: c.forms for c in drill_cells.drill_cells(reader)[1]}
        infinitives = bx.aorist_infinitives(reader)
    by_source = collections.Counter(r["source"] for r in rows)
    out = ["# Drill examples: a sample for review", "",
           "Written by `Scripts/drill_examples.py --sample` "
           "([0134-example-sentences.md](../../docs/specs/0134-example-sentences.md), \"Checks\", 3). Do not edit "
           "by hand.", "",
           f"{len(chosen)} of the {len(rows):,} rows of `Scripts/data/drill-examples/{bx.DATA_FILE}`"
           + (f" that `{base}`'s file does not hold, the rows the ticket adds" if base is not None else "") + " (" +
           ", ".join(f"{source} {by_source[source]:,}" for source in bx.SOURCE_IDS) + "), drawn by "
           f"`random.Random(int(sha256, 16)).sample(rows, {count})` with the file's sha256 "
           f"`{digest}`, so nobody picks them; in id order.", "",
           "kyukhin reads the Greek, the English and the Russian. A wrong form or a wrong meaning: its cause is "
           "fixed, the rows it touched are generated again and a new sample is drawn. A Wiktionary row's Greek and "
           "English are Wiktionary's; its Russian is generated.", "",
           "| # | id | Source | Cell | Greek | English | Russian |", "|---|---|---|---|---|---|---|"]
    for number, r in enumerate(chosen, 1):
        toks = bx.drill_tokens(r["text"])
        span = next((s for form in forms.get(r["cell"], ()) if (s := bx.find_form(toks, form, infinitives))), None)
        greek = bx.highlighted(r["text"], span[0], span[1] - span[0]) if span else bx.cell(r["text"])
        origin = f"Wiktionary ({r['page']})" if r["source"] == "wiktionary" else r["source"]
        out.append(f"| {number} | {r['id']} | {bx.cell(origin)} | {bx.cell(label(r['cell']))} | {greek} | "
                   f"{bx.cell(r['eng'])} | {bx.cell(r['rus'])} |")
    SAMPLE_REPORT.write_text("\n".join(out) + "\n", encoding="utf-8")
    print(f"Wrote {SAMPLE_REPORT} ({len(chosen)} rows, seed from sha256 {digest[:12]})")
    return 0


def pairs(source: Path, out: Path | None) -> int:
    """The cell rows of a built file that no verdict covers (#371): the pair
    gate's misses (`build_examples.unchecked_pairs`), as the next batch of
    the check, in sentence id order."""
    reader = bx.read_only(source)
    found = reader.execute("""
        SELECT w.word, w.sentence_id, w.form_start, w.form_length, s.text,
               (SELECT text FROM example_translation t WHERE t.sentence_id = s.id AND t.lang = 'eng'),
               (SELECT text FROM example_translation t WHERE t.sentence_id = s.id AND t.lang = 'rus')
        FROM example_word w JOIN example_sentence s ON s.id = w.sentence_id
        WHERE w.lang = 'ell' AND instr(w.word, '|') > 0 ORDER BY w.sentence_id, w.word""").fetchall()
    data = bx.read_drill_data(DATA, {}, "")
    texts = {sid: (text, eng or "", rus or "") for _, sid, _, _, text, eng, rus in found}
    verdicts = bx.data_verdicts(data, texts)
    stored = bx.Rows([], [], [("ell", key, 1, sid, start, length) for key, sid, start, length, *_ in found])
    open_ = set(bx.unchecked_pairs(stored, verdicts))
    names = ("tatoeba", "wiktionary", "generated")
    rows = [(key, str(sid), bx.texts_hash(*texts[sid]), names[bx.source_of(sid)], text[start:start + length], text,
             eng or "", rus or "") for key, sid, start, length, text, eng, rus in found if (key, sid) in open_]
    text = "\n".join("\t".join(r) for r in [PAIR_COLUMNS, *rows]) + "\n"
    if out is None:
        sys.stdout.write(text)
    else:
        out.mkdir(parents=True, exist_ok=True)
        (out / "pairs.tsv").write_text(text, encoding="utf-8")
    print(f"{len(rows):,} of {len(found):,} cell rows have no verdict"
          + (f": {out / 'pairs.tsv'}" if out is not None else ""), file=sys.stderr)
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--todo", action="store_true", help="List the open cells of a scope.")
    mode.add_argument("--add", type=Path, metavar="FILE", help="Append rows to ell.tsv with new ids.")
    mode.add_argument("--sample", type=int, metavar="N", help="Write the review sample of N rows.")
    mode.add_argument("--pairs", action="store_true", help="List the cell rows of --source that no verdict covers.")
    parser.add_argument("--scope", default="A2/A2", help="Verb lists up to / tenses up to (default A2/A2: 2.0).")
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE,
                        help="A built full file or Greek pack (default: the cache's full file).")
    parser.add_argument("--out", type=Path,
                        help="With --todo: write todo.tsv and words-<level>.tsv here; with --pairs: pairs.tsv.")
    parser.add_argument("--base", metavar="REV",
                        help="With --sample: draw only the rows whose id is not in REV's ell.tsv (a git revision).")
    args = parser.parse_args()
    if args.base and not args.sample:
        parser.error("--base goes with --sample")
    if args.add:
        return add(args.add)
    if args.sample:
        return sample(args.sample, args.source, args.base)
    if args.pairs:
        return pairs(args.source, args.out)
    return todo(args.source, args.scope, args.out)


if __name__ == "__main__":
    sys.exit(main())
