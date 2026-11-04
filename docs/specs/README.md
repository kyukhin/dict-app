# Specs

LibreDict is developed spec-first. Every feature (epic) has a spec in this folder. Specs are committed together with the code that implements them and describe how the feature works now.

## Rules

1. **Read first.** Before designing, coding, testing or reviewing, read this index, `0000-overview.md` and the specs of every area you touch. Bootstrap: while `0000-overview.md` does not exist, the Architect writes it first (as Draft) and the other agents skip it.
2. **One spec per epic:** `NNNN-slug.md`, where `NNNN` is the epic's issue number, zero-padded. Bug fixes and small tickets update the spec of their area. Every spec has a row in the index below; update the row when a spec is created, renamed or changes status.
3. **Statuses:** Planned (listed in the index, not written yet) → Draft (written, waiting for review) → Approved (Kirill reviewed the whole spec; the header records his approval and its date) → Implemented. No development before Approved.
4. **Spec and code travel together.** The PR that implements a ticket updates its spec (decisions, test plan, status). Any deviation found during development is written into the spec in the same PR, with the reason. If the deviation is visible to the user or changes the architecture (data model, storage, migrations, module boundaries, dependencies), the spec goes back to Draft and the PR waits for Kirill's re-approval. Smaller implementation details only get a History line, and the PR is flagged "spec changed" in the daily merge batch.
5. **Implemented:** when the epic's last ticket merges, the status becomes Implemented. Later changes keep the spec current and add a line to its History.
6. **Authorship:** every spec states in its header that it was written by Claude (AI). Commit messages and PR descriptions don't mention it.
7. **Style:** English, short and concrete. A spec is read before every task.

## Template

```markdown
# <Feature>

> Spec written by Claude (AI) for LibreDict.
> Status: Draft | Approved by Kirill on YYYY-MM-DD | Implemented · Epic: #N · Tickets: #A, #B · Updated: YYYY-MM-DD

## Why
The problem and who it is for.

## Behaviour
What the user sees and does. Product decisions with their date.

## Design
Data, modules, APIs, migrations, constraints. Links to the code.

## Test plan
| Acceptance criterion | Test |
|---|---|

## Open questions

## History
- YYYY-MM-DD: what changed and why.
```

## Index

| Spec | Status | Epic |
|---|---|---|
| `0000-overview.md`: the app today (data pipeline, database, search, screens, tests) | Approved | — |
| `0129-dictionary-file.md`: dictionaries as read-only files (the English bundle and the attached language packs), the user database, the 1.x migration, reopening an invalidated file | Approved | #129 |
| `0130-word-lists.md`: word lists by level (Greek A1–B1, English A1–C2), My words as a list, the Lists screen, list import | Approved | #130 |
| `0131-learning.md`: learning words with spaced repetition (cards, the answer log, sessions, exercises, match the pairs, mistakes, the Learn tab replacing Bookmarks, learning settings and the reminder) | Approved | #131 |
| `0132-conjugation-drill.md`: the Greek conjugation drill (questions and options by level, the drill screen and Practise on Definition, spaced repetition per verb and tense) | Approved | #132 |
| `0134-example-sentences.md`: example sentences from Tatoeba (the pipeline and its pin, the example tables in the Greek and English lists packs, the Examples section on Definition, the example sheet in learning) | Approved | #134 |
| `0136-word-forms.md`: word forms (search by any inflected form, inflection tables) | Implemented | #136 |
| `0146-quick-switch.md`: dictionary chips on Search, one setting with Dictionary Order | Implemented | #146 |
| `0166-learning-statistics.md`: learning statistics (daily goal and streak, today, a 30-day chart, list progress and forecast, hardest words, accuracy by direction and tense, a word's status on Definition) | Approved | #166 |
| `0237-downloads.md`: language packs downloaded at setup (the English-only bundle, packs on GitHub Releases, first launch, Settings → Languages, the 1.x and alpha upgrade, the install API for learning) | Approved | #237 |
