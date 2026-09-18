# F22 — Widgets and watch complications / Smart Stack

| | |
|---|---|
| Milestone | M3 |
| Status | proposed |
| Depends on | F09, F18 |
| Branch | `feat/F22-widgets-complications` |
| Design refs | Today "UP NEXT" card (compressed); watch idle screen |
| Spec refs | R1 §4.2–§4.3; `docs/product-decisions.md` ("Complications / Smart Stack: M3") |

## Goal
"Next session" at a glance on the iPhone Home Screen and in the watch Smart Stack, plus a rest-remaining Smart Stack card that surfaces itself during a workout via WidgetKit relevance.

## Scope
**In:** iOS widget (small: day name + tag + week; medium: + first three exercises), watch `accessoryRectangular`/`accessoryCorner` complications for next session, Smart Stack relevance during rest, timeline reloads on program/workout changes, a shared read-only `WidgetSnapshot` JSON in the app group written by the app.
**Out:** interactive widgets, Live Activity (F21).

## Touches
- `LedgerKit/Sources/LedgerDomain/Widgets/WidgetSnapshot.swift` (pure: next session summary)
- `LedgerKit/Sources/LedgerAppKit/WidgetSnapshotWriter.swift`, `LedgerKit/Sources/LedgerWatchAppKit/WidgetSnapshotWriter.swift`
- `Apps/LedgerWidgets/NextSessionWidget.swift`, `Apps/LedgerWatchWidgets/{NextSessionComplication,RestRelevance}.swift` (targets — human, ADR-003)
- App group entitlement on all four targets

## Domain changes
```swift
public struct WidgetSnapshot: Codable, Sendable, Equatable { public var generatedAt: Date; public var nextSession: NextSession?; public var liveRest: (endsAt: Date, exercise: String)?
    public struct NextSession: Codable, Sendable, Equatable { public var dayName: String; public var tag: String; public var weekLabel: String; public var scheduledFor: Date; public var preview: [String] } }
public enum WidgetSnapshotBuilder { public static func build(program: Program?, calendar: WeekCalendar, workouts: [WorkoutState], live: WorkoutState?, now: Date) -> WidgetSnapshot }
```

## Acceptance criteria
1. Given an active program, when the app writes the snapshot, then the iOS small widget shows "Upper A · UA · Week 3 of 8" and the medium adds three preview lines; with no program, "Set up a program" deep-links to Onboarding.
2. Given a rest in progress on the watch, then the Smart Stack card "Rest 1:23 · Bench Press" appears with relevance score rising and a countdown `Text(timerInterval:)`.
3. Given a program edit or a finished workout, then `WidgetCenter.shared.reloadTimelines` is called once (recorded on a fake) and the widget updates within the next timeline entry.
4. Given a rest day, then the widget shows "Rest day · Next: Fri UB".
5. Given the widget is tapped, then the app opens on Today (deep link `ledger://today`).

## Test plan
- Unit: `WidgetSnapshotBuilderTests` (scheduled/rest/next-week/no-program cases; live rest), `SnapshotWriterTests` (writes atomically, reloads once).
- Snapshot: widget and complication views × families × light/dark.
- Device: Smart Stack appearance during rest (F20 addendum).

## Non-functional
- Snapshot file ≤ 4 KB; written on the main actor after materialization; never on every tick.

## Risks / unknowns
- watchOS relevance heuristics are opaque; treat card surfacing as best-effort.

## Definition of Done
Inherits `docs/engineering-standards.md` §12.

---
_Filled in by agents during delivery:_ `F22-widgets-complications/{implementation-notes,test-findings,review}.md`
