# Ledger — Engineering Standards

Every human and every AI agent reads this before touching code. These rules are
enforced by the compiler where possible (package boundaries, strict
concurrency), by tooling where not (SwiftLint, SwiftFormat, CI gates), and by
code review for the rest. "It works" is not the bar. "A staff engineer would
merge it without comment" is the bar.

Related: `docs/architecture.md`, `docs/testing-strategy.md`,
`docs/subagent-workflow.md`, `docs/adr/`.

---

## 1. Toolchain

| Item | Value |
|---|---|
| Language | Swift 6.3, Swift 6 language mode, strict concurrency `complete` |
| UI | SwiftUI only. No UIKit/WatchKit views except via documented, isolated wrappers in `LedgerDesign` |
| Minimum OS | iOS 26.0, watchOS 26.0 |
| Xcode | 26.6 (pinned in `.xcode-version`; CI uses the same). Xcode 27 migration is task F32 |
| Project | Committed `Ledger.xcodeproj` with synchronized folders (ADR-003). Adding files never touches the pbxproj. Never hand-edit `project.pbxproj`; target/entitlement changes are made in Xcode by a human |
| Packages | All product code lives in the local Swift package `LedgerKit/`. App targets depend only on the umbrella products `LedgerAppKit` / `LedgerWatchAppKit`; adding a feature is a `Package.swift` edit |
| Formatting | SwiftFormat 0.63.x (config: `.swiftformat`), pinned via `mise`, run by the lefthook pre-commit hook |
| Linting | SwiftLint 0.65.x `--strict` (config: `.swiftlint.yml`), pinned via `mise`; warnings are errors locally and in CI |

Run `scripts/check.sh` before declaring any task done. It runs format-lint,
lint, build (iOS + watchOS), and the full test suite. Green `check.sh` is the
minimum bar for a PR.

---

## 2. Module boundaries (compiler-enforced)

```
LedgerDomain        pure Swift; Foundation only. Models, WorkoutEngine, rules, protocols
   ▲
   ├── LedgerPersistence   GRDB. Schema, migrations, repositories (implements Domain protocols)
   ├── LedgerHealth        HealthKit adapter (sessions, mirroring, saving workouts, HR)
   ├── LedgerSync          Event transport phone⇄watch; reconciliation
   ├── LedgerDesign        Tokens + reusable SwiftUI components. Depends on SwiftUI only
   │
   ├── Feature* targets    One per screen family (FeatureToday, FeatureWorkout, …).
   │                       Depend on LedgerDomain + LedgerDesign only.
   │                       Get everything else through injected protocols.
   │
   └── App targets         Ledger (iOS), LedgerWatch (watchOS), widgets.
                           The ONLY place concrete implementations are wired together.
LedgerTestSupport   fakes, fixtures, builders, in-memory DB, snapshot helpers. Test-only.
```

Rules:

- A `Feature*` target never imports `LedgerPersistence`, `LedgerHealth`, or
  `LedgerSync`. It receives protocol-typed dependencies.
- Features never import other features. Cross-feature navigation is expressed
  as a `Route` value the App target resolves.
- `LedgerDomain` imports nothing but Foundation. If you need `import SwiftUI`
  or `import HealthKit` you are in the wrong module.
- Adding a dependency edge in `Package.swift` that violates this diagram
  requires an ADR.

---

## 3. Architecture pattern

Unidirectional, MVVM-lite, no framework:

```
View (SwiftUI, declarative, no logic)
  → sends intents to
Store (@Observable @MainActor final class, one per screen)
  → calls
Use cases / WorkoutEngine (LedgerDomain, pure, synchronous where possible)
  → read/write through
Repository protocols (declared in LedgerDomain, implemented in LedgerPersistence)
```

- Views hold no business logic. If a view needs an `if` about domain state, the
  store exposes a computed presentation value.
- Stores are `@MainActor`. They own no `Task`s that outlive the view; async work
  is started from `.task { }` on the view and cancelled by SwiftUI.
- Domain logic is pure functions or small value-type services. The
  `WorkoutEngine` is a reducer: `(WorkoutState, WorkoutEvent) -> WorkoutState`
  plus a separate `Effect` list. See ADR-004.
- Dependency injection: `swift-dependencies` `@Dependency` for cross-cutting
  services (clock, UUID, repositories, health store). Every dependency has a
  `liveValue`, a `testValue` (unimplemented, fails loudly), and where useful a
  `previewValue`.
- No singletons. No `static let shared`. No global mutable state.

---

## 4. Concurrency rules (Swift 6 strict)

- Every type crossing an isolation boundary is `Sendable`. Prefer value types.
- `@unchecked Sendable` is forbidden without a comment explaining the invariant
  and a link to the ADR or issue that allows it.
- Shared mutable state lives in an `actor`. Persistence, HealthKit, and Sync
  each expose an actor-backed service.
- No `DispatchQueue`, no `NSLock`, no semaphores in product code.
- No `Task.detached`. No fire-and-forget `Task { }` in stores; structured
  concurrency via `.task`, `TaskGroup`, `async let`.
- Respect cancellation: long loops call `try Task.checkCancellation()`.
- Timers are derived from wall-clock timestamps (`restEndsAt: Date`), never from
  tick counting, so phone and watch agree. See ADR-004.
