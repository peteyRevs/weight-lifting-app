# ADR-005: Watch is the primary workout session; HealthKit mirroring carries live events; WatchConnectivity carries everything else

**Status:** Accepted · **Date:** 2026-09-16 · **Evidence:** `docs/research/R1-apple-platform.md` §2–§4

## Context

"Phone + watch share one live workout" requires a bidirectional, low-latency
channel while a workout is running, plus a reliable, background-capable channel
for pushing programs to the watch and pulling finished workouts back. Only the
watch has a heart-rate sensor, and HealthKit only allows the watch to be the
primary `HKWorkoutSession`; `startMirroringToCompanionDevice()` exists on
watchOS only (verified 2026-09-16). iOS 26 lets the phone run its *own*
session, but not act as the primary for a watch mirror.

## Decision

1. **The watch owns the HealthKit workout session** and is the authoritative
   producer of the workout's HealthKit record. The phone requests a start via
   `HKHealthStore.startWatchApp(toHandle:)` when the user taps "Start workout"
   on the phone; the watch can also start from the wrist.
2. **Live workout events** (ADR-004 envelopes) travel over the mirroring data
   channel (`sendToRemoteWorkoutSession` / `didReceiveDataFromRemoteWorkoutSession`).
   Because HealthKit also mirrors session state (running / paused / ended) and
   launches the phone app in the background, this is the only channel that
   gives the phone live HR and a consistent session.
3. **Latency and loss mitigation:** envelopes are small, versioned, idempotent
   and ordered by `(device, seq)`. While `WCSession.isReachable`, the same
   envelopes are additionally sent via `sendMessageData` for sub-second phone
   UI updates; receivers dedupe. A watchdog on `sendToRemoteWorkoutSession`
   falls back to WatchConnectivity if the call never returns (a known ~5 %
   failure). On every reconnect both sides exchange "highest seq seen" and
   replay gaps.
4. **Session start sequence** (DTS workaround for the 26.0.x regression):
   `prepare()` → wait for `.prepared` in `workoutSession(_:didChangeTo:from:date:)`
   → `startMirroringToCompanionDevice()` → begin sending. The phone assigns
   `workoutSessionMirroringStartHandler` synchronously at launch and retains
   every session object it is handed (the handler may fire repeatedly on
   reconnect). The Live Activity is started inside that handler.
5. **Non-live data** uses WatchConnectivity: `updateApplicationContext` for
   "current program + next day" (latest wins, ≤ 256 KB), `transferFile` for
   full program/history JSON, `transferUserInfo` for ordered small records such
   as a workout finished on the watch while the phone was away. Never
   `sendMessage` for anything that must arrive.
6. **The watch works alone.** Its GRDB store, event log, and HealthKit save do
   not depend on the phone. Divergent logs for the same `WorkoutID` merge by
   union + replay.

## Alternatives rejected

- Phone as primary with the watch as a dumb display: not supported by HealthKit
  and loses standalone wrist workouts.
- WatchConnectivity only: no session-state mirroring, no background launch of
  the phone app, no HR on the phone, delivery not guaranteed for `sendMessage`.
- Custom Bluetooth/Multipeer channel: not available to watch apps.

## Consequences

- Real-device testing is mandatory for the sync feature (the multi-device
  sample requires physical devices; `transferUserInfo` is unsupported in the
  simulator). `docs/testing-strategy.md` defines a device checklist that gates
  M2.
- `LedgerSync` must be written defensively: timeouts, retries, dedupe,
  observable connection state surfaced to the UI ("Watch not connected —
  logging continues").
- The phone can still log a workout without any watch (saves via
  `HKWorkoutBuilder`, no HR), so the product degrades gracefully.
