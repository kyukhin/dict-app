#!/usr/bin/env python3
"""
cut_packs.py
Cuts the full dictionary file into the files the app reads
(docs/specs/0237-downloads.md, "Build and release", "The catalog", "Files"):

  - `DictApp/DictApp/Resources/dictionaries.sqlite`, the English bundle:
    WordNet, morphy and the pack catalog;
  - `DictApp/DictApp/Resources/empty-pack.sqlite`, the stub: the same schema
    with no rows, attached for a pack that is not installed;
  - one file per language pack, as the xz release asset
    `Packs/<id>-<version>.sqlite.xz` (Git LFS; never in a target).

`Scripts/packs.json` says which sources, whole tables and filtered rows go
into which file. Every output has every table of the full file and fills
only its own; `PRAGMA user_version` is the format of all of them. Entry ids
move into the file's range, `ord << 32 + id`, so they never collide across
files and stay below 2^40. `<version>` is the first 12 hex digits of the
pack file's sha256, so an unchanged pack keeps its name, URL and asset.

Steps: build the full file (`build_dictionaries.build`, unless `--full`),
cut each output (schema, rows, `entries_fts` rebuilt, VACUUM), the stub,
the xz assets (`lzma`, preset 6, no integrity check: byte-identical to
Apple's `compression_tool -a lzma`; the sha256 does the checking), then the
catalog tables into the bundle, last (with `limited_pairs` as `catalog_pair`
rows). The checks fail the build: every row of every table but
`data_source` lands in exactly one file; every source in one file;
`word_count` equals rows; integrity and FTS `integrity-check` in each file;
ids in range and below 2^40; at most `max_packs` packs; a dictionary for
each limited pair's meanings; each asset decompresses to its file; the
bundle under 60 MB.

A pack whose version is not in the committed catalog needs
`--release-tag packs-YYYYMMDD`: its asset URL names that GitHub release,
which Kirill creates after the merge (`gh release create`). Unchanged packs
keep their URL. `--verify` rebuilds everything into a temp folder and
compares the bundle, the stub and each pack's `file_sha256` with the
committed ones; compression is not part of it, the committed asset is the
pinned one, and it must decompress to the rebuilt file.

Usage (from the repository root, with Scripts/requirements.txt installed):
    .venv/bin/python Scripts/cut_packs.py --release-tag packs-20261104
    .venv/bin/python Scripts/cut_packs.py --verify
    .venv/bin/python Scripts/cut_packs.py --full path/to/full.sqlite   # skip the full build
"""

from __future__ import annotations

import argparse
import hashlib
import json
import lzma
import os
import re
import shutil
import sqlite3
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_dictionaries as full_build  # noqa: E402
import inputs  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
PACKS_JSON = REPO / "Scripts/packs.json"
BUNDLE_PATH = REPO / "DictApp/DictApp/Resources/dictionaries.sqlite"
STUB_PATH = REPO / "DictApp/DictApp/Resources/empty-pack.sqlite"
ASSETS_DIR = REPO / "Packs"

FORMAT_VERSION = full_build.FORMAT_VERSION
BUNDLE_LIMIT = 60_000_000
ID_LIMIT = 1 << 40
XZ_PRESET = 6
RELEASE_TAG = re.compile(r"packs-\d{8}")
PACK_ID = re.compile(r"[a-z]{3}(-[a-z]+)?")
ASSET_URL = "https://github.com/{repository}/releases/download/{tag}/{name}"
# Tables that are not data: SQLite's own, the credits (copied where their
# data goes) and the catalog (the bundle's, filled last).
NOT_DATA = ("data_source", "catalog_pack", "catalog_source", "catalog_list", "catalog_pair", "sqlite_sequence")
LANG = re.compile(r"[a-z]{3}")


