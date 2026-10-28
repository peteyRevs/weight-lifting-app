# F14 — implementation notes

## S1 — as built (G1 implementer, 2026-10-28)

Branch `feat/F14-settings`, cut from `main` at `98b340d` plus the plan `ec0c42b` and the rulings `bd2d26c`. The
specification is the brief's "Plan amendments (planner, 2026-10-28)" (C1–C29; slice S1: criteria 1, 2, 4, 7, 8 and
N1–N10) and "Rulings before G1". Pete's Q1–Q7 are built to the recommended defaults (S1 builds Q2 = A, Q4 = A,
Q7 = A).

**The slice was split (R10, the brief's stop rule).** The whole of S1 was written and measured at about **1,040 net
product lines**, past the ~1,000 line set for this lane. As instructed, this branch carries only the plan's first
part, **S1a: the domain, persistence, launch, copy, presentation and store, with nothing on screen** (601 net, plus
5 in `Package.swift`). The second part, **S1b: the views, `SegmentedChoice`, the previews and the app's wiring**
(about 440 net), is written and kept as a draft patch against this branch (see "S1b, ready as a draft" below). Nothing
was compressed to fit.

Commits:
- `a374175` feat(settings): the region's settings seeded on a new install's first launch (N3).
- `0d0508d` feat(settings): Settings' store, presentation and copy, with nothing on screen yet (S1a).
- this notes commit (docs only).

### What landed (S1a)

Paths under `LedgerKit/`.

- **Domain.** `Settings.regional(locale:calendar:)`: pounds where `locale.measurementSystem == .us`, kilograms
  elsewhere; `weekStart = Weekday.first(of: calendar)`; the rest `.default`'s. `Settings.default`'s doc no longer says
  decision #15 is unimplemented. `SettingsRepository.seedIfAbsent(_:)` (A3).
- **Persistence.** `GRDBSettingsRepository.seedIfAbsent` is `INSERT … ON CONFLICT (id) DO NOTHING`: a stored row,
  readable or not, keeps its payload, version and `updated_at`. `DatabaseLaunch` takes `regionalSettings: Settings?`
  (default nil); its `loadSettings` step seeds it before loading; a seed that throws is logged (error level, not a
  launch failure) and the step goes on with what `load()` gives.
- **Fakes and stubs.** `InMemorySettingsRepository.init(_ settings: Settings? = nil)`: a value given is a stored row,
  none is "no row" (load gives `.default`), so `seedIfAbsent` can tell the two apart. Every existing caller passes a
  value or nothing, unchanged. `UnimplementedSettingsRepository.seedIfAbsent` throws.
- **Contract.** `SettingsRepositoryContract` gains two clauses, run on GRDB and in memory: a seed with no row saves
  and is observed; a seed over saved settings (even ones equal to `.default`) changes nothing, and a later save still
  replaces them. GRDB only: three unreadable rows (later version, invalid JSON, non-UTF-8 payload) are untouched by a
  seed, and a seed writes the row at the save's version and time.
- **LedgerAppKit.** `AppComposition.Environment.regionalSettings`; `.live` passes
  `.regional(locale: .autoupdatingCurrent, calendar: .autoupdatingCurrent)`. The watch passes nothing.
- **FeatureSettings** (the placeholder and its test removed):
  - `SettingsRoute` (`.debugMenu`, `#if DEBUG` only: a Release build has no case), `AppAbout`, `SettingsAction`,
    `SettingsInput`, `SettingsModel`.
  - `SettingsPresentation.make(_:)`: units (LB/KG, spoken pounds/kilograms), the rest (`RestDuration.label`, in
    words through `Duration.UnitsFormatStyle`, each step nil past 30 or 300 s), the seven weekdays from the
    calendar's first weekday named with `standaloneWeekdaySymbols` in the lifter's locale, the three switches, the
    Health row ("Apple Health", "Not connected"), Diagnostics in Debug only, and the About line.
  - `SettingsStore` and `+Sources` (N1, N2, R7; see below).
  - `SettingsCopy.swift`, `SettingsCopy+Names.swift` and `Resources/Localizable.xcstrings`: 26 keys.
- **Module setup (C4, part).** `Package.swift` gives FeatureSettings its `resources`;
  `coverage-thresholds.json` `required` gains it. `snapshotTestTargets` and `PreviewScan.registeredModules` wait for
  S1b, which has the first references and previews.
- **Tests.** `FeatureSettingsTests`: `SettingsPresentationTests`, `SettingsStoreTests` (+`Unreadable`),
  `SettingsCopyTests`, `FeatureSettingsSourceTests`, support. `LedgerDomainTests/Model/SettingsRegionalTests`.
  `LedgerPersistenceTests`: `DatabaseLaunchTests+Regional`, two GRDB tests in `SettingsRepositoryTests`.
  `LedgerAppKitTests/SettingsReachTests` (the cross-store criteria 2 and 7: FeatureSettingsTests cannot import
  FeatureProgram or FeatureToday, LedgerAppKitTests can). One test in `AppCompositionTests`.

### The store (N1, N2, R7)

- A change applies to the settings on screen (`pending ?? stored`) and the model is made before `send` returns.
- `pending` holds the lifter's latest whole value until the observation gives it back; an earlier save's echo only
  updates `stored`, so a control never flickers back.
- Saves run in `run()`'s task group (no task of the store's own), on a `bufferingNewest(1)` channel: one at a time,
  each of the whole `Settings`; changes made during a save are folded into the next (last value wins).
