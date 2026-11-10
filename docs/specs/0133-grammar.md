# Grammar reference

> Spec written by Claude (AI) for LibreDict.
> Status: Implemented, with a revision for epic #292 (#295: the Grammar section on Greek's tab, with Conjugation; #297: the Grammar list), approved by kyukhin on 2026-11-10 and not built yet; the rest approved by kyukhin on 2026-11-04 · Epic: #133 · Tickets: #171, #172, #173, #174; #295, #297 · Updated: 2026-11-10

Read [0000-overview.md](0000-overview.md), [0129-dictionary-file.md](0129-dictionary-file.md) and [0136-word-forms.md](0136-word-forms.md) (the Greek paradigms, `ParadigmLayout`, `InflectionTable`) first. Then the specs this epic builds on, approved by kyukhin on 2026-11-04. 0237 and 0130 are on master; 0131 comes with PR #235 and 0132 with PR #247, which merge before this spec: [0237-downloads.md](0237-downloads.md) (#237: every language's data comes in its pack), [0130-word-lists.md](0130-word-lists.md) (E3: learned languages, the Greek lists, `entry(for:sourceOrder:)`), [0131-learning.md](0131-learning.md) (E4: the Learn home, "Learn %@?", the run views) and [0132-conjugation-drill.md](0132-conjugation-drill.md) (E5: `ConjugationTense`, the drill, Practise on Definition). No number in this spec is measured: the content does not exist yet. Sizes are estimates, checked by the build.

## Why

