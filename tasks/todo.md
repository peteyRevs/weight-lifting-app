# Ledger — Plan & progress

Status legend: `[ ]` not started · `[~]` in progress · `[x]` done · `[!]` blocked

Plan documents: `docs/architecture.md` · `docs/engineering-standards.md` ·
`docs/testing-strategy.md` · `docs/ci-cd.md` · `docs/subagent-workflow.md` ·
`docs/product-spec.md` · `docs/product-decisions.md` · `docs/adr/` · `docs/research/`
Feature briefs: `tasks/features/F##-*.md` — all 33 written 2026-09-17; M0's approved with the milestone (2026-09-24).

---

## Phase 0 — Plan review (owner: Pete)

- [ ] Read `docs/architecture.md` and the six ADRs; object or approve.
- [ ] Confirm or override the 20 defaults in `docs/product-decisions.md` (the big ones: no accounts, lb+kg, 4 tabs, watch works standalone).
- [~] Apple setup (identifiers per `docs/product-decisions.md` › Identifiers):
  - [x] Simulator runtimes: iOS 26.5 (23F77) + watchOS 26.5 (23T570) installed 2026-09-19.
  - [x] MCP servers verified 2026-09-19: sosumi, context7, XcodeBuildMCP. `xcode` pending the Intelligence toggle.
  - [x] Bundle ID prefix decided: `com.petearevalo` (2026-09-19).
  - [x] Xcode ▸ Settings ▸ Intelligence ▸ "Allow external agents to use Xcode tools" on (verified 2026-09-26: `xcode` MCP answers).
  - [x] Xcode ▸ Settings ▸ Accounts: signed in (`Apple Development: Peter Arevalo` certificate issued 2026-09-22).
  - [x] Enrolled in the Apple Developer Program as an individual (2026-09-22).
  - [x] Team ID `95JAK545DF` recorded in `Config/Base.xcconfig`; confirmed paid Individual team (Xcode defaults, 2026-09-26).
  - [x] App IDs `com.petearevalo.Ledger` and `com.petearevalo.Ledger.watchkitapp` exist (registered by Xcode; found 2026-09-29). **Pete:** confirm HealthKit is ticked on both before F16.
  - [ ] Register iCloud container `iCloud.com.petearevalo.Ledger` (assigned to the iOS App ID in F28; App Group added in F21/F22).
- [x] Create the GitHub repository (private) and push `main`. (2026-09-18: github.com/peteyRevs/weight-lifting-app)
- [x] Approve starting M0. (Pete, 2026-09-24)

## M0 — Foundation (target: 1.5 weeks; mostly serial)

| ID | Feature | Depends on | Lane |
|---|---|---|---|
| F00 | Project skeleton & local gate (`scripts/check.sh`) | — | A |
| F01 | CI gates (GitHub Actions), Xcode Cloud workflows, release-please | F00 | A |
| F02 | Domain core: models, units, progression, 1RM, plate math, calendar | F00 | B |
| F03 | Exercise catalog seed (~200 exercises) | F02 | C |
| F04 | WorkoutEngine (event-sourced reducer, ADR-004) | F02 | B |
| F05 | Persistence (GRDB schema, repositories, stats queries, event store) | F02, F04 | B |
| F06 | Design system (tokens, Archivo width axis, components, snapshots) | F00 | C |
| F07 | DI keys, composition roots, `LedgerTestSupport` | F05, F06 | A |

