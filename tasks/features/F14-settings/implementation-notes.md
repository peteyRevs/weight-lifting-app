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

Against G3's round 2 (`ba60919`, "## Round 2") and the orchestrator's rulings. Code and notes in one commit, `262bb8f`; this sentence fixed in the commit after
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

## S1b — as built (G1 implementer, 2026-10-29)

Branch `feat/F14-settings-screen`, cut from `main` at `e10cbe0` (S1a #78 and F13 S1 #77 are in it). The draft patch
(see "S1b, ready as a draft") was applied with `git apply --3way`. Pete's questions are still open: S1b builds Q2 = A,
Q4 = A and Q7 = A, the recommended defaults.

Commits:
- `ae9a84a` feat(settings): the Settings screen, drawn from its store, with the design system's two-option control
  (S1b).
- `346fe53` test(settings): G3's round 3 (R3-1 to R3-4).
- `3571ecd` test(design): the gallery's dark reference re-recorded.
- this notes commit (docs only).

### What landed (S1b)

The draft as described in "S1b, ready as a draft", unchanged in substance:
- `SettingsRoot` and `Views/`: `SettingsScreen`, `SettingsPage` with `SettingsHeader`, `SettingsSection`,
  `TrainingRows`, `WeekStartRow` and `Settings+Previews`.
- `LedgerDesign/Components/SegmentedChoice.swift`, with its gallery section, its tests and 6 component references.
- `LedgerAppKit`:
  - `AppAbout(bundle:)` and `.main`;
  - `Routes+Settings.swift`;
  - `AppTabs` draws `SettingsRoot`, and `MainRoot` passes `onSettingsRoute`;
  - `AppCopy.settingsTitle` and its catalog key are gone.
- FeatureSettings is in `snapshotTestTargets` and in `PreviewScan.registeredModules`.
- Tests: the root, accessibility, layout, snapshot (8 references), preview and route-mapping tests, the view checks of
  `FeatureSettingsSourceTests`, and the nightly UI test `Apps/LedgerUITests/Settings.swift`.

**The rebase.** None of the store's names that the three fix rounds changed appear in the draft's sources.
`SettingsRootTests` waits on `pending == nil`, which still means "written": the saver clears it once it has written.
Four files conflicted, each with F13 S1's lines, and each was resolved by keeping both sides:
- `Package.swift` (`snapshotTestTargets`);
- `AppTabs` (`onHistoryRoute` and `onSettingsRoute`);
- `MainRoot` (the two route handlers);
- `PreviewScan` (`FeatureHistory` and `FeatureSettings`).

`AppTabsTests` needed no edit.

**G3's round 3 (S1a), in this slice:**
- **R3-1.** With `holdsFirstValues`, `ScriptedSettings` now queues the values sent to an observation behind its held
  first value. `deliverNextFirstValue()` sends them right after it, in order, as GRDB does.
  - `firstValueReadBeforeASave_isNotTheRow` now runs G3's order. Before D's read is delivered, the test checks that
    B's echo has not overtaken it (`stored` is still A).
  - It then delivers A and B together, and checks with `withObservationTracking` that `model` never changes while
    they are received. Under M1 the model changes to A for a moment; the old final check could not see that, because
    B's echo lands right after.
- **R3-2.** `failureBeforeTheFreshRead_stillReadsTheRow` runs with `holdsFirstValues`. The fresh read after the first
  save is delivered only once the second save is held, so it always lands while `isSaving`. The test checks that
  (`written` is still KG) before the save fails. It then waits for the failure's own fresh read: under M7 there is
  none.
- **R3-3.** New: `retiredObservationsValue_isNeverReceived`.
  - The test keeps the first observation's `retireObservation` handle from the follower, so that observation stays
    open after it is retired. This is the window G3 described (between `finish()` and the cancellation landing),
    held open, as the R2-2 test holds `followMark`.
  - A's echo is held for that observation. After B's save, the row is read afresh at B, and A's echo is then delivered
    to the retired observation only. The screen must stay on B.
- **R3-4.** `EndedFlag`, with its two lines, now sits above `ObservedState`'s doc comment.
- `ScriptedSettings`' read-only accessors moved to an extension in the same file (type body length; nothing
  compressed).

**Mutation kills** (`swift test` on a scratch copy of `LedgerKit` at `346fe53`, never in the worktree; the copy was
deleted afterwards). The unmutated copy passes all three tests.

| Mutant | Test | Result |
|---|---|---|
| M1: `isFirst && writes == writesBefore` → `isFirst` | `firstValueReadBeforeASave_isNotTheRow` | **Killed** 5 of 5 (`!modelChanged`) |
| M11: `writes += 1` removed | `firstValueReadBeforeASave_isNotTheRow` | **Killed** 5 of 5 |
| M4: `number == observationNumber` dropped from the per-value guard | `retiredObservationsValue_isNeverReceived` | **Killed** 5 of 5 (`shownIsB`) |
| M7: the failure leaves `hasWrittenOrFailed` false | `failureBeforeTheFreshRead_stillReadsTheRow` | **Killed** 10 of 10 runs of the whole FeatureSettingsTests (2 issues) |

### Decisions and deviations

1. **The draft is unchanged in substance.** The only edits are swiftformat's re-wrapping and the lint fixes:
   - `SegmentedChoiceTests`' `Option` moved to file scope (nesting).
   - `ModuleCopyTests`' `AppAbout.swift` exemption is one key per line.
   - `SettingsAccessibilityTests`' `@Test` is wrapped.
2. **R3-3 holds the retire handle instead of racing it.** Delivering a value between `finish()` and the cancellation
   depends on a pool task's timing, so a test that races it would kill M4 only sometimes. With the handle held, the
   window is the same and always open.
3. **Disk space.** The first targeted simulator run failed with "No space left on device". To continue, I deleted
   only regenerable build caches: my own scratch mutation copy, the `.build` folders of the finished scratch copies
   `scratchpad/mut3` and `scratchpad/g3r2` (their sources and logs are kept), and this worktree's host `.build`. The
   merged lanes' worktrees `F14-s1` (7.5 GB) and `F10-s7` (8 GB) still hold build products; I left them alone.
