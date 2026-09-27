# F21 — Live Activity: elapsed and rest on Lock Screen and Dynamic Island

| | |
|---|---|
| Milestone | M3 |
| Status | proposed |
| Depends on | F10, F17 |
| Branch | `feat/F21-live-activity` |
| Design refs | v2 rest card (ring, m:ss, next line) adapted to ActivityKit layouts |
| Spec refs | `docs/research/R1-apple-platform.md` §4.1–§4.2; ADR-005 §4; `docs/architecture.md` §4 |

## Goal
While a workout is live, the iPhone Lock Screen and Dynamic Island show the elapsed time, the current exercise/set, and a rest countdown that ticks without app updates. The activity starts inside the HealthKit mirroring start handler (or at phone-only start), updates only on state transitions, and ends on finish/discard.

## Scope
**In:** `LedgerActivityKit` attributes/content state, `LedgerWidgets` Live Activity UI (compact/minimal/expanded/Lock Screen), start/update/end driven by engine `Effect.updateLiveActivity`, iOS 27-only `LiveActivityIntent` buttons (+30s / Skip) behind `#available(iOS 27, *)`.
**Out:** watch Smart Stack (F22), push-updated activities (none; local only).

## Touches
- `LedgerKit/Sources/LedgerActivityKit/{WorkoutActivityAttributes,ActivityContentMapper}.swift`
- `Apps/LedgerWidgets/{LedgerWidgetsBundle,WorkoutLiveActivity,RestIntents}.swift`, `Apps/LedgerWidgets/Info.plist`
- `LedgerKit/Sources/LedgerDependencies/Keys/LiveActivities.swift` (`liveValue` → `ActivityKitClient`)
- `Apps/Ledger-Info.plist` (`NSSupportsLiveActivities`), `Ledger.xcodeproj` (widget extension target — human, ADR-003)

## Domain changes
```swift
public struct WorkoutActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable { public var startedAt: Date; public var exerciseName: String; public var setLabel: String; public var restEndsAt: Date?; public var restTotal: TimeInterval?; public var doneSets: Int; public var totalSets: Int }
    public var workoutID: WorkoutID
}
```
`Effect.updateLiveActivity` → `LiveActivitiesClient.update(state)`; `start` on `started`, `end(dismissalPolicy: .after(now + 15 min))` on `finished`/`discarded`.

## Acceptance criteria
1. Given a mirrored session starts, when `workoutSessionMirroringStartHandler` fires, then the activity is requested within the 10 s budget (measured in a unit test around `ActivityKitClient.start` with an injected clock; device check in F20).
2. Given a rest started with `endsAt`, then the Lock Screen shows `Text(timerInterval: now...endsAt, countsDown: true)` and needs no further updates until the rest ends.
3. Given consecutive `setLogged` events, then at most one `update` per event and none for timer ticks (call recording on the fake).
4. Given `finished`, then the activity ends with a "Workout done · 52:14 · 24,180 lb" final state and dismisses after 15 minutes.
5. Given iOS 27, then the expanded Dynamic Island shows "+30s" and "Skip" `LiveActivityIntent` buttons that post `restExtended`/`restSkipped` to the `WorkoutSessionActor` through the app group; on iOS 26 the buttons are absent and layouts still pass snapshots.
6. Given Live Activities disabled in system settings, then the app degrades silently (no error UI).

## Test plan
- Unit: `ActivityContentMapperTests` (state → content), `LiveActivityEffectTests` (start/update/end call sequences on `FakeLiveActivities`), `RestIntentTests` (intent → event).
- Snapshot: widget views for compact/minimal/expanded/Lock Screen × light/dark (render the SwiftUI views directly).
- Device (F20 protocol): visual check on iPhone; budget check.

## Non-functional
- Update count per workout ≤ number of state transitions (typically < 60); no background push.

## Risks / unknowns
- App-group data path for intents → actor (use a small `WorkoutIntentQueue` file + Darwin notification; F23 shares it).

## Definition of Done
Inherits `docs/engineering-standards.md` §12.

---
_Filled in by agents during delivery:_ `F21-live-activity/{implementation-notes,test-findings,review}.md`
