# Intel x86_64 CI — setup and operational recipe

Canonical setup and run recipe for the Intel Mac mini that serves as this
project's CI target. Replaces the recipe fragments previously scattered
across project memories.

## Environment

- **Host:** Intel Mac mini, macOS 15.x, Xcode 16.4, iPhone 16 Pro
  simulator (iOS 18.5), x86_64.
- **Why Intel:** iOS 17.x was the last simulator runtime with x86_64
  support. Apple's iOS 18+ / iOS 26 simulators are arm64-only — they
  don't run on Intel hardware. `IPHONEOS_DEPLOYMENT_TARGET = 17.0`
  across all targets (per #57) so master builds cleanly on this host.
- **SSH-driven:** all commands below assume `ssh sevastanuhin@<mini>`.
  Non-interactive SSH PATH is `/usr/bin:/bin:/usr/sbin:/sbin` — excludes
  Homebrew's `/usr/local/bin`.

## One-time setup — Git LFS (the historical real blocker)

`DictApp/DictApp/Resources/seed.sqlite` is a ~104 MB Git-LFS object.
Without LFS materialization the on-disk file is a 134-byte pointer; the
app crashes on database open at launch and **every UI test fails with a
generic timeout** — looks like UI flake but is a data-layer setup
failure.

```bash
# git-lfs must be installed (e.g. `brew install git-lfs`).
# SSH PATH excludes /usr/local/bin — must prepend for LFS ops:
export PATH=/usr/local/bin:$PATH

cd ~/dict-app
git lfs install      # configures repo's smudge/clean filters (once)
git lfs pull         # materializes the real seed.sqlite

# Verify:
ls -la DictApp/DictApp/Resources/seed.sqlite       # ~104 MB
head -c 16 DictApp/DictApp/Resources/seed.sqlite   # "SQLite format 3"
```

The build itself does not need `git-lfs` on PATH (the file is on disk
by build time).

## The canonical run recipe

**Per-suite execution.** Never run the full `DictAppUITests` bundle —
cross-suite contamination triggers `HistoryFlowTests` warm-run flakes,
language-bleed in `ArabicLocalizationTests`, and other documented
artifacts.

**Pre-warm + no-uninstall + `-resetData`** for most suites:

```bash
xcodebuild test \
  -project DictApp/DictApp.xcodeproj \
  -scheme DictApp \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:DictAppUITests/<SuiteName> \
  ALWAYS_EXTRA_FLAGS='-resetData'
```

**Uninstall-between** for cold-seed-sensitive suites (the AC-binding
recipe per #62/#66) — runs the one-time ~306k-row seed import on every
test:

```bash
xcrun simctl uninstall booted com.kyukhin.DictApp   # before each run
```

## Per-language-suite discipline

`LocalizationManager` snapshots the persisted UI language at init,
*before* any `-resetData` runs. Consequence: running `ArabicLocalizationTests`
immediately after `SpanishLocalizationTests` (or any language suite) in
the same sim session triggers persisted-language bleed — Arabic suite
launches in Spanish, asserts fail.

**Rule:** erase the simulator between language-suite runs, not just
between in-suite tests. Practical: `xcrun simctl erase booted` between
`SpanishLocalizationTests` and `ArabicLocalizationTests`.

## Expected results (current master)

| Suite | Recipe | Expected |
|---|---|---|
| `HistoryFlowTests` | per-suite | 9/9 |
| `SearchFlowTests` | per-suite | 6 pass + 1 skip (`testSearchToDefinitionNavigation`) |
| `NavigationTests` | per-suite | 10/10 |
| `BookmarkFlowTests` | per-suite | 8/8 |
| `LaunchTests` | per-suite | 32/32 |
| `ReportBugFlowTests` | per-suite | 0 pass + 1 skip (`testReportBugFallbackAlertAndCopyAddress`, Intel/iOS-18.x) |
| `VersionDisplayTests` | per-suite | 1/1 |
| `SpanishLocalizationTests` | uninstall-between | 3/3 cold-seed |
| `ArabicLocalizationTests` | uninstall-between, erased sim | 5/5 cold-seed |
| `iPadSpecificTests` | per-suite | 2 skipped (iPhone destination) |

Total: every UI suite either passes or skips with the skip linked to a
tracking ticket. Zero non-skip failures.

## Known accepted skips

- **`SearchFlowTests.testSearchToDefinitionNavigation`** — `XCTSkip` on
  Intel x86_64 + iOS 18.x sim, per #60. Root cause: SwiftUI `List`
  drops long-definition `EntryRow` cells from the rendered cell tree
  on iOS 18.5 (definition-length triggered, def_len > ~122 chars).
  The test's probe loop cannot reach the matching result because the
  cells aren't in the tree. Open investigation — separate from CI
  greenness.

- **`ReportBugFlowTests.testReportBugFallbackAlertAndCopyAddress`** —
  `XCTSkip` on Intel x86_64 + iOS 18.x sim, per #60. Root cause:
  `report_bug_button` sits below `dictionaryManagementSection`, whose
  async `loadDictionaries()` expands the section from a "loading" row to
  N rows in one shot; on the slow Intel sim that empty→populated reflow
  drops the below-fold support row from the virtualised AX tree mid-
  interaction → transient "No matches found". Identity-pinning (`.id`)
  does not fix it (probed) — it's reflow/virtualization-driven. The
  test-side `scrollToElement` geometry hardening keeps it green on
  arm64 / iOS 26; the production fix (remove the reflow) is deferred per
  Test-Driven Stability. Full analysis: project memory
  `project_settings_dictionary_section_reflow`.

## When something fails — diagnostic ladder

1. **Was the seed materialized?** `ls -la DictApp/DictApp/Resources/seed.sqlite`.
   If 134 bytes, run the LFS setup above. Looks like UI flake but is
   a data-layer setup failure.
2. **Is the sim in landscape?** Code now forces `.portrait` in setUp
   defensively, but if the line was removed, landscape no-ops `swipeUp`
   on SwiftUI Form/List scroll views.
3. **Did you run the full bundle?** Switch to per-suite. Full-bundle
   marathon triggers cross-suite contamination.
4. **Did you chain language suites?** Erase the sim between them.
5. **Is it `HistoryFlowTests` or a Search/Nav test in isolation?**
   On *Intel* this is unexpected — file a ticket. On *arm64 dev sim*
   it's `#67` family (Xcode 26 / iPhone 15 Pro environmental flakiness).
   The Intel mini is the authoritative test target.

## Related project memories

- `project-ui-flake-investigation-recipe` — per-suite discipline
- `project-remote-mac-mini-ssh-testing` — SSH PATH, LFS, sim quirks
- `project-arabic-intel-recipe-catch22` — RESOLVED-by-#62
- `project-spanish-selectlanguage-coldseed-race` — RESOLVED-by-#66
- `project-xcuitest-orientation-landscape-swipe` — portrait-force rationale
- `project-issue56-getresultscount-countrace` — lazy-List `cells.count`
- `project-swiftui-navback-button-label` — back-button label gotcha
