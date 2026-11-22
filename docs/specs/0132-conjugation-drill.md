# Greek conjugation drill

> Spec written by Claude (AI) for LibreDict.
> Status: Implemented, with a revision for epic #292 (#295: the Conjugation row moves to Greek's Grammar section; #299: a wrong form shows its tense and person) and #300 (sounds), approved by kyukhin on 2026-11-10 and built (PRs #303, #304, #305); the rest approved by kyukhin on 2026-11-04; the example in the answer panel (#364) approved by kyukhin on 2026-11-22 · Epic: #132 · Tickets: #167, #168, #169; #295, #299, #300; #329, #330, #331; #364 · Updated: 2026-11-22

Read [0000-overview.md](0000-overview.md), [0129-dictionary-file.md](0129-dictionary-file.md) and [0136-word-forms.md](0136-word-forms.md) (the Greek paradigms and `ParadigmLayout`) first. Then read the specs this epic builds on. kyukhin approved them on 2026-11-04. 0130 and 0237 are on master; 0131 and 0166 come with PR #235, which merges before this spec: [0130-word-lists.md](0130-word-lists.md) (E3, the Greek A1–B1 lists), [0131-learning.md](0131-learning.md) (E4: cards, the answer log, the run views, the Learn tab, its "For E5" section), [0166-learning-statistics.md](0166-learning-statistics.md) (E10: the goal, accuracy by tense) and [0237-downloads.md](0237-downloads.md) (#237: the Greek forms and lists move into the Greek pack, attached as `ell`). Numbers marked "measured" come from a prototype run on 2026-11-04 against the dictionary file of master `fc8c930` (format 3) and kyukhin's three CSVs of 2026-10-22, with είμαι moved to A1 (0130, Decisions).

## Why

