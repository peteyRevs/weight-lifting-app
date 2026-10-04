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
| Language | Swift 6.4, Swift 6 language mode, strict concurrency `complete` |
| UI | SwiftUI only. No UIKit/WatchKit views except via documented, isolated wrappers in `LedgerDesign` |
| Minimum OS | iOS 26.0, watchOS 26.0 |
| Xcode | 27.0 (pinned in `.xcode-version`; CI uses the same, on the `xcode-27` runner; F32). `scripts/check.sh` fails on any other Xcode |
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
LedgerFakes         in-memory stores, fixtures, device fakes; LedgerDomain (+ IssueReporting), #if DEBUG.
                    Linked by the features (previews) and LedgerDependencies (previewValue) (ADR-008).
LedgerTestSupport   contracts, builders, withTestDependencies; re-exports LedgerFakes. Test-only.
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
  each expose an actor-backed service. Exceptions: `LedgerFakes`' in-memory stores
  keep their state behind a `Synchronization.Mutex` so that `observe…()` registers
  synchronously (ADR-008 decision 4); and state that a system framework callback
  writes synchronously on the framework's own queue, where an actor could be
  reached only after the callback returned, may sit behind a `Mutex`
  (`MirroringStartRegistrar`; Pete, 2026-10-04). Product stores use actors.
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
- Units are explicit: `Weight` (stores exact grams as `Decimal`, rounds only where a rule says so, presents lb/kg; ADR-007),
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
  populated, error). Previews use `LedgerFakes` fixtures and the keys' seeded `previewValue`s (ADR-008).
- Only `LedgerDesign` tokens for color, type, spacing, radius. A raw
  `Color(red:…)`, `.font(.system(size: 17))`, or `.padding(13)` in a feature
  is a lint error (the design lint below). "Tokens only" is enforced by
  review (`docs/subagent-workflow.md`, review point 4); the lint is a
  tripwire for common slips and is not meant to catch every spelling.
- Every interactive control has an accessibility label; hit targets ≥ 44 pt
  (iOS) / follow watchOS defaults; Dynamic Type supported up to
  accessibility sizes; `.accessibilityIdentifier` on anything UI tests touch.
- All user-visible strings go through the String Catalog
  (`Localizable.xcstrings`). No string literals in `Text(...)` in features.
- Animations are explicit (`withAnimation(.snappy)`) and respect
  `accessibilityReduceMotion`.

### Design lint (`ledger_raw_*`): a tripwire, not a proof

Pete's decision (2026-09-29). The four SwiftLint custom rules in
`.swiftlint.yml` catch the raw values a feature author writes without meaning
to bypass the tokens. They are not meant to catch every spelling: "tokens
only" is enforced by review (`docs/subagent-workflow.md`, review point 4). The
rule set is frozen; a spelling it misses is fixed in review, not by growing
the regexes. Comments and string literals are ignored, and a literal `0` is
allowed for spacing and radii.