- A failed save drops every pending change, shows "Couldn't save that change." under the title, and draws the stored
  settings. The next change clears the line.
- N2: when the observation ends, the screen draws what it last had, else `Settings.default`, and nothing is saved.
  The first change saves the whole value over the unreadable row; after that save the follower subscribes again.
- A save that changes nothing stored (and so is never echoed) clears `pending` itself.
- **Known limit, documented on the root in S1b:** a change is saved by the screen's task. A change whose save has not
  begun when the lifter leaves the screen is not saved (the save runs within milliseconds of the tap, so this needs a
  tap and Back in the same instant). The exercise sheet's save behaves the same.

### Decisions and deviations

1. **The split** (above). S1a's store is reached only by tests until S1b's root makes one; S1a's `.debugMenu`
   route has no resolver until S1b.
2. **Regional settings come through the environment, not the environment's locale and calendar.** The plan had
   `AppComposition` read "the environment's locale and calendar". A test's `Environment` would then seed the host
   machine's region and move every launch test that relies on Monday weeks (`RootGateLaunchTests`, the gate
   adversarial suites). `Environment.regionalSettings` is nil in tests (they keep `Settings.default`) and the region's
   in `.live`.
3. **UI tests now launch in the simulator's region**: en_US, so a `-LEDGER_UITEST` install starts in pounds with
   weeks from Sunday (it was Monday). Program weeks are unaffected (C10). Today's strip and "this week" in the nightly
   UI tests now count from Sunday; I found no UI test that reads the strip's first day, but the nightly plan was not
   run in this lane (see "Runs").
4. **The seed's failure is logged, not recorded as `.failed(.loadSettings)`**: the load still runs and may succeed.
5. **About line (N6).** "{name} {version} · build {build}". No name: "Version 1.2.3 · build 45". Neither version nor
   build: "App · Version unknown" (or "Version unknown"), so the line always says what is known in words. Blank
   values count as missing.
6. **Weekday names** are `standaloneWeekdaySymbols` of the injected calendar with the injected locale ("lundi"), so a
   menu item reads as a word on its own.

### New user-facing wording

"Couldn't save that change." · "TRAINING" · "Units" / "Applies to every log and chart" (prototype) · "Default rest" /
"Used for new exercises" (prototype) · "Week starts on" / **"For the week strip and the week's totals"** (new) ·
"Plate math" / "Show the plates per side on each set" · "Auto rest timer" / "Start the clock when a set is logged" ·
"Watch haptic at zero" / "Buzz the wrist when rest ends" (prototype) · "DATA" · "Apple Health" / "Not connected" ·
"Diagnostics" · "LB", "KG", spoken "pounds", "kilograms" · "Version %@", "build %@", "Version unknown".

### Sanctioned edits