- Time, UUIDs, and randomness are injected (`@Dependency(\.date)`,
  `@Dependency(\.uuid)`), never called directly in domain or store code.

---

## 5. Domain modelling

- All identifiers are typed: `struct ExerciseID: Hashable, Codable, Sendable { let rawValue: UUID }`.
  Never pass a bare `UUID` or `String` as an identity.
- Units are explicit: `Weight` (stores grams as `Int`, presents lb/kg),
  `Reps` (`Int`, ≥ 1), `Duration` (`Swift.Duration`). No `Double` weights.
- Models are `struct`, `Equatable`, `Sendable`, `Codable` when persisted or
  transmitted. Events are `enum` with associated values.
- Validation happens at construction (`init` throws or returns `nil`), not at
  the call site.
- No optionals for "not loaded yet" — model loading state explicitly
  (`enum Loadable<T> { case idle, loading, loaded(T), failed(Error) }`).

---

## 6. Persistence (GRDB)

- Migrations live in `Migrations.swift`, are append-only, named
  `v001_createExercises`, and never edited after merge.
- Every repository method has an integration test against an in-memory
  `DatabaseQueue`.
- GRDB types (`Row`, `Record`, `DatabaseQueue`) never appear above
  `LedgerPersistence`. Repositories return Domain types.
- Live queries use `ValueObservation` and are exposed as `AsyncSequence`
  of Domain values.
- Aggregates (weekly volume, PRs, 1RM history) are SQL with indexes, and each
  has a performance test seeded with 20k sets (budget in `docs/testing-strategy.md`).

---

## 7. SwiftUI rules

- One primary view per file, ≤ 150 lines. Extract subviews early.
- Every view has a `#Preview` for each meaningful state (empty, loading,
  populated, error). Previews use `LedgerTestSupport` fixtures.
- Only `LedgerDesign` tokens for color, type, spacing, radius. A raw
  `Color(red:…)`, `.font(.system(size: 17))`, or `.padding(13)` in a feature
  is a lint error.
- Every interactive control has an accessibility label; hit targets ≥ 44 pt
  (iOS) / follow watchOS defaults; Dynamic Type supported up to
  accessibility sizes; `.accessibilityIdentifier` on anything UI tests touch.
- All user-visible strings go through the String Catalog
  (`Localizable.xcstrings`). No string literals in `Text(...)` in features.
- Animations are explicit (`withAnimation(.snappy)`) and respect
  `accessibilityReduceMotion`.

---

## 8. Error handling & logging

- Each module defines its own `Error` enum. Errors are never swallowed
  (`try?` needs a comment saying why the failure is acceptable).
- Stores map errors to user-facing presentation state; they never surface raw
  error descriptions.
- Logging via `os.Logger` with subsystem `app.ledger` and a category per
  module. No `print`. No logging of health data values.

---

## 9. Testing rules (summary — see `docs/testing-strategy.md`)

- Every PR adds or updates tests. A PR that only adds product code is rejected.
- Domain: Swift Testing unit tests, target ≥ 95% line coverage.
- Persistence: integration tests on in-memory SQLite.
- Design components and key screens: snapshot tests (light + dark, 3 Dynamic
  Type sizes, iPhone + watch sizes).
- Nothing in unit or integration tests touches the network, HealthKit,
  WatchConnectivity, the file system (outside temp), or wall-clock time.
- A flaky test is a bug with P1 priority. Retries are not a fix.

---

## 10. Git & PR conventions

- Branch: `feat/F07-active-workout`, `fix/…`, `chore/…`. One feature brief per branch.
- Commits: Conventional Commits (`feat(workout): …`, `fix(sync): …`, `test(domain): …`).
- PRs: ≤ 500 changed lines excluding tests and snapshots. Larger = split.
- PR description follows `.github/PULL_REQUEST_TEMPLATE.md` and links the
  feature brief.
- `main` is protected: no direct pushes, required CI checks, linear history.
- Never commit secrets, provisioning profiles, or `.p8` keys.

---

## 11. Forbidden

- `!` force unwrap, `try!`, `as!` outside tests and previews.
- `@unchecked Sendable` without ADR reference.
- `DispatchQueue`, `Task.detached`, `Timer` in domain/store code.
- Singletons, global mutable state, `UserDefaults` accessed outside a
  `Settings` repository.
- UIKit/WatchKit in feature modules.
- Raw colors, fonts, spacing in feature modules.
- Business logic in SwiftUI `body`.
- Editing a merged migration.
- Disabling a lint rule inline without a justification comment.
- Skipping or `.disabled`-ing a test to get CI green.

---

## 12. Definition of Done (every feature brief inherits this)

- [ ] All acceptance criteria in the brief demonstrably met (test or screenshot per criterion).
- [ ] `scripts/check.sh` green locally.
- [ ] Unit + integration tests added; coverage does not decrease.
- [ ] Snapshot tests added or updated for any new/changed UI, light and dark.
- [ ] Previews exist for every new view state.
- [ ] Accessibility: labels present, Dynamic Type verified at XL, VoiceOver traversal sane.
- [ ] No new lint suppressions.
- [ ] `implementation-notes.md` in the feature folder explains decisions and any deviations from the brief.
- [ ] Independent adversarial test pass completed (see workflow) and green.
- [ ] Independent review completed with zero blocking findings.
- [ ] CI green on the PR.