A Greek verb has six persons in each of a dozen tenses, two voices and many irregular stems (γράφω, έγραψα; έρχομαι, ήρθα). Learners know what a verb means long before they can produce its aorist. The Definition screen shows the tables (#144). This epic turns them into practice: a multiple-choice drill by exam level, "γράφω · aorist · εγώ → έγραψα". It is scheduled with the same spaced repetition as words (E4) and feeds accuracy by tense into the statistics (E10). It is for learners of Greek, the language 2.0 teaches in depth.

## Behaviour

### Where the drill starts (#168)

- **Learn → Greek's tab → Grammar → Conjugation** (in Trainers until #295; kyukhin, 2026-11-10): a row on Greek's pair tab (0131), under the grammar topics (0133). It reads "Conjugation · A2", with the drill's tense level, and opens the Conjugation screen:
  - **the verbs**: "Verbs from Greek A1, Greek A2 · 253 verbs". The drill follows the lists checked on New words from (0130): its verbs are the verbs of the checked Greek lists only (kyukhin, 2026-11-04);
  - **"Tenses up to"**: A1, A2, B1, B2 (Α1, Α2, Β1, Β2 in a Greek UI, as E3 names levels). It starts at the highest checked level and can be raised up to B2 for the same verbs, to add the perfect tenses and the passive past (kyukhin, 2026-11-04). Levels below the highest checked one are not offered. The choice is remembered;
  - the tenses this gives (Levels, below), each with its accuracy over the last 30 days once it has answers: "Aorist · 82%";
  - **Start**, which opens the run.
  - **No Greek list checked**: "Choose Greek lists to practise their verbs." and E4's "Choose lists" button, which opens New words from (0130). There is no Start.
  - **Without the Greek download** (0237): "Download Greek to practise conjugation." and a Download button instead of Start. Cards and progress stay.
- **Practise** on the Definition screen: a button under a Greek verb's conjugation table (#144) starts a drill of that verb at once (A single verb, below). Noun and adjective tables have no button. When Greek is not a learned language, Practise first asks "Learn Greek via English?" (E4's alert with Greek's default pair; a Russian UI asks for the limited Greek via Russian, with its warning), as Learn does (0131). Yes adds the pair and starts the drill; No cancels it (kyukhin, 2026-11-04).

### A question (#168)

```
γράφω
to write
Aorist ⓘ
εγώ

[ θα γράψω ]  [ έγραψα ]
[ γράφω ]     [ έγραψαν ]
```

- **The verb**, as grammar books cite it: its present εγώ form (γράφω; έρχομαι for a verb with passive forms only; πρέπει for an impersonal verb; υπάρχει for a list word given in the third person, #330), with its translation in the meanings language of Greek's pair (0131, "Languages and pairs"; kyukhin, 2026-11-04): the list's translation when it is in that language ("to write"), else the verb's first sense in the pair's dictionary (0131, Meanings), also for a verb opened from the Definition screen. Both Greek pairs of 2.0 have English meanings: Greek via English, and the limited Greek via Russian (kyukhin, 2026-11-04: its drill translations stay English). So the drill reads exactly as before.
- **The tense line**: the form's name, the tense ("Aorist", "Subjunctive: simple form", "Imperative: continuous form"); then "passive" for the passive of a verb with both voices ("Present · passive", εγώ → γράφομαι); then an ⓘ button (#329).
- **The person** has its own line below (#329, kyukhin 2026-11-14): the Greek pronoun, εγώ … αυτοί, as in the tables, in the headline font and the accent colour.
- **ⓘ** (#329) opens a popover, also on iPhone, pointing at the button: one or two sentences on what the form is for, then one Greek example and its translation in the UI language (none in a Greek UI, where the example is already in the UI language). No table. Each tense has two examples with different verbs; the popover shows the first one with no form of the asked verb: a word of the example (lowercased, without punctuation, in NFC) counts when it is the last word of any form of the verb, in any tense, voice or person the drill knows, an impersonal verb's other persons too (έγραψα; γράψει of έχω γράψει, so the auxiliary έχω does not count). When both have one, the popover shows the explanation alone. Over the three Greek lists' verbs at tenses up to B2, every asked tense has an example (measured 2026-11-15). The time the popover is open does not count in the answer's `duration_ms`.
- **A verb with passive forms only** (έρχομαι, κάθομαι, ντύνομαι) carries a small "passive" note (kyukhin, 2026-11-04), below the person since #329, in a smaller secondary style.
- **Four options**: the right form and three other real forms of the same verb (Options, below). Exactly one is right.
- **Speak words** (#331, kyukhin 2026-11-15): with Speak words on (0131, Settings), the verb is spoken in the Greek voice as the question appears, as the prompt cites it (γράφω, έρχομαι, πρέπει), never the tense line or the options. The next question, the summary, closing the run and leaving its screen stop it; nothing is spoken with VoiceOver running or without a Greek voice (0131, Exercises).
- **Feedback** is E4's (#159): a wrong choice turns red with a cross, and the right option always turns green with a check mark. A haptic tap and a sound play, as the settings allow (0131, Sounds; the drill never plays Lesson complete, which is the daily lesson's; it plays Daily goal reached when its answers fill the ring). The bar reads "Right!" or "Right answer: έγραψα". After a wrong choice it adds the form chosen with its tense and person, as the tense line writes them: "You chose: γράψαμε · Aorist · εμείς" (#299, kyukhin 2026-11-10); a form that fills several cells is named by the cell the option was taken from (its own entry in `optionSlots`), not the first cell in tense order.
- **Then the whole tense by person** appears in the bar above Continue: every person of that tense with all its forms (γράφτηκα / γράφηκα), with the asked person highlighted. An impersonal verb shows its αυτός row only (#330).
- **Then an example** (#364, kyukhin 2026-11-22): under the tense table, after a right and after a wrong answer, one sentence with exactly the asked form, the form in bold and the accent colour:

  ```
  Right!
  εσύ    κάνε / κάμε
  εσείς  κάντε
  Κάνε αυτό που μπορείς!
  Do what you can.
  glavkos, Hybrid · Tatoeba
  ```

  - It is the asked cell's sentence, never the chosen option's. A compound form is highlighted whole, with any clitics between: **θα σου γράψω**.
  - Its translation is in the via language of Greek's pair, as in learning (0134, "Translation in learning"): Greek via English shows the English one; the limited Greek via Russian shows Russian when the sentence has it, else English.
  - The byline names the source as on the Definition screen: the Tatoeba authors, "Wiktionary" or "LibreDict, generated" (0134, "Drill examples").
  - **No sentence, no change**: a cell without one shows the panel as before, with no gap and no placeholder. So does a Greek pack from before #364, until it is updated (0237).
  - The sentence is not spoken, and its time is not the answer's: the answer's time ends at the tap, as before.
  - Which cells have a sentence, and from where, is 0134's "Drill examples". In 2.0 every cell of the A1 and A2 verbs at tenses up to A2 gets one; their B1 and B2 tenses and the B1 verbs come in 2.1 (kyukhin, 2026-11-22).

### A session (#168, #169)

- 15 questions on the checked lists' verbs, in the tenses up to the drill's level.
- Due (verb, tense) cards come first, then new ones, until there are 15. Weaker tenses come more often (Planner, below).
- New verbs come by list (Greek A1 first, when checked), then by frequency, so a drill on Greek A1 starts with είμαι, έχω, κάνω, λέω, μπορώ, ξέρω and θέλω.
- Cards of verbs or tenses outside the current choice (a list unchecked, tenses lowered back) are kept, and they are asked again once the choice includes them.
- The person is picked at random from the persons the tense has. An impersonal verb is asked in αυτός only.
- The same verb is not asked twice in a row while another one can be.
- A wrong answer comes back once at the end, with another person, as one of the 15.
- The run can be closed at any time. Answers given so far are kept.
- **Summary** (E4's run summary): questions, right answers in %, time and the daily goal (E10), plus this run by tense: "Aorist · 4 of 5".

### A single verb: Practise (#168)

- Any Greek verb with a table can be practised, whether or not it is in a checked list.
- The verb is drilled in the drill's tenses ("Tenses up to", or A1 when no Greek list is checked). If the verb has no question at that level, the drill uses the first level that has one: έρχομαι at A1 starts at A2.
- Up to 15 questions. The verb's tenses take turns, weaker first, and each question asks a person not yet asked in this run. A verb with fewer questions gives a shorter run: πρέπει at A1 has 2 (θα πρέπει, να πρέπει).
- Practise uses the same cards, log and summary as the drill.
- When Greek is not a learned language, Practise first shows E4's alert for Greek's default pair, "Learn Greek via English?" ("Learn Greek via Russian?" with its warning in a Russian UI) (0131, "Learn on the Definition screen"):
  - Yes adds that pair as Learn does (`learning_languages`, `learning_via`; its My words are enrolled; the Greek pack is already installed, since the table shows), then starts the drill;
  - No cancels the drill: no question, no card, and the languages are unchanged.

### Levels (#167)

The levels follow the ΚΕΓ syllabus (kyukhin, 2026-10-22), as #167 details it. A level here is a **tense level**: each level adds tenses, and the drill asks every tense up to its level. The verbs do not depend on it: they are the checked lists' verbs (below).

| Tense (example forms) | Main voice | Passive of a verb with both voices |
|---|---|---|
| Present (γράφω) | A1 | A2 (γράφομαι) |
| Aorist (έγραψα), Future: simple form (θα γράψω), Subjunctive: simple form (να γράψω), Imperative: simple form (γράψε) | A1 | B2 (γράφτηκα, θα γραφτώ, να γραφτώ, γράψου) |
| Imperfect (έγραφα) | B1 | B2 (γραφόμουν) |
| Future: continuous form (θα γράφω), Subjunctive: continuous form (να γράφω) | B1 | B1 (θα γράφομαι, να γράφομαι) |
| Imperative: continuous form (γράφε) | B1 | B2 (γράφεστε) |
| Perfect (έχω γράψει), Pluperfect (είχα γράψει), Future perfect (θα έχω γράψει) | B2 | B2 (έχω γραφτεί) |

- **Main voice**: the active voice, or the passive for a verb with passive forms only (έρχομαι, κάθομαι, θυμάμαι; ντύνομαι from a list). A1 is active only (#167), so these verbs start at A2 with all their A1 tenses (ήρθα, θα έρθω, έλα) and then follow the main-voice column. Their questions carry the "passive" note (kyukhin, 2026-11-04). With tenses up to A1 they are not asked yet.
- **Verbs** (kyukhin, 2026-11-04): the verbs of the checked built-in Greek lists that have a conjugation table. Unchecked lists give none: Greek A2 alone gives only A2 verbs, in the A1 and A2 tenses; Greek A1 and A2 give both lists' verbs. Measured per list (a verb shared by two lists counts in the lower one):

  | List | Verbs | With passive forms only |
  |---|---|---|
  | Greek A1 | 189 | 19 |
  | Greek A2 | 64 | 4 |
  | Greek B1 | 274 | 60 |
  | All three | 527 | 83 |

- **Tenses**: up to the highest checked level (Greek A1 → A1, A2 → A2, B1 → B1). The "Tenses up to" setting can raise them, up to B2, for the same verbs. There is no B2 list.
- **Gaps**: a verb is asked only the tenses its table has: είμαι has no aorist, and έχω has no aorist and no simple forms. A verb without simple forms takes θα and να + its present as its Future and simple Subjunctive (θα είμαι, να έχω), from A1; its continuous Future and Subjunctive are not asked separately (kyukhin, 2026-11-04). There are 12 such list verbs (measured): είμαι, έχω, ξέρω, περιμένω and others.
- **Impersonal verbs** (every form in the third person: πρέπει, πρόκειται) are asked in αυτός only (#167). Their other persons are never offered or shown either (#330): θα πρέπει gets πρέπει, να πρέπει and έπρεπε, never θα πρέπουν, and the tense after the answer is the αυτός row.
- **A verb the lists give only in the third person** (#330, kyukhin 2026-11-14) is impersonal too: its list word, without a parenthesised part, punctuation or case, is the present αυτός of the main voice of the verb it reaches (επιτρέπεται "it is allowed"). It is cited as listed, with the list's translation, and asked, offered and shown in αυτός only. Its card word stays the verb's.
- **A verb the lists also give in its plain form** (kyukhin, 2026-11-15) is an ordinary verb, in every person, with the citation, translation and level of that entry. The plain form is the verb's citation or another form of its present εγώ, ignoring brackets, punctuation and case (υπάρχω; προτιμώ for προτιμάω). So υπάρχω is "to exist" from Greek A1 though υπάρχει "there is" is listed first, and πειράζω is "to mess around with, to harm, to tease" from Greek B1, not A2's πειράζει; αρέσω, βρέχω and αστράφτω stay whole. A verb listed by its passive εγώ whose active has only the third person is that passive, in every person: νοιάζομαι "to care", not the active's νοιάζει. Measured over the three lists on 2026-11-15, the impersonal verbs are πρέπει, επιτρέπεται, χιονίζει and πρόκειται. Practise on Definition has no list word: υπάρχω is a whole verb there.
- **A list word of another part of speech is never a verb** (#330, kyukhin 2026-11-15): a word that is a lemma of the pack in another part of speech and no verb lemma does not take a verb's table, even when it spells one of its forms. The lists carry no part of speech, so the pack's `lemma` table decides. Measured over the three lists on 2026-11-15, six words left: Ορίστε! (ορίζω), φορά (φοράω's αυτός), χώρα (χωράω), κρέμα (κρεμάω), γέννα (γεννάω), πείνα (πεινάω). So ορίζω and κρεμάω leave the drill, φοράω is drilled as "to wear" and χωράω from Greek B1 as "to fit"; γεννάω and πεινάω are unchanged, being list words of their own first.
- **The cited form is never asked**: the present εγώ of the main voice is the prompt itself (γράφω → γράφω). For an impersonal verb that form is the present αυτός.
- Participles are not drilled in 2.0 (kyukhin, 2026-11-04). The tables keep showing them.
- Forms tagged rare, archaic or dated are never asked or offered, as in the tables.

Each verb's questions by tense level:

| Verb | A1 | A2 adds | B1 adds | B2 adds |
|---|---|---|---|---|
| γράφω | Present (not εγώ), Aorist, Future: simple form, Subjunctive: simple form, Imperative: simple form | Present · passive | Imperfect, Future: continuous form, Subjunctive: continuous form, Imperative: continuous form; θα and να + the passive present | The passive's past and simple tenses; Perfect, Pluperfect, Future perfect in both voices |
| είμαι | Present (not εγώ), Future: simple form (θα είμαι), Subjunctive: simple form (να είμαι) | — | Imperfect (ήμουν) | — (no aorist infinitive, so no perfect) |
| έρχομαι (with the "passive" note) | — | Present (not εγώ), ήρθα, θα έρθω, να έρθω, έλα | ερχόμουν, θα έρχομαι, να έρχομαι, έρχεστε | έχω έρθει, είχα έρθει, θα έχω έρθει |
| πάω (Practise) | The tenses of πηγαίνω, whose table πάω shows (#144), asked as πηγαίνω | as πηγαίνω | as πηγαίνω | as πηγαίνω |
| πρέπει | αυτός: θα πρέπει, να πρέπει | — | έπρεπε | — |

### Options (#167)

- The right option is the first form of the asked cell, in table order. Every other form of that cell is also right, so it is never offered: of γράφτηκα / γράφηκα, only γράφτηκα appears.
- Three distractors, all real forms of the same verb (kyukhin, 2026-10-22: the same person in another tense, the same tense in another person):
  1. a form of the same person in another tense or voice of the level (for έγραψα: γράφω, θα γράψω, να γράψω);
  2. a form of the same tense in another person (έγραψες, έγραψε, γράψαμε); none for an impersonal verb, which has only αυτός (#330);
  3. the third from either group;
  4. when these run short: other tenses and persons of the level, then the verb's other tenses of the asked voice outside the level (πρέπει at A1: έπρεπε).
- Never offered:
  - a form of the other voice at A1;
  - a form that is also right. γραφόμαστε is both the present and the imperfect εμείς of γράφομαι, so neither question offers it as a wrong option;
  - two options that read alike once accents are removed (0131's rule).
- A question that cannot get three distractors is never asked. In the prototype (without the θα/να fallback), groups 1 and 2 alone gave three for every A1 question of the A1 verbs except πρέπει's.
- The options are shuffled with the run's generator (`-learningSeed` fixes the order, 0131).

### Spaced repetition (#169)

- One card per (verb, tense, voice): γράφω's aorist is one card, and γράφω's passive present is another. The person is picked again for every question.
- The card climbs E4's ladder of 1, 3, 7, 14, 30 and 90 days by the same rules (0131):
  - a right answer on a due card moves it one rung up;
  - a wrong answer sends it back to learning: it is asked once more in this run, and it is due today;
  - a right answer on a card that is not due (Practise, or a repeat in a single-verb run) is logged, and the card does not change.
- A card starts on its first answer. Nothing is created ahead, so a level of 500 verbs adds no backlog.
- Drill cards never appear in the daily session, the Recognition and Production trainers, match the pairs or mistakes practice. They never change a word's learning: γράφω drilled is still a new word for the session, and Stop learning on γράφω leaves its drill cards alone.
- Every question counts toward the daily goal and the streak (kyukhin, 2026-11-03, 0166).

### Statistics (E10, #164)

With Greek chosen, Statistics shows the Conjugation block once the drill has answers (0166). The block holds accuracy by tense over the last 30 days, both voices together and in the tables' order, and the 10 hardest verbs. The drill only writes the log rows E10 reads, and supplies the tense names and order.

### iPhone, iPad, Arabic, VoiceOver

- The run uses E4's layout: full screen, a close button and the progress "Question 4 of 15". On iPad and in landscape the content is at most 600 pt wide and centred. The content scrolls when the tense table does not fit (small iPhones, large text).
- Arabic mirrors the screens. The tense table's pronoun column is on the right, and Greek forms read left to right (#144). Composed lines start with U+200F and wrap Greek in FSI…PDI (#119). The answer panel's example (#364) mirrors as on the Definition screen. The Greek sentence keeps its left-to-right order, and the byline starts with U+200F with the names isolated (0134).
- VoiceOver:
  - reads the prompt as "γράφω, to write. Aorist, εγώ", with the Greek parts in the Greek voice, and "έρχομαι, to come. Aorist, εγώ, passive" for a verb with passive forms only. Since #329 the form's name, the person and the note are three lines, still one VoiceOver stop ("Aorist, εγώ", "Aorist, εγώ, passive"), and the ⓘ, "About Aorist", is the next stop;
  - reads each option as a button, and announces the result as E4 does;
  - reads each row of the tense table as "εγώ, έγραψα", and the asked row as selected;
  - reads the example (#364) as one element after the table, as on the Definition screen: the sentence in the Greek voice, the translation in its own voice, then the byline ("From Tatoeba: glavkos and Hybrid", "Generated by LibreDict"). The answer's announcement does not change.

### Decisions

- 2026-10-22 (kyukhin, #132): multiple choice from 4 real forms of the same verb (the same person in another tense, the same tense in another person).
- 2026-10-22 (kyukhin, #132): tenses by level follow the ΚΕΓ exam syllabus: aorist at A1, imperfect at B1, perfect tenses at B2. #167 details the other tenses (Levels).
- 2026-10-22 (kyukhin, #132): after each answer the whole tense by person is shown.
- kyukhin (epic #132): the declension drill for nouns and adjectives (#170) moves to v2.1.0.
- 2026-10-22 (kyukhin, 0131): fixed intervals; the app grades the answers. The drill reuses both.
- 2026-11-03 (kyukhin, 0131): learning is per language. The drill is Greek's and shows in Trainers only when Greek is chosen.
- 2026-11-03 (kyukhin, 0166, Open question 4): every drill question counts toward the daily goal.
- 2026-11-03 (kyukhin, 0131, Open question 6): a learning day starts at 4 AM. Drill cards and log rows use E4's days.
- 2026-11-03 (kyukhin, 0237): the Greek forms and lists come with the Greek pack, so the drill needs it.
- 2026-11-04 (kyukhin): E3, E4, E10 and #237 are done by 11-20, code is complete on 11-27 and the app goes to Apple on 12-04. Two UI and two data streams.
- 2026-11-04 (kyukhin, Open question 1): a verb with passive forms only enters at A2 with every A1 tense in its own voice (έρχομαι, ήρθα, θα έρθω, να έρθω, έλα), then follows the main-voice schedule. Its questions carry a small "passive" note next to the tense.
- 2026-11-04 (kyukhin, Open question 2): the drill follows the lists checked on New words from (0130): its verbs are the verbs of the checked Greek lists only, and its tenses are every tense up to the highest checked level (ΚΕΓ syllabus). A1 + A2 checked: verbs of both lists, in the A1 and A2 tenses; A2 alone: only A2 verbs, in the A1 and A2 tenses. No cumulative verb levels.
- 2026-11-04 (kyukhin, Open question 3): the drill has a setting "Tenses up to: A1 / A2 / B1 / B2". It defaults to the highest checked level and can be raised, up to B2 (perfect tenses, the passive past), for the same checked verbs.
- 2026-11-04 (kyukhin, Open question 4): participles stay out of the drill in 2.0; the tables keep showing them. They may come in 2.1.0 with #170.
- 2026-11-04 (kyukhin, Open question 5): verbs without a dependent stem (είμαι, έχω, ξέρω, περιμένω and 8 more) take θα and να + the present as their Future and simple Subjunctive in the drill (θα είμαι, να έχω), from A1, and are not asked the continuous ones separately. The tables stay as approved; aligning them is a small follow-up.
- 2026-11-04 (kyukhin, Open question 6): Practise on a verb asks "Learn Greek?" first when Greek is not a learned language, as Learn does; No cancels the drill.
- 2026-11-04 (kyukhin): learning is chosen as a language pair (0131). Applied here: the verb's translation is in Greek's via language, and the alert reads "Learn Greek via English?". Drill cards, like word cards, belong to Greek, whatever the via. 2.0 has no Greek pair other than Greek via English.
- 2026-11-04 (kyukhin): Greek via Russian is offered as a limited pair (0131): grammar and notes in Russian, word meanings in English. Applied here: the drill's verb translations stay in English for it (the pair's meanings language), and a Russian UI's Practise asks "Learn Greek via Russian?" with the pair's warning. The drill's own texts are UI strings, in the UI language as always.
- 2026-11-04 (kyukhin): nothing is cut from 2.0 if it runs late: the release date moves instead (0131).
- 2026-11-10 (kyukhin, #295): the conjugation drill moves out of Trainers into the Grammar section of Greek's tab.
- 2026-11-10 (kyukhin, #299): a wrong choice also shows the chosen form with its person and tense.
- 2026-11-22 (kyukhin, #364): after an answer, right or wrong, the panel shows a real sentence with exactly the asked form under the table: the form in bold, the translation in the via language as in learning, the byline as on the Definition screen. No sentence, no change. In 2.0, as kyukhin's exception to the release/2.0 freeze: it lands on master, then is cherry-picked into release/2.0.
- 2026-11-22 (kyukhin, 0134's Open questions 7 to 12): in 2.0 the A1 and A2 verbs at tenses up to A2 get a sentence for every cell; a homograph of another reading needs a model-checked reading; the sentences LibreDict adds carry English and Russian translations only, the drill's two vias. No date moves: build 11 and the App Store submission stay on 2026-11-26.

Design choices of this spec, for review:
- One card per (verb, tense, voice) on E4's tables and ladder. No migration and no new static table.
- A card starts on its first answer. Due cards come first. Tense weights come from the last 30 days.
- The repeat of a wrong answer is one of the 15 questions, not a 16th.
- The cited form (present εγώ) is never asked.
- The right option is the cell's first form. The other right forms are never offered.
- A list word that is the passive of another verb's table (ντύνομαι in ντύνω's) is drilled in the passive only, under its own word. An active alternative (πάω, βρομώ) drills the table's verb (πηγαίνω, βρομάω).
- The drill does not need learned words: it takes the checked lists' verbs, by list and frequency. Imported Greek lists do not feed it, even when checked.
- "Tenses up to" offers only the highest checked level and above, since lower tenses are always included.

### Out of scope

The declension drill (#170, 2.1.0). Typed answers in the drill. Participles (Decisions; maybe 2.1.0 with #170). Drills for other languages. Choosing tenses one by one, or tenses below the highest checked level. Verbs of imported lists, even when checked (Practise still works on any Greek verb with a table). A badge or a due count on the Conjugation row. Hand-written forms for Wiktionary gaps (as in #144). Showing θα είμαι under Future in the tables (a follow-up, Decisions).

## Design

### Depends on

| Spec | What E5 uses | Notes |
|---|---|---|
| 0136 (#141, #144) | `ParadigmCell`, `LemmaParadigm`, `ParadigmLayout.verbSlot`, `voiceForms`, `mainVoice`, `VoiceForms` (its generated θα, να, έχω and είχα forms), `Person` (pronouns, raw values `1sg`…`3pl`), the `FormLabel` keys; `DatabaseService.inflection(for:)` and its link rule (`linkedLemmasSQL`, `chooseLink`, `linkFits`) | E5 adds no grammar of its own: every form it asks is a form the tables show, except the θα/να + present fallback (Decisions) |
| 0130 (#151, #152, #154) | `wordlist_item` of series `ky-ell` (`term`, `headword`, `translation`, `level_ord`, `rank`, `seq`), `WordKey`, `SettingsService.learningListIDs` (`learning_lists`, the lists checked on New words from), `NewWordsFromView`, the level names `wordLists.level.*` | kyukhin's lists have no part of speech, so verbs are found through `ell.lemma` (pos `verb`). There is no B2 list: B2 is a tense level only |
| 0131 (#157, #158, #159) | `learn_card` with kind `conjugation` and facet `<tense>.<voice>` ("For E5"), `recordAnswer`, `FixedLadder`, `LearningClock`, `dueCards(kinds:)`, `AnswerChecker.fold`, `Gloss.short`, the seeded generator, `FeedbackPlayer`, the run views and `RunSummaryView`, the Trainers section and "Choose lists", the "Learn %@ via %@?" alert and `LearningLanguageService.learn(language:)`, `LearningPairs.via` and `meanings(of:lang:meaningsLang:sourceOrder:)` for the verb's translation, `-learningSeed`, `-learningAnswerHints`, `-learningFixture`, `-learningLanguages`, `-learningLists` | Four requests, below |
| 0166 (#163, #164) | `tenseAccuracy(since:lang:)`, `Accuracy.byTense`, `reviewRows(run:)`, the goal write in `recordAnswer`, the Conjugation block | E5 supplies `ConjugationTense` (titles, order) |
| 0237 (T1, T2, T3) | The Greek pack attached as `ell` (forms and lists), `DictionarySchemas.listsSchema(for:)`, `PackService.installedPacks()`, `PackService.install(_:)`, `PackStatusModel`, `-installPacks`, `PackFixtures` | Without the pack, `ell` is the empty stub: the pool is empty and the drill offers the download |

**Requests to E4 and E10.** Each is small. #157, #158, #163 or #165 does it if the ticket is still open when this spec is approved; otherwise #169 does it.
1. **`recordAnswer` for kind `conjugation`**: it inserts the card when it is missing (step 0, `due_day` today) before reading it, and it never touches `learn_word` (`introduced_day` stays as it is, `introduced` = 0). Otherwise a drill answer on γράφω, a word not started yet, would mark it as started: the word would leave the new-word pool, and its word cards would never be asked.
2. **Word cards only** (`kind IN ('recognition', 'production')`) in:
   - `stopLearning` and `learnWord` (pause and resume);
   - `mistakeCards`;
   - `learningState(of:)` and `WordStatus` (the Learn button, #165);
   - E10's `wordStates(lang:)` and `ListProgress`, so a drilled verb does not count as "learning";
   - `errorCount`, for #165's mistakes.

   `dueCards` already takes `kinds`, and E4's planners pass the word kinds.
3. **Reusable run views**: #159's option button, feedback bar and progress bar, and `RunSummaryView`, are views the drill can compose, not private parts of `ExerciseRunView`. The summary hides rows a run has none of (new and reviewed words).
4. **Tense names**: E10's Conjugation block reads the tense titles and their order from `ConjugationTense`. 0166 calls this type `ConjugationFacet`; here `ConjugationFacet` is the tense plus the voice. If #164 merges before #167, #164 adds `ConjugationTense` as defined here, and #167 builds on it.

Where this spec differs from the others:
- 0131 "For E5" keys a card by "the verb lemma". This spec does too, except for a passive link: its card word is the list's own word (ντύνομαι, not ντύνω), as the prompt shows it.
- 0130 has no B2 Greek list, so B2 exists only in "Tenses up to"; and the Greek items carry no part of speech.
- #167 says "verbs of the same level". kyukhin's decision of 2026-11-04 replaces it: the checked lists choose the verbs, the highest checked level (or the setting) the tenses.

### Data

- **No migration**: 0131's tables hold the drill ("For E5"). 0129's example name `132-1-conjugation` stays unused.
- **No static table**: the pool is read at runtime from `ell.wordlist_item`, `ell.lemma` and `ell.paradigm`, so the pack format does not change (0237's format rule).
- **Cards**: `learn_card (lang 'ell', word, kind 'conjugation', facet)`.
  - `word` is the drilled verb's word (Verbs, below), in NFC, a `WordKey` word.
  - `facet` is `ConjugationFacet.rawValue`, `<tense>.<voice>`: `aorist.active`, `present.passive`.
- **Log**: `learn_review` rows with:
  - `kind` `conjugation`, `exercise` `conjugation`, `mode` `drill` and the card's `facet`;
  - `detail`: the person asked, `1sg`…`3pl`;
  - `outcome`: `right` or `wrong` (a choice has no `accent`);
  - `introduced` 0, `step_before`, `step_after` and `run_id`;
  - `duration_ms`, from the question appearing to the answer, capped at 60 s (0131), less the time the ⓘ popover was open (#329).
- **Preference** `learning_drill_tenses` ("Tenses up to"): `A1`, `A2`, `B1` or `B2`, through a `SettingsService.learningDrillTenses` accessor on the `KeyValueStore` seam (0131's settings keys). Rules:
  - absent: the tense level is the highest checked Greek list's level, or A1 when none is checked;
  - a stored value below the highest checked level is ignored, because the setting only raises. Checking Greek B1 after storing A2 gives B1;
  - `-resetData` clears it with the other `learning_*` keys;
  - #73 (iCloud) syncs it with the other preferences.
- **Size**: about 120 bytes per answer (0131). The cards are a few hundred rows in practice; the maximum is 527 verbs × 12 tenses × 2 voices.

### Tenses and levels (#167)

These are pure types in `Models/Learning.swift`.

- **`enum ConjugationTense: String, CaseIterable`**: `present`, `imperfect`, `aorist`, `future`, `imperativeContinuous`, `imperativeSimple`, `futureContinuous`, `perfect`, `pluperfect`, `futurePerfect`, `subjunctiveContinuous`, `subjunctiveSimple`.
  - `allCases` is in the tables' order (#144). E10's block and the Conjugation screen use it.
  - The raw values are ASCII with no dot, so E10's `substr(facet, 1, instr(facet, '.') - 1)` reads them.
  - `title(locale:)`: the `FormLabel` titles for the six tenses named by one word ("Present", "Aorist", "Future perfect"); the six others from `drill.tense.*`, in kyukhin's terms shared with 0133 (2026-11-07): "Future: simple form", "Future: continuous form", "Subjunctive: simple form", "Subjunctive: continuous form", "Imperative: simple form", "Imperative: continuous form".
  - `forms(_ voice: VoiceForms, _ person: Person) -> [String]`:
    - present, imperfect, aorist and the two imperatives read the cells;
    - the other tenses are `VoiceForms`' generated forms: future = θα + dependent, futureContinuous = θα + present, the subjunctives = να + dependent or present, and perfect, pluperfect and futurePerfect come from the aorist infinitive.
    - **Fallback** for a voice with present forms and no dependent form: future and subjunctiveSimple take θα or να + the present, and futureContinuous and subjunctiveContinuous give nothing (kyukhin, 2026-11-04).
  - `persons`: 2sg and 2pl for the imperatives, all six for the others.
- **`struct ConjugationFacet: Hashable`** holds a tense and a `ParadigmLayout.Voice`. Its `rawValue` is `"\(tense.rawValue).\(voice.rawValue)"`, and it has `init?(rawValue:)`.
- **`enum DrillLevel: String, CaseIterable, Comparable`**: `a1 = "A1"`, `a2`, `b1`, `b2`, a tense level. It never selects verbs.
- **`DrillLevel.facets(mainVoice:hasPassive:)`** returns the level's facets, every tense up to it, from the table in Levels:
  - a verb whose main voice is active gets at A1 present, aorist, future, subjunctiveSimple and imperativeSimple; B1 adds imperfect, futureContinuous, subjunctiveContinuous and imperativeContinuous; B2 adds perfect, pluperfect and futurePerfect;
  - a verb whose main voice is passive (passive forms only) gets nothing at A1, the A1 set from A2 on, then the same additions;
  - the passive of a verb whose main voice is active adds present at A2, futureContinuous and subjunctiveContinuous at B1, and the other nine at B2.
- **`DrillScope`** (pure) turns the preferences into what the drill asks:
  - `greekLists(checked:) -> [WordListID]`: `ky-ell-a1`, `-a2` and `-b1` among `learning_lists`, in level order. Imported lists are left out;
  - `floor(checked:) -> DrillLevel`: the highest of those lists' levels (A1, A2, B1), or A1 when none is checked;
  - `tenseLevel(checked:stored:) -> DrillLevel`: `max(stored ?? floor, floor)`;
  - `offeredLevels(checked:) -> [DrillLevel]`: `floor` … B2, the segments of "Tenses up to".

### Verbs (#167)

`struct DrillVerb` has these fields:
- `word`: the card's word;
- `citation`: the word the prompt shows;
- `translation`: in the meanings language of Greek's pair (`LearningPair.meanings`, 0131: English for Greek via English and for the limited Greek via Russian), by 0131's meaning rule: the list's translation when the list's `translation_lang` is that language, else the first sense of the verb in the pair's dictionaries;
- `listLevel: Int?`: 1–3, the list it came from; nil from the Definition screen;
- `rank: Int?` and `seq: Int`;
- `mainVoice: ParadigmLayout.Voice`. When it is the passive (passive forms only), every question shows the "passive" note;
- `voices: [Voice: VoiceForms]`: only the voices drilled;
- `isImpersonal`.

**`DrillVerb.make(word:paradigm:translation:listLevel:rank:seq:listTerm:) -> DrillVerb?`** is pure. It takes a word and the `LemmaParadigm` that the Definition rule gives that word (#144):
- **Own table** (`isLinked` false): `word` is the lemma. The voices are the main voice (`ParadigmLayout.mainVoice`), plus the passive when the main voice is active and the passive has a present.
- **Linked table** (`isLinked`: the word is a form or an alternative of another verb, #144): the voices are those in which the word is a finite cell of the table.
  - Passive only (ντύνομαι in ντύνω's table, σηκώνομαι, ετοιμάζομαι: 44 list verbs, measured): `word` is the word itself, and the passive is its main voice.
  - Active (πάω in πηγαίνω's, βρομώ in βρομάω's, πειράζει in πειράζω's): `word` is the table's lemma, as if the lemma had been given. Two list words with one table are one verb.
  - Neither (participles listed as verbs, such as συνηθισμένος: 15 list words): no verb.
- `citation` is the first form of the main voice's present εγώ (γράφω, έρχομαι, πηγαίνω). An impersonal verb uses its present αυτός (πρέπει), and a verb with neither uses the lemma.
- `isImpersonal`: every finite cell of the main voice is in the third person, or `listTerm` (the list item's `term`) gives the main voice's present αυτός (`DrillVerb.thirdPerson(listTerm:_:)`, #330), which is then the `citation`. A `listTerm` that gives the passive εγώ of a verb whose active has only the third person makes the passive the main voice (νοιάζομαι). Only αυτός is asked, and the verb's `cells` hold only its αυτός cells, so the options and the tense rows of its questions never use another person.
- The result is nil when no level has a question for the verb (Questions, below).

**Pool**: `DatabaseService.drillVerbs(lists: [WordListID], meaningsLang: String) -> [DrillVerb]` (#167) takes `DrillScope.greekLists`, the checked Greek lists, and the meanings language of Greek's pair. With none it returns no verbs and reads nothing. Otherwise it does it in one read:
1. Read the list items:
   - `SELECT term, headword, translation, level_ord, rank, seq FROM <ell lists>.wordlist_item WHERE series = 'ky-ell' AND level_ord IN (…)`, on the primary-key prefix, with the checked lists' `level_ord` (0130: each list is one level of the series), and the series' `wordlist.translation_lang`;
   - a translation not in `meaningsLang` is dropped, and the verb's translation comes from 0131's `meanings(of:lang:meaningsLang:sourceOrder:)` instead (never in 2.0, where both Greek pairs have English meanings and kyukhin's translations are English);
   - look them up in `ell.lemma` on `lang = 'ell'`, `word = COALESCE(headword, term)` and `pos = 'verb'`, through its unique index; a word with no verb lemma is kept for step 2, since 0136 links it to a verb's table (αγαπώ → αγαπάω, αρέσει → αρέσω), unless it is a lemma of another part of speech (`other_pos`, #330: φορά, a noun, never takes φοράω's table);
2. Get each word's table by the Definition's rule for a verb: its lemma's own cells, else its single link (`linkedLemmasSQL` with pos `verb`, then `chooseLink` and `linkFits`), as `inflection(for:)` does. A word with neither (a noun, an adverb, a participle listed as an adjective) is not a verb. About 60 list verbs need a link, at one primary-key query each.
3. Read the cells of every table in one query (`paradigm` with `lemma_id IN (…)`). Measured: 29,371 cells for 530 verbs in 16 ms on the Mac.
4. Run `DrillVerb.make` on each, with the item's `term` (#330), and merge duplicates by `word`: the first item in the verb's plain form wins (`DrillVerb.isPlainForm(listTerm:of:)`, kyukhin 2026-11-15), else the lowest level, then the best rank; the winning item's citation, translation, level and third person are kept.
5. Sort by list level, then `rank` (unranked last), then `seq`.

- The schema names come from `DictionarySchemas` (0237): `ell` for the forms and the lists. Until T2 merges, the forms are in `dict` and the lists wherever #152 puts them. Whichever of #167 and T2 merges second moves the names.
- The view model caches the pool per set of checked lists while the screen is open. Changing "Tenses up to" re-plans the same pool without reading it again. Target: the Conjugation screen is ready in under 300 ms with all three lists checked (527 verbs; iPhone 15 Pro simulator, iOS 17.5, median of 3, recorded by QA in History).

**From the Definition screen**: `DefinitionViewModel` already loads the entry's `LemmaParadigm` (#144). It keeps the paradigm and builds `drillVerb = DrillVerb.make(word: entry.word, paradigm:, translation:)`, the translation being the verb's meaning in the meanings language of Greek's pair (0131's `meanings`; the default pair's when Greek is not learned): the first of the pair's dictionaries in Dictionary Order that has the verb. So γράφω opened from El–En · WN reads "write" from El–En · FD when FD comes first, as in E4's exercises, where `Gloss.short` of the WN entry would read "read, say". One indexed read. The Practise button shows when `drillVerb` is not nil, whether or not the verb is in a checked list.

### Questions and options (#167)

`struct ConjugationQuestion` has these fields:
- `verb`, `facet`, `person`;
- `options: [String]` (4) and `rightIndex`;
- `rightForms: [String]`: every form of the asked cell;
- `tenseRows: [(Person, [String])]`: the whole tense, for the feedback.
- `optionSlots: [ConjugationQuestion.Slot]` (#299; `Slot` is a `Hashable` struct of `facet: ConjugationFacet` and `person: Person`): for each option, the cell it was taken from, which the builder knows (a distractor is a cell's first form, and its slot is that cell even when another cell holds the same form; a generated θα or να form is its generated cell's); the right option's is the question's. The feedback's "You chose" line writes the chosen option's slot as the tense line does (0131, Feedback).

**`ConjugationQuestionBuilder.build(verb:facet:person:level:rng:) -> ConjugationQuestion?`** is pure:
1. `rightForms` = `facet.tense.forms(voice, person)`. If it is empty, the result is nil.
2. Collect the candidates, each the first form of a cell:
   - A: the same person in another facet of the level;
   - B: the same facet in another person;
   - C: another facet of the level in another person;
   - D: the asked voice's other tenses outside the level, any person.
3. Drop a candidate that folds equal (`AnswerChecker.fold`, 0131) to any of `rightForms` or to an option already taken.
4. With `rng`, pick one candidate from A and one from B, and the third from A ∪ B. Fill any gap from C, then from D. With fewer than 3, the result is nil.
5. The options are the first of `rightForms` plus the three, shuffled with `rng`.

`level` is the tense level, `DrillScope.tenseLevel`. Practise raises it to the verb's first level with a question when it has none (έρχομαι at A1 → A2).

**`ConjugationQuestionBuilder.questions(verb:level:) -> [(ConjugationFacet, [Person])]`** lists the level's facets of the verb with the persons that build a question:
- without the cited cell (the main voice's present εγώ, or αυτός for an impersonal verb);
- with only αυτός for an impersonal verb.

The planner, the Conjugation screen's verb count and the Practise button all use it.

### Planner (#169)

`ConjugationPlanner` is pure and returns `[DrillItem]`, each a (verb, facet, person).

Its inputs are:
- the questions of the pool (the checked lists' verbs) at the tense level, or one verb's;
- Greek's conjugation cards (`CardState`);
- the 30-day accuracy by tense (E10's `tenseAccuracy(since:lang:)`);
- `today`, the length (15) and `rng`.

- **Weights**: `weight(t) = 1 + 4 × (1 − (right + 1) / (answers + 2))`, over the last 30 days of tense `t`, both voices together. A tense never answered weighs 3; 19 of 20 right weighs 1.36; 8 of 20 right weighs 3.36.
- **Drill** (`session`). For each of the 15 places:
  1. Pick the group: due cards (answered, `due_day ≤ today`) while any remain, else new pairs (a verb's facet with no card), else practice (answered and not due: the lowest step, then the oldest `last_day`, as in E4's trainers).
  2. Pick a tense among the group's tenses, at random by weight.
  3. Pick the item in that tense:
     - a due card: the earliest `due_day`, then the lowest step, then pool order;
     - a new pair: pool order (list, then frequency).

     The previous item's verb is skipped while another candidate exists.
  4. Pick a random person among the facet's persons.

  Each card is asked at most once. Cards outside the pool or the tense level are not candidates, and they are kept.
- **Single verb** (`verbRun`): the verb's (facet, person) questions, at most 15, each asked once. The planner goes round its facets, each round in weight order (a weighted shuffle), with one new person per facet.
- **Retry** (`afterWrong`): a wrong item comes back once, with another person when the facet has one. It takes the place of the last item not asked yet that is a new pair or practice. With none left it is not repeated: its card is due today, so the next drill starts with it.
- Each question is built just before it shows, so its options use the run's `rng` (0131).

### Answers and cards (#169)

- `ConjugationRunViewModel` writes each answer at once with 0131's `recordAnswer`:
  - `card`: `CardKey(WordKey(lang: "ell", word: verb.word), .conjugation, facet.rawValue)`;
  - `exercise`: `"conjugation"`, `mode`: `"drill"`;
  - `runID`, `outcome` and `durationMs`;
  - `detail`: `person.rawValue`;
  - `today` and `scheduler: FixedLadder()`.

  It then calls the same goal hook as E4's runs: the reminder is rescheduled when an answer reaches the goal (0131).
- `DatabaseService.cards(lang:kinds:) -> [CardState]` (#169, new, one indexed query) gives the planner every conjugation card.
- With requests 1 and 2 (Depends on), drill answers never touch words, and word features never touch drill cards.

### Screens (#168)

- **Learn tab**: on Greek's tab, the Grammar section (0133, #295) holds a "Conjugation" row (`learn_trainer_conjugation`, the id kept) with the tense level as its value, after the topics row. It pushes `ConjugationStartView`. Until #295 it sat in E4's Trainers section, in a section of its own below their footer while they were disabled; in Grammar, E4's "Learn a few words first" footer is the trainers' alone.
- **`ConjugationStartView`** (in `LearnView.swift`):
  - the verbs line: the checked Greek lists by name (E3's `wordLists.listTitle`) and the verb count;
  - "Tenses up to", a segmented `Picker` over `DrillScope.offeredLevels`. A change writes `learning_drill_tenses` and re-plans; on appear the view model re-reads `learning_lists`, so checking a list on New words from shows at once;
  - the tenses of that level, each with its `ConjugationTense.title` and its accuracy over the last 30 days;
  - Start, which presents `ConjugationRunView` in a `fullScreenCover`.
  - With no Greek list checked: `drill.noLists` and E4's "Choose lists" button, which pushes E3's `NewWordsFromView`. No picker and no Start.
  - Without a usable Greek pack (`PackService.installedPacks()`): `drill.needsGreek` and a Download button that calls `PackService.install(.ell)`, with E4's progress row (0237, "For E3 and E4"). This state wins over the one above.
  - Its view model is `ConjugationDrillViewModel`: the checked lists, the pool, the tense level, the accuracy and the pack state.
  - The setting lives on this screen only; Settings → Learning (#162) does not change.
- **`ConjugationRunView`** (in `ExerciseView.swift`):
  - E4's run shell (close button, progress, feedback bar, Continue) around `ConjugationQuestionView`: the verb, the translation, the tense line (`DrillText.formName`, `.headline`) with the ⓘ button, the person (`.headline`, accent colour) and four options. For a verb whose main voice is the passive, the person is followed by the "passive" note (`drill.passiveNote`, `.caption`, secondary colour). With VoiceOver on (`accessibilityVoiceOverEnabled`), the tense line's element reads `DrillText.promptLabel` ("Aorist, εγώ", "Aorist, εγώ, passive") and the person and the note are hidden from it, so the three lines are one stop; with VoiceOver off (UI tests, Voice Control) they are three elements, `drill_prompt_tense` ("Aorist"), `drill_prompt_person` and `drill_passive_note`;
  - ⓘ (#329, `info.circle`, a 44 pt target) presents `TenseInfoView` in a `.popover` with `.presentationCompactAdaptation(.popover)`, with the run's locale and layout direction. Its texts come from `DrillText.tenseInfo(_:verb:locale:)`: `drill.tenseInfo.<tense>`, then `ConjugationTense.examples[i]` (Greek runs; in Arabic after U+200F and isolated, FSI…PDI) and `drill.tenseInfo.<tense>.example<i+1>`, left out in a Greek UI. `ConjugationTense.exampleIndex(avoiding:)` picks the example over every person of the drilled voices (`ConjugationTense.forms` of `DrillVerb.voices`, as `cells` are built), also for an impersonal verb, whose `cells` hold αυτός only (pure, `firstExample(_:avoiding:)`). The view reports the popover opening and closing to `ConjugationRunViewModel.tenseInfo(isOpen:)`, which moves the question's start on by the time it was open;
  - #331: `ConjugationRunViewModel.show()` speaks each question's `verb.citation` through 0131's `QuestionSpeaker` and keeps it in `spokenWord`, the verb's accessibility value (`spokenWord` of `ConjugationQuestionView`); the view's `.onDisappear` calls `leave()`, which stops it;
  - after the answer, `ConjugationTenseView`: a `Grid` of pronouns and forms, with the asked row in bold on the accent background. A cell's forms are joined with " / " and wrapped by #144's narrow-screen rule;
  - at the end, `RunSummaryView` with a "By tense" block: `Accuracy.byTense` over the run's rows (`reviewRows(run:)`, 0166).
- **Definition**: under `InflectionTableView`, for a conjugation table whose `drillVerb` is not nil, a bordered "Practise" button (`drill_practise_button`). `InflectionTableView` does not change. `DefinitionViewModel.practise()`:
  - if `ell` is in `learning_languages`, it starts the run;
  - otherwise it raises E4's "Learn %@ via %@?" alert with Greek's default pair, the same one the Learn button uses (0131, #158). Yes calls `LearningLanguageService.learn(language: "ell")`, which chooses that pair, then starts the run. No dismisses the alert and nothing else happens.

  The run is presented in a `fullScreenCover`, single-verb mode, at `DrillScope.tenseLevel`.
- **`ConjugationRunViewModel`** (`@MainActor`, in `LearnViewModel.swift`):
  - plans with `ConjugationPlanner` and builds each question just before it shows;
  - records each answer and applies the retry;
  - ends with the summary. Closing keeps what was answered.
- **Layering**: SQL only in `DatabaseService`. Levels, forms, options and planning are pure, in `Learning.swift`. The views render the `ConjugationQuestion` and the summary they are given.

### Example in the answer panel (#364; approved by kyukhin on 2026-11-22)

The data, the cell key and the sources are in 0134, "Drill examples". Here is the app side.
- **Key** (pure, `Learning.swift`): `DrillExampleKey.word(verb:facet:person:) -> String`, which is `"<verb.word>|<facet.rawValue>|<person.rawValue>"` in NFC: `κάνω|imperativeSimple.active|2sg`. The verb's `word` is the card's word, so πάω reads πηγαίνω's cells and ντύνομαι its own.
- **Read**: `DatabaseService.examples(lang: "ell", word: <key>, limit: 1)`, which `examples(for:limit:)` of 0134 now calls too. It does not go through `WordKey`, whose init lowercases A-Z and would turn `imperativeSimple` into `imperativesimple`; the key is looked up as `DrillExampleKey.word` writes it (NFC, mixed case). It is one primary-key read of `example_word`, then the sentence's translations. A missing pack or a pack from before #364 has no cell row, so the result is `[]`, with no special code.
- **`ConjugationRunViewModel`**:
  - gains `@Published private(set) var example: ShownExample?`;
  - in `start()`, next to `loadGrammar`, it reads Greek's via once: `languages.explanationLanguage(of: "ell")`. The meanings language is the run's `meaningsLang`;
  - in `show()`, after building the question and before `phase = .question`, it sets `example` to the cell's first sentence with `ExampleText.learningTranslation(for:via:meanings:)` (0134). So the read ends before the question appears, and the bar never changes after it shows;
  - a failed read or no row gives `nil`. `show()` clears it with the question;
  - the example is the asked cell's, the same after a right and a wrong choice. Nothing is written: no card, log row or setting changes, and `duration_ms` still ends at the answer.
- **`ConjugationRunView`**: the feedback bar's `detail` is the tense table and, when `vm.example` is set, 0134's `ExampleSentenceView(example:number: 1)` under it.
  - `ExampleSentenceView` gains an `identifier` parameter, defaulting to `example_<n>`. The drill passes `drill_example`.
  - Both views are in the bar's scroll, at most half the run's height, so at large text the example scrolls with the table.
- **Layering**: the key and the translation choice are pure; the SQL is 0134's; the view renders the `ShownExample` it is given.
- **Strings**: none new in #364 (Tatoeba's byline is as today). #365's source bylines are 0134's.

### Test seams

- DEBUG `-learningFixture conjugation`, through 0131's fixture mechanism. It writes:
  - Greek learned and `ky-ell-a1` checked;
  - γράφω's `aorist.active` due on rung 2, έχω's `present.active` in learning, πρέπει's `future.active` learned;
  - 30 days of drill rows: aorist 4 of 10 right, present 9 of 10.
- UI tests set the checked lists with E4's `-learningLists` (`ky-ell-a1`, `ky-ell-a2`) and clear `learning_drill_tenses` through `-resetData`.
- DEBUG `-drillLength <n>` sets the session length, so most UI tests answer 3 questions. One test runs the default 15.
- DEBUG `-drillPlan "<cell key>;<cell key>…"` (#364, in `LearningLaunchOptions`): a run asks exactly these cells, in this order, instead of the planner's plan. A key whose verb is not the run's (Practise) or not in the pool (a session), or that is not a cell key, is skipped. Its items are built at tense level B2, whatever the run's level, so any drillable cell builds a question. A wrong answer's retry still applies. So the panel's UI tests reach `κάνω|imperativeSimple.active|2sg` at once.
- E4's `-learningSeed`, `-learningAnswerHints` (the right option's value is `answer`), `-learningLanguages` and `-learningLists`; 0237's `-installPacks ell -packFixtures <path>`, `-skipWelcome`, `-resetPacks` and `-packDownloads`.
- Unit tests that read real forms and lists use the dictionary file on master until 0237 T2 merges, then the Greek pack through `PackFixtures` (0237's rule for `WordFormsLookupTests`).

### Identifiers

| Element | Identifier |
|---|---|
| Learn tab row | `learn_trainer_conjugation` (value: the tense level, `A1`), in Greek's Grammar section since #295 |
| Conjugation screen | `drill_start`, `drill_lists` (the verbs line), `drill_verb_count`, `drill_tenses_picker` (segments labelled by level; only the offered ones exist), `drill_tense_<tense>` (value: the accuracy, `82%`, or empty), `drill_start_button`, `drill_no_lists`, `drill_choose_lists`, `drill_needs_greek`, `drill_download_greek` |
| Run | E4's `exercise_view`, `exercise_close`, `exercise_progress`, `exercise_option_<0…3>`, `exercise_feedback`, `exercise_continue`, `run_summary`, `run_summary_done`; and `drill_prompt_verb` (#331, value: the verb spoken as the question appeared, empty for none), `drill_prompt_translation`, `drill_prompt_tense` (the form's name, label "Aorist"; "Present, passive"), `drill_prompt_person` (label "εγώ", #329), `drill_passive_note` (only on a verb with passive forms only), `drill_tense_info` (the ⓘ, label "About Aorist") and its popover `drill_tense_info_popover` with `drill_tense_info_text`, `drill_tense_info_example` and `drill_tense_info_translation` (#329), `drill_tense_table`, `drill_tense_row_<1sg…3pl>` (value `asked` on the asked person), `drill_example` (#364: the example, one element; its label is the sentence, the translation and the byline, as on the Definition screen) |
| Summary | `drill_summary_tense_<tense>` (value `4/5`) |
| Definition | `drill_practise_button`; the "Learn Greek via English?" alert (Greek via Russian in a Russian UI) is E4's, and its buttons are found by label, as in E4's tests |

`<tense>` is a `ConjugationTense` raw value, as in E10's `stats_tense_<tense>`.

### Strings

About 18 new keys in all 5 languages, translated by the implementing agent (overview, Localization):

| Key | en |
|---|---|
| `drill.title` | Conjugation |
| `drill.tensesUpTo` | Tenses up to |
| `drill.verbsFrom` | Verbs from %@ (the checked lists' titles, comma-joined) |
| `drill.verbCount` | %lld verbs (plural variants) |
| `drill.start` | Start (or E4's Start key, if #158 has one) |
| `drill.noLists` | Choose Greek lists to practise their verbs. |
| `drill.needsGreek` | Download Greek to practise conjugation. |
| `drill.passiveNote` | passive |
| `drill.a11y.tenseInfo %@` | About %@ (the tense's title; #329) |
| `drill.tenseInfo.<tense>` (12) | What the form is for (#329): "One finished action in the past: did." The Greek texts use no verb form, which could give an answer away |
| `drill.tenseInfo.<tense>.example1`, `.example2` (24) | The Greek examples' translations (#329): "Yesterday I wrote a letter." The Greek value is the example itself, never shown |
| `drill.practise` | Practise |
| `drill.a11y.practise` | Practise conjugating %@ |
| `drill.summary.byTense` | By tense |
| `drill.summary.tenseScore` | %1$lld of %2$lld |
| `drill.tense.future`, `.futureContinuous`, `.subjunctiveSimple`, `.subjunctiveContinuous`, `.imperativeSimple`, `.imperativeContinuous` | Future: simple form · Future: continuous form · Subjunctive: simple form · Subjunctive: continuous form · Imperative: simple form · Imperative: continuous form |

- `drill.passiveNote` is a short note, lowercase in every language: en "passive", ru "страдательный залог", es "voz pasiva", ar "مبني للمجهول", el "παθητική φωνή". This matches the wording of `forms.voice.passive` (0136), but the key is separate, so the note can be shortened without touching the tables.
- Reused keys:
  - the tense line: #144's titles of the tenses named by one word (`forms.tense.*`) and `forms.voice.passive` (0136);
  - the levels: E3's `wordLists.level.*` (Α1 … in Greek), and the list names, `wordLists.listTitle`;
  - "Choose lists": E4's `learn.chooseLists`;
  - "Learn Greek via English?" with its Yes and No: E4's `learn.learnLanguage.title` (the pair's two names) and the catalog's buttons;
  - the Download button: 0237's `languages.download`;
  - the run and feedback texts: E4's.
- Percentages use a percent `NumberFormatter` in the in-app locale. The " · " separator is not translated. The pronouns are Greek constants (#144).
- In Arabic a composed tense line starts with U+200F, with the Greek pronoun in FSI…PDI (#119).
- `testEveryCatalogKeyIsTranslatedInEveryShippedLanguage` covers the new keys.

### Code map

| Path | Change | Ticket |
|---|---|---|
| `DictApp/DictApp/Models/Learning.swift` | `ConjugationTense`, `ConjugationFacet`, `DrillLevel`, `DrillScope`, `DrillVerb`, `ConjugationQuestion`, `ConjugationQuestionBuilder` | #167 |
| | `ConjugationPlanner`, `DrillItem` | #169 |
| `DictApp/DictApp/Services/DatabaseService.swift` | `drillVerbs(lists:)` | #167 |
| | `cards(lang:kinds:)`; requests 1 and 2 if E4 and E10 have not done them; the `conjugation` fixture | #169 |
| `DictApp/DictApp/Services/SettingsService.swift` | `learningDrillTenses` (`learning_drill_tenses`), cleared by `-resetData` | #167 (accessor), #168 (UI) |
| `DictApp/DictApp/ViewModels/LearnViewModel.swift` | `ConjugationDrillViewModel`, `ConjugationRunViewModel` | #168 |
| `DictApp/DictApp/ViewModels/DefinitionViewModel.swift` | Keeps the `LemmaParadigm`; `drillVerb` with its translation in the meanings language; `practise()` with the "Learn Greek via English?" alert | #168 |
| `DictApp/DictApp/Views/LearnView.swift` | The Trainers row, `ConjugationStartView` | #168 |
| `DictApp/DictApp/Views/ExerciseView.swift` | `ConjugationRunView`, `ConjugationQuestionView`, `ConjugationTenseView`, the summary's tense block | #168 |
| `DictApp/DictApp/Views/DefinitionView.swift` | The Practise button under the table | #168 |
| `DictApp/DictApp/DictApp.swift` | DEBUG `-drillLength` | #168 |
| `DictApp/DictApp/Models/Learning.swift` | `DrillExampleKey` | #364 |
| `DictApp/DictApp/ViewModels/LearnViewModel.swift`, `Services/LearningService.swift` | `ConjugationRunViewModel.example` and the via; DEBUG `-drillPlan` in `LearningLaunchOptions` | #364 |
| `DictApp/DictApp/Views/ExerciseView.swift`, `Views/DefinitionView.swift` | The example under the tense table; `ExampleSentenceView`'s `identifier` | #364 |
| `DictAppTests`, `DictAppUITests` (`ConjugationDrillFlowTests`, `ConjugationPage`, `AccessibilityIdentifiers`; the Arabic, Greek and iPad suites) | The tests below | #364 |
| `DictApp/DictApp/Resources/Localizable.xcstrings` | The keys | #168 |
| `DictApp/DictAppTests/DictAppTests.swift` | The unit classes in the Test plan | all |
| `DictApp/DictAppUITests/TestCases/ConjugationDrillFlowTests.swift`, `PageObjects/ConjugationPage.swift`, `TestHelpers/AccessibilityIdentifiers.swift`; additions to `ArabicLocalizationTests`, `GreekLocalizationTests`, `iPadSpecificTests`, `StatisticsFlowTests` | UI tests (a synchronized folder, no Xcode step) | #168, #169 |
| `docs/specs/0000-overview.md` | Screens (the Conjugation trainer, Practise on Definition), Preferences (`learning_drill_tenses`), Test plan | each PR |

**No new Swift file.** Every type goes into files that exist on master or that 0131's Xcode step (PR #239) adds: `Learning.swift`, `LearnViewModel.swift`, `LearnView.swift` and `ExerciseView.swift`. So E5 needs no Xcode step and no `project.pbxproj` edit. `INFOPLIST_KEY_CFBundleDisplayName` stays `LibreDict`. There is no new dependency, entitlement or Info.plist key. The drill makes no network call; only the Download button starts 0237's download.

### Tickets, order and sizes

Sizes are pipeline days: development, QA on the four simulators, review and the daily merge.

| Ticket | Scope | Needs | Size | Stream |
|---|---|---|---|---|
| #167 Questions and options by level | `ConjugationTense`, `ConjugationFacet`, `DrillLevel` and its table, `DrillScope` (checked Greek lists, tense level, the "Tenses up to" rule) with the `learning_drill_tenses` accessor, `DrillVerb` (voices, citation, links, passive-only), the θα/να fallback, `ConjugationQuestionBuilder`, `drillVerbs(lists:)`. Unit tests only, on real Greek data | Approval. E3 #151 (`WordKey`, `learning_lists`, `wordlists_schema.sql`) for `drillVerbs` and `DrillScope`, #152 for the test on the real lists. Not E4: no cards; E4 #157's `LearningPairs.via` and #159's `meanings` for a translation not in the via (until they merge, Greek via English is assumed and no translation is dropped) | M, 1.75 | UI 2, free now (there is no UI in it) |
| #169 Spaced repetition and statistics | `ConjugationPlanner` (the 15-question session: due first, tense weights, verb order, retry; single verb), `cards(lang:kinds:)`, requests 1 and 2 (if not done), the `conjugation` fixture, the store and planner unit tests | #157, #163, #167 | M, 1.25 | UI 2 after #167, so the data streams stay free for 0237, E3 and E4 |
| #168 Drill screen | The Trainers row; `ConjugationStartView` with the verbs line, "Tenses up to", the no-list state ("Choose lists") and the missing-pack state; the run (question with the "passive" note, feedback with the tense table, retry, summary); Practise on Definition with the "Learn Greek?" alert; strings; `-drillLength`; the UI suite and the localization and iPad tests | #158 (Trainers, the alert, `LearningLanguageService`), #159 (request 3), E3 #154 (`NewWordsFromView`), #167. Built in parallel with #169 against its interface; merges after it | M–L, 2.25 | UI, whichever is free after #159 |

- The issue bodies are to be updated after approval: the 15-question session logic (due first, weaker tenses more often, the retry) moves from #168 to #169, because the weights need the answers #169 logs. #168 keeps the screens.
- In all: 5.25 stream-days. The first draft's 4.75 grew by 0.25 when #168 gained the no-list state, the "Learn Greek?" alert and the passive note, and by 0.25 for learning pairs (kyukhin, 2026-11-04): #167, already built, takes the meanings language of Greek's pair in `drillVerbs(lists:meaningsLang:)` and keeps a list translation only in that language. The limited Greek via Russian adds nothing: its meanings are English. #168 and #169 do not grow: #168 reuses E4's meaning and alert. 0131's calendar counted about 1.5 for E5.
- **Calendar.** #167 can start on 11-05 and merge as soon as #151 is in, before 11-18: it only adds types and one read. #169 follows #157 and #163 (about 11-13) and merges about 11-17. #168 follows #159 and #154 and merges after #169, about 11-21 to 11-25. All of it is inside the 11-18 to 11-27 window, with 11-26 and 11-27 as slack.
- **If late**: nothing is cut, Practise on the Definition screen included; the release date moves (kyukhin, 2026-11-04, Decisions).
- **#364**: the example in the answer panel is #364's app part, 1.0 stream-day of its 2.5. Its sizes, order and the data part are in 0134's "Tickets, order and sizes".

## Test plan

Unit classes go in `DictAppTests.swift`. Async tests, and classes that are mostly async, are `@MainActor` (#229). Database classes use a temp user database through `setup(userPath:dictionaryURL:)`, and the real Greek forms and lists (the dictionary file, then the Greek pack through `PackFixtures`). Pure classes use fixed cells, fixed days and a seeded generator. UI suites run one per `xcodebuild` run on the four-simulator matrix (iPhone and iPad, iOS 17.5 and 26.4), with the app uninstalled before each, `-resetData`, `-skipWelcome` and `-installPacks ell`.

| Acceptance criterion | Test |
|---|---|
| #132, #167: an A1 drill asks only A1 tenses and verbs from the A1 list | Unit `ConjugationLevelTests`: `testA1IsActivePresentAoristFutureSubjunctiveImperative`, `testA2AddsThePassivePresent`, `testB1Adds`, `testB2Adds`. `DrillVerbPoolTests.testA1PoolIsTheA1ListsVerbs` (only Greek A1 checked: every verb's `listLevel` is 1, 189 verbs; σπίτι and συνηθισμένος are never verbs; πηγαίνω appears once; a list word with no verb lemma, such as αγαπώ, comes in through its link, αγαπάω's table). `ConjugationPlannerTests.testSessionUsesOnlyTheLevelsFacets` (A1 pool, tenses up to A1, 100 seeded sessions: every facet is in A1's set, every verb is from Greek A1). UI `ConjugationDrillFlowTests.testA1DrillAsksA1Tenses` (`-learningLists ky-ell-a1`, `-drillLength 5`: `drill_lists` names Greek A1, the picker starts at A1 and the 5 A1 tenses are listed; every `drill_prompt_tense` starts with one of their titles) |
| kyukhin 2026-11-04: the verbs are the checked Greek lists' verbs only; the tenses go up to the highest checked level | Unit `DrillVerbPoolTests`: `testOnlyCheckedListsGiveVerbs` (Greek A2 alone: only A2 verbs, no έχω or γράφω; A1 and A2: both lists' verbs, A1 first; none checked: no verb and no read; an imported Greek list checked: ignored), `testCountsPerList` (189, 64 and 274 as measured, or the numbers #152's lists give, recorded in History). `DrillScopeTests`: `testTenseLevelIsTheHighestCheckedList` (A2 alone → A2; A1 and B1 → B1; none → A1), `testGreekListsOnly`. UI `ConjugationDrillFlowTests.testNoCheckedListOffersChooseLists` (`-learningLanguages ell`, no list: `drill_no_lists`; `drill_choose_lists` opens `new_words_from`; after checking Greek A2 the screen shows `drill_start_button` and starts at A2) |
| kyukhin 2026-11-04: "Tenses up to" defaults to the highest checked level and can be raised up to B2 for the same verbs | Unit `DrillScopeTests`: `testStoredValueOnlyRaises` (stored A1 with Greek B1 checked → B1; stored B2 → B2), `testOfferedLevelsStartAtTheHighestCheckedList` (A2 checked: A2, B1, B2). `LearningSettingsTests.testDrillTensesKey` (default absent, `-resetData` clears it). `ConjugationPlannerTests.testRaisingTensesKeepsTheVerbs` (Greek A1 at B2: the same verbs, plus perfect and passive-past facets). UI `ConjugationDrillFlowTests.testTensesUpToIsRemembered` (Greek A1 checked: the segments are A1 to B2; B2 lists Perfect; relaunch: still B2; the Learn home row reads B2) |
| kyukhin 2026-11-04: a verb with passive forms only enters at A2 with every A1 tense, with a "passive" note | Unit `ConjugationLevelTests.testPassiveOnlyVerbsStartAtA2` (έρχομαι and ντύνομαι: no question at A1; at A2 Present, Aorist, Future: simple form, Subjunctive: simple form and Imperative: simple form, all in the passive), `ConjugationQuestionTests.testPassiveNoteOnlyForPassiveOnlyVerbs` (έρχομαι yes; γράφομαι, the passive of γράφω, no: its tense line says "passive" instead). UI `ConjugationDrillFlowTests.testPassiveNote` (Practise on έρχομαι: every question shows `drill_passive_note`; Practise on γράφω: none) |
| #132, #167: 4 distinct options, all real forms of the same verb; exactly one correct (any valid variant) | Unit `ConjugationQuestionTests`: `testEveryQuestionOfThePoolHasFourDistinctRealForms` (every (verb, facet, person) of the three lists' verbs at tenses up to B2, 3 seeds: 4 options, no two fold-equal, each a cell or generated form of the verb, exactly one among `rightForms`), `testOtherRightFormsAreNeverOffered` (γράφομαι aorist εγώ: γράφτηκα offered, γράφηκα never; present and imperfect εμείς: γραφόμαστε never a distractor; πηγαίνω present εσείς: πάτε never), `testRightOptionIsTheFirstForm`, `testOneSamePersonAndOneSameTense`, `testNoOtherVoiceAtA1`, `testNoQuestionWithoutThreeDistractors` |
| kyukhin 2026-11-04 (pairs, the limited Greek via Russian): the verb's translation is in the meanings language of Greek's pair | Unit `DrillVerbPoolTests.testTranslationFollowsTheVia` (Greek via English and the limited Greek via Russian: kyukhin's English translation, as before; a test pack with an `ell` → `rus` dictionary, which makes Greek via Russian a full pair: the dictionary's Russian sense, never the English one; neither: an empty translation line, the verb still drilled), `DefinitionViewModelDrillTests.testPractiseTranslationIsInTheVia` (γράφω from El–En · WN with Greek via English and the default order: "write", El–En · FD's first sense) |
| #167: defective and impersonal verbs never produce impossible questions | Unit `ConjugationFormsTests.testEimai` (no aorist and no imperative question; Future: simple form θα είμαι, Subjunctive: simple form να είμαι; no separate continuous forms), `testPrepei` (only αυτός; the present αυτός is cited and never asked; A1 asks θα πρέπει, with the options πρέπει, να πρέπει and έπρεπε, and the tense table has the αυτός row only, #330), `ConjugationQuestionTests.testEveryPlannedItemBuilds` (every planner item over the three lists' verbs at tenses up to B2 builds a question) |
| #167: unit tests on γράφω, είμαι, έρχομαι, πάω and an impersonal verb | Unit `ConjugationFormsTests`: `testGrafo` (facets per level, both voices, εγώ not asked in the present), `testEimai`, `testErchomai` (passive main voice; nothing at A1; at A2 ήρθα, θα έρθω, έλα; ερχόμουν at B1), `testPao` (linked to πηγαίνω: the card word and the citation are πηγαίνω; a right option is a first form), `testPrepei`; `DrillVerbTests.testPassiveLinkKeepsItsWord` (ντύνομαι: passive only, word ντύνομαι), `testParticipleIsNoVerb` |
| #330 (kyukhin, 2026-11-14): impersonal verbs and list words given in the third person ask and show only αυτός | Unit `DrillVerbTests.testListWordInTheThirdPerson` (υπάρχει: cited υπάρχει, card word υπάρχω, only αυτός questions, options and rows; "(δεν) πειράζει"; Practise on υπάρχω stays whole), `DrillVerbPoolTests.testListWordsInTheThirdPersonAreImpersonal` (the three lists: a verb listed only in the third person is impersonal, cited and translated as listed; the third-person words of verbs also listed in their plain form; no impersonal question drops), `testPlainFormMakesAWholeVerb` (υπάρχω "to exist" A1, πειράζω B1 and νοιάζομαι in every person with their own entry; προτιμάω from A1's προτιμώ), `testListNounsAreNoVerbs` (the six words of another part of speech that spelled a verb's form; no verb translated "time" or "country"; φοράω "to wear", χωράω from B1; the impersonal verbs are πρέπει, επιτρέπεται, χιονίζει, πρόκειται), `testCountsPerList` (196, 66, 333), `ConjugationFormsTests.testPrepei`, `ConjugationQuestionTests.testEveryPlannedItemBuilds` |
| #329 (kyukhin, 2026-11-14): ⓘ explains the form; the person has its own line | Unit `DrillTenseInfoTests`: `testEveryTenseHasItsTextInEveryLanguage` (the explanation and both translations of 12 tenses in en, ru, es, ar, el; no translation in a Greek UI), `testArabicAndTheButtonsLabel`, `testExampleRule` and `testExampleRuleOnMadeUpVerbs` (case, punctuation, NFC, the last word, any tense or voice, nil when both have a form), `testThePoolsExamplesHaveNoFormOfTheVerb` (every verb of the three lists at every tense up to B2: the example shown has no form of the verb; none left without one; έχω is never asked the perfect tenses, whose examples all have its forms); `DrillQuestionTextTests.testTenseLine` (VoiceOver's one stop, `promptLabel`: "Aorist, εγώ", "Present, passive, εσύ", "Aorist, εγώ, passive"); `ConjugationRunRuleTests.testTenseInfoTimeIsNotTheAnswersTime`. UI `ConjugationDrillFlowTests.testTenseInfoExplainsTheForm` (the person under the name, "About Aorist", the popover by the button with its texts, closed: the same verb, options and person), `GreekLocalizationTests.testConjugationDrillInGreek` (no translation line), `ArabicLocalizationTests.testConjugationDrillRightToLeft` (ⓘ left of the name, the example after U+200F and isolated) |
| #132, #168: the whole tense is shown after the answer | Unit `ConjugationQuestionTests.testTenseRowsHoldEveryPersonAndForm` (γράφομαι aorist: 6 rows, εγώ reads "γράφτηκα / γράφηκα"; an imperative: 2 rows). UI `ConjugationDrillFlowTests.testWholeTenseAfterEachAnswer` (`-learningAnswerHints`: one right and one wrong answer, each followed by `drill_tense_table` with the tense's rows, the asked row with value `asked`, then Continue) |
| #299 (kyukhin, 2026-11-10): a wrong form shows which person and tense it is | Unit `ConjugationQuestionTests.testOptionSlots` (γράφω aorist εγώ: each distractor's slot is a cell holding that form; a θα form's slot is its future cell; the right option's slot is the question's), `testSharedFormKeepsItsOwnSlot` (a form held by two cells, such as present and imperfect: the option's slot is the cell it was taken from, not the earlier one), `ConjugationRunViewModelTests.testWrongChoiceKeepsItsSlot` (the feedback's chosen form and slot; nil when right). UI `ConjugationDrillFlowTests.testWrongFormShowsItsSlot` (`-learningAnswerHints`: a wrong option; `exercise_you_chose` starts with "You chose:" and holds a Greek pronoun) |
| #132, #168, #169: 15 questions per session; weaker tenses come more often | Unit `ConjugationPlannerTests`: `testFifteenItems`, `testDueCardsFirst` (20 due: 15 due items, the weakest tense first), `testWeakerTensesComeMoreOften` (aorist 4 of 10, present 9 of 10, 500 seeded sessions of new pairs: aorist asked more than 1.5 times as often as present), `testWeights` (the formula's three examples), `testSameVerbNotTwiceInARow`, `testWrongComesBackOnceWithinFifteen`, `testShortVerbRun` (πρέπει at A1: 2 items). UI `ConjugationDrillFlowTests.testSessionOfFifteen` (no `-drillLength`: `exercise_progress` reaches 15, then `run_summary` with `drill_summary_tense_*`) |
| #132, #169: each (verb, tense, voice) follows the interval ladder; a wrong answer returns it to learning | Unit `ConjugationStoreTests`: `testCardClimbsTheLadder` (answers on days 1, 2, 5, 12 and 26: steps 1 to 5; then a wrong answer: step 0, due today), `testVoicesAreSeparateCards` (γράφω `aorist.active` and `present.passive`), `testFirstAnswerCreatesTheCard`, `testRightOnACardNotDueChangesNothing`, `testLogRow` (kind, exercise, mode, facet, detail, `introduced` 0) |
| #132, #169: per-tense accuracy and the hardest verbs appear in statistics | Unit `ConjugationStoreTests.testTenseAccuracyFromDrillAnswers` (answers through `recordAnswer`, then E10's `tenseAccuracy`: the aorist's two voices are one group), `testHardestVerbsFromDrillAnswers`; E10's `AccuracyTests.testByTenseFromDrillRows`. UI `StatisticsFlowTests.testConjugationBlockAfterADrill` (Greek, a 3-question drill with one wrong answer: `stats_tense_<tense>` shows its accuracy) |
| #169 (requests 1, 2): drill answers never change words, and word features ignore drill cards | Unit `ConjugationStoreTests.testDrillLeavesWordsAlone` (γράφω in My words, not started: after a drill answer `introduced_day` is NULL, the word is still in the new pool and `startedCount` is 0; Stop learning on γράφω leaves its drill cards unpaused; `mistakeCards`, `learningState`, `wordStates` and `errorCount` ignore drill rows; the daily session never plans a drill card) |
| #166 (0166): every drill question counts toward the daily goal | Unit `ConjugationRunViewModelTests.testEachQuestionCountsTowardTheGoal` (3 answers: `answeredCount(today)` grows by 3 and today's `learn_day` row exists), `testSummaryEqualsTheRunsLogRows`, `testClosingKeepsAnswers` |
| #132, #168: Practise on a verb's table starts the drill for that verb | Unit `DefinitionViewModelDrillTests.testPractiseFollowsTheTable` (γράφω, έχω, πάω (as πηγαίνω), έρχομαι and ντύνομαι give a drill verb, in a checked list or not; σπίτι, καλός and an English word do not), `ConjugationPlannerTests.testVerbRunAsksOnlyThatVerb`. UI `ConjugationDrillFlowTests.testPractiseFromDefinition` (`-learningLanguages ell`; search γράφω, open El–En · FD: `drill_practise_button` under `inflection_table`; the run starts with no alert; every `drill_prompt_verb` is γράφω; σπίτι has no button) |
| kyukhin 2026-11-04: Practise asks "Learn Greek?" first when Greek is not learned; No cancels the drill | Unit `DefinitionViewModelDrillTests`: `testPractiseAsksToLearnGreek` (no learned language: the alert state is set and no run starts), `testNoCancels` (after No: no run, no `learn_card` or `learn_review` row, `learning_languages` unchanged), `testYesLearnsGreekThenStarts` (a fake `LearningLanguageService`: `learn(language: "ell")` called once, then the run). UI `ConjugationDrillFlowTests.testPractiseAsksLearnGreekFirst` (fresh install with the Greek pack, no learned language: Practise on γράφω shows "Learn Greek via English?"; No: still on Definition, no `exercise_view`; Practise again, Yes: `exercise_view` appears; after closing, the Learn tab offers Greek, not the picker) |
| #168: the row only for Greek; the drill needs the Greek pack | UI `ConjugationDrillFlowTests`: `testRowOnlyForGreek` (`-learningFixture bilingual`: the English tab, no row; the Greek tab, the row, in its Grammar section since #295), `testNeedsTheGreekPack` (`-resetPacks`, `-learningLanguages ell`, `-learningLists ky-ell-a1`, no pack: `drill_needs_greek`; Download with `-packDownloads ok`, then Start appears) |
| #331: the drill speaks its verb as each question appears, Speak words off nothing | 0131's test plan: unit `QuestionWordTests`, `ConjugationRunViewModelTests.testDrillSpeaksTheCitedVerb`; UI `ConjugationDrillFlowTests.testDrillSpeaksItsVerb`, `ExerciseFlowTests.testSpeakWordsOffSpeaksNothing` |
| #132, #168: tense names in 5 UI languages; Arabic right to left; iPhone and iPad, iOS 17.5 and 26.4 | `testEveryCatalogKeyIsTranslatedInEveryShippedLanguage`; unit `ConjugationLevelTests.testTenseTitlesInEveryLanguage` (12 titles × 5 languages, none equal to its key). UI `GreekLocalizationTests.testConjugationDrillInGreek` (an Α1 segment, Greek tense titles), `ArabicLocalizationTests.testConjugationDrillRightToLeft` (the pronoun column on the right, forms left to right), `iPadSpecificTests.testConjugationDrillOnIPad` (a centred column, landscape); `ConjugationDrillFlowTests` on the matrix |
| #364: κάνω, imperative εσύ: the panel shows a sentence with κάνε, its translation and byline, after a right and after a wrong answer | UI `ConjugationDrillFlowTests.testAnswerShowsTheCellsExample`, launched with `-learningLanguages ell`, `-learningAnswerHints` and `-drillPlan "κάνω\|imperativeSimple.active\|2sg;κάνω\|imperativeSimple.active\|2sg"`, Practise on κάνω (El–En · FD). The first answer is right: `drill_example` is under `drill_tense_table` in `exercise_feedback`, and its label holds Κάνε, a Latin-script translation and "Tatoeba". Continue. The second answer is wrong: the same example (the asked cell's, not the chosen option's). Unit `ConjugationRunViewModelTests.testExampleIsTheAskedCells`, on a fixture pack with one cell row: `example` is set before `phase` becomes `.question`, unchanged after a right and a wrong choice, one read per question, and cleared on the next question. `DrillExampleKeyTests.testKey` (the format, NFC, πάω's question reads πηγαίνω's key, ντύνομαι its own) |
| #364: the translation follows the via, as in learning | Unit `ConjugationRunViewModelTests.testExampleTranslationFollowsTheVia`: Greek via English shows English; the limited Greek via Russian shows Russian when the row has it, else English (0134's `learningTranslation`) |
| #364: a cell without a sentence shows the panel as before | Unit `ConjugationRunViewModelTests.testNoSentenceNoExample`: no row, the stub attached, or a failed read give `example` nil and the feedback as before. UI `ConjugationDrillFlowTests.testCellWithoutSentenceShowsNoExample`, with `-drillPlan` on a cell the build report lists as open (`γράφω\|futurePerfect.passive\|1sg` on 2.0's data, a B2 tense): `drill_tense_table` shows and `drill_example` does not |
| #364: VoiceOver, Arabic, iPad, large text | UI `ArabicLocalizationTests.testDrillExampleRightToLeft`: the example's leading edge is on the right, and the byline starts with U+200F. `GreekLocalizationTests.testDrillExampleInGreek`: the byline is as on Definition. `iPadSpecificTests.testConjugationDrillOnIPad`, extended: the example sits in the centred column. `ConjugationDrillFlowTests.testDrillExampleAtTheLargestTextSize`: the bar scrolls to `drill_example`, and Continue stays hittable. `ConjugationDrillFlowTests` on the matrix |
| #365: a generated sentence says so | UI `ConjugationDrillFlowTests.testGeneratedExampleSaysSo`: `-drillPlan` on a cell whose only sentence is generated, picked from the data file in `TestData`; the label holds "Generated by LibreDict". The rest is in 0134's test plan |
| Performance | QA: the Conjugation screen ready in under 300 ms with all three Greek lists checked and tenses up to B2 (iPhone 15 Pro simulator, iOS 17.5, median of 3), recorded in History |
| Offline | Review: no networking API in the diff besides the call to 0237's `PackService.install` |

## Open questions

1. **Verbs with passive forms only, and "A1 is active only".** Resolved 2026-11-04: they enter at A2 with every A1 tense in their own voice, marked as passive (Decisions).
2. **Which verbs a level drills.** Resolved 2026-11-04: the checked lists choose the verbs, the highest checked level the tenses (Decisions).
3. **B2 without a B2 list.** Resolved 2026-11-04: a "Tenses up to" setting, B2 included (Decisions).
4. **Participles at B2.** Resolved 2026-11-04: left out of the drill in 2.0 (Decisions).
5. **Future of verbs without simple forms.** Resolved 2026-11-04: θα and να + the present in the drill (Decisions).
6. **Practise when Greek is not a learned language.** Resolved 2026-11-04: ask "Learn Greek?" first (Decisions).
7. **The answer panel's example (#364).** Resolved 2026-11-22: kyukhin answered 0134's open questions 7 to 12 (0134, Decisions).

## History

- 2026-11-04: First draft. Measured with a prototype on the dictionary file of master `fc8c930` and kyukhin's three CSVs: 527 list verbs with a table (A1 189, A2 64, B1 274), 44 of them linked passives, 15 participles left out, 12 without simple forms, two impersonal (πρέπει, πρόκειται); the cells of 530 verbs read in 16 ms. Aligned with 0130, 0131, 0166 and 0237 as kyukhin approved them on 2026-11-04, with four requests to E4 and E10 (Depends on).
- 2026-11-04: kyukhin decided the six open questions (Decisions), and the spec now follows them:
  - the checked Greek lists choose the verbs;
  - "Tenses up to" (`learning_drill_tenses`) starts at the highest checked level and can be raised to B2;
  - verbs with passive forms only start at A2 and carry a "passive" note;
  - participles stay out;
  - θα / να + the present for verbs without simple forms;
  - Practise asks "Learn Greek?" first.

  This changed Behaviour, Design (`DrillScope`, `drillVerbs(lists:)`), Identifiers, Strings, the Tickets (#168 grows to 2.25, 5 days in all) and the Test plan. The spec stays Draft.
- 2026-11-04: Approved by kyukhin.
- 2026-11-04: Learning is chosen as a language pair (kyukhin, 0131): the verb's translation is in Greek's via (`drillVerbs(lists:via:)`, 0131's meaning rule, also from the Definition screen), and the alert reads "Learn Greek via English?". With Greek via English as 2.0's only Greek pair, the drill reads as before. #167 +0.25 (5.25 days in all). Nothing is cut if late (kyukhin).
- 2026-11-04: Greek via Russian is offered as a limited pair (kyukhin, 0131): the verb's translation follows the pair's meanings language (`drillVerbs(lists:meaningsLang:)`), English for both Greek pairs; Practise asks for Greek's default pair, Greek via Russian in a Russian UI. No size change.
- 2026-11-06: Rebased on master with 0130 and 0237. Review fixes: the pool keeps a list word with no verb lemma until the Definition's link rule has run, so αγαπώ and αρέσει come in through their linked tables (with a test); the weight examples match the formula (1.36 and 3.36); the intro says which prerequisite specs are on master.
- 2026-11-07: #167 as built on the packs: the lists come from `DictionarySchemas.listsSchema(for: "ell")` and the forms from the `ell` pack's schema; the drill keeps its own `fold` until #159's `AnswerChecker` is on master; a full Greek pair whose via has no translation drills the verb with no translation line; a list without `wordlist.translation_lang` (before #152) keeps its translation. The retry rule (CodeRabbit, PR #247) is settled in #168.
- 2026-11-07: #167 rebased on #152 and #163: every pack has `wordlist.translation_lang`, so the pool reads it directly and the "absent column keeps the translation" case is gone; the test fixture replaces the pack's own `ky-ell` rows (CodeRabbit, PR #256). The Greek pack's lists give 198, 69 and 330 drill verbs (597; the CSV prototype measured 189, 64 and 274), which `testCountsPerList` now checks.
- 2026-11-07: #169 as built: a verb whose passive is also a passive-only verb in the pool (ντύνω and ντύνομαι) drops that passive in sessions, so it is drilled once, under ντύνομαι; Practise on ντύνω from Definition still drills both voices under ντύνω's cards. `recordAnswer` creates a missing conjugation card. When only the previous verb is left in a group, the group waits one place. A run shorter than its length adds the retry at the end instead of replacing an item; the retry asks a person not yet asked and is the only card asked twice in a run (CodeRabbit, PR #247). The planner uses #163's `Tally`, `ReviewSummary.durationCapMs` and `DailySeries.start(today:)`; its tense accuracy, hardest verbs and `learn_day` goals are tested against #163's statistics.
- 2026-11-07: For #168: plan with `ConjugationPlanner.session` or `verbRun` over `cards(lang:kinds:)` and #163's tense accuracy, pass the run's real length (`-drillLength`) to `afterWrong` (it defaults to 15), record each answer with `recordAnswer(item.answer(...))`, and add the drill fixture to `writeLearningFixture`.
- 2026-11-08: #168 as built: the tense titles use kyukhin's terms shared with 0133's Practise button ("Future: simple form", «Будущее: простая форма»; kyukhin 2026-11-07), so six `drill.tense.*` keys are new and the statistics screen's tense titles follow; `-drillLength` lives in `LearningLaunchOptions`; Start reuses `learn.start`; the Trainers row's value is the level as the UI writes it (Α1 in Greek); the tense table is rows, not a `Grid`; new id `drill_download_progress`. Measured: the Conjugation screen with three lists at B2 opens in 425 ms in Release (target 300), mostly #167's `DrillVerb.make`; a follow-up makes it fast. The "Learn a few words first" footer still shows under an enabled Conjugation row (follow-up).
- 2026-11-08: Epic #132 closed: Implemented. The tense names read as the code and 0133 name them ("Subjunctive: simple form", six `drill.tense.*` keys); while the other trainers are disabled, the Conjugation row sits in its own section below their "Learn a few words first" footer; the screen reads its verbs again when the meanings language of Greek's pair changes (CodeRabbit, PR #277). Performance: the Conjugation screen with three lists at B2 now loads in 209 ms in Release (438 ms before; iPhone 17 simulator, iOS 26.4, median of 7), under the 300 ms target: `fold` reads a byte table indexed by code point instead of a dictionary (folding the pool's forms took 190 ms, now 24 ms), and the pool read parses each tag set once.
- 2026-11-10: Revision for epic #292 and #300 (Draft, awaiting kyukhin's approval): the Conjugation row moves from Trainers to the Grammar section of Greek's pair tab, keeping its id (#295); a wrong choice shows the chosen form's tense and person, from the new `optionSlots` (#299); the drill plays 0131's new sounds (#300).
- 2026-11-10: The #292/#300 revision approved by kyukhin.
- 2026-11-10: Two rules from kyukhin's spec review via CodeRabbit on PR #302: the drill never plays Lesson complete (only Daily goal reached, when its answers fill the ring), and a form shared by several cells is named by the option's own slot.
- 2026-11-10: The #292/#300 revision is built (PRs #303, #304, #305).
- 2026-11-12: CodeRabbit review: `optionSlots` names its real type, `[ConjugationQuestion.Slot]`; no change to the behaviour.
- 2026-11-15 (kyukhin, #331): with Speak words on (0131), each question speaks its verb as the prompt cites it as the question appears; the next question, the summary and closing the run stop it. The verb's accessibility value is the word spoken, for UI tests. A question, Screens, Identifiers and Test plan updated.
- 2026-11-15 (kyukhin, #329): the question's tense line keeps the form's name with an ⓘ that explains the form in a popover (an explanation and a Greek example with no form of the asked verb, translated into the UI language); the person moves to its own line, in the accent colour; the popover's time is not the answer's. VoiceOver still reads the name, the person and the note in one stop, then the ⓘ. Over the three lists at tenses up to B2 every asked tense has an example.
- 2026-11-15 (kyukhin, #330): an impersonal verb has only its αυτός cells, so its options and its tense table never use another person (θα πρέπει: πρέπει, να πρέπει, έπρεπε). A list word given in the third person (υπάρχει, πειράζει, επιτρέπεται) makes its verb impersonal, cited as listed; the pool reads the item's `term`, and the first list word of a verb decides (αρέσω, βρέχω and αστράφτω stay whole). No impersonal question drops. A list word that is a lemma of another part of speech and no verb lemma is no verb (kyukhin): Ορίστε!, φορά, χώρα, κρέμα, γέννα and πείνα leave the pool, so ορίζω and κρεμάω are no longer drilled (196, 68 and 331 drill verbs; 595, was 597). Then (kyukhin, 2026-11-15) a verb the lists also give in its plain form is whole, with that entry's citation, translation and level, and only verbs listed in the third person alone stay impersonal: υπάρχω ("to exist", A1) and πειράζω (B1) are whole, νοιάζομαι is its passive in every person, εξετάζω comes from B1 ("to examine", not A2's εξετάσεις), and 19 B1 verbs listed first by their passive or participle (αναγκάζομαι, οργανωμένος, βρόμα) take their own entry's translation. The impersonal verbs are πρέπει, επιτρέπεται, χιονίζει and πρόκειται; the lists give 196, 66 and 333 drill verbs.
- 2026-11-16 (kyukhin, follow-up 4): the ⓘ example rule reads every person of an impersonal verb's drilled voices, not only its αυτός cells; its questions, options and tense table stay αυτός only (CodeRabbit, PR #335; `DrillTenseInfoTests.testImpersonalVerbAvoidsEveryPerson`; the pool's examples do not change). Speak words fixes of 0131 (PR #332): a drill already left does not stop the next run's verb, and the verb's accessibility value is empty while VoiceOver runs.
- 2026-11-22 (kyukhin, #364; Draft, waiting for kyukhin's review): after an answer, right or wrong, the answer panel shows one sentence with exactly the asked form under the tense table. The translation follows Greek's via as in learning, and the byline names the source; no sentence, no change. `ConjugationRunViewModel.example`, read with 0134's `examples(for:limit:)` under the cell key `DrillExampleKey.word`. `ExampleSentenceView` under the table with the id `drill_example`; DEBUG `-drillPlan`. The data, the sources and the measured coverage are in 0134, "Drill examples".
- 2026-11-22: The #364 example approved by kyukhin on 2026-11-22, with his answers to 0134's open questions 7 to 12 (0134, Decisions): tenses up to A2 in 2.0, checked readings for homographs, English and Russian only for added sentences.
- 2026-11-22 (#364): the cell's sentence is read with `examples(lang:word:limit:)`, not `WordKey`, which lowercases A-Z; DEBUG `-drillPlan` builds its items at B2.
