# Ledger — Plan & progress

Status legend: `[ ]` not started · `[~]` in progress · `[x]` done · `[!]` blocked

Plan documents: `docs/architecture.md` · `docs/engineering-standards.md` ·
`docs/testing-strategy.md` · `docs/ci-cd.md` · `docs/subagent-workflow.md` ·
`docs/product-spec.md` · `docs/product-decisions.md` · `docs/adr/` · `docs/research/`
Feature briefs: `tasks/features/F##-*.md` — all 33 written 2026-09-17; none approved yet.

---

## Phase 0 — Plan review (owner: Pete)

- [ ] Read `docs/architecture.md` and the six ADRs; object or approve.
- [ ] Confirm or override the 20 defaults in `docs/product-decisions.md` (the big ones: no accounts, lb+kg, 4 tabs, watch works standalone).
- [ ] Apple Developer account ready (Team ID), App IDs for iOS + watch, HealthKit capability, iCloud container name reserved.
- [ ] Create the GitHub repository (private) and push `main`.
- [ ] Approve starting M0.

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

- [ ] F00 · [ ] F01 · [ ] F02 · [ ] F03 · [ ] F04 · [ ] F05 · [ ] F06 · [ ] F07
- [ ] M0 exit: both apps build and launch to an empty Today screen; `check.sh` and CI green; domain coverage ≥ 95 %; Archivo width axis verified on watch simulator.

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

- [ ] F08 · [ ] F09 · [ ] F10 · [ ] F11 · [ ] F12 · [ ] F13 · [ ] F14 · [ ] F15
- [ ] M1 exit: a new user can onboard, run a full workout on the phone, see it in history and in the exercise chart; all flows pass the accessibility audit.

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

- [ ] F31 · [ ] F32

---

## Risk register

| # | Risk | Mitigation | Owner |
|---|---|---|---|
| R1 | HealthKit mirroring regressions on 26.x/27.0 | Watch authority + idempotent envelopes + WC fallback (ADR-005); device protocol F20 | F17 |
| R2 | Archivo `wdth` axis on watchOS | M0 spike in F06; fallback to static instances | F06 |
| R3 | XcodeGen watch-embed bug → committed project | ADR-003; human creates project in F00 | F00 |
| R4 | Xcode 27 not on hosted runners | Pin 26.6; F32 tracked | F01 |
| R5 | CKSyncEngine × GRDB fit | F27 spike before commitment | F27 |
| R6 | Agent-written code drifting from design | Snapshot tests + reviewer design-fidelity check (workflow §Reviewer) | all |

## Review log
_Appended after each milestone: what shipped, what was cut, lessons, rule changes._