@dataclass
class Output:
    """One file of the cut: the bundle (ord 0), a pack, or the stub."""
    name: str
    ord: int
    lang: str = ""
    kind: str = ""
    sources: list[str] = field(default_factory=list)
    tables: list[str] = field(default_factory=list)
    rows: dict[str, str] = field(default_factory=dict)
    data_source: list[str] = field(default_factory=list)

    @property
    def is_pack(self) -> bool:
        return self.name not in ("bundle", "stub")


@dataclass
class Cut:
    """A cut file and what the checks read from it."""
    output: Output
    path: Path
    counts: dict[str, int]
    sha256: str = ""
    size: int = 0


def ro_uri(path: Path) -> str:
    return path.resolve().as_uri() + "?mode=ro&immutable=1"


def load_map() -> tuple[str, int, Output, list[Output], list[dict]]:
    """packs.json: the repository, the pack limit, the bundle, the packs in
    `ord` order and the limited pairs. Fails on a malformed map."""
    with open(PACKS_JSON, encoding="utf-8") as f:
        config = json.load(f)
    b = config["bundle"]
    bundle = Output("bundle", 0, "eng", "bundle", b.get("sources", []), b.get("tables", []),
                    b.get("rows", {}), b.get("data_source", []))
    packs = [Output(p["id"], p["ord"], p["lang"], p["kind"], p.get("sources", []), p.get("tables", []),
                    p.get("rows", {}), p.get("data_source", [])) for p in config["packs"]]
    packs.sort(key=lambda p: p.ord)
    problems = []
    if len(packs) > config["max_packs"]:
        problems.append(f"{len(packs)} packs, at most {config['max_packs']} (SQLite attaches 10 files; "
                        "a ninth language needs a design change)")
    if len({p.name for p in packs}) != len(packs) or len({p.ord for p in packs}) != len(packs):
        problems.append("pack ids and ords must be unique")
    for p in packs:
        if not PACK_ID.fullmatch(p.name) or p.ord < 1 or p.kind not in ("language", "lists"):
            problems.append(f"pack {p.name}: bad id, ord or kind")
    pairs = config.get("limited_pairs", [])
    for pair in pairs:
        langs = [pair.get(k, "") for k in ("lang", "via", "meanings_lang")]
        if not all(LANG.fullmatch(lang) for lang in langs) or langs[0] == langs[1] or langs[1] == langs[2]:
            problems.append(f"limited pair {pair}: lang, via and meanings_lang must be ISO 639-3 codes, "
                            "via neither lang nor meanings_lang")
    if len({(p["lang"], p["via"]) for p in pairs}) != len(pairs):
        problems.append("limited pairs must be unique")
    if problems:
        sys.exit("packs.json: " + "; ".join(problems))
    return config["repository"], config["max_packs"], bundle, packs, pairs


# ---------------------------------------------------------------------------
# The cut
# ---------------------------------------------------------------------------

def schema_of(full: Path) -> tuple[list[str], list[str], set[str]]:
    """The full file's DDL (tables, then indexes, each in creation order,
    without FTS shadow tables), its data tables and every table name."""
    conn = sqlite3.connect(ro_uri(full), uri=True)
    try:
        rows = conn.execute("""
            SELECT type, name, sql FROM sqlite_master
            WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' ORDER BY rowid""").fetchall()
    finally:
        conn.close()
    virtual = [name for _, name, sql in rows if sql.startswith("CREATE VIRTUAL TABLE")]
    rows = [r for r in rows if not any(r[1].startswith(v + "_") for v in virtual)]
    ddl = [sql for kind, _, sql in rows if kind == "table"] + [sql for kind, _, sql in rows if kind == "index"]
    names = {name for kind, name, _ in rows if kind == "table"}
    data = sorted(n for n in names if n not in virtual and n not in NOT_DATA)
    return ddl, data, names


def table_counts(conn: sqlite3.Connection, tables: list[str], schema: str = "main") -> dict[str, int]:
    return {t: conn.execute(f"SELECT COUNT(*) FROM {schema}.{t}").fetchone()[0] for t in tables}


