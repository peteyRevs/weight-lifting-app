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
