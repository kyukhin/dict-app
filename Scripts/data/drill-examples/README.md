# Drill examples

The example sentences of LibreDict's Greek conjugation drill, besides the ones from Tatoeba. `Scripts/build_examples.py` reads these files into the Greek pack; `Scripts/drill_examples.py` is the tool around them ([0134-example-sentences.md](../../../docs/specs/0134-example-sentences.md), "Drill examples" and "Corpus sentences").

What each file is under:

- `ell.tsv`: Wiktionary usage examples and sentences generated for LibreDict, with LibreDict's translations: CC BY-SA 4.0. The Wiktionary rows keep their entry (`page`); Wiktionary's text is CC BY-SA 4.0 too.
- `ell-corpus.tsv`: sentences written by people, from openly licensed corpora (BabyLM-ell first). Each row is under its own document's licence, the `licence` of its `doc` in `ell-corpus-documents.tsv`, together with LibreDict's edits (`text` against `original`: punctuation, capitals, a look-alike letter or a speaker tag, never a word) and translations (`eng`, `rus`). For a public-domain document, LibreDict's edits and translations are CC BY-SA 4.0.
- The rows under a NonCommercial licence (CC BY-NC, CC BY-NC-SA) may not be used commercially.
- `ell-corpus-documents.tsv`: each document's collection, work, licence, the licence statement as the document or its record gives it, its address and who read it when.
- `ell-readings.tsv`, `ell-skipped.tsv`: verdicts and skipped cells, CC BY-SA 4.0.

The repository's MIT licence covers the software only, not these files.
