# Learning words with spaced repetition

> Spec written by Claude (AI) for LibreDict.
> Status: Implemented, with a revision for epic #292 (tickets #293, #295, #296, #298, #299; #297 is in 0133) and for #300, approved by kyukhin on 2026-11-10 and not built yet; the rest approved by kyukhin on 2026-11-04 · Epic: #131, revised by #292 · Tickets: #157, #158, #159, #160, #161, #162; #293, #295, #296, #298, #299, #300 · Updated: 2026-11-10

Read [0000-overview.md](0000-overview.md) and [0129-dictionary-file.md](0129-dictionary-file.md) first. This epic is designed together with [0166-learning-statistics.md](0166-learning-statistics.md) (E10, #166), which computes the daily goal, the streak and every number from this epic's answer log. Word lists are E3 (#130, [0130-word-lists.md](0130-word-lists.md), drafted at the same time). This spec follows E3's interface ("For E4 and E10" there); "Depends on E3" records how, and the three points where it differs. The conjugation drill (E5, #132) reuses the cards, the scheduler and the log ("For E5"). The pair tabs of #292 also change 0130, 0132, 0133 and 0166 where they describe the Learn tab.

## Why

LibreDict 2.0.0 is for learning Greek (and English) words, not only looking them up. In 1.x a bookmark was the only way to keep a word, and nothing helped the user remember it. This epic adds a daily session that schedules each word on fixed intervals and grades the answers itself, Duolingo-style exercises with instant feedback, mistakes practice and an opt-in reminder. Bookmarks go: the Learn tab replaces them, and "Learn" on a word adds it to My words and starts learning it.

Beta feedback (kyukhin, 2026-11-09/10, #292): the Learn tab mixed the learned languages behind one switch, did not say which pairs exist or how to add one, and a lesson closed early could not be continued. #292 gives each learned pair its own tab with everything about its language, keeps a lesson closed early, and #300 gives learning its own sounds.

## Behaviour

### Words and cards (#157)

- A word is a word of a language (E3's `WordKey`): γράφω in Greek, house in English.
  - It is one word whether it comes from a list, from My words or from two dictionaries: γράφω in Greek A1, from El–En · FD and from El–En · WN.
  - List words without a dictionary entry (12% of kyukhin's Greek words, such as γιουβέτσι) are learned too, with the list's translation.
- Each word has two cards with separate schedules, one per direction:
  - **recognition**: the word → its meaning, choose 1 of 4;
  - **production**: the meaning → the word, choose 1 of 4 or type it.
- The app grades every answer. There is no "Again / Good / Easy".
- Each card climbs a fixed ladder: 1, 3, 7, 14, 30, 90 days.
  - A right answer to a card that is due moves it one rung up.
  - A wrong answer, due or not, puts it back to learning: it comes back in the same session, then after 1 day.
  - A right answer to a card that is not yet due (trainers, mistakes, match the pairs) is logged and counts toward the daily goal, but does not move the card.
- **Learned** means both cards reached the 30-day rung. A later wrong answer takes the word out of "learned" again.
- What the user sees for a card: New (never answered), Learning, Every 1 / 3 / 7 / 14 days, Learned (30 and 90 days).
- **The meaning** shown in exercises is in the meanings language of the word's pair, which is its via language except in the limited Greek via Russian (Languages and pairs, below):
  - the list's translation, when the list has one in the meanings language (kyukhin's Greek lists have English ones, the English lists none) or when the list is the user's own import;
  - otherwise the first sense of the word in the pair's dictionary, shortened (Design, "Meanings"): house via Spanish is "casalicio, casa", via Greek "σπίτι (το χτίριο), οίκος, στεγάζω".
  - Meanings are shown as the dictionary or list gives them. They are not translated into the UI language.
- **The word** is shown as its list writes it, with its endings in the secondary colour (`αγάπη η`, `αγαπημένος -η, -ο`), as on E3's list screen. A word from My words is shown as its headword.

A card's life:

| Day | Answer | Card after |
|---|---|---|
| 1 | right (first answer) | every 1 day, due day 2 |
| 2 | right | every 3 days, due day 5 |
| 5 | right | every 7 days, due day 12 |
| 12 | right | every 14 days, due day 26 |
| 26 | right | every 30 days, due day 56. The word is learned once its other card is there too |
| 56 | wrong | learning, asked again before the session ends. Right then: every 1 day |

### The Learn tab (#158; by pair since #293, #295)

- The tabs become Search · Learn · History · Settings. Bookmarks is gone.
- No learned language yet: the Learn tab shows the pair picker (Languages and pairs, below).
- Otherwise it shows one tab per learned pair, then "+" (Pair tabs, below). The selected tab shows its language's home, one list, top to bottom; everything on it is that language's, except the goal ring and the streak (kyukhin, 2026-11-10):

| Section | Content | Ticket |
|---|---|---|
| Today | The daily goal ring and the streak, the same on every tab (0166). "12 due · 6 new words left today" and **Start** (the daily session), or **Continue lesson · 7 left** (Daily session) | #158 counts, #161 Start, #164 ring and streak, #296 Continue |
| Practise mistakes | "Practise mistakes · 7 words", hidden at 0 | #161 |
| Trainers | Recognition, Production, Match the pairs | #159, #160 |
| Grammar | "Topics · 17" (0133) and, for Greek, "Conjugation · A1" (0132, moved here from Trainers). Hidden for a language with neither (English in 2.0) | #172, #168, #295 |
| Lists | The tab language's checked lists ("Greek A1", "Greek A2") with their progress, "Learning from · Greek A1, A2" (E3's screen of checked lists, "New words from" until #298) and "All lists" (E3's Lists screen, the tab's language only) | E3 #154, #295, #298 |
| My words | "My words · 23": the tab language's words | #158, #295 |
| Statistics | The statistics screen of the tab's language | #164, #295 |

- While the pair's packs download, the install row sits above Today (0237).
- Nothing to learn yet on a tab (no word in learning, no list checked):
  - a language with lists, built-in or imported: Today reads "Choose lists or tap Learn on a word", with a "Choose lists" button that opens E3's Learning from. There is no default (0130, Open questions 3 and 6);
  - a language without any list: Today offers "Import a list" (E3's Import) and reads "Add words with Learn on a word's screen."
- Nothing due and no new words left: Start is hidden and Today reads "All done for today", unless a lesson can be continued (Daily session). Trainers and mistakes stay available.
- **The chosen language**, here and in 0130, 0132, 0133 and 0166, is the language of the selected tab.

### Pair tabs (#293)

kyukhin, 2026-11-10: one tab per learned pair, replacing the language switch.

- **A tab** is a learned language with its via: "Greek · via Russian", "English · via Spanish" (the language's name and Settings' "via Russian", joined by " · "). A language has one via (Languages and pairs), so one tab; changing the via in Settings renames its tab and changes nothing else. Other (`und`) has no via: its tab reads "Other".
- **The strip** sits at the top of the Learn tab, under its title, and stays while the home scrolls; screens pushed from the home (a list, Statistics, a topic) do not show it. The selected tab is filled. A tap selects a tab; the choice is remembered across launches.
- **"+"** after the last tab opens the pair picker, the same screen as Settings → Learning → Languages → Add a language: the pairs of the languages not learned, with their download sizes. Choosing one adds its tab last, selects it and starts its download, which its home shows.
- **Too many tabs.** When the tabs and "+" do not fit the width, the last visible item is "…". It opens a sheet listing the pairs that did not fit, then "Add a language" (Open question 11). Choosing a pair closes the sheet and selects its tab. The selected tab always shows in the strip: a selected pair that would be hidden takes the last place before "…", for display only. A tab name that does not fit even alone is cut with "…".
- **No sorting.** A tab is dragged to another place. The order is stored and kept across launches. A new pair goes last, and so does a pair stopped and added again.
- **Long press** on a tab opens a menu with "Stop learning", then Settings' alert, "Stop learning Greek? Your progress is kept." Yes removes the tab: its cards, log, checked lists and via are kept, as Stop learning in Settings keeps them (2026-11-03). The first tab is then selected; with no tab left, the picker shows. Adding the pair again with "+" brings back the tab, last, with its progress. Resetting a language's progress is for a later release (kyukhin, 2026-11-10).
- **Shared by every tab**: the streak and the daily goal ring, as Duolingo does (kyukhin, 2026-11-10). Words, lists, My words and statistics are per language.
- **VoiceOver**: the strip is a tab bar. A tab reads its pair name and "selected" when it is; "+" reads "Add a language" and "…" "More languages". Each tab has the actions "Move earlier", "Move later" and "Stop learning", so the order changes without dragging.
- **Arabic** mirrors the strip: the first tab on the right, "+" or "…" at the left end. A pair name starts with U+200F (#119).
- **iPad**: the same strip; its width usually fits every tab.

### Languages and pairs (#157, #158, #162)

Learning a language is explicit (kyukhin, 2026-11-03), learning never mixes languages, and a language is learned through another one, chosen as a pair (kyukhin, 2026-11-04).

**Pairs.** A pair is the language learned and the language it is learned through, its via language: "Greek via English", "English via Spanish". It does not depend on the UI language. The app offers a pair only when the data has a dictionary from the one into the other (`from_lang` → `to_lang`): bundled, in 0237's catalog, or imported with both languages known (#208). The list of pairs is read from the data, so a new source adds its pair with no code change.

A pair has two languages besides the learned one: its **via language**, which explanations are in (grammar, tips, notes), and its **meanings language**, which word meanings are in (exercises, list translations, the drill). They are the same language in every pair a dictionary gives. The catalog can also offer a **limited pair**, whose meanings language differs because no dictionary goes into its via (kyukhin, 2026-11-04): Greek via Russian, with meanings in English. In 2.0:

| Pair | Its dictionaries (meanings) | Packs it downloads (0237) |
|---|---|---|
| Greek via English | El–En · FD, El–En · WN | `ell` |
| Greek via Russian, limited: meanings in English | El–En · FD, El–En · WN | `ell` |
| English via Greek | En–El · FD, En–El · WN | `eng-lists`, `ell` |
| English via Spanish | En–Es · FD | `eng-lists`, `spa` |
| English via English | WordNet | `eng-lists` |
| Spanish via English | Es–En · WN | `spa` |
| Russian via English | OpenRussian | `rus` |
| Arabic via English | Ar–En · WN | `arb` |

Not in 2.0: Greek via Spanish (no such dictionary, and kyukhin's lists are translated into English only), a full Greek via Russian with Russian meanings (Greek–Russian data may come in 2.1), and English via Russian or via Arabic (OpenRussian and Ar–En · WN only go into English; Open question 9).

- **One via language per learned language.** Cards, the log, progress and statistics belong to the learned language: a word's cards do not depend on the pair. The pair decides only what is shown and downloaded:
  - its meanings language: the meanings in questions, production prompts, match the pairs and the hardest words (Meanings); the translations on E3's list screen (0130); the drill verb's translation (E5, 0132);
  - its via language: grammar explanations (E6, 0133) and example translations in learning (E7, 0134; in a limited pair the meanings language when Tatoeba has none in the via);
  - the packs the pair needs (0237).
- **The limited pair, Greek via Russian** (kyukhin, 2026-11-04):
  - its rows in the picker and in Settings carry a warning on a second line: "Greek via Russian · Words are practised in English";
  - in Russian: the grammar, all 17 A1 topics with Russian-specific Watch out items (0133), and the notes inside learning content;
  - in English: word meanings in exercises, list translations (kyukhin's lists are in English) and the drill's verb translations;
  - examples in learning: the Russian translation when Tatoeba has a direct one, else the English one (0134);
  - the screens themselves stay in the UI language, as always.
- **The default via**, when a language is chosen: the UI language if that pair exists, limited or not, else English. A Spanish UI learns English via Spanish, a Greek UI English via Greek, a Russian or Arabic UI English via English. A Russian UI learns Greek via Russian, with the warning; every other UI learns Greek via English.
- **The picker.** With no learned language, the Learn tab asks "Which language do you want to learn?" and lists every pair whose language is not learned yet. Pairs of languages with built-in lists come first, captioned "With word lists"; the others follow. Within each group: by the learned language's name, its default via first, then its other vias by name. A row reads "English via Spanish", with the size of its missing packs under it, "9.6 MB to download" (the catalog's sizes, 0237; the English lists pack with its examples and the Spanish pack). A limited pair's row adds its warning, "Words are practised in English", with an info icon hidden from VoiceOver, so text carries it.
- **Choosing a pair** adds its language to the learned languages (`learning_languages`, last: the tab order), stores its via (`learning_via`) and selects its tab. Its My words not started yet are enrolled then and come first among new words (Decisions, Open question 1). 0237 then installs the pair's missing packs: the learned language's lists (Greek in the Greek pack, English in the English lists pack) and the pair's dictionaries.
  - With built-in lists, the Learn home then offers "Choose lists".
  - Without, the Learn home offers "Import a list" and "Add words with Learn on a word's screen."
- **The tabs** (Pair tabs, above) show the learned languages in the stored order, one or more. Languages are named as in the production prompt (`language.*.name`, in the UI language; `und` is E3's "Other"). The selected tab is remembered (`learning_language`); if its language is no longer learned, the first tab is selected.
- **More languages.** "+" on the Learn tab, and Settings → Learning → Languages, which lists the learned languages in the tab order, each with its via ("English · via Spanish"), and "Add a language". Both open the picker without the languages already learned. Learn on a word of a language not learned also adds one (below).
- **Changing the via**, in Settings → Learning → Languages: a language with two or more pairs shows its via as a menu (Greek: English, Russian; a limited pair's item and row carry its warning). A change applies from the next question and installs the new pair's missing packs, with the picker's progress row. It changes no data: cards, log, progress and checked lists stay.
- **Stop learning a language**, in Settings → Learning → Languages or with a long press on its tab (#293), after "Stop learning Greek? Your progress is kept.": its tab goes and its lists are hidden (0130); its cards, log, checked lists and via stay as they are. Choosing it again resumes, as the last tab: its due cards are due, its lists come back checked, with the via of the pair chosen then.
- **Other** (`und`, 0130) has no pair. Imported lists marked Other and words of imported dictionaries without languages are learned in it; its meanings are the lists' translations, else the word's own entry's first sense.
- **Everything on a tab is its language's** (#295): Today's counts, Start, the trainers, mistakes practice, match the pairs, Grammar, the Lists section, My words and Statistics. Due cards and new words alike; a My words word goes by its own language (`WordKey.lang`). Only the goal ring and the streak are shared.
- **The daily limit of new words is per language**: 10 Greek and 10 English on a day when both are studied.
- **The daily goal ring and the streak count every language** (E10).
- **Progress is per language**: a tab's counts and list bars, and its statistics screen (0166), show its language only.
- A notification tap opens the Learn tab on the tab selected last.

### Learn on the Definition screen (#158)

The bookmark star becomes a Learn button in the same place.
- **Not in learning**: an outlined graduation cap, read as "Learn". A tap adds the entry to My words and starts learning the word at once: two new cards. A word that was learned before and stopped comes back with its progress.
- **A word of a language not learned** (kyukhin, 2026-11-03): the tap asks "Learn Spanish via English?", with the language's default pair (kyukhin, 2026-11-04). For a limited pair the alert's message is its warning: "Learn Greek via Russian?" · "Words are practised in English." Yes adds the pair (as the picker does) and learns the word. No only adds the word to My words, without cards; it is enrolled if the language is chosen later, and until then it shows on no tab (#295, Open question 12). A word of a language without a pair (an import whose languages are unknown) asks 0130's "Learn lists in other languages?" and is learned in Other.
- **In learning**: a filled cap, read as "Stop learning". A tap removes the word from My words, every row of its `WordKey` (γράφω saved from El–En · FD and El–En · WN goes at once), and pauses its cards. Paused cards keep their progress, and no session, trainer or new-word pick offers them.
- **In My words, language not learned**: a filled cap, read as "Remove from My words". A tap removes it, every row of its `WordKey` too.
- A word in learning from a list shows the filled cap too. E10 (#165) adds the word's stage and next review under the headword.

### My words (#158, then E3 #154)

- Until E3's list screen lands, Learn → My words shows today's Bookmarks list, moved as it is: newest first, a one-line snippet, a tap opens the Definition. A key that no longer resolves stays stored and is skipped (#138).
- E3's list screen (#154) then shows My words like any other list (0130).
- In both, the swipe is Stop learning: the word leaves My words and its cards are paused, as with the Learn button.
- Empty: "Tap Learn on any word to add it here."
- **Per tab** (#295): the My words row counts, and its screen lists, the words of the tab's language only (`WordKey.lang`). A word of a language not learned shows on no tab until its language is learned (Open question 12).

### Exercises (#159)

- **Recognition**: the word (large) with its endings, its part of speech, a speaker button when the device has a voice (#202), and 4 meanings in the meanings language.
- **Production, choice**: the meaning in the meanings language, and 4 words.
- **Production, typed**: the meaning, a text field ("Type the word in Greek"), Check and "Don't know". "Don't know" counts as wrong.
- A card's first question shows a "New word" badge.
- The 4 options are the right one and 3 others in the same language. They come from the same list and the same part of speech where possible. No two options read alike: equal after removing accents, or sharing a meaning ("house, home" and "home, place").
- **Typed answers** follow the answer mode setting. The answer is the word as shown, without its endings. Case, extra spaces, a final σ typed as σ and one leading article are ignored in every mode, and a part in parentheses is optional (`(ένα) σωρό`: σωρό or ένα σωρό):

| Typed, expected γράφω | Strict accents | Lenient | Multiple choice |
|---|---|---|---|
| γράφω, Γράφω, " γράφω " | right | right | (no field: 4 words) |
| γραφω | wrong: "Mind the accent: γράφω" | right, with "Mind the accent: γράφω" | — |
| το σπίτι, expected σπίτι | right | right | — |
| γράφεις | wrong | wrong | — |

### Instant feedback (#159; #299)

- On the tap of an option, or on Check, the answer is graded at once:
  - the chosen option turns red with a cross if it is wrong;
  - the right option turns green with a check mark, always.
- At the same moment there is a haptic tap and a sound (Sounds, below), each of which can be turned off in Settings.
- A bar slides up with "Right!" or "Right answer: write", and Continue.
- **What you chose** (#299, kyukhin 2026-11-10): after a wrong choice the bar also shows what the chosen option means, under the right answer, so both are remembered:
  - Recognition (choose the meaning): "You chose: water · νερό", the meaning chosen and the word it belongs to;
  - Production as a choice (choose the word): "You chose: νερό · water", the word chosen and its meaning;
  - the conjugation drill (0132): "You chose: γράψαμε · Aorist · εμείς", the form with its tense and person, written as the question's tense line writes them;
  - match the pairs: below.
  Typed answers and "Don't know" are unchanged: there is no chosen option.
- VoiceOver announces the result, and the "You chose" line after the right answer. Colour is never the only signal. In Arabic the line starts with U+200F and its word and meaning are isolated (FSI…PDI), as the bar's other lines are.

### Sounds (#300)

kyukhin, 2026-11-09/10: learning should sound playful, in the spirit of ICQ in its day, never with ICQ's own sounds (they are copyrighted). The app has its own sounds, synthesized in code as today's two tones are: no audio file, no licence.

| Sound | Plays when | Before #300 |
|---|---|---|
| Right | a right or accent answer: the session, trainers, mistakes, the drill | two rising notes |
| Wrong | a wrong answer or "Don't know" | one low note |
| Pairs right | a pair matched in match the pairs | the Right tones |
| Pairs wrong | a wrong pair | the Wrong tone |
| Lesson complete | a run's summary appears: the session, a trainer, mistakes, the drill, or a match round's result | none |
| Daily goal reached | in place of Lesson complete, on the summary of the run during which today's exercises reached the goal | none |

- Each plays once, at its moment. A run closed before its summary plays no end sound.
- One Sounds setting (Settings → Learning) covers all six, on by default. The ring/silent switch mutes them and other audio keeps playing, as today.
- Each sound is the variant kyukhin picks from the candidates (Open question 10).

### Daily session (#161; #296)

Start runs the session in the chosen language:
1. **Due cards** first: reviews and cards to relearn, most overdue first, at most 30.
2. **New words**, up to the daily limit (10 by default) minus the words of that language already started today:
   - first the words of My words not started yet, oldest first;
   - then the next words of that language's checked lists, as E3 orders them (`nextNewWords`): lower levels first across the lists, within a level by frequency with a light shuffle, or at random (setting). The user checks lists on E3's Learning from or with "Learn this list". With none checked, new words come from My words only.
- A new word is asked twice: recognition, then its production as a choice. New words come in groups of three: three recognitions, then those three productions.
- Familiar production cards (on the 1-day rung or higher) are typed per the answer mode, or a choice when the mode is "Multiple choice".
- The two cards of a word are never asked back to back while other cards remain.
- A card answered wrong comes back once at the end of the session.
- The session can be closed at any time. The answers so far are kept and count.
- **Continue lesson** (#296, kyukhin 2026-11-10). A session closed before its end (a lesson) is kept until it is finished or the learning day ends:
  - the Today button reads "Continue lesson · 7 left" instead of Start. It opens the same lesson at the next unanswered question, with its progress bar (closed after answering question 3 of 18: "Question 4 of 18", the bar at 3 of 18), and its wrong answers still come back at its end;
  - no new lesson is built while one can be continued;
  - the next learning day (4 AM) drops it, and Start builds a new lesson. Its words then follow the session's rules: new words never answered come first, and a word left with one card answered has its other card due;
  - its summary counts the whole lesson, both sittings;
  - each tab keeps its own: Greek's lesson and English's are separate;
  - Practise mistakes, the trainers, match the pairs and the drill are unchanged: closing them ends them.
- **Summary**: exercises, right answers in %, new words, reviewed words and time, plus the daily goal progress (E10). Its numbers come from the answer log of this session.

### Trainers (#159, #160)

- **Recognition** and **Production** each run 10 items of their own direction, in the chosen language:
  - due cards first;
  - then new words, within the daily limit;
  - then practice: the cards on the lowest rungs.
- Match the pairs is the third trainer. E5's Conjugation is in the Grammar section since #295.
- With nothing in learning and no list checked, the trainers are disabled with "Learn a few words first".

### Mistakes practice (#161)

"Practise mistakes" asks every card of the chosen language answered wrong in the last 7 days (today and the 6 days before) and not answered right since, the most recent mistake first, with the session's exercise rules. The row is hidden when there is none.

### Match the pairs (#160)

- Five words and their meanings stand in two columns, each shuffled. A timer counts up.
- Tap one tile in each column, in either order:
  - a right pair disappears, with the success haptic and the Pairs right sound;
  - a wrong pair flashes red, with the error haptic and the Pairs wrong sound. A line under the columns shows each tapped tile's own pair, "νερό · water" and "γράφω · write", until the next tap (#299).
- When all 5 pairs are matched, the round shows its time and mistakes, with "Next round" and "Done".
- **Words**: all of the chosen language. Learning words come first, then new words (within the daily limit), then the lowest rungs. The meanings must all differ.
- With fewer than 5 such words, the trainer is disabled with "Learn 5 words first".
- Each word is one recognition answer: right if it was matched at the first try, wrong if it was part of a wrong pair before. A round is 5 items toward the daily goal.

### Settings (#162)

A Learning section replaces the "Coming Soon" stub in Settings:

| Setting | Values | Default | Effect |
|---|---|---|---|
| Languages | The learned languages in the tab order, with their via (a menu with two or more pairs), "Add a language", "Stop learning" on each | none | Languages and pairs, above |
| New words per day | 0–50 | 10 | The daily limit of new words per language, in sessions, trainers and match the pairs |
| Learning from ("New words from" until #298) | The checked lists of every learned language (E3's screen) | none | The lists new words come from (0130) |
| Daily goal | 5–200 exercises, in steps of 5 | 20 | E10: the goal ring, the streak and the reminder |
| New words order | By frequency / Random | By frequency | The order of new words from a list |
| Typed answers | Strict accents / Lenient / Multiple choice | Lenient (Decisions) | Production on the 1-day rung or higher |
| Sounds | on / off | on | The six learning sounds (Sounds, above) |
| Haptics | on / off, hidden on devices without haptics | on | The feedback haptics |
| Daily reminder | off / a time | off, 19:00 | Below |

A change applies from the next question. Words already started keep their cards.

### Reminder (#162)

- Opt-in. The notification permission is asked only when the user turns the reminder on. If iOS denies it, the switch goes back off and a footer offers "Open Settings".
- At the chosen time, only on a day when the daily goal is not met yet: "Time for today's words. Your goal: 20 exercises."
- Tapping the notification opens the Learn tab.
- Reminders are scheduled for the next 7 days, so they stop after a week without opening the app.

### Upgrade from 1.x and earlier 2.0 builds (#157)

- 1.x bookmarks are in My words since #139. They are not enrolled until their language is chosen (kyukhin, 2026-11-03); then they come first among new words, within the daily limit (Decisions). The 1.x move stays as 0129 describes it on master.
- Words added to My words by 2.0 builds before #157 wait the same way.

### iPhone, iPad, Arabic, VoiceOver, Dynamic Type

- Exercises cover the screen, with a close button and a progress bar. On iPad and in landscape the content is at most 600 pt wide and centred. Long options wrap and are never cut.
- Arabic mirrors every screen; match the pairs puts the words on the right. Greek and English words keep left to right inside Arabic text (FSI…PDI, as in #119).
- VoiceOver reads an option as a button ("write, button"), the result as an announcement, the stage as text. The progress bar reads "Question 4 of 18".
- On iPadOS 26 the Learn tab sits in the floating strip (#120). Several iPad windows show the same data after a reload.

### Decisions

- 2026-10-22 (kyukhin): no self-rated flashcards. The app grades by correctness.
- 2026-10-22 (kyukhin): two cards per word, one per direction: recognition (Greek → translation, choose 1 of 4) and production (translation → Greek, choose or type). These are two separate exercises, each launchable on its own.
- 2026-10-22 (kyukhin): typed answers follow a user setting: strict accents, lenient, or multiple choice.
- 2026-10-22 (kyukhin): fixed intervals. "Learned" means both cards reached a 30-day interval; this may become configurable later.
- 2026-10-22 (kyukhin): 10 new words a day by default. Within a level they come by frequency with a light shuffle, behind a setting "by frequency / random".
- 2026-10-22 (kyukhin): from Duolingo, all in 2.0: a daily goal ring (N exercise items, set in Settings, default 20), a streak where a day counts when the goal is met, with 1 freeze per week (E10; since 2026-11-03 one freeze every Monday, up to 3 in stock, 0166), instant feedback with haptics and sound that can be turned off, mistakes practice, an opt-in reminder, and match the pairs.
- 2026-10-22 (kyukhin): Bookmarks are removed. The tabs become Search · Learn · History · Settings. The Definition star becomes "Learn", which adds the word to My words and enrols it at once. 1.x bookmarks migrate into My words (#139).
- 2026-10-22 (kyukhin): listening, build-a-sentence, achievements and the widget move to 2.1.0 (#147–#150).
- 2026-10-28 (kyukhin, 0129): learning data lives in the user database, keyed by stable text, never by entry row ids.
- 2026-11-03 (kyukhin): learning is per language. Languages never mix in a session, a trainer or mistakes practice; a switch on the Learn home chooses the language when there are several, and the choice is remembered. The new-word limit is per language. The daily goal and the streak stay shared. Progress is per language: "progress is about a specific language, not the whole learning module".
- 2026-11-03 (kyukhin, Open question 1): Learn enrols a word within the daily limit: My words not started yet come first among new words, so 50 words added in one evening come 10 a day.
- 2026-11-03 (kyukhin, Open question 2): Stop learning pauses the word and keeps its progress; Learn resumes it.
- 2026-11-03 (kyukhin, Open question 3): a card leaves mistakes practice once its last answer is right, as in Duolingo.
- 2026-11-03 (kyukhin, Open question 4): typed answers default to Lenient.
- 2026-11-03 (kyukhin, Open question 5): no introduction screen for a new word: its first question carries the "New word" badge and the instant feedback teaches it.
- 2026-11-03 (kyukhin, Open question 6): a learning day starts at 4 AM local time, for the daily limit, the goal and the streak.
- 2026-11-03 (kyukhin, Open question 7): one Xcode step for E3, E4 and E10 (2 renames, 6 new files), in the worktree of whichever of #151 and #157 starts first.
- 2026-11-04 (kyukhin): the Xcode step is its own PR, made by Claude in the project file and merged before #151 and #157, so the two data streams start from it.
- 2026-11-03 (kyukhin, Open question 8): if 11-16 slips, after #160 and E7 the cuts go in this order: the reminder (to 2.0.1, the settings stay), E10's streak calendar and per-tense block, then E10's #165.
- 2026-11-03 (kyukhin): nothing is cut ahead of time. The checkpoint moves from 11-13 to 11-15, then to 11-16 for learning per language; code complete (11-20) and the App Store submission (11-27) stay.
- 2026-11-03 (kyukhin): learning a language is explicit (`learning_languages`, ordered). With none, the Learn tab asks "Which language do you want to learn?" over the languages the app has dictionaries for, bundled or downloadable. A chosen language with built-in lists gets them through #237's download flow; one without offers "Import a list" and Learn on a word. The switch shows the learned languages, and E3's screens only their lists.
- 2026-11-03 (kyukhin): Learn on a word of a language not learned asks "Learn Spanish?": Yes adds the language, No only adds the word to My words.
- 2026-11-03 (kyukhin): 1.x bookmarks go to My words but are not enrolled until their language is chosen. E4 does not change 0129's 1.x move.
- 2026-11-03 (kyukhin): a language can be stopped in Settings → Learning: its progress is kept, its lists are hidden, it leaves the switch, and choosing it again resumes.
- 2026-11-03 (kyukhin): the release date moves for #237 (downloads). The calendar below is to be replanned with it; the order stays.
- 2026-11-04 (kyukhin): new dates with #237: E3, E4, E10 and #237 done by 11-20; code complete 11-27; submission to Apple 12-04. A second data stream runs (2 UI + 2 data). If behind, E7 and #160 move to 2.0.x first, then the agreed cut order.
- 2026-11-04 (kyukhin): learning is chosen as a language pair, "Greek via English", "English via Spanish", independent of the UI language. 2.0 offers only the pairs the data has a dictionary for; Greek via Russian is not offered. Progress, cards and statistics stay per learned language; each learned language has one via language, changeable; the via decides the meanings, the list translations, the example translations and the packs. The default via is the UI language when that pair exists, else English.
- 2026-11-04 (kyukhin): nothing is cut from 2.0 if it runs late: the release date moves instead. This replaces the cut order of 2026-11-03 (Open question 8) and "E7 and #160 move to 2.0.x first" above.
- 2026-11-04 (kyukhin, Open question 9): 2.0 has no English via Russian or via Arabic (no dictionary from English into them); with a Russian or Arabic UI, English is learned via English. English–Russian data comes in 2.1 with Greek–Russian.
- 2026-11-04 (kyukhin): Greek via Russian is offered as a limited pair, although there is no Greek–Russian dictionary: its picker row warns "Words are practised in English"; grammar, tips and notes are in Russian; word meanings, list translations and the drill's verb translations are in English; examples show the Russian translation when Tatoeba has a direct one, else the English one. A Russian UI choosing Greek gets it by default. Data-driven: a pair has a via language (explanations) and a meanings language, and the catalog marks the pair as limited. This replaces "Greek via Russian is not offered" above. English via Russian stays out of 2.0 (Open question 9).
- 2026-11-07 (kyukhin): Greek meanings prefer the bilingual dictionary: El–En · FD comes before El–En · WN among a Greek pair's dictionaries, whatever Dictionary Order says (`LearningPairs.preferredMeaningSources`), as WordNet's first senses (κάνω "befriend", βλέπω "date") mislead learners. Search's Dictionary Order is unchanged.
- 2026-11-07 (kyukhin): don't show a wrong WordNet sense. English WordNet defines nouns, verbs, adjectives and adverbs only, so a list word none of whose parts of speech (the list's) is one of them takes no meaning from it (`Gloss.gives`): in English via English, he, I, us, me, or and who have no meaning and are skipped (rule 4), as WordNet's senses are other words' (He "helium", US, OR, WHO). A word that is also a noun keeps it; via Greek or Spanish the bilingual dictionaries still give one.
- 2026-11-10 (kyukhin, #293): one tab per learned pair, named "Greek · via Russian", replaces the language switch. A "+" tab after the last opens the pair picker, with its download. When the tabs and "+" do not fit, the last visible item is "…", which opens a modal sheet with the pairs that did not fit. No sorting: the tabs are reordered by dragging, the order is stored and kept, and a new pair goes last.
- 2026-11-10 (kyukhin, #293): a long press on a tab offers Stop learning, with its progress kept (as decided on 2026-11-03); adding the pair again restores it. A full progress reset is for a later release, not this revision.
- 2026-11-10 (kyukhin, #293): the streak and the daily goal are shared by all pairs, as Duolingo does; words, lists and statistics are per language.
- 2026-11-10 (kyukhin, #295): each tab holds everything about its language: Today, Practise mistakes, Trainers (Recognition, Production, Match the pairs), Grammar (the topics and, for Greek, the conjugation drill, moved out of Trainers), Lists, My words, Statistics. Sections a language lacks are hidden.
- 2026-11-10 (kyukhin, #296): a lesson closed early is kept until it is finished or the day ends. The button reads "Continue lesson · N left" and resumes at the next unanswered question with its bar. The trainers, mistakes and the drill are unchanged.
- 2026-11-10 (kyukhin, #297): the Grammar list has no header while only one level exists; the level is in the subtitle ("17 topics · A1"), and an "A2 · Coming soon" row ends the list, not a button (0133).
- 2026-11-10 (kyukhin, #298): "New words from" becomes "Learning from", with the checked lists as the row's value ("Greek A1, A2").
- 2026-11-10 (kyukhin, #299): a wrong choice also shows what the chosen option means: recognition, production with options, match the pairs, and the drill's form with its person and tense. Typed answers are unchanged.
- 2026-11-10 (kyukhin, #300): learning gets its own sounds, synthesized in code in the spirit of ICQ, never ICQ's own: right, wrong, lesson complete, daily goal reached, pairs right, pairs wrong. One Sounds setting, as today. The variants are kyukhin's pick (Open question 10).

### Out of scope

The 2.1.0 tickets above. Russian meanings for Greek (no Greek–Russian dictionary in 2.0; Greek via Russian is limited), other limited pairs, and meanings translated from another pair. FSRS or another algorithm (the scheduler is a protocol, so it can replace the ladder later). A configurable ladder or learned threshold. Typo tolerance in typed answers. Editing a word's meaning. A badge on the Learn tab. Resetting a language's progress (a later release, kyukhin 2026-11-10). Two vias of one language as two tabs. iCloud sync of learning data (#73 syncs preferences only). List export (#156).

## Design

### Depends on #129

| #129 rule | E4 use |
|---|---|
| User data lives in `user.sqlite`; each epic registers its own migration, `<epic>-<n>-<what>` | `131-1-learning` (below). E10 adds `166-1-daily-goal` |
| Text keys, never `dict.*` row ids | A word is E3's `WordKey (lang, word)`; its entry, when it has one, is an `EntryKey (source, headword)`. Nothing stores a row id |
| `my_words (source, word, added_at)` holds My words; 0129 on master still says "E4 enrols every item, in its migration and on add" | Changed by kyukhin on 2026-11-03, and this rule is the one to implement: E4 enrols a language's My words when the language is chosen, and a new item on add only when its language is learned. The migration enrols nothing. `learnWord` writes `my_words` and the cards in one transaction. 0129's `my_words` row says the same from #237's spec change (PR #238, merging first): "E4 enrols a language's My words when the user chooses to learn that language; the 1.x move and E4's migration enrol nothing" |
| The 1.x move (#139) runs after the migrator, then inserts My words | Unchanged: the moved bookmarks wait in My words until their language is chosen. E4 does not touch `LegacyMigration.copy` or 0129's "1.x migration" (an earlier draft of this spec did) |
| #213: only reads and the import retry after an I/O error | Learning writes touch only `user.sqlite`. `learnWord`, `stopLearning`, `enrolMyWords` and `introduce` read the dictionary file in their transaction (the sources' languages, the entries), so they retry once after an I/O error, as the import does; the other writes are plain `pool.write`, never retried. Learning reads go through `read` |
| `userPool()` waits for a running 1.x move | Every learning method starts there, so the Learn tab shows its loading state until the move commits, like History |

### Depends on E3 (#130)

Aligned with [0130-word-lists.md](0130-word-lists.md), "For E4 and E10" (draft of 2026-11-03). E3 owns lists, their words, the built-in list data (in the languages' packs, 0237), import, the Lists, list and Learning from screens (New words from until #298), the new-word order and the checked-lists preference. E4 owns cards, the log, sessions, enrolment, the Learn tab and home, and the other learning settings, "by frequency / random" among them.

What E4 uses, as 0130 defines it:
1. **`WordKey (lang, word)`** is a word's learning identity:
   - `lang` is ISO 639-3, or `und` when unknown;
   - `word` is the term as stored, with only A–Z lowercased, and no Unicode normalisation (0130: SQL cannot normalise, and 1,402 Arabic WordNet headwords are not NFC). Swift's `String` equality merges canonically equal spellings where SQL keeps two keys. Such twins come only from such an Arabic headword next to an NFC list or import spelling: SQL then holds two words, and `enrolledKeys()` counts them as one, so the list spelling is not picked as new. Accepted, as in 0130.
   Cards, the log and `learn_word` are keyed by it, never by `EntryKey`. Two lists or two dictionaries give one word, and a word without an entry can still be learned.
2. **A My words row's key**, in the enrol statement's SQL:
   - `COALESCE(d.from_lang, s.from_lang, 'und')` and `lower(m.word)`;
   - from `my_words m LEFT JOIN (<DictionarySchemas.sourceLanguageSQL>) d ON d.source = m.source LEFT JOIN imported_sources s ON s.source = m.source`. 0237's `sourceLanguageSQL` reads the bundle's `dict_metadata` and `dict.catalog_source`, so a My words row of a pack not yet downloaded keeps its language instead of `und`.
   In Swift, the same key comes from `wordKey(for: EntryKey)`. A unit test checks that the two agree.
3. **Queries**:
   - `wordLists()`;
   - `wordListItems(_:)`;
   - `nextNewWords(in:from:count:excluding:order:)`, over the lists of one language in a set, deterministic per install, language, set, order and exclusion set. E4 passes the chosen language, the checked lists and every key it has cards for, paused ones included, so a stopped word does not come back as new;
   - `entry(for item:sourceOrder:)`, with the pair's dictionaries first, then Dictionary Order's sources, enabled first (`LearningPairs.sourceOrder`);
   - `wordKey(for: EntryKey)`.
4. **Content** of a list word: `term`, `translation` (may be empty), `translationLang` (0130's `WordListItem.translationLang`, from `wordlist.translation_lang`; '' for imports and My words; added to 0130 by PR #251, which merges before this spec; until #154 reads the column, built-in items carry '' too, so a list word introduced before #154 keeps '' and its translation shows in every pair, as an import's does), `endings`, `partOfSpeech`, `headword`, and `listID`, the list it came from. When the translation is empty, or `translationLang` is neither the pair's meanings language nor '', the meaning comes from the pair's dictionary (Meanings).
5. **The checked lists** are `SettingsService.learningListIDs` (key `learning_lists`, a set, defined by #151), changed on E3's Learning from screen (`NewWordsFromView`) and by "Learn this list" (#154). The set stays empty until the user checks a list (no default, 0130 Open questions 3 and 6). Deleting a list unchecks it.
6. **List progress** on E3's rows is E10's `ListProgress` over `wordListItems(id).map(\.key)` (0166).
7. **Order of work**: #154 is reached from #158's Learn tab, so #158 merges first. E3's screens read `learning_languages` (0130). #154 adds "Choose lists" and the "New words from" row to the Learn home; whichever of #154 and #162 merges second adds the row to the Learning settings.

Where E4 differs from 0130, and why:
1. **One transaction for Learn.** 0130 has the Learn button call `addToMyWords` / `removeFromMyWords(EntryKey)` and then enrol. E4's `learnWord` and `stopLearning` run the same `my_words` statement and the card changes in one transaction instead. A crash between two writes would otherwise leave a My words row without cards, which nothing repairs. The `my_words` insert is the same; the delete removes every row of the word's key (0130's key, item 2 above), not only one `EntryKey`, or a word saved from two dictionaries would stay in My words.
2. **The My words swipe on E3's list screen calls `stopLearning`**, not `removeFromMyWords`. kyukhin's rule is that the second tap of Learn removes the word from learning too (#158). Removing it from My words alone would leave it in sessions with no way to stop it.
3. **E4 stores a list word's content when it picks the word** (`term`, `translation` with its language, `endings`, `partOfSpeech`, the resolved entry) in `learn_word`, rather than reading the list at every question. The meaning in the meanings language is still chosen at each question (Meanings), so changing the via needs no rewrite:
   - a deleted list keeps its words in learning (0130: "Progress on its words is kept"), which also covers the words without an entry;
   - questions, E10's hardest words and the Definition status need no list reads;
   - the cost is that a later fix to a translation in the bundled list does not reach words already picked.

Two conditions on 0130's key, for the other epics:
- **#208** (v2.0.0, open) will fill `imported_sources.from_lang`. It changes the key of a word from an existing import from `und` to its language. If an import has words in learning, #208's PR remaps them, with a unit test for each case below:
  - their `lang` in `learn_word`, `learn_card` and `learn_review` (matched through `learn_word.source`), in one user-database transaction;
  - when the new key already exists (house in learning from WordNet and from the import), the existing word and its cards stay, the `und` word and its cards are deleted, and its log rows move to the existing key, so the statistics keep them;
  - then the preferences: if `und` is learned, the language joins `learning_languages` right after it (unless already there) with its default via, and `learning_language` moves from `und` to it. `und` stays learned until the user stops it.
  - #208's languages also make an import's direction a pair (Languages and pairs), with no pack to install.
- Words of imports without a language, and of user lists marked "Other", share `und`. The same spelling in two such lists is one word, which is accepted.

#151 merged first (master `4713f6b`), so #157 uses master's `WordKey` and `wordKey(for:)`, and #161 master's `nextNewWords`, `wordListItems` and `entry(for:sourceOrder:)`.

### For E5 (#132)

The drill reuses this epic's tables and scheduler, and needs no migration of its own:
- **Cards**: `learn_card` rows with `kind = 'conjugation'`, `lang = 'ell'`, `word` = the verb lemma under the `WordKey` rule: as `lemma.word` stores it (in NFC, as the forms build writes it), only A–Z lowercased, nothing normalised by E4, and `facet` = `<tense>.<voice>` (ASCII; E5 names the tenses, e.g. `aorist.active`). One card per (verb, tense, voice), scheduled by `FixedLadder` like a word card.
- **Answers**: `recordAnswer` with `exercise = 'conjugation'`, `mode = 'drill'`, the card's `facet`, and `detail` = the person asked (`1sg`…`3pl`). That gives E10 accuracy by tense, grouped on the part of `facet` before the dot, so both voices of a tense are one group, and the hardest verbs (`GROUP BY word`) from the same log.
- Drill answers count toward the daily goal and the streak.
- E4's planners never pick `conjugation` cards. E5 reads them with `dueCards(lang: "ell", kinds: [.conjugation])`.
- E5 uses `FeedbackPlayer` and the Sounds and Haptics settings, and adds its row to Greek's tab: in Trainers until #295, in the Grammar section since.

### Data: migration `131-1-learning` (#157)

```sql
-- A word in learning: one row per WordKey (0130).
CREATE TABLE learn_word (
    lang            TEXT NOT NULL,                -- WordKey.lang: ISO 639-3, 'und' if unknown
    word            TEXT NOT NULL,                -- WordKey.word: the term, only A–Z lowercased
    term            TEXT NOT NULL,                -- shown and expected: the list's term, or the headword
    endings         TEXT NOT NULL DEFAULT '',     -- shown next to the term
    pos             TEXT NOT NULL DEFAULT '',     -- part of speech, for distractors
    translation     TEXT NOT NULL DEFAULT '',     -- the list's; '' = take the meaning from the pair's dictionary
    translation_lang TEXT NOT NULL DEFAULT '',    -- its language (the list's translation_lang, 'eng' for kyukhin's lists); '' = an import's, shown in every pair
    source          TEXT,                         -- its entry is EntryKey(source, headword);
    headword        TEXT,                         --   both NULL for a word without an entry
    list_id         TEXT,                         -- the E3 list it was picked from; NULL for My words
    added_at        TEXT NOT NULL DEFAULT (datetime('now')),
    introduced_day  TEXT,                         -- local day of its first answer; NULL = not started
    PRIMARY KEY (lang, word)
) WITHOUT ROWID;

-- A card: two per word; E5 adds conjugation cards.
CREATE TABLE learn_card (
    lang       TEXT NOT NULL,
    word       TEXT NOT NULL,
    kind       TEXT NOT NULL,                    -- recognition | production | conjugation (E5)
    facet      TEXT NOT NULL DEFAULT '',         -- '' for word cards; E5: <tense>.<voice>
    step       INTEGER NOT NULL DEFAULT 0,       -- 0 learning; 1…6 = 1, 3, 7, 14, 30, 90 days
    due_day    TEXT NOT NULL,                    -- local day it is due
    last_day   TEXT,                             -- local day of its last answer; NULL = never answered
    suspended  INTEGER NOT NULL DEFAULT 0,       -- 1 after Stop learning
    PRIMARY KEY (lang, word, kind, facet)
) WITHOUT ROWID;
CREATE INDEX learn_card_due ON learn_card(lang, due_day) WHERE suspended = 0;

-- The answer log: one row per exercise item, append-only.
CREATE TABLE learn_review (
    id           INTEGER PRIMARY KEY,
    answered_at  TEXT NOT NULL DEFAULT (datetime('now')), -- UTC
    day          TEXT NOT NULL,                  -- local day, YYYY-MM-DD
    lang         TEXT NOT NULL,
    word         TEXT NOT NULL,
    kind         TEXT NOT NULL,
    facet        TEXT NOT NULL DEFAULT '',
    exercise     TEXT NOT NULL,                  -- recognition | production_choice | production_typed | match | conjugation (E5)
    mode         TEXT NOT NULL,                  -- session | trainer | mistakes | drill (E5)
    run_id       TEXT NOT NULL,                  -- one UUID per run: the summary's rows
    outcome      TEXT NOT NULL,                  -- right | accent | wrong
    step_before  INTEGER NOT NULL,
    step_after   INTEGER NOT NULL,
    introduced   INTEGER NOT NULL DEFAULT 0,     -- 1 on the answer that started the word
    duration_ms  INTEGER NOT NULL DEFAULT 0,     -- question shown → answer
    detail       TEXT                            -- per exercise; E5: the person asked
);
CREATE INDEX learn_review_day ON learn_review(day);
CREATE INDEX learn_review_word ON learn_review(lang, word);
CREATE INDEX learn_review_run ON learn_review(run_id);     -- a run's summary (E10's reviewRows(run:))
```

- The migration enrols nothing (Decisions). `LearningSQL.enrolMyWords` enrols a language's My words when the language is chosen, in one `INSERT … SELECT` over `my_words` rows of that language whose keys are not in `learn_word` yet:
  - the key is 0130's (Depends on E3, item 2), filtered on its `lang`;
  - one row per key: two My words rows can share a key (γράφω from El–En · FD and from El–En · WN), so the select groups by the key and takes the row added first (`added_at`, then `source`);
  - `term` and `headword` are that row's word, and `source` is its source;
  - two cards per new word are created with step 0 and `due_day` = today.
- **A picked list word** gets its content from its `WordListItem`, `translation_lang` included. Its entry is `entry(for:sourceOrder:)` with the pair's dictionaries first, resolved once, when it is picked, and stored as `source` and `headword`: the Definition it opens. Its meaning is not stored (Meanings).
- `translation_lang` goes into `131-1-learning` itself: no build with the migration has shipped (#157 is not on master yet).
- **Days** start at 4 AM local time, as in Anki: an answer at 00:30 counts for the day before (Decisions). A day is written `YYYY-MM-DD` in the Gregorian calendar and the current time zone, so days compare as text. A log row keeps the day it was written in: a later time-zone change rewrites nothing.
- **Size**: about 120 bytes per answer. A year at 50 answers a day is ~2 MB, with 5,000 words in learning ~1 MB more. The dictionary file does not change.
- **Removal**: nothing deletes learning rows except `-resetData` (DEBUG). Stop learning sets `suspended`. A word whose entry no longer resolves and that has no list translation is skipped by the planners, never deleted (#137 rule).

### Data: migration `292-1-kept-lesson` (#296)

A lesson closed early is learning data, so it lives in the user database (2026-10-28), next to the answers it must agree with:

```sql
-- The lesson a tab can continue: one row per language.
CREATE TABLE learn_lesson (
    lang      TEXT PRIMARY KEY,   -- the tab's language
    day       TEXT NOT NULL,      -- the learning day it started (YYYY-MM-DD); another day: not offered
    run_id    TEXT NOT NULL,      -- its log rows (learn_review.run_id): the summary covers both sittings
    answered  INTEGER NOT NULL,   -- answers given so far: the bar's value
    items     TEXT NOT NULL       -- JSON array of the items left, in order
) WITHOUT ROWID;
```

- `items`: `[{"word":"γράφω","kind":"production","retry":false}, …]`: the card's `WordKey.word` (the language is the row's; a session's cards are word cards, so the facet is always '') and whether it is a wrong answer's retry, which does not come back again. Card states are not stored: they are read when the lesson continues.
- **Written** only by the daily session (`ExerciseRunViewModel` with `.session`):
  - at Start, the whole plan, with `answered` 0, before the first question (`saveLesson`);
  - with each answer, in `recordAnswer`'s transaction: the items left after it (its retry appended and the words kept apart, as the run's plan is) and `answered` + 1. So the log and the lesson never disagree: after a crash the lesson continues after the last answer written, and no answer is asked or counted twice. The answer that leaves no item deletes the row in the same transaction;
  - when a question is skipped (a paused card, no meaning in the pair), `saveLesson` without it.
- **Read** by `keptLesson(lang:today:)`: the row when its `day` is today, else nil. A stale row is never offered and the next Start overwrites it (one row per language), so nothing cleans up.
- **Migration from the current state**: the table starts empty. A lesson closed before the update was never stored, so the first Start after the update builds a new lesson, as before. No other table or key changes.
- `clearLearning()` (`-resetData`) deletes its rows. Stop learning a language keeps its row: the pair added again the same day continues the lesson. #73 (iCloud preferences) does not sync it.
- **Size**: one row per language. A session holds at most 30 due cards and 2 × 50 new-word cards, plus their retries: under 20 KB of JSON; with the defaults (10 new words) about 3 KB.

### Scheduling (#157)

`protocol Scheduler { func next(_ card: CardState, outcome: Outcome, today: LearnDay) -> CardState; func isLearned(_ card: CardState) -> Bool }`. `FixedLadder` is the only implementation:

| `step` | 0 | 1 | 2 | 3 | 4 | 5 | 6 |
|---|---|---|---|---|---|---|---|
| Interval (days) | learning | 1 | 3 | 7 | 14 | 30 | 90 |
| Stage shown | New if never answered, else Learning | Every 1 day | Every 3 days | Every 7 days | Every 14 days | Learned | Learned |

- **Wrong**: `step = 0`, `due_day = today`.
- **Right or accent**, when the card is due (`due_day ≤ today`), learning (`step = 0`) or new: `step = min(step + 1, 6)`, `due_day = today + interval(step)`.
- **Right or accent** on a card that is not due: unchanged.
- Every answer sets `last_day = today`.
- `isLearned`: `step ≥ 5`, i.e. an interval of 30 days or more (`FixedLadder.learnedInterval = 30`). A word is learned when both its word cards are.
- `WordStatus` (pure): the stage of each card and of the word, for My words, the Learn button and E10.
- Minimum time from the first right answer to learned: 1 + 3 + 7 + 14 = 25 days.

### New words (#157, #161)

- **Started today** is the number of `learn_word` rows of the chosen language with `introduced_day = today`. Each planner offers at most `newPerDay − startedToday` new words, so the limit is per language.
- **The new pool**, in order, all of the chosen language:
  1. words in learning never answered, not paused, oldest `added_at` first (My words additions, and list words picked by an earlier unfinished session);
  2. then the checked lists' next words: E3's `nextNewWords(in: language, from: learningListIDs, count:, excluding: enrolledKeys(), order: newWordOrder)`. The excluded keys are every key in `learn_word`, paused ones too.
  A picked list word gets its `learn_word` row (with `list_id` = its `listID`, and its content) and two cards when the run starts.
- **The order** is 0130's "Order of new words": per language, levels in order across that language's checked lists, by frequency with each run of 10 places shuffled, or random within each level, fixed per install, language and set of checked lists. E4 only passes the language, the set and the setting `learning_new_order`. Its tests are E3's (`LearningOrderTests`).

### Languages and pairs (#157, #158, #162)

- **The pairs come from the data.** 0237's `PackCatalog.pairs` gives the pairs of the bundle and the catalog: every distinct (`from_lang`, `to_lang`) of the bundle's `dict_metadata` and of `catalog_source`, with meanings language = via, plus the limited pairs of the catalog's `catalog_pair` table (lang, via, meanings: `ell`, `rus`, `eng` in 2.0), each with its dictionaries and the packs it needs (0237, "For E3 and E4"). A limited pair is offered only when its (lang, meanings) pair is, and a pair a dictionary gives replaces a limited one with the same (lang, via). E4 adds the directions of imports whose `imported_sources` has both languages (#208), which need no pack. `und` is never part of a pair. There is no list in code: a later source (a Greek–Russian dictionary in 2.1) turns Greek via Russian into a full pair through the catalog alone.
- `LearningPair (lang, via, meanings)`, with `isLimited` (meanings ≠ via), and `LearningPairs` (pure, `Models/Learning.swift`) replace #157's `LearningLanguages.pickable`. `learning_via` stores the via only; the meanings language always comes from the offered pair.
  - `defaultVia(for lang:, offered:, uiLanguage:) -> String?`: the UI language's ISO 639-3 code when (lang, UI) is offered, limited or not, else `eng` when offered, else the first via by code; nil when the language has no pair;
  - `pair(for lang:, stored: [String: String], offered:, uiLanguage:) -> LearningPair?`: the pair of the stored via when it is still offered, else of the default;
  - `pickerRows(offered:, withLists:, learned:, uiLanguage:, name:) -> [LearningPair]`: the order in Behaviour, the learned languages left out;
  - `vias(for lang:, offered:, uiLanguage:, name:) -> [String]`: the Settings menu, default first, then by name;
  - `sourceOrder(pair:, pairSources:, dictionaryOrder:, enabled:) -> [String]`: the pair's dictionaries (lang → meanings language) in Dictionary Order (enabled first), then the rest of Dictionary Order;
  - `chosen(stored:learned:) -> String?` stays as #157 has it (in `LearningLanguages`, or moved here).
- `LearnViewModel` holds the learned languages (the tabs, in order), the selected one and its `LearningPair`, writes `learning_languages` and `learning_language`, and passes the language and the pair's meanings language to every store call below and to `ExerciseRunViewModel` and `MatchPairsViewModel` (the via goes to E6's and E7's views). The tabs are `PairTabStrip` (Pair tabs, below); #293 deletes the segmented switch `LearningLanguagePicker`, which E10's statistics screen reused. The picker is `LanguagePickerView`, over `LearningPair` rows with their sizes, shown by `LearnView` with no learned language and pushed by "+" and by "Add a language".
- `LearningLanguageService` (in `LearningService.swift`) runs a choice:
  - `learn(_ pair:)` appends the language, writes `learning_via[lang] = via`, enrols its My words (`enrolMyWords`), and starts 0237's `PackService.installPair(lang:via:)`, which installs the pair's missing packs (for a limited pair, those of its (lang, meanings) pair: `ell` for Greek via Russian) and nothing when all are there;
  - `learn(language:)` (Learn on a word, E3's import, E5's and E6's Practise, after their alert) does the same with the language's default pair. Other (`und`) has no pair (`defaultVia` is nil): it is appended alone, with no `learning_via` entry and no install;
  - `setVia(_ via:, for lang:)` (#162) writes `learning_via` and starts the same install;
  - stopping removes the language from `learning_languages` and changes no data; `learning_via` keeps its entry;
  - `reorder(_ languages: [String])` (#293) writes `learning_languages` in the given order when it holds the same languages, else changes nothing (a drag started before another window added or stopped one).
  - #158's protocol `LanguageListsInstalling` (`languagesWithLists`, `installLists(for:)`) becomes `PairPacksInstalling` (`pairs`, `installPair(lang:via:)`), with the same fake in tests.
- The goal and the streak read every language: `answeredCount(on:)` and E10's day counts take no language.

### Store API (#157)

All in `DatabaseService`; every method takes `today` from the caller, so the store reads no clock.

| Method | Does |
|---|---|
| `learnWord(_ key: EntryKey, today:)` | For a word of a learned language. In one transaction: `my_words` insert, a `learn_word` row under `wordKey(for: key)` inserted only when missing (an existing row, such as a paused list word, keeps its content, `translation`, `translation_lang` and `list_id` included), two cards created, or the word's paused cards resumed with their progress. "No" to "Learn Spanish via English?" calls E3's `addToMyWords` instead |
| `enrolMyWords(lang:, today:)` | When a language is chosen: `LearningSQL.enrolMyWords` for that language, in one transaction |
| `stopLearning(_ key: EntryKey)` | In one transaction: every `my_words` row whose key is `wordKey(for: key)` deleted, whatever its source, and every card of that key paused with its progress. Also the My words swipe and "Remove from My words" |
| `learningState(of key: WordKey) -> WordLearningState?` | The word and its cards, paused included; nil when never enrolled. For the Learn button (through `wordKey(for:)`) and #165 |
| `introduce(_ items: [WordListItem], sourceOrder:, today:)` | For list picks, in one transaction: `learn_word` rows with the items' content (`translation_lang` included), list (`listID`) and resolved entry, and two cards each. Retry-safe: `INSERT OR IGNORE` for the word and for each card, so a repeated call keeps the content and progress already stored and only adds a missing card. `sourceOrder` is `LearningPairs.sourceOrder` of the language's pair |
| `meanings(of words: [MeaningQuery], lang:, meaningsLang:, sourceOrder:) -> [WordKey: String]` | The meaning of each word in the pair's meanings language (Meanings). `MeaningQuery (key, lookup, translation, translationLang)`; `lookup` is the headword, else the term. Rule 1 in Swift; for the rest, one read per file that holds a pair dictionary (`word IN (…)` on the entries' word index, chunks of 500). Used by questions, match the pairs, E3's list rows, E5's verbs and E10's hardest words |
| `enrolledKeys() -> Set<WordKey>` | The exclusion set for `nextNewWords`, paused words included |
| `recordAnswer(_ answer: AnswerRecord, today:, scheduler:) -> CardState` | In one transaction: read the card, `scheduler.next`, update the card, set `introduced_day` if NULL, insert the log row (`introduced`, steps), and, from E10 #163, `INSERT OR IGNORE` today's `learn_day` row with the current goal, which #163 adds as a `goal:` argument (0166). #296 adds `lesson: KeptLesson?`: the session's lesson after this answer, upserted in the same transaction, or its row deleted when no item is left; nil (trainers, mistakes, match, the drill) touches no lesson |
| `keptLesson(lang:, today:) -> KeptLesson?`, `saveLesson(_:)` | #296: the tab's lesson of today, read through `read`; the upsert at Start and after a skipped question, a plain `pool.write` |
| `cardStates(_ keys: [CardKey]) -> [CardKey: CardState]` | #296: the current state of a continued lesson's cards; a key without a card is absent |
| `dueCards(lang:, today:, kinds:, limit:) -> [CardState]` | Answered, or the unanswered word card of a started word (`introduced_day` set: a session closed between its two cards), not paused, of `lang`, `due_day ≤ today`, ordered by `due_day`, then `step`. A card of a word that Meanings rule 4 skips in the pair takes no slot: the planner reads further, in pages, until it has `limit` cards or none are left, as for `newPool` |
| `newPool(lang:, limit:) -> [LearnWord]` | Pool part 1. A word that Meanings rule 4 skips in the pair takes no slot: the planner reads past it, in pages, until it has `limit` words with a meaning or the pool runs out. Part 2 does the same with `nextNewWords`, and a skipped list word is not picked, so it gets no row |
| `startedCount(on:, lang:)`, `answeredCount(on:)` | The daily limit, per language; the reminder's "goal met", every language |
| `mistakeCards(since:, lang:) -> [CardState]` | #161: cards of `lang` with a wrong answer since the day and no right answer after it, latest first |
| `distractorCandidates(lang:, meaningsLang:, source:, pos:) -> [Candidate]` | #159: the enrolled words of the language with their meanings in the meanings language, plus a sample of 30 headwords with the same part of speech, read through `read`. The sample comes from the pair dictionary that gave the word's meaning, else from the pair's first dictionary in Dictionary Order; for Other, from the word's own source |
| `clearLearning()` | `-resetData` (DEBUG) |

The records are `LearnDay`, `CardKind`, `CardKey (WordKey, kind, facet)`, `CardState`, `Outcome (right, accent, wrong)`, `LearnWord`, `AnswerRecord (card, exercise, mode, runID, outcome, durationMs, detail)`, `WordLearningState`, `WordStatus`, `LearningPair`, `MeaningQuery`, and, from #296, `KeptLesson (lang, day, runID, answered, items: [LessonItem])` with `LessonItem (card: CardKey, isRetry)`, whose JSON coding is pure (`Models/Learning.swift`). `WordKey`, `WordListID`, `WordListItem` and `NewWordOrder` are E3's (0130).

### Meanings (#159)

`Gloss.short(definition:)` is pure:
1. Drop part-of-speech header lines (`**verb**`) and example lines (`*"…"*`), then strip the remaining `*`.
2. Take the first sense: the text after `1. `, or the first non-empty line.
3. A WordNet-style sense `X — Y` keeps X.
4. Cut at 80 characters, at a space or comma, with "…".

| Entry | Meaning |
|---|---|
| γράφω (El–En · FD) | write |
| σπίτι (El–En · FD) | house, home, habitation |
| γράφω (El–En · WN) | read, say |
| house (WordNet) | a dwelling that serves as living quarters for one or more families |
| house (En–Es · FD) | casalicio, casa |
| house (En–El · FD) | σπίτι (το χτίριο), οίκος, στεγάζω |
| house (En–El · WN) | οικογένεια |
| дом (OpenRussian) | house, home, house-hold |

A word's meaning is in the meanings language of its language's pair (`LearningPair.meanings`: the via, except in a limited pair, where it is English for Greek via Russian), chosen at each question, never stored. Below, "the pair's dictionaries" go from the learned language into the meanings language:
1. its stored `translation`, when it is not empty and `translation_lang` is the meanings language, or '' (an imported list: the user's own translations show in every pair);
2. else `Gloss.short` of its headword (its term, for a word without an entry) in the first of the pair's dictionaries that has it, in Dictionary Order, enabled ones first (`meanings(of:lang:meaningsLang:sourceOrder:)`);
3. Other (`und`) has no pair: rule 1, else `Gloss.short` of its own entry `(source, headword)`, as before pairs;
4. none: the planners skip the word in this pair. It is never deleted, and comes back when the via changes or the pair's pack is installed.

| Word, pair | Meaning | Rule |
|---|---|---|
| γράφω (Greek A1), Greek via English | kyukhin's English translation | 1 |
| γιουβέτσι (Greek A1, no entry), Greek via English | kyukhin's English translation | 1 |
| γράφω (Greek A1), Greek via Russian (limited) | kyukhin's English translation: the meanings language is English | 1 |
| house (English A1), English via Spanish | casalicio, casa | 2, En–Es · FD |
| house (English A1), English via Greek | σπίτι (το χτίριο), οίκος, στεγάζω: a Greek UI's default order puts En–El · FD first (#88). With En–El · WN first it is οικογένεια | 2 |
| house (English A1), English via English | a dwelling that serves as living quarters for one or more families | 2, WordNet |

- The meaning's text runs carry the meanings language (`languageIdentifier`), so VoiceOver reads σπίτι with the Greek voice in English via Greek; in Arabic it keeps its own direction (FSI…PDI, #119).
- Changing the via changes the meanings from the next question when the meanings language changes (Greek via English to via Russian does not); cards and the log are untouched.

### Questions and answers (#159)

- **`AnswerChecker.check(_ typed:, expected:, lang:, mode:) -> Outcome`**, pure:
  - an answer that is empty after trimming is wrong, before any other rule;
  - `normalize`:
    - NFC, trimmed, inner spaces collapsed, lowercased;
    - trailing `. ! ? ;` and the Greek question mark dropped;
    - Greek: σ at a word end becomes ς, ς inside a word becomes σ;
    - one leading article followed by a word dropped on both sides: ell ο, η, το, οι, τα; eng the, a, an, to; spa el, la, los, las, un, una. A lone article is the word itself, so the list words `the`, `a` and `to` are typed as written;
    - the expected `term` matches with and without each parenthesised part (`(ένα) σωρό` → `ένα σωρό`, `σωρό`).
  - `fold`: `normalize`, then NFD without combining marks (accents, Greek dialytika, Arabic harakat), without the Arabic tatweel, with ς as σ, then NFC.
  - Strict: equal after `normalize` → right. Equal only after `fold` → wrong, with the accent hint. Otherwise wrong.
  - Lenient: equal after `normalize` → right. Equal after `fold` → accent, which counts as right. Otherwise wrong.
- **`DistractorPicker.pick(for:candidates:count:rng:)`**, pure:
  - candidates, in order of preference: the word's own list (`list_id`, or else the checked lists of the word's language), then the enrolled words of the language, then the source sample;
  - within that order, the same primary part of speech first (the first label of `pos` or `partOfSpeech`, mapped as #144 maps them);
  - every candidate's meaning is in the same meanings language as the word's (Meanings), so the four options are in one language;
  - a candidate is dropped if:
    - it is the word itself;
    - it has no meaning in the meanings language;
    - its option text folds equal to the answer or to an option already taken;
    - for meanings, one of its comma-separated parts folds equal to a part of the right meaning or of a meaning already taken.
  - Fewer than 3 left: the question shows what there is. None: a production card is typed, and a recognition card is skipped without a log row.
- **`QuestionBuilder`**, pure: card + meaning + candidates + answer mode + generator → `Question` (prompt, prompt language, options, right index, input `choice` or `typed`, `isNew`). The language of a meaning, as prompt or option, is the pair's meanings language.
- Production on rung 0 (new or learning) is always a choice. On rung 1 or higher it is typed, unless the mode is Multiple choice.

### Runs: session, trainer, mistakes (#159, #161; #296)

- **`SessionPlanner`** is pure and returns `[PlannedItem]` (card, exercise):
  - `session(due:newWords:)`: due cards up to 30, then new words in groups of 3 (recognition ×3, then production ×3);
  - `trainer(kind:due:newWords:practice:)`: 10 items. Practice is the answered, unpaused cards of that kind, lowest `step` first, then oldest `last_day`;
  - `mistakes(cards:)`;
  - `requeue`: a wrong item goes to the end once.
  - If two cards of one word end up next to each other, the second swaps with the next card of another word.
- **`ExerciseRunViewModel`** (`@MainActor`) runs a plan:
  - it builds each question just before showing it, with options shuffled by the run's generator;
  - it writes each answer at once with `recordAnswer`, so closing early loses nothing;
  - it reads `LearningClock.today` at each answer, never once per run, so an answer after 4 AM counts for the new day (its log row, `introduced_day`, due day and goal); the plan made at the start stays. `MatchPairsViewModel` and E5's drill do the same;
  - `duration_ms` runs from the question appearing to the answer, capped at 60 s;
  - the summary reads this run's log rows (`run_id`) through E10's `ReviewSummary`, the same function as Today's numbers.
- **Continue lesson** (#296), in `ExerciseRunViewModel` with `.session`:
  - `start()` first reads `keptLesson(lang:today:)`. With one, the run takes its `run_id` (`runID` becomes a `var` set once at start), its `answered` and its items with their current states (`cardStates`; a card that is gone or paused is dropped, as a skipped question is). The bar shows `answered` of `answered` + the items, and "Question 4 of 18". Without one, it plans as before, introduces the list words it picked, then `saveLesson` with the whole plan;
  - before writing an answer, it computes the items left: a wrong item's retry with the card as `FixedLadder.next` leaves it (step 0, due today, answered today), then `separatingWords` from the next item, the same plan it shows. It passes them to `recordAnswer(… lesson:)`. Today's code requeues after the write, with the card the write returns; the result is the same card;
  - the Learn home reads the tab's `keptLesson` with Today's counts: its item count is the button's "N left", and while it exists Start and "All done for today" do not show (`LearnViewModel.lessonLeft: Int?`).
- **End sound** (#300): `RunEndSound.of(answeredBefore:answeredAfter:goal:) -> FeedbackSound` (pure): `goalReached` when `answeredBefore < goal ≤ answeredAfter`, else `lessonComplete`. `answeredBefore` is `answeredCount(on: today)` read when the run (or a match round, or the drill) starts; `answeredAfter` is the count the summary already reads for its goal row. Played when the summary or the round's result appears.
- Views: `ExerciseRunView` in a `fullScreenCover` (close button, progress, question, feedback bar), `RecognitionQuestion`, `ProductionChoiceQuestion`, `ProductionTypedQuestion`, `RunSummaryView`.

### Match the pairs (#160)

- `MatchRound` (pure) picks the 5 words and holds the state: the selection, the matched pairs, and the words with a mistake.
- `MatchPairsViewModel` writes one `recordAnswer` per word when its pair is matched: exercise `match`, kind `recognition`, outcome `wrong` if it had a mistake, `duration_ms` from the previous match, or from the round's start for the first, capped at 60 s like every answer.
- A wrong pair is charged to the word whose tile is in the word column.
- `MatchPairsView`: two `VStack` columns of tiles; the elapsed time shows as `m:ss`.
- #299: `MatchRound.tap` already returns `.mismatched(word, meaning)`, the two tiles' word indexes. `MatchPairsViewModel.mismatch: (word: Int, meaning: Int)?` keeps them until the next tap; `MatchPairsView` shows under the columns the two words' own pairs, "νερό · water" and "γράφω · write" (`match_mismatch`), and VoiceOver announces them after "Wrong".
- #300: `MatchPairsViewModel` plays `pairRight` and `pairWrong` instead of `right` and `wrong`, and the end sound when the round's result appears.

### Feedback (#159; #299, #300)

- `FeedbackPlayer` (in `LearningService.swift`) plays the sounds and decides on the haptics from the settings.
- **Haptics**: the views use `.sensoryFeedback(.success / .error, trigger:)` (iOS 17), returning nil when Haptics is off.
- **Sounds**: short sounds generated in code as WAV data, played by `AVAudioPlayer` on a serial queue of their own, never the main thread: starting the audio output can block for seconds (15 s when the audio system stalls), and the run must not freeze. The audio session category is `.ambient`, set once: the silent switch mutes the sounds and the user's music keeps playing. There is no sound file, so no license and no Xcode step. QA checks that the speaker button (#202) still speaks.
  - Until #300: two tones (right: two rising notes; wrong: one low note, about 0.2 s each).
  - #300: `FeedbackSound` has six cases, `right`, `wrong`, `lessonComplete`, `goalReached`, `pairRight`, `pairWrong`. `FeedbackPlayer.play(_ sound:)` plays any of them when Sounds is on; `play(_ outcome:)` stays for right and wrong. `ToneSynth` (pure, `nonisolated`, in `LearningService.swift`) replaces `TonePlayer.wav`: a Swift port of the voices of `make_sounds.py` (bell, marimba, soft, FM, the pop; notes in sequence and mixed with offsets), 44.1 kHz 16-bit mono, scaled to a 0.7 peak with a 10 ms fade-out, with one recipe per sound, the variant kyukhin picks (Open question 10). `TonePlayer` makes a sound's data and player on its queue at its first play, as today; the longest candidate lasts about 1 s (44,100 samples), a few milliseconds to synthesize. The Python script is not committed: the Swift recipes are the source.
- **What you chose** (#299):
  - `Question.Option` gains `counterpart`: a meaning option's word (its term, without endings), a word option's meaning. `QuestionBuilder` sets it from the `WordChoice` each option comes from, the source sample's included, so every option has one.
  - `AnswerFeedback` (`Equatable`) gains `chosen: ChosenOption?`, a struct of `text` and `counterpart`, set for a wrong choice only; nil for a right answer, a typed answer and "Don't know".
  - `ConjugationQuestion` gains `optionSlots`: for each option, the facet and person of the cell it was taken from (`ConjugationQuestionBuilder` takes each distractor from a cell; a generated θα or να form from its generated cell). The drill's `chosen` counterpart is that slot written as the tense line writes it (`DrillText`): "Aorist · εμείς", "Present · passive · εγώ".
  - `FeedbackBar.lines` returns a third line, `exercise.youChose`, composed and isolated as its other lines are; the bar shows it under the right answer (`exercise_you_chose`) and the announcement reads it last.
- A test seam, `FeedbackSink`, records what would have played.

### Settings keys (#157, UI in #162)

`SettingsService` gains `learning*` accessors on the `KeyValueStore` seam. The keys are added to the overview's Preferences table.

| Key | Values | Default |
|---|---|---|
| `learning_new_per_day` | 0–50 | 10 |
| `learning_daily_goal` | 5–200 | 20 |
| `learning_new_order` | `frequency`, `random` | `frequency` |
| `learning_answer_mode` | `strict`, `lenient`, `choice` | `lenient` |
| `learning_sounds`, `learning_haptics` | `1`, `0`; `learning_sounds` covers the six sounds of #300 | `1` |
| `learning_reminder` | minutes after midnight, absent = off | absent |
| `learning_languages` | JSON array of ISO 639-3 codes: the pair tabs' order (#293). A chosen language is appended, a drag rewrites the array, Stop learning removes the language | absent = none: the picker |
| `learning_via` | JSON object, learned language → via language (ISO 639-3), `{"ell":"eng","eng":"spa"}`; `"ell":"rus"` for the limited Greek via Russian, whose meanings language comes from the catalog's pair, never from this key. Written when a pair is chosen or its via changed; kept when a language is stopped | absent or a pair no longer offered = the language's default via |
| `learning_language` | ISO 639-3, the selected pair tab (the switch's choice before #293) | absent = the first learned language |

- Values outside their range are clamped when read. #73 (iCloud) will sync them with the other preferences.
- **#293 adds no key and no migration.** The tab order is `learning_languages`, which already holds the learned languages in the order chosen, so after the update the tabs show in that order; the selected tab is `learning_language`, the switch's stored choice.
- The checked lists are E3's key, `learning_lists` (#151).
- E3's shuffle seed is in `user_meta` (0130); E4 keeps no seed of its own.

### Reminder (#162)

- `LearningReminder` (in `LearningService.swift`) works through a protocol, `NotificationScheduling`, which `UNUserNotificationCenter` implements in the app and a fake implements in tests.
- `reschedule(today:goalMetToday:)` removes every pending `learning.reminder.<day>` request. Then, if the reminder is on and authorised, it adds one request per day for today and the next 6 days, at the set time. Today is skipped if the goal is met or the time has passed. The content is localised in the in-app language (`LocalizationManager.localizedBundle`).
- It runs on every return to `.active` (the scene-phase hook in `DictApp.swift`), on a reminder or goal change, and when an answer reaches the goal (`answeredCount(today)` crosses it).
- Turning the reminder on calls `requestAuthorization([.alert, .sound])`. Nothing else in the app asks.
- A notification tap sets `AppRouter.shared.selectedTab = .learn`. `AppRouter` is a new `@MainActor ObservableObject`, and `ContentView`'s `TabView` gets a `selection` bound to it.

### Tabs, Learn button, My words (#158)

- `ContentView`: tabs `search`, `learn` (`graduationcap`, `learn_tab`), `history`, `settings`. `BookmarksView` and `BookmarksViewModel` are replaced by `LearnView` and `LearnViewModel`.
- **My words, interim**: today's Bookmarks list moves as `MyWordsView` behind the Learn home's My words row, its swipe now calling `stopLearning`. When E3's #154 lands, the row opens E3's list screen for `my-words` instead, and `MyWordsView` goes. E3's swipe on My words calls `stopLearning` too (Depends on E3).
- `DefinitionViewModel`: `isBookmarked` and `toggleBookmark` become `learning: WordLearningState?` and `toggleLearn()`, which calls `learnWord` or `stopLearning`. The state is looked up through `wordKey(for: EntryKey(entry))`.
- Removed: the Bookmarks tab and its view, `bookmarks.*`, `tab.bookmarks`, `definition.a11y.addBookmark` and `removeBookmark`, `settings.learningMode.section`, `common.comingSoon`. The `DatabaseService` My words methods stay (E3's lists use them).
- UI tests:
  - `TabBarPage` gets the case `learn` (index 1, symbol `graduationcap`) and drops `bookmarks`. Indexes shift: History 2, Settings 3.
  - `BookmarksPage` becomes `MyWordsPage`, `BookmarkFlowTests` becomes `MyWordsFlowTests`.
  - The 10 suites that use the Bookmarks tab or `bookmark_button` are updated: ArabicLocalization, BookmarkFlow, DictionaryFilter, GreekLocalization, HistoryFlow, ImportDictionary, iPadSpecific, Navigation, ReadingMode, SpanishLocalization. So are the helpers `DefinitionPage`, `AccessibilityIdentifiers` and `TestData`, and the unit tests `testBookmarkCycle` and `testStarAndBookmarksTabUseMyWords`.

### Pair tabs (#293) and one language per tab (#295)

- **Storage**: the tab order is `learning_languages` and the selected tab `learning_language` (Settings keys): no new key, no migration.
- **`LearnViewModel`**: `tabs: [PairTab]` (lang, its `LearningPair` from `LearningLanguageService.pair(for:)`, nil for Other), `select(_:)` as today, `move(_ lang: String, to index: Int)` (through `reorder`; the selection stays), `stop(_ lang: String)` (`LearningLanguageService.stop`, then a reload that selects the first tab), and the home of the selected language only, as `loadHome` reads it now. Logic stays out of the views: the strip renders `tabs` and calls these.
- **`PairTabStrip`** (`LearnView.swift`), the strip:
  - a `.safeAreaInset(edge: .top)` of the home `List`, so it stays while the list scrolls and pushed screens do not show it;
  - capsule buttons in the style of Search's dictionary chips (0146), the selected one filled, labels on one line;
  - a custom `Layout`, `PairTabStripLayout`, measures the tabs, "+" and "…" and places what the pure `PairTabFit.fit(tabWidths:addWidth:moreWidth:available:selected:) -> PairTabFit` (`Models/Learning.swift`) returns: the visible tab indexes, the hidden ones in order, and whether "+" shows. Every tab and "+" when they fit; else the most tabs that fit before "…", with the selected tab in the last visible place when it would be hidden; the selected tab alone, cut, before "…" when nothing else fits;
  - drag: `.draggable` with the language code and `.dropDestination(for: String.self)` on each tab; a drop on a tab's leading half puts the dragged language before it, on its trailing half after it (mirrored in Arabic), through `move`;
  - long press: `.contextMenu` with "Stop learning" (`learn_pair_tab_stop`), then Settings' alert. iOS turns the long press into a drag when the finger moves, so the menu and the drag share it;
  - VoiceOver: the strip is `.accessibilityElement(children: .contain)` with the `.isTabBar` trait; a tab has `.isSelected` when selected and the `accessibilityActions` "Move earlier", "Move later" and "Stop learning".
- **"+"** pushes `Route.addPair`: `LanguagePickerView` with `LearningPairs.pickerRows(… learned: learned …)`, as "Add a language" does. Choosing calls `LearningLanguageService.learn(_:)` (appended, selected, its install started), then pops to the home.
- **"…"** presents `PairOverflowSheet` (`.sheet`, `.medium` detent): a `List` of the hidden pairs, then "Add a language" (`learn_pair_overflow_add`), which dismisses and pushes `Route.addPair`. A pair selects its tab and dismisses.
- **The home**, per tab (#295): Today, Practise mistakes, Trainers (the three trainers only, with their "Learn a few words first" footer; E5's row and its extra section go), Grammar (0133's `learn_grammar_row` and, for `ell`, E5's `learn_trainer_conjugation`; hidden when the language has no topic and no drill), Lists, My words, Statistics.
- **Pushed screens take the tab's language**:
  - `WordListRoute` carries it: `.allLists(lang)`, `.newWordsFrom(lang)`, `.list(WordList, lang)`. `WordListsView(lang:)` and `NewWordsFromView(lang:)` show that language's lists (`WordListsViewModel.sections(… learned: [lang] …)`); Settings pushes `NewWordsFromView(lang: nil)`, every learned language, as today (0130);
  - My words: the row counts the `myWordsEntries()` whose `item.key.lang` (their `WordKey`) is the tab's language, with no extra read, and its list screen keeps the same items (0130);
  - `StatisticsView(lang:)` (0166).
- The goal ring and the streak are read once per home load, as now, for every language.

### Test seams

- `LearningClock` (`now`, `calendar`, `today`) is injected into the view models; `today` is the local date of `now`, or the day before when the local hour is under 4, computed with `calendar` (`component(.hour, from:)`, `date(byAdding: .day, …)`), never by subtracting 4 hours: on a daylight-saving change day the two differ for an hour. The store takes `today` as an argument.
- `InMemoryKeyValueStore`, a `FakeNotificationCenter` and a `FeedbackSink`.
- DEBUG launch arguments:

| Argument | Effect |
|---|---|
| `-resetData` | Also clears the learning tables, the `learning_*` keys and pending reminders |
| `-learningFixture <name>` | After the reset, writes a named fixture relative to today. `myWords5` (#158): γράφω, σπίτι, νερό, καλός, είμαι in My words, new. `due` (#159): the same words due on rungs 1–3, plus one learned word. `mistakes` (#161). `bilingual` (#158): γράφω and σπίτι due in Greek, house and water due in English. `stats` (E10, see 0166). Each fixture also sets `learning_languages` to its languages, each with its default via in `learning_via` |
| `-learningLanguages <lang[:via],…>` | Sets `learning_languages`, and `learning_via` for the items with a via (`ell,eng:spa`), skipping the picker |
| `-learningSeed <n>` | Fixes the option order and the distractors |
| `-learningAnswerHints` | The right option or tile gets the accessibility value `answer`, so a UI test can answer right or wrong on purpose |
| `-learningLists <id,…>` | Sets `learning_lists`, until E3's New words from can |

- Learning UI suites that log heavily set `OS_ACTIVITY_MODE=disable` (#125).

### Identifiers

| Element | Identifier |
|---|---|
| Tab | `learn_tab`; on iPadOS 26 the symbol `graduationcap` |
| Learn home | `learn_view`, `learn_due_count`, `learn_new_count`, `learn_start_button`, `learn_continue_button` (#296; value: the items left), `learn_all_done`, `learn_mistakes_row`, `learn_trainer_recognition`, `learn_trainer_production`, `learn_trainer_match`, `learn_my_words_row`, `learn_choose_lists`, `learn_new_words_from_row` (the Learning from row since #298; value: the checked lists), `learn_import_list`, `learn_add_words_hint`. `learn_language_switch` goes with #293 |
| Pair tabs (#293) | `learn_pair_tabs` (the strip), `learn_pair_tab_<lang>` (label: the pair name; value `selected` on the selected tab), `learn_pair_tab_add`, `learn_pair_tab_more`, `learn_pair_tab_stop` (the menu item), `learn_pair_overflow` (the sheet), `learn_pair_overflow_row_<lang>`, `learn_pair_overflow_add` |
| Language picker | `language_picker`, `language_picker_row_<lang>-<via>` (`language_picker_row_ell-eng`, `language_picker_row_eng-spa`), `language_picker_size_<lang>-<via>` (only when something is to download), `language_picker_limited_<lang>-<via>` (a limited pair's warning, `language_picker_limited_ell-rus`) |
| Definition | `learn_button` (replaces `bookmark_button`) |
| My words | `my_words_list`, `my_words_item_<word>` |
| Run | `exercise_view`, `exercise_close`, `exercise_progress`, `exercise_prompt`, `exercise_new_badge`, `exercise_option_<0…3>`, `exercise_answer_field`, `exercise_check`, `exercise_dont_know`, `exercise_feedback` (value `right`, `accent`, `wrong`), `exercise_you_chose` (#299, also in the drill), `exercise_continue`, `run_summary`, `run_summary_done` |
| Match | `match_view`, `match_word_<0…4>`, `match_meaning_<0…4>`, `match_timer`, `match_mismatch` (#299), `match_next_round`, `match_done` |
| Settings | `settings_learning_languages`, `learning_language_row_<lang>`, `learning_language_via_<lang>` (value: the via code; a menu with two or more pairs), `learning_language_limited_<lang>` (the warning of a limited pair), `learning_language_stop_<lang>`, `learning_language_add`, `settings_learning_new_per_day`, `settings_learning_new_words_from`, `settings_learning_goal`, `settings_learning_order`, `settings_learning_answer_mode`, `settings_learning_sounds`, `settings_learning_haptics`, `settings_learning_reminder`, `settings_learning_reminder_time` |

### Strings

- About 90 new keys, in all 5 languages, written by the implementing agent:
  - `tab.learn`;
  - `learn.*` (home, empty states, trainers, My words);
  - `stage.*`;
  - `exercise.*` (prompts, badge, field, buttons, feedback);
  - `run.summary.*`;
  - `match.*`;
  - `settings.learning.*`;
  - `reminder.*`.
- Counts use the catalog's plural variants ("%lld words due": one/other; Russian one/few/many/other; Arabic zero/one/two/few/many/other).
- The production prompt, the pair tabs and the pair names name languages with the existing `language.*.name` keys; `und` uses E3's "Other". Until #293 the switch's VoiceOver label was `learn.language` ("Learning language"). In Arabic a pair name is composed, so it starts with U+200F (#119).
- "Choose lists" is `learn.chooseLists`; the Learning from rows on the Learn home and in Settings reuse E3's `newWordsFrom.title`, whose text becomes "Learning from" in #298 (0130).
- #292 and #300 (English; plural variants where a count shows; the implementing agent writes all five languages):

| Key | en |
|---|---|
| `learn.tabs.more` | More languages (the "…" item's VoiceOver label) |
| `learn.tabs.moveEarlier`, `learn.tabs.moveLater` | Move earlier · Move later |
| `learn.continueLesson` | Continue lesson · %lld left |
| `exercise.youChose` | You chose: %1$@ · %2$@ |

- Reused by #293: `settings.learning.addLanguage` ("+" and the sheet's last row), `settings.learning.stopLanguage` (the menu item), its `.title` and `.message` (the alert), `settings.learning.languages` (the sheet's title), `learn.viaLanguage` (the tab name: the language's name, " · ", "via Russian"; the separator is not translated). `learn.language`, the switch's label, goes.
- Languages (English; the alerts' Yes and No reuse the catalog's existing buttons):

| Key | en |
|---|---|
| `learn.picker.title`, `learn.picker.withLists` | Which language do you want to learn? · With word lists |
| `learn.pair`, `learn.viaLanguage`, `learn.picker.download` | %1$@ via %2$@ ("Greek via English") · via %@ · %@ to download |
| `learn.pair.limited` | Words are practised in %@. (the meanings language; a limited pair's warning in the picker, in Settings and as the "Learn %@ via %@?" alert's message; ru "Слова тренируются на английском.", written for all 5 languages by the implementing agent) |
| `learn.importList`, `learn.addWordsHint` | Import a list · Add words with Learn on a word's screen. |
| `learn.learnLanguage.title` | Learn %1$@ via %2$@? (the pair; also E3's import and E5's and E6's Practise) |
| `settings.learning.languages`, `.addLanguage`, `.stopLanguage`, `.via` | Languages · Add a language · Stop learning · Via |
| `settings.learning.stopLanguage.title`, `.message` | Stop learning %@? · Your progress is kept. |
| `definition.a11y.removeFromMyWords` | Remove from My words |
- `testEveryCatalogKeyIsTranslatedInEveryShippedLanguage` covers them. The keys listed under "Removed" go.

### Code map and the Xcode step

| Path | Change |
|---|---|
| `Models/Learning.swift` (new) | Pure: `LearnDay`, `CardKey`, `CardState`, `Outcome`, `Scheduler`, `FixedLadder`, `WordStatus`, `LearningPair`, `LearningPairs` (#157); `Gloss`, the meaning rule, `MeaningQuery`, `AnswerChecker`, `DistractorPicker`, `QuestionBuilder`, a seeded SplitMix64 generator for option order (#159); `SessionPlanner` (#161); `MatchRound` (#160) |
| `Services/LearningService.swift` (new) | `LearningClock`, `LearningLanguageService` (#158), `FeedbackPlayer` (#159), `LearningReminder`, `NotificationScheduling`, `AppRouter` (#162) |
| `Services/DatabaseService.swift` | Migration `131-1-learning` with `translation_lang`, the store API with `enrolMyWords` (#157), `meanings(of:lang:meaningsLang:sourceOrder:)` and `distractorCandidates(meaningsLang:)` (#159), `clearLearning`, DEBUG fixtures. `LegacyMigration` is not changed |
| `Services/SettingsService.swift` | `learning*` accessors, `learning_via` among them (#157) |
| `ViewModels/LearnViewModel.swift` (renamed from `BookmarksViewModel.swift`) | `LearnViewModel` (#158), `ExerciseRunViewModel` (#159, #161), `MatchPairsViewModel` (#160) |
| `Views/LearnView.swift` (renamed from `BookmarksView.swift`) | `LearnView`, `LanguagePickerView`, `LearningLanguagePicker` (deleted by #293), the interim `MyWordsView` (#158), the sections the later tickets add; #293's `PairTabStrip`, `PairTabStripLayout`, `PairOverflowSheet` |
| `Views/ExerciseView.swift` (new) | Run, questions, feedback bar, summary (#159, #161), `MatchPairsView` (#160) |
| `ViewModels/DefinitionViewModel.swift`, `Views/DefinitionView.swift` | The Learn button (#158) |
| `ViewModels/SettingsViewModel.swift`, `Views/SettingsView.swift` | The Learning section with its Languages screen (#162) |
| `Views/ContentView.swift`, `DictApp.swift` | Tabs and `AppRouter` (#158, #162); reminder hooks, `-resetData`, the DEBUG arguments |
| `Resources/Localizable.xcstrings` | The keys |
| `DictAppTests/DictAppTests.swift` | The unit classes in the test plan |
| `DictAppUITests/…` (synchronized folder, no Xcode step) | `LearnPage`, `MyWordsPage`, `ExercisePage`, `MatchPairsPage`; the suites in the test plan |
| `docs/specs/0000-overview.md` | Tabs, Screens, Preferences, Database, Test plan. 0129 is not changed by E4 |

- **Xcode step, one batch for E3, E4 and E10**, in its own PR merged before #151 and #157 (Decisions, 2026-11-04). All files go in the app target, empty, in `DictApp/DictApp/`:
  - rename `Views/BookmarksView.swift` to `Views/LearnView.swift`, and `ViewModels/BookmarksViewModel.swift` to `ViewModels/LearnViewModel.swift`;
  - add, for E4: `Models/Learning.swift`, `Services/LearningService.swift`, `Views/ExerciseView.swift`;
  - add, for E10: `Views/StatisticsView.swift`;
  - add, for E3 (0130): `ViewModels/WordListsViewModel.swift`, `Views/WordListsView.swift`.
  That is 2 renames and 6 new files. No later ticket of the three epics needs a step.
- Without the step (it was the alternative to Open question 7), the same code would go into `Models.swift`, `ReviewRequestService.swift` and the two Bookmarks files.
- Display name and identity are unchanged (`INFOPLIST_KEY_CFBundleDisplayName = LibreDict`). There is no new dependency, entitlement or Info.plist key: local notifications need none, and `Charts` (E10), `UserNotifications` and `AVFoundation` are system frameworks.
- **Layering**: SQL stays in `DatabaseService`. Scheduling, ordering, planning, answer checking and meanings are pure, tested without a database. Views render the questions and states they are given.
- **#292 and #300** add no file, so no Xcode step; the display name stays `LibreDict`, with no new dependency, entitlement or Info.plist key:

| Path | Change |
|---|---|
| `Models/Learning.swift` | `PairTabFit` (#293); `KeptLesson`, `LessonItem` and their JSON (#296); `Question.Option.counterpart`, `ConjugationQuestion.optionSlots` (#299); `RunEndSound` (#300) |
| `Services/LearningService.swift` | `LearningLanguageService.reorder` (#293); `FeedbackSound`'s six cases, `FeedbackPlayer.play(_ sound:)`, `ToneSynth` (#300) |
| `Services/DatabaseService.swift` | Migration `292-1-kept-lesson`, `keptLesson`, `saveLesson`, `recordAnswer(… lesson:)`, `cardStates`, `clearLearning` (#296) |
| `ViewModels/LearnViewModel.swift` | `LearnViewModel` tabs, `move`, `stop`, `lessonLeft` (#293, #295, #296); `ExerciseRunViewModel` continue and `chosen` (#296, #299); `MatchPairsViewModel` mismatch and sounds (#299, #300); `ConjugationRunViewModel` `chosen` (#299); `StatisticsViewModel(lang:)` (0166); `GrammarTopicsViewModel` layout (0133, #297) |
| `Views/LearnView.swift` | The strip, the overflow sheet, the home's sections, the Continue button, the Grammar section with Conjugation; `LearningLanguagePicker` deleted |
| `Views/ExerciseView.swift` | The "You chose" line, the mismatch line, the end sound on the summary and the round's result |
| `Views/WordListsView.swift`, `ViewModels/WordListsViewModel.swift` | The tab's language on the Lists, list and Learning from screens; the Learning from row's value (0130) |
| `Views/StatisticsView.swift` | No switch (0166) |
| `Resources/Localizable.xcstrings` | The keys above, 0130's and 0133's |

### Tickets, order and sizes

Sizes are pipeline days: development, QA on the four simulators, review and the daily merge. The critical path is lists → #157 → #159 → #161 → E10 #164.

| Ticket | Scope | Needs | Size | Stream |
|---|---|---|---|---|
| #157 | Migration (with `translation_lang`), enrolment of a chosen language's My words, `FixedLadder`, `WordStatus`, the store API with its language filters, `LearningPairs` with limited pairs (`meanings`), the settings keys with `learning_via`. Unit tests only, no UI | Approval, the Xcode step; `WordKey` and `wordKey(for:)` from E3 #151, or added here | M, 2.25 | A (data) |
| #158 | Tabs, the pair picker (with a limited pair's warning) and `LearningLanguageService`, Learn home (language switch, Today counts and empty states, My words), the Learn button with "Learn %@ via %@?", `MyWordsView`, Bookmarks removed, 10 UI suites updated | #157; 0237's `PackCatalog.pairs` and `installPair(lang:via:)` | L, 4.25 | B (UI) |
| #159 | Meanings in the meanings language (`meanings(of:lang:meaningsLang:sourceOrder:)`), answer checking, distractors in the meanings language, questions, the run views, feedback, the Recognition and Production trainers | #157; UI tests after #158 | L, 2.75 | C (UI) |
| E10 #163 | Aggregates, goal, streak, `ReviewSummary` (0166) | #157 | M, 1 | A (unit only) |
| #161 | The session (Start), new words from the checked lists, requeue, summary, mistakes practice | #159, #163, E3 #151 (`nextNewWords`, `entry(for:sourceOrder:)`) | M, 1.5 | C |
| #162 | Settings section with Languages (add, stop, change the via), reminder, `AppRouter` | #158, #163 | M, 2.25 | B |
| #160 | Match the pairs | #159 | M, 1 | B or C, last |

- **Calendar** (2 UI streams and 2 data streams from 2026-11-04; everything here done by 11-20, Decisions). The order stands:
  1. review and the Xcode step;
  2. #157;
  3. #158, #159 and #163 in parallel;
  4. #161, #162 and E10 #164 / #165;
  5. #160;
  6. the checkpoint, which moves with the work instead of cutting it.
- #158 merging also unblocks E3's #154, which needs the Learn tab (0130).
- **This is tight.** After #157, E4 and E10 need about 15 UI-stream days. E3's #154 and #155 need 6.75 more (0130's sizes) and E5's #168 about 2.25: about 24 stream-days, 12 days with two streams. The limited Greek via Russian adds 0.5 (kyukhin, 2026-11-04): #157 +0.25 (`LearningPair.meanings`, the catalog's limited pairs, the default via), #158 +0.25 (the warning in the picker and the alert); #159 and #162 only pass the meanings language and reuse the warning. Learning per language added about 1.5 days (0.5 each to #157, #158 and E10 #164), choosing languages about 1 (0.75 to #158, 0.25 to #162), and learning pairs 2.75 (kyukhin, 2026-11-04): #157 +0.5, #158 +0.75, #159 +0.75, #162 +0.5, E10 #164 +0.25. #157, #158 and #159 are already built on their branches, so for them this is rework before they merge. The dates are to be replanned with #237 (Decisions).
- **If the checkpoint slips, nothing is cut**: the release date moves (kyukhin, 2026-11-04, Decisions). #160, the reminder, E10's streak calendar and per-tense block and #165 all ship in 2.0.

**Revision #292 and #300** (due 2026-11-19, submission 2026-11-25). Estimates in pipeline days, as above:

| Ticket | Scope | Needs | Size |
|---|---|---|---|
| #293 | The strip, "+", "…" and its sheet, drag, long press and its VoiceOver actions, `reorder`, `PairTabFit`; `LearningLanguagePicker` and the switch's tests go | Approval | M–L, 2 |
| #295 | The home's sections per tab, Grammar with Conjugation, the tab's language on Lists, Learning from, My words and Statistics (0130, 0166) | #293 | M, 1.25 |
| #296 | `learn_lesson`, the continued lesson, the Continue button | Approval | M, 1.25 |
| #297 | The Grammar list (0133) | Approval | S, 0.25 |
| #298 | "Learning from" and its value (0130) | Approval; merges after #295 when both touch the Lists section | S, 0.5 |
| #299 | "You chose" in the runs, the drill and match the pairs | Approval | M, 1 |
| #300 | The six sounds | Approval and kyukhin's pick (Open question 10) | S–M, 0.75 |

- #293 first, then #295 on it; #296, #297, #299 and #300 run beside them. #293, #295, #296 and #298 all change `LearnView.swift`, so each rebases on the one merged before it.

## Test plan

Unit classes go in `DictAppTests.swift`. Async tests, and classes that are mostly async, are `@MainActor` (#229). Database classes use a temp user database through `setup(userPath:dictionaryURL:)`, with `TestDictionary.make(rows:metadata:)` or the bundled file. UI suites run one per `xcodebuild` run on the four-simulator matrix, with the app uninstalled in between, after `-resetData`.

| Acceptance criterion | Test |
|---|---|
| #131, #161: "Learn this list": due cards first, then up to 10 new words by frequency | Unit `SessionPlannerTests.testDueCardsComeBeforeNewWords`, `testNewWordsStopAtTheDailyLimit` (limit 10, 4 started today → 6), `testDueCardsCappedAt30` (a due card with no meaning in the pair takes no slot: the next due card fills it); `LearningStoreTests.testNewPoolTakesMyWordsFirstThenTheCheckedLists` (fake E3 lists), `testIntroduceIsAtomicAndRetrySafe` (a failure after the first card leaves no row; a second call changes nothing; a word with one card gets the other, its progress kept), `testIntroduceStoresTheListContent` (term, endings, translation, list id from `listID`, the entry resolved through Dictionary Order). UI `SessionFlowTests.testSessionDueThenNew` (`-learningFixture due`, `-learningLists ky-ell-a1`: the 4 due cards, then new words with `exercise_new_badge`) |
| 0130 (2026-11-03): with no list checked, the Learn home offers "Choose lists"; it and Settings open New words from | UI `LearnTabTests.testChooseListsWhenNothingToLearn` (`-learningLanguages ell`, the Greek lists installed: Today reads "Choose lists or tap Learn on a word"; `learn_choose_lists` opens `new_words_from`; after checking Greek A1 the Lists section shows it and `learn_new_words_from_row`), `LearningSettingsFlowTests.testNewWordsFromOpensTheScreen` (`settings_learning_new_words_from` opens `new_words_from`). Unit `LearnViewModelTests.testEmptyStateFollowsTheCheckedLists` (no words and an empty set: the empty state; one list checked: Start) |
| 0130: list words without an entry are learned; a deleted list keeps its words in learning | Unit `LearningStoreTests.testStandaloneWordUsesItsTranslation` (no `source`; the meaning is the list's, the distractors come from the language's first dictionary), `testDeletedListKeepsItsWords` (the list deleted through E3: cards, content and log unchanged; the word is still asked) |
| #131, #157: two cards per word with their own intervals; a wrong answer returns the card to learning; "learned" when both reach 30 days | Unit `LearningSchedulerTests` (pure): `testRightAnswersClimbTheLadder` (1, 3, 7, 14, 30, 90, then 90), `testWrongReturnsToLearningFromAnyStep`, `testRightOnACardNotDueChangesNothing`, `testAccentCountsAsRight`, `testLearnedNeedsBothCardsAt30Days`, `testTwentyFiveDaysToLearned`; `LearningStoreTests.testLearnWordCreatesTwoCards`, `testAnswerMovesOnlyItsCard`, `testRecordAnswerIsOneTransaction` (card, `introduced_day`, log row together; from #163 the day's goal too) |
| #157: new words by frequency with a light shuffle; "random" works; daily limit respected | The order itself: E3's `LearningOrderTests` and `WordListDataTests.testGreekA1FirstTwentyHoldTheFrequentVerbs` (0130). E4: `LearningStoreTests.testNewWordsAskE3WithTheSettingAndEveryEnrolledKey` (the checked lists and the order setting are passed; paused keys are excluded, so a stopped word never returns), `testStartedTodayCountsWordsNotCards`; `SessionPlannerTests.testNewWordsStopAtTheDailyLimit` |
| #157: a learning day starts at 4 AM | Unit `LearningClockTests.testDayStartsAtFourAM` (03:59 is the day before, 04:00 is today, also on a daylight-saving change day), `ExerciseRunViewModelTests.testRunAcrossFourAMUsesEachAnswersDay` (a fake clock moves from 03:59 to 04:01 between two answers: the two log rows carry the two days, and a word first answered after 04:00 gets the new `introduced_day`) |
| #157: every answer is logged; unit tests for scheduling, grading and new-word selection | Unit `LearningStoreTests.testEveryAnswerIsLogged` (one row per answer, with outcome, exercise, mode, run, steps, `introduced` exactly once per word); the classes above and below |
| #157, #129: data only in the user database; offline | Unit `LearningStoreTests.testLearningTablesAreInTheUserDatabase` (no `learn_*` name in `dict`; a write to `dict` still fails), `testEnrolKeysEqualWordKeyFor` (the enrol statement's SQL key equals `wordKey(for:)` for every catalog source, its pack installed or not (not installed: the catalog's language, never `und`), an import with a language and one without); review: no networking API in the diff |
| #131, #158: after upgrading from 1.x, former bookmarks are in My words and in learning (kyukhin, 2026-11-03: in learning once their language is chosen) | Unit `LegacyMigrationTests` as on master (0129). `LearningStoreTests.testMigrationEnrolsNothing` (a database at `129-1-core` with 3 My words, then migrated: no `learn_word` rows), `testChoosingALanguageEnrolsItsMyWords` (the 1.4.0 fixture moved, then Greek chosen: its Greek bookmarks get cards and come first among new words, the others get none; γράφω in My words from El–En · FD and El–En · WN gives one word with two cards; choosing Greek again adds nothing). QA: a real 1.4.0 → 2.0 upgrade on the simulator, as in #139 QA: the bookmarks are in My words, the Learn tab shows the picker, and after choosing Greek the first session offers the Greek bookmarks |
| #158 (kyukhin, 2026-11-03): learning a language is explicit | UI `LearnTabTests.testChooseGreekOffersItsLists` (fresh install: `language_picker`; `language_picker_row_ell-eng`, its pack installed as 0237's tests do; "Choose lists" opens `new_words_from` with Greek A1, A2 and B1 only), `testLanguageWithoutListsOffersImportAndLearn` (Spanish via English: `learn_import_list` and `learn_add_words_hint`, no "Choose lists"), `MyWordsFlowTests.testLearnOnANewLanguageAsks` (`-learningLanguages ell`, English UI: Learn on "house" asks "Learn English via English?"; No: no English tab; Learn on "water", Yes: the tabs read Greek · via English, English · via English), `LearningSettingsFlowTests.testStopAndResumeALanguage` (`-learningFixture bilingual`: stop English, its tab and the English lists go; add English again: its tab, last, and its 2 due words return). Unit `LearningLanguageServiceTests.testChooseEnrolsAndInstalls` (a fake `PairPacksInstalling`), `testStopChangesNoData` (`learning_via` kept), `DefinitionViewModelLearnTests.testNoOnlyAddsToMyWords` |
| kyukhin 2026-11-04: learning is chosen as a pair; only pairs with a dictionary; one via per learned language, changeable; the via decides meanings and packs, never cards | Unit `LearningPairsTests` (pure): `testOfferedPairsFollowTheDictionaries` (2.0's nine dictionaries give the seven full pairs of Behaviour; no English via Russian or via Arabic; a made-up `ell` → `rus` source makes Greek via Russian a full pair with Russian meanings, replacing the limited one; `und` gives none), `testDefaultViaIsTheUILanguageElseEnglish` (Spanish UI: English via Spanish, Greek via English; Greek UI: English via Greek; Russian and English UI: English via English; Russian UI: Greek via Russian, limited; Arabic UI: Greek via English), `testStoredViaFallsBackWhenNotOffered`, `testPickerRows` (languages with lists first, the default via first, learned languages left out), `testSourceOrderPutsThePairFirst`. `LearningStoreTests.testMeaningFollowsTheVia` (the rows of the table in Meanings; a via change gives the other meaning and leaves cards and log rows unchanged), `testListTranslationOnlyInItsLanguage` (a test pack with an `ell` → `rus` dictionary: via Russian shows its Russian meaning, never kyukhin's English; a word without one is skipped by `newPool` and the planners and kept, and takes no new-word slot: with a limit of 2 and the first word skipped, the next two words come), `testImportedTranslationShowsInEveryPair`, `testIntroduceStoresTheTranslationLanguage`, `testDistractorsAreInTheVia` (English via Spanish: four Spanish options). `LearningLanguageServiceTests.testChoosingAPairStoresItsViaAndInstallsItsPacks` (English via Greek: `eng-lists` and `ell`; Greek via English: `ell`; English via English: `eng-lists`; all installed: no install), `testChangingTheViaKeepsTheCards`. UI `LearnTabTests.testPickerOffersPairs` (fresh install, Spanish UI: `language_picker_row_eng-spa` before `…_eng-eng` and `…_eng-ell`, no `…_eng-rus`; a size under the rows with missing packs; English via Spanish with `-packDownloads ok -learningAnswerHints`: the Recognition trainer's options are Spanish), `LearningSettingsFlowTests.testChangeTheVia` (`-learningLanguages eng:eng`, `-learningFixture due`: change English to via Spanish in `learning_language_via_eng`; the next recognition question's right option reads "casalicio, casa"; `learn_due_count` unchanged) |
| kyukhin 2026-11-04: Greek via Russian is a limited pair: a warning in its row, meanings in English, the Russian UI's default for Greek | Unit `LearningPairsTests.testLimitedPairFromTheCatalog` (a `catalog_pair` row `ell`, `rus`, `eng` gives Greek via Russian with `meanings` `eng` and `isLimited`; without the (ell, eng) pair it is not offered; `vias(for: "ell")` lists English, then Russian), `LearningStoreTests.testLimitedPairMeaningsAreInTheMeaningsLanguage` (Greek via Russian: γράφω's meaning and its three distractors are English, as via English; switching Greek between via English and via Russian changes no meaning and no card), `LearningLanguageServiceTests.testLimitedPairInstallsItsMeaningsPack` (Greek via Russian: `ell` only). UI `LearnTabTests.testLimitedPairShowsItsWarning` (`-AppleLanguages (ru)`, fresh install: `language_picker_row_ell-rus` is Greek's first row, with `language_picker_limited_ell-rus`; `language_picker_row_ell-eng` has none; choose it with `-installPacks ell -learningAnswerHints`: the Recognition trainer's options are English), `MyWordsFlowTests.testLearnGreekInRussianUIWarns` (Russian UI, nothing learned: Learn on γράφω asks for Greek via Russian with the warning as the alert's message), `LearningSettingsFlowTests.testLimitedPairWarningInSettings` (`learning_language_limited_ell` with Greek via Russian, gone after switching to via English) |
| #158 (kyukhin, 2026-11-03): learning is per language: a tab per language since #293; session, trainers and mistakes in the chosen language; the new-word limit per language; goal and streak shared | Unit `LearningLanguagesTests` (pure): `testStoredChoiceFallsBackToTheFirstLearned`, `testNoneLearned`; `LearningStoreTests.testDueCardsOfOneLanguage`, `testNewPoolOfOneLanguage`, `testDailyLimitPerLanguage` (10 Greek words started today: English still offers 10), `testMistakesOfOneLanguage`, `testAnsweredCountIsEveryLanguage`. UI `PairTabsTests.testTabsSwitchTheHome` (replaces `LearnTabTests.testLanguageSwitch`; `-learningFixture bilingual`: two tabs; the English tab: `learn_due_count` reads 2 and the Recognition trainer asks only English words; the selection survives a relaunch), `testOneTabAndAdd` (replaces `testNoSwitchWithOneLanguage`; `-learningFixture due`: one tab, then `learn_pair_tab_add`) |
| #158: four tabs: Search, Learn, History, Settings | UI `LearnTabTests.testFourTabsInOrder` (iPhone tab bar and the iPadOS 26 strip), `NavigationTests` updated (`testLearnTabNavigation` replaces `testBookmarksTabNavigation`) |
| #158: "Learn" on Definition adds the word to My words and to learning; tapping again removes it | Unit `DefinitionViewModelLearnTests.testToggleLearnAddsThenPauses` (My words row, cards, `suspended` = 1 then 0 with progress kept), `LearningStoreTests.testLearnResumesAListWordWithItsContent` (a Greek A1 word with the list's translation, stopped, then Learn on its Definition: the same `translation`, `translation_lang`, `list_id` and steps); `LearningStoreTests.testStopLearningRemovesEveryRowOfTheWord` (γράφω in My words from El–En · FD and El–En · WN, Stop learning on the WN entry: no My words row of the key is left, its cards are paused with their steps). UI `MyWordsFlowTests.testLearnButtonAddsAndRemoves` (search γράφω, Learn, My words lists it; Stop learning, gone), `testStopLearningFromMyWordsSwipe` (the word also leaves learning; E3's list screen gets the same test in #154), `testLearnButtonStatePersists`, `testWordFromAnotherDictionaryIsTheSameWord` (γράφω from El–En · WN shows the filled cap after Learn on El–En · FD) |
| #158: localized in 5 languages; Arabic right to left | `testEveryCatalogKeyIsTranslatedInEveryShippedLanguage`; UI `ArabicLocalizationTests.testLearnTabRightToLeft`, `GreekLocalizationTests.testLearnTabInGreek` |
| #159: both exercises launch from Trainers and grade the card of their own direction | UI `ExerciseFlowTests.testRecognitionTrainer`, `testProductionTrainer` (`-learningFixture due`, `-learningAnswerHints`: 10 items, the summary). Unit `ExerciseRunViewModelTests.testTrainerGradesOnlyItsKind` |
| #159: strict, lenient and choice behave as described | Unit `AnswerCheckerTests`: `testStrictNeedsTheAccent`, `testLenientWarnsOnAccent`, `testCaseSpacesAndFinalSigmaNeverCount`, `testLeadingArticleIgnored` (ell, eng, spa), `testParenthesisedPartIsOptional` (`(ένα) σωρό`), `testArabicHarakatFold`, `testSpanishAccentsFold`, `testEmptyIsWrong` (also when the expected word is an article), `testLoneArticleIsAWord` (expected `the`: `the` right, `a` wrong); `QuestionBuilderTests.testChoiceModeNeverTypes`, `testNewProductionIsAChoice`. UI `ExerciseFlowTests.testTypedLenientAccentWarning`, `testTypedStrictAccentIsWrong` (each mode set through `SettingsPage`) |
| #159: distractors from the same list and part of speech | Unit `DistractorPickerTests`: `testSameListAndPartOfSpeechFirst`, `testNoOptionFoldsLikeAnother`, `testSharedMeaningPartIsExcluded` (also between two distractors: `home, residence` and `home, place` for `house`), `testFallsBackToTheSourceSample`, `testNoCandidatesTypesOrSkips`; `GlossTests` (the table in "Meanings", En–El · FD and En–El · WN included, every bundled source, plain-text imports) |
| #131, #159: the right answer highlighted at once; sound and haptics can be turned off | UI `ExerciseFlowTests.testWrongChoiceHighlightsTheRightOption` (`exercise_feedback` = `wrong`, the right option marked, without waiting). Unit `FeedbackPlayerTests.testSoundAndHapticsFollowTheSettings` (`FeedbackSink`: nothing plays when off) |
| #160: a round of 5 pairs with a timer; right pairs disappear, wrong ones flash | Unit `MatchRoundTests`: `testRoundPicksFiveWordsOfOneLanguage` (the chosen language's), `testWrongPairIsChargedToTheWord`, `testMeaningsAreDistinct`, `testNeedsFiveWords`. UI `MatchPairsFlowTests.testRoundOfFive` (`-learningAnswerHints`: one wrong pair, then all right; tiles gone, `match_timer` advancing, the result) |
| #160: results logged and recognition cards updated | Unit `MatchPairsViewModelTests.testEachWordLogsOneRecognitionAnswer` (5 rows, exercise `match`, one `wrong`, cards per the ladder) |
| #160: iPhone and iPad; Arabic right to left | UI `MatchPairsFlowTests` on the matrix; `ArabicLocalizationTests.testMatchPairsRightToLeft` (words column on the right) |
| #161: new words go recognition → reverse choice; familiar words get production typed per setting | Unit `SessionPlannerTests.testNewWordsInGroupsOfThree`, `testFamiliarProductionFollowsTheAnswerMode`, `testCardsOfOneWordNotAdjacent`, `testWrongItemComesBackOnce` |
| #161: the summary matches the answer log | Unit `ExerciseRunViewModelTests.testSummaryEqualsTheRunsLogRows` (`ReviewSummary` over `run_id`). UI `SessionFlowTests.testSummaryAfterSession` (counts equal the answers given) |
| #131, #161: mistakes practice holds exactly the cards wrong in the last 7 days and not right since | Unit `LearningStoreTests.testMistakesAreTheLastSevenDays` (wrong today, 6 days ago, 7 days ago: the first two only; a paused word excluded; a card answered right after its error excluded). UI `SessionFlowTests.testPractiseMistakes` (`-learningFixture mistakes`) |
| #162: every setting changes the session as described | Unit `LearningSettingsTests` (defaults, clamping, `-resetData`), `SessionPlannerTests.testNewPerDaySetting`, `LearningStoreTests.testNewWordsAskE3WithTheSettingAndEveryEnrolledKey` (order), `QuestionBuilderTests` (answer mode). UI `LearningSettingsFlowTests.testSettingsSectionReplacesComingSoon`, `testNewWordsPerDayZeroOffersNoNewWords` |
| #131, #162: the reminder fires only when on and the goal is not met | Unit `LearningReminderTests` (fake center, fixed clock): `testOffSchedulesNothing`, `testSchedulesSevenDays`, `testGoalMetTodaySkipsToday`, `testTimePassedSkipsToday`, `testReachingTheGoalCancelsToday`, `testContentInTheInAppLanguage` |
| #162: no permission prompt until the reminder is turned on | Unit `LearningReminderTests.testAuthorizationOnlyOnTurningOn` (no `requestAuthorization` from launch, sessions or settings changes). UI `LearningSettingsFlowTests.testPermissionAskedOnlyWhenTurnedOn` (fresh install: a session and the Settings screen show no SpringBoard alert; the switch shows it, Allow through SpringBoard) |
| #131: 5 UI languages; iPhone and iPad, iOS 17.5 and 26.4 | The catalog test; every suite above on the matrix; `iPadSpecificTests.testExerciseOnIPad` (centred column, landscape) |
| #292, #293: two learned pairs show two tabs; "+" adds a third; with five on an iPhone the overflow sheet lists the hidden ones | Unit `PairTabFitTests` (pure): `testAllFit` (two tabs and "+": no "…"), `testOverflowEndsWithMore` (five tabs on a 361 pt strip: a prefix of the tabs, then "…", no "+"; the hidden ones in order), `testSelectedHiddenTakesTheLastPlace`, `testSelectedAloneIsCut`, `testNothingReordered`. UI `PairTabsTests.testTwoPairsTwoTabsAndAdd` (`-learningFixture bilingual`: `learn_pair_tab_ell`, `learn_pair_tab_eng`, `learn_pair_tab_add` in that order; "+" opens `language_picker` without Greek or English rows; Spanish via English with `-packDownloads ok`: `learn_pair_tab_spa` last and selected), `testFiveTabsOverflow` (`-learningLanguages ell,eng,spa,rus,arb`; iPhone: `learn_pair_tab_more` is last and no `learn_pair_tab_add`; it opens `learn_pair_overflow` with a row for each tab not in the strip and `learn_pair_overflow_add`; choosing a row selects its tab, which then shows before "…"; iPad: five tabs and "+", no "…") |
| #292, #293: the order survives a relaunch; a new pair goes last | Unit `LearningLanguageServiceTests.testReorderWritesTheOrder` (the same languages: written; another set: unchanged), `LearnViewModelTests.testMoveKeepsTheSelection`, `testNewPairGoesLast` (a pair stopped and added again too). UI `PairTabsTests.testDraggedOrderSurvivesRelaunch` (`-learningLanguages ell,eng`: English dragged onto Greek's leading half; the strip reads English, Greek; relaunched without `-resetData`: the same order). The drag tries the strategies of `DictionaryOrderReorderTests` until the order changes (coordinates differ by simulator architecture, #6) |
| #292, #293: Stop learning hides the tab and keeps the progress; adding the pair again brings it back | Unit `LearnViewModelTests.testStopRemovesTheTab` (the first tab selected; cards, log, `learning_lists` and `learning_via` unchanged), `testStoppingTheLastTabShowsThePicker`. UI `PairTabsTests.testStopLearningFromTheTab` (`-learningFixture bilingual`: long press `learn_pair_tab_eng`, `learn_pair_tab_stop`, Yes: no English tab, the Greek tab selected; "+", English via English: `learn_pair_tab_eng` last, `learn_due_count` 2) |
| #293: the streak and the goal ring read the same on every tab | UI `PairTabsTests.testGoalAndStreakShared` (`-learningFixture stats`: `learn_goal_ring` and `learn_streak` have the same values on the Greek and English tabs) |
| #293: VoiceOver tab group with the pair name and selected state; Arabic right to left; iPhone and iPad, iOS 17.5 and 26.4, five languages | UI `PairTabsTests.testTabsAccessibility` (`learn_pair_tabs` is a tab bar; `learn_pair_tab_ell` labelled "Greek · via English", selected; `learn_pair_tab_more` labelled "More languages"), `ArabicLocalizationTests.testPairTabsRightToLeft` (the first tab right of the second), `GreekLocalizationTests.testPairTabsInGreek`; the catalog test; `PairTabsTests` on the matrix |
| #295: Greek's tab shows Grammar with the topics and Conjugation; English's tab has no Grammar section | UI `PairTabsTests.testGrammarSectionPerLanguage` (`-learningFixture bilingual -installPacks ell`: the Greek tab has `learn_grammar_row`, and `learn_trainer_conjugation` right below it, after `learn_trainer_match`; the English tab has neither), `testConjugationWhileTrainersAreOff` (replaces `LearnTabTests.testTrainersOnKeepTheConjugationRow` and `testTrainersOffConjugationRowRightToLeft`: Greek with nothing to learn: the trainers' footer, and `learn_trainer_conjugation` enabled in Grammar). Unit `LearnViewModelTests.testGrammarRowOnlyWithTopics` (0133) |
| #295: Lists, My words and Statistics on a tab show only that language | Unit `LearnViewModelTests.testMyWordsCountPerTab` (γράφω and house in My words, both languages learned: 1 on each tab), 0130's `WordListsViewModelTests.testListsOfOneLanguage`, 0166's `StatisticsViewModelTests.testBlocksFollowTheTab`. UI `PairTabsTests.testListsMyWordsStatisticsPerTab` (`-learningFixture bilingual`, γράφω and house in My words: on the English tab, My words lists house only, All lists shows the English section and My lists only, Statistics' `stats_today_new` is English's) |
| #296: a lesson closed on its third question continues from the fourth, with the bar at 3 of N | Unit `KeptLessonTests.testClosedLessonContinuesAtTheNextQuestion` (a session of 10 items, 3 answered, the view model dropped; a new one: its first question is the fourth card, `answered` 3, total 10, the same `runID`), `testRetryIsKept` (wrong on question 2, closed after 3: the retry is still the last item, asked once in the second sitting), `testSkippedQuestionIsSaved`, `testItemsRoundTrip` (pure), `testStoreReadsOnlyTodaysLesson`. Edges: `testClosedBeforeTheFirstAnswerContinuesAtTheFirst`, `testClosedAfterTheFirstAnswerCountsItOnce`, `testKillAfterAnAnswerBeforeNext` (killed after an answer, before the next question), `testClosedOnTheLastQuestionContinuesWithOne`, `testWrongOnTheLastQuestionKeepsOneRetry`, `testPausedAndDeletedWordsAreDroppedAndTheLessonShrinks`, `testEveryItemGone`, `testLessonsAreOnePerLanguage`, `testUnreadableLessonRowDoesNotBlockStart` (a damaged row is no lesson: Start builds one and overwrites it). UI `SessionFlowTests.testContinueLesson` (`session` fixture, `-learningAnswerHints`: Start, 3 answers, close; `learn_continue_button` reads "Continue lesson · 15 left"; tap: `exercise_progress` at "Question 4 of 18"; to the end: `run_summary_exercises` reads 18) |
| #296: after the learning day ends the button reads Start and builds a new lesson; none is built while one can continue | Unit `KeptLessonTests.testLessonEndsWithTheDay` (fake clock: the next day: `lessonLeft` nil, Start offered; Start plans a new lesson and overwrites the row), `testNoNewLessonWhileOneCanContinue` (`lessonLeft` 7; `ExerciseRunViewModel(.session)` continues it), `testRolloverMidLessonCountsEachAnswerOnceOnItsDay` (answers after 4 AM count for the new day, the old day keeps its 3, no log row is added by the new day's Start), `testStopLearningKeepsTheLessonAndReAddResumesIt`, `testTrainersKeepNoLesson`, `testTrainerAndMistakesLeaveTheKeptLessonAlone` (a trainer and mistakes read and write no `learn_lesson` row, the kept one unchanged) |
| #296: the goal ring and the reviews count each answer once | Unit `KeptLessonTests.testAnswerAndLessonInOneTransaction` (a failure after the log row leaves neither: the lesson keeps the item, no log row), `testLastAnswerDeletesTheLesson`, `testContinuedLessonCountsEachAnswerOnce` (3 answers, close, continue, finish: 10 log rows for the run, `answeredCount(today)` 10), `testKeptLessonMigration` (a database at `166-1-daily-goal`, migrated: `learn_lesson` exists, empty; no other table changes), `testBetaDatabaseKeepsItsLearningDataAcrossTheMigration` (a 2.0 beta database with learning rows: every row equal after the migration), `LegacyMigrationTests.testMigrates140FixtureLeavesNoLesson` (the 1.4 fixture: `learn_lesson`, `learn_review` and `learn_word` empty) |
| #297 | 0133's test plan (`GrammarTopicsViewModelTests.testOneLevelHasNoHeader`, `GrammarFlowTests.testTopicsByLevel`, `testComingSoonIsNotAButton`) |
| #298 | 0130's test plan (`testLearningFromValue`, `testLearningFromRow`, `testNoNewWordsFromLeft`) |
| #299: every wrong choice shows the chosen option's meaning (or form) next to the right answer | Unit `QuestionBuilderTests.testOptionsCarryTheirCounterpart` (recognition: each meaning's word; production: each word's meaning; source-sample options too), `ExerciseRunViewModelTests.testWrongChoiceKeepsTheChosenOption` (a wrong option: its text and counterpart; right, typed and "Don't know": nil), `FeedbackBarTests.testYouChoseLine` (en "You chose: water · νερό"; ar starts with U+200F, the Greek isolated), `MatchPairsViewModelTests.testMismatchShowsBothPairs` (νερό with "write": νερό · water and γράφω · write; cleared by the next tap), 0132's `ConjugationQuestionTests.testOptionSlots`. UI `ExerciseFlowTests.testWrongChoiceShowsWhatYouChose` (`-learningAnswerHints`: a wrong option; `exercise_you_chose` starts with "You chose:"; a typed wrong answer has none), `MatchPairsFlowTests.testWrongPairShowsBothPairs` (`match_mismatch`), 0132's `ConjugationDrillFlowTests.testWrongFormShowsItsSlot` |
| #299: VoiceOver reads it after the right answer | Unit `FeedbackBarTests.testAnnouncementOrder` (`lines`: the right answer, then the "You chose" line) |
| #300: each of the six cases plays its sound once, off the main thread | Unit `FeedbackPlayerTests.testSixSoundsAtTheirMoments` (`FeedbackSink`: a right and a wrong answer give `right`, `wrong`; a match round with one wrong pair gives `pairWrong` once, `pairRight` 5 times, then `lessonComplete`; a session that reaches the goal ends with `goalReached`, not `lessonComplete`; a run closed early, no end sound), `RunEndSoundTests` (pure: 18 → 22 with a goal of 20: `goalReached`; 20 → 25: `lessonComplete`), `ToneSynthTests` (each sound: a 16-bit mono 44.1 kHz WAV of its recipe's length, a peak of about 0.7, silent at its end, equal across two calls), `TonePlayerTests.testTonesPlayOffTheMainThread` over the six. QA: kyukhin hears each on a device; the silent switch mutes them; music keeps playing; the speaker button (#202) still speaks |
| #300: Sounds off in Settings: none plays | Unit `FeedbackPlayerTests.testSoundAndHapticsFollowTheSettings`, over the six |

## Open questions

1. **Learn on a word and the daily limit.** Resolved 2026-11-03: within the limit, My words first (Decisions).
2. **Stop learning.** Resolved 2026-11-03: pause (Decisions).
3. **Mistakes practice.** Resolved 2026-11-03: a card leaves once its last answer is right (Decisions).
4. **Default for typed answers.** Resolved 2026-11-03: Lenient (Decisions).
5. **New words.** Resolved 2026-11-03: no introduction screen (Decisions).
6. **When a day starts.** Resolved 2026-11-03: 4 AM local time (Decisions).
7. **New Swift files.** Resolved 2026-11-03: one Xcode step for the three epics (Decisions).
8. **Cutting beyond #160 if 11-16 slips.** Resolved 2026-11-03: the recommended order (Decisions). Superseded 2026-11-04: nothing is cut, the release date moves (Decisions).
9. **English via Russian and via Arabic.** Resolved 2026-11-04: not in 2.0; Russian and Arabic UIs learn English via English (Decisions).
10. **The sound variants (#300).** Resolved 2026-11-10 (kyukhin): variant 1 of each case for now (`right_1`, `wrong_1`, `lesson_1`, `goal_1`, `pair_right_1`, `pair_wrong_1` of `make_sounds.py`), swapped later if kyukhin picks others; "lesson complete" plays after every daily lesson, not after the trainers, mistakes or the drill.
11. **"+" when the tabs overflow.** Resolved 2026-11-10 (kyukhin): the "…" sheet ends with "Add a language"; Settings → Learning → Languages keeps its own.
12. **My words of a language not learned.** Resolved 2026-11-10 (kyukhin): such a word is on no tab until its language is learned.

## History

- 2026-11-03: First draft, designed with E10 (0166).
- 2026-11-03: Aligned with E3's draft (0130):
  - words and cards are keyed by E3's `WordKey`, with 0130's key for My words in the migration;
  - the new-word order, its seed and the learning-list preference (`learning_list`) are E3's, and E4 passes its order setting to `nextNewWords`;
  - list words, those without an entry included, are learned with their stored content;
  - My words moves to E3's list screen once #154 lands;
  - one Xcode step for the three epics.
  It keeps three differences, with reasons, in "Depends on E3": one transaction for Learn, Stop learning on the My words swipe, and stored content.
- 2026-11-03: Aligned with 0130's checked lists (Open question 6): new words come from the set `learning_lists` through `nextNewWords(from:)`, and the Learn home ("Choose lists") and the Learning settings open E3's New words from screen.
- 2026-11-03: Learning is per language (kyukhin): a language switch on the Learn home (`learning_language`), the session, trainers, mistakes and match the pairs filtered by language through the store API's `lang` arguments, the new-word limit per language, the goal and streak shared; #157 and #158 grow by 0.5 day each.
- 2026-11-03: Learning a language is explicit (kyukhin): the language picker and `learning_languages`; lists installed through 0237; "Learn %@?" on a word of a new language; Settings → Learning → Languages to add or stop one. The migration and the 1.x move enrol nothing: a language's My words are enrolled when it is chosen, which undoes this spec's earlier change to 0129's move. #158 +0.75 day, #162 +0.25; the calendar is to be replanned with #237.
- 2026-11-04: Review fixes and alignment with 0237 (Draft): the My words key reads a source's language through 0237's `DictionarySchemas.sourceLanguageSQL`, so a word of a pack not yet downloaded keeps its language; `enrolMyWords` takes one My words row per `WordKey`; `recordAnswer` lists E10's `learn_day` write; `LearningClock` finds the 4 AM boundary with calendar arithmetic, right on daylight-saving days; E5's accuracy by tense groups both voices; #208's remap of `und` covers a key collision and the language preferences.
- 2026-11-04: Approved by kyukhin.
- 2026-11-04: Review fix after approval: Stop learning, the My words swipe and "Remove from My words" delete every My words row of the word's `WordKey`, not only the one shown, so a word saved from two dictionaries leaves My words; cards are still paused with their progress (Decisions, Open question 2). Test added.
- 2026-11-04: Learning is chosen as a language pair (kyukhin): the pairs come from the dictionaries' directions through 0237's catalog (seven in 2.0); each learned language has one via (`learning_via`), chosen with the pair and changeable in Settings; meanings, distractors and production prompts are in the via, chosen at each question (`meanings(of:lang:via:sourceOrder:)`, `learn_word.translation_lang`); the picker lists pairs with their download size; "Learn %@ via %@?"; Open question 9. Nothing is cut if late: the release date moves (kyukhin). #157 +0.5, #158 +0.75, #159 +0.75, #162 +0.5.
- 2026-11-04: Greek via Russian is offered as a limited pair (kyukhin): a pair has a via language (explanations) and a meanings language, the same except in the catalog's limited pairs (`catalog_pair`, 0237); Greek via Russian shows meanings, list translations and drill translations in English, its grammar in Russian, its examples in Russian else English, and a warning in its rows and alert; a Russian UI gets it as Greek's default. `meanings` and `distractorCandidates` take the meanings language (`meaningsLang:`). #157 +0.25, #158 +0.25.
- 2026-11-04: Review fixes after approval: `introduce` is one transaction and retry-safe; each answer takes the learning day at its own time, so an answer after 4 AM in a running session counts for the new day; an empty answer is always wrong, and a lone article is a word, not an article to drop. Tests added.
- 2026-11-05: Review fixes after approval: the enrolment rule is stated as the one to implement and points at 0129's `my_words` row as #237's spec change updates it; Learn on Definition resumes a paused word without overwriting its stored content; a distractor that shares a meaning with another distractor is dropped too. Tests added.
- 2026-11-05: Review fixes after the rebase on master: the `WordKey` item follows 0130 (no Unicode normalisation; canonical twins accepted); #157 and #161 use #151's merged code; `learn_review` gets a `run_id` index for run summaries; `learn(language:)` appends Other without a pair; a word with no meaning in the pair takes no new-word slot; a match answer's `duration_ms` starts at the round for the first match and is capped at 60 s.
- 2026-11-06: Rebased on master with 0237 (#238). Review fixes: the 2026-10-22 freeze decision points at 0166's later rule; a list word's `translationLang` is 0130's (PR #251), and its translation counts in the pair's meanings language or, for imports, in every pair; a conjugation card's word follows the `WordKey` rule; due cards of words skipped in the pair take no slot.
- 2026-11-06: #157: word-level logic (started words, Stop learning and its resume, the new pool, mistakes, `learningState`) reads and writes word cards only (`LearningSQL.wordKinds`), so E5's conjugation cards never count as a word's.
- 2026-11-06: #157: only a word card's first answer sets `introduced_day`; a conjugation answer starts no word.
- 2026-11-06: #157: `learnWord`, `stopLearning`, `enrolMyWords` and `introduce` read the sources' languages or entries from the dictionary file in their transaction, so they retry once after an I/O error, as the import does (#213).
- 2026-11-06: #157: `dueCards` and `newPool` read a negative limit as 0 (SQLite reads a negative `LIMIT` as none), so more words started today than the daily limit give no new word.
- 2026-11-06: #157: learning pairs as built. Until #241's `PackCatalog.pairs`, `DatabaseService.learningPairs()` reads the directions of the bundle's `dict_metadata` and of imports with both languages, and the limited pair is `LearningPairs.limitedPairs` in code. `LearningPairs.pair(for:stored:offered:uiLanguage:)` returns the pair rather than its via. The default via is the UI language whenever that pair is offered, a limited one included, else English, else the first via by code.
- 2026-11-06: #157: `introduce` lands here for #161; `WordListItem.translationLang` is declared here as #154 declares it, and stays `""` until #154 reads `wordlist.translation_lang`.
- 2026-11-06: Review fix (CodeRabbit, PR #253): `dueCards` also returns the unanswered word card of a started word, so a session closed between a word's two cards cannot strand the second one.
- 2026-11-07: #157, rebased on 0237 (#252): `learningPairs()` reads the directions of the bundle and of the catalog (`DictionarySchemas.sourceLanguageSQL`), so a pack not yet downloaded offers its pairs; the limited pair stays `LearningPairs.limitedPairs` until #158 reads `catalog_pair`. Review note (CodeRabbit, PR #253): the interim `translationLang` of built-in items before #154.
- 2026-11-06: #158: `common.yes` and `common.no` are new keys, as the catalog had no Yes and No buttons to reuse; `listImport.language.other` and `listImport.learnOther` come early from #155, for Other's name and its alert.
- 2026-11-06: #158: "Import a list" shows disabled until #155's import screen.
- 2026-11-06: #158: Today's due count counts words, not cards: a word with both cards due counts once.
- 2026-11-06: #158: UI tests as built: `LearnTabTests.testChooseGreekOffersItsLists` is `testChooseGreekShowsItsHome` ("Choose lists" waits for #154), `testChooseListsWhenNothingToLearn` and `LearnViewModelTests.testEmptyStateFollowsTheCheckedLists` wait for #154, `LearningSettingsFlowTests.testStopAndResumeALanguage` for #162, and `GreekLocalizationTests.testLearnTabInGreek` is `testSearchHistoryLearnAreLocalizedInGreek`.
- 2026-11-06: #158: the Russian limited-pair warning reads "Слова тренируются с переводом на английский.", with the meanings language as a name in the sentence.
- 2026-11-06: #158: in Russian, Greek and Spanish a language name inside a sentence ("Learn %@ via %@?", a pair's row, the warning) is lowercase, as those languages write it; English capitalises it.
- 2026-11-06: #158: until #241 and #242, `PendingPairPacks` stands in for 0237's catalog and install: Greek and English have lists, and nothing downloads.
- 2026-11-06: #159: `distractorCandidates` is two reads: `wordChoices(lang:meaningsLang:sourceOrder:)`, every enrolled word of the language with its meaning and part of speech, once per run, and `distractorSample(lang:meaningsLang:source:sourceOrder:pos:near:seed:count:)`, about 30 random headwords near the word's, only when the enrolled words leave a choice short.
- 2026-11-06: #159: `MeaningQuery` also carries the word's `entry`, which Other's rule 3 reads.
- 2026-11-06: #159: the `due` fixture gives a trainer 6 items, not 10: its five due words, then the learned βιβλίο as practice.
- 2026-11-06: #159: until #162's Settings, the UI tests set the answer mode through the `learning_answer_mode` launch default.
- 2026-11-06: #159: trainer practice also takes the unanswered card of a started word (its other card was answered), as the oldest.
- 2026-11-06: #159: a run reads the due cards, the new pool and practice whole, drops the cards of words without a meaning in the pair, then takes its 10, instead of reading in pages.
- 2026-11-06: #159: the feedback texts isolate the word or meaning with FSI…PDI, so a Greek word keeps left to right in Arabic.
- 2026-11-07: #159, merged after #163: the run summary is `ReviewSummary.of(reviewRows(run:))` over the run's log rows, and each answer passes the daily goal to `recordAnswer`.
- 2026-11-07: #161 as built: the planner is `session(due:newWords:today:)` with `mistakes(cards:)`; `separatingWords` runs after each requeue and each skipped card, so a retry may move off the very end to stay apart from its word's other card. Today's counts (due, new, mistakes) count only words with a meaning in the pair, so Start and Practise mistakes never open an empty run. The home's empty state also reads the checked lists. The summary also shows the goal row ("11 of 20"), done here rather than in #164.
- 2026-11-07: #161 tests as built: `SessionFlowTests` uses the `session` fixture with a user list (`user-fixture-ell`), not `ky-ell-a1`; new ids `run_summary_exercises`, `_accuracy`, `_new_words`, `_reviewed`, `_time`, `_goal`; `SessionRunTests` and `LearningStoreTests.testListWordWithoutAMeaningTakesNoSlot` are new; `testDeletedListKeepsItsWords` waits for #155 (no list can be deleted yet).
- 2026-11-07: #162 as built: the via control is a `Menu` of toggles (a menu `Picker` cannot show the limited pair's warning); `learning_language_via_<lang>` is labelled "via Spanish" with no code value; `common.cancel` is new and `settings.learning.via` unused. `AppRouter` keeps a tab per window (iPad windows switch independently) and a reminder tap opens Learn in every open window; changing the UI language lands on Search. A reminder time before 4 AM belongs to the learning day before and fires after the next midnight. `testChangeTheVia` uses the `bilingual` fixture. #160's match the pairs must call `answerRecorded`, so reaching the goal cancels today's reminder.
- 2026-11-07: #160 as built: "learning words" are those whose recognition card is on rung 0; the five meanings share no comma-separated part and no two terms fold alike (the distractor rule); a round introduces only the list words it takes; one `run_id` per round; mistakes on the result count the wrong pairs tapped; match plays the feedback sounds too; a matched tile keeps its place, hidden; with no words at all the row shows the trainers' footer, "Learn 5 words first" only when the other trainers are enabled; new ids `match_result`, `match_result_time`, `match_result_mistakes`, the close button is `exercise_close`; extra string "Tap the matching pairs".
- 2026-11-08: Learning on 0237's packs (#131 follow-up): the offered pairs and the limited Greek via Russian come from the catalog (`PackCatalog`: the dictionaries' directions and `catalog_pair`), with no pair in code. `CatalogPairPacks` replaces `PendingPairPacks`: the picker's sizes are the catalog's for the packs not installed, and a pair's install runs through `PackService.installPair`. The Learn home, and Settings → Learning → Languages under the language, show the install: the pack's language with "Downloading…" and its progress, or "The download did not finish…" with Try again (`learn_install_row`, `learn_install_error`, `learn_install_retry`; keys `learn.install.downloading`, `.failed`, `.retry`, until #243's `PackRow`). UI `LearnTabTests.testChoosingAPairDownloadsItsPacks` (`failOnce`, then Try again) and `testChoosingAPairOffline`.
- 2026-11-08: Review fixes (CodeRabbit, PRs #260, #263, #266, #267, #268): the Definition's History write and its Learn state load independently, the first error shown; a choice's or a load's error survives the reload and shows in an alert on the Learn tab; meanings and distractors of a source both in a pack and imported read both; separating a word's two cards never moves a new card ahead of a due one; the reminders reschedule when the in-app language changes, and goal changes are written in order, the last one winning; a second Next round while the last answer is being written starts no second round. Tests added.
- 2026-11-08: Epic #131 closed: Implemented. The answer tones load and play on their own serial queue, off the main thread: `prepareToPlay` blocked the main thread for up to 15 s while the audio system started, freezing the run (`testTonesPlayOffTheMainThread`).
- 2026-11-10: Revision for epic #292 and #300, from kyukhin's beta feedback and decisions of the day (Draft, awaiting approval): one tab per learned pair with "+", "…" and drag reorder, Stop learning on a long press, the streak and goal shared (#293); everything about a language on its tab, Conjugation moved to Grammar (#295); a lesson closed early continues, stored in the new `learn_lesson` table, migration `292-1-kept-lesson` (#296); "Learning from" (#298, 0130); "You chose" after a wrong choice (#299); six synthesized sounds (#300). The tab order is the existing `learning_languages`: no new key. Open questions 10–12.
- 2026-11-10: The #292/#300 revision approved by kyukhin.
- 2026-11-10 (QA, #296): the Test plan rows for #296 name the tests as built (`KeptLessonTests`) and add the edges: closing on the first and the last question, a kill after an answer, a wrong last answer, a day rollover mid-lesson, Stop learning and adding again, words paused or deleted meanwhile, trainers and mistakes, a damaged row (no lesson; Start overwrites it), and the 2.0 beta and 1.4 migrations.
