#!/usr/bin/env python3
"""
arabic_normalize.py
Single source of truth for Arabic search-key normalization (Issue #10).

`normalize_arabic(s)` strips the Arabic *harakat* (combining vocalization
marks) from a string, leaving every other character byte-for-byte intact.
The result is stored in `entries.word_normalized` and is what FTS5 indexes,
so a user typing the bare (unvocalized) form matches a vocalized headword.

Why exactly this set (see also Issue #10's design discussion): every code
point below is Unicode category **Mn (nonspacing mark)**, i.e. a harakat.
The build pre-normalizes `word_normalized` to the bare (un-vocalized) form
so FTS5 indexes the bare form. A user typing the bare form therefore
matches a vocalized headword.

Note: Swift's `CharacterSet.alphanumerics` *includes* category M* marks,
so `DatabaseService.sanitizeFTS` does **not** strip harakat from the
query; the FTS5 `remove_diacritics 2` tokenizer also leaves harakat
intact. Diacritic-insensitivity therefore depends on the user typing the
bare form — a fully-vocalized query will not match. The MVP AC ("search
without diacritics") is met because users type bare; vocalized-query
matching is a documented follow-up.

The transformation is purely subtractive: it never substitutes or merges
letters, so it cannot collide two distinct lemmas. Full letter folding
(alef/yaa/taa-marbuta) and tatweel (U+0640, category Lm — which neither
sanitizeFTS nor the FTS tokenizer strips) are deliberately out of scope
for the v1.3.0 MVP.
"""

from __future__ import annotations

# Exact code-point set removed from `word` to produce `word_normalized`.
# U+064B–U+065F: tanwin, short vowels, shadda, sukun, maddah, hamza marks,
#                and the Quranic annotation marks through U+065F.
# U+0670:        superscript (dagger) alef.
# All are Unicode category Mn (nonspacing mark).
_HARAKAT = {cp for cp in range(0x064B, 0x0660)} | {0x0670}

# Pre-built translation table: map every harakat code point to None (delete).
_STRIP_TABLE = {cp: None for cp in _HARAKAT}


def normalize_arabic(s: str) -> str:
    """Return `s` with all Arabic harakat removed; a no-op on text that
    contains none of them (e.g. Latin/Cyrillic/Spanish headwords)."""
    if not s:
        return s
    return s.translate(_STRIP_TABLE)


if __name__ == "__main__":
    # Tiny self-check / demo. `كِتَاب` (vocalized) → `كتاب` (bare).
    samples = ["كِتَاب", "قادِر", "مُخْتَصَر", "book", "ёлка"]
    for sample in samples:
        print(f"{sample!r} -> {normalize_arabic(sample)!r}")
