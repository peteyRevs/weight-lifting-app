# F23 — Rest-over notifications and abandoned-session handling

| | |
|---|---|
| Milestone | M3 |
| Status | proposed |
| Depends on | F10 |
| Branch | `feat/F23-rest-notifications` |
| Design refs | v2 rest card copy "watch buzzes at zero" |
| Spec refs | `docs/product-decisions.md` #7, #8; ADR-004 effects |

## Goal
When the phone app is backgrounded and no watch is connected, a local notification fires exactly when rest ends, with "+30s" and "Skip" actions that feed the engine. A live workout left idle for four hours prompts "Still lifting?" on next open.

## Scope
**In:** `NotificationsClient` live implementation (UNUserNotificationCenter), scheduling/cancelling from `Effect.scheduleRestNotification/cancelRestNotification`, notification category with actions, permission request at first rest (not at launch), foreground suppression when the app is visible or the watch session is connected, the 4-hour prompt.
**Out:** scheduled-day reminders (post-launch), watch haptics (F18).

## Touches
- `LedgerKit/Sources/LedgerDependencies/Keys/Notifications.swift` (live client), `LedgerKit/Sources/LedgerAppKit/{NotificationCoordinator,StillLiftingPrompt}.swift`
- `LedgerKit/Sources/FeatureWorkout/AbandonedSessionSheet.swift`
- Tests under `LedgerAppKitTests`, `FeatureWorkoutTests`

## Domain changes
`WorkoutState.lastActivityAt: Date` (updated by the engine on every applied event) — add to F04's state (coordinate: small additive change with a test).

## Acceptance criteria
1. Given a rest starts while the app is in the foreground, then no notification is scheduled until the app enters the background; on background, one request is scheduled for `endsAt` (or fires immediately if already past).
2. Given the watch is connected (`ConnectionState.connected`), then the phone does not schedule rest notifications (the wrist buzzes instead).
3. Given the notification's "+30s" action, then `restExtended(by: 30 s)` is applied and the notification rescheduled; "Skip" applies `restSkipped`.
4. Given rest is skipped or a set is logged before `endsAt`, then the pending request is cancelled (no stale buzz).
5. Given notification permission denied, then the rest card shows a one-time inline hint "Turn on notifications to be alerted when rest ends" with a Settings link; no repeated prompts.
6. Given a live workout with `lastActivityAt` older than 4 h, when the app opens, then a sheet offers Finish / Discard / Keep going; Finish uses the last activity time as `endedAt`.

## Test plan
- Unit: `NotificationCoordinatorTests` (criteria 1–4 with `FakeNotifications` and scene-phase injection), `AbandonedSessionTests` (6), `PermissionFlowTests` (5).
- Snapshot: hint state of the rest card; abandoned sheet.
- UI (nightly): background the app with a 10 s rest and assert a delivered notification via `XCUIDevice` springboard query (`.flakyProne`).

## Non-functional
- At most one pending notification at any time; identifiers deterministic (`rest-<workoutID>`).

## Definition of Done
Inherits `docs/engineering-standards.md` §12.

---
_Filled in by agents during delivery:_ `F23-rest-notifications/{implementation-notes,test-findings,review}.md`
