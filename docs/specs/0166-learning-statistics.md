# Learning statistics

> Spec written by Claude (AI) for LibreDict.
> Status: Approved by Kirill on 2026-11-04 · Epic: #166 · Tickets: #163 (done), #164, #165 · Updated: 2026-11-06

Read [0000-overview.md](0000-overview.md), [0129-dictionary-file.md](0129-dictionary-file.md) and [0131-learning.md](0131-learning.md) first. Every number here is computed on the device from 0131's answer log (`learn_review`), cards (`learn_card`) and words (`learn_word`). The conjugation drill (E5, #132) writes to the same log, which gives accuracy by tense. Lists and their words come from E3 ([0130-word-lists.md](0130-word-lists.md)). This epic adds one small table, for the daily goal.

## Why

Learners want to see their progress and their weak spots. A daily goal with a streak brings them back every day, which is the habit spaced repetition depends on. Statistics is its own epic so that the learning engine stays small: it only reads the engine's data and adds the goal history.

## Behaviour

### Daily goal and streak (#163, shown by #164)

- **Daily goal**: N exercise items a day, set in Settings (default 20, 0131). An item is one answered question, one matched pair or one drill question. Every run counts: session, trainers, mistakes, match the pairs and the drill (Decisions). The goal and the streak are shared: an exercise in any language counts (Kirill, 2026-11-03).
- **On the Learn home**, Today gets a ring "12 / 20" that closes with a check mark when the goal is met. Next to it a flame shows the streak, "5". The flame is grey until today's goal is met, and a snowflake shows the freezes in stock, 0 to 3. Tapping the ring or the streak opens Statistics.
- **Streak rules** (Kirill, 2026-10-22, #163). Weeks run Monday to Sunday:
  - a day whose goal is met adds 1;
  - a missed day spends a freeze when one is in stock: the day is frozen, and the streak stays and does not grow;
  - a missed day with no freeze in stock resets the streak to 0;
  - every Monday adds one freeze; unused freezes carry over, up to 3 in stock (Kirill, 2026-11-03). A first week that starts after Monday has none;
  - today counts as soon as its goal is met, and it is not a miss before the day ends;
  - a freeze is spent only when it saves a streak: a missed day with a streak of 0 keeps it (Decisions).
- **A day keeps the goal in force when it ended.** Changing the goal later does not change past days (Decisions). Today always uses the current setting.

| Mon | Tue | Wed | Thu | Fri | Streak after Fri | Why |
|---|---|---|---|---|---|---|
| ✓ | ✓ | ✓ | ✓ | ✓ | 5 | |
| ✓ | ✓ | ✗ | ✓ | ✓ | 4 | Wednesday frozen |
| ✓ | ✓ | ✗ | ✓ | ✗ | 0 | One freeze in stock: Wednesday spends it, Friday resets |
| ✓ | ✓ | ✗ | ✓ | ✗ | 3 | Two freezes in stock: both misses frozen |
| ✗ | ✓ | ✓ | ✓ | ✓ | 4 | First day ever: Monday missed with a streak of 0, freeze kept |
| ✓ | ✗ | ✓ | ✓ | today, 3 of 20 | 3 | Today not over yet |

Every Monday adds a freeze, up to 3 in stock: a learner who misses nothing holds 3 from the third Monday.

### Statistics screen (#164)

Learn → Statistics, or a tap on the ring or the streak. One scrolling list.

Progress is per language (Kirill, 2026-11-03). With two or more learned languages (0131), the screen starts with the Learn home's language switch, on the same preference. The goal, the streak and the 30-day chart count every language; every other number is the chosen language's. A language whose learning stopped leaves the switch and its numbers are hidden; its past answers still count for the goal, the streak and the chart.

| Block | Content |
|---|---|
| Today | Exercises "12 of 20" (every language); the chosen language's new words, reviewed words, accuracy and time |
| Streak | Current streak, best streak, "Freezes: 2 of 3", a calendar of the last 5 weeks (Monday first): goal met, frozen, missed, today outlined |
| Last 30 days | A bar chart of exercises per day with a line at the current goal; days with the goal met in the accent colour |
| Lists | The checked lists of the chosen language (0130, New words from), and every list of it with a started word (My words included, counting its words of that language): a bar of learned / learning / new, the numbers, and a forecast: "All learned in ~129 days", "Start learning to see a forecast" or "All learned". E3's Lists screen shows the same bar on each row (#154) |
| Accuracy, last 30 days | Recognition 87% (412 answers), Production 71% (380) |
| Hardest words | Up to 20 words with the most mistakes in the last 30 days: word, meaning in the pair's meanings language (0131: the via, English for the limited Greek via Russian), "5 mistakes · 62%". A tap opens the Definition; a list word without a dictionary entry has none to open |
| Conjugation | Shown once the drill (E5) has answers: accuracy by tense and the 10 hardest verbs, last 30 days |

- Before the first answer: "Your statistics appear after your first exercise."
- **VoiceOver** reads each chart as one short summary:
  - "Last 30 days: 412 exercises on 21 days. Goal met on 18 days. Best day: 2 November, 45 exercises."
  - "Conjugation, last 30 days: aorist 82%, present 91%, future 64%."
  - The calendar reads day by day: "3 November, goal met".
- **iPhone and iPad**: one column, at most 700 pt wide on iPad.
- **Arabic**: mirrored. The chart runs from the oldest day at the leading edge to today at the trailing edge, so it reads right to left.

### Word status on the Definition screen (#165)

Under the part of speech, for a word in learning that is not paused:

```
Learning · next review tomorrow
Recognition: every 7 days · Production: learning
3 mistakes
```

- **Learned**: "Learned · next review 12 Dec".
- **Started, not learned**: "Learning", with the earlier due date of the two cards: "today", "tomorrow" or a short date in the UI language.
- **New**: "New · not started yet".
- **Not in learning, or paused**: nothing.
- Mistakes are all wrong answers on the word's two cards, ever.

### The numbers, defined

| Number | Definition |
|---|---|
| Exercises (a day, a run) | Log rows of that day or run, of every kind |
| Goal met (a day) | Exercises ≥ the day's goal |
| New words | Rows with `introduced = 1`: a word counts on the day of its first answer, once |
| Reviewed words | Distinct words with a recognition or production row, `introduced = 0`, and no `introduced = 1` row among the same rows: a word started that day (or run) is new, never also reviewed |
| Accuracy | Right and accent rows ÷ all rows |
| Time | The sum of `duration_ms`, each capped at 60 s |
| List: learned / learning / new | Per distinct word of the list: **learned**, both word cards at 30 days or more; **learning**, unpaused cards with an answer but not learned; **new**, no cards, paused, or never answered |
| Hardest words | The most wrong answers on word cards in the last 30 days (today and the 29 days before) |
| Accuracy by direction | Recognition (match the pairs included) and production rows of the last 30 days |
| Accuracy by tense | `conjugation` rows of the last 30 days, by tense: the part of `facet` before the dot, both voices together |
| Per language | Every number above counts only the rows, cards and words of the chosen language, except the shared ones, which count every language: a day's exercises (the goal and the 30-day chart), goal met and the streak |

The run summary in 0131 uses the same definitions over one run's rows. So a summary and Today always agree.

### Decisions

- 2026-10-22 (Kirill): statistics is a separate epic and ships in 2.0.0.
- 2026-10-22 (Kirill): a day counts for the streak when the daily goal is met. One missed day per week is frozen.
- 2026-10-22 (Kirill): the daily goal is a number of exercise items, set in Settings, default 20.
- 2026-10-22 (Kirill): statistics show today, progress per list with a forecast, a 30-day chart, the streak, weak words, and per-tense accuracy fed by the E5 drill.
- 2026-10-22 (Kirill): achievements and the widget move to 2.1.0 (#149, #150).
- 2026-11-03 (Kirill): learning is per language. Progress is "about a specific language, not the whole learning module": statistics, the Learn home's counts and list bars show the chosen language. The daily goal ring and the streak stay shared.
- 2026-11-03 (Kirill): learning a language is explicit (0131). Per-language numbers are offered for the learned languages only; a stopped language's numbers are hidden until it is chosen again.
- 2026-11-04 (Kirill): learning is chosen as a language pair (0131). Statistics stay per learned language: changing the via changes no number, only the meanings shown with the hardest words.
- 2026-11-04 (Kirill): Greek via Russian is offered as a limited pair (0131): its meanings are in English. Applied here: the hardest words show their meaning in the pair's meanings language (English for Greek via Russian); every number stays per learned language.
- 2026-11-04 (Kirill): nothing is cut from 2.0 if it runs late: the release date moves instead (0131). This replaces the cut order for the streak calendar, the conjugation block and #165.
- 2026-11-03 (Kirill, Open question 1): the forecast predicts "all learned" (both cards at 30 days).
- 2026-11-03 (Kirill): the forecast's pace is a sliding window of the last 30 days, or of the days since the list's first started word when fewer.
- 2026-11-03 (Kirill, Open question 2): a past day keeps the goal in force when it ended, as usual in streak apps.
- 2026-11-03 (Kirill, Open question 3): freezes accumulate: every Monday adds one, up to 3 in stock. A freeze is spent only when it saves a streak.
- 2026-11-03 (Kirill, Open question 4): every exercise item counts toward the goal: each question of a session, a trainer or mistakes practice, each matched pair and each drill question.
- 2026-11-03 (Kirill, Open question 5): Statistics shows the best streak next to the current one.
- #166: everything stays on the device.

### Out of scope

Achievements (#149). The widget (#150). Charts beyond 30 days. Statistics export. A streak repair. Streak notifications: the only notification is 0131's reminder. Sync of statistics.

## Design

### Inputs from 0131

| 0131 data | Used for |
|---|---|
| `learn_review`: `day`, `answered_at`, `kind`, `facet`, `exercise`, `run_id`, `outcome`, `introduced`, `duration_ms`, `lang`, `word` | Every count, accuracy and the hardest words |
| `learn_card`: `step`, `due_day`, `last_day`, `suspended` | Stages, list progress, forecast, next review |
| `learn_word`: `term`, `translation`, `translation_lang`, `source`, `headword`, `introduced_day` | The hardest words' text and meaning, opening the Definition (`EntryKey(source, headword)`), the per-list pace |
| `WordStatus`, `FixedLadder` intervals, `LearningClock`, `LearnDay` | Stages and dates |
| `recordAnswer` | Gains the goal write below |

### Data: migration `166-1-daily-goal` (#163)

```sql
CREATE TABLE learn_day (
    day   TEXT PRIMARY KEY,     -- local day, as learn_review.day
    goal  INTEGER NOT NULL      -- the daily goal in force when the day ended
) WITHOUT ROWID;
```

- **Writes**:
  - `recordAnswer` (0131) takes the current goal and runs `INSERT OR IGNORE INTO learn_day(day, goal)` in its transaction;
  - a change of the goal in Settings calls `setGoal(_:today:)`, which upserts today's row. So a day keeps the last goal set before it ended.
- **Reads**: a day with answers but no row (written before #163, development builds only) uses the current goal. There is no backfill.
- `clearLearning()` (`-resetData`) clears the table too.

### Aggregates (#163)

These are pure, in `Models/Learning.swift`, and tested without a database.

- `ReviewSummary.of(_ rows:) -> ReviewSummary`: exercises, right, accuracy, new words, reviewed words, time. It serves Today, the run summary (0131) and each day of the chart.
- `DailySeries.last30(_ counts:, today:) -> [DayPoint]`: days without answers are 0.
- `Streak.compute(counts:goals:currentGoal:today:) -> StreakState`. The result has `current`, `best`, `freezes` (in stock, 0 to 3) and a mark per day: met, frozen, missed, open, none.

  ```
  current = 0, best = 0, freezes = 0
  for d in firstDayWithAnswers ... today:
      if d is a Monday { freezes = min(freezes + 1, 3) }   // ISO weekday, in every locale
      goal = d == today ? currentGoal : (goals[d] ?? currentGoal)
      if counts[d] >= goal        { current += 1; mark met }
      else if d == today          { mark open }
      else if current > 0 && freezes > 0 { freezes -= 1; mark frozen }
      else                        { current = 0; mark missed }
      best = max(best, current)
  // freezes: the stock left today
  ```

  Days come from 0131's `LearnDay`: the Gregorian calendar, the current time zone, ISO weeks whatever the locale's first weekday. A few years of days is a few thousand steps.
- `Accuracy.byDirection(_:)` and `Accuracy.byTense(_:)`.
- `HardestWords.rank(_:limit:)`: most wrong first, then lower accuracy, then the latest mistake. Only words with at least one mistake.
- `ListProgress.of(items:states:) -> ListProgress`: new, learning, learned, and the day each started word was started (`startedDays`), from which the forecast counts the last 30 days.
- `Forecast.days(progress:states:today:) -> Forecast?`, one of `.days(n)` (n ≥ 1), `.noPace` and `.done`, or nil for an empty list, which shows no forecast:
  - pace = words of the list started in the last 30 days (today and the 29 before) ÷ 30, a sliding window as in Anki's month view; when the list's first word was started fewer than 30 days ago, ÷ the days since then, today included. Raising the daily limit improves the forecast day by day;
  - a learning word needs the larger of its two cards' `daysToLearned`. For a card, that is `max(0, due − today)` plus the intervals from its next rung up to the 14-day rung: on rung 0, 1 + 3 + 7 + 14 = 25; on rung 4, 0;
  - no new words: the largest of those, or `.done` when nothing is learning either;
  - new words and pace 0: `.noPace`;
  - otherwise: the larger of `ceil(new ÷ pace) + 25` and the learning words' largest.
  - Shown as "~N days" up to 365, else "over a year".
  - Example: Greek A1 with 1,458 words, 120 learned, 300 learning, 1,038 new and 300 started in the last 30 days. The pace is 10 a day, so ceil(1,038 ÷ 10) + 25 = 129: "All learned in ~129 days".
- `ChartSummary`: the VoiceOver texts (#164).
- `WordStatusText.lines(state:errors:today:locale:)`: the lines for #165, in #165.

### Queries (#163)

All in `DatabaseService`, behind `userPool()`. The reads go through `read`; `setGoal` is a plain user-database write, never retried (0131). Each uses an index or reads a small table.

| Method | SQL |
|---|---|
| `dayCounts() -> [LearnDay: DayCount]` | `SELECT day, COUNT(*), SUM(outcome <> 'wrong'), SUM(MIN(duration_ms, 60000)), SUM(introduced) FROM learn_review GROUP BY day`: one row per active day |
| `learnDayGoals() -> [LearnDay: Int]` | `SELECT day, goal FROM learn_day` |
| `reviewRows(day:lang:)`, `reviewRows(run:)` | The rows `ReviewSummary` needs (distinct reviewed words), on 0131's `learn_review_day` and `learn_review_run` indexes |
| `directionAccuracy(since:lang:)` | `GROUP BY kind` over recognition and production |
| `hardestWords(since:lang:limit:)` | `GROUP BY lang, word` over every word-card row since the day (recognition and production): all answers, wrong ones and the latest wrong `answered_at`, kept when one is wrong (`HAVING`), so accuracy counts every answer; joined to `learn_word` for the entry's `source` and `headword`, `term`, `translation` and `translation_lang` (0131), from which #164 gets the meaning in the meanings language |
| `tenseAccuracy(since:lang:)`, `hardestVerbs(since:lang:limit:)` | `kind = 'conjugation'`, `GROUP BY facet`, merged by tense (the part before the dot) in `Accuracy.byTense`, and `GROUP BY word`, the verbs with `hardestWords`' three aggregates |
| `wordStates(lang:) -> [WordKey: WordLearningState]` | Every word of the language with its cards, one query, for list progress |
| `errorCount(lang:word:)` | #165: `COUNT(*)` of `learn_review` where `lang = ? AND word = ? AND kind IN ('recognition', 'production') AND outcome = 'wrong'`, on the `learn_review_word` index |
| `setGoal(_:today:)` | Upsert of today's `learn_day` row |

- **Per language**: `dayCounts`, `learnDayGoals`, `reviewRows(run:)` and `setGoal` read every language (the goal, the streak, the chart; a run has one language). `errorCount` reads one word, by its `lang` and `word`. The others take the chosen `lang` and add `lang = ?`: `reviewRows(day:lang:)`, `directionAccuracy(since:lang:)`, `hardestWords(since:lang:limit:)`, `tenseAccuracy(since:lang:)`, `hardestVerbs(since:lang:limit:)`, `wordStates(lang:)`.
- **Lists** come from E3 (0130, "For E4 and E10"). A list's progress is `ListProgress.of` over `wordListItems(id).map(\.key)` (E3's `WordKey`, the key of 0131's cards) and `wordStates(lang:)`. A list has one language; My words keeps only its keys of the chosen language.
  - E3's `WordListsView` rows take an optional `ListProgress` and hide the bar while it is nil.
  - #164 fills it through `WordListsViewModel` and tests it, which is the progress half of #154's criterion. If #154 merges after #164, #154 fills it with the same function.
- **Performance targets**, measured by QA on the iPhone 15 Pro simulator (iOS 17.5, median of 3) and recorded in History:
  - with a fixture of one year at 50 answers a day (18k rows, 5,000 words): the Learn home loads in under 100 ms and the statistics screen in under 300 ms;
  - with 50k rows: the statistics screen still loads in under 300 ms.

### Screen (#164)

- `StatisticsViewModel` (`@MainActor`, in `LearnViewModel.swift`) loads every block in one `load()` with `async let`, on `LearningClock.today` and the chosen language (`learning_language`, 0131). A switch reloads the per-language blocks; the screen reuses 0131's `LearningLanguagePicker`, shown with two or more languages.
- `StatisticsView` goes in `Views/StatisticsView.swift`, created by 0131's Xcode step. It is a `List` with one section per block.
- **Charts** use Swift Charts (`import Charts`, a system framework since iOS 16):
  - the 30-day `BarMark`s plus a `RuleMark` at the goal;
  - the tenses as horizontal `BarMark`s.
  - Each chart is `.accessibilityElement(children: .ignore)` with its `ChartSummary` label.
- **The calendar** is a 5 × 7 `Grid`. Each day is one accessibility element.
- **Hardest words**:
  - each row shows the word's `term` and its meaning in the chosen language's meanings language (0131), as in 0131's exercises: `StatisticsViewModel` passes the 20 words to 0131's `meanings(of:lang:meaningsLang:sourceOrder:)` (a list translation in that language, else the pair dictionary's first sense). A via change reloads the block's meanings, not its counts;
  - a row whose `EntryKey(source, headword)` resolves is a `NavigationLink` to `DefinitionView`;
  - a row that does not resolve (a list word without an entry, a removed import) shows the same text without a link.
- **Learn home**: `GoalRingView` (a trimmed `Circle` with "12/20", read as "Daily goal: 12 of 20 exercises") and `StreakBadge` ("5-day streak, 2 freezes") join the Today section of `LearnView`. Both open Statistics, as does the `learn_statistics_row`.
- **Conjugation block**: E5 supplies the tense titles and their order (`ConjugationFacet`). The block is built only when drill rows exist.

### Definition (#165)

- `DefinitionViewModel` already loads `learning: WordLearningState?` for the Learn button (0131, #158). #165 adds `errorCount`, and a `LearningStatusView` under the part of speech that renders `WordStatusText`.
- Dates use the in-app locale (`LocalizationManager.currentLocale`), with catalog keys for "today" and "tomorrow".

### For E5 (#132)

E5's rows are those in 0131 "For E5": kind `conjugation`, `facet` `<tense>.<voice>`, `detail` the person. Accuracy by tense groups by the part of `facet` before the dot, both voices together, and the hardest verbs group by `word`. Drill items count toward the goal and the streak with no extra code. The tests use fixture rows, so #164 does not wait for E5.

### Identifiers

| Element | Identifier |
|---|---|
| Learn home | `learn_goal_ring` (value `12/20`), `learn_streak` (value `5`), `learn_statistics_row` |
| Screen | `stats_view`, `stats_language_switch`, `stats_empty`, `stats_today_exercises`, `stats_today_new`, `stats_today_reviewed`, `stats_today_accuracy`, `stats_today_time`, `stats_streak_current`, `stats_streak_best`, `stats_streak_freeze`, `stats_streak_day_<YYYY-MM-DD>` (value `met`, `frozen`, `missed`, `open`), `stats_chart_30d`, `stats_list_<list id>`, `stats_list_forecast_<list id>`, `stats_accuracy_recognition`, `stats_accuracy_production`, `stats_hardest_<n>`, `stats_tense_<tense>`, `stats_hardest_verb_<n>` |
| Definition | `learning_status` |

### Strings

- About 35 new keys in all 5 languages: `stats.*`, `status.*`, `learn.goal.*`, `learn.streak.*`.
- Counts use plural variants.
- Chart summaries are composed with the in-app bundle (`SettingsViewModel.localizedString`). In Arabic they start with U+200F (#119).

### Code map

| Path | Change |
|---|---|
| `Models/Learning.swift` | `ReviewSummary`, `DailySeries`, `Streak`, `Accuracy`, `HardestWords`, `ListProgress`, `Forecast` (#163), `ChartSummary` (#164), `WordStatusText` (#165) |
| `Services/DatabaseService.swift` | Migration `166-1-daily-goal`, the goal write in `recordAnswer`, `setGoal`, the queries (#163) |
| `ViewModels/LearnViewModel.swift` | `StatisticsViewModel`; goal and streak in `LearnViewModel` (#164) |
| `Views/StatisticsView.swift` (new, 0131's Xcode step) | The screen, charts and calendar (#164) |
| `Views/LearnView.swift` | `GoalRingView`, `StreakBadge`, the Statistics row (#164) |
| `ViewModels/DefinitionViewModel.swift`, `Views/DefinitionView.swift` | `LearningStatusView` (#165) |
| `ViewModels/SettingsViewModel.swift` | A goal change calls `setGoal` (#163, wired by #162) |
| `ViewModels/WordListsViewModel.swift` (E3's file, 0130) | Each list row's `ListProgress` (#164) |
| `Resources/Localizable.xcstrings` | The keys |
| `DictAppUITests/…` | `StatisticsPage`, `StatisticsFlowTests` |

### Tickets, order and sizes

| Ticket | Scope | Needs | Size (pipeline days) | Stream |
|---|---|---|---|---|
| #163 | `learn_day`, the goal write, the aggregates, the queries, `ReviewSummary`. Unit tests only | 0131 #157 | M, 1 | A (data), in parallel with #158 and #159 |
| #164 | The statistics screen with its language switch and per-language blocks; the hardest words' meanings in the meanings language; the ring and the streak on the Learn home; the progress bar on E3's list rows | #163, 0131 #158, #159 (`meanings`); E3 #151 for the Lists block, #154 for its rows | M–L, 2.75 | B or C, with #161 and #162 |
| #165 | The Definition status | 0131 #157, #158 | S, 0.5 | Any, with #161 and #162 |

The dates are to be replanned with #237 (0131, Decisions); the order stays as in 0131's calendar. Learning pairs add 0.25 to #164: the hardest words' meanings in the via, and `translation_lang` in #163's `hardestWords` (#163 adds it if it has not merged yet, else #164). #163's aggregates do not change. If the checkpoint slips, nothing is cut: the release date moves (Kirill, 2026-11-04, Decisions).

## Test plan

- Unit classes go in `DictAppTests.swift`. Database and async classes are `@MainActor` (#229).
- The pure classes use fixed days and no clock.
- UI tests use the DEBUG fixture `-learningFixture stats`, written relative to today:
  - 30 days of answers for 8 Greek words, with the goal met on known days, one frozen day and one reset, so the streak is current 9, best 12;
  - three words with 5, 3 and 2 mistakes;
  - a learned, a learning and a new word;
  - 40 `conjugation` rows over 3 tenses, one of them in both voices (4 facets);
  - 2 English words answered on 3 days whose goal the Greek answers already meet, so the streak stays the same;
  - `learning_languages` set to Greek and English.

| Acceptance criterion | Test |
|---|---|
| #166, #163: today's numbers match the answer log | Unit `ReviewSummaryTests.testNumbersFromRows` (each definition above: accent counts as right, time capped at 60 s, a word is new once); `LearningStatsStoreTests.testTodayMatchesTheLog` (answers through `recordAnswer`, match and drill rows included, then Today), `testRunSummaryAndTodayAgree`. UI `StatisticsFlowTests.testTodayAfterAnswers` (3 trainer answers: Today shows 3, the ring 3/20) |
| #163: streak rules: goal met → +1; a miss spends a freeze; a miss without one → 0; Monday adds a freeze, up to 3 (fixed calendar) | Unit `StreakTests`: `testGoalMetAddsOne`, `testMissSpendsAFreeze`, `testMissWithoutAFreezeResets`, `testMondayAddsAFreeze`, `testFirstPartialWeekHasNoFreeze` (first answers on a Wednesday, goal met; Thursday missed: the streak is 0), `testFreezesCarryOverUpToThree`, `testTwoMissesInAWeekWithTwoFreezes`, `testSundayMissThenMondayMiss`, `testTodayUnmetIsOpenNotMissed`, `testTodayMetCounts`, `testFreezeKeptWithoutAStreak`, `testLongGapResets`, `testPastDaysKeepTheirGoal`, `testBestStreak`, `testWeeksStartOnMondayInEveryLocale` (en-US, ar); `LearningStatsStoreTests.testGoalChangeUpsertsToday`, `testFirstAnswerRecordsTheDaysGoal` |
| #163: per-list counts and the forecast correct on fixtures | Unit `ListProgressTests`: `testNewLearningLearned` (a paused word counts as new; a word twice in a list counts once), `testForecastFromTheLastThirtyDays` (the A1 example: 129), `testForecastWithShortHistory` (50 words started over 5 days: pace 10), `testForecastWithoutPace`, `testForecastWhenEveryWordIsStarted`, `testAllLearned`, `testDaysToLearnedPerRung` |
| #154 (0130, progress half): every list shows its progress | Unit `ListProgressTests.testProgressOverE3Keys` (a fake E3 list whose keys are cards in every state, a standalone word among them). UI `WordListsFlowTests.testListRowsShowProgress` (`-learningFixture stats`: the Greek A1 row's bar reads its learned / learning / new; a list with no started word shows the bar at new) |
| #163: unit tests for every aggregate | The classes above, plus `DailySeriesTests`, `AccuracyTests`, `HardestWordsTests`, `ChartSummaryTests`, `WordStatusTextTests` |
| Kirill 2026-11-04: statistics stay per learned language; the via changes only the meanings shown | Unit `StatisticsViewModelTests.testViaChangesOnlyTheMeanings` (a temp database with two English words answered wrong and the Spanish pack through `PackFixtures`; English via English, then via Spanish: every number and the order of the hardest words unchanged; their meanings WordNet's, then En–Es · FD's), `testLimitedPairShowsEnglishMeanings` (a Greek word answered wrong, Greek via English, then via Russian: the same English meaning and the same numbers) |
| #166, #164: a 30-day chart and the 20 hardest words, each opening its Definition | Unit `DailySeriesTests.testThirtyDaysWithZeros`; `HardestWordsTests.testOrdering` (mistakes, then accuracy, then the latest), `LearningStatsStoreTests.testHardestWordsCountEveryAnswer` (a word wrong 2 times in 10: 2 mistakes, 80%, its latest mistake the last wrong answer, not the last answer), `testOnlyTheLast30Days`, `testAtMost20`. UI `StatisticsFlowTests.testChartAndHardestWords` (the chart and its summary; row 1 is the word with 5 mistakes; a tap opens its Definition) |
| #166, #163, #164: accuracy by direction and by tense; the hardest verbs | Unit `AccuracyTests.testByDirection` (match counts as recognition, accent as right), `testByTenseFromDrillRows` (both voices of a tense in one group); `HardestWordsTests.testHardestVerbs`. UI `StatisticsFlowTests.testConjugationBlock` (the fixture's 3 tenses), `testNoDrillAnswersNoBlock` |
| #166 (Kirill, 2026-11-03): progress per language; the goal and the streak shared | Unit `StatisticsViewModelTests.testBlocksFollowTheChosenLanguage` (`stats` fixture: Greek and English give different Today numbers, lists, accuracy and hardest words; the goal, the streak and the chart are the same for both), `LearningStatsStoreTests.testEveryLanguageCountsTowardTheGoal` (a Greek and an English answer: the day counts 2), `ListProgressTests.testMyWordsPerLanguage`, `StatisticsViewModelTests.testOnlyLearnedLanguages` (English stopped: no switch, no English numbers; the streak still counts its past answers). UI `StatisticsFlowTests.testLanguageSwitch` (the switch shows; English: `stats_today_new` changes, `stats_streak_current` stays 9) |
| #164: every block shows the numbers from the aggregates | Unit `StatisticsViewModelTests.testBlocksEqualTheAggregates` (a temp database with the `stats` fixture) |
| #166, #164: VoiceOver reads each chart as a short summary | Unit `ChartSummaryTests` (the texts in 5 languages; Arabic starts with U+200F). UI `StatisticsFlowTests.testChartsHaveSummaries` (the label of `stats_chart_30d` and of the conjugation chart) |
| #165: a learned, a learning and a new word show the right status and dates | Unit `WordStatusTextTests` (the three states; today, tomorrow and a date; mistakes); `LearningStatsStoreTests.testErrorCountForAWord` (only the word's recognition and production rows: a conjugation row and the same spelling in another language do not count). UI `StatisticsFlowTests.testDefinitionShowsStatus` (the fixture's three words) |
| #165: words not in learning show nothing extra | UI `StatisticsFlowTests.testDefinitionWithoutLearningShowsNothing` (a word never added, and a paused word: no `learning_status`) |
| #166: nothing leaves the device | Review: no networking API in the diff; the app makes no network calls of its own (overview) |
| #166, #164: 5 UI languages, Arabic right to left, iPhone and iPad, iOS 17.5 and 26.4 | `testEveryCatalogKeyIsTranslatedInEveryShippedLanguage`; UI `ArabicLocalizationTests.testStatisticsRightToLeft` (today's bar at the left edge), `GreekLocalizationTests.testStatisticsInGreek`, `iPadSpecificTests.testStatisticsOnIPad`; the matrix run of `StatisticsFlowTests` |
| Performance | QA: the 1-year and 50k-row fixtures. The Learn home under 100 ms and the statistics screen under 300 ms, recorded in History |

## Open questions

1. **What the forecast predicts.** Resolved 2026-11-03: all learned (Decisions).
2. **Changing the daily goal.** Resolved 2026-11-03: past days keep their goal (Decisions).
3. **The weekly freeze.** Resolved 2026-11-03: freezes accumulate, up to 3 (Decisions).
4. **What counts toward the goal.** Resolved 2026-11-03: every exercise item (Decisions).
5. **Best streak.** Resolved 2026-11-03: shown (Decisions).

A day starts at 4 AM local time (0131, Decisions), here too.

## History

- 2026-11-03: First draft, designed with E4 (0131) and aligned with E3's draft (0130):
  - list progress runs over E3's `WordKey`s;
  - E3's list rows take the optional `ListProgress`, which #164 fills;
  - the hardest words show a list word's stored text and open no Definition when it has no entry.
- 2026-11-03: Aligned with 0130's checked lists (Open question 6): the Lists block shows every checked list instead of one learning list.
- 2026-11-03: Learning is per language (Kirill): the statistics screen gets 0131's language switch and shows the chosen language, except the goal, the streak and the 30-day chart, which count every language; the queries take `lang`; #164 grows by 0.5 day.
- 2026-11-03: Learning a language is explicit (Kirill, 0131): the switch shows the learned languages, a stopped language's numbers are hidden while its past answers still count for the goal and the streak; the `stats` fixture sets `learning_languages`; dates are to be replanned with #237.
- 2026-11-04: Review fixes: accuracy by tense groups both voices of a tense, on the part of `facet` before the dot (`Accuracy.byTense`, `tenseAccuracy`, `stats_tense_<tense>`, a fixture tense in both voices); `setGoal` is a write, not a `read`.
- 2026-11-04: Approved by Kirill.
- 2026-11-04: Learning is chosen as a language pair (Kirill, 0131): numbers stay per learned language; the hardest words show their meaning in the language's via, through 0131's `meanings` (#164 +0.25). Nothing is cut if late: the release date moves (Kirill).
- 2026-11-04: Review fix: the Per language row now says plainly that the goal, goal met, the streak and the 30-day chart count every language.
- 2026-11-04: Greek via Russian is offered as a limited pair (Kirill, 0131): the hardest words' meanings follow the pair's meanings language (English for it); a test covers it. No size change.
- 2026-11-04: Review fixes after approval: a freeze comes on Mondays only, as the rules say (the pseudocode also gave one in a first week that starts after Monday); the hardest words and verbs aggregate every answer on their cards, with the latest wrong one, so accuracy is right. Tests added.
- 2026-11-05: Review fixes after approval: `translation_lang` is in the `learn_word` inputs; the query table names the `lang` argument of every per-language query; `errorCount` counts only the word's own recognition and production mistakes, with its test.
- 2026-11-05: Review fix: `reviewRows(run:)` reads 0131's new `learn_review_run` index instead of scanning the log.
- 2026-11-06: #163: a word started in a day or a run counts as new there, never also as reviewed (PM, 2026-11-04).
- 2026-11-06: #163: in list progress a word enrolled but never answered is new, as `WordStatus` shows it (PM, 2026-11-04).
- 2026-11-06: #163: an empty list has no forecast (nil), and a forecast is at least "~1 day", never "~0 days" (PM, 2026-11-04).
- 2026-11-06: #163: `ChartSummary` moves to #164 and `WordStatusText` to #165, with their tests, next to the screens that read them.
- 2026-11-06: #163: `tenseAccuracy` groups by `facet` in SQL and merges the voices of a tense in `Accuracy.byTense`.
- 2026-11-06: #163: `ListProgress` keeps `startedDays`, the day each started word was started, and the forecast counts the last 30 days from it.
- 2026-11-06: #163: `hardestWords` and `hardestVerbs` keep the log id of the latest wrong answer, which orders like `answered_at`.
- 2026-11-06: #163: built when `learn_review` had no `run_id` index, `reviewRows(run:)` scanned the log; rebased on #157, it reads `learn_review_run`.
- 2026-11-07: #164 as built: the `stats` fixture has 2 frozen days (a reset after a 12-day streak spends at least 2 Monday freezes); extra ids `stats_chart_tenses`, `stats_chart_start`, `stats_chart_end`, calendar value `none`, `stats_hardest_<n>` from 1; tense rows sit below the tense chart to carry `stats_tense_<tense>`; list titles are built in code until E3's title keys; `ListProgressReader` and `ListProgressBar` are for #154, which also writes `testListRowsShowProgress`; the forecast text lives in `StatisticsViewModel.forecastText`; the Arabic test reads the chart bars from a screenshot. `ConjugationTense` here is a subset of #167's (same names, raw values, order); whichever merges second keeps #167's.
- 2026-11-07: #164 performance, measured in a Debug build on iPhone 17 iOS 26.4: Statistics loads in about 420 ms (target 300) and the Learn home in 255 ms (target 100); #164 adds about 10 ms, the rest is #163's `wordStates` (231 ms) and `Forecast.days` (84 ms). To be measured in Release and fixed in a follow-up before release.
- 2026-11-08: #164 rebased on #154 and #167: it keeps #167's `ConjugationTense` and adds only `text`, `title(of:)` and `ordered`; the Lists block takes #154's `ListProgressReader`, `ListProgressBar`, `stats.list.*` strings and list titles (`WordListsViewModel.title(of:locale:)`), and #154's `testListRowsShowProgress` covers the rows. The Statistics row sits below E3's Lists section.
- 2026-11-07: #165 as built: the mistakes line is hidden at 0; a learned word also shows the per-card line; an overdue word reads "today"; a word of a language not learned or stopped shows no status (as Statistics hides a stopped language's numbers, 2026-11-03); the card stages use `status.card.*` keys. The UI tests are `WordStatusFlowTests` on the `due` fixture until #164's `StatisticsFlowTests` and `stats` fixture are on master.
