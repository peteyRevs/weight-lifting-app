# F00 — Project skeleton & local gate

| | |
|---|---|
| Milestone | M0 |
| Status | ready |
| Depends on | — |
| Branch | `feat/F00-project-skeleton` |
| Design refs | n/a (placeholder screens only; no prototype screen is reproduced here) |
| Spec refs | `docs/architecture.md` §1–§3, §11 (font); `docs/adr/ADR-003`; `docs/engineering-standards.md` §1–§2, §11; `docs/research/R3-tooling-ci.md` §1–§3; `docs/research/R2-data-architecture.md` §6.2 |

## Goal
After this ships, an agent can `git clone`, run `scripts/bootstrap.sh`, open `Ledger.xcodeproj`, build and launch both apps to a placeholder screen on the iOS 26.5 and watchOS 26.5 simulators, add Swift files to any target without touching `project.pbxproj`, and prove a change is mergeable with one command (`scripts/check.sh`). Every later brief assumes this skeleton exists exactly as described.

## User stories
- As an engineer or agent, I can add a file under `LedgerKit/Sources/<Target>/` or `Apps/<App>/` and it is built without editing the project, so parallel worktrees never conflict on the pbxproj.
- As an engineer, I can run one script that fails on any format, lint, build, or test problem, so "green check.sh" is a meaningful bar.
- As a reviewer, I can trust that a raw colour/font/padding literal in a feature module cannot be committed, because lint rejects it locally and in CI.

## Scope
**In:**
1. `Ledger.xcodeproj` created **by a human in Xcode 26.6** (checklist below), committed once.
2. `LedgerKit/Package.swift` with every target from architecture §2–§3 stubbed so the whole graph compiles, plus two additions this brief introduces (see Domain changes): `LedgerDependencies` (home for `@Dependency` keys) and `LedgerSnapshotTesting` (snapshot helpers, test-only).
3. Tooling: `mise.toml`, `.swiftlint.yml`, `.swiftformat`, `lefthook.yml`, `.xcode-version`, `scripts/bootstrap.sh`, `scripts/check.sh`, `Config/*.xcconfig`.
4. Archivo variable font bundled in both apps with `UIAppFonts`.

**Out (explicitly):** CI workflows and release-please (F01); any real Domain type (F02); design tokens and font loading code (F06); DI keys with real values and composition roots (F07); widgets/extension targets `LedgerWidgets`, `LedgerWatchWidgets` (F21/F22 — do not create them now).

