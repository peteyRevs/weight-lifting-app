# Ledger — Product decisions (assumed defaults)

`docs/product-spec.md` §10 lists 20 open questions the prototypes leave
unanswered. Engineering cannot start without answers, so the defaults below
are **assumed** for the plan. Each is a recommendation with a reason. Override
any of them and the affected feature briefs will be updated.

| # | Question | Decision (default) | Why |
|---|---|---|---|
| 1 | Canonical prototype | **v1 flow, v2 visual system.** Four tabs (Today · Program · Library · History). Dark is the primary theme; light tokens are defined so both ship. | v1 has the complete behaviour (builder, progression, deload, supersets); v2 is the intended look. |
| 2 | Auth vs onboarding | **No accounts.** Local-first on device; cross-device sync via iCloud/CloudKit (keyed to the Apple ID, no sign-in UI). Onboarding = v2's three steps → generates the initial program from templates → user may edit in the builder. The v1 Home/auth screen is dropped. | Removes a whole backend, password reset, Sign in with Apple review burden. Apple users already have iCloud. Accounts can be added later without changing the domain. |
| 3 | Progression & PR rules | Linear / double / fixed exactly as spec §7.2. Deload: load × 0.85 rounded to the exercise's weight step, −1 set (min 1), −2 RPE (min 5). **PR** = new best estimated 1RM for the exercise, or new best weight at ≥ the same reps. The prototype's "above catalog start load" rule is discarded. | Prototype PR rule is a placeholder; e1RM-based PRs are what lifters expect. |
| 4 | 1RM formula | **Brzycki** (`w × 36 / (37 − r)`), capped at r ≤ 12 (above that, e1RM is not computed). Weekly chart point = best e1RM in that week. | Matches the prototype's sample number (218 for 195×5). |
| 5 | Miss / hold rule | A slot is missed if any **working** set (not drop, not added) is short of target reps or fewer working sets were logged than prescribed. Deload-week results never count as misses. | Prevents drop/extra sets masking a miss (spec §7.2 note). |
| 6 | Watch superset logging | Watch and phone call the **same** round-aware engine path (ADR-004). Group rest after the last member of a round; cursor is round-robin. | One engine → one behaviour. |
| 7 | Rest timer | Starts on every not-done → done transition when Auto-rest is on (default on). Superset: only after the round's last member; duration = max rest of members. Un-ticking never cancels rest. "+30s" at zero restarts a 30 s rest. | Spec §7.4 plus the obvious fix for the "+30s after zero" hole. |
| 8 | Elapsed timer | Keeps counting while minimised or backgrounded. A live workout idle for 4 h prompts "Still lifting?" on next open (Finish / Discard / Continue). | Matches prototype; prevents 9-hour "workouts" from a forgotten session. |
| 9 | Units | **lb and kg both supported at launch.** Domain stores weight in grams (`Int`). Per-unit steps: lb 5 / 2.5, kg 2.5 / 1.25. Bar 45 lb / 20 kg. Plate set per unit, editable in Settings. | Retrofitting units is the classic lifting-app regret; the domain type makes it free. |
| 10 | Plate math | Shown under the active set row (v2 suggestion) for barbell exercises when enabled. Bar and plates configurable. | Where the eye already is. |
| 11 | History tab root | **Workout list** grouped by week (newest first) → workout detail (receipt view, editable) → exercise history. Exercise history also reachable from Library. | The prototype's jump-to-Bench-Press is a placeholder. |
| 12 | Exercise catalog | Ship a curated seed of ~200 exercises (name, equipment, primary/secondary muscles, movement pattern, default step, alternatives) as JSON in `LedgerDomain` resources; a dedicated brief (F03) authors and validates it. Custom exercises supported. | Copy promises "214 exercises". |
| 13 | Swap semantics | One-off for this workout by default, with an "Also update program" toggle in the sheet. The replacement brings its own last-known load if history exists, else the original's load. Swap allowed inside supersets. | Least surprise; program stays intact unless asked. |
| 14 | Time estimate | One formula everywhere: Σ over sets of (42 s + rest), where a superset round counts its rest once. | Spec §7.7 has two; pick one. |
| 15 | Week boundary & stats | Week starts on the user's locale first weekday (Settings override). "Sessions this week" = done / scheduled in the current week. "lb moved" tile = current week; delta vs previous complete week. | Deterministic and testable. |
| 16 | Watch scope | Start-from-wrist is **in** for M2. Watch works fully without the phone (own event log, own HealthKit session); events reconcile on reconnect. Heart rate via HealthKit is required. | This is the product's headline. |
| 17 | Copy tone | v2 rules: ≤ 6 all-caps eyebrows per screen; accent orange once per screen on the primary action. Encoded in `LedgerDesign` guidance. | Design intent. |
| 18 | Dates | A program **block** has a `startDate` (the first day of the week the user started). Current week = weeks since `startDate`. Training on an unscheduled day → "Train off-schedule" picker of that week's days. Skipping a whole week counts as a miss for every slot (loads hold). Block end → "Start next block" flow (repeat with +progression or edit). | Spec has no real dates at all; this anchors everything. |
| 19 | Account | None (see #2). | — |
| 20 | Export / Health | CSV export of workouts + sets (share sheet). HealthKit workout type `traditionalStrengthTraining`, with heart-rate samples and active energy from the watch session; total volume in metadata. | Standard for the category. |

## Additional scoping calls

- **Launch platforms:** iPhone + Apple Watch. iPad runs the iPhone app (no dedicated layout at launch). No Mac.
- **Sync scope:** M2 = phone⇄watch live workout. M4 = iCloud across the user's devices. No sharing between users.
- **Live Activity** for elapsed + rest on the iPhone Lock Screen / Dynamic Island: M3.
- **Complications / Smart Stack:** "Next session" and "Rest remaining": M3.
- **Notifications:** rest-over local notification when the phone app is backgrounded: M3. Scheduled-day reminders: post-launch.
- **Accessibility:** Dynamic Type, VoiceOver, Reduce Motion, and contrast fixes for the 35–45 % alpha text are launch requirements, not polish.