4. **The simulator was rebooted once.** After the disk filled, it refused to install the UI test runner ("Failed to
   acquire termination assertion"). A `simctl shutdown`, under the lock, cleared it.

### New user-facing wording

None. Every string S1b draws is one of S1a's 27 keys. `LedgerAppKit`'s catalog loses "Settings" (6 keys; it was
`AppCopy.settingsTitle`), which the title now takes from FeatureSettings' catalog.

### Sanctioned edits

| File | Edit | Why |
|---|---|---|
| `LedgerAppKit/AppCopy.swift`, its catalog, `AppCopyTests`, `AppCopyAdversarialTests` | `settingsTitle` removed; six strings | The placeholder goes (as in the draft) |
| `LedgerAppKitTests/ModuleCopyTests.swift` | 7 → 6 keys; `AppAbout.swift`'s four Info.plist keys exempted | N6 |
| `LedgerAppKit/AppTabs.swift`, `MainRoot.swift` | Settings' root and route, beside F13's History route | K1: each lane takes the other's lines |
| `Package.swift`, `PreviewScan.swift` | FeatureSettings added beside FeatureHistory | C4 |
| `LedgerDesignTests/DesignGalleryTests.swift` and its dark reference | `SegmentedChoice` in the component list; the reference re-recorded (235 px taller: the new section only, looked at) | A5 |
| `LedgerDesignTests/ComponentSnapshotTests.swift` | The `SegmentedChoice` references | A5 |
| `LedgerFakes/Support/ObservedState.swift` | `EndedFlag` moved above `ObservedState`'s doc comment | R3-4 |
| `FeatureSettingsTests/Adversarial/ScriptedSettingsAdversarialSupport.swift` | Values queue behind a held first value; accessors in an extension | R3-1 |

### Product lines per file

Measured the same way as S1a's table (non-blank, non-comment Swift lines in `LedgerKit/Sources` and `Apps`, with
`LedgerTestSupport`, UI tests and catalogs excluded), against `e10cbe0`.

| File | + | − |
|---|--:|--:|
| `LedgerDesign/Components/SegmentedChoice.swift` | 111 | |
| `FeatureSettings/Views/TrainingRows.swift` | 66 | |
| `FeatureSettings/Views/SettingsPage.swift` | 52 | |
| `FeatureSettings/Views/SettingsSection.swift` | 51 | |
| `FeatureSettings/Views/Settings+Previews.swift` | 50 | |
| `FeatureSettings/Views/WeekStartRow.swift` | 39 | |
| `FeatureSettings/SettingsRoot.swift` | 32 | |
| `FeatureSettings/Views/SettingsScreen.swift` | 13 | |
| `LedgerAppKit/AppAbout.swift` | 13 | |
| `LedgerAppKit/Routes+Settings.swift` | 11 | |
| `LedgerAppKit/AppTabs.swift` | 3 | 1 |
| `LedgerAppKit/AppCopy.swift` | | 3 |
| `LedgerAppKit/MainRoot.swift`, `LedgerDesign/Gallery/DesignGallery.swift` | 1 each | |
| `Package.swift` | 1 | 1 |
| `LedgerFakes/Support/ObservedState.swift` (R3-4: comments moved only) | 0 | 0 |
| **Total** | **444 added** | **5 removed (net 439)** |

Tests and UI tests: 33 files, +876 / −72 lines (raw).

### Runs

- **Host:** `swift build --build-tests` is clean, with no warnings in S1b's files. Suites:
  - FeatureSettingsTests: 54 tests, green;
  - LedgerAppKitTests: 335 tests, green;
  - LedgerDesignTests and the rendering suites: 183 tests, green with the one old known issue (`DeviceKeys`).
- **Lint and format:** swiftformat and swiftlint (strict) are clean on every changed file.
- **Simulator, targeted** (PR plan, `LedgerDesignTests`, `FeatureSettingsTests`, `LedgerAppKitTests`): everything
  passed except `designGallery_dark_matchesReference`, which recorded its missing reference, as intended. I then
  looked at:
  - the new gallery section, and ReceiptLayout below it, unchanged;
  - the Settings references the draft had not looked at: lb dark large, kg light large and lb light accessibility3;
  - the component references dark accessibility3 and light xLarge.
- **Nightly UI test:** `LedgerUITests/Settings/test_kilograms_chosenInSettings_reachToday` **passed** (14.8 s).
- **PR-sweep seconds** (the gate's `PR-iOS.xcresult`; the sum of each test case's duration): S1b's hosted suites take
  about **0.6 s** in all. That is Previews 0.07, accessibility 0.12, layout 0.06, the 8 snapshots 0.21, the root 0.07,
  `SegmentedChoice` and its references 0.07, and the routes 0.00. This is well under the plan's 6–9 s estimate. The
  whole of FeatureSettingsTests is 1.4 s.

### The gate