- [x] F00 (#1, #3) · [x] F01 (#5) · [x] F02 (#2 → #3) · [x] F03 (#14) · [x] F04 (#8) · [x] F05 (#13, #17, #19, #21) · [x] F06 (#6, #11, #15) · [x] F07 (#22, #24, #25)

### Status — 2026-10-04: M0 complete

- **On `main`:** F00–F07 and F32. Both apps launch to Today on a real database: the catalog is seeded (224 exercises), this device has its row, the HealthKit mirroring handler is assigned first, and a Debug-only menu opens the design gallery and Diagnostics (screenshots in `tasks/features/F07-composition-di/screenshots/`). Releases: v0.2.0–v0.4.0; release PR #23 (0.5.0) is open and is Pete's to merge.
- **CI:** PR CI runs static checks on Linux, then iOS only on the `xcode-27` preview runner (risk R4); watchOS is tested by the full local gate before every merge. Actions is paid since 2026-09-30 with a $60 monthly limit, so a PR is pushed once, after a green local gate. A code PR's `Check` takes 20–29 minutes; the compilation cache restores but has not yet shortened the build (diagnosis queued).
- **Process:** PR size is a 500-line code target with a split above ~1,000 (standards §10). Merging is delegated to the orchestrator unless a PR carries a product or architecture decision (workflow G5).
- **Open for Pete:** the iCloud container (before F28); Xcode Cloud workflows (before F30); confirm HealthKit is ticked on both App IDs (before F16); in Xcode, delete the dangling `Fonts` synchronized group if it is still there.

### F00 delivery — merged 2026-09-27 (#1; the gate's result check landed via #3)

- [x] Scrap the half-built 2026-09-21 `Ledger.xcodeproj` and the duplicate root `Ledger/` folder.
- [x] Tooling: `.xcode-version`, `mise.toml`, `.swiftformat`, `.swiftlint.yml`, `lefthook.yml`.
- [x] Scripts: `bootstrap.sh`, `check.sh`, `check-commit-msg.sh`, `check-package-graph.sh`.
- [x] `Config/{Base,Debug,Release,Ledger,LedgerWatch,Tests}.xcconfig`.
- [x] `LedgerKit`: 19 source targets + 17 test targets, graph recorded, `swift test` green (18 tests).
- [x] `Resources/Fonts/Archivo[wdth,wght].ttf` (+ OFL) — `fvar` verified: wght 100–900, wdth 62–125.
- [x] `Apps/` shells and smoke/UI tests for both apps; `TestPlans/*.xctestplan` ×6.
- [x] Criteria 5 and 7 demonstrated (lint rejects planted violations; hook rejects `added stuff`).
- [x] **Pete:** the Xcode sitting — finished 2026-09-26 (watch folders, xcconfigs, cleared settings, hosts, `LedgerWatchAppKit`, fonts); test plans wired into the schemes by the orchestrator; orphan self-reference removed in a reviewed edit. Committed `1f2991d` / `ff02613` / `7847bb0`.
- [x] `Info.plist` / `.entitlements` moved beside the synchronized folders (fixes `Multiple commands produce Info.plist`; implementation-notes #11).
- [x] `scripts/check.sh` green end to end with the package tests running (2026-09-27): PR-iOS 19 tests, PR-watchOS 10 (was 3 each — LedgerKit had been added as a dependency, so its test targets never existed; now a local package in the project, notes #17). Nightly/Device plans resolve 17/8/1/1 targets. Coverage is plan-wide (Xcode bug); F01's gate filters by path.
- [x] Criteria 1–10 verified against the real project (2026-09-27, fresh clone; two defects fixed — bootstrap SIGPIPE, watch-scheme asset warning; notes #18).
- [x] PR opened: https://github.com/peteyRevs/weight-lifting-app/pull/1 (2026-09-27; criteria table + check.sh output in the body). Awaiting Pete's merge (G5). No CI yet — F01 adds it.

### F02 delivery — merged 2026-09-27 (#2 merged into the F00 branch as its stacked base; landed on `main` via #3 at `10ff661`)

Started 2026-09-26 in parallel with the F00 Xcode sitting (Pete approved). Based on
`00a504b` (F00 scaffolding); rebased onto `main` once F00 merges. Until the Xcode
project is committed the working gate is `scripts/check.sh --fast` plus a
`LedgerDomain` coverage measurement; the full `scripts/check.sh` runs after the rebase.

- [x] G0 brief: `tasks/features/F02-domain-core.md` (14 criteria, test plan) — approved with M0.
- [x] G1 implementer: code + brief's tests, `check.sh --fast` green, coverage ≥ 95 %, implementation notes. (2026-09-26: 148 domain tests, 98.91 % lines; re-run green by orchestrator; committed `f30d94e`. Brief's rest-label example fixed to rule 39 in `76ebbdb`.)
- [x] 500-line PR budget (standards §10): product code is ~2,200 lines. **Pete granted a one-time waiver (2026-09-26)** — F02 ships as one PR; say so in the PR body. (Superseded 2026-09-29: the budget is now a target; split above ~1,000.)
- [x] G2 adversarial tester (round 1): 209 tests, 8 failing from 3 bugs (A 11 kg step, B DST-at-midnight weeks, C 1.25 lb ties) + 7 spec questions. **Pete decided 2026-09-27: exact weights (Decimal grams; amends decision #9 → ADR-007) and a calendar-date program start.** Revision committed `f891e12` (ADR/docs) + `f8e1687` (code + adversarial suite): 367 domain tests green, 98.87 %. Round 2: tester auditing its changed tests + attacking the new Weight/CivilDate surface.
- [x] G2 closed (round 2, 2026-09-27): tester accepted the implementer's test edits, +44 tests, no new bugs; 413 tests green at 2,000 seeds.
- [x] G3 reviewer: approved, 0 Blocking / 4 Should fix / 9 Nits (`review.md`). Should-fix round in progress (CivilDate range, brzycki doc, SessionBuilder day source, lb/kg lint allowlist).
- [x] Rebased onto F00 tip `70b36b5` (clean).
- [x] Should-fix round done (`eb2a30d`); rebased on F00 tip; full `check.sh` green (PR-iOS 431/431, PR-watchOS 422/422, all planned targets ran); host 419 tests; coverage 98.78 %.
- [x] PR opened: https://github.com/peteyRevs/weight-lifting-app/pull/2 (stacked on #1). After #1's squash merge: rebase onto `main`, retarget #2, re-run the gate.

- [x] M0 exit (2026-10-04): both apps build and launch to Today (F07 #25, UI tests and screenshots); `check.sh` and CI green; LedgerDomain coverage 99.11 %; Archivo width axis verified on the watch simulator (F06 slice 1, risk R2 closed).

## M1 — iPhone core loop (target: 3 weeks; up to 3 lanes in parallel)

| ID | Feature | Depends on |
|---|---|---|
| F08 | Onboarding → template program generation | F07 |
| F09 | Today | F07 |
| F10 | Active workout (phone): sets, steppers, supersets, rest, swap, add/repeat, minimize/resume, receipt | F07 |
| F11 | Program builder, day editor, exercise picker | F07 |
| F12 | Library + exercise history (e1RM chart, PRs) | F07 |
| F13 | History tab: workout list + detail, edit/delete | F07 |
| F14 | Settings: units, rest, plates, toggles, CSV export, Health row | F07 |
| F15 | iOS UI tests for critical flows, accessibility audit, Dynamic Type pass | F08–F14 |

- [~] F08 · [~] F09 · [~] F10 · [~] F11 · [ ] F12 · [ ] F13 · [ ] F14 · [ ] F15
- [ ] M1 exit: a new user can onboard, run a full workout on the phone, see it in history and in the exercise chart; all flows pass the accessibility audit.

### Status — 2026-10-12: M1 after release 0.10.0 (#53); two slices in review

M1 opened with three lanes (Pete approved 2026-10-04); F11 joined as a fourth on 2026-10-05. Each feature is
delivered as slices, one PR each, batched since 2026-10-08 into larger PRs (700 to 900 lines of code, under
1,000). Slice plans, rulings and each slice's specification are in the feature's brief ("Plan amendments") and
notes. "Built" means implemented, adversarially tested, reviewed and gated locally, on a branch pushed for safe
keeping with no PR yet.

| Slice | What it is | State |
|---|---|---|
| F08 S1 | Program generator (goal and days per week to an 8-week program) | Built (`feat/F08-s1-templates`), not on `main`; as of 2026-10-05 it waited for Pete: do our 3, 5 and 6-day programs ship as defaults; should "Get stronger" accessories use reps-first progression |
| F08 S2 | The three-step onboarding screen | Built (`feat/F08-s2-onboarding-ui`), not on `main` |
| F08 S3 | A fresh install opens on onboarding; the root follows the active program | Built (`feat/F08-s3-root-gate`), not on `main` |
| F09 S1 | Four-tab shell, navigation, the first String Catalog and the localization checks | **On `main`** (#28) |
| F09 S2 | Domain additions for Today (next scheduled day, volume change, load state) | **On `main`** (#37) |
| F09 S3 | Today's presentation: which card, every word | **On `main`** (#38) |
| F09 S4 | The views of the Today screen | **On `main`** (#43) |
| F09 S5 | Today on screen in the app, with its store, its wiring and the live workout (the plan's S5 and S6 as one PR; the number S6 is not used) | **On `main`** (#50) |
| F10 S1 | The workout session interface, its test double and shared contract | **On `main`** (#27) |
| F10 S2 | The real session host, recovery after a kill, the start use case | **On `main`** (#29) |
| F10 S3 | A swap's program change lands with the saved workout; the log goes in the same transaction | **On `main`** (#30) |
| F10 S4 | Starting or resuming a workout opens its cover | **On `main`** (#45) |
| F10 S5 | Logging the sets of a solo exercise under the cover | **On `main`** (#52) |
| F10 S6 | The rest panel under the cover, with haptics | **PR #54 open** (`feat/F10-s6-rest`) |
| F10 S7–S9 | Finish and receipt, swap, supersets | Not started |
| F11 S1 | Program and day editing rules in the Domain (the plan's S1 and S2; the number S2 is not used) | **On `main`** (#34) |
| F11 S3 | A program is changed where it is stored, in one step | **On `main`** (#36) |
| F11 S5 | The presentation of the program builder | **On `main`** (#40) |
| F11 S6 | The presentation of the day editor and its slot panel | **On `main`** (#44) |
| F11 S8 | The form controls and the presentation of the exercise library sheet | **On `main`** (#47) |
| F11 S9 | The views of the program builder and of the exercise library sheet | **On `main`** (#49) |
| F11 S10 | The views of the Day editor and of its slot panel | **PR #55 open** (`feat/F11-s10-day-editor-views`) |
| F11, the rest | The stores, the wiring into the Program tab and the UI tests (the plan's S13 and S14; the brief names the numbers that larger batches took in) | Not started |

- **On `main` through #53:** releases v0.5.0 to v0.10.0. The app opens on four tabs; Today is on screen with its
  store and wiring and starts or resumes a workout, whose cover logs the sets of a solo exercise. The program
  builder and the exercise library sheet are drawn and tested as views and are not in the app yet (their store
  is a later slice). Also merged: the ADR-004 and ADR-008 amendments (#32), the convention for screens that
  scroll with the reader that refuses a scroll view (#41), a fix to a racy sync test (#39), and the PR lane's
  40 seeds and 2,520 s deadline (#51).
- **Waiting on Pete (carried over from 2026-10-05, not re-checked here):** the two questions on F08 S1's
  program tables; the product questions asked on 2026-10-04 whose defaults are built (elapsed time past an hour
  as "1:01:05"; units and week start from the stored settings; a live workout takes over Today's card; a session
  done on another day is offered again; "Also update program" lands with the saved workout; a swap keeps the
  original's load); may a lifter abandon a finished workout that cannot be saved. Pete is told before any F12
  work starts (2026-10-06).
- **Conventions settled in M1 so far:** one String Catalog and one copy file per module, checked by the gate
  against the compiler's keys (standards §7, #28); a counted text takes its plural form by the catalog's
  language and its digits by the lifter's locale (`Locale.forCountedText`, one place for every feature since
  chore batch B); a screen that scrolls is its pinned parts plus a scroll view around one page view, and its
  VoiceOver tree is pinned on the page (testing-strategy §2.6, #41); stores take synchronous intents and run
  their work from the view's task; a feature exposes a route and never presents another feature.
- **CI:** Actions is paid, with a $60 monthly limit; a PR is pushed once, after a green local gate. Since #51
  the hosted run takes the first 40 seeds of every seeded test and has a 2,520 s deadline; the local gate runs
  the plan's 200 (`tasks/chores/2026-10-09-pr-lane-time.md`). A branch pushed without a PR starts no run.
- **Chores.** Done in chore batch B (`chore/m1-batch-b`, 2026-10-12; `tasks/chores/2026-10-12-m1-batch-b.md`):
  counted texts in every feature; the check mark right to left; `AppRootAdversarialTests`' comparisons of large
  values; the font suites on the Mac host. Queued from it: the hosted reader fails on a text field (designed,
  to build after #55); phone references are drawn a few points cut on long pages and their precision lets a
  44 to 74 pt change pass (proposal in the record: one harness change and a `chore(snapshots):` PR). Still
  queued from before: package targets do not yet build with warnings as errors in `check.sh`; `LedgerDesign`'s
  and the watch's strings are not in catalogs yet; a recording seam for the logger; three tests that fail in the
  nightly lane on one thread; the hosted run's text-size matrices and build time (the PR-lane record's "Not
  done").

## M2 — Apple Watch (target: 3 weeks; real devices required)

| ID | Feature | Depends on |
|---|---|---|
| F16 | HealthKit adapter: auth, watch session + live builder, HR, save, recovery, phone start | F04, F07 |
| F17 | Live sync transport: mirroring channel, WC boost, watchdog, gap replay | F04, F16 |
| F18 | Watch app screens (idle → summary), crown weight, haptics, Always-On | F06, F07, F16 |
| F19 | Program push / workout pull-back over WatchConnectivity; standalone watch start | F17, F18 |
| F20 | Device sync test protocol & M2 acceptance | F16–F19 |

- [ ] F16 · [ ] F17 · [ ] F18 · [ ] F19 · [ ] F20
- [ ] M2 exit: start on either device, log on both, disconnect mid-workout, reconnect, finish on either → one workout in history with HR, saved to Health.

## M3 — Depth & delight (target: 2.5 weeks)

| ID | Feature | Depends on |
|---|---|---|
| F21 | Live Activity (Lock Screen + Dynamic Island) | F10, F17 |
| F22 | Widgets & watch complications / Smart Stack | F09, F18 |
| F23 | Rest-over notifications, abandoned-session prompt | F10 |
| F24 | Progression states: held / failed / deload UI, block view, off-schedule, next block | F10, F11 |
| F25 | Plate math on the set row | F10, F14 |
| F26 | Performance & polish pass (budgets in architecture §15) | M1, M2 |

- [ ] F21 · [ ] F22 · [ ] F23 · [ ] F24 · [ ] F25 · [ ] F26

## M4 — iCloud & beta (target: 2 weeks)

| ID | Feature | Depends on |
|---|---|---|
| F27 | CKSyncEngine spike (SQLiteData vs hand-rolled) → decision | F05 |
| F28 | iCloud sync (private DB, exclusions, conflict tests) | F27 |
| F29 | Privacy manifest, HealthKit strings, App Review readiness, data export/delete | F14, F16 |
| F30 | TestFlight beta (internal → external Beta App Review) | F01, F29 |

- [ ] F27 · [ ] F28 · [ ] F29 · [ ] F30

## M5 — Launch

| ID | Feature | Depends on |
|---|---|---|
| F31 | App Store release: assets, metadata, phased release | F30 |
| F32 | Xcode 27 / Swift 6.4 migration (before April 2027 SDK requirement) | hosted-runner availability |

- [ ] F31 · [x] F32 (#10, done early: see M0 status)

---

## Risk register

| # | Risk | Mitigation | Owner |
|---|---|---|---|
| R1 | HealthKit mirroring regressions on 26.x/27.0 | Watch authority + idempotent envelopes + WC fallback (ADR-005); device protocol F20 | F17 |
| R2 | Archivo `wdth` axis on watchOS | M0 spike in F06; fallback to static instances | F06 |
| R3 | XcodeGen watch-embed bug → committed project | ADR-003; human creates project in F00 | F00 |
| R4 | Xcode 27 is only on GitHub's `xcode-27` preview image (actions/runner-images#14404) | F32 (Pete, 2026-09-29): pin 27.0 and run CI on `xcode-27`; rolling back to 26.6 (still on `macos-26`) means reverting F32 as a whole, harder after each merge (ADR-006 amendment). Close when a standard image carries Xcode 27 | F32 |
| R5 | CKSyncEngine × GRDB fit | F27 spike before commitment | F27 |
| R6 | Agent-written code drifting from design | Snapshot tests + reviewer design-fidelity check (workflow §Reviewer) | all |

## Review log
_Appended after each milestone: what shipped, what was cut, lessons, rule changes._

### M0 — Foundation (2026-09-24 → 2026-10-04; target was 1.5 weeks)

**Shipped:** F00 skeleton and local gate; F01 CI (PR, nightly, release-please) and its efficiency pass (#18); F02 domain core with exact weights (ADR-007); F03 catalog (224 exercises); F04 event-sourced engine; F05 persistence in three slices plus the records follow-up; F06 design system in three slices; F07 composition in three slices (ADR-008, the `LedgerFakes` module); F32 Xcode 27 pulled forward from M5.

**Product decisions made during M0:** #21–#30 (catalog loads and upgrades, kettlebell step, search, set kinds, a workout's day, records after an edit, seeding and database failures, launch time).

**Cut or deferred:** Xcode Cloud workflows and the iCloud container (Pete, before F30/F28); launch time gated only on a real device (#30, F20/F26); watchOS in PR CI (local gate and nightly instead).

**Lessons and rule changes:**
- Adversarial testing paid for itself: almost every slice took two strikes, mostly on damage, cancellation and boundary cases that review alone did not catch. When a third bug comes from the same root (F07 S2's launch steps), change the design rather than patch the case.
- Test doubles must obey the database's rules (F07 S1): the fakes now share LedgerDomain's storage checks and are run against GRDB with seeded random scripts.
- Process rules added: no stacked PRs (build the next slice on a local branch, open its PR after the base merges); the orchestrator re-runs every gate before committing; agents never move HEAD; check the network before diagnosing a red gate; clean agent scratch copies after each round.
- CI is a budget: one push per PR after a green local gate; a docs-only PR starts no Mac.
