# F25 — Plate math on the active set row

| | |
|---|---|
| Milestone | M3 |
| Status | proposed |
| Depends on | F10, F14 |
| Branch | `feat/F25-plate-math` |
| Design refs | v1 `plateLine` under TARGET; v2 NEXT STEPS (2) "on the set row" |
| Spec refs | `docs/product-spec.md` §7.7 rule 38; `docs/product-decisions.md` #10 |

## Goal
For barbell exercises, the active set row shows the per-side plate breakdown for the current weight using the user's bar and plate inventory, updating live with the stepper and the crown.

## Scope
**In:** `PlateLine` component under the active `SetRow` (phone) and a compact plate line on the watch set-ready screen; reads `Settings.plateMathEnabled` and `plateInventory[units]`; hides for non-barbell equipment or when the load is below one plate.
**Out:** inventory editing (F14), warm-up ramp suggestions.

## Touches
- `LedgerKit/Sources/LedgerDesign/Components/PlateLine.swift`
- `LedgerKit/Sources/FeatureWorkout/SetRow+PlateLine.swift`, `LedgerKit/Sources/WatchFeatureWorkout/SetReady+PlateLine.swift`
- Tests in `LedgerDesignTests`, `FeatureWorkoutTests`, `WatchFeatureWorkoutTests`

## Domain changes
None (`PlateMath.perSide` from F02).

## Acceptance criteria
1. Given plate math on, lb units, a barbell exercise and weight 185, then the active row shows "45 + 25 / side"; stepping to 190 shows "45 + 25 + 2.5 / side".
2. Given kg units with the standard kg inventory and weight 62.5, then "20 + 1.25 / side"; 47.5 lb (below one 2.5 plate per side) shows nothing.
3. Given a dumbbell exercise, then no plate line is rendered.
4. Given a custom inventory without 2.5 lb plates, then 185 → "45 + 25 / side" and 190 → "45 + 25 / side · +2.5 short" (explicit shortfall text).
5. Given the watch set-ready screen, then the line renders under the weight in the 17 px label style and truncates with "…" beyond 3 terms.

## Test plan
- Unit: `PlateLineFormattingTests` (criteria 1–4 incl. shortfall), `PlateLineVisibilityTests` (equipment, setting, threshold).
- Snapshot: phone active row with line (light/dark/XL), watch set-ready with line (46 mm).

## Non-functional
- Computation on the main actor is O(plates); no allocation per tick.

## Definition of Done
Inherits `docs/engineering-standards.md` §12.

---
_Filled in by agents during delivery:_ `F25-plate-math/{implementation-notes,test-findings,review}.md`
