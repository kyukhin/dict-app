# Greek grammar notes

The sources of the Grammar reference (spec: `docs/specs/0133-grammar.md`, epic #133). One Markdown file per topic and explanation language, named by the topic id: `eng/ell-aorist-regular.md`. 2.0.0 has the 17 Greek A1 topics, explained in English (`eng/`, Greek via English) and in Russian (`rus/`, Greek via Russian). `Scripts/build_grammar.py` (#171) reads them, renders their forms tables from the Wiktionary word forms, checks them and writes them into the Greek pack (`ell`).

## Authoring brief

- The texts were drafted with AI (Claude, an LLM) and reviewed by Kirill Yukhin. The hash of every reviewed topic is in `reviewed.tsv`; the build fails on a topic changed since its review.
- Own text only. The LLM wrote every topic from its own knowledge of Greek, in plain English or Russian for an adult A1 learner. Nothing is copied or paraphrased from a textbook, a website or the ΚΕΓ syllabus, and no third-party text was put in the drafting prompt. The ΚΕΓ syllabus only decides each topic's level.
- Examples are the author's own everyday sentences in A1 vocabulary, each with its translation, with no real people or brands. Transliteration appears only in the alphabet topic.
- Verb and noun forms are never typed by hand. A `forms` block names model words and a tense; the build fills the table from the paradigm data, the same data as the Definition screen's tables, keeping each cell's first form and its -ουνε or -ανε variants, and one set of endings for -άω verbs (αγαπάω … αγαπάνε). Articles, pronouns, numbers and letters are written tables.
- Each file has the shape the spec fixes: front matter (`id`, `lang`, `level`, `order`, `tenses`, `classes`, `words`, `topics`), then the title, the rule (at most 120 words), one to three tables, `## Examples` (3 to 5) and `## Watch out` (1 or 2).

`forms-checklist.md` lists what to check on the rendered forms tables.

## Russian texts

The `rus/` files have the same front matter, tables, forms blocks and Greek examples as the `eng/` ones; only the explanations, the captions and the translations are Russian. They are written for Russian speakers, not translated from English (Kirill, 2026-11-04): they compare Greek aspect with the Russian one (θα γράψω, «напишу»; γράψε, «напиши») and their Watch out items target Russian speakers' mistakes:

- leaving out είμαι in the present (Я врач: Είμαι γιατρός), and the nominative after it where Russian can use the instrumental;
- «у меня есть» is έχω, «здесь есть» is υπάρχει, and age goes with είμαι;
- gender that differs from Russian: το πρόβλημα and το νερό are neuter, η θάλασσα is feminine;
- the article before names and possessives;
- one present tense: γράψω alone is not «напишу».

## License

The topic texts are LibreDict's, under the [Creative Commons Attribution-ShareAlike 4.0 International license](https://creativecommons.org/licenses/by-sa/4.0/) (CC BY-SA 4.0), like Kirill's Greek word lists. The forms tables rendered into them come from Wiktionary, also CC BY-SA 4.0. Credit: "Greek grammar notes: LibreDict (CC BY-SA 4.0)".
