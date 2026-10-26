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
