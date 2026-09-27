# F00 — implementation notes

Branch `feat/F00-project-skeleton`. Agent-side scaffolding delivered 2026-09-24;
`Ledger.xcodeproj` is still to be created by hand
(`tasks/features/F00-project-skeleton/xcode-setup.md`).

## Starting state

A half-finished `Ledger.xcodeproj` from 2026-09-21 was **scrapped** (Pete's call,
2026-09-24): it had no watch target, the app sources were a per-file yellow group
pointing at a duplicate `Ledger/` at the repo root, and the two synchronized test
groups pointed at paths that no longer existed. A copy is in the session
scratchpad; nothing in it was hand-written. The duplicate root `Ledger/` folder
(identical to `Apps/Ledger/`, staged but never committed) was removed.

## Deviations from the brief

1. **`.strictConcurrency(.complete)` does not exist.** `PackageDescription` in
   Swift 6.3.3 offers `defaultIsolation`, `swiftLanguageMode`, `strictMemorySafety`
   — there is no `strictConcurrency` SwiftSetting (checked against
   `PackageDescription.swiftinterface` in the pinned toolchain). Complete
   checking comes from `swiftLanguageModes: [.v6]`, which implies it. So
   `uiSettings = [.defaultIsolation(MainActor.self)]`,
   `coreSettings = [.defaultIsolation(nil)]`.
2. **`swiftTestingTestCaseNames` is disabled in `.swiftformat`.** SwiftFormat
   0.63 rewrites `@Test("Sentence") func name()` into a backticked raw-identifier
   function name, which contradicts testing-strategy §6 and then fails SwiftLint's
   `identifier_name`. Format and lint cannot both be green with it on.