def cut(full: Path, output: Output, path: Path, ddl: list[str], data_tables: list[str],
        full_tables: set[str]) -> Cut:
    """Writes one output file at `path`: the full schema, then its rows."""
    for leftover in (path, path.with_name(path.name + "-journal")):
        leftover.unlink(missing_ok=True)
    conn = sqlite3.connect(path, isolation_level=None, uri=True)
    try:
        conn.execute("PRAGMA page_size = 4096")
        conn.execute("PRAGMA journal_mode = DELETE")
        conn.execute("BEGIN")
        for sql in ddl:
            conn.execute(sql)
        conn.execute(f"PRAGMA user_version = {FORMAT_VERSION}")
        conn.execute("COMMIT")

        conn.execute("ATTACH DATABASE ? AS f", (ro_uri(full),))
        conn.execute("BEGIN")
        if output.sources:
            marks = ", ".join("?" for _ in output.sources)
            conn.execute(f"""
                INSERT INTO main.entries(id, word, word_normalized, definition, phonetic, pos, source)
                SELECT (? << 32) + id, word, word_normalized, definition, phonetic, pos, source
                FROM f.entries WHERE source IN ({marks}) ORDER BY id""", (output.ord, *output.sources))
            conn.execute(f"INSERT INTO main.dict_metadata SELECT * FROM f.dict_metadata "
                         f"WHERE source IN ({marks}) ORDER BY rowid", output.sources)
        for table in output.tables:
            if table not in full_tables:
                raise SystemExit(f"{output.name}: table {table} is not in the full file")
            conn.execute(f"INSERT INTO main.{table} SELECT * FROM f.{table}")
        for table, where in output.rows.items():
            if table in full_tables:  # E3's tables join the map before they exist
                conn.execute(f"INSERT INTO main.{table} SELECT * FROM f.{table} WHERE {where}",
                             {"lang": output.lang})
        credits = list(output.data_source)
        if "wordlist" in full_tables:
            credits += [r[0] for r in conn.execute("SELECT DISTINCT data_source FROM main.wordlist ORDER BY 1")]
        if credits:
            marks = ", ".join("?" for _ in credits)
            conn.execute(f"INSERT OR IGNORE INTO main.data_source SELECT * FROM f.data_source "
                         f"WHERE id IN ({marks}) ORDER BY rowid", credits)
        conn.execute("INSERT INTO main.entries_fts(entries_fts) VALUES('rebuild')")
        conn.execute("COMMIT")
        counts = table_counts(conn, data_tables + ["data_source"])
        conn.execute("DETACH DATABASE f")
        # rank = 1 also compares the index with `entries`.
        conn.execute("INSERT INTO entries_fts(entries_fts, rank) VALUES('integrity-check', 1)")
        conn.execute("VACUUM")
    finally:
        conn.close()
    return Cut(output, path, counts)


def check_file(c: Cut, failures: list[str]) -> None:
    """The per-file checks."""
    conn = sqlite3.connect(ro_uri(c.path), uri=True)
    try:
        name = c.output.name
        if [r[0] for r in conn.execute("PRAGMA integrity_check")] != ["ok"]:
            failures.append(f"{name}: integrity_check")
        if conn.execute("PRAGMA user_version").fetchone()[0] != FORMAT_VERSION:
            failures.append(f"{name}: user_version is not {FORMAT_VERSION}")
        if conn.execute("PRAGMA journal_mode").fetchone()[0].lower() != "delete":
            failures.append(f"{name}: journal mode is not DELETE")
        counts = dict(conn.execute("SELECT source, COUNT(*) FROM entries GROUP BY source"))
        metadata = dict(conn.execute("SELECT source, word_count FROM dict_metadata"))
        if set(counts) != set(metadata) or set(metadata) != set(c.output.sources):
            failures.append(f"{name}: entries sources {sorted(counts)}, dict_metadata {sorted(metadata)}, "
                            f"packs.json {sorted(c.output.sources)}")
        for source, word_count in metadata.items():
            if word_count != counts.get(source, 0):
                failures.append(f"{name}: {source} word_count {word_count}, {counts.get(source, 0)} rows")
        low, high = conn.execute("SELECT MIN(id), MAX(id) FROM entries").fetchone()
        if low is not None and not (c.output.ord << 32 <= low and high < (c.output.ord + 1) << 32
                                    and high < ID_LIMIT):
            failures.append(f"{name}: ids {low}..{high} outside {c.output.ord} << 32 or above 2^40")
        if c.output.name != "bundle":
            for table in ("catalog_pack", "catalog_source", "catalog_list", "catalog_pair"):
                if conn.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]:
                    failures.append(f"{name}: {table} has rows; only the bundle has the catalog")
    finally:
        conn.close()


