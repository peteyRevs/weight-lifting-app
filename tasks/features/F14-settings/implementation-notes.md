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
as it can be: values, oldest first. **Corrected in fix round 2:** the claim here that a stale entry is "harmless" was
wrong. G3 (F14-S1a-R1-1) showed that a change made elsewhere which equals a stale entry is taken for an echo, and the
screen then shows a value that is not in the row. The list was replaced; see "S1a fix round 2".

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

### S1a fix round 2 (G1, 2026-10-28)

Against G3's review (`2df12aa`, "## S1a — G3 review (round 1)") and the orchestrator's rulings. Commit `c8a52ac`,
then this notes commit.

**R1-1: the row read afresh (option (a)).** This is the final design of the store's echo handling. It replaces round
1's list.
- `written` holds the last value this store wrote. `committed = written ?? stored`, and `shown = pending ?? committed`.
- When the saver goes idle after writing or failing, it marks the follower. The follower starts a new observation
  and retires the one before by its number (`observationNumber`): the old observation receives nothing more and ends
  at its next value, which ends its stream. A task group cannot cancel one child alone, and after `cancelAll()` every
  task added starts cancelled. I found that the hard way: the first try hung every test.
- The new observation's first value is the row as it is now. It is taken as committed, and `written` is forgotten,
  only when three things hold: no save is running, nothing is pending, and no save has returned since the
  observation started (`writes`). A save that returned since may have committed after the observation's first read,
  so that read is older than the row. Without this check, `lateEcho_afterTapBack_doesNotFlicker` failed 2 runs in 60
  (a first read of KG delivered after LB's write). With it, 80 of 80 runs passed. A save that returned means another
  fresh read follows when the saver goes idle again, so `written` is always forgotten in the end.
- Between the fresh reads, an echo, or a change made elsewhere, updates `stored` only. A late echo of an earlier
  save never draws over a newer value (F14-S1-3). A change made elsewhere during a burst of saves is shown at the
  burst's fresh read; one made while the store is idle is shown at once.
- What (a) removed: the FIFO (`unechoed`) and its index rule (G3's M9), and with them the `else { unechoed = [] }`
  branch (M3). M3's test went with its branch. In its place, `changeElsewhere_afterAHeldEcho_isShown` pins the same
  behaviour in the new design. N2's separate resubscription is gone too: every fresh read follows an unreadable row
  again.
- `ScriptedSettings`, G2's test double, now sends a held echo only to the observations there were when its value
  was committed, as a GRDB observation starts with a fetch and never hears of an earlier commit. It also gains
  `deliverNewestEcho()` (coalescing) and `writeElsewhere(_:)`, for G3's probes.
- The store's doc comment and the round-1 notes no longer call a stale entry harmless.

**R1-2: tests.** All of these are in `SettingsSaveQueueAdversarialTests+Round2.swift`:
- `coalescedEcho_thenAChangeElsewhere_drawsTheRow`: G3's stale-entry probe. It passes.
- `echoesABA_inOrder_neverDrawB`: G3's in-order A, B, A probe. It passes.
- `changeElsewhere_afterAHeldEcho_isShown`: R1-2's first case, in the new design.
- `restart_handsTheQueuedChangeToTheNewRun`: G3's test. **M5 is killed.** With the defer's `saveMark?.yield()`
  replaced by a no-op, this test fails with 4 issues (I ran it, then restored the line).
- **M3 no longer exists**: its branch went with the FIFO.

**R1-3: the seed in the device row's write.**
- `LedgerStores.open(at:kind:regionalSettings:now:newID:)` runs `LocalDevice.open(in: Database, …)` and, when the row
  is new and regional settings are given, `GRDBSettingsRepository.seedIfAbsent(_:at:in:)` in the same `write`.
- `LedgerStores.isNewInstall` is gone. `DatabaseLaunch` passes `regionalSettings` to the open, and `loadSettings`
  only loads.
- A seed the database refuses now takes the device row with it and fails the open (decision #29's screen). The
  foreground retries, and that retry is again a new install's.
- Tests in `DatabaseLaunchTests+Regional`:
  - `deviceRowAndSeed_areOneWrite` replaces `regionalSeedFailure_carriesOn`. It pins that the "first launch died
    after the device insert" state cannot be reached: a refused seed leaves no device row, and the retried open
    seeds.
  - `onlyTheFirstLaunch_isANewInstall` is removed with `isNewInstall`.
  - Still covered, by these tests and G2's: the fresh install, an install with a device row and no settings row,
    and a pre-F14 install with a program.

**R1-4:** nothing to do in F14.

**R1-5: Bool first, then `#expect`.** I bound every whole-`Settings`, model or `Program` comparison G3 listed:
- `SettingsStoreTests` and `+Unreadable`;
- `SettingsReachTests`;
- `DatabaseLaunchTests+Regional` (rewritten);
- `SettingsRepositoryTests` (my seed test, and F05's two lines at :47 and :71, which are sanctioned edits under this
  ruling);
- `AppCompositionTests`' two tests.

**R1-6.** `"{name} {version}"` is now the catalog key `"%@ %@"` (`SettingsCopy.nameAndVersion`), with a comment that
gives the order and says a translation may reorder with `%1$@`/`%2$@`. The catalog has 27 keys.

**The `locale:` parameters are kept, against the ruling.** I dropped them, and `ModuleCopyTests`' audit failed all
three lookups: "a lookup whose key carries a value and that passes no `locale:`" (standards §7). That rule is a gate.
So the parameters stay, and `SettingsCopy+Names` says why. This is G3's alternative, "say why it is kept". If the
orchestrator wants them gone, the audit's rule needs an exemption first.

**R1-7:** the bounded wait in `restartDuringASave_keepsSaving` is 1,000 yields.

**APIs S1b's rebase must know about:**
- `SettingsStore`:
  - `unechoed` is gone; `written` (observed) is back, with a new meaning.
  - `committed` is `written ?? stored`.
  - New members: `observationNumber`, `writes`.
  - `stored` is any observation's last value.
- `LedgerStores`: `isNewInstall` is gone, and `open` takes `regionalSettings:`.
- `LocalDevice.open` is internal and takes a `Database`.
- `GRDBSettingsRepository.seedIfAbsent(_:at:in:)` is new and internal.
- `SettingsCopy`: `nameAndVersion(_:_:locale:)` is new.
- None of these names appear in the draft's sources. Its `SettingsRootTests` waits on `pending == nil`, which still
  means "written".

**Runs (host).**
- `FeatureSettingsTests` (42 tests): 80 of 80 runs passed after the `writes` check, and green again after the last
  edits.
- `grdb_burstsConverge` (6 seeds × 60 changes over GRDB): **30 of 30** runs passed.
- The persistence, domain, dependencies, AppKit and FeatureSettings targets passed. Their known issues are the old
  ones (`InMemoryStores` F7-10, and `LedgerDependenciesTests`' 18).
- swiftformat and swiftlint (strict) are clean on every changed file.

**Net product lines** (against `bd2d26c`): 698 added, 24 removed, **net 674**, plus 5 in `Package.swift` (679). This
round alone is +94 / −66, net +28.

#### The gate (fix round 2)

`scripts/check.sh` (full: iOS and watchOS), through the simulator lock, on `c8a52ac`: **exit 0, "check.sh OK"**,
1,932 s. Steps: lint 75 s, iOS build 33 s, string catalogs 1 s (7 catalogs, each matching its code, the new
`"%@ %@"` among them), iOS tests 1,530 s, watchOS build 20 s, watchOS tests 269 s, coverage 2 s. Coverage:
FeatureSettings 99.20 % (502 / 506), overall 98.55 %.

### S1a fix round 3 (G1, 2026-10-28)

Against G3's round 2 (`ba60919`, "## Round 2") and the orchestrator's rulings. One code commit, then this notes
commit. No sim gate in this round: the orchestrator runs it.

**R2-1: a retired observation is closed at once.**
- Each observation runs in its own child task of the follower: `observe(_:until:)`. That task holds a small task
  group of two children:
  - the observation itself;
  - a waiter on its own `retired` stream.
- When the next observation starts, the follower finishes the old one's `retired` stream
  (`SettingsStore.retireObservation`). The waiter ends, the group's `next()` returns, and `cancelAll()` cancels the
  observation, which ends its stream and its GRDB `ValueObservation`.
- Cancelling the run cancels the follower and so every observation, structurally. No `withTaskCancellationHandler`
  is needed, and no unstructured `Task`, which `FeatureSettingsSourceTests` forbids in this module ("no file starts a
  task of its own").
- **About `cancelAll`:** the ruling said to avoid it on a group. The trap from round 2 was `cancelAll()` on the
  follower's long-lived group: every task added to a cancelled group afterwards starts cancelled. Here it is called
  on a group that belongs to one observation and ends right after. Nothing is ever added to it again, so the trap
  cannot occur. The follower's own group is never cancelled.
- **Test:** G3's P2, as `failingSaves_leaveOneObservationOpen`. After 20 failing saves exactly one observation is
  open, and never more than two at any turn sampled (1,000 turns after each failure).
- **A deadlock this exposed in the in-memory fakes, fixed.** Closing observations for real means streams now end
  while values are being yielded.
  - `ObservedState` (LedgerFakes) and G2's `ScriptedSettings` both took their lock in a stream's `onTermination`.
  - The runtime calls that handler holding the cancelled consumer task's lock. A write yielding under the store's lock
    takes the same task's lock to resume it.
  - That is an ABBA deadlock. In the first 60-run batch it hung the whole test process in 6 runs. `sample` showed the
    two stacks: the main thread in `_swift_taskGroup_cancel_unlocked` → `onTermination` → mutex wait, and a pool
    thread in `broadcast` → `yield` → the status-record lock.
  - Both handlers now only set an `EndedFlag` (an `Atomic<Bool>`; new and public in LedgerFakes). The next write or
    delivery drops the ended observers.
  - GRDB's own streams were never affected.

**R2-2: two conditions pinned.**
- **(a)** `ScriptedSettings(holdsFirstValues:)` holds each observation's first value, which is read when the
  observation starts, until `deliverNextFirstValue()`, as GRDB fetches it at once and delivers it later.
  - `firstValueReadBeforeASave_isNotTheRow`:
    1. A is saved. Its restart starts D, which reads A.
    2. The test keeps the restart mark from the follower (it takes `followMark` and gives it back later), which holds
       open the window G3 described: a GRDB delivery that lands during the saver's tail.
    3. B is saved and returns.
    4. D's read of A arrives. The screen must stay on B.
  - With the mark handed straight to the follower, D is retired before its value is read, so the window cannot be
    reached without holding it.
- **(b)** `failureBeforeTheFreshRead_stillReadsTheRow` is G3's P3.

**R2-3:** `receive` tests `readsTheRowAfresh, !isSaving`; `pending == nil` is gone, and the doc comment says why
(the fresh read is the row whatever is pending).

**Mutation kills.** Each mutant was run on a scratch copy of the worktree
(`scratchpad/mut3/LedgerKit`), never in the worktree, against the test named:

| Mutant | Test | Result |
|---|---|---|
| M1: `isFirst && writes == writesBefore` → `isFirst` | `firstValueReadBeforeASave_isNotTheRow` | **Killed**, 2 issues |
| M11: `writes += 1` removed | `firstValueReadBeforeASave_isNotTheRow` | **Killed**, 2 issues |
| M7: the failure path leaves `hasWrittenOrFailed` false | `failureBeforeTheFreshRead_stillReadsTheRow` | **Killed**, 1 issue |
| R2-1: the retired observation is not finished (`retireObservation?.finish()` removed) | `failingSaves_leaveOneObservationOpen` | **Killed**, 2 issues |

The unmutated copy passes all four tests. Under M1, the whole of FeatureSettingsTests also fails elsewhere: the
oracle, R1-1, and N2's re-follow.

**Runs (host).**
- `FeatureSettingsTests`, 45 tests: **65 of 65** runs passed after the fakes fix.
  - Each run was bounded by a 60 s alarm, so a hang counts as a failure.
  - Before that fix, the first batch failed 7 of 10, by the hang above.
- Passed: the persistence, dependencies, AppKit, Library, Program, Today, Onboarding, Workout and Sync host suites.
  Their known issues are the old ones.
- `grdb_burstsConverge`: 10 of 10.
- swiftformat and swiftlint (strict) are clean on the changed files.

**APIs S1b's rebase must know about:**
- `SettingsStore.retireObservation`: new.
- `LedgerFakes.EndedFlag`: new and public.
- `ScriptedSettings`: gains `holdsFirstValues`, `deliverNextFirstValue()` and `firstValuesWaiting`.
- Nothing the draft names has changed.

**Net product lines** (against `bd2d26c`): 733 added, 34 removed, **net 699**, plus 5 in `Package.swift` (704). This
round alone is +37 / −12, net +25: LedgerFakes' `ObservedState` +11 and the store +14.