| File | Edit | Why |
|---|---|---|
| `FeatureSettingsTests/FeatureSettingsTests.swift` | Removed with the placeholder | A8 |
| `LedgerPersistenceTests/DatabaseLaunchTests.swift` | `Subject.init` takes `regionalSettings:` and `in:` (defaults keep every call); the new tests live in `+Regional` (file length) | A8 |
| `LedgerDependenciesTests/UnimplementedStubTests.swift` | The settings stub list gains `seedIfAbsent` | A3 |
| Nine `SettingsRepository` doubles: `OnboardingAdversarialStores` (`ProbedSettings`, forwards and notes), `StoreDoubles` (`FailingSettings`), `LibraryStoreTests` (`EndedSettings`, throws), `ProgramStoreScene` (`OnceSettings`), `TodayStoreAdversarialSupport` (`ScriptedSettings`, throws), `AppRootGateAdversarialProbes` (`GateProbedSettings`, forwards and notes), `ProtocolsAdversarialTests` (`BriefSettingsRepository`), `StartWorkoutUseCaseAdversarialSupport` (`UnreadableSettings`) | One `seedIfAbsent` each | A3: a protocol requirement, as F12's `bestSets()` |
| `LedgerAppKitTests/AppCompositionTests.swift` | One new test | N3 |

### Product lines per file

Non-blank, non-comment Swift lines in `LedgerKit/Sources` and `Apps`, `LedgerTestSupport`, UI tests and catalogs
excluded, against `bd2d26c`.

| File | + | − |
|---|--:|--:|
| `FeatureSettings/SettingsCopy.swift` | 121 | |
| `FeatureSettings/SettingsPresentation.swift` | 119 | |
| `FeatureSettings/SettingsStore.swift` | 95 | |
| `FeatureSettings/SettingsStore+Sources.swift` | 76 | |
| `FeatureSettings/SettingsModel.swift` | 64 | |
| `FeatureSettings/SettingsCopy+Names.swift` | 47 | |
| `LedgerFakes/InMemorySettingsRepository.swift` | 18 | 6 |
| `LedgerPersistence/Repositories/GRDBSettingsRepository.swift` | 13 | |
| `LedgerPersistence/DatabaseLaunch.swift` | 10 | |
| `FeatureSettings/SettingsAction.swift`, `AppAbout.swift` | 10 each | |
| `FeatureSettings/SettingsInput.swift` | 9 | |
| `LedgerDomain/Model/Settings.swift` | 6 | |
| `FeatureSettings/SettingsRoute.swift` | 5 | |
| `LedgerAppKit/AppComposition.swift` | 4 | 1 |
| `LedgerDependencies/…/UnimplementedStores.swift` | 3 | |
| `LedgerDomain/Protocols/Repositories.swift` | 1 | |
| `FeatureSettings/FeatureSettings.swift` (placeholder) | | 3 |
| `Package.swift` | 5 | |
| **Total** | **616 added** | **10 removed (net 606)** |