3. **UI test files are `Smoke.swift` / class `Smoke`,** not `LaunchTests.swift`.
   The PR plans select `LedgerUITests/Smoke`, and that identifier is the class
   name. The test inside is still `test_launchShowsPlaceholder` (XCTest requires
   the `test` prefix, so §6's no-prefix rule does not apply).
4. **Test-plan target lists.** F00 step 9 and testing-strategy §8 disagree about
   which targets each plan runs. Resolved as: iOS plans run everything except the
   two watch-only targets (`WatchFeatureWorkoutTests`, `LedgerWatchAppKitTests`);
   watch plans run Domain, Persistence, Sync, Design, WatchFeatureWorkout,
   LedgerWatchAppKit plus the watch app tests. Worth a line in testing-strategy §8
   when F01 touches it.
5. **No `skippedTests` entries yet.** `StatsQueriesPerformanceTests` (F05) and the
   `.device`-only `HealthStoreContract` suites (F16) do not exist, and listing
   absent identifiers in a plan is noise. The owning brief adds them.
6. **`Tags.swift` is not in this PR.** Tags would make `LedgerTestSupport`
   `import Testing`, and feature targets link `LedgerTestSupport`, which would drag
   swift-testing into shipping app code. F02 adds tags once the preview-fixtures
   question below is settled.
7. **Three target-level build settings survive:** `TEST_HOST`, `BUNDLE_LOADER`,
   `TEST_TARGET_NAME`. They differ per test target and xcconfig has no per-target
   conditionals. Everything else is in `Config/`.
8. **`scripts/snapshots-update.sh` is not created.** `check.sh --record-snapshots`
   exports `SNAPSHOT_TESTING_RECORD=all`; F06 owns the snapshot workflow and can
   replace that with a script if it needs one.
9. **SwiftLint analyzer rules do not run in `check.sh`.** `unused_declaration` and
   `unused_import` need `swiftlint analyze --compiler-log-path`, i.e. a build log.
   Declared in `.swiftlint.yml`, wired up in F01 where the CI build log exists.
10. **`scripts/coverage-gate.sh`** is F01's; step 5 prints `coverage gate: F01`.
11. **`Info.plist` and `.entitlements` live beside the synchronized folders, not
    in them:** `Apps/Ledger-Info.plist`, `Apps/Ledger.entitlements`,
    `Apps/LedgerWatch-Info.plist`, `Apps/LedgerWatch.entitlements`. A
    synchronized folder puts every file it holds into Copy Bundle Resources, so
    `Apps/Ledger/Info.plist` was both copied and processed — the first
    `xcodebuild` (2026-09-24) failed with `Multiple commands produce
    …/Ledger.app/Info.plist`. The alternative, a membership exception, is
    per-file state in the pbxproj, which ADR-003 avoids.
12. **The xcconfigs had to absorb what the templates set at project level.**
    Clearing the pbxproj (2026-09-26) exposed settings the templates had been
    supplying. A diff of every target's resolved settings, old project vs new,
    found: the four test targets resolved to **macOS** (no `SDKROOT`); the
    embedded watch app lost `SKIP_INSTALL = YES` (its archive would become a
    Generic Xcode Archive); both apps lost `LD_RUNPATH_SEARCH_PATHS` and
    `ENABLE_PREVIEWS`; `COPY_PHASE_STRIP` flipped to YES. Fixed in `Config/`:
    iOS is the project default in `Base.xcconfig`, a new `WatchTests.xcconfig`
    (includes `Tests.xcconfig`) switches the two watch test targets to watchOS,
    and the app files carry the rest. After the fix the only differences from
    the template are intended: 26.0 targets, iPhone only, Swift 6 + strict
    concurrency + warnings as errors, and clean test bundle IDs. Not adopted
    from the 26.6 templates: `SWIFT_APPROACHABLE_CONCURRENCY` and
    `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY` — the LedgerKit targets
    don't enable them, and app and package code should compile under the same
    rules; revisit together in `Package.swift` if wanted.
13. **Test plans and schemes wired after the project existed (2026-09-26).**
    The plans named the four app test targets by name, but a test plan
    identifies an `.xcodeproj` target by its pbxproj ID, so they now carry
    `8AA8D3B9…` (LedgerTests), `8AA8D3C3…` (LedgerUITests), `8AAE5FE4…`
    (LedgerWatchTests), `8AAE5FEE…` (LedgerWatchUITests), plus
    `targetForVariableExpansion` = the host app. The 26.6 schemes had no
    "Convert to use Test Plans…" path (`shouldAutocreateTestPlan`), so the
    `<TestPlans>` blocks were written into the two `.xcscheme` files directly.
14. **`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` moved from `Base.xcconfig`
    to `Ledger.xcconfig` / `LedgerWatch.xcconfig`.** The brief put it at project
    level, which also made the four test targets MainActor by default; the first
    full `check.sh` then failed to compile `LedgerUITests/Smoke` (`main
    actor-isolated … setUpWithError() has different actor isolation from
    nonisolated overridden declaration`). Architecture §3 only asks for it on the
    app shells, and Apple's 26.6 templates leave test targets nonisolated. The
    smoke tests now say `@MainActor` where they touch UI or `LedgerAppKit`
    symbols. Architecture §3's table gained a row for app test targets.
15. **The font is bundled flat, so `UIAppFonts` names `Archivo[wdth,wght].ttf`.**
    `Resources/Fonts` is a synchronized folder like every other source folder;
    those copy their files to the bundle root (checked in the built
    `Ledger.app`), not into a `Fonts/` subdirectory as the brief's blue folder
    reference would have. The first full run failed `archivo_isRegistered`
    because both plists still said `Fonts/…`. `OFL.txt` ships beside the font.
16. **One-off pbxproj text edit (Pete-approved, 2026-09-26, Xcode closed).**
    Removed an orphan self-reference to `Ledger.xcodeproj` (a
    `PBXFileReference`, its empty `Products` group and the `projectReferences`
    array — invisible in the navigator, so not removable in Xcode) and four
    empty `PROVISIONING_PROFILE = ""` lines Xcode wrote when the UI-test
    Target Application was re-picked. Validated with `plutil -lint` and
    `xcodebuild -list`; Pete reviewed and approved the diff (18 lines
    removed, none added) before the project was committed. ADR-003's rule stands for
    everything else.

## Concern to settle (not blocking F00)

Feature targets link `LedgerTestSupport` (per the brief's target table) so
previews can use fixtures — but `LedgerTestSupport` depends on Persistence,
Health, Sync and Design, so every feature transitively links the whole stack,
which is what architecture §3's rule exists to prevent. Recorded as an open
question in `docs/architecture.md` §3; the cheap fix is a `LedgerPreviewFixtures`
target that depends on `LedgerDomain` only. Decide in F06/F07, before any real
feature code exists.

## Verified facts

- Xcode 26.6 (17F113) — matches `.xcode-version`.
- Swift 6.3.3; `swift build` and `swift test` green on the host: **18 tests, 18
  suites**, including `GRDB links and opens an in-memory queue`.
- Pinned tools install clean: swiftlint 0.65.1, swiftformat 0.63.0,
  lefthook 2.1.14, xcbeautify 3.2.1.
- Resolved packages: GRDB 7.11.1, swift-dependencies 1.17.1,
  swift-snapshot-testing 1.19.6 (`LedgerKit/Package.resolved`, committed).
- `scripts/check-package-graph.sh` records 36 targets and matches the brief's
  table exactly.
- Archivo: `googlefonts/Archivo` does not exist; the file comes from
  `google/fonts/ofl/archivo`. `fvar` parsed directly: **wght 100–900 (default
  600), wdth 62–125** — the axes F06 needs.
- Acceptance criterion 5 reproduced: a planted `FeatureToday/Violation.swift`
  fails `check.sh` at step 2 with `feature_raw_font`, `feature_raw_padding`,
  `force_unwrapping`, `implicitly_unwrapped_optional`, before any build.
- Acceptance criterion 7 reproduced: `git commit -m "added stuff"` is rejected by
  the lefthook `commit-msg` hook.
- Team ID `95JAK545DF`, read from the OU of the `Apple Development: Peter Arevalo`
  certificate issued 2026-09-22, is in `Config/Base.xcconfig`. Confirmed
  2026-09-26 from Xcode's provisioning-team defaults: `teamType = Individual`,
  `isFreeProvisioningTeam = 0` — the paid team, not a Personal Team.
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` is a real Xcode 26.6 build setting:
  the 26.6 app and watch-app templates write exactly that key (seen in the
  generated pbxproj, 2026-09-26). No `OTHER_SWIFT_FLAGS` fallback needed.
- The `xcode` MCP server is connected (`XcodeListWindows` answered 2026-09-26),
  so the Intelligence toggle is on.

## Still open after the Xcode sitting

- Criteria 1–4, 6, 8, 10 need the project: they are the checklist at the end of
  `xcode-setup.md`.