def check_complete(full: Path, cuts: list[Cut], data_tables: list[str], failures: list[str]) -> None:
    """Every row of every data table in exactly one file, every source in one
    file, every credits row in at least one."""
    conn = sqlite3.connect(ro_uri(full), uri=True)
    try:
        full_counts = table_counts(conn, data_tables)
        sources = [r[0] for r in conn.execute("SELECT source FROM dict_metadata ORDER BY rowid")]
        credits = [r[0] for r in conn.execute("SELECT id FROM data_source ORDER BY rowid")]
    finally:
        conn.close()
    for table, n in full_counts.items():
        cut_total = sum(c.counts.get(table, 0) for c in cuts)
        if cut_total != n:
            failures.append(f"table {table}: {n:,} rows in the full file, {cut_total:,} in the cut files")
    for source in sources:
        owners = [c.output.name for c in cuts if source in c.output.sources]
        if len(owners) != 1:
            failures.append(f"source {source} is in {owners or 'no file'}, must be in exactly one")
    listed = {s for c in cuts for s in c.output.sources}
    for source in sorted(listed - set(sources)):
        failures.append(f"packs.json lists {source}, which the full file lacks")
    for credit in credits:
        if not any(_has_credit(c.path, credit) for c in cuts):
            failures.append(f"data_source {credit} lands in no file (add it to packs.json)")


def check_pairs(pairs: list[dict], cuts: list[Cut], failures: list[str]) -> None:
    """A limited pair needs a dictionary from its language into its
    meanings language, in some file."""
    directions = set()
    for c in cuts:
        conn = sqlite3.connect(ro_uri(c.path), uri=True)
        try:
            directions |= set(conn.execute("SELECT from_lang, to_lang FROM dict_metadata"))
        finally:
            conn.close()
    for pair in pairs:
        if (pair["lang"], pair["meanings_lang"]) not in directions:
            failures.append(f"limited pair {pair['lang']}/{pair['via']}: no dictionary from {pair['lang']} "
                            f"into {pair['meanings_lang']} gives its meanings")


def _has_credit(path: Path, credit: str) -> bool:
    conn = sqlite3.connect(ro_uri(path), uri=True)
    try:
        return conn.execute("SELECT 1 FROM data_source WHERE id = ?", (credit,)).fetchone() is not None
    finally:
        conn.close()


# ---------------------------------------------------------------------------
# Assets and catalog
# ---------------------------------------------------------------------------

def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def committed_catalog(bundle: Path) -> dict[str, dict]:
    """The catalog_pack rows of the committed bundle, by id; empty when the
    file has none yet (format 3) or is missing."""
    if not bundle.is_file():
        return {}
    with open(bundle, "rb") as f:
        if f.read(16) != b"SQLite format 3\0":
            sys.exit(f"{bundle} is not an SQLite file (a Git LFS pointer? git lfs pull)")
    conn = sqlite3.connect(ro_uri(bundle), uri=True)
    conn.row_factory = sqlite3.Row
    try:
        if not conn.execute("SELECT 1 FROM sqlite_master WHERE name = 'catalog_pack'").fetchone():
            return {}
        return {r["id"]: dict(r) for r in conn.execute("SELECT * FROM catalog_pack ORDER BY ord")}
    finally:
        conn.close()