Scope: the modules that can draw UI. That is the `Feature*` and
`WatchFeature*` targets, the `LedgerAppKit` and `LedgerWatchAppKit`
umbrellas, and `Apps` (test targets excluded). `LedgerDesign` is where raw
values become tokens. `LedgerDomain`, `LedgerDependencies`, the adapters
(`LedgerPersistence`, `LedgerHealth`, `LedgerSync`) and `LedgerActivityKit`
are Foundation-only (§2), so a hit there (a plate-colour enum's `.black`, a
validator's `minLength: 2`) can only be a false positive. Narrowing the scope
to exclude them (F06 review S2, 2026-09-29) is a false-positive fix under the
decision above: the regexes did not change and stay frozen.
`scripts/tests/lint-rules.test.sh` checks both sides of the scope.

| Rule | Flags, outside `LedgerDesign` |
|---|---|
| `ledger_raw_color` | `Color(…)`, `Color.init(…)`, `Color.Resolved(…)`; `Color.orange`, `Color.secondary` and the other named and hierarchical styles; a named or hierarchical style (`.orange`, `.secondary` … `.quinary`) as an argument or after `:`; a named colour as a value after `=`, `?`, `??`, `{` or `return`; `.init(red:…)`, `.init(white:…)`, `.init(uiColor:…)` and the like, and `.color(red:…)`; a raw alpha on a token (`LedgerColor.ink.opacity(…)`, also with the chain wrapped, and `LedgerColor.accent.secondary`); `UIColor`, `NSColor`, `#colorLiteral` |
| `ledger_raw_font` | a system style, `.system`, `.custom` or `.init` inside `.font(…)` or `.environment(\.font, …)`, or assigned to a `Font`; `Font(…)`; `UIFont`, `NSFont`; `.bold()`, `.italic()`, `.fontWeight(`, `.fontWidth(`, `.fontDesign(`, `.monospaced(`, `.monospacedDigit(`, `.textScale(`, `.tracking(`, `.kerning(`, `.lineSpacing(`, `.lineHeight(`; a literal `size:` in `LedgerFont.font(_:size:)`; a constant text size passed on (`dynamicTypeSize: .large`, `.environment(\.dynamicTypeSize, .large)`, `min(dynamicTypeSize, .accessibility2)`); `.dynamicTypeSize(.large)` or any pin at or below the default size |
| `ledger_raw_spacing` | a non-zero literal in `.padding(`, `.safeAreaPadding(`, `.contentMargins(`, `.listRowSpacing(`, `.listSectionSpacing(`, `EdgeInsets(…)` / `.init(top:…)`, `spacing:`, `horizontalSpacing:`, `verticalSpacing:`, `minLength:`, also in either arm of a simple ternary (`flag ? 13 : LedgerSpacing.l`); a token nudged by a literal (`LedgerSpacing.m + 1`, `/ 2`, `* 1.5`) |
| `ledger_raw_radius` | a non-zero literal for `cornerRadius:`, `topLeadingRadius:` …, `topLeading:` …, `.cornerRadius(`, a `cornerSize:`, iOS 26's `.fixed(…)` corner style (after `corners:`, `minimum:` or `…Corner:`), also in a simple ternary; a token nudged by a literal |

Known limits: the lint does not flag these, and review has to.
`scripts/tests/lint-rules-adversarial-round3.test.sh` keeps each as a `limit`
case (the `Role.spec` one is in `lint-rules.test.sh`), which fails if a rule
starts to flag it, so this list stays true.

- A comment inside the call (`.padding(.horizontal, // inset` then `13)` on
  the next line): SwiftLint drops every match that spans a comment.
- A raw value held in a constant or property (`private let rowGap: CGFloat =
  13`, then `.padding(.vertical, rowGap)`), a ternary on a compound condition,
  `?? 13`, or arithmetic the regexes don't follow.
- A size cap: `.dynamicTypeSize(...DynamicTypeSize.large)`, or a pin above the
  default size (`.dynamicTypeSize(.xLarge)`). The larger pin is allowed so a
  `#Preview` can show `.xLarge` or `.accessibility3`; a bounded range such as
  `...DynamicTypeSize.accessibility2` is Apple's documented way to limit
  growth where a layout truly cannot grow.
- `.minimumScaleFactor(…)`, which can shrink a watch role below the 11 pt floor.
- A raw alpha on the view (`.foregroundStyle(LedgerColor.ink).opacity(0.6)`);
  view `.opacity` is also how fades are written.
- Gaps made with a frame (`Spacer().frame(height: 13)`); frames are layout.
- System colours under other names: `.separator`, materials such as
  `.ultraThinMaterial`.
- Role properties set outside the role: `.baselineOffset(…)`, `.textCase(…)`.
- `LedgerFont.archivo(size:weight:width:)` with literals (public in the F06
  brief; its intended callers are inside `LedgerDesign`).
- A role's design size passed back as a fixed size
  (`LedgerFont.font(.body, size: LedgerFont.Role.body.spec.size)`): it
  drops Dynamic Type. `Role.spec` is public for the same reason as
  `archivo(…)`; use `.ledgerFont(_:)` or `font(_:dynamicTypeSize:…)`.
- A false positive, accepted: a feature enum case named like a hierarchical
  style (`.primary`) is flagged as an argument or after `:` (a ternary's
  second arm included), and one named like a colour (`.orange`) in any value
  position; qualify it (`Emphasis.primary`).

---

## 8. Error handling & logging

- Each module defines its own `Error` enum. Errors are never swallowed
  (`try?` needs a comment saying why the failure is acceptable).
- Stores map errors to user-facing presentation state; they never surface raw
  error descriptions.
- Logging via `os.Logger` with subsystem `com.petearevalo.Ledger` and a category per
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
- PR size (Pete, 2026-09-29): count code only, excluding tests, snapshots, docs (`docs/`, `*.md`)
  and comments. **500 lines is a target**: a PR over it says so in one line of its description and
  names the split it considered. **Above ~1,000 lines, split** at a natural seam, merging the first
  PR before opening the next (no stacked PRs). Never compress code or comments to fit.
- PR description follows `.github/PULL_REQUEST_TEMPLATE.md` and links the
  feature brief.
- `main` changes only through squash-merged PRs (linear history). The repo is on GitHub Free with no
  branch protection (Pete, 2026-09-27), so the merge gate is the orchestrator's policy: a green
  local `scripts/check.sh` on the merge candidate, plus CI when it ran (`docs/ci-cd.md` §4).
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
