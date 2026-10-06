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
  keep their state behind a `Synchronization.Mutex`, so that `observe…()` registers
  synchronously and so that a save that spans linked stores is one step, as the
  database's transaction is (ADR-008 decision 4 and its amendment of
  2026-10-05); and state that a system framework callback
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
- All user-visible strings, spoken ones included, come from the module's
  String Catalog (`Localizable.xcstrings`), through its copy file. No string
  literal in `Text(...)`, in a component's arguments or anywhere else a lifter
  could read or hear it: see "Localization" below.
- Animations are explicit (`withAnimation(.snappy)`) and respect
  `accessibilityReduceMotion`.

### Localization: one catalog and one copy file per module

M1 convention (2026-10-04), built in F09 S1 and revised in its fix round 1.
`LedgerAppKit` is the model: `AppCopy.swift` and
`Resources/Localizable.xcstrings`. A feature adds a catalog and a copy file,
and nothing else: no test of its own and no entry in a list. Three checks find
both without being told ("Who checks what"). This holds for the modules the
iOS build compiles; a watch module gets its catalog with F18 ("Not yet
converted" below).

- **Catalog.** A module with copy has one hand-written
  `Sources/<Module>/Resources/Localizable.xcstrings`, and its target declares
  `resources: [.process("Resources")]`; `defaultLocalization: "en"` is set once,
  in `Package.swift`. English is the source language. The key is the English
  text with its format specifiers (`"Week %lld of %lld"`), as the briefs'
  "Copy (exact)" sections are written.
  - **The key is the compiler's.** It is what the compiler extracts from the
    lookup in the copy file: an interpolated `Int` is `%lld`, a `String` is
    `%@`, a `Text`'s `timerInterval:` is `%@`. A `%` in the text is written
    once in a key that carries no value (`"100% done"` has the key
    `100% done`) and doubled in one that does (`"\(week)% of the block"` has
    the key `%lld%% of the block`). When in doubt, write the lookup and run the
    gate: its message spells the key.
  - Every key spells out its English text, marked `"state" : "translated"`. The
    build leaves out a key with no localization and one left `new`; this rule
    is stricter and accepts `translated` only. A plain key's text is the key.
  - A counted key has the plural forms `one` and `other` and exactly one
    `%lld`, the number that picks the form; its `other` form is the key. Any
    other number in it is formatted first and passed as a `String`, so it is
    `%@` in the key (`"%@ of %lld sets"`). Two counts are two keys, joined with
    " · ".
  - A translator's comment may stand in the catalog alone. When the code
    gives one (`comment:`), the catalog's `"comment"` must equal it, word for
    word.
  - No key and no text holds the product's name
    (`docs/product-decisions.md`, Naming).
  - A catalog is edited as text, as Xcode's tool writes it: two-space indent,
    `"key" : value`, each key once, keys in code-unit order: by their UTF-8
    bytes, which is by Unicode scalar (`"10"` before `"9"`, `"Z"` before
    `"a"`, an accented letter after `"z"`; measured with `xcstringstool`,
    2026-10-04). It is not the order a dictionary gives. Xcode is not needed,
    and no build and no check writes to the file.
- **Copy file.** Every lookup of the module is in `<Feature>Copy.swift` (and
  `<Feature>Copy+<Area>.swift` when it grows): a `nonisolated enum` whose
  members return `String`. It holds lookups and nothing else, in two forms:
  1. `String(localized: "…", bundle: .module)`, with `locale:` straight after
     the bundle whenever the key carries a value, and `comment:` where a
     translator needs one. The locale is a parameter of the copy member: the
     caller passes the injected `@Dependency(\.locale)`, and the member never
     writes one itself (`locale: .current`). The locale picks more than the
     digits and their grouping: it also picks the plural rule, over the English
     words (`fr_FR` gives "0 fixture set", pinned by
     `CatalogBuildAdversarialTests.pluralForm_followsTheLocalesLanguage`), so a
     lookup without it takes both from the device and a test cannot fix them.
  2. `Text("… \(timerInterval: start ... end)", bundle: .module)`, only for a
     line that embeds a live timer; the member returns `Text` and the key holds
     `%@` where the timer stands. The timer form carries the timer and no
     other value: it can take no `locale:`. A line is never joined from
     `Text + Text`, and a copy file makes no other `Text`.

  A value interpolated into a key is a parameter of the member, an `Int` or a
  `String`; anything else is formatted first and passed as a `String`. So a
  key holds only `%lld` and `%@` (with their positional forms, `%1$@`, and
  `%%`), and a catalog key with any other specifier is refused. The key
  is a one-line literal: a key built at run time (an enum's raw value) cannot
  be compared with the catalog, so each case gets its own lookup. A lookup is
  never written inside another literal's interpolation: a join is two
  statements.
- **Every other file receives `String`s.** Views, stores, presentation builders
  and `LedgerDesign` components hold neither a user-facing literal nor a
  localized lookup. A bare `Text("…")` in a package looks in the app's main
  bundle, where the package's strings are not, and it is a lookup whether or
  not it has an interpolation (`Text("\(done)/\(total)")` looks up `%lld/%lld`).
- **Spoken text is copy.** VoiceOver labels, values and hints are lookups in
  the copy file like any other line.
- **Not copy.** Lines the Domain already formats (weights, volumes, receipt
  rows, the last-performance line, rest labels, clock text) and data (program
  and day names, catalog names) are shown as given and are not catalog entries.
- **A Domain value's name is each module's own.** Where the name of a Domain
  enum's case (a kind of equipment, a muscle group, a progression rule) is
  shown, the module that shows it holds its own entry for it in its own
  catalog and its own member in its own copy file, one lookup per case. The
  key is the English text, so two modules cannot differ in English; no module
  looks up another module's key, and nothing shared is built (orchestrator,
  2026-10-05, on F11's proposal 2).

**Who checks what.** None of it is per module, and none needs a list kept by
hand.

1. **The catalog's keys are the code's keys: the gate, with the compiler's
   keys.** `scripts/check-string-catalogs.sh` runs in `scripts/check.sh` after
   the iOS build, in every mode that builds iOS, and so in CI. For every
   `LedgerKit/Sources/<Module>/Resources/Localizable.xcstrings` it takes the
   keys the compiler extracted from that module's sources (the build's
   `.stringsdata` files). First it fails every lookup that is not in a copy
   file, with its file and line, whether or not the catalog has its key. The
   compiler sees what no source check can: a bare `Text("…")` in a preview is
   such a lookup, and so is `Button("\(done)/\(total)")`, which has no letter.
   The cure is in the message: move the lookup into the copy file and hand the
   view a `String`; in Debug-only code that needs no translation write
   `Text(verbatim:)`; never give the catalog a key for it. Then it fails on a
   key the copy files look up that the catalog lacks and on a catalog key no
   code looks up, naming each. Then it runs Xcode's own
   `xcrun xcstringstool sync` on a temporary copy and fails when the tool would
   write the file differently: a comment that is not the code's, keys out of
   order, a key twice, another layout. A composed and a decomposed spelling of
   a key are two keys. It reads the committed catalog and never writes it.
2. **Copy stands only in the copy files: `CopyAudit`
   (`LedgerTestSupport/Localization/`), on the sources.** It derives no key.
   - Outside a copy file, a localized lookup is a finding, however it is spelled
     or wrapped over lines (`localized:`, `NSLocalizedString`,
     `LocalizedStringKey`, `LocalizedStringResource`, `LocalizationValue`,
     `localizedString(forKey:`, `localizedAttributedString(forKey:`). So is a
     string literal with a letter in it, and any literal handed straight to
     `Text(…)`, interpolated or not.
   - A literal is not copy when no lifter sees its argument: an argument
     labelled `identifier:`, `…Identifier:`, `systemImage:`, `systemName:` or
     `category:`, the argument of `.accessibilityIdentifier(…)`, and the
     message of a level call on a logger. The label is the argument's own (it
     opens the argument), and it covers every literal in that argument's
     expression: both arms of a ternary, an interpolation. A name that only
     reads like a label (a ternary's arm, a `case`) covers nothing.
   - In a copy file, anything but the two forms above is a finding: a literal
     that is not a lookup's key, a lookup without `bundle: .module`, a key with
     a value and no `locale:`, another lookup API, a key that is not a one-line
     literal, a lookup inside an interpolation, and a `Text` that is not the
     timer form (one made from a `String`, from `verbatim:`, or joined from
     parts). A `comment:` is not read. A copy file in a module without a
     catalog is a finding.
   - The catalog's own rules above (source language, English text, state,
     plural forms, a specifier other than `%lld` and `%@`, the product's name)
     are findings. Texts are compared exactly, scalar by scalar.
   - **Exemptions name literals, not files.** A module's entry in
     `ModuleCopyTests.exemptions` lists, per file, the literals no lifter sees
     (a launch argument, a file name), with the reason. Any other literal of
     that file is still a finding, and so is an entry the file no longer holds.
     A file of Debug builds only is exempted as `debugOnly`; it and every
     `*+Previews.swift` go unread only when they are wholly inside `#if DEBUG`
     (imports may stand before it), which the audit verifies. The G3 reviewer
     confirms each exemption. A file that declares a view, a store or a
     presentation builder is never exempt. The table is one every feature lane
     edits (a shared file, as `Package.swift`'s `snapshotTestTargets` is): add
     only your own module's entry.
   - A module folder that cannot be read fails the audit.
3. **The built bundle resolves every key: `StringCatalog.unresolvedKeys(in:)`**
   on the bundle the build made (`StringCatalog.resourceBundle(ofModule:)`).
   In a test target with resources of its own, `Bundle.module` is the test
   target's bundle, so tests do not use it for a module's.

`ModuleCopyTests` (`LedgerAppKitTests`) runs 2 and 3 over every folder of
`LedgerKit/Sources`: 2 on every module, with its catalog when it has one, and
3 on every module that has a catalog. Two tables in that suite name the
modules it does not audit:

- **No user-facing copy by design**, each with its reason: `LedgerDomain`,
  `LedgerPersistence`, `LedgerDependencies`, `LedgerSync`, `LedgerHealth`,
  `LedgerFakes`, `LedgerTestSupport`, `LedgerSnapshotTesting`. Their literals
  are data, SQL, keys and log lines.
- **Not yet converted**: `LedgerDesign` (VoiceOver words looked up in
  components, the Debug gallery) and `LedgerWatchAppKit` (its placeholder and
  can't-open screen). This table only shrinks, and a module that passes the
  audit while still listed fails the suite. The chore after F09 S1 converts
  `LedgerDesign` only. `LedgerWatchAppKit` converts with F18, and
  `WatchFeatureWorkout` gets its catalog then too: the iOS build compiles
  neither, so check 1 has nothing to compare a catalog there with and fails
  it, and the iOS tests do not embed the watch bundles, so check 3 cannot ask
  them. F18 teaches the step to read the watch build and gives a watch test
  target check 3.

A module with a counted string also tests it through its copy file, with one
and with several.

To run the checks yourself: `swift test --package-path LedgerKit
--only-use-versions-from-resolved-file --filter ModuleCopyTests` for 2 and 3
(on the Mac, a few seconds after the build), and the gate, `scripts/check.sh`,
for 1.

**Known limits.** The audit reads text, not types; it does not find these, and
review has to. Each is kept as a `limit` test (`CopyAuditLimitTests`, and those
marked "Limit" in the tester's `CopyAuditAdversarialTests`,
`CopyAuditAllowedAdversarialTests` and `CopyAuditCloseOutAdversarialTests`),
which fails if the audit starts to find it, so this list stays true.

- A literal without a letter that is not handed straight to `Text(…)`, where
  check 1 does not see it either: one that is no lookup (a
  `"\(done)/\(total)"` held in a `String` constant), and any in a module that
  has no catalog yet (`Label("—", …)`, `.navigationTitle("\(count)")`). In a
  module with a catalog, check 1 fails those two as lookups outside the copy
  file.
- A text made from a name instead of a literal:
  `Text(day.rawValue.capitalized)`.
- A call that only reads like an allowed one: any argument labelled
  `identifier:`, `…Identifier:`, `systemImage:`, `systemName:` or `category:`
  (`Chip(category: "Push day")`), and a level call on anything named like a
  logger (`toastLogger.error("…")`).
- What a key's value is. The audit does not read an interpolation's type or
  expression: `"Week \(week + 1)"` and an optional (keyed `%@`, and shown as
  `Optional(3)`) pass it. The compiler warns of the optional, and a warning
  does not fail a package target's build. A `Double` or another type is
  caught one step later, by its specifier: check 1 holds the catalog to the
  compiler's key (`%lf`), and the catalog's rules refuse that key.
- A locale written into a copy member (`locale: .current`, `Locale.current`,
  `.autoupdatingCurrent`): the audit reads as far as `locale:`.
- Code in a copy file that holds no literal (`.uppercased()`, a join of two
  members): the audit does not check that a member is a lookup and no more.
- An exemption is a text: it covers every literal of its file that reads so,
  wherever it stands (never one handed to `Text(…)`).
- A regex literal that holds a quote or `/*` is read as the start of a string
  or a comment, which hides the code after it.
- Parentheses that do not balance in the text leave every later literal
  inside that argument, unread when its label is an allowed one: a call
  opened in both branches of an `#if` and closed once after `#endif`, or a
  regex literal that holds `(` (`/\(identifier: /`).

Outside the audit's reach altogether, and so for review: the app targets under
`Apps/` (thin by rule, §2), files that are not Swift, and the modules in the
first table. Check 1 has its own reach: it reads the iOS build. A module that
only the watch build compiles has nothing there to be compared with (above),
and a lookup compiled only for watchOS in a module both builds compile is
seen as a key no code looks up. Check 1 also fails any other `*.xcstrings`
under `LedgerKit/Sources`: a module has one catalog, in one place. And it
compares a source by the `.stringsdata` its last build wrote, so a source
edited since that build is compared as it was built: `check.sh` always builds
first, and a run by hand needs a build (a known limit of the step, kept by
case ST09 of `string-catalogs-tester.adv.sh`).

**Considered and not taken: generated string symbols** (Xcode's
`GeneratedStringSymbols`, a typed accessor per catalog key). They would give
the same agreement between code and catalog from the compiler, but rest on
tooling nobody has built against in this package or on the CI image; check 1
gives it with tools every build already runs. Revisit if hand-written copy
files become a burden.

- **Tiers.** With the pinned toolchain the catalog is compiled on the iOS
  simulator (`xcodebuild`, the gate) and on the Mac host (`swift test`, whose
  default build system is Swift Build), so checks 2 and 3 pass in both.
  SwiftPM's deprecated `--build-system native` copies the catalog uncompiled;
  every lookup then returns its key, no plural resolves, and check 3 fails, as
  it should. Check 1 needs the iOS build and runs only in the gate.
  `scripts/check.sh --fast` runs only the Domain and Persistence tests, so a
  module's copy is proven by the full gate. watchOS is unproven until a watch
  module has a catalog (F18).

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