def decompress(asset: Path) -> bytes:
    return lzma.decompress(asset.read_bytes(), format=lzma.FORMAT_XZ)


def catalog_row(c: Cut, repository: str, tag: str | None, previous: dict | None, verify: bool,
                failures: list[str]) -> dict | None:
    """The pack's catalog_pack row. Writes its asset when the version is
    new (not in verify), and checks that the asset decompresses to the
    file."""
    p = c.output
    version = c.sha256[:12]
    name = f"{p.name}-{version}.sqlite.xz"
    asset = ASSETS_DIR / name
    if previous and previous["version"] == version:
        url = previous["url"]
    elif verify:
        failures.append(f"pack {p.name}: the rebuilt file is version {version}, the catalog has "
                        f"{previous['version'] if previous else 'none'}")
        return None
    elif not tag:
        failures.append(f"pack {p.name}: new version {version}; pass --release-tag packs-YYYYMMDD")
        return None
    else:
        url = ASSET_URL.format(repository=repository, tag=tag, name=name)
    if not asset.exists():
        if verify or (previous and previous["version"] == version):
            failures.append(f"pack {p.name}: asset {asset.relative_to(REPO)} is missing (git lfs pull)")
            return None
        ASSETS_DIR.mkdir(exist_ok=True)
        data = lzma.compress(c.path.read_bytes(), format=lzma.FORMAT_XZ, check=lzma.CHECK_NONE,
                             preset=XZ_PRESET)
        asset.write_bytes(data)
    packed = asset.read_bytes()
    if packed.startswith(b"version https://git-lfs"):
        failures.append(f"pack {p.name}: {asset.relative_to(REPO)} is a Git LFS pointer (git lfs pull)")
        return None
    sha, size = sha256_bytes(packed), len(packed)
    if previous and previous["version"] == version and (previous["sha256"], previous["size"]) != (sha, size):
        failures.append(f"pack {p.name}: {name} is not the pinned asset (sha256 {sha[:12]}…)")
        return None
    if sha256_bytes(decompress(asset)) != c.sha256:
        failures.append(f"pack {p.name}: {name} does not decompress to its file")
        return None
    return {"id": p.name, "ord": p.ord, "lang": p.lang, "kind": p.kind, "version": version, "url": url,
            "sha256": sha, "size": size, "file_sha256": c.sha256, "file_size": c.size, "asset": asset}


def write_catalog(bundle: Path, rows: list[dict], cuts: list[Cut], pairs: list[dict]) -> None:
    """Fills the bundle's catalog tables from the packs and the limited
    pairs, then VACUUMs it."""
    conn = sqlite3.connect(bundle, isolation_level=None, uri=True)
    try:
        conn.execute("BEGIN")
        for r in rows:
            conn.execute("INSERT INTO catalog_pack(id, ord, lang, kind, version, url, sha256, size, "
                         "file_sha256, file_size) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                         (r["id"], r["ord"], r["lang"], r["kind"], r["version"], r["url"], r["sha256"],
                          r["size"], r["file_sha256"], r["file_size"]))
        for pair in pairs:
            conn.execute("INSERT INTO catalog_pair(lang, via, meanings_lang) VALUES (?, ?, ?)",
                         (pair["lang"], pair["via"], pair["meanings_lang"]))
        conn.execute("COMMIT")
        for c in cuts:
            conn.execute("ATTACH DATABASE ? AS p", (ro_uri(c.path),))
            conn.execute("BEGIN")
            conn.execute("""
                INSERT INTO catalog_source(pack_id, source, display_name, version, license, url, word_count,
                                           description, from_lang, to_lang)
                SELECT ?, source, display_name, version, license, url, word_count, description, from_lang, to_lang
                FROM p.dict_metadata ORDER BY rowid""", (c.output.name,))
            if conn.execute("SELECT 1 FROM p.sqlite_master WHERE name = 'wordlist'").fetchone():
                conn.execute("""
                    INSERT INTO catalog_list(pack_id, id, lang, level, word_count)
                    SELECT ?, id, lang, level, word_count FROM p.wordlist ORDER BY id""", (c.output.name,))
            conn.execute("COMMIT")
            conn.execute("DETACH DATABASE p")
        conn.execute("VACUUM")
    finally:
        conn.close()


# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------

def sizes(path: Path) -> list[tuple[str, int]]:
    conn = sqlite3.connect(ro_uri(path), uri=True)
    try:
        return full_build.table_sizes(conn)
    except sqlite3.OperationalError:
        return []
    finally:
        conn.close()


def report(cuts: list[Cut], stub: Cut, assets: dict[str, dict]) -> None:
    print("\nFiles (MB = 10^6 bytes)")
    for c in cuts + [stub]:
        top = ", ".join(f"{n} {s / 1e6:.1f}" for n, s in sizes(c.path)[:5] if s >= 50_000)
        line = f"  {c.output.name:<10} {c.size / 1e6:7.1f} MB  sha256 {c.sha256[:12]}"
        if c.output.name in assets:
            line += f"  asset {assets[c.output.name]['size'] / 1e6:5.1f} MB"
        print(line + (f"  ({top})" if top else ""))
    packs = [c for c in cuts if c.output.is_pack]
    print(f"  packs: {sum(a['size'] for a in assets.values()) / 1e6:.1f} MB to download, "
          f"{sum(c.size for c in packs) / 1e6:.1f} MB installed")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def run(full: Path, work: Path, tag: str | None, verify: bool) -> int:
    repository, max_packs, bundle_out, pack_outs, pairs = load_map()
    ddl, data_tables, full_tables = schema_of(full)
    with sqlite3.connect(ro_uri(full), uri=True) as conn:
        if conn.execute("PRAGMA user_version").fetchone()[0] != FORMAT_VERSION:
            sys.exit(f"{full} is not format {FORMAT_VERSION}: rebuild it")
    work.mkdir(parents=True, exist_ok=True)

    print(f"\nCutting {full} (SQLite {sqlite3.sqlite_version})")
    cuts = []
    for output in [bundle_out] + pack_outs:
        c = cut(full, output, work / f"{output.name}.sqlite", ddl, data_tables, full_tables)
        cuts.append(c)
        print(f"  {output.name}: {c.counts.get('entries', 0):,} entries")
    stub = cut(full, Output("stub", 0), work / "empty-pack.sqlite", ddl, data_tables, full_tables)

    failures: list[str] = []
    for c in cuts + [stub]:
        check_file(c, failures)
    check_complete(full, cuts, data_tables, failures)
    check_pairs(pairs, cuts, failures)
    if len(pack_outs) > max_packs:
        failures.append(f"{len(pack_outs)} packs, at most {max_packs}")
    for c in cuts[1:] + [stub]:
        c.sha256, c.size = inputs.sha256(c.path), c.path.stat().st_size
    if failures:
        sys.exit("Cut checks failed:\n  - " + "\n  - ".join(failures))

    previous = committed_catalog(BUNDLE_PATH)
    rows = []
    for c in cuts[1:]:
        row = catalog_row(c, repository, tag, previous.get(c.output.name), verify, failures)
        if row:
            rows.append(row)
    if failures:
        sys.exit("Asset checks failed:\n  - " + "\n  - ".join(failures))
    write_catalog(cuts[0].path, rows, cuts[1:], pairs)
    bundle = cuts[0]
    bundle.sha256, bundle.size = inputs.sha256(bundle.path), bundle.path.stat().st_size
    if bundle.size >= BUNDLE_LIMIT:
        sys.exit(f"The bundle is {bundle.size:,} bytes, the limit is {BUNDLE_LIMIT:,}")
    assets = {r["id"]: r for r in rows}
    report(cuts, stub, assets)
    print("Checks passed: every row in one file, word counts, integrity and FTS, id ranges, "
          f"{len(pack_outs)} of at most {max_packs} packs, meanings for {len(pairs)} limited pairs, "
          "each asset decompresses to its file, "
          "the bundle under 60 MB.")

    if verify:
        mismatches = []
        for c, committed in ((bundle, BUNDLE_PATH), (stub, STUB_PATH)):
            expected = inputs.sha256(committed) if committed.is_file() else "missing"
            print(f"  {c.output.name:<10} committed {expected[:16]}…  rebuilt {c.sha256[:16]}…")
            if expected != c.sha256:
                mismatches.append(committed.name)
        for row in rows:
            print(f"  {row['id']:<10} catalog   {previous[row['id']]['file_sha256'][:16]}…  "
                  f"rebuilt {row['file_sha256'][:16]}…")
        if mismatches:
            print(f"MISMATCH: {', '.join(mismatches)}. The committed bundle was written by SQLite "
                  f"{full_build.sqlite_version_of(BUNDLE_PATH)}, this cut used {sqlite3.sqlite_version}.")
            return 1
        print("OK: the bundle, the stub and every pack are byte-identical to the committed ones.")
        return 0

    shutil.copyfile(bundle.path, BUNDLE_PATH)
    shutil.copyfile(stub.path, STUB_PATH)
    keep = {r["asset"].name for r in rows}
    for old in sorted(ASSETS_DIR.glob("*.sqlite.xz")):
        if old.name not in keep:
            old.unlink()
            print(f"  removed {old.relative_to(REPO)} (no longer in the catalog)")
    for c in cuts[1:]:
        shutil.copyfile(c.path, work / f"{c.output.name}-{c.sha256[:12]}.sqlite")
    print(f"\nWrote {BUNDLE_PATH.relative_to(REPO)} (sha256 {bundle.sha256}), "
          f"{STUB_PATH.relative_to(REPO)} (sha256 {stub.sha256})")
    for r in rows:
        print(f"  {r['asset'].relative_to(REPO)}  {r['size']:,} B  sha256 {r['sha256']}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Cut the full dictionary file into the bundle and the packs.")
    parser.add_argument("--cache-dir", type=Path, default=inputs.DEFAULT_CACHE_DIR,
                        help="Where the pinned inputs and the full file live (default: Scripts/.cache).")
    parser.add_argument("--full", type=Path,
                        help="Cut this full file instead of building one (build_dictionaries.py output).")
    parser.add_argument("--release-tag", help="packs-YYYYMMDD: the GitHub release of new pack versions.")
    parser.add_argument("--verify", action="store_true",
                        help="Rebuild into a temp folder and compare with the committed files.")
    args = parser.parse_args()
    if args.release_tag and not RELEASE_TAG.fullmatch(args.release_tag):
        sys.exit("--release-tag must look like packs-YYYYMMDD")
    cache_dir = args.cache_dir.resolve()
    with tempfile.TemporaryDirectory() as folder:
        if args.full:
            full = args.full.resolve()
        elif args.verify:
            full = Path(folder) / full_build.FULL_FILE_NAME
            full_build.build(full, cache_dir)
        else:
            full = cache_dir / full_build.FULL_FILE_NAME
            full_build.build(full, cache_dir)
        work = Path(folder) / "cut" if args.verify else cache_dir / "packs"
        if not args.verify and work.exists():
            shutil.rmtree(work)
        return run(full, work, args.release_tag, args.verify)


if __name__ == "__main__":
    sys.exit(main())