### Human checklist — Xcode project (≈15 min, done once, ADR-003)
1. Xcode 26.6 → File ▸ New ▸ Project ▸ iOS ▸ App. Product Name `Ledger`; Team = Pete's team; Organization Identifier `app.ledger` (bundle id `app.ledger.Ledger`); Interface SwiftUI; Language Swift; Testing System **Swift Testing**; Storage None; tick "Include Tests" (creates `LedgerTests`, `LedgerUITests`). Save the project at the repo root as `Ledger.xcodeproj`; **untick** "Create Git repository".
2. In Finder move the generated `Ledger/` source folder to `Apps/Ledger/` and the two test folders to `Apps/LedgerTests/`, `Apps/LedgerUITests/`. In Xcode, delete the now-red groups, then File ▸ Add Files… ▸ pick `Apps/Ledger` with **"Synchronized folder"** selected (Xcode 16+; the group shows a folder icon, not a yellow group) and target `Ledger`. Repeat for the two test folders with their targets. Verify: `grep -c PBXFileSystemSynchronizedRootGroup Ledger.xcodeproj/project.pbxproj` ≥ 3 and `grep -c PBXGroup` shows no per-file `PBXFileReference` for Swift sources.
3. File ▸ New ▸ Target ▸ watchOS ▸ **App** → Product Name `LedgerWatch`, "Watch App for Existing iOS App" = `Ledger` (modern single-target watch app; bundle id becomes `app.ledger.Ledger.watchkitapp`, `WKCompanionAppBundleIdentifier` is set by Xcode), Testing System Swift Testing, include tests. Move its folder to `Apps/LedgerWatch/` (+ `Apps/LedgerWatchTests/`, `Apps/LedgerWatchUITests/`) and re-add as synchronized folders as in step 2.
4. Project ▸ Info ▸ Configurations: set every target/config to the xcconfig files listed in Touches (Debug → `Config/Debug.xcconfig`, Release → `Config/Release.xcconfig`; per-target `Config/Ledger.xcconfig`, `Config/LedgerWatch.xcconfig`, `Config/Tests.xcconfig`). Then delete all target-level build-setting overrides so the pbxproj holds none (Build Settings ▸ Levels shows only xcconfig values).
5. File ▸ Add Package Dependencies… ▸ **Add Local** ▸ `LedgerKit`. Frameworks: `Ledger` links product `LedgerAppKit` only; `LedgerWatch` links `LedgerWatchAppKit` only.
6. Signing & Capabilities: `Ledger` → + HealthKit. `LedgerWatch` → + HealthKit; + Background Modes ▸ tick **Workout processing**. Entitlement files land in `Apps/Ledger/Ledger.entitlements` and `Apps/LedgerWatch/LedgerWatch.entitlements` (referenced from xcconfig `CODE_SIGN_ENTITLEMENTS`).
7. Both apps: custom `Info.plist` at `Apps/Ledger/Info.plist` and `Apps/LedgerWatch/Info.plist` (keep `GENERATE_INFOPLIST_FILE = YES`; Xcode merges) containing `NSHealthShareUsageDescription`, `NSHealthUpdateUsageDescription`, `UIAppFonts = ["Fonts/Archivo[wdth,wght].ttf"]`; watch additionally `WKRunsIndependentlyOfCompanionApp = YES` (decision #16).
8. Add `Resources/Fonts` to **both** app targets as a folder reference (blue folder → copied as `Fonts/…` inside each bundle).
9. Product ▸ Scheme ▸ Manage Schemes: keep exactly `Ledger` and `LedgerWatch`, both **Shared**. Edit each scheme ▸ Test ▸ convert to test plans under `TestPlans/` exactly as `docs/testing-strategy.md` §8 defines them: `PR`, `Nightly`, `Device` attached to the `Ledger` scheme and `PR-Watch`, `Nightly-Watch`, `Device-Watch` attached to `LedgerWatch` (the `PR`/`PR-Watch` plans are each scheme's default); add the package test targets: iOS plan = all `LedgerKit` test targets except `WatchFeatureWorkoutTests` + `LedgerTests` + `LedgerUITests`; watch plan = `LedgerDomainTests`, `LedgerPersistenceTests`, `LedgerSyncTests`, `LedgerDesignTests`, `WatchFeatureWorkoutTests`, `LedgerWatchAppKitTests`, `LedgerWatchTests`. Enable code coverage for all targets in both plans.
10. Commit `Ledger.xcodeproj/` (including `project.xcworkspace/xcshareddata/swiftpm/Package.resolved` — Xcode Cloud needs it) in a `chore(project): create Xcode project` commit. Agents never edit the pbxproj afterwards.

## Touches
- `Ledger.xcodeproj/` (human), `TestPlans/{PR,PR-Watch,Nightly,Nightly-Watch,Device,Device-Watch}.xctestplan`, `.xcode-version` (`26.6`)
- `Apps/Ledger/{LedgerApp.swift, Info.plist, Ledger.entitlements}`, `Apps/LedgerTests/SmokeTests.swift`, `Apps/LedgerUITests/LaunchTests.swift`
- `Apps/LedgerWatch/{LedgerWatchApp.swift, Info.plist, LedgerWatch.entitlements}`, `Apps/LedgerWatchTests/SmokeTests.swift`, `Apps/LedgerWatchUITests/LaunchTests.swift`
- `Config/{Base,Debug,Release,Ledger,LedgerWatch,Tests}.xcconfig`
- `LedgerKit/Package.swift`, `LedgerKit/Sources/<Target>/<Target>.swift` (one placeholder file per target), `LedgerKit/Tests/<Target>Tests/<Target>Tests.swift`
- `Resources/Fonts/Archivo[wdth,wght].ttf`, `Resources/Fonts/OFL.txt` (SIL OFL 1.1 — download the variable TTF from the Archivo GitHub release / Google Fonts; verify with `fc-query` or `otfinfo` that `fvar` lists `wdth` 62–125 and `wght` 100–900)
- `mise.toml`, `.swiftlint.yml`, `.swiftformat`, `lefthook.yml`, `scripts/bootstrap.sh`, `scripts/check.sh`, `scripts/check-commit-msg.sh`, `.gitignore`, `.github/PULL_REQUEST_TEMPLATE.md`

## Domain changes
None. Every target contains one public placeholder so the graph links: `public enum <Target>Module { public static let name = "<Target>" }`; umbrellas add `public struct AppRootView: View` / `public struct WatchRootView: View` rendering `Text("Ledger")`. F02/F06/F07 replace these.

`LedgerKit/Package.swift` contract (agents may only append to it later):
- `// swift-tools-version: 6.2`, `swiftLanguageModes: [.v6]`, `platforms: [.iOS(.v26), .watchOS(.v26), .macOS(.v26)]` (macOS is present only so `swift test` runs the pure targets on the host; every Apple-framework import outside Domain is wrapped in `#if canImport(…)`).
- Dependencies: `groue/GRDB.swift` `.upToNextMinor(from: "7.11.1")`; `pointfreeco/swift-dependencies` `.upToNextMinor(from: "1.17.0")`; `pointfreeco/swift-snapshot-testing` `.upToNextMinor(from: "1.19.5")` (test-only: linked from `LedgerSnapshotTesting` and test targets only).
- Two swiftSettings arrays: `ui = [.defaultIsolation(MainActor.self), .strictConcurrency(.complete)]`, `core = [.defaultIsolation(nil), .strictConcurrency(.complete)]`. Both add `.unsafeFlags(["-warnings-as-errors"])`? **No** — unsafeFlags break package consumption; warnings-as-errors comes from `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` in `Config/Base.xcconfig`, and SwiftLint `--strict` covers the rest.
- Targets and edges (this table *is* the dependency diagram of architecture §3; anything else needs an ADR):

| Target | Settings | Depends on |
|---|---|---|
| LedgerDomain | core | — |
| LedgerDependencies | core | LedgerDomain, `Dependencies` |
| LedgerPersistence | core | LedgerDomain, `GRDB` |
| LedgerHealth · LedgerSync · LedgerActivityKit | core | LedgerDomain |
| LedgerDesign | ui | — (SwiftUI only) |
| FeatureOnboarding · FeatureToday · FeatureProgram · FeatureLibrary · FeatureHistory · FeatureSettings | ui | LedgerDomain, LedgerDesign, LedgerDependencies, LedgerTestSupport, `Dependencies` |
| FeatureWorkout | ui | as above + LedgerActivityKit |
| WatchFeatureWorkout | ui | LedgerDomain, LedgerDesign, LedgerDependencies, LedgerTestSupport, `Dependencies` |
| LedgerTestSupport | core | LedgerDomain, LedgerDependencies, LedgerPersistence, LedgerHealth, LedgerSync, LedgerDesign, `Dependencies` |
| LedgerSnapshotTesting | ui | LedgerTestSupport, `SnapshotTesting` |
| LedgerAppKit (product) | ui | every iOS Feature*, LedgerDomain, LedgerDependencies, LedgerPersistence, LedgerHealth, LedgerSync, LedgerDesign, LedgerActivityKit, `Dependencies` |
| LedgerWatchAppKit (product) | ui | WatchFeatureWorkout, LedgerDomain, LedgerDependencies, LedgerPersistence, LedgerHealth, LedgerSync, LedgerDesign, `Dependencies` |
| `<X>Tests` for every target above except LedgerTestSupport/LedgerSnapshotTesting | same as X | X, LedgerTestSupport, LedgerSnapshotTesting |

- `LedgerDomain` declares `resources: [.copy("Resources/exercises.json")]` with an empty `{"version":1,"exercises":[]}` placeholder (F03 fills it).

Tooling contracts:
- `mise.toml`: `[tools] swiftlint = "0.65.1"`, `swiftformat = "0.63.0"`, `lefthook = "2.1.14"`, `xcbeautify = "3.2.1"`.
- `.swiftformat`: `--swiftversion 6.3 --languagemode 6 --indent 4 --maxwidth 120 --wraparguments before-first --wrapparameters before-first --wrapcollections before-first --self remove --semicolons never --commas inline --header strip --exclude .build,DerivedData,**/__Snapshots__`.
- `.swiftlint.yml`: `strict: true`; `included: [LedgerKit, Apps]`; `excluded: [**/.build, **/__Snapshots__, DerivedData]`; `analyzer_rules: [unused_declaration, unused_import]`; `opt_in_rules` ≥ `force_unwrapping, implicitly_unwrapped_optional, explicit_init, first_where, empty_count, sorted_imports, unhandled_throwing_task, unowned_variable_capture, closure_body_length, fatal_error_message, discouraged_optional_boolean, contains_over_filter_is_empty, redundant_type_annotation, private_outlet, variable_shadowing`; severities: `force_cast/force_try/force_unwrapping: error`; `file_length: {warning: 300, error: 400}`; `type_body_length: {warning: 150, error: 200}`; `function_body_length: {warning: 40, error: 60}`; `line_length: {warning: 120, error: 140, ignores_urls: true}`. Custom regex rules, all `severity: error`, with `excluded` covering `.*Tests/.*` and `LedgerTestSupport`:
  - `feature_raw_color` (`included: LedgerKit/Sources/(Feature|WatchFeature)[A-Za-z]+/.*`): `Color\((red|white|hue|\.sRGB|\.displayP3|uiColor)|Color\.(red|blue|green|orange|black|white|gray|yellow|pink|purple|indigo|mint|teal|cyan|brown|primary|secondary|accentColor)\b|\.(foregroundStyle|foregroundColor|background|tint|fill)\(\.(red|blue|green|orange|black|white|gray|yellow)\b|UIColor\(|#colorLiteral`
  - `feature_raw_font` (same include): `\.font\(\.(system|largeTitle|title[23]?|headline|subheadline|body|callout|footnote|caption2?)\b|Font\.(system|custom)\(|\.fontWeight\(`
  - `feature_raw_padding` (same include): `\.padding\((\.[a-zA-Z]+,\s*)?-?\d` and `(VStack|HStack|LazyVStack|LazyHStack|Grid)\((alignment:[^,)]+,\s*)?spacing:\s*\d`
  - `feature_raw_radius` (same include): `cornerRadius:\s*\d|\.cornerRadius\(\d`
  - Repo-wide (Sources only): `no_dispatch_queue` `\bDispatchQueue\b`; `no_task_detached` `Task\.detached`; `no_nslock` `\bNSLock\b|DispatchSemaphore`; `no_shared_singleton` `static\s+(let|var)\s+shared\b`; `no_print` `(^|[^\w.])print\(`; `no_user_defaults_outside_settings` `UserDefaults` with `excluded: .*LedgerPersistence/Settings.*`; `unchecked_sendable_needs_reason` `@unchecked Sendable(?!.*//\s*(ADR|issue))`.
- `lefthook.yml`: `pre-commit` (parallel) → `swiftformat --lint {staged_files}` and `swiftlint lint --strict --quiet {staged_files}` via `mise exec --`; `commit-msg` → `scripts/check-commit-msg.sh {1}` (Conventional Commits regex `^(feat|fix|chore|docs|test|refactor|perf|ci|build)(\([a-z0-9-]+\))?!?: .+`).
- `scripts/bootstrap.sh`: `set -euo pipefail`; verify `xcodebuild -version` starts with the version in `.xcode-version`; `mise install`; `xcodebuild -downloadPlatform iOS -buildVersion 26.5` if `xcrun simctl list runtimes` lacks iOS 26.5 (same for watchOS 26.5); `mise exec -- lefthook install`; print versions.
- `scripts/check.sh`: implements the contract in `docs/testing-strategy.md` §7 verbatim (steps 0–5: mise tools, `swiftformat --lint`, `swiftlint --strict`, `xcodebuild test -scheme Ledger -testPlan PR`, `xcodebuild test -scheme LedgerWatch -testPlan PR-Watch`, `scripts/coverage-gate.sh`), plus `scripts/check-package-graph.sh` in step 2 and flags `--fast` (adds a host-side `swift test --package-path LedgerKit --filter 'LedgerDomainTests|LedgerPersistenceTests'` and skips the simulator steps), `--lint-only`, `--skip-lint` (used by CI after the `Lint` job), `--record-snapshots`. Simulator destinations default to `LEDGER_IOS_DEST='platform=iOS Simulator,name=iPhone 17,OS=26.5'` and `LEDGER_WATCH_DEST='platform=watchOS Simulator,name=Apple Watch Series 11 (46mm),OS=26.5'` (verify names with `xcrun simctl list`); output piped through `xcbeautify`; results under `.derivedData/Results/` (git-ignored). Exit non-zero on any failure (`pipefail`). `scripts/coverage-gate.sh` itself is delivered in F01; until then step 5 is a no-op that prints "coverage gate: F01".
- `Config/Base.xcconfig`: `SWIFT_VERSION = 6.0`, `SWIFT_STRICT_CONCURRENCY = complete`, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES`, `IPHONEOS_DEPLOYMENT_TARGET = 26.0`, `WATCHOS_DEPLOYMENT_TARGET = 26.0`, `MARKETING_VERSION = 0.1.0 // x-release-please-version`, `CURRENT_PROJECT_VERSION = 1`, `DEVELOPMENT_TEAM = <Team ID from Phase 0>`, `ENABLE_USER_SCRIPT_SANDBOXING = YES`, `GENERATE_INFOPLIST_FILE = YES`; per-target files set `PRODUCT_BUNDLE_IDENTIFIER`, `INFOPLIST_FILE`, `CODE_SIGN_ENTITLEMENTS`, `TARGETED_DEVICE_FAMILY = 1` (iOS) / `4` (watch), `SDKROOT`.

## Acceptance criteria
1. Given a fresh clone on a Mac with Xcode 26.6, when `scripts/bootstrap.sh` runs, then it exits 0 and `mise ls` shows swiftlint 0.65.1, swiftformat 0.63.0, lefthook 2.1.14, and both 26.5 simulator runtimes are present.
2. Given the project, when `xcodebuild build -scheme Ledger` and `-scheme LedgerWatch` run against the destinations above, then both succeed with zero warnings.
3. Given the built apps, when launched in the iOS 26.5 and watchOS 26.5 simulators, then each shows a screen containing the text "Ledger" (UI test `LaunchTests.test_launchShowsPlaceholder` on both platforms).
4. Given `scripts/check.sh`, when run on the F00 branch, then it exits 0 and prints every step.
5. Given a file `LedgerKit/Sources/FeatureToday/Violation.swift` containing `struct V { var v: Int! ; func f() { let x: Int? = nil; _ = x! } }` and a SwiftUI view with `.padding(13)` and `.font(.system(size: 17))`, when `scripts/check.sh` runs, then step (2) fails with `force_unwrapping`, `implicitly_unwrapped_optional`, `feature_raw_padding`, `feature_raw_font` errors and the script exits non-zero before building.
6. Given a new file added under `LedgerKit/Sources/LedgerDomain/` or `Apps/Ledger/`, when the project is built, then the file compiles and `git status` shows no change to `Ledger.xcodeproj/project.pbxproj`.
7. Given `lefthook` installed, when a commit with message `added stuff` is attempted, then the commit-msg hook rejects it; `feat(domain): add Weight` is accepted.
8. Given both app bundles, when inspected (`unzip -l` / `find … .app`), then each contains `Fonts/Archivo[wdth,wght].ttf` and its `Info.plist` lists it under `UIAppFonts`; `UIFont.familyNames` on the iOS simulator contains "Archivo" (asserted in `LedgerTests/SmokeTests.test_archivoIsRegistered`).
9. Given `Package.swift`, when `swift package describe --type json` runs, then the target list and edges match the table above exactly (asserted by `scripts/check-package-graph.sh` comparing against `LedgerKit/package-graph.expected.txt`, run as part of check.sh step (2)).

## Test plan
- Unit (LedgerDomainTests): `test_placeholderModuleName` (proves the target and Swift Testing run on the host and on both simulators).
- Integration (LedgerPersistenceTests): `test_grdbLinksAndOpensInMemoryQueue` (opens `DatabaseQueue()` — proves GRDB resolves on macOS, iOS, watchOS).
- Snapshot (LedgerDesignTests): none yet (F06).
- UI (LedgerUITests, LedgerWatchUITests): `LaunchTests.test_launchShowsPlaceholder`.
- Smoke (LedgerTests / LedgerWatchTests): `test_archivoIsRegistered`, `test_umbrellaProductLinks`.
- Tooling: shell tests are manual but scripted in the PR description: run criteria 5, 6, 7 and paste the output.

## Non-functional
- Performance budget: `check.sh` cold ≤ 20 min on an M-series laptop; `swift test` fast tier ≤ 60 s.
- Accessibility: n/a (placeholders), but placeholders already use `Text` (VoiceOver-readable).
- Offline behaviour: bootstrap needs network once (mise, runtimes); check.sh works offline afterwards.

## Risks / unknowns
- Synchronized folders may need a per-file exception (ADR-003 §5 fallback: one-shot XcodeGen then commit). Document in implementation-notes if used.
- `SWIFT_DEFAULT_ACTOR_ISOLATION` xcconfig key name must be verified in Xcode 26.6 build settings (Build Settings ▸ search "Default Actor Isolation").
- `defaultIsolation` swiftSetting requires tools-version ≥ 6.2; if the local toolchain rejects it, bump to 6.3 and note.
- `xcodebuild -downloadPlatform` is slow (5–8 GB per runtime); bootstrap must be idempotent.
- Simulator device names (`iPhone 17`, `Apple Watch Series 11 (46mm)`) are assumptions; check.sh reads overrides from env and bootstrap prints the available names on failure.

## Definition of Done
Inherits `docs/engineering-standards.md` §12, plus:
- [ ] Human checklist executed and the project commit is separate from agent commits.
- [ ] Criteria 5–7 demonstrated with pasted terminal output in the PR.
- [ ] `LedgerKit/package-graph.expected.txt` committed and matches the table.
- [ ] `docs/architecture.md` §2 amended (in this PR) to list `LedgerDependencies` and `LedgerSnapshotTesting`, and §3's edge list to include `Feature* → LedgerDependencies, LedgerTestSupport, Dependencies`.

---
_Filled in by agents during delivery:_
- `F00-project-skeleton/implementation-notes.md`
- `F00-project-skeleton/test-findings.md`
- `F00-project-skeleton/review.md`
