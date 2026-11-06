# The valid fixture topic

`build_grammar.py --self-check` builds `eng/ell-valid.md` and `rus/ell-valid.md` (docs/specs/0133-grammar.md, "Modes"), alone and with each case of `../invalid/`.

This file is a top-level file, as `Scripts/data/grammar/README.md` is: never a topic. Every self-check build copies it next to the topics, and `GrammarFileTests` reads this folder, so a reader that parsed it would fail.