Learners of Greek meet the grammar on every screen: an aorist in the drill (E5), a table on the Definition screen (#144), an article in a list word (E3). The app shows forms but never says why έγραψα has an ε, or why σπίτι takes το. A short note per topic, at the moment the learner meets it, closes that gap: in English, and in Russian for Greek via Russian (0131). 2.0.0 ships the 17 A1 topics of the ΚΕΓ syllabus; A2–B1 (#175) and English grammar (#176) follow in 2.1.0 on the same format.

## Behaviour

### Where grammar appears

| Place | What the user sees | Ticket |
|---|---|---|
| Learn tab | On a pair tab, a **Grammar** section after Trainers (0131, #295): a row "Topics · 17" when the tab's language has topics (Greek, with the Greek pack installed), which opens the Grammar screen, and for Greek E5's "Conjugation · A1" row (0132), moved here from Trainers. The section is hidden when the language has neither | #172, #295 |
| Definition | A **Grammar** section under the inflection table and E5's Practise button, one row per linked topic, for a headword of a Greek → English dictionary (El–En · FD, El–En · WN) | #174 |
| Conjugation drill | A **Rule** button in the feedback bar after each answer, when the question's tense has a topic. It opens that topic over the run | #174 |

### Grammar screen (#172)

- Title "Grammar".
- **The explanation language is the via language** of the language taught (0131, "Languages and pairs"; kyukhin, 2026-11-04): a topic shows its text in Greek's via, or in Greek's default via when Greek is not learned (a topic opened from Definition). 2.0 has two Greek pairs, Greek via English and the limited Greek via Russian (kyukhin, 2026-11-04), and every topic has an English and a Russian text. So Greek via English reads English, Greek via Russian reads Russian, and a Russian UI that has not chosen Greek yet reads Russian (its default pair), whatever else the screen is in.
- **A via language without texts** (a later pair whose via has no texts yet) shows the English texts, with a line on top: "Topics are explained in English." The rest of the screen (headings, buttons, Practise) is in the UI language, as always. A topic with a text in the via shows it without the line. The topic screen shows the same line above its title whenever its own text is the English fallback, however it opens, so a topic opened straight from Definition or the drill's Rule sheet, without the Grammar screen, says it too. In 2.0 the line never shows.
- **Levels** (#297, kyukhin 2026-11-10). While only one level has topics, as in 2.0 (A1):
  - no level header; a subtitle under the title gives the count and the level, "17 topics · A1" ("Α1" in a Greek UI, E3's level names);
  - the topics in their order (Content, below);
  - then, in a section of its own, one row "A2 · Coming soon" for the next level, in the secondary colour. It is text, not a button: a tap does nothing and VoiceOver reads "A2, Coming soon" without a button trait. After C2 there is no such row.
  With two or more levels (A2 in a later release) each level gets its header again, lowest first, the subtitle reads "40 topics", and the "Coming soon" row goes.
- Each row is the topic's title in the explanation language. A tap opens the topic.

### Topic screen (#172)

Top to bottom:

1. **Title** and level: "The aorist of regular verbs and the augment", "A1".
2. **Rule**: the explanation, at most 120 words, with Greek words in the text.
3. **Table**: one to three tables. Verb and noun tables are built from the word-form data, the same data as the Definition tables (#144): a grid of persons (or cases) by one to three model words, for one tense (Design, "Forms tables"). Tables of articles, pronouns, numbers and letters are written in the topic.
4. **Examples** (heading in the UI language): 3 to 5 Greek sentences, each with its translation in the explanation language (English or Russian in 2.0) under it.
5. **Watch out** (heading in the UI language): 1 or 2 typical mistakes. The Russian texts name the mistakes typical of Russian speakers (Content).
6. **Practise · Aorist**: for a topic about verb tenses, a button that starts the conjugation drill for those tenses (Practise, below).
7. **Words** (heading in the UI language): the topic's words, each with its short meaning in the pair's meanings language (0131: English for both Greek pairs). A tap opens the word's Definition: its entry in the first Greek dictionary of Dictionary Order, enabled ones first, as E3 opens list words.
8. **Related topics** (heading in the UI language): a tap opens the topic.

- The toolbar has the Reading Mode toggle, as Search and Definition do (#5): the screen stays awake while it is on.
- On iPad and in landscape the content column is at most 700 pt wide and centred. Text wraps at every Dynamic Type size; tables use the Definition tables' fallbacks (bands, then one block per column, #144), so the screen never scrolls sideways.
- **Arabic**: the screen mirrors (headings, buttons and link rows), but the topic's English or Russian content (title, rule, tables, examples, Watch out) is laid out left to right, as a text with Greek words.
- **VoiceOver**: headings are headers; Greek words and sentences are spoken with the Greek voice, inside the English text too; each table cell reads "column, row, form" as on the Definition screen; an example reads the Greek sentence, then its translation.

### Practise (#172)

- "Practise" on a topic runs E5's drill **for the topic's tenses** (kyukhin's #172 wording: "opens the conjugation drill for that tense"):
  - 15 questions, E5's session rules (due cards first, then new verb–tense pairs, weaker tenses more often, a wrong answer once more at the end), limited to the topic's tenses in each verb's main voice;
  - the verbs of the checked Greek lists, as the drill takes them; with no Greek list checked, Greek A1's verbs (Open question 1);
  - the tenses up to E5's "Tenses up to" level, raised to the first level that has one of the topic's tenses (every A1 topic's tense is A1, so 2.0 never raises it).
- Cards, the answer log, the daily goal and the summary are E5's. Nothing new is stored.
- When Greek is not a learned language (a topic opened from Definition), Practise first asks E4's "Learn Greek via English?" (Greek's default pair; "Learn Greek via Russian?" with its warning in a Russian UI). Yes adds the pair and starts the drill; No cancels it, as E5's Practise on Definition does (kyukhin, 2026-11-04, 0132).
- A topic opened from the drill's Rule button has no Practise.

### Links from the Definition screen (#174)

The Grammar section lists the topics that apply to the entry, in topic order:

| Entry | Topics |
|---|---|
| γράφω | Present tense: first conjugation · The aorist of regular verbs · The future with θα · να + the simple form · The imperative |
| αγαπάω, μπορώ | Present tense: second conjugation, then the same four |
| πηγαίνω | Present tense: first conjugation · Irregular aorists · the future, να and the imperative. πάω shows πηγαίνω's table (#144), so it gets the same, plus any topic that lists πάω |
| έχω | είμαι and έχω · the future · να (and the imperative only if its table has one; έχω has no aorist) |
| έρχομαι | Irregular aorists (it is listed there). Verbs with passive forms only get no class topic in 2.0: the deponent topic is A2 (#175) |
| σπίτι, Αθήνα | Articles and gender · Noun endings |
| καλός (adjective) | Adjective agreement |
| σε, εγώ, δεν | The topic that lists them (σε + article; personal pronouns; negation) |

The rules:
1. **By word.** A topic links every word it lists: the entry's headword, or the lemma of the table the entry shows (πάω → πηγαίνω).
2. **By class.** A topic can apply to a class of words, taken from the entry's table:
   - `verb`: a verb whose main voice is active;
   - `verb.conj1`: such a verb whose present εγώ ends in an unaccented -ω (γράφω, ακούω, λέω);
   - `verb.conj2`: one whose present εγώ ends in -άω or an accented -ώ (αγαπάω, μπορώ, οδηγώ);
   - `verb.passive`: a verb with passive forms only (έρχομαι). No 2.0 topic uses it;
   - `noun`: a noun or a proper noun; `adj`: an adjective.
   Without a table, an entry whose part of speech says noun or adjective (#144's label map) is `noun` or `adj`; a verb without a table has no class.
3. **Tenses.** A topic about tenses applies to a verb by class only when the verb's table has one of those tenses (E5's `ConjugationTense.forms`, with E5's θα / να fallback): έχω gets no aorist topic.
4. **A listed word wins its tenses.** When a topic lists the word, class topics about the same tenses are dropped: πηγαίνω gets Irregular aorists, not the regular one; έχω gets "είμαι and έχω", not the first conjugation; ζω (a monosyllable, so `verb.conj1` by the ending) is listed in the second conjugation's words and gets that one.
   Without a table, a word a topic lists gets no class from its part of speech: FreeDict calls εγώ, θα and σου nouns, so they get only the topic that lists them.
5. The rows are in level order, then topic order. A tap pushes the topic in the same tab.

### Rule in the drill (#174)

- After each answer, the feedback bar shows **Rule** next to Continue when the question has a topic: the topic of the question's tense that the rules above give for the drilled verb, in the voice asked. Aorist of γράφω → the regular aorist; of πηγαίνω → irregular aorists; present of αγαπάω → the second conjugation.
- No button for tenses without a 2.0 topic (the imperfect, the continuous future and subjunctive, the perfect tenses). A passive facet gets Rule only for a verb with passive forms only, and only from a topic that lists it, never from a class topic (kyukhin, 2026-11-08): the aorist of έρχομαι (ήρθα) → irregular aorists; θυμάμαι, which no topic lists, has none. The passive of a verb with both voices (γράφομαι) has none: its topics teach the active forms.
- Rule opens the topic in a sheet over the run, with Done. In the sheet, words and related topics open inside the sheet; there is no Practise, on the topic or on a Definition opened from it. Done returns to the same answer's feedback.
- It sits after the answer, so it never helps answer the question and does not count in the answer's time (`duration_ms`).

### Content (#173)

17 topics. Ids, order, tenses and classes are fixed here, since #174's links depend on them. Titles, model words and the words lists are #173's first draft and change in review; the build checks every word (Design).

| Ord | Id | Working title | Table | Tenses | Classes | Words (draft) | Related |
|---|---|---|---|---|---|---|---|
| 1 | `ell-alphabet` | The alphabet, the stress mark and the diaeresis | Written: letter, name, sound | | | | `ell-articles` |
| 2 | `ell-articles` | Articles and gender | Written: ο, η, το and ένας, μία, ένα by case and number | | `noun` | ο, η, το, ένας | `ell-noun-endings`, `ell-se-prepositions` |
| 3 | `ell-noun-endings` | Noun endings: nominative and accusative | Forms: δρόμος, γυναίκα, σπίτι | | `noun` | | `ell-articles`, `ell-adjectives` |
| 4 | `ell-adjectives` | Adjective agreement | Forms: καλός by gender | | `adj` | | `ell-noun-endings` |
| 5 | `ell-pronouns` | Personal pronouns, strong and weak | Written | | | εγώ, εσύ, αυτός, εμείς, εσείς, αυτοί | `ell-possessives` |
| 6 | `ell-possessives` | Possessives | Written | | | μου, σου, δικός | `ell-pronouns` |
| 7 | `ell-eimai-echo` | είμαι and έχω | Forms: είμαι, έχω · present | `present` | | είμαι, έχω | `ell-present-1`, `ell-future` |
| 8 | `ell-present-1` | Present tense: first conjugation | Forms: γράφω, δουλεύω · present | `present` | `verb.conj1` | γράφω, δουλεύω | `ell-present-2`, `ell-negation-questions` |
| 9 | `ell-present-2` | Present tense: second conjugation | Forms: αγαπάω, μπορώ · present | `present` | `verb.conj2` | αγαπάω, μιλάω, μπορώ, ζω | `ell-present-1` |
| 10 | `ell-negation-questions` | Negation and question words | Written | | | δεν, μην, όχι, τι, ποιος, πού, πότε, πώς, γιατί | `ell-present-1` |
| 11 | `ell-se-prepositions` | σε + article and basic prepositions | Written: σε + τον → στον … | | | σε, από, με, για | `ell-articles` |
| 12 | `ell-numbers-time` | Numbers, time and dates | Written | | | ένας, δύο, τρία, ώρα | `ell-articles` |
| 13 | `ell-aorist-regular` | The aorist of regular verbs and the augment | Forms: γράφω, διαβάζω, αγοράζω · aorist | `aorist` | `verb` | | `ell-aorist-irregular`, `ell-future` |
| 14 | `ell-aorist-irregular` | Irregular aorists | Forms: πηγαίνω, βλέπω, λέω · aorist | `aorist` | | πηγαίνω, βλέπω, λέω, τρώω, πίνω, έρχομαι, βγαίνω, μπαίνω, παίρνω, βρίσκω | `ell-aorist-regular` |
| 15 | `ell-future` | The future with θα | Forms: γράφω, αγαπάω · future | `future` | `verb` | θα | `ell-na-perfective`, `ell-aorist-regular` |
| 16 | `ell-na-perfective` | να + the simple form | Forms: γράφω, πηγαίνω · subjunctiveSimple | `subjunctiveSimple` | `verb` | να | `ell-future`, `ell-imperative` |
| 17 | `ell-imperative` | The imperative | Forms: γράφω, διαβάζω · imperativeSimple | `imperativeSimple`, `imperativeContinuous` | `verb` | | `ell-na-perfective` |

- **Authoring.** An LLM drafts every topic from its own knowledge of Greek, in the structure above, in plain English for an A1 learner. Nothing is copied or paraphrased from a textbook, a website or the ΚΕΓ syllabus: the syllabus only placed these topics at A1 (kyukhin, 2026-10-22), and no third-party text is put in the drafting prompt. Examples are the author's own everyday sentences in A1 vocabulary, with no real people or brands. Transliteration only in the alphabet topic.
- **Russian texts** (kyukhin, 2026-11-04, for Greek via Russian): every one of the 17 topics also has a Russian text, `Scripts/data/grammar/rus/<topic id>.md`, with the same front matter, the same forms tables and the same Greek examples, translated into Russian. It is written for Russian speakers, not translated word for word, under the same authoring rules. Its Watch out items name the mistakes Russian speakers make:

| Topic | Russian-specific Watch out |
|---|---|
| `ell-eimai-echo` | είμαι is never dropped, as "есть" is in Russian (Είμαι φοιτητής, not "Εγώ φοιτητής"); "у меня есть" is έχω, not a phrase with σε |
| `ell-articles` | The gender of the -μα nouns: το πρόβλημα, το θέμα, το όνομα are neuter (проблема and тема are feminine); names take the article (ο Γιάννης, η Μαρία) |
| `ell-possessives` | The noun keeps its article before μου, σου: το σπίτι μου, not "μου σπίτι" |

  The other topics' Russian Watch out items are free, as in English. The exact wording and examples are #173's draft and change in review.
- **Review** (kyukhin, 2026-10-22, #173): the drafted texts go to kyukhin as one document, `Scripts/reports/grammar-review.md`, which the build writes (all topics in order, each with its English and Russian text, forms tables rendered once, words and links listed). He checks every Greek example and table with a strong LLM and returns corrections; they are applied before merge. Two passes keep it off the critical path (Open question 4): text, examples and written tables first, as soon as they are drafted; then the rendered forms tables, which come from the same Wiktionary data as the Definition tables. When the last corrections are in, the hash of each reviewed text (topic and explanation language) goes into `Scripts/data/grammar/reviewed.tsv`, and the build fails on a topic whose text or rendered tables changed since (Design).
- **License** (Open question 3): the topic texts are LibreDict's, under CC BY-SA 4.0 like kyukhin's Greek lists, since their forms tables come from Wiktionary (CC BY-SA 4.0). Credits gains the line "Greek grammar notes: LibreDict (CC BY-SA 4.0)" in the five UI languages. `Scripts/data/grammar/README.md` records the authoring brief, that the texts were drafted with AI and reviewed by Kirill Yukhin, and the license.

### Decisions

- 2026-10-22 (kyukhin, #133): explanations are in English.
- 2026-10-22 (kyukhin, #133): 2.0.0 ships the 17 A1 topics; Greek A2–B1 (#175) and English grammar (#176) move to 2.1.0.
- 2026-10-22 (kyukhin, #133, #173): own text only. The ΚΕΓ syllabus decides the level of each topic; its text is not copied or paraphrased.
- 2026-10-22 (kyukhin, #133, #173): kyukhin reviews the drafted texts with a strong LLM, as one document; his corrections are applied before merge.
- kyukhin (#171): one Markdown file per topic per explanation language, with front matter (language, level, order, links), built into the read-only data; verb tables reference model verbs and come from the paradigm data, never typed by hand.
- 2026-11-03 (kyukhin, 0237): every language's data comes in its pack, English only in the bundle. Applied here: Greek grammar ships in the Greek pack (`ell`).
- 2026-11-04 (kyukhin): code complete 11-27, App Store submission 12-04. E3, E4, E10 and #237 hold the streams until about 11-20, so E6 must fit 11-20 to 11-27, and it is a candidate to cut if behind.
- 2026-11-04 (kyukhin): the 17 topics are written by an LLM and reviewed by kyukhin.
- 2026-11-04 (kyukhin, Open question 1): a topic's Practise with no Greek list checked asks the user: "No Greek list is checked. Practise the verbs of Greek A1, or choose lists?" with "Greek A1" and "Choose lists" (which opens New words from).
- 2026-11-04 (kyukhin, Open question 2): the empty grammar tables land in format 4 with #240 (T1), so adding grammar later never forces a pack re-download.
- 2026-11-04 (kyukhin, Open question 3): the grammar texts are CC BY-SA 4.0; the repository README says they were drafted with AI and reviewed by kyukhin. Credits gets "Greek grammar notes: LibreDict (CC BY-SA 4.0)". Settings shows a Credits button right under the version, opening the read-only Credits screen (it moves there from Support; #180 does it for every 2.0 data source).
- 2026-11-04 (kyukhin, Open question 4): the 17 A1 texts of #173 are drafted right after approval, outside the four streams; kyukhin does the first review pass (text, examples, written tables) before 11-20, the second pass (rendered forms tables) after #171.
- 2026-11-04 (kyukhin, Open question 5): nothing is cut from 2.0 if it runs late, E6 included: the release date moves instead.
- 2026-11-04 (kyukhin): learning is chosen as a language pair (0131), "Greek via English". Applied here: topics are explained in the via language of the language taught, not the UI language; a via without texts shows the English ones with the line "Topics are explained in English.". 2.0's only Greek pair is Greek via English, so 2.0 shows every topic in English, as decided on 2026-10-22, and the line never shows.
- 2026-11-04 (kyukhin): Greek via Russian is offered as a limited pair (0131), although there is no Greek–Russian dictionary: grammar, tips and notes in Russian, word meanings in English. Applied here: all 17 A1 topics get Russian explanation texts (`Scripts/data/grammar/rus/`), with Russian-specific Watch out items (dropping είμαι, έχω for "у меня есть", the gender of το πρόβλημα / το θέμα / το όνομα, the article before names and possessives). Greek via Russian shows them; Greek via English keeps English. This extends "explanations are in English" (2026-10-22) and the line above.
- 2026-11-10 (kyukhin, #297): the Grammar list has no header while only one level exists; the level is in the subtitle ("17 topics · A1"); an "A2 · Coming soon" row ends the list, and it is not a button.
- 2026-11-10 (kyukhin, #295): the Grammar section of Greek's tab holds the topics and the conjugation drill, moved out of Trainers.

Design choices of this spec, for review:
- Greek grammar in the Greek pack; the 2.1.0 English topics in the English lists pack. Grammar is learning content, and it needs the word forms of its pack.
- Forms tables are rendered at build time, in Python, and stored as Markdown tables. What kyukhin reviews is byte for byte what ships, and a Wiktionary refresh shows its table changes in the review document's diff. A Swift unit test checks every stored table against the app's own paradigm code.
- One Markdown body per topic, of a fixed shape the build enforces; the app parses only that shape. No general Markdown renderer, no web view.
- One link table for words, related topics, tenses and classes; Definition links match by word first, then by class.
- Practise is E5's session limited to the topic's tenses, not a new drill.
- Rule sits in the feedback bar after the answer, and opens the topic in a sheet without Practise.
- English content keeps left to right in Arabic.
- The Grammar section has one row for the topics, not 17; since #295 it also holds the Conjugation row.
- A hash gate (`reviewed.tsv`) makes "reviewed before merge" checkable, also after a data refresh.

### Out of scope

Greek A2–B1 topics (#175) and English topics (#176, 2.1.0). Explanations in languages other than English and Russian (the format allows them; none is written). Searching topics. Links inside the rule text (the Words and Related topics sections hold them). Read marks or progress on topics. Audio for examples. The declension drill (#170) and Practise for noun topics. Grammar for Spanish, Russian and Arabic. Mentioning grammar in 0237's Languages row and remove alert (their strings stay). Verb tables typed by hand.

## Design

### Depends on

| Spec | What E6 uses | Notes |
|---|---|---|
| 0136 (#141, #144) | `lemma`, `paradigm`, `tagset`; `ParadigmLayout.voiceForms`, `mainVoice`, `Person`, `table(for:locale:)` and its cell ids; `InflectionTable.Section` and `InflectionSectionView` (DefinitionView.swift); the `languageIdentifier = "el"` runs of #144's labels | Forms tables are #144's data; the reader draws its tables with #144's section view |
| 0237 (T1, T2) | The Greek pack attached as `ell`; `Scripts/packs.json` row routing; one schema in every file and the format rule; `DictionarySchemas.listsSchema(for:)`; `PackFixtures`, `-installPacks`, `-skipWelcome` | Without the pack, `ell` is the stub: no topics, no section, no links, with no special code |
| 0130 (#151, #152) | E3's level names `wordLists.level.*`; `entry(for:sourceOrder:)` (the word's entry in Dictionary Order, enabled first); `wordlist_item` of `ky-ell` (A1's verbs for Practise without a checked list) | #172 extracts E3's headword lookup as `entry(headword:lang:sourceOrder:)`, which `entry(for:sourceOrder:)` then calls |
| 0131 (#157, #158, #159) | The Learn home sections, `LearnViewModel`, `learning_languages`, `LearningPairs.via` (the explanation language), `meanings` (the Words rows), `LearningLanguageService.learn(language:)`, the "Learn %@ via %@?" alert, the feedback bar | Adds a Grammar section to 0131's Learn home table |
| 0132 (#167, #168, #169) | `ConjugationTense` (titles, raw values, `forms` with the θα / να fallback), `ConjugationFacet`, `DrillScope`, `drillVerbs(lists:)`, `ConjugationQuestionBuilder.questions`, `ConjugationPlanner.session`, `ConjugationRunViewModel`, `ConjugationRunView`, `DefinitionViewModel.practise()` and its paradigm and `drillVerb` | Two small extensions to E5 (Practise for tenses; the Rule button), below |
| 0129 | "Adding static data" (a step with `SCHEMA` and `build`, `data_source`, determinism, format bump, size budget) | 0129 already names E6's three tables |

Where this spec differs from the others:
- #171 says the build writes "the read-only dictionary file". Since #237 the full build still writes them, and the cut moves Greek rows into the `ell` pack.
- 0132 has no drill limited to tenses, and no Rule button. This spec adds both (Practise, Rule). E5's own behaviour does not change.
- 0131's Learn home table gains a Grammar section after Lists; since #295 it comes after Trainers and holds E5's Conjugation row (0131, 0132).
- The issue's column `target_lang` is called `lang` here, as in `wordlist` and `lemma`.

### Data placement

| Data | Where | Why |
|---|---|---|
| Greek topics, texts and links | The Greek pack (`ell`), tables `grammar_topic`, `grammar_text` (English and Russian texts), `grammar_link` | 0237: a language's data comes in its pack. The forms tables, word links and Practise need that pack anyway |
| English topics (2.1.0, #176) | The English lists pack (`eng-lists`) | English learning content; the bundle stays dictionary, morphy and catalog. 2.1.0 adds rows only, so no format bump |
| The bundle and the stub | The three tables, empty | 0237: one schema in every file |
| Topic sources | `Scripts/data/grammar/<explain_lang>/<topic id>.md` (Markdown, in Git) | Readable diffs. They are source, like the scripts: versioned by Git, not pinned in `inputs.json` |
| Reviewed hashes | `Scripts/data/grammar/reviewed.tsv` | The review gate |
| Nothing in `user.sqlite` | | Topics have no user state in 2.0 |

`Scripts/packs.json` routes the rows by language: `grammar_topic` where `lang = 'ell'`, and `grammar_text` and `grammar_link` where `topic_id` is a topic of that language (`topic_id IN (SELECT id FROM f.grammar_topic WHERE lang = :lang)`, T1's row filters take SQL), into `ell`; `eng` rows into `eng-lists`. The credit row goes the same way: the `ell` pack's `data_source` list names `libredict-grammar-ell` (and `eng-lists` names `libredict-grammar-eng` for 2.1.0), since the cut fails on a `data_source` row that lands in no file. A listed id with no row (a language without topics) copies nothing. The app reads a language's grammar from `DictionarySchemas.listsSchema(for: lang)`: `ell` for Greek, `eng_lists` for English, nil (no grammar, no query) for the others.

### Topic files (#171)

One file per topic per explanation language, named by the topic id: `Scripts/data/grammar/eng/ell-aorist-regular.md`. Explanation languages are ISO 639-3 like every data column; 2.0 has `eng` and `rus` (for Greek via Russian), each for all 17 topics.

````markdown
---
id: ell-aorist-regular
lang: ell
level: A1
order: 13
tenses: aorist
classes: verb
words: γράφω, διαβάζω, αγοράζω
topics: ell-aorist-irregular, ell-future
---
# The aorist of regular verbs and the augment

The aorist says what happened once, or was completed: *έγραψα*, I wrote. …

**Most verbs**

```forms
words: γράφω, διαβάζω, αγοράζω
tense: aorist
```

## Examples

- Χθες έγραψα ένα γράμμα στη γιαγιά μου.
  Yesterday I wrote a letter to my grandmother.
- …

## Watch out

- The augment έ- goes only where the stress needs it: έγραψα, but γράψαμε.
````

- **Front matter**: `key: value` lines, lists comma-separated. Keys: `id` (permanent, `<lang>-<slug>`, equal to the file name), `lang`, `level` (`A1` … `C2`), `order` (unique within the language and level), and the links: `words`, `topics`, `tenses` (E5's `ConjugationTense` raw values), `classes` (`verb`, `verb.conj1`, `verb.conj2`, `verb.passive`, `noun`, `adj`). Every explanation language's file of a topic has the same front matter. No YAML library: the build parses this subset.
- **Body**, in this order:
  1. `# Title`;
  2. the rule: paragraphs and `- ` lists with inline Markdown (bold, italic, strikethrough);
  3. one to three tables, each optionally after a caption line that is one bold span (`**Most verbs**`; a rule line such as `**ο** and **η**` is no caption). A table is a `forms` block or a Markdown pipe table. A pipe table whose top-left cell is empty has row headers in its first column;
  4. `## Examples`: 3 to 5 list items, each a Greek sentence with its translation on the indented second line;
  5. `## Watch out`: 1 or 2 list items.
  The two `##` headings are fixed markers, written in English in every explanation language; the app shows them in the UI language.
- **Forms blocks** (the only way to show verb and noun forms):

  | Key | Values | Default |
  |---|---|---|
  | `words` | 1 to 3 Greek lemmas, the columns | required |
  | `tense` | a `ConjugationTense` raw value; the rows are the six persons (two for the imperatives) | a verb table |
  | `voice` | `active`, `passive` | the verb's main voice |
  | `rows` | for nouns and adjectives: `nominative singular`, `accusative singular`, … (case and number) | the four nominative and accusative rows |
  | `genders` | `masculine, feminine, neuter`: the columns of one adjective instead of several words | |
  | `headers` | column headers instead of the words (`ο δρόμος, η γυναίκα, το σπίτι`) | the words |
  | `title` | the caption, for a block without a caption line | the tense name, "Noun endings" or "Adjective endings", in the file's explanation language |

  A block with `tense` reads verb lemmas; one with `genders` an adjective; otherwise nouns (a proper noun when no common noun exists). Keys and values are the same in every explanation language (`rows: nominative singular` in a Russian file too); only the rendered labels follow the file's language.

### Build step: `Scripts/build_grammar.py` (#171)

A static step (0129, "Adding static data"), last in `STEPS` after `build_forms`, `build_morphy` and `build_wordlists`, whose tables it reads. Its DDL, `Scripts/grammar_schema.sql`, is the step's `SCHEMA`: `build_dictionaries.py` applies every step's `SCHEMA` before any `build()` (0129), so the step itself only writes rows; `--standalone` and `--self-check` apply it to their own files. The unit tests read it through `#filePath`, as E3's `wordlists_schema.sql`.

```sql
-- One row per topic. Ids are permanent.
CREATE TABLE grammar_topic (
    id     TEXT PRIMARY KEY,   -- 'ell-aorist-regular'
    lang   TEXT NOT NULL,      -- the language taught, ISO 639-3 (the issue's target_lang)
    level  TEXT NOT NULL,      -- 'A1' … 'C2'; sorts as text
    ord    INTEGER NOT NULL,   -- order within the language and level
    UNIQUE (lang, level, ord)
);
-- One row per topic and explanation language.
CREATE TABLE grammar_text (
    topic_id     TEXT NOT NULL,  -- grammar_topic.id
    explain_lang TEXT NOT NULL,  -- ISO 639-3: 'eng'
    title        TEXT NOT NULL,
    body         TEXT NOT NULL,  -- the Markdown after the title, forms tables rendered
    PRIMARY KEY (topic_id, explain_lang)
) WITHOUT ROWID;
-- The front matter's links, in their order.
CREATE TABLE grammar_link (
    topic_id TEXT NOT NULL,
    kind     TEXT NOT NULL,      -- 'word' | 'topic' | 'tense' | 'class'
    key      TEXT NOT NULL,      -- a Greek headword (NFC), a topic id, a ConjugationTense raw value, a class
    ord      INTEGER NOT NULL,
    PRIMARY KEY (topic_id, kind, key)
) WITHOUT ROWID;
```

No index on `grammar_link.key`: a language has about 200 links, and the app reads them all at once.

**Steps**
1. Read every `.md` in the explanation-language directories (`Scripts/data/grammar/eng/`, `rus/`), NFC; the top-level files (README, checklist, review drafts) are not topics. Parse the front matter and the body.
2. **Render forms blocks** from `lemma`, `paradigm` and `tagset`. `verb_slot(tags)` is a port of `ParadigmLayout.verbSlot`: the voice, the person, the finite slots, hidden `rare`, `archaic` and `dated` cells; the generated forms (θα + the dependent, να + the present, …) and E5's fallback (θα and να + the present for a verb without a dependent form) follow `ConjugationTense.forms`. Nominal cells by case, number and gender. A topic's table shows what its rule teaches, not every Wiktionary variant (kyukhin's review of the tables, 2026-11-07): a cell keeps its first form in table order and the variants in -ουνε or -ανε, accents aside (γράφουν / γράφουνε, έγραψαν / γράψανε, θα δουν / θα δούνε), joined with " / ", and drops the others (γράψαν, πατεράδες, γράφτε, θα παν, είσαστε); the present cells of an -άω verb, and the θα and να + present forms built on them, keep only the first set of endings, -άω, -άς, -άει, -άμε, -άτε, -άνε (αγαπάω … αγαπάνε, not αγαπώ, αγαπούν), which `ell-present-2` teaches, or all their forms when none has it. The Definition tables (#144) keep every variant. The block becomes a pipe table, preceded by a comment with its parameters, which the app skips and the cross-check test reads: `<!-- forms words=γράφω,διαβάζω,αγοράζω tense=aorist voice=active -->` for a verb table, which has one voice (`voice`, else the words' common main voice; words with different main voices need `voice`); `<!-- forms words=δρόμος,Αθήνα pos=noun,name rows=nominative.singular,accusative.singular -->` for nouns, one `pos` per word (`noun`, else `name`); `<!-- forms words=καλός pos=adj genders=masculine,feminine,neuter rows=… -->` for an adjective. Row headers: the Greek pronouns, or the case and number in the file's explanation language ("Nominative singular" in `eng`, the Russian names in `rus`). A block without a caption line gets one: its `title`, else the tense name, "Noun endings" or "Adjective endings" in that language. The labels come from a table per explanation language in `build_grammar.py`, next to the required languages; a file in a language without labels fails.
3. **Write** the three tables in sorted order, and, for each taught language with topics (none before #173), a `data_source` row `libredict-grammar-<lang>`, which `packs.json` routes to that language's pack (Data placement). Greek's, `libredict-grammar-ell`: kind `grammar`, "Greek grammar notes (LibreDict)", version the date of the last review, CC BY-SA 4.0, the repository URL of `Scripts/data/grammar/`. Nothing stores a timestamp, so the file stays byte-identical across builds (0129).
4. **Write the review document** `Scripts/reports/grammar-review.md`, committed with the pack: each topic in order as the app shows it (title, level, rule, tables, examples, Watch out, words with their dictionary's first sense, related topics), its gate figures, and "not reviewed" on each topic whose hash is not in `reviewed.tsv`. It also lists, for information, the example words that are no form of a Greek A1 or A2 list word.

**Gates** (the step raises, so the build fails):
- Front matter: known keys; `id` equals the file name and starts with `<lang>-`; `level` in A1 … C2; `order` unique per language and level; the same front matter in every explanation language; an `eng` file for every topic, and for Greek a `rus` file too (the vias of 2.0's Greek pairs; `build_grammar.py` reads the required languages per taught language from its config).
- Body: a title; a rule of at most 120 words; one to three tables; 3 to 5 examples, each a line with Greek letters and a translation line whose letters are in the file's explanation language's script (Latin for `eng`, Cyrillic for `rus`, from the same per-language table); 1 or 2 Watch out items; the blocks in the order above. A word is a whitespace-separated token with a letter in it, after removing Markdown marks; the app's test counts the same way.
- Links: every `words` entry is a headword (NFC, exact) in `entries` of a dictionary from the topic's `lang` into English (`dict_metadata`): for Greek topics the Greek → English ones (El–En · FD, El–En · WN); for 2.1.0's English topics (#176) English WordNet. Every `topics` entry is a topic of the same language; `tenses` are `ConjugationTense` raw values; `classes` are the six known ones; at least one word or topic link per topic; at most 16 words (kyukhin's review, 2026-11-07).
- Tables: a forms block's every word has a lemma of the part of speech it needs and no empty cell in the rows shown; a topic with `tenses` has no pipe table (verb forms are never typed).
- Content: a topic of the Content table has exactly its tenses and classes, in their order (`CONTENT` in `build_grammar.py`). They are front matter, which the review hash leaves out, so changing them means changing this spec first. Other topics (later levels, the self-check's) are not checked.
- Greek text has no Latin or Cyrillic lookalike letters, as E3's gate (Cyrillic since the Russian texts): an example's Greek line and a `words` entry as a whole; a written table's cells and a forms block's `words` and `headers` word by word, since their cells mix English or Russian with Greek (a word mixing Greek with Latin or Cyrillic letters fails, an English word beside a Greek one does not). These gates, and the examples' Greek line, are Greek's; #176 sets English's.
- Review: every text's hash (sha256 of the UTF-8 `title + "\n" + body` as stored, in each explanation language) is in `reviewed.tsv` (`topic id`, `sha256`, `date`). `--allow-unreviewed` skips this gate while drafting, and only `--standalone` takes it; the `STEPS` build never does, so the committed pack is always built without it, which `--verify` checks.
- Size: the three tables together at most 1 MB (#171), printed by `dbstat`. Expected under 0.3 MB for the 17 topics in two languages.

**Modes**
- `--standalone <out.sqlite> [--dictionary <full file>] [--source <dir>] [--report <file>] [--allow-unreviewed]`: builds only the grammar tables against a built full file (default `Scripts/.cache/dictionaries-full.sqlite`), plus the review document, in seconds; `--source` and `--report` read topics from and write the document to other places. The content author iterates with it.
- `--self-check`: offline, as `build_forms.py --self-check`. It builds the forms of `Scripts/fixtures/kaikki-el-sample.jsonl` (γράφω, σπίτι, καλός, βλέπω, κάνω), then fixture topics in `Scripts/fixtures/grammar/`: one valid topic with a verb, a noun and an adjective table, in `eng` and in `rus` (Cyrillic translations, Russian row headers and captions), and one invalid topic per gate. It checks the rendered cells (έγραψα / γράψαμε …, θα γράψω, γράψε / γράψτε, σπίτι / σπιτιού …), that each invalid topic fails with its reason, and that two builds give equal table hashes.

**Format.** The three tables change every file's shape, which bumps `user_version` and `DictionaryFile.formatVersion` (0237's format rule); after 2.0 ships a bump makes every user download their packs again. So the DDL had to reach master before the release even if the rest of E6 is cut: 0237 T1 (#240) put the three tables, empty, into format 4 (Open question 2). #171 and #173 only add rows, so they bump no format.

### Reading (#172)

`DatabaseService`, async, on the schema `DictionarySchemas.listsSchema(for: lang)` (no schema: empty results, no query):
- `grammarTopics(lang:explainLang:) -> [GrammarTopicSummary]`: id, level, order, title and the language the title is in (`explainLang` of the row used), by level and order. The title is the `explainLang` text when the topic has one, else `eng` (one query over `explain_lang IN (?, 'eng')`, `ORDER BY explain_lang = ? DESC`, so another language's text is never taken). The view models pass the via of `lang` (0131's `LearningPairs.via`, the default via when `lang` is not learned), never the UI language; in 2.0 that is `eng` for Greek via English and `rus` for Greek via Russian, and every topic has both texts.
- `grammarTopic(id:explainLang:) -> GrammarTopic?`: the summary, the body and the topic's links.
- The "explained in English" line shows when a summary's language differs from the asked `explainLang` (so never in 2.0): on the Grammar screen for its list, and on the topic screen for its own text, wherever the topic opens from (Definition and the Rule sheet open it without the Grammar screen).
- `grammarLinks(lang:) -> [GrammarLink]`: every link of the language, for the Definition and Rule lookups. About 200 rows, read on each use; no cache.
- `entry(headword:lang:sourceOrder:) -> DictionaryEntry?`: E3's lookup, extracted (Depends on). The topic's words resolve through it with Dictionary Order's sources, enabled first.

### Pure model (#172, #174)

In `Models/Learning.swift`, next to E5's types, tested without a database:
- `GrammarTopicSummary` (id, lang, level, ord, title, explainLang), `GrammarTopic` (summary, body, `words`, `related`, `tenses: [ConjugationTense]`, `classes: Set<GrammarClass>`), `GrammarLink` (topic id, kind, key, ord).
- `GrammarDocument.parse(body:) -> [GrammarBlock]`: `.paragraph`, `.bullets`, `.caption`, `.table(InflectionTable.Section)`, `.examples([GrammarExample])`, `.watchOut`. It reads exactly the shape the build writes and skips `<!-- … -->` lines; anything else becomes a plain paragraph, never a crash.
  - Inline text goes through `AttributedString(markdown:)` with `.inlineOnlyPreservingWhitespace`, as Definition does. Every run of Greek letters (U+0370–U+03FF, U+1F00–U+1FFF) gets `languageIdentifier = "el"`, as #144's labels, so VoiceOver speaks it in Greek.
  - A pipe table becomes an `InflectionTable.Section` (#144's model): the header row gives the columns, an empty top-left cell makes the first column the row headers, each cell's forms are split at " / ". Cell ids are `grammar_cell_<table>_<row>_<column>` (from 1, 0, 0), section ids `grammar_table_<n>`, and each cell's accessibility label is "column, row, text" with its Greek runs in `el`.
  - `GrammarDocument.ruleWordCount` counts words as the build does.
- `GrammarClass` (`verb`, `verbConj1`, `verbConj2`, `verbPassive`, `noun`, `adj`, raw values as in the files) and `GrammarClass.classes(paradigm: LemmaParadigm?, entryPOS: String) -> Set<GrammarClass>`:
  - a verb table: `verbPassive` when `ParadigmLayout.mainVoice` is passive; otherwise `verb`, plus `GrammarClass.conjugation(ofPresent:)` of the first present εγώ form of the active voice: `verbConj2` when it ends in "άω" or an accented "ώ", `verbConj1` when it ends in an unaccented "ω", none otherwise;
  - a noun or proper-noun table: `noun`; an adjective table: `adj`;
  - no table: `noun` or `adj` from the entry's part-of-speech labels (`InflectionLookup.lemmaPOS(forEntryPOS:)`), nothing for a verb.
- `GrammarSubject` (the words, the classes, the tenses the verb has) and `GrammarLinks.topics(for: GrammarSubject, topics:, links:) -> [GrammarTopicSummary]`, the five rules in Behaviour. `GrammarLinks.ruleTopic(verb: DrillVerb, facet: ConjugationFacet, …) -> GrammarTopicSummary?` is the same with the classes of the asked voice and only the topics of the facet's tense; the first in order. A passive facet gives nil unless the verb has passive forms only; then it has no classes, so only a topic that lists the verb gives it Rule (Behaviour).
- A verb's tenses: the `ConjugationTense`s whose `forms` are not empty for some person in the main voice.

### Screens (#172, #174)

- **Learn tab** (`LearnView.swift`, #295): after the Trainers section, a Grammar section: a `NavigationLink` row "Topics" with the value "17", read by VoiceOver as "17 topics" (`learn_grammar_row`), hidden at 0; and, for `ell`, E5's Conjugation row (0132). `LearnViewModel` loads the count with the tab's home; the section is hidden when it has no row.
- **`GrammarTopicsView`** (`LearnView.swift`, view model `GrammarTopicsViewModel` in `LearnViewModel.swift`): a `List` with the English note on top when the topics fell back from the via to English (Reading), then the topics. #297: the pure `GrammarTopicsViewModel.layout(levels:) -> (headers: Bool, subtitle: (count, level?), comingSoon: String?)` decides the rest: with one level, no headers, the subtitle "17 topics · A1" and the next level of `A1 … C2` for the "Coming soon" row (nil after C2); with more, a header per level, the subtitle "40 topics" and no row. The subtitle is the first section's header, a plain secondary line without the header trait (`navigationSubtitle` is iOS 26 only, and the app supports 17); the "Coming soon" row is a `Text`, not a link or button.
- **`GrammarTopicView`** (`LearnView.swift`, view model `GrammarTopicViewModel`): a `ScrollView` of the blocks in a column of at most 700 pt, with the English note above the title when the topic's text fell back from the via to English (Reading).
  - Text blocks are `Text` with the parsed `AttributedString`; tables reuse `InflectionSectionView` (#144's per-section view with its `ViewThatFits` fallbacks and per-cell accessibility); examples are a Greek line and a secondary translation line, combined into one accessibility element.
  - Watch out items have an exclamation-mark icon hidden from VoiceOver, so colour is never the only signal.
  - The explanation blocks (English or Russian) carry `.environment(\.layoutDirection, .leftToRight)`; headings, the Practise button and link rows follow the UI direction.
  - Words rows show the word and its meaning in the meanings language of Greek's pair (E4's `meanings`, 0131: English for both Greek pairs); they push `DefinitionView(entry:)`. Related topics push `GrammarTopicView`. Destination-style `NavigationLink`s, so the screen works in any tab's stack and in the sheet without new `navigationDestination`s.
  - Toolbar: `ReadingModeToolbarButton`.
  - A topic whose pack was removed meanwhile shows `grammar.unavailable`.
- **Definition** (#174): `DefinitionViewModel` already keeps the entry's `LemmaParadigm` (E5). After the table lookup, with or without a table, it builds the `GrammarSubject` (the headword, a linked table's lemma, the classes, the verb's tenses; without a table the headword and the classes from the part of speech, so σε, which has no table, still gets its word link), reads `grammarLinks(lang: "ell")` and `grammarTopics`, and publishes `grammarTopics`. Only for `InflectionLookup.sources`. `DefinitionView` shows the section under the table and E5's Practise button.
- **Environment `\.allowsPractise`** (Bool, default true, `DefinitionView.swift`): the Rule sheet sets it to false; then the Practise button of `GrammarTopicView` and E5's Practise button on Definition are hidden, and the topic itself still shows.

### Practise: the drill for a topic's tenses (#172, extends E5)

- `ConjugationRunViewModel` gains a mode `.tenses(Set<ConjugationTense>)` next to E5's session and single verb.
- The pool is E5's `drillVerbs(lists:)` with `DrillScope.greekLists(checked:)`. When `DrillScope.greekLists(checked:)` is empty (no list checked, or only imported ones), Practise first asks (Decisions, Open question 1), with "No built-in Greek list is checked": "Greek A1" builds the pool from `[ky-ell-a1]`; "Choose lists" opens New words from and starts nothing.
- The level is `DrillScope.tenseLevel(checked:stored:)`, raised to the lowest `DrillLevel` whose facets hold one of the tenses.
- The questions are E5's `ConjugationQuestionBuilder.questions(verb:level:)`, keeping the facets whose tense is one of the topic's and whose voice is the verb's main voice. `ConjugationPlanner.session` takes them as it takes the pool's; its weights, due-first order and retry are unchanged.
- The run, its log rows (`mode` `drill`), the goal hook and the summary are E5's. A plan with no question closes the run at once and writes nothing (not expected: every A1 topic's tense has A1 questions for Greek A1's verbs, a unit test checks it).
- `GrammarTopicViewModel.practise()` follows E5's `DefinitionViewModel.practise()`: when `ell` is not in `learning_languages`, it raises E4's "Learn %@ via %@?" alert with Greek's default pair; Yes calls `LearningLanguageService.learn(language: "ell")`, then presents `ConjugationRunView` in a `fullScreenCover`; No does nothing.
- The button's title is E5's `drill.practise` and the tense terms the topic texts use (kyukhin, 2026-11-07: «Будущее: простая форма», "Future: simple form"; `ConjugationTense.title` carries them), joined with " · ". Only tenses with a question at the run's level are named.

### Rule in the drill (#174, extends E5)

- `ConjugationRunViewModel` computes `ruleTopic` for each question when it is built: `GrammarLinks.ruleTopic` over the links read once per run.
- `ConjugationRunView` (`ExerciseView.swift`) adds a bordered "Rule" button (`drill_rule_button`, `book` icon) to the feedback bar beside Continue when `ruleTopic` is not nil. It presents a `.sheet` with a `NavigationStack` around `GrammarTopicView`, a Done button (0237's `welcome.done`) and `.environment(\.allowsPractise, false)`. The run's state does not change while the sheet is open.

### Layering

SQL only in `DatabaseService`. The document parser, classes, link rules and the tense filter are pure and unit-tested. View models load and compose; views render the blocks, sections and summaries they are given. Python renders and validates; Swift checks the result.

### Test seams

- No new launch argument. UI tests use 0237's `-skipWelcome`, `-installPacks ell -packFixtures <path>` and `-resetPacks`, E4's `-learningLanguages`, `-learningLists`, `-learningSeed`, `-learningAnswerHints`, and E5's `-drillLength`.
- Unit tests read the real Greek pack through `PackFixtures` (0237), and build made-up grammar rows with `TestDictionary.make(rows:)` plus `grammar_schema.sql` through `#filePath`.
- `GrammarLinks` and `GrammarDocument` tests use fixed links and bodies.

### Identifiers

| Element | Identifier |
|---|---|
| Learn tab row | `learn_grammar_row` (value: the topic count) |
| Grammar screen | `grammar_topics`, `grammar_english_note`, `grammar_subtitle` (#297), `grammar_level_<level>` (a section header, only with two or more levels since #297), `grammar_topic_row_<id>` (`grammar_topic_row_ell-aorist-regular`), `grammar_coming_soon` (#297; value: the level, `A2`) |
| Topic screen | `grammar_topic`, `grammar_english_note`, `grammar_topic_title`, `grammar_topic_level`, `grammar_rule`, `grammar_table_<n>`, cells `grammar_cell_<n>_<row>_<column>`, `grammar_examples`, `grammar_example_<n>`, `grammar_watch_out`, `grammar_practise_button` (value: the tense raw values, comma-joined), `grammar_word_<word>`, `grammar_related_<id>`, `grammar_unavailable`; Reading Mode keeps `reading_mode_toggle` |
| Definition | `definition_grammar_section`, `definition_grammar_topic_<id>` |
| Drill | `drill_rule_button`; the sheet `grammar_sheet` and its `grammar_sheet_done` |
| Credits | `credits_greek_grammar` |

### Strings

About 11 new keys in the five languages, translated by the implementing agent (overview, Localization). Topic titles and bodies are content, in English, never in the catalog.

| Key | en |
|---|---|
| `grammar.title` | Grammar (the Learn tab's section, the screen title and the Definition section) |
| `grammar.topics` | Topics (#295: the Learn tab's row) |
| `grammar.comingSoon` | Coming soon (#297; the row reads the level name, " · ", then this) |
| `grammar.topicCount` | %lld topics (plural variants) |
| `grammar.inEnglish` | Topics are explained in English. |
| `grammar.section.examples` | Examples |
| `grammar.section.watchOut` | Watch out |
| `grammar.section.words` | Words |
| `grammar.section.related` | Related topics |
| `grammar.rule` | Rule |
| `grammar.a11y.rule` | Grammar rule: %@ (a tense title) |
| `grammar.unavailable` | Download Greek to read this topic. |
| `credits.dataSources.greekGrammar` | Greek grammar notes: LibreDict (CC BY-SA 4.0) |

- Reused: E3's `wordLists.level.*` (Α1 in Greek), E5's `drill.practise` and `ConjugationTense.title`, E4's `learn.learnLanguage.title` and its Yes and No, 0237's `welcome.done`.
- Composed Arabic strings start with U+200F, and Greek inside them is wrapped in FSI…PDI (#119). The " · " separator is not translated.
- `testEveryCatalogKeyIsTranslatedInEveryShippedLanguage` covers the keys.

### Code map

| Path | Change | Ticket |
|---|---|---|
| `Scripts/grammar_schema.sql` | New: the DDL | #171 (or earlier, Open question 2) |
| `Scripts/build_grammar.py` | New step: parse, render, gates, review document, `--standalone`, `--self-check`; in `STEPS` | #171 |
| `Scripts/build_dictionaries.py` | `STEPS`; no format bump: 0237 T1 put the empty grammar tables into format 4 | #171 |
| `Scripts/packs.json` | Grammar rows to `ell` and `eng-lists` | #171 |
| `Scripts/fixtures/grammar/` | Self-check topics | #171 |
| `Scripts/data/grammar/eng/ell-*.md` (17), `Scripts/data/grammar/rus/ell-*.md` (17), `Scripts/data/grammar/reviewed.tsv`, `Scripts/data/grammar/README.md` | Content, review hashes, authoring brief and license | #173 |
| `Scripts/reports/grammar-review.md` | Written by the build, committed | #171, #173 |
| The Greek pack asset and every file's format (0237) | Rebuilt and cut | #171, #173 |
| `DictApp/DictApp/Models/Learning.swift` | `GrammarTopicSummary`, `GrammarTopic`, `GrammarLink`, `GrammarDocument`, `GrammarBlock`, `GrammarExample` (#172); `GrammarClass`, `GrammarSubject`, `GrammarLinks` (#174); the tense filter for `ConjugationPlanner` (#172) | #172, #174 |
| `DictApp/DictApp/Services/DatabaseService.swift` | `grammarTopics`, `grammarTopic`, `grammarLinks`; `entry(headword:lang:sourceOrder:)` extracted from E3 | #172 |
| `DictApp/DictApp/ViewModels/LearnViewModel.swift` | The topic count; `GrammarTopicsViewModel`, `GrammarTopicViewModel`; `ConjugationRunViewModel`'s `.tenses` mode (#172) and `ruleTopic` (#174) | #172, #174 |
| `DictApp/DictApp/Views/LearnView.swift` | The Grammar section, `GrammarTopicsView`, `GrammarTopicView` and its block views | #172 |
| `DictApp/DictApp/ViewModels/DefinitionViewModel.swift`, `Views/DefinitionView.swift` | `grammarTopics` and the Grammar section; `\.allowsPractise`, which hides E5's Practise button | #174 |
| `DictApp/DictApp/Views/ExerciseView.swift` | The Rule button and sheet | #174 |
| `DictApp/DictApp/Views/CreditsView.swift`, `Resources/Localizable.xcstrings` | The credit line; the keys | #172, #173 |
| `DictApp/DictAppTests/DictAppTests.swift` | The unit classes in the Test plan | all |
| `DictApp/DictAppUITests/TestCases/GrammarFlowTests.swift`, `PageObjects/GrammarPage.swift`, `TestHelpers/AccessibilityIdentifiers.swift`; additions to `ConjugationDrillFlowTests`, `ArabicLocalizationTests`, `GreekLocalizationTests`, `iPadSpecificTests` | UI tests (a synchronized folder, no Xcode step) | #172, #174 |
| `docs/specs/0000-overview.md`, `0129-dictionary-file.md` | Screens, Code map, Bundled data, Localization, tests; 0129's E6 line | each PR |

**No new Swift file**, so no Xcode step and no `project.pbxproj` edit: every type goes into files on master or added by the Xcode step of 2026-11-04 (`Learning.swift`, `LearnViewModel.swift`, `LearnView.swift`, `ExerciseView.swift`). The Python, SQL, Markdown and TSV files are outside every target. `INFOPLIST_KEY_CFBundleDisplayName` stays `LibreDict`. No new dependency, entitlement or Info.plist key. E6 makes no network call.

### Tickets, order and sizes

Sizes are pipeline days: development, QA on the four simulators, review and the daily merge.

| Ticket | Scope | Needs | Size | Stream |
|---|---|---|---|---|
| #171 Format and build | `grammar_schema.sql`, `build_grammar.py` (parse, render forms, gates, links, `data_source`, review document, the `reviewed.tsv` gate per text, the required `rus` texts and their script check, `--standalone`, `--self-check`), `STEPS`, `packs.json`, rebuild and cut (no format bump, T1 has the tables), `GrammarFileTests` | Approval; 0237 T1 (`packs.json`, the cut); E3 #152 for the list words in the report | M, 1.75 | Data |
| #173 Content | The 17 topics in English and in Russian (with the Russian-specific Watch out items), `README.md`, the Credits line, the two review passes with kyukhin, corrections, `reviewed.tsv`, the rebuild; `GrammarContentTests`, and `testGreekGrammarIsInTheGreekPack` asserting the 17 topics | Drafting: approval only. The rebuild: #171 | M, 1.5 (plus kyukhin's review of both languages) | Drafting outside the four streams (Open question 4); the rebuild on Data |
| #172 Reader | Learn home section, Grammar screen, topic screen (parser, tables through `InflectionSectionView`, examples, Watch out, words, related, Reading Mode, Arabic), Practise for tenses with "Learn Greek via English?", the explanation language from the via, reads, strings, `GrammarFlowTests`, the language and iPad tests | Develops on fixtures from the DDL; UI tests need #173's content; Practise needs E5 #168 and #169, E4 #158 | M–L, 2.5 | UI |
| #174 Links | `GrammarClass`, `GrammarLinks`, the Definition section, `\.allowsPractise`, the Rule button and sheet, their tests | #172; E5 #168 | M, 1.25 | UI, after #172 |

- In all: 7 stream-days, plus kyukhin's review. Order: #171 first (or its DDL earlier), then #172 and #173 in parallel, then #174, as the epic says.
- **Calendar** (window 11-20 to 11-27):
  1. From approval: #173's texts drafted from this spec; kyukhin's first review pass (text, examples, written tables) before 11-20 (Open question 4).
  2. 11-20 to 11-21: #171 on the first free data stream; #172 starts on a UI stream against fixtures.
  3. About 11-22: #173 applies the first pass, rebuilds, and sends the rendered forms tables for the short second pass.
  4. About 11-23: #173 merges with `reviewed.tsv`; #172 merges after E5's #168.
  5. About 11-25: #174 merges. 11-26 and 11-27 are slack.
- **The risk** is kyukhin's review: if both passes happen after 11-20, #173 merges about 11-25 and the slack is gone.
- **If late** (checkpoint 11-24), nothing is cut, E6 included: the release date moves (Decisions, Open question 5).
- Learning pairs (kyukhin, 2026-11-04) add no day: #172 asks for the via instead of the UI language and tests the fallback line, inside its 2.5. The limited Greek via Russian (kyukhin, 2026-11-04) adds 0.75: #173 +0.5 (17 Russian texts with the Russian-specific Watch out items, a second review language), #171 +0.25 (the `rus` texts required and checked, review hashes per text); #172 reads `rus` through the same via and does not grow. kyukhin's review grows by the Russian texts.

## Test plan

Unit classes go in `DictAppTests.swift`; async tests and mostly-async classes are `@MainActor` (#229). Classes that read real topics read the Greek pack through `PackFixtures`; made-up rows use `TestDictionary.make(rows:)` and `grammar_schema.sql`. UI suites run one per `xcodebuild` run on the four-simulator matrix (iPhone and iPad, iOS 17.5 and 26.4), with the app uninstalled before each, `-resetData`, `-skipWelcome` and `-installPacks ell`.

| Acceptance criterion | Test |
|---|---|
| #133, #173: every topic has a rule of at most 120 words, a table, 3–5 examples with translation, "Watch out" and links | Build gates (Build step). `build_grammar.py --self-check` (one invalid fixture topic per gate fails with its reason). Unit `GrammarContentTests.testEveryTopicHasTheStructure` (every shipped topic, parsed by `GrammarDocument`: rule ≤ 120 words, 1–3 tables, 3–5 examples each with a Greek line and a translation, 1–2 Watch out items, at least one word or topic link) |
| #173: 17 A1 topics | Unit `GrammarContentTests.testSeventeenA1TopicsInOrder` (the 17 ids of Content, in order, all A1, all with an `eng` and a `rus` text) |
| #133, #171: verb tables are rendered from the paradigm data | `--self-check` (γράφω's aorist, future and imperative, σπίτι's cases, καλός by gender, from the kaikki sample; the cell rule: έγραψαν / γράψανε, γράψτε, θα πάνε, and αγαπάω's present αγαπάω … αγαπάνε). Unit `GrammarContentTests.testFormsTablesMatchTheParadigms` (every forms table of the pack, by its comment: each cell equals `ConjugationTense.forms` of `ParadigmLayout.voiceForms`, or #144's nominal cell, after the build's cell rule (the first form and the -ουνε, -ανε variants; an -άω verb's first set), joined with " / "), `testTopicsWithTensesHaveNoTypedTable` |
| #171: a topic edit shows as a readable diff and lands in the app after a rebuild | The Markdown source and `grammar-review.md` diffs in the PR; `build_dictionaries.py --verify` and `cut_packs.py --verify` (0237). Unit `GrammarFileTests.testPackHoldsTheSourceTopics` (every `Scripts/data/grammar/eng/*.md`, read through `#filePath`, has its topic, title and link rows in the pack). QA: change a word in a topic, rebuild, see it on the topic screen |
| #171: added size under 1 MB | Build gate (`dbstat`). Unit `GrammarFileTests.testGrammarTablesUnderOneMegabyte` |
| 0237: Greek grammar in the Greek pack | Unit `GrammarFileTests.testGreekGrammarIsInTheGreekPack` (the pack has the 17 topics; the bundle and the stub have the three tables, empty; no other pack has a Greek topic or the credit): #173's, since #171 lands it relaxed to the source topics, none before #173, and #173 asserts the 17. `testLinksResolve` (every word link is a Greek → English headword in the pack, every topic link a topic, every tense a `ConjugationTense`, every class known), `testGrammarDataSourceRow` (`libredict-grammar-ell`, CC BY-SA 4.0, once the pack has topics; none before #173) |
| #133, #173: Greek examples and tables reviewed by kyukhin (LLM-assisted) before merge | Build gate on `reviewed.tsv` (the committed pack is built without `--allow-unreviewed`). Unit `GrammarContentTests.testEveryTopicIsReviewed` (sha256 of each stored title and body, in each explanation language, is in `reviewed.tsv`, read through `#filePath`). The #173 PR names kyukhin's review dates; History records them |
| #173: no copied third-party text | Review: the authoring brief in `README.md`, kyukhin's review, and the PR's statement that no source text was given to the drafting LLM |
| #172: topics are listed by level and open | UI `GrammarFlowTests.testTopicsByLevel` (`-learningLanguages ell`: `learn_grammar_row` reads 17; since #297 no `grammar_level_A1`, `grammar_subtitle` reads "17 topics · A1", `grammar_topic_row_ell-alphabet` first and `…_ell-imperative` last, then `grammar_coming_soon` reads "A2 · Coming soon"; a tap on a topic opens `grammar_topic`). Unit `LearnViewModelTests.testGrammarRowOnlyWithTopics` (Greek with the pack: 17; English: hidden; Greek with the stub: hidden) |
| #297 (kyukhin, 2026-11-10): Greek's Grammar shows 17 topics without a header and an "A2 · Coming soon" row at the end, in five languages | Unit `GrammarTopicsViewModelTests.testOneLevelHasNoHeader` (pure `layout`: A1 only: no headers, subtitle 17 and A1, coming soon A2; A1 and A2: headers, subtitle without a level, no coming soon; C2 as the only level: no coming soon). UI `GrammarFlowTests.testTopicsByLevel` (above), `GreekLocalizationTests.testGrammarInGreek` (the subtitle holds Α1 and the row Α2), `ArabicLocalizationTests.testGrammarTopicRightToLeft` (the row mirrored); the catalog test |
| #297: the "Coming soon" row is not a button for VoiceOver | UI `GrammarFlowTests.testComingSoonIsNotAButton` (`grammar_coming_soon` is static text, no button with its id; a tap pushes nothing) |
| #295: the Grammar section on Greek's tab holds the topics and Conjugation | 0131's `PairTabsTests.testGrammarSectionPerLanguage` |
| #172: the topic screen shows rule, table, examples, Watch out, links | Unit `GrammarDocumentTests` (pure): `testRuleParagraphsAndLists`, `testPipeTableWithAndWithoutRowHeaders`, `testFormsCommentIsSkipped`, `testExamplesAreTwoLineItems`, `testWatchOut`, `testUnknownLinesBecomeParagraphs`, `testGreekRunsCarryTheGreekLanguage`, `testRuleWordCountMatchesTheBuild`. UI `GrammarFlowTests.testTopicStructure` (`ell-aorist-regular`: `grammar_cell_1_0_0` reads έγραψα, 3–5 `grammar_example_*`, `grammar_watch_out`, `grammar_practise_button`, `grammar_related_ell-aorist-irregular`) |
| #172: word links open the Definition; topic links open the topic | UI `GrammarFlowTests.testWordLinkOpensDefinition` (`grammar_word_γράφω` → `definition_view` for γράφω; History records it), `testRelatedTopicOpensTopic`. Unit `GrammarTopicViewModelTests.testWordsResolveInDictionaryOrder` (the first Greek dictionary of the order, enabled first; the short meaning) |
| #172: "Practise" opens the drill for that tense | Unit `ConjugationPlannerTests.testTenseRunAsksOnlyThoseTenses` (aorist, Greek A1's pool, 100 seeds: every facet is `aorist` in the verb's main voice), `testTenseRunRaisesTheLevelForItsTense` (imperfect with tenses up to A1: B1, imperfect only), `testEveryA1TopicHasQuestions`, `testTenseRunWithoutCheckedListsUsesGreekA1` (Open question 1). `GrammarTopicViewModelTests`: `testPractiseStartsWhenGreekIsLearned`, `testPractiseAsksToLearnGreek`, `testNoCancels` (no card, no log row, languages unchanged), `testYesLearnsGreekThenStarts`, `testNoPractiseWhenNotAllowed`, `testPractiseWithoutListsAsks` (no Greek list checked: the question; "Greek A1" starts the drill on Greek A1's verbs; "Choose lists" opens New words from, with no card and no log row). UI `GrammarFlowTests.testPractiseOpensTheDrillForThatTense` (`-learningLists ky-ell-a1 -drillLength 3 -learningSeed 1`: `exercise_view`; every `drill_prompt_tense` starts with "Aorist"), `testPractiseAsksLearnGreekFirst` (no learned language, the topic opened from γράφω's Definition: the alert; No: no `exercise_view`) |
| #174: γράφω links to the present and aorist topics; a noun links to articles and endings | Unit `GrammarClassTests` (pure: `conjugation(ofPresent:)` of γράφω, δουλεύω, ακούω, λέω, τρώω → `verbConj1`, of αγαπάω, αγαπώ, μπορώ, οδηγώ → `verbConj2`, of ζω → `verbConj1` (the content lists it); `classes` of the tables of έρχομαι, θυμάμαι → `verbPassive`, of πάω (πηγαίνω's table) → `verbConj1`, of σπίτι, Αθήνα → `noun`, of καλός → `adj`; a noun entry without a table → `noun`; a verb without one → none). `GrammarLinksTests` (pure, fixed links): `testBehaviourTable` (every row of the Behaviour table), `testListedWordWinsItsTenses` (πηγαίνω, έχω, ζω), `testTenseNeedsTheVerbsForms` (έχω: no aorist topic), `testLinkedTableLemmaCounts` (πάω via πηγαίνω), `testOrder`. `DefinitionViewModelGrammarTests` (real pack): `testVerbLinksToItsTenseTopics` (γράφω from El–En · FD and El–En · WN: `ell-present-1` and `ell-aorist-regular` among them), `testNounLinksToArticlesAndEndings` (σπίτι), `testEnglishEntryHasNone`, `testNoneWithoutTheGreekPack`. UI `GrammarFlowTests.testDefinitionLinksOfGrafo` (search γράφω: `definition_grammar_topic_ell-present-1` and `…_ell-aorist-regular`; a tap opens the topic), `testNounLinksToArticlesAndEndings` (σπίτι) |
| #174: "Rule" in the drill opens the right topic | Unit `GrammarLinksTests.testRuleTopicForDrillFacets` (γράφω aorist → `ell-aorist-regular`; πηγαίνω aorist → `ell-aorist-irregular`; αγαπάω present → `ell-present-2`; έχω present → `ell-eimai-echo`; έρχομαι `aorist.passive` → `ell-aorist-irregular`; θυμάμαι's passive facets, γράφω `present.passive` and `aorist.passive`, and any imperfect → none). UI `ConjugationDrillFlowTests.testRuleOpensTheTensesTopic` (Practise on γράφω, `-learningAnswerHints`: answer; `drill_rule_button` opens `grammar_sheet` with the topic of the question's tense and no `grammar_practise_button`; a word link there shows no `drill_practise_button`; Done: back on `exercise_feedback`, Continue goes on), `testNoRuleWithoutATopic` (tenses up to B1: an imperfect question has no `drill_rule_button`) |
| kyukhin 2026-11-04 (pairs): explanations in the via language; a via without texts shows English with a line | Unit `GrammarTopicsViewModelTests.testExplanationLanguageIsTheVia` (Greek via English, in each UI language: `eng` texts and no note; Greek via Russian (the limited pair): `rus` texts and no note; a made-up via without texts: the `eng` texts with the note, never the `rus` ones; Greek not learned: Greek's default via), `GrammarTopicViewModelTests.testEnglishNoteOnAFallbackTopic` (that via, the topic opened alone as from Definition: its `eng` text with the note), `GrammarTopicViewModelTests.testWordMeaningsInTheVia` (the Words rows use 0131's `meanings`) |
| kyukhin 2026-11-04: Greek via Russian reads the grammar in Russian, with Russian-specific Watch out items | Unit `GrammarContentTests.testRussianTextsHaveTheRussianWatchOut` (the Russian Watch out of `ell-eimai-echo` names είμαι and έχω, of `ell-articles` το πρόβλημα, το θέμα, το όνομα and an article before a name, of `ell-possessives` μου after a noun with its article), `testRussianTextMatchesTheEnglishShape` (same front matter, the same forms tables, the same Greek example lines). UI `GrammarFlowTests.testGreekViaRussianReadsRussian` (`-AppleLanguages (ru) -learningLanguages ell:rus`: `grammar_rule` and the example translations are Cyrillic, no `grammar_english_note`; with `-learningLanguages ell:eng`, the same topic in English) |
| #133, #172: UI in 5 languages, explanations in English; Arabic right to left; iPhone and iPad, iOS 17.5 and 26.4 | `testEveryCatalogKeyIsTranslatedInEveryShippedLanguage`. UI `ArabicLocalizationTests.testGrammarTopicRightToLeft` (Arabic headings; the rule and the table laid out left to right; link rows mirrored), `GreekLocalizationTests.testGrammarInGreek` (`grammar_subtitle` holds Α1 since #297, Greek headings, English topics, no `grammar_english_note`: Greek via English explains in English), `iPadSpecificTests.testGrammarTopicOnIPad` (a centred column at most 700 pt wide, landscape); every suite above on the matrix |
| Reading Mode on a topic | UI `GrammarFlowTests.testReadingModeOnTopic` (`reading_mode_toggle` on the topic's toolbar switches to its "on" label, and back) |
| Credits | UI `GrammarFlowTests.testCreditsListsGrammar` (`credits_greek_grammar` through `settings_credits_link`) |
| Offline | Review: no networking API in the diff |
| Performance | QA: a topic opens in under 100 ms and a Definition's grammar lookup adds under 10 ms (iPhone 15 Pro simulator, iOS 17.5, median of 5), recorded in History |

## Open questions

1. **Practise with no Greek list checked.** Resolved 2026-11-04: ask the user (Decisions).
2. **When the grammar tables reach the schema.** Resolved 2026-11-04: with #240, empty (Decisions).
3. **License and credit of the grammar text.** Resolved 2026-11-04: CC BY-SA 4.0, credited on the Credits screen opened under the version (Decisions).
4. **Content before the window.** Resolved 2026-11-04: drafted right after approval, outside the streams (Decisions).
5. **Cut order if late.** Resolved 2026-11-04: nothing is cut; the release date moves instead (Decisions).

## History

- 2026-11-04: First draft. Aligned with 0130, 0131, 0132 and 0237 as kyukhin approved them on 2026-11-04. Applies 0237's rule (Greek grammar in the Greek pack) and adds two small extensions to E5: Practise for a topic's tenses, and the Rule button.
- 2026-11-04: Learning is chosen as a language pair (kyukhin, 0131): topics are explained in the via language of the language taught (`grammarTopics(lang:explainLang:)` gets the via, not the UI language); a via without texts falls back to English with the "explained in English" line, which 2.0 (Greek via English only) never shows; Words rows show their meaning in the via; "Learn Greek via English?". The cut order is replaced by "nothing is cut". No size change.
- 2026-11-04: Approved by kyukhin.
- 2026-11-04: Greek via Russian is offered as a limited pair (kyukhin, 0131): all 17 topics get Russian texts (`Scripts/data/grammar/rus/`) with Russian-specific Watch out items, required and checked by the build and reviewed with the English ones; Greek via Russian, and a Russian UI's default, read them; Words rows use the pair's meanings language (English). #171 +0.25, #173 +0.5 (7 days in all), plus the Russian review.
- 2026-11-04: Small fix after approval, for the Russian texts (#173): the build rules follow each file's explanation language. Translation lines are checked against that language's script (Cyrillic for `rus`), and rendered row headers and default captions come in that language. Greek text is also checked for Cyrillic lookalikes, the review gate checks every text's hash as the test plan does, not only `eng`, and the self-check gets a Russian fixture topic.
- 2026-11-06: Rebased on master with 0130 and 0237. Review fixes: the English fallback reads only the asked language and English; a passive facet has no Rule topic before any rule; Practise with no Greek list checked asks first, as decided, with a test; the intro says which specs are on master.
- 2026-11-06: Review fixes: the build reads topics only from the explanation-language directories; Russian blocks are left-to-right too.
- 2026-11-07: Review fixes (CodeRabbit, PR #248): `\.allowsPractise` hides the Practise buttons, never the topic; the Practise prompt follows `DrillScope.greekLists(checked:)` being empty, so an imported Greek list alone also asks; T1 holds the grammar tables, so #171 bumps no format. For #171: the build checks each topic's tenses and classes against Content. For #173's review: A1 verbs with an irregular aorist outside topic 14's words (κάνω → έκανα and others) must not link to the regular aorist.
- 2026-11-07: #171 as built. No format bump: T1 has the tables. The credit row is written only when a language has topics, and `packs.json` routes `libredict-grammar-ell` to the `ell` pack. Adjective tables' default caption is "Adjective endings". The forms comment gains `pos`, `rows` and `genders`, and a verb table has one voice. Lookalike letters are checked word by word in written tables and forms headers (a lone Latin letter in a Greek cell passes; #173's drafts were scanned clean). `--allow-unreviewed` only with `--standalone`, which also takes `--source` and `--report`. A caption is one bold span only, so a rule line in bold is no caption. Two tests are relaxed until #173: `testGreekGrammarIsInTheGreekPack` checks the source topics, `testGrammarDataSourceRow` the credit only with topics. The self-check runs 66 cases.
- 2026-11-07: The Content gate: the build fails a topic of Content whose tenses or classes differ, with a self-check fixture (67 cases). Review fixes (CodeRabbit on 0133): the step's `SCHEMA` is applied by `build_dictionaries.py`; the Links gate is per taught language (Greek → English headwords for Greek); a topic opened straight from Definition or the Rule sheet shows the English note itself; Definition builds `GrammarSubject` with or without a table (σε); the 17-topic check of `testGreekGrammarIsInTheGreekPack` is #173's.
- 2026-11-07: #173, kyukhin's review of the Russian texts. Headwords: `ell-articles` links ο, το, ένας (η is no headword), `ell-pronouns` drops αυτοί and `ell-negation-questions` ποιανού, which stays in its table. The Russian Watch out of `ell-articles` names το πρόβλημα, with το νερό and η θάλασσα; θέμα (not A1) and όνομα (neuter in Russian too) are gone, so `testRussianTextsHaveTheRussianWatchOut` checks those.
- 2026-11-07: #173: a topic links at most 16 words (was 12), so `ell-aorist-irregular` links the 16 verbs it teaches (kyukhin's review, item 30) and none of them falls back to the regular aorist (#174). Greek words are checked for lookalike letters word by word in every text line (title, rule, captions, Watch out), not only in tables. The self-check runs 74 cases.
- 2026-11-07: #173, kyukhin's terms (review of the Russian texts): the texts, the default captions and the topic's Practise button (#172) name the tenses alike: «Будущее: простая форма», «Сослагательное наклонение: простая форма», «Повелительное наклонение: простая форма» and «…: длительная форма»; in English "Future: simple form", "Subjunctive: simple form", "Imperative: simple form" and "…: continuous form". The build's labels no longer copy `ConjugationTense.title`.
- 2026-11-07: #173, kyukhin's review of the forms tables (`Scripts/data/grammar/review-final-notes.md`): the cell rule of "Build step", so the third persons plural read έγραψαν / γράψανε, έφαγαν / φάγανε, θα πάνε, πατέρες has no πατεράδες, γράψτε no γράφτε and είστε no είσαστε, and αγαπάω's present shows one set of endings. `ell-possessives` and `ell-se-prepositions` no longer link μου and για, which El–En · FD glosses "moo" and "just, let"; the texts keep them. The review document's list check lowercases the example words and lemmatises them and the list words through `form_lookup` (αδερφές and the list's αδερφή are both αδελφή). `reviewed.tsv` holds the 34 texts as kyukhin approved them on 2026-11-07, the Greek pack carries the 17 topics, and the two tests #171 relaxed are tight again (the 17 topics in order; the credit row, versioned by the last review). The self-check runs 79 cases.
- 2026-11-08: #173, the eight content fixes from CodeRabbit on PR #264, decided by kyukhin: an adjective's feminine after a vowel usually ends in -α; θέλω has a rare aorist, θέλησα, and ήθελα is named as the imperfect; the singular article shows the gender; the accusative follows most prepositions; most feminine and all neuter nouns keep their form, feminines in -ος change like masculines (Watch out); έντεκα never changes; a stated duration usually takes the aorist (Russian). The two alphabet tables have an empty top-left cell, so their letters are row headers (kyukhin 2026-11-08). kyukhin approved the diff on 2026-11-08, and `reviewed.tsv` holds the new hashes. `GrammarContentTests.testEveryTopicIsReviewed` checks the hash of every shipped text against `reviewed.tsv`.
- 2026-11-08: #172 as built: the no-list question has its own string, `grammar.practise.noLists`; `\.allowsPractise` lands with #172, not #174; a topic's words open through E3's order (the pair's dictionaries first, enabled first, FD before WN); the Grammar row's VoiceOver value is "17 topics"; Greek words only spaces apart are read as one Greek phrase; the `.tenses` run carries the verbs and the level; a Practise run with no questions shows E5's empty screen instead of closing. `testPractiseAsksLearnGreekFirst` and `grammar.rule`/`grammar.a11y.rule` move to #174. Stress marks over Cyrillic (про-и-о́н, ко́змос) sit on the vowel in light, dark and the largest text size, so no capital-letter fallback is needed. QA: 17 deliberate breaks each failed their target test (the right-to-left one after short-line checks were added); a topic loads in 5–12 ms median, 26 ms at most (iPhone 15 Pro, iOS 17.5, Debug); unit 1020 pass; `GrammarFlowTests` 9/9 on iPhone 17 and iPad Pro 11-inch (iOS 26.4) and on iPhone 15 Pro (iOS 17.5).
- 2026-11-08: #174 as built: without a table, a word a topic lists gets no class from its part of speech (rule 4), so εγώ, θα and σου, which FreeDict calls nouns, lose Articles and Noun endings and get only their listing topic, as the Behaviour table says; 3 of the pack's 99 listed entries change. The key is `grammar.a11y.rule %@`; `ConjugationRunViewModel` takes the languages service to read the topics; Rule shares the Example button's place in the feedback bar; rule 1 uses the lemma of any table shown; Done is only on the sheet's first screen. iPadSpecificTests skips landscape on the iPadOS 26.4 simulator, which does not rotate (it passes on 17.5). QA: 16 deliberate breaks each failed their test; every Behaviour row is tested on the real pack; the Definition screen's grammar read takes 0.6–0.9 ms median, 4.5 ms at most (iPhone 15 Pro, iOS 17.5, Release); unit 1066 pass; `GrammarFlowTests` 13/13 on iPhone 17, iPad and iPhone 15 Pro. E6 is implemented.
- 2026-11-08: kyukhin: a passive facet of a verb with passive forms only gets Rule from a topic that lists the verb, never from a class topic, so the aorist of έρχομαι (ήρθα) opens Irregular aorists. The passive of a verb with both voices still has no Rule (γράφομαι): the listed topics teach the active forms.
- 2026-11-08: #180 moves the Credits row under the version in Settings, as decided on 2026-11-04 (Decisions).
- 2026-11-10: Revision for epic #292 (Draft, awaiting kyukhin's approval): the Grammar section sits after Trainers on Greek's pair tab and holds the topics row ("Topics · 17") and E5's Conjugation row (#295); the Grammar list drops its only level header, shows "17 topics · A1" under the title and ends with an "A2 · Coming soon" row that is not a button (#297).
- 2026-11-10: The #292/#300 revision approved by kyukhin.
