# F20 — Device sync test protocol & M2 acceptance

| | |
|---|---|
| Milestone | M2 |
| Status | ready |
| Depends on | F16, F17, F18, F19 |
| Branch | `feat/F20-device-test-protocol` |
| Design refs | `design/prototype/LedgerWatch.dc.html` → screen labels: all six; `design/prototype/Ledger.dc.html` → `Active workout`, `Today`, `Session receipt` |
| Spec refs | `docs/product-spec.md` §5.3; ADR-005 (Consequences: "Real-device testing is mandatory"); `tasks/todo.md` M2 exit; R1 §2.3, §2.5, §6 #1 |

## Goal
After this ships, M2 has an executable, repeatable manual protocol on a physical iPhone + Apple Watch whose pass/fail result is the M2 exit gate: "start on either device, log on both, disconnect mid-workout, reconnect, finish on either → one workout in history with HR, saved to Health." Results are committed per run so regressions on new OS builds are visible.

## User stories
- As the release owner, I can hand the protocol to anyone with the two devices and get a comparable results file back.
- As an implementer of F16–F19, I know exactly which behaviours only a device can prove.

## Scope
**In:** the scripted protocol (this file), a results template, a debug-only Diagnostics screen hook (architecture §14) exposing what the protocol reads, and a list of what becomes automatable later.
**Out (explicitly):** `docs/testing-strategy.md` (referenced by ADR-005 and README but not present in the repo — this brief is the device checklist of record until it exists); automation of these scenarios (nightly XCUITest cannot pair devices).

## Touches
- `tasks/features/F20-device-test-protocol.md` (this)
- `tasks/features/F20-device-test-protocol/results-YYYY-MM-DD.md` (template; copy per run)
- `LedgerKit/Sources/FeatureSettings/Diagnostics/DiagnosticsScreen.swift` (`#if DEBUG`: connection state, highest seq per device, event-log size, HealthKit auth, last handshake time, mirroring degraded flag)
- `LedgerKit/Sources/LedgerDomain/Diagnostics.swift` (`DiagnosticsSnapshot` value type + `WorkoutSessionClient.diagnostics` — additive)
- `tasks/todo.md` (M2 exit line links the latest results file)

## Domain changes
`DiagnosticsSnapshot { connection: LiveConnectionState, highestSeq: [DeviceID: UInt64], eventLogCount: Int, healthAuthorization: HealthAuthorization, lastHandshakeAt: Date?, mirroringDegraded: Bool }` — read-only; no persistence.

## Protocol
Preconditions: iPhone (iOS 26.x, note exact build) + paired Apple Watch (watchOS 26.x), both on a TestFlight or local Debug build of the same commit; Ledger onboarded with the seed program; HealthKit authorised; Diagnostics screen enabled on both. Reset between scenarios: finish or discard any live workout; confirm Diagnostics shows `eventLogCount == 0`.