`scripts/check.sh` (full: iOS and watchOS), through the simulator lock, on `3571ecd`:
- **First run: exit 65, infrastructure.** About 12 minutes into the iOS tests, a FeatureProgramTests process crashed
  in `library_previews_noPillIsCut`. After that the simulator could not spawn processes ("Process spawn via launchd
  failed"), so every later bundle failed to launch. Nothing in FeatureProgram changed. This followed the full disk
  above.
- **Second run, on a freshly shut-down simulator: exit 0, "check.sh OK", 2,142 s.** Steps: format 1 s, lint 72 s,
  iOS build 23 s, string catalogs 2 s (8 catalogs; LedgerAppKit's has 6 keys), iOS boot 1 s, iOS tests 1,674 s,
  watchOS build 68 s, watchOS tests 298 s, coverage 3 s.
- Coverage: FeatureSettings 98.81 % (1,001 / 1,013) against 70 %; overall 98.58 %.

### Questions for Pete

Q1–Q7 are still open. S1b builds Q2 = A (the region's units and week start on a new install), Q4 = A (Apple Health
reads "Not connected" and does nothing) and Q7 = A ("Plate math" and "Watch haptic at zero" are shown now). Nothing
new arose in S1b.

### S1b fix round 1 (G1 implementer, 2026-10-29)

G2's findings (`a57d9cd`, "## S1b" in `test-findings.md`), both fixed:

- **F14-S1b-1 (a blank display name hides the bundle name).** `AppAbout(bundle:)` treats a value that is empty once
  trimmed (whitespace and newlines) as absent, for every key, before the `??` fallback. A blank
  `CFBundleDisplayName` now falls back to `CFBundleName`. `about_blankDisplayName_fallsBackToTheBundleName` ("",
  "   ", "\n") is now a plain test, without `withKnownIssue`.
- **F14-S1b-2 (a failed save isn't announced).**
  - `SettingsRoot`'s test initializer takes `announce`, with `ProgramRoot`'s default: it posts
    `AccessibilityNotification.Announcement`.
  - `.onChange(of: store.model?.problem)` announces the line when it becomes non-nil.
  - The store clears the line on the next change, so a second failure is announced again.
- G2's source scan is replaced by a behavioural `failedSave_isAnnounced`, without `withKnownIssue`. It injects
  `announce` into a hosted root, and checks that:
  - loading announces nothing;
  - the failed save announces "Couldn't save that change." once;
  - the next, successful save announces nothing more.
- The test's box, `HeardAnnouncements`, is `@Observable` at file scope, since `eventually` waits on observations. A
  local `@Observable` class can't take the macro's extension.

**Product lines:** +20 / −2, net 18 (`SettingsRoot` and `AppAbout`, non-blank, non-comment). Raw diff: product
+27 / −5, tests +27 / −19.

**Runs:**
- Host:
  - `swift build --build-tests` is clean;
  - FeatureSettingsTests: 54 tests, green;
  - LedgerAppKitTests: 341 tests, green, with no known issues;
  - swiftformat and swiftlint (strict) are clean on the four files.
- Simulator, through the lock (PR plan, FeatureSettingsTests and LedgerAppKitTests): 453 of 453 passed, with no
  expected failures.
  - The first run of the new test timed out, because its box wasn't observable, so `eventually` never woke.
  - The second run didn't compile: a local `@Observable` class.
  - Both were fixed in the test, and the third run is the one above.
- The full gate is left to the coordinator.

### S1b fix round 2 (G1 implementer, 2026-10-29)

G3's round 1 (`6b24503`, "## S1b round 1" in `review.md`): approved with minors. All four are fixed.

- **F14-S1b-R1-1 (nothing pins that Diagnostics reaches `MainRoot`'s sheet): a UI step, not a hosted test.**
  - **Why not hosted.** The coordinator preferred a hosted `AppTabs`/`MainRoot` test, and I tried one. It ran on
    `GateShell`, the real `MainRoot` and tabs over a database, pushed Settings on Today and looked for
    "Diagnostics" inside scroll views. The test read no element at all. "Diagnostics" sits inside Settings'
    `ScrollView`, and in a package test process a hosted SwiftUI scroll view hands UIKit no accessibility children
    (testing-strategy §2.6, measured in F08 S2 and recorded in `AccessibilityElements.swift`). Reaching the row
    hosted would need test-only seams in product code, so I reverted the attempt; no file of it remains.
  - **What landed.** G3's other option: one step in the nightly `Apps/LedgerUITests/Settings.swift`. After KG is
    chosen:
    1. it taps "Diagnostics";
    2. it expects the Debug menu (`debug.menu.diagnostics`) within 5 s;
    3. it swipes the sheet down, and expects the menu gone and Settings still there.

    The test then goes on to Today as before. It runs in 22.6 s, up from 14.8 s. The cost is that it runs nightly,
    not in the PR plan; Today's long press into the same sheet is in the same position (`DebugMenu`,
    `TabsAdversarial`).
  - **Kills,** in a scratchpad copy of the worktree (sources rsynced, its own derivedData), through the lock, with
    `-only-testing:LedgerUITests/Settings` on the Nightly plan:

    | Mutant | Result |
    |---|---|
    | H5: `MainRoot`'s `onSettingsRoute:` argument deleted | **Killed** at "Diagnostics raised the Debug menu" |
    | H6: `AppTabs` passes `{ _ in }` to `SettingsRoot` | **Killed** at "Diagnostics raised the Debug menu" |

    Before each mutant, `diff -r` of `Sources` against the worktree showed only that mutant. The copy, with its
    derivedData, was deleted afterwards.
- **F14-S1b-R1-2.** `SegmentedChoiceTests.options_sitInASemanticGroupNamedByTheLabel` walks up UIKit's tree from
  the "pounds" option, with a copy of G2's `parent(of:)` probe. It expects a container named "Units" whose type is
  a semantic group. The suite's doc comment no longer leaves this to the DoD's manual check.
  - **Kill:** V9 (`.accessibilityElement(children: .contain)` and `.accessibilityLabel(label)` removed), run in the
    same scratch copy on LedgerDesignTests in the simulator, is **killed** by this test alone inside LedgerDesign.
- **F14-S1b-R1-3.** `SettingsStore`'s doc comment now says that `SettingsRoot`, the screen over the store, makes
  one. The stale "S1b's; until then only the tests make one" is gone.
- **F14-S1b-R1-4.** R3-3's doc comment now says the test holds the window far wider than production can, and why.
  The old observation stays open across a whole second save and a fresh read; in the app, its cancellation lands a
  few main-actor jobs after `finish()`. The comment also gives the narrower order that is reachable: a late value
  just after the next observation's first value, with an outside write between. The guard still matters there, and
  the wide window makes the kill certain. The test itself is unchanged.

**Product lines:** −1 (`SettingsStore`'s comment only; no code changed).

**Runs:**
- **Host:**
  - `swift build --build-tests` is clean;
  - FeatureSettingsTests: 54 tests, green;
  - LedgerAppKitTests: 341 tests, green;
  - swiftformat and swiftlint (strict) are clean on the changed files.
- **Simulator, through the lock** (PR plan: LedgerAppKitTests, LedgerDesignTests and FeatureSettingsTests):
  `options_sitInASemanticGroupNamedByTheLabel` passed. The only failure was the hosted Diagnostics attempt described
  above, since reverted; the 6 expected failures are the known `DeviceKeys` issues. After the revert, LedgerAppKit's
  tests are as at `6b24503`.
- **Nightly UI test, through the lock:** `test_kilograms_chosenInSettings_reachToday` **passed** (22.6 s).
- The full gate is left to the coordinator.

## S2 — as built (G1 implementer, 2026-11-10)

Branch `feat/F14-s2-plates-export`, cut from `main` at `da6470d`. The contract is the brief's "### S2" (criteria 1's
program part, 3 and 5; N11–N18) with "Rulings before G1"; ruling A4 replaces N11's two writes (below).

**Pete's questions, decided by the orchestrator (2026-11-10):** Q1 = A (a switch rounds the program's loads to the new
unit's grid), Q4 = A (Apple Health reads "Not connected" and does nothing), Q5 = A (`workouts-YYYY-MM-DD.csv`, every
weight in the current unit with the unit in the column title, every set with a `done` column), Q6 = A (the bar with −
and +, plates on or off from a fixed list per unit, "Reset to standard", each unit its own), Q7 = A (the later
features' switches are shown now). Q2 and Q3 are as S1 and S3 build them.

### What landed

Paths under `LedgerKit/`.

- **Domain.**
  - `Rules/UnitSwitch.convert(_:to:equipment:)`: each explicit start load rounded to the nearest default step of its
    exercise's equipment in the new unit; each explicit step the same, never below one default step; `nil` stays
    `nil`. An exercise the map lacks moves on the finest grid (`Equipment.machine`'s: 1.25 kg, 2.5 lb). Idempotent.
  - `Export/CSVExport`: `header(units:)`, `lines(for:units:calendar:)`, `render(workouts:units:calendar:)` and
    `byteOrderMark` (N13–N15). Quoting and the formula guard work on Unicode scalars: "\r\n" is one `Character`, and a
    quote followed by a combining mark is one too.
  - `SettingsRepository.switchUnits(_:)` (ruling A4): the settings and the active program's converted weights, one
    write, both or neither. The program is converted only when the stored units differ from the new ones (or cannot
    be read): a conversion is idempotent but not neutral, so a load set on purpose between two grid steps in the unit
    it is in would otherwise be rounded.
- **Persistence.** `GRDBSettingsRepository.switchUnits` reads the stored units, upserts the row and calls
  `GRDBProgramRepository.convertActive(to:in:at:)` in the same `queue.write`. That reads the active program and every
  exercise's equipment (deleted ones too) and writes `ProgramRows` as `update` does: only the rows that changed.
- **Fakes and stubs.** `InMemorySettingsRepository(_:programs:)`; `InMemoryStores` links it to its programs. Its
  `switchUnits` checks the settings first, then converts (which may refuse, and then nothing is written), then stores
  the settings, which cannot fail. `InMemoryProgramRepository.convertActive(to:)`, `InMemoryExerciseRepository
  .equipment()`. `UnimplementedSettingsRepository.switchUnits` throws.
- **FeatureSettings.**
  - The store's saver calls `switchUnits` when the change's units differ from what is committed, else `save`. A failed
    switch sets `failedSwitch`: the line reads "Couldn't change the units. Nothing was changed." with "Try again",
    which sends `.setUnits` of the failed units again. Any other failed save keeps S1's line and has no retry.
  - "Bar and plates" (`Plates/`, `SettingsStore+Plates`, `Views/PlateInventorySheet`, `Views/DataRows`): the row
    reads "45 lb bar" and opens the sheet while Plate math is on; off, it is dimmed, without its chevron, and reads
    "Turn on Plate math to edit". The sheet edits a `PlatesDraft` of the current unit's inventory; "Done" saves the
    draft into that unit's inventory through N1's pipeline; "Cancel" or a swipe drops it; "Reset to standard" puts back
    `PlateInventory.standard(units)`. The bar is a `StepperField` (0–100 lb by 2.5, 0–45 kg by 1.25; a bar off the grid
    steps to the multiples beside it). The plates are a `FilterChipRow` with `allowsMany` over the unit's fixed list,
    with any stored size off the list shown among them. With every plate off the sheet says "No plates: no plate line
    will show".
  - "Export data · CSV" (`Export/`, `SettingsStore+Export`): a `ShareLink` over `WorkoutExport`, a `Transferable`
    whose `FileRepresentation(exportedContentType: .commaSeparatedText)` writes the file when the lifter picks a
    destination (A2). The writer reads `workouts(in: .distantPast ..< .distantFuture)` and streams BOM, header and each
    workout's lines, oldest first, to a `FileHandle` in `temporaryDirectory/Export/`, emptied first. The store's run
    empties the directory when it ends (Settings goes away). A failure is logged and thrown to the system's sheet.
    The workouts' dependency is read only when the file is written (`Dependency(\.workoutRepository)` kept whole), so
    drawing Settings needs no workout store.
  - Copy: 17 keys (44 in all). Previews: "Couldn't switch" (Settings) and three of the sheet.
- **UI test (nightly).** `Apps/LedgerUITests/SettingsExport.swift`: gear, "Export data, CSV", the activity list
  appears.

### Decisions and deviations

1. **Ruling A4 over N11.** One call, `SettingsRepository.switchUnits(_:)`, a protocol requirement beside `save` (as
   S1's `seedIfAbsent`), not a new protocol and dependency key: it is one call on the settings' own repository, and
   GRDB's settings and programs share one queue. N11's wording is reworked: a failed switch leaves both as they were
   and shows "Couldn't change the units. Nothing was changed." with "Try again".
2. **The brief's 135 lb example is wrong.** 135 lb is 61.23 kg, nearest 60 on a 2.5 kg grid, not 62.5. 180 lb is 82.5 kg.
   The drift pinned by `UnitSwitchTests` is 135 lb → 60 kg → 130 lb (R6: one step), and 45 lb → 20 kg → 45 lb.
3. **Weights in the CSV are rounded to hundredths** (N13's "rounded to hundredths"; Q1's "102.06 kg"), not to
   `formatted(in:)`'s one decimal for a converted value.
4. **The plates' chips are switches to VoiceOver** (`FilterChipRow` with `allowsMany`): on or off as their value. The
   hosted reader does not report them as selected, so the tree pins the value only.
5. **The export's directory name is exempted** in `ModuleCopyTests` (`"Export"` in `Export/ExportFile.swift`): a path,
   never drawn. The file's name is copy (`"workouts-%@.csv"`).
6. **N17's memory figure** is the process footprint after the write against before it, not a peak: the streamed write
   leaves no large buffer behind, and a true peak needs a sampler. The test is nightly; on the Mac host it wrote
   10,000 sets in 0.165 s.
7. **Export row at accessibility sizes** keeps its chevron beside the label (the row is a `ShareLink`'s label, not a
   `HairlineRow`); the references were looked at.

### New user-facing wording

"Couldn't change the units. Nothing was changed." · "Try again" · "Bar and plates" · "%@ bar" ("45 lb bar") · "Turn on
Plate math to edit" · "%@ lb", "%@ kg" · "Bar" · "Plates you own" · "No plates: no plate line will show" · "Reset to
standard" · "Done" · "Cancel" · "Export data · CSV", spoken "Export data, CSV" · "Every set you logged, in your current
units" · "workouts-%@.csv". The DATA heading's translator comment now names the export.

### Sanctioned edits

| File | Edit | Why |
|---|---|---|
| Eleven `SettingsRepository` doubles (`OnboardingAdversarialStores`, `StoreDoubles`, `LibraryStoreTests`, `ProgramStoreScene`, `TodayStoreAdversarialSupport`, `HistoryStoreTests`, `WorkoutDetailAdversarialSupport`, `ProtocolsAdversarialTests`, `StartWorkoutUseCaseAdversarialSupport`, `AppRootGateAdversarialProbes`, `ScriptedSettings`) | One `switchUnits` each, as its `seedIfAbsent` (`ScriptedSettings` scripts it as a save) | A4: a protocol requirement |
| `FeatureSettingsTests/Support/SettingsTesting.swift` | `WatchedSettings` records switches; `SettingsScene` takes a seed, binds the workouts and an export directory of its own; `TestLane`, `.performance` | S2 |
| `SettingsSaveQueueAdversarialTests` (F14-S1-1's test) | The failed save there is a switch of units, so its line is now the switch's | A4 |
| `SettingsSavePropertyAdversarialTests` | The oracle's switch lists the sheet's actions | S2 actions |
| `SettingsScreenAdversarialSupport`, `SettingsScreenAdversarialTests` | The model takes S2's rows (in English); 14 → 16 stops; the Arabic order gains the two rows | S2 rows |
| `SettingsAccessibilityTests`, `PreviewTests`, `SettingsCopyTests`, `FeatureSettingsSourceTests` | The trees gain the plates row, the export and Try again; 7 → 9 targets (10 with Try again); the plates previews; 27 → 44 keys; the sheet's scroll view | S2 |
| `LedgerAppKitTests/ModuleCopyTests.swift` | FeatureSettings' exemption: `"Export"` | Decision 5 |
| `SettingsSnapshotTests`' 8 references | Re-recorded: the two new rows (kilograms: Bar and plates off) | S2 rows |

### Tests added

- Domain: `UnitSwitchTests` (8, the idempotence property over `PropertySeed.all`), `CSVExportTests` (9, the RFC 4180
  round trip over `PropertySeed.all` with emoji, Arabic, Hebrew, RLM, combining marks, CR/LF and formula starts).
  `LedgerTestSupport/Export/CSVReader` is the RFC 4180 reader.
- Persistence: `SwitchUnitsTests` on GRDB and the linked in-memory stores (converts, same units convert nothing, no
  program, an unreadable program rolls the settings back, one commit).
- FeatureSettings: `SettingsUnitsStoreTests` (5), `SettingsPlatesExportStoreTests` (6: edit and save, the other unit
  untouched, cancel and reset, off while Plate math is off, the export's bytes equal BOM + `render` over a two-week
  history oldest first with a stale file cleared, the directory emptied when the run ends, kilograms),
  `PlatesPresentationTests` (4), `PlateInventorySheetTests` (hosted: the exact tree per state and size, each control's
  action, layout) and its 6 references (looked at), `ExportPerformanceTests` (nightly).

### Product lines

Non-blank, non-comment Swift in `LedgerKit/Sources` and `Apps`, `LedgerTestSupport`, UI tests and catalogs excluded,
against `da6470d`: **754 added, 28 removed, net 726** (plan: about 710). The largest: `SettingsCopy+Plates` 89, the
sheet 71, `PlatesPresentation` 70, `CSVExport` 50, `ExportFile` 46.

### Runs

- Host: `swift build --build-tests` clean; FeatureSettingsTests (71, with the nightly lane's performance test), the
  domain, persistence (settings, programs, contracts, switch) and `ModuleCopyTests` suites green.
- Simulator, through the lock: FeatureSettingsTests (94 tests), `CSVExportTests`, `UnitSwitchTests`,
  `SwitchUnitsTests`, `ModuleCopyTests` green with recording off.
- swiftformat and swiftlint (strict) clean.
- The nightly UI test `SettingsExport` was not run in this lane.

### The gate

`scripts/check.sh` (full: iOS and watchOS), through the simulator lock, on `a472372`: **exit 0, "check.sh OK"**,
2,106 s. Steps: lint 82 s, iOS build 25 s, string catalogs 1 s, iOS tests 1,638 s, watchOS build 46 s, watchOS tests
311 s, coverage 1 s. Coverage: FeatureSettings 96.97 % (1,569 / 1,618) against 70 %; LedgerDomain 99.34 %; overall
98.49 %. This notes commit follows it and changes docs only.

### S2 fix round 1 (G1, 2026-11-10)

Against G2 round 1 (`4ae944b`, "## S2 — G2 round 1" in `test-findings.md`) and the orchestrator's rulings.

- **F14-S2-G2-1 (fixed).** `PlatesDraft.opened` keeps the sizes the sheet opened with (set at `.editPlates` from the
  stored inventory); `PlatesPresentation.sheet` lists the unit's sizes ∪ `opened` ∪ the draft's plates. An off-list
  size switched off stays listed, off, for the whole sheet session, so it can be switched on again without Cancel.
  The list no longer changes within a session, so the chips' ids (their places) stay stable. G2's
  `offListSize_switchedOff_staysListed` passes with only its known-issue marker removed.
- **F14-S2-G2-2 (ruled: keep the code).** N11.3 in the brief now reads "Couldn't change the units. Nothing was
  changed."; G2's `failedSwitch_lineMatchesTheContract` expects that line, without its marker.
- **F14-S2-G2-3 (docs).** The brief's criterion 1, its `UnitSwitchTests` line and Q1 say 135 lb → 60 kg → 130 lb.

Product lines: +5 / −1 (net 730 for the slice).

### S2 fix round 1, the gate

`scripts/check.sh` (full), through the lock, on `ddd11bf`: **exit 0**, 2,330 s. FeatureSettings 96.97 % (1,572 / 1,621).

### S2 fix round 2 (G1, 2026-11-10)

Against G3 round 1 (`f1c2718`, "## S2 — G3 round 1" in `review.md`) and the orchestrator's rulings.

- **S1 (fixed).** `SettingsRepositoryContract` gains three clauses, run on GRDB and the in-memory store: a switch
  saves and is observed; a switch to the stored units is a save; a switch refuses what `save` refuses (a NaN bar) and
  writes nothing. The conversion stays `SwitchUnitsTests`' (it needs a program store).
- **S2 (fixed).** `ExportWriter`, an actor the store keeps, runs every write and the emptying of the directory when
  Settings goes away, one at a time, so two exports never empty the directory under each other. G2's
  `export_twoAtOnce` is deterministic by construction. The write also checks for cancellation between workouts
  (standards §4).
- **S3 (fixed).** The plates sheet is `.sheet(item:)` over `PlatesModel` (now `Identifiable` by its units), so it
  keeps its last content while it goes down. No reference changed.
- **S4 (ruled: every program).** `switchUnits` converts every live program, active or not, in its one write
  (`GRDBProgramRepository.convertLive`, `InMemoryProgramRepository.convertLive`); which program is active is left as
  it is. The brief's criterion 1 and N11 are amended. G2's `inactiveProgram_untouched` became
  `inactiveProgram_convertedToo` (both programs converted), and `refusedSecondProgram_rollsBackEverything` refuses
  the second program's slot writes with a trigger: the settings row and both programs stay byte for byte. A program
  that cannot be read now fails the whole switch, the inactive ones included; the line and "Try again" say so.
- **Coverage.** `SettingsReviewFixTests.export_failedRead_throwsAndWritesNothing` (the store's export over a
  workouts store whose read fails: it throws, and no file is left) and `unavailableExport_throws`; the hosted
  `PlateInventorySheetChromeTests` (the chrome's title and Cancel; "Bar and plates" sends `editPlates`). The log
  line itself is not asserted in the PR lane: reading the process's log back is the nightly pattern
  (`OnboardingStoreLoggingTests`). What stays uncovered is system-only: `WorkoutExport.transferRepresentation`'s
  closure (only the system's share sheet calls it; the nightly UI test runs outside coverage), `ExportFile.write`'s
  `createFile` failure and its close-on-error branch, `clearExports`' catch, and the sheet's swipe-down setter in
  `SettingsScreen` (a presented sheet, outside the hosted reader).
- **Nits.**
  - N1: the brief's N17 is amended (a smoke figure: the footprint retained after the write); the time is the median
    of 5 runs after a warm-up.
  - N2: the export's doc says a workout this version cannot read is left out and logged, as History does.
  - N3: the file is named for the day it is written (`ExportRequest.plan()` in the write); the share sheet's preview
    title is the redraw's.
  - N4: `switchUnits` rethrows a `DatabaseError` from its read of the stored units; only an unreadable payload
    converts.
  - N5: the fake's switch compares, converts and stores under the settings' lock, in one step.
  - N6: a failed switch closes a plates sheet opened in the units it put back; "Try again" for units already shown
    clears the line and saves nothing. Both tested.
  - N7: `render` uses `reduce(into:)`.
  - N8: the chrome is tested hosted; the presentation itself (`SettingsScreen`'s sheet) is not, as the hosted reader
    cannot see a presented sheet. **Skipped in part, for that reason.**
- **For the chrome's test**, the sheet's frame is `PlatesChrome` (title, Cancel, page, foot); the sheet puts its page in
  a scroll view inside it, and the test reads the frame around the page alone.

Product lines for the slice after both rounds (against `da6470d`): 830 added, 31 removed, **net 799**. This round:
+76 / −3, mostly `ExportWriter` and `ExportRequest`, `convertLive`, `PlatesChrome` and the failure helper.

Simulator, through the lock: FeatureSettingsTests (128) and the switch suites green with recording off; no reference
changed.

### S2 fix round 2, the gate

`scripts/check.sh` (full), through the lock, on `81eef98`: **exit 0**, 2,010 s. FeatureSettings 98.01 % (1,630 / 1,663);
overall 98.54 %.

### S2 fix round 3 (G1, 2026-11-11)

- **Ruled: an unreadable program never fails a switch.** `GRDBProgramRepository.convertLive` reads each live program
  in a `do`; a program this app cannot read (a malformed id, a damaged column, a slot or program its `init`s refuse)
  is logged under "persistence" and left as it is, F05's rule for an unreadable row, and every readable program is
  converted and the settings saved in the same transaction. A `DatabaseError` on the read, or any failure of a write,
  still fails the whole switch. The in-memory store holds programs as values, so it has no unreadable one.
- **Tests.** `SwitchUnitsTests.unreadableProgram_isSkipped` replaces `unreadableProgram_rollsBackTheSettings`: the
  damaged seed program's slots keep every byte and the settings switch. `SwitchUnitsAdversarialTests
  .unreadableProgram_skipped_readableConverted`: one unreadable and one readable program; the switch succeeds, the
  readable converts, the unreadable one's slot rows are unchanged. G2's trigger tests (a refused write) still roll
  everything back.
- **The brief:** criterion 1 and N11.3 say so.
- **Coverage, accepted at 98.01 % (orchestrator, 2026-11-11).** What stays uncovered is reachable only by the
  system: `WorkoutExport.transferRepresentation`'s closure (only the system's share sheet calls it, and the nightly UI
  test runs outside coverage); `ExportFile.write`'s `createFile` failure and its close-on-error branch;
  `clearExports`' catch (a temporary directory the app cannot remove); and `SettingsScreen`'s sheet binding setter
  (a sheet swiped away, which the hosted reader cannot present).

## S3 — as built (G1 implementer, 2026-11-11)

Branch `feat/F14-s3-delete-all`, cut from `main` at `8d462a2` (S2 is #88). The contract is the brief's "### S3: Delete
all data" (criterion 6 as restated per C22–C26; N19–N24) with "Rulings before G1" (A1).

**Pete's question 3, decided by the orchestrator (2026-11-10/11): A for both parts.** Confirming is a warning, then
typing DELETE (the localized word, compared ignoring case and the spaces around it). While a workout is in progress
"Delete all data" is unavailable: the lifter finishes or discards it first. What goes: every workout and set, the
records, the programs, the custom exercises, the settings (back to a new install's) and any exported files on the
phone. What stays: the built-in exercise list (seeded afresh) and the workouts already in Apple Health, which the
lifter deletes in the Health app. The warning says all of it.

### What landed

Paths under `LedgerKit/`.

- **Domain.** `Protocols/DataReset.swift`: `eraseAll(restoring settings: Settings) async throws`, its contract in its
  doc (all or nothing; the catalog read first; `device` kept; Apple Health untouched).
- **Persistence.**
  - `Repositories/GRDBDataReset.swift`. The catalog is read and the settings encoded before the write opens (N20).
    One `queue.write` then empties `erasedTables`, every table but `device`, children before parents (`slot_miss`,
    `slot`, `day_template`, `program_week`, `program`, `logged_set`, `personal_record`, `workout_health`,
    `workout_exercise`, `workout`, `workout_event`, `exercise`, `settings`), seeds the catalog with the launch's own
    seed and writes the settings row. After the commit, `vacuum()` and `checkpoint(.truncate)` run on the queue,
    best-effort: a failure is logged under "persistence", a cancellation is not (N21).
  - `GRDBExerciseRepository.seedIfNeeded` is now `catalogRecords(_:)` and `seed(_:version:at:in:)`, which the erase
    calls inside its transaction (the plan's "seeding moved into a `Database`-level function").
  - `GRDBSettingsRepository.replace(payload:updatedAt:in:)`: `save`'s upsert inside the caller's write.
  - `LedgerStores.reset`.
- **Fakes.** `InMemoryDataReset` over `InMemoryStores` (`InMemoryStores.reset`), with a `reset` on the exercise,
  program, workout, event and settings stores. It checks everything that can refuse first (the catalog read, the
  settings round-tripped through `SettingsCodec`, each catalog entry at the exercise store's boundary in its own reset,
  which runs first), then resets the others, which cannot fail. Unlike the database it resets them one after another.
- **Dependencies.** The `dataReset` key: `UnimplementedDataReset` as its live value, an `InMemoryDataReset` over
  stores of its own as its preview value. `withTestDependencies`' `inMemoryStores(seed:)` binds it too.
- **LedgerAppKit.** `AppComposition.bind` binds `dataReset` to `stores.reset`. No route: the gate already shows
  onboarding when the active program goes (C23).
- **FeatureSettings.**
  - `DeleteAll/DeleteAllModel.swift` (`DeleteAllDraft`: warning or typing, the text, erasing, failed; the row, warning
    and sheet models) and `DeleteAllPresentation.swift` (the row, the warning, the sheet, `matches(_:locale:)`).
  - `SettingsStore+DeleteAll.swift`. The row opens the warning; "Continue" opens the sheet; "Delete everything" acts
    only while the word matches and no erase runs, and marks the eraser, a third child of `run()`'s group beside the
    saver and the follower. The erase asks the session once more (`current()`), then calls
    `eraseAll(restoring: Settings.regional(locale:calendar:))` with the injected locale and calendar, then empties the
    export's directory through the S2 writer (N22). A failure keeps the sheet with "Nothing was deleted. Try again.";
    a cancellation reports nothing and lets the button act again. A fourth child follows `workoutSession.updates()`:
    while a workout is live the row is off, and a warning or sheet not yet erasing is closed (N19).
  - Views: `DeleteAllRow` in `DataRows.swift` (under Export), the system's alert and `DeleteAllSheet` on
    `SettingsScreen`. The sheet is `SheetChrome` + a scrolling `DeleteAllPage` + a pinned `DeleteAllFoot`, as the
    plates sheet is. The field takes capitals and no autocorrection; while the erase runs it is disabled and the sheet
    cannot be swiped away.
  - Copy: `SettingsCopy+DeleteAll.swift`, 13 keys (57 in all). "Cancel"'s comment now names Delete all data too.
  - Previews: `DeleteAll+Previews.swift` (empty, typed, failed). The "Kilograms" Settings preview now has a workout in
    progress, so the row's off state is drawn.
- **Nightly UI test.** `Apps/LedgerUITests/SettingsDeleteAll.swift`: gear, Delete all data, Continue, DELETE, Delete
  everything, onboarding, Skip setup, Today.
- **Docs.** `architecture.md` §7 gains the erase's paragraph, §13 the `dataReset` key.

### Decisions and deviations

1. **The settings restored are `Settings.regional` of the store's injected locale and calendar.** In the app those
   are the device's (`Locale.autoupdatingCurrent`, `Calendar.autoupdatingCurrent`, the dependencies' live values),
   which is exactly what S1a seeds a new install with. The one difference: under `-LEDGER_UITEST`, S1a seeds a US
   iPhone's settings whatever the simulator's region (`UITestRegion`), and the erase restores the simulator's region's.
   Plumbing the composition's `regionalSettings` to `SettingsRoot` for that one case was not worth a second source.
2. **N20's "duplicate id" failure is not reachable.** The catalog seed keeps the last entry of a repeated id (F03,
   decision #24), so a duplicate never throws. The tests make the erase fail instead with a catalog entry whose start
   load no column keeps exactly (`inexactWeight`, inside the transaction, after every delete), with a catalog that
   cannot be read (before it), with settings that cannot be encoded, and, on GRDB, with a trigger that refuses a
   statement midway through the deletes, the catalog's seed, or the settings row: every row count is unchanged.
3. **Order on the disk: `VACUUM`, then the `TRUNCATE` checkpoint.** `VACUUM` rewrites every page through the WAL;
   the checkpoint copies them into the file and truncates the `-wal`, which also drops the older frames that held the
   deleted rows. Without the compaction `erase_leavesNoTraceOnDisk` fails on the WAL (checked: the mutant below).
4. **No VoiceOver label on the sheet's field beyond SwiftUI's.** The field's label is "Type DELETE to confirm" and its
   placeholder "DELETE"; the visible label above it is hidden from VoiceOver so it is not read twice.
5. **The alert's binding ignores the system's dismissal.** Its two buttons send `cancelDeleteAll` and
   `continueDeleteAll`; the alert goes when the model has no warning. A setter that sent Cancel could cancel the sheet
   "Continue" had just opened, depending on the order SwiftUI runs them in.
6. **`DataResetContract` seeds through the protocols** (both stores hold the same history) and runs on GRDB and the
   linked in-memory stores in `LedgerPersistenceTests/DataResetTests`, as `SwitchUnitsTests` runs both.

### New user-facing wording

"Delete all data" · "Finish or discard your workout first" · "Delete all data?" · "This deletes every workout and
set, your records, your programs and your custom exercises." · "Any exported files on this iPhone go too, and your
settings go back to how they started." · "The built-in exercise list is restored." · "Workouts already saved to Apple Health stay
there: delete them in the Health app." · "Continue" · "This can't be undone." · "DELETE" · "Type %@ to confirm" ·
"Delete everything" · "Nothing was deleted. Try again." Only "Delete all data?", "Continue", the typed word and the
failure line are the brief's; the rest are new.

### Sanctioned edits

| File | Edit | Why |
|---|---|---|
| `FeatureSettingsTests/Support/SettingsTesting.swift` | `SettingsScene` binds `workoutSession` (a `FakeWorkoutSessionClient` by default) and `dataReset` (its stores', or what `reset` makes of them) | N19: the store follows the session |
| `ScriptedSettingsAdversarialSupport`, `SettingsReachAdversarialTests` | Bind a `FakeWorkoutSessionClient` | N19 |
| `SettingsSavePropertyAdversarialTests` | The oracle's switch lists S3's actions | S3 actions |
| `SettingsScreenAdversarialSupport`, `SettingsScreenAdversarialTests` | The model takes S3's three members; 16 → 17 stops; the Arabic order gains the row; the switches' mapping moved to a helper (function length) | S3 row |
| `SettingsAccessibilityTests` | The tree gains the row (dimmed in "Kilograms"); 9 → 10 targets (11 with Try again) | S3 row |
| `PreviewTests`, `SettingsCopyTests`, `FeatureSettingsSourceTests` | The sheet's previews; 44 → 57 keys and lookups; the sheet's scroll view | S3 |
| `SettingsSnapshotTests`' 8 references | Re-recorded: the new row (its line under it in kilograms; looked at) | S3 row |
| `LedgerDependenciesTests`: `DependencyKeysTests`, `UnimplementedStubTests`, `PreviewValueTests` | The `dataReset` key's test value, stub and preview value | A1 |

### Tests added

- Contract: `LedgerTestSupport/Persistence/DataResetContract` (+`Contents`), 5 clauses: the erase leaves the bundled
  catalog, the given settings and nothing else (the custom exercise, the live log, the deleted workout gone); every id
  is free again; observations open across the erase hear nil, `[]` and the restored settings; a second erase is
  harmless; an unreadable catalog, a refused catalog entry and unsavable settings erase nothing.
- Persistence, `DataResetTests` (+`Disk`): the contract on GRDB and the linked in-memory stores; the erased list is
  every table of the schema but `device` (a new table must join it); row counts after the erase (health values,
  records, soft-deleted rows gone; `device` and its id kept); a trigger refusing a statement midway through the
  deletes, at the catalog's seed and at the settings row leaves every count and every read as before (N20); a task
  cancelled at once leaves all or nothing (N23); the names of a custom exercise and a workout are in neither the file
  nor its `-wal` after the erase, and the reopened file keeps the device and the restored settings (N21).
- FeatureSettings: `DeleteAllPresentationTests` (the row, the warning's exact text, the sheet at each step, the word's
  rule over 14 inputs), `DeleteAllStoreTests` (Cancel at each step, the word table, the erase once with the region's
  settings and the export directory removed, a second tap and the field and Cancel ignored while it runs, a failure
  keeping the sheet then a retry, a cancellation), `DeleteAllLiveWorkoutTests` (N19: the row off while a workout is
  live and back when it ends, a workout started with the sheet up closes it, one found only by the erase's own check
  deletes nothing), `DeleteAllSheetTests` (hosted: the exact tree per state and size, the one `UITextField` with its
  placeholder and text, each control's action, the row's tap, layout) and 8 references in
  `__Snapshots__/DeleteAllSheetTests/` (empty and failed at `.large`, typed at `.large` and `.accessibility3`, light
  and dark; looked at).
- LedgerAppKit, `DeleteAllGateTests`: a real composition on a temporary file, Settings' own store erasing through the
  bound keys; the gate turns to onboarding, the stores hold the catalog and the region's settings, the device id is
  kept, and Skip setup brings the tabs back with no history.
- Nightly UI, `SettingsDeleteAll`: **passed** (19.3 s) through the lock, so the alert's "Continue" hands over to the
  sheet on the simulator.

**Mutant:** `GRDBDataReset` without `compact()` fails `erase_leavesNoTraceOnDisk` on the WAL (2 issues); restored.

**Not covered, system-only:** `SettingsScreen`'s alert and delete sheet closures and binding setter (a presented alert
or sheet, which the hosted reader cannot reach; the nightly UI test drives them), the field's binding setter (a hosted
`UITextField` does not hand programmatic text to SwiftUI: I tried `insertText`, then `text` with `editingChanged` and
the notification), and `GRDBDataReset.compact`'s catch.

### Product lines

Non-blank, non-comment Swift in `LedgerKit/Sources` and `Apps`, `LedgerTestSupport`, UI tests and catalogs excluded,
against `8d462a2`: **649 added, 16 removed, net 633** (plan: about 540). The largest: `DeleteAllSheet` 120,
`SettingsCopy+DeleteAll` 96 (13 lookups), `SettingsStore+DeleteAll` 85, `GRDBDataReset` 51. The 500-line target is
passed; S3 was planned as its own PR so the data-loss change has its own review, and no smaller seam remains.

### Runs

- Host: `swift build --build-tests` clean; FeatureSettings, persistence (the contracts, `DataResetTests`), dependencies
  and AppKit (`DeleteAllGateTests`, the reach suites) green.
- Simulator, through the lock: FeatureSettingsTests (151), `DataResetTests`, `ModuleCopyTests`, `DeleteAllGateTests`,
  LedgerDependenciesTests green after the references were recorded; the nightly `SettingsDeleteAll` passed.

### The gate

`scripts/check.sh` (full), through the lock, on `816928c`: **exit 0, "check.sh OK"**, 2,041 s (lint 68, iOS build 14,
string catalogs 1, iOS tests 1,605, watchOS build 45, watchOS tests 304, coverage 2). Coverage: FeatureSettings 96.98 %
(2,089 / 2,154; S2 left it at 98.01 %: the gap is the system-only lines above), LedgerPersistence 99.06 %,
LedgerFakes 99.07 %, LedgerDependencies 96.62 %, LedgerDomain 99.36 %, overall 98.44 %. The commit after it adds
`row_opensTheWarning` and these notes; its gate is below.

`scripts/check.sh` (full), through the lock, on `8c8033d`: **exit 0, "check.sh OK"**, 2,022 s. FeatureSettings 97.16 %
(2,093 / 2,154), overall 98.45 %. The commit after it records this paragraph and changes docs only.

### S3 fix round 1 (G1, 2026-11-11)

Against G2's round (`dc13af9`: `DataResetAdversarialTests`, `DeleteAllAdversarialTests`,
`DeleteAllSheetAdversarialTests`) and the orchestrator's rulings. None of G2's tests was edited.

- **F14-S3-G2-1 (ruled Blocking): the compaction died with the caller's task.** In the app the erase's commit empties
  the active program, the gate turns to onboarding and SwiftUI cancels `SettingsRoot`'s task, which runs the erase.
  GRDB then skipped or interrupted `VACUUM` and the checkpoint, `compact()` swallowed the `CancellationError`, and the
  deleted names stayed in the `-wal`: `cancelledAfterCommit_stillLeavesNoTraceOnDisk` failed.
  - **Fix:** `GRDBDataReset.eraseAll` runs `compact()` in an unstructured `Task` of its own and awaits its value. A
    `Task { }` does not inherit its creator's cancellation, so once the transaction has committed nothing the caller
    does can cut the compaction short; the call still returns only when the disk is clean. I chose this over handing
    the compaction to a long-lived owner in Persistence (an actor or the launch): the erase stays one call that ends
    with the disk clean, the caller still waits for it, and nothing outlives it. It is not fire-and-forget: it is
    awaited, and it is Persistence's, not a store's (standards §4).
  - The `CancellationError` branch is gone: the compaction's task is never cancelled, so any error is SQLite's or the
    file system's and is logged at error level. The wrong comment ("the next erase, or SQLite's own checkpoints,
    reclaim the pages") went with it; the catch's comment now says what such a failure leaves.
  - The erase still reports success once committed, as the protocol says; compaction can now end early only through
    a real I/O failure, which is logged.
- **Robustness: Delete everything with no run.** `.confirmDeleteAll` while no `run()` is active (`eraseMark` nil) now
  does nothing, so `isErasing` never sticks. New test: `DeleteAllStoreTests.confirmWithoutARun_erasesNothing` (nothing
  asked for, the button not stuck, then a run and a tap erase once).
- **Copy:** "The built-in exercises stay." is now **"The built-in exercise list is restored."** (it is reseeded). The
  catalog key and comment follow; `DeleteAllPresentationTests` expects the new sentence.

**Input for F19 (watch sync).** "Delete all data" erases the phone's database only. The watch keeps its cached
program, settings and any workouts it has not yet sent; F19 must carry the erase to the watch (push an empty context
and drop its queued envelopes, and refuse an erase while either device reports a live workout, K7), or the next sync
brings deleted workouts and the old program back. F28 has the same duty for iCloud (K6).

**Product lines this round:** +11 / −9, net +2 (non-blank, non-comment, against `dc13af9`): `GRDBDataReset`, `SettingsStore+DeleteAll` and the copy line. The
slice is now net 635.

**The gate (fix round 1):** `scripts/check.sh` (full), through the lock, on `abcd33d`: **exit 0, "check.sh OK"**,
2,060 s (log `scratchpad/f14-s3-fix1-gate.log`). FeatureSettings 97.21 % (2,096 / 2,156), LedgerPersistence 99.09 %,
overall 98.46 %. G2's `cancelledAfterCommit_stillLeavesNoTraceOnDisk` passes unedited. This notes commit follows it
and changes docs only.