Against the plan's S1a estimate of about 460: the copy (168, every lookup wrapped by the formatter), the presentation
(119) and the store (171, the serial and folded saves and N2's resubscription) carry the excess, as F12 S1's copy and
store did.

### S1b, ready as a draft

`/private/tmp/claude-501/-Users-peterarevalo-Dev-workout-app/c550c068-d570-4451-b1c9-69f88f147b7a/scratchpad/F14-S1b-draft.patch`
(a copy in this worktree's ignored `.derivedData/F14-S1b/`) applies cleanly on `0d0508d` (`git apply --check`). It
holds:
- `FeatureSettings/SettingsRoot.swift` (draws the title alone until the settings are read, so `settings.title` is
  there from the first frame; `AppTabsTests` then needs no edit), `Views/` (`SettingsScreen`, `SettingsPage` with
  `SettingsHeader`, `SettingsSection` with the row helpers, `TrainingRows` (units, rest, switches), `WeekStartRow`
  (a `Menu` over a `Picker`, ink-tinted), `Settings+Previews` (3 states)).
- `LedgerDesign/Components/SegmentedChoice.swift` with its gallery section, `SegmentedChoiceTests` and 6 component
  references.
- `LedgerAppKit`: `AppAbout.swift` (`AppAbout(bundle:)`, `.main`), `Routes+Settings.swift`, `AppTabs` drawing
  `SettingsRoot`, `MainRoot` passing `onSettingsRoute`; `AppCopy.settingsTitle` and its key removed, with
  `AppCopyTests`, `AppCopyAdversarialTests` (six strings) and `ModuleCopyTests` (7 → 6, and the `AppAbout.swift`
  Info.plist keys exempted) following.
- `snapshotTestTargets` and `PreviewScan.registeredModules` gain FeatureSettings.
- Tests: `PreviewTests`, `SettingsAccessibilityTests`, `SettingsLayoutTests`, `SettingsRootTests`,
  `SettingsSnapshotTests` (8 references, looked at: lb light large, kg dark large, kg dark accessibility3, and the
  segmented control at light accessibility3), `SettingsRouteMappingTests`, the view checks of
  `FeatureSettingsSourceTests`, and the nightly UI test `Apps/LedgerUITests/Settings.swift`.

Its state: one simulator run of the whole S1 passed every Settings accessibility, layout, store, and AppKit test
(`AppTabsTests` unchanged and green). Three hosted tests failed on that run and were corrected in the patch but **not
re-run**: the group test of `SegmentedChoice` was removed (the hosted reader flattens containers), its one-row check
now allows 44 pt, and `SettingsRootTests.loading_drawsTheTitle` no longer reads the identifier (the UI tests do). Still
to do in S1b: re-record `DesignGalleryTests`' dark reference (the new section is the only change), run swiftlint and
swiftformat on its files, look at the remaining references, the nightly UI test, and the PR-sweep seconds.

### Runs

- Host: `swift build --build-tests` clean; the FeatureSettings, persistence (settings, launch, contracts), domain
  (regional), dependencies (stubs) and AppKit (composition, copy, reach) suites green.
- **Full gate on this branch:** see "The gate".

### The gate

`scripts/check.sh` (full: iOS and watchOS), through the simulator lock, on `0d0508d`: **exit 0, "check.sh OK"**,
2,251 s of steps (it waited about 20 min for the lock first). Steps: tools 1 s, format 5 s, lint 90 s, iOS build 86 s,
string catalogs 1 s, iOS tests 1,720 s, watchOS build 53 s, watchOS tests 291 s, coverage 2 s. Coverage: FeatureSettings
98.04 % (451 / 460) against 70 %; overall 98.52 %.

PR-sweep seconds for S1a's suites were not measured separately: S1a adds no hosted suite (the plan's 6–9 s estimate
is S1b's hosted suites and references).

### S1a fix round 1 (G1, 2026-10-28)

Against G2's findings in `fdb28bf` ("## S1a — G2 findings") and the orchestrator's rulings. Commit `bcdeacb`, then
this notes commit.

| Finding | What changed |
|---|---|
| F14-S1-1 (ruled) | No code change was needed: a failed save already dropped what was queued behind it. The rule is now "back to what is **committed**" (with S1-2). G2's test became `changeDuringAFailingSave_isDroppedWithIt`, which pins the ruling: one save, the screen shows the committed value, and the line. The spec's N1 gains the ruling's sentence. |
| F14-S1-2 | A failure reverts to `committed`, the newest value the store knows is in the row, not to the observation's last echo. |
| F14-S1-3 | `SettingsStore.unechoed`: the store's committed saves that the observation has not echoed yet, oldest first. `committed = unechoed.last ?? stored`, and `shown = pending ?? committed`. `pending` is cleared by the saver as soon as it is written, never by an echo. An echo that matches an entry drops that entry and those before it (a GRDB observation may coalesce commits). A value that matches no entry is a change made elsewhere: the list is emptied and that value is committed. |
| F14-S1-4 | `isSaving`: one save at a time, whichever run started it. A run whose task is cancelled starts no further save, and on leaving it hands any change still pending to the current run's saver. Each run has a number (`runNumber`), and a run clears the marks at its end only while they are still its own. |
| F14-S1-5 (ruled) | `LocalDevice.open(in:kind:now:newID:) -> (id, isNew)`. `id(…)` now calls it. `LedgerStores.isNewInstall`. `DatabaseLaunch` seeds the regional settings only when `stores.isNewInstall`. A seed that fails on that first launch is not retried: the install then keeps `Settings.default`. |
| F14-S1-6 | `LedgerAppKit/UITestRegion.swift`: under `-LEDGER_UITEST`, `Environment.live` seeds a US iPhone's settings (en_US, Gregorian: pounds, weeks from Sunday) whatever the simulator's region is. I chose the equivalent under `-LEDGER_UITEST` over adding `-AppleLocale`/`-AppleLanguages` to the 23 launch sites. The app's text is English only (every catalog holds `en`), so the region was the one thing a runner could change. |
| F14-S1-7 | `present(_:)` returns the trimmed value. |

**Why a list of unechoed saves (S1-3), and not "ignore echoes while anything is pending".** Ignoring echoes still
needs to know when the last of this store's own echoes has arrived. Without that, the late echo of an earlier save
lands once nothing is pending and is drawn, which is exactly G2's script. The list is that knowledge, kept as small
as it can be: values, oldest first. An entry whose echo GRDB coalesced away, or whose value equals the observation's
last (`removeDuplicates`), can stay in the list. That is harmless: the screen shows the list's newest entry, which is
the last value written, and a change made elsewhere empties the list. Nothing in S1a writes settings from elsewhere.
S3's erase will reach the store as such a change.

**G2's known issues are now plain tests**, with no expectation loosened. The doc comments of S1-2 to S1-4 say they
are fixed. G2's comment on Saudi Arabia was already right (Sunday). No comment or test on this branch says Saturday
for SA: the Saturday cases are fa_IR's.

**New tests:**
- `DatabaseLaunchTests+Regional`:
  - `deviceRowWithoutSettings_isNotSeeded`: a device row with no settings row is not seeded, nothing is written,
    and the settings are `.default`;
  - `onlyTheFirstLaunch_isANewInstall`.
  - The fresh install is still `regional_seededOnce_thenLoaded`, and the pre-F14 install with a program is G2's
    `installBeforeF14_keepsItsSettings`.
- `AppCompositionTests.uiTestEnvironment_seedsAUSiPhonesSettings`.
- The mid-save restart is G2's `restartDuringASave_keepsSaving`, now plain: one save at a time, and a later change
  is saved.

**Runs (host):**
- `SettingsReachAdversarialTests.grdb_burstsConverge` (6 seeds × 60 changes over GRDB) passed **30 of 30** runs in a
  row.
- `FeatureSettingsTests` (38 tests, the seeded property test included) passed 10 of 10.
- Each of the persistence, domain, dependencies, AppKit, Library, Program, Today and Onboarding host suites passed.
- `FeatureWorkoutTests`' pump and updates adversarial suites failed on the host, in different tests each run
  (`WorkoutPumpAdversarialSession.swift:244`, `WorkoutUpdatesAdversarialTests.swift:27`). Those are unrelated timing
  waits, while another lane's gate held the machine; nothing in FeatureWorkout changed. The gate below is the
  arbiter.

**APIs S1b's draft patch must follow when it is rebased:**
- `SettingsStore`: `written` is gone. It now has `unechoed`, `committed`, `isSaving` and `runNumber`.
- `shown` is `pending ?? committed`.
- `stored` is the observation's last value only.

None of these are named in the draft's sources. The draft's `SettingsRootTests` waits on `pending == nil`, which
still means "written". `LedgerStores.init` gains `isNewInstall:` (default false). `LocalDevice.open` is new.

**Net product lines** (against `bd2d26c`): 662 added, 16 removed, **net 646**, plus 5 in `Package.swift` (651). The
round itself is +70 / −25, net +45: the store +16, `UITestRegion` +13, `LedgerStores` and `LocalDevice` +15, and
the composition, launch and presentation +1.

#### The gate (fix round 1)

`scripts/check.sh` (full: iOS and watchOS), through the simulator lock, on `bcdeacb`: **exit 0, "check.sh OK"**,
2,100 s of steps. Steps: format 1 s, lint 99 s, iOS build 64 s, string catalogs 2 s, iOS tests 1,628 s, watchOS
build 27 s, watchOS tests 275 s, coverage 2 s. Coverage: FeatureSettings 98.95 % (473 / 478), overall 98.54 %. The
FeatureWorkout suites that failed on the host passed here.