| # | Scenario | Steps | Expected (ADR-005 / F16–F19 criteria) |
|---|---|---|---|
| 1 | Start from phone | Phone: Today → Start. | Watch opens to set-ready within 10 s (F16 #8); one `WorkoutID` on both (F17 #8); phone header "Connected". |
| 2 | Start from wrist | Watch: idle → Start (phone in pocket, unlocked). | Phone app launched in background; Today shows "Resume" within 10 s (F16 #7); HR on watch within 5 s (F16 #4). |
| 3 | Log alternately | Log set 1 on watch, set 2 on phone, crown +5 on watch, reps −1 on phone, +30s on phone, skip on watch. | Every change appears on the other device < 1 s (F17 #13); rest rings agree to the second; Diagnostics seq vectors equal after each step. |
| 4 | Phone in bag 10 min | Lock phone, put it 10 m away. Log 6 sets on the watch over 10 min. Return. | Watch line "iPhone not connected — logging continues" (F17 #12); on return the phone shows all 6 sets within 5 s of reconnect (F17 #7); one handshake in Diagnostics. |
| 5 | Bluetooth off mid-workout | Log 2 sets both sides; turn Bluetooth off on the phone; log 2 on watch, 1 on phone; Bluetooth on. | Both sides converge to 5 sets with identical state (F17 #5); no duplicate sets. |
| 6 | Kill phone app mid-workout | Swipe-kill Ledger on the phone during rest; log a set on the watch. | Phone relaunched by mirroring or on open shows the new set; `shouldHandleActiveWorkoutRecovery` path taken (F16 #11); elapsed continues. |
| 7 | Kill watch app mid-workout | Force-quit the watch app (hold side button → swipe); reopen. | `handleActiveWorkoutRecovery` → set-ready restored with the same sets and HR continuing on the same `HKWorkout` (F16 #10). |
| 8 | Apple Workout started concurrently | Start Apple's Workout app (Strength) during a Ledger session. | Ledger shows "Apple Workout took over · logging continues" within 2 s (F16 #9); logging still works; on finish, Health shows Ledger's workout only if no takeover, otherwise none from Ledger and no crash. |
| 9 | Finish on watch | End workout → Save workout. | Summary with avg BPM (F18 #11); phone shows receipt; History has one workout; Health shows one `traditionalStrengthTraining` with HR + `com.petearevalo.Ledger.totalVolumeGrams` (F16 #5). |
| 10 | Finish on phone | Repeat a short workout; Finish on phone. | Watch shows summary within 1 s; watch ends the HealthKit session (F17 #11); exactly one Health workout, saved by the watch (no phone `saveWorkout`). |
| 11 | Discard | Repeat; Discard from watch end-confirm, then from phone on another run. | No History entry, no Health workout (F16 #6), Today back to Up-next on both. |
| 12 | Standalone + pull-back | Phone powered off. Start from wrist, log 5 sets, finish. Power phone on. | One workout in phone History within 60 s of pairing (F19 #5), HR filled within 24 h (F19 #9), Today "Logged". |
| 13 | Both finish while partitioned | Bluetooth off; finish on watch; log a set and finish on phone; Bluetooth on. | One workout (F19 #6); union of sets; earlier `finishedAt`; one Health workout. |
| 14 | Always-On | During rest, wrist down 15 s. | HR hidden, countdown still ticking (F18 #12). |
| 15 | Watch HealthKit adapter (stands in for its unit coverage, see testing-strategy §4) | Start on the watch; wear it 1 min; kill the watch app from the Dock mid-set and relaunch; start Apple's Workout app; on another run, finish and check Health. | HR on the wrist within 5 s (F16 #4); `prepare()`→running < 3 s; relaunch recovers the same session with HR resuming (F16 #10); takeover emits the event, no crash (F16 #9); Health shows the workout with `com.petearevalo.Ledger.totalVolumeGrams` accepted as grams (F16 #5). Paste results into `F16-healthkit/implementation-notes.md`. |

Record for each: pass/fail, timings observed, OS builds, and whether `mirroringDegraded` flipped (R1 §2.5 #2 tracking).

## Acceptance criteria
1. Given the protocol above, when executed on one iPhone + Watch pair on iOS/watchOS 26.x, then all 14 scenarios pass and the results file is committed under `tasks/features/F20-device-test-protocol/` (**device**).
2. Given any scenario fails, when recorded, then the results file links the F16–F19 criterion it violates and a bug is filed before M2 is declared done.
3. Given the Diagnostics screen, when opened on either device during scenario 3, then highest-seq vectors are shown per device and match after each step (**device**).
4. Given a Release build, when inspected, then the Diagnostics screen is absent (`#if DEBUG`).
5. Given the M2 exit line in `tasks/todo.md`, when M2 is marked done, then it links the passing results file.

## Test plan
- Unit (LedgerDomainTests): `test_diagnosticsSnapshot_equatableSendable`
- Unit (LedgerSyncTests): `test_actor_diagnosticsReflectsSeqVectorAndDegraded`
- Snapshot (FeatureSettingsTests): `DiagnosticsScreen` × {light, dark}
- Device: the protocol itself; results per run.

## Non-functional
- One full run ≈ 90 min including resets; scenarios 4 and 12 dominate.
- Accessibility: n/a.
- Offline behaviour: scenarios 4, 5, 12, 13 are the offline proof.

## Risks / unknowns
- Whether the 26.0.x mirroring regression persists on the tested build (R1 §6 #1) — scenario 1 + 5 detect it; the WC fallback (F17) must still pass.
- Mirroring "send never returns" (R1 §2.5 #2) is intermittent; record `mirroringDegraded` on every run to size it.
- Later automation: scenarios 3, 5, 13 are reproducible in CI through `FakeTransport` property tests (F17/F19); 6/7 need physical kill; 8 needs Apple's Workout app — never automatable.

## Definition of Done
Inherits `docs/engineering-standards.md` §12, plus:
- [ ] Results file committed with all 14 rows filled, OS builds and commit SHA.
- [ ] Failures cross-linked to issues; M2 exit not ticked until all pass.

---
_Filled in by agents during delivery:_
- `F20-device-test-protocol/implementation-notes.md`
- `F20-device-test-protocol/test-findings.md`
- `F20-device-test-protocol/review.md`

## Inputs from F05 (2026-09-30)
- Run the `Device` and `Device-Watch` test plans on every protocol run and record the result. Besides
  `LedgerHealthTests`, they now run all of `LedgerPersistenceTests` (about 75 fast tests), so the database
  is also exercised on real storage. In it, `DatabaseTests.open_protectsTheFileAndItsCompanions` checks
  that the database file and its `-wal` get the requested data-protection class
  (`completeUntilFirstUserAuthentication` by default). The simulators do not enforce protection classes
  (they accept one and keep none), so the test is skipped there. It runs only on a device and on the Mac
  host (`check.sh --fast`).

## Inputs from F17 (2026-11-26)

F17's device halves: criteria 7, 11 and 13 are proven here, on iPhone 17 + Apple Watch Series 9, with Console open on
both (subsystem `com.petearevalo.Ledger`, category `sync`). Their fake-backed halves are unit tests in
`LedgerSyncTests`. Each step names the scenario above that it extends. Paste the results into
`F17-live-sync/implementation-notes.md` (§ Slice S8, "Device checklist") as well as the run's results file.

**What the phone's header shows (F17 S8).** "Watch not connected — logging continues" shows under the progress bars
while the connection is `reconnecting` (the 30 s after the watch was last reached), and in `solo` once the open
workout screen has heard the watch. `connected` (either channel) and `degraded` show no line, nor does `solo` on a
screen that never heard the watch (a lifter with no watch). So:
- Scenario 1's "phone header 'Connected'" reads as "no line under the bars": there is no "Connected" text.
- In scenario 4 the phone's line shows from the drop until the watch is reached again, through `reconnecting` and
  then `solo`. The watch's line ("iPhone not connected — logging continues") is F18's.

| # | Criterion | Steps | Expected |
|---|---|---|---|
| F17-a | 7 (extends 4) | Start on the watch. Put the phone in airplane mode, or 10 m away and locked, so the watch is `solo`. Log 12 sets on the watch over 10 min. Turn airplane mode off, or bring the phone back and unlock it. | From the drop until the reconnect the phone's workout screen, if it was open with the watch connected, shows "Watch not connected — logging continues", and every control still answers. With Ledger on a phone that has no paired watch, no line ever shows. Within 5 s of the reconnect the phone shows all 12 sets; Console shows one handshake each way (`sync.handshake`) and no "conflicting envelope". |
| F17-b | 11 (extends 10) | Start on the phone, log 2 sets. Put the watch out of reach (airplane mode on the watch). Finish on the phone (Save workout). Bring the watch back. | On reconnect the watch applies the finish: its HealthKit session ends (F16), the watch leaves the workout, and both Histories hold one workout with the 2 sets. Health holds one workout, saved by the watch. |
| F17-c | 13 (extends 3) | With both apps open and mirroring off (the watch app not in a workout, or after a mirroring hang: `degraded`), log a set on the watch. Repeat 10 times. | The phone's row ticks in under 1 s each time. In Instruments (os_signpost, category `sync`) each `sync.roundtrip` interval is under 1 s; record the median and the worst. |
| F17-d | 12 (the line) | During F17-a, with VoiceOver on, move to the line. | VoiceOver reads "Watch not connected — logging continues" once, as text, and does not re-announce it while it stays. Minimize, Finish and every set row still answer. |

Criteria 7 and 13 need the watch's screens (F18) to log a set on the wrist; until then they run with F18's first build.

## Inputs from F18 (2026-11-27)

F18's device halves, run on iPhone 17 + Apple Watch Series 9 with Ledger's watch app frontmost and Console open on the
watch (subsystem `com.petearevalo.Ledger`, categories `watch.workout` and `health`). Everything else in F18 is proven by
`WatchFeatureWorkoutTests` and, on the simulator, by `LedgerWatchUITests` (`WatchFlows`, `WatchAudit`; nightly). Paste
the results into the run's results file; F18's definition of done points at these rows. Until
F19 the watch's settings are the defaults (pounds, buzz on), so the kg and "buzz off" halves wait for F19's push.

While F17-a runs, the watch's own line ("iPhone not connected — logging continues") shows under the set label and over
the rest, and goes within 5 s of the reconnect; record it in F17-a's row.

| # | Criterion | Steps | Expected |
|---|---|---|---|
| F18-a | 4 | On set-ready for the bench press (step 5 lb), turn the crown slowly up 4 detents, then down 4, then flick it fast. Repeat on a dumbbell exercise. | One haptic detent per step and the numeral moves by the step with each detent, with no visible lag (Instruments, `watch.crown` signpost: under one frame). No clamp buzz on the first turn. When the crown stops, the phone shows the new weight once. |
| F18-b | 6 | Log a set, lower the wrist and wait for the rest to end. | At zero, one notification tap on the wrist with the wrist down. Raising the wrist then shows "GO", or set-ready once 1.2 s have passed. |
| F18-c | 15 | Settings › Accessibility › Reduce Motion on; repeat F18-b with the wrist up. | At zero the title reads "GO" and the haptic plays, and the screen does not shake. With Reduce Motion off it shakes three times. |
| F18-d | 12 (extends 14) | On set-ready, then during a rest, lower the wrist and wait at least 15 s; raise it. | Ledger stays on screen, dimmed (not the clock face): the orange dims, the set dots are outlined, the heart rate is hidden in its place, and nothing shifts. The rest countdown keeps ticking; the elapsed time updates at least once a minute. Raised, the screen is full again with no jump. |
| F18-e | 13 (extends 1) | With the watch app not running, start a workout on the phone. | The watch app launches by itself (`handle(_ workoutConfiguration:)`) and shows set-ready of the phone's workout without a tap. |
| F18-f | 13 (extends 7) | During a workout started on the watch, log a set, then force-quit the watch app (side button, swipe). Wait for the system to relaunch it, or open it. | `handleActiveWorkoutRecovery()` runs: set-ready of the same workout, the logged set kept, without a tap. The heart rate resumes on the same Health session; Health later holds one workout. |
| F18-g | spec §9 (extends 8) | During a Ledger workout, start Apple's Workout app (Strength). Return to Ledger and log 2 sets, then save. | The banner "Apple Workout took over · logging continues" shows over every live screen; both sets log; the summary shows; no crash. Health holds Apple's workout and none from Ledger. |
| F18-h | spec §9 | iPhone: Settings › Health › Data Access › Ledger, turn every category off. Start on the watch; log a set. | No Health sheet on the watch. Set-ready reads "— BPM" with the line "Allow Health in iPhone Settings" under it; after the first "Done set" the line goes and does not come back while the app runs. Logging and saving work; the summary's AVG BPM reads "—". Turn access back on afterwards. |
| F18-i | 2, 5, 11 (extends 2) | With Health allowed, start on the watch and lift for 5 min. Compare with Apple's Heart Rate app afterwards. | A BPM shows on set-ready within 5 s of the start and moves with effort, also inside the rest ring. Save: the summary's AVG BPM equals Health's average for the workout, ±1. |
| F18-j | F17 S5b, F18 S3 | With both apps on today's screen, tap "Start" on the phone and on the watch within 1 s of each other. Repeat 3 times. | Each time both devices show one workout, the winner's; the watch shows its set-ready without going through idle. Health holds one workout per run, and the watch shows no error. |
| F18-k | 14 | VoiceOver on the watch. On set-ready swipe through every element; swipe up and down on the weight; double-tap "Done set"; on the rest, the list, the end overlay and the summary, swipe through. | "Weight, 185 pounds, adjustable"; a swipe up or down changes it by one step; "Decrease reps", "Increase reps" and "Done set" are buttons; the heart rate and the set dots read as text; the ring reads "Rest, 42 seconds remaining" (its seconds); each list row reads its name and scheme, done rows "All sets logged"; each summary tile reads as one phrase. |
| F18-l | layout (DoD) | Run a workout to the summary on the Series 9, then on the 42 mm and 49 mm (Ultra) simulators, at the default text size and at the largest (Settings › Display & Brightness › Text Size). | Every screen fits, or scrolls whole to its last button; nothing is cut; the 3-digit weight shows whole at the default size and never shrinks below the 11 pt floor. Record a screenshot of set-ready and the rest per size. (The 49 mm snapshots are a follow-up; this row stands in until then.) |
| F18-m | frontmost, battery | Charge to 100 %. Run a 60-minute workout from the watch: a set every 2–3 min, the wrist down between sets. | On every wrist raise Ledger is frontmost (the running Health session keeps it there; no `WKExtendedRuntimeSession`). Record the battery used in the hour, and the same for an hour of Apple's Workout (Strength) on another day, for comparison. |
