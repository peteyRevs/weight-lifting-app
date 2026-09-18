# Ledger — Product Specification (derived from design prototypes)

Source of truth for this document: the interactive prototypes in `design/prototype/`:

| File | Label in file | Theme | Role |
|---|---|---|---|
| `Ledger.dc.html` | "WORKING PROTOTYPE — V1" | Light ("paper") | **Primary.** Full flow: auth, program builder, day editor, settings, today, live workout, receipt, library, history. Contains the real state model and business rules. |
| `Ledger v2.dc.html` | "V2 · SLEEKER PASS" | Dark | Visual restyle of an *earlier, smaller* flow set (onboarding, today, workout, library, history). Fewer rules; many values hard-coded. |
| `LedgerWatch.dc.html` | — | Watch (black) | Shared watch component used by both phone prototypes. |
| `LedgerTabs.dc.html` | — | Light | 4-tab bar used by v1 (Today, Program, Library, History). |
| `LedgerTabsDark.dc.html` | — | Dark | 3-tab bar used by v2 (Today, Library, History). |

Important orientation note for implementers: despite the naming, **v1 is the more complete and more recent behavioural prototype** (its header says "NEW THIS PASS: Exercises can be chained into supersets… and any exercise can carry a drop set"). v2 explicitly lists "Program builder — the one screen not designed yet", "Plate math", "Deload and failed-set states" and "workout-start-from-wrist" as *next steps*, yet all four exist in v1. Treat v1 as the functional spec and v2 as the candidate visual language. Where the two disagree on behaviour, this document says so explicitly.

Conventions used below:
- "Copy" strings are quoted exactly as they appear in the prototype, including capitalisation and the middle dot `·`.
- `state.x` refers to the phone prototype's component state; `watch.x` refers to the object the phone passes to the watch component.
- Pixel values are prototype pixels at 1:1 for the phone (402 × 874 frame) and at 1.5× for the watch (see §4).

---

## 1. Product summary

Ledger is a lifting log for iPhone and Apple Watch for lifters who already know what they want to train. The user writes a multi-week block at home (training days, exercises, sets × reps, starting load, progression rule, rest), assigns days to a weekly schedule, and then at the gym only logs: each set arrives pre-filled with the prescribed weight and reps, one tap logs it, a shared rest timer runs on both phone and wrist, and the wrist buzzes at zero. History feeds a per-exercise estimated-1RM chart, best set, PR tags and weekly volume. The phone owns setup, programming and review; the watch is for tracking only, with weight and reps pushed from the phone and adjustable from the Digital Crown.

### Design principles (verbatim from prototype copy)

From v1 (`Ledger.dc.html` header):
- Tagline: "A lifting log built around one question: what am I lifting next, and what did I lift last time. Everything else gets out of the way."
- Sub-label: "PHONE + WATCH SHARE ONE LIVE WORKOUT"
- **ASSUMED** — "Barbell strength plus hypertrophy accessories, four days a week, pounds. Programs get built at home; the gym is for logging only."
- **THE SYSTEM** — "Paper ground, ink type, one accent. Numbers are the loudest thing on every screen: expanded Archivo, tabular figures, nothing below 15px."
- **NEW THIS PASS** — "Exercises can be chained into supersets from the expanded panel, and any exercise can carry a drop set. The live workout shows a superset as one block, logged round by round, and only rests once the last exercise in the round is done."
- Phone caption: "Phone — setup, programming and review. Change the week or the schedule on Program, then open Today: the session that starts is the one you just wrote. Tap a set row for steppers; tick a set to start the shared rest timer."
- Watch caption: "Watch — six states: before the workout (start from the wrist), set ready, rest, the session list (tap the exercise name), end-workout confirm, and the summary. Weight and reps arrive preset from the phone. Drag the crown to adjust, tap the face to log. Drawn at 1.5× a 46mm display (208 × 248 pt) — divide by 1.5 for real point sizes. Smallest label is 17px = 11pt; the ± buttons are 44px = 29pt, tuned for the crown to do the fine work."
- Home-screen marketing copy: "Write the program. Log the work." / "For lifters who already know what they want to train. Build your own routine, day by day, and keep every number."

From v2 (`Ledger v2.dc.html` header):
- Tagline: "Same flows, quieter surface. The interface went dark to match the watch, the cards became hairlines, and the numbers are now the only thing with weight."
- **SURFACE** — "Two greys and a hairline. Nothing floats on a white card any more, so the eye has one place to land per screen."
- **TYPE** — "Archivo at 300 and 500 for everything except the numbers, which stay at 700 in a narrow width. All-caps labels dropped from thirty-odd to six."
- **ACCENT** — "Orange appears once per screen, on the thing you are about to touch. Everywhere else it is a one-pixel rule."
- Phone caption: "Phone — setup, programming and review. Tap a set row for steppers; tick a set to start the shared rest timer."
- Watch caption: "Watch — tracking only. Weight and reps arrive preset from the phone. Drag the crown to adjust, tap the face to log. Drawn at 1.5× a 46mm display (208 × 248 pt); smallest label is 17px, so 11pt on device."

Note the "nothing below 15px" principle in v1 is aspirational: the prototype itself uses 8–13 px for labels and metadata. Treat 15 px as the minimum for *numbers and primary text*, and the listed smaller sizes as the actual label scale (§8).

---

## 2. Information architecture

### 2.1 Tabs

| Tab key | Label | v1 (light) | v2 (dark) | Root screen |
|---|---|---|---|---|
| `today` | "Today" | ✓ | ✓ | Today |
| `program` | "Program" | ✓ | **absent** | Program builder |
| `library` | "Library" | ✓ | ✓ | Library |
| `history` | "History" | ✓ | ✓ | Exercise history (prototype shows a single hard-coded exercise, Bench Press — see §9) |

Tab-bar behaviour (`setTab` in v1): tapping a tab sets `state.tab` and navigates to that tab's root screen. `program` always returns to the Program builder root (not to Day editor or Settings). Sub-screens keep the parent tab highlighted: Day editor and Settings highlight "Program"; Session receipt and Active workout highlight "Today" (`tabFor`). The tab bar is **not** rendered on: Home (auth), Day editor, Session receipt, Active workout. It is rendered on: Program builder, Settings, Today, Library, Exercise history.

Tab-bar icons are single-path 24×24 stroke SVGs (§8.7).

### 2.2 Screens (by `data-screen-label`)

v1 phone screens: `Home`, `Program builder`, `Settings`, `Day editor`, `Today`, `Session receipt`, `Active workout`, `Library`, `Exercise history`.

v2 phone screens: `Onboarding`, `Today`, `Active workout`, `Library`, `Exercise history`.

Watch screens (shared component): `Watch — before workout`, `Watch — set ready`, `Watch — rest timer`, `Watch — session list`, `Watch — end workout`, `Watch — summary`.

Modal sheets / overlays (rendered inside the screen, `position:absolute; inset:0` scrim):
- Day editor → **Exercise library** picker sheet (90% height, bottom sheet).
- Active workout → **Rest** panel (v1: full-width ink bottom sheet; v2: floating translucent card) — not dismissable by tap-outside; ends by timer, "Skip rest", or logging.
- Active workout → **Swap exercise** bottom sheet.

### 2.3 Navigation graph (v1)

```
Home (auth) ──"Log in"/"Create account"/"Continue with Apple"/"Forgot password?"──▶ Program builder
Program builder ──gear button──▶ Settings ──"‹ Program"──▶ Program builder
Program builder ──tap training-day card / "+ Add training day"──▶ Day editor ──"‹ Program" or "Done"──▶ Program builder
Day editor ──"+ Add exercise from library"──▶ [Exercise library sheet] ──"Cancel"/"Add N exercises"──▶ Day editor
Settings ──"Log out"──▶ Home
Today ──"Start workout" / "Resume · m:ss"──▶ Active workout
Today ──"View session" (logged card)──▶ Session receipt
Today ──RECENT row (today's finished session)──▶ Session receipt
Today ──RECENT row (sample sessions)──▶ Exercise history (tab: history)
Today ──"Edit this week" (rest-day card)──▶ Program builder
Active workout ──"‹ Minimize"──▶ Today (session stays live; Today shows "Resume · m:ss")
Active workout ──"Finish"──▶ Session receipt
Active workout ──"⇄"──▶ [Swap exercise sheet] ──"USE"/"Cancel"──▶ Active workout
Session receipt ──"Done"──▶ Today
Library ──any exercise row──▶ Exercise history ──"‹ Library"──▶ Library
Tab bar: Today | Program | Library | History (History tab → Exercise history directly)
Watch: idle ──"Start"──▶ phone opens Active workout for today's scheduled day
Watch: list ──"End workout"──▶ end ──"Save workout"──▶ Session receipt on phone, summary on watch
                                     ──"Discard"──▶ Today on phone, idle on watch
```

Initial screen in the v1 prototype is Program builder (`screen:'program'`), with the Home/auth screen reachable via "Log out". In the product, Home is the unauthenticated entry point.

### 2.4 Navigation graph (v2)

```
Onboarding (3 steps) ──"Continue" ×2, "Start training"──▶ Today   (or "Skip setup" at any step ──▶ Today)
Today ──"Start workout"/"Resume workout · m:ss"──▶ Active workout ──"Minimize"──▶ Today
Active workout ──"Finish"──▶ Today (no receipt screen in v2; marks finished, watch shows summary)
Active workout ──swap icon──▶ [Swap exercise sheet]
Today ──RECENT row──▶ Exercise history
Library ──row──▶ Exercise history ──"Library"──▶ Library
Tab bar: Today | Library | History
```

### 2.5 v1 vs v2 flow differences (explicit)

| Area | v1 | v2 |
|---|---|---|
| Entry | Home: Log in / Create account / Continue with Apple | Onboarding: goal → days/week → program preview |
| Program tab | Present (Program builder, Day editor, Settings) | Absent; "Program builder" listed as not designed |
| Settings | Present (units, default rest, 3 toggles, account rows) | None |
| Today | Data-driven from schedule; rest-day card; logged card; UP NEXT card with week/deload; stats; recent | Hard-coded "Upper A", "Week 3 of 8 · ~52 min", 3/4 sessions, 41.2k lb |
| Active workout | Supersets as blocks, drop sets, TARGET pill (RPE), plate math line, per-exercise weight step (5 / 2.5) | Straight sets only; no target pill; fixed 5 lb step |
| Finish | → Session receipt (time, sets, lb moved, PR line, logged vs prescribed) | → Today, no receipt |
| Rest UI | Ink bottom sheet, "Watch will buzz at zero" | Floating glass card, "Resting · watch buzzes at zero" |
| Watch modes used | idle, ready, rest, summary (+ list, end) | ready, rest, summary only (no idle, no list callbacks) |
| Weight step | `exercise.step` (Barbell 5, else 2.5) | 5 always |
| Auto-rest toggle | Yes (Settings) | Always on |
| Type | 400–900 weights, wide numerals (wdth 106–112) | 300–700 weights, narrow numerals (wdth 88–98) |

---

## 3. Screen specs (iPhone)

All v1 screens: background `#EFEDE6` (PAPER), full-height flex column, scrollable content region with hidden scrollbars, top padding 64–78 px to clear the status bar, side padding 20–26 px. Cards are `#fff`. Section labels are 700 9px uppercase with 0.14–0.18em tracking at 42% ink.

Initial prototype state (v1) — the defaults an engineer should reproduce for a seeded/demo account:

```
screen:'program', tab:'program', auth:'login',
units:'lb', restDefault:90, plateMath:true, autoRest:true, watchBuzz:true,
days: DAYS (4 days, see §6), dayIdx:0, openEx:0,
weeksData: 8 weeks; weeks 1–7 sched [UA,—,LA,—,UB,LB,—]; week 8 sched [UA,—,LA,—,UB,—,—] and deload:true,
curWeek:0, exIdx:0, activeSet:0, started:false, elapsed:0, rest:0, restTotal:150,
buzz:false, swapOpen:false, filter:'All', session:null,
todayDow:2 (Wednesday), doneDow:[0] (Monday already logged), priorVolume:24180,
finishedSummary:null, crownDrag:false, hr:118, finished:false
```

A 1-second tick runs continuously: `elapsed += 1` while `started && !finished`; `rest -= 1` while `rest > 0`, and when `rest` goes from 1 to 0 the tick sets `buzz = true`; heart rate is a random walk clamped to 96–158 bpm (±3/s) — sample data standing in for HealthKit.

### 3.1 Home (v1 only) — `data-screen-label="Home"`

**Purpose.** Unauthenticated entry: log in or create an account.

**Layout (top → bottom).**
1. Brand row: 24×24 ink rounded square (radius 7) containing "L" in paper, 800 11px; beside it "LEDGER" 700 9px, 0.2em tracking, 45% ink.
2. Headline "Write the program. Log the work." — 800 42px/1.02, `'wdth' 108`, −0.03em.
3. Body "For lifters who already know what they want to train. Build your own routine, day by day, and keep every number." — 400 15px/1.5, 60% ink, max-width 290.
4. Flexible spacer.
5. Segmented control (2 segments, track `rgba(22,21,15,.07)` radius 14, padding 4; selected segment `#fff` radius 11, ink text; unselected transparent, 50% ink): "Log in" | "Create account". State `auth ∈ {'login','create'}`, default `login`.
6. Inputs (border 1.5px 14% ink, white, radius 14, padding 17px 16px, 500 15px; focus border `#FF5B22`): "Name" (create only), "Email", "Password".
7. Primary button (orange, white 700 16px, radius 16, padding 19): label = "Log in" or "Create account" (`authCta`).
8. Divider row: hairline — "OR" (600 10px, 0.12em, 35% ink) — hairline.
9. Secondary button (1.5px 16% ink border, radius 16, 600 15px): "Continue with Apple".
10. Login only: text button "Forgot password?" (500 13px, 45% ink).
11. Create only: legal line "By creating an account you agree to the terms and privacy policy." (400 11.5px, 40% ink, centred).

**Interactions.** Segment tap → `auth`. Every button including "Forgot password?" and "Continue with Apple" calls `authGo` → navigates to Program builder (`screen:'program', tab:'program'`). No validation, no error states in the prototype.

### 3.2 Program builder (v1 only) — `data-screen-label="Program builder"`

**Purpose.** Define the block: number of weeks, which training day happens on which weekday each week, deload weeks, and the shared list of training days.

**Layout (top → bottom).**
1. Header: eyebrow "MY PROGRAM"; title "Upper / Lower" (800 34px, wdth 108) — hard-coded program name; right side a 44×44 gear button (1.5px 14% border, radius 14, 20px stroked gear icon at 60% ink) → Settings.
2. Row: label "BLOCK · {weeks} WEEKS" (e.g. "BLOCK · 8 WEEKS"); right: two 34×34 stepper buttons "−" and "+" (radius 10).
3. Horizontal scroll of **week chips** (54×58, radius 13, 1.5px border): top text `W{n}` (700 14px tabular), bottom text `{count} DAYS` or `DELOAD` (600 8.5px, 0.08em). Selected chip: ink fill, paper text, sub at 50% paper (orange if deload). Unselected: transparent, 14% border, 55% ink text, sub 35% ink (orange if deload).
4. Row: label `WEEK {n}` or `WEEK {n} · DELOAD` (`weekTitle`); right hint "Tap to assign" (500 11px, 38% ink).
5. **Schedule strip**: 7 equal buttons (min-height 66, radius 11, 1.5px border). Top: weekday letter from `['M','T','W','T','F','S','S']` (600 10px). Bottom: the assigned day's tag (e.g. "UA") or "REST" (700 12px, 0.03em). Assigned: ink fill, paper text, weekday letter at 55% paper. Rest: transparent, 14% border, 35% ink text, weekday 40% ink.
6. Row of three buttons (radius 12, 600 11.5px): `copyPrevLabel` = "First week" (week 1, no-op) or "Copy week {n−1}"; "Apply to later weeks"; "Deload" (toggle — active: bg `rgba(255,91,34,.12)`, border `rgba(255,91,34,.5)`, text `#C63F0F`).
7. Row: label "TRAINING DAYS"; right `daySummary` = "{days} days · {sets} sets a week" (seed: "4 days · 58 sets a week").
8. Helper text "Shared by every week. The schedule above decides which day you train, and when." (400 11.5px, 40% ink).
9. **Training-day cards** (white, radius 18, padding 17): 38×38 paper tile with tag (700 11px, 55% ink) · name (600 15px) · meta "{n} exercises · {sets} sets · ~{min} min" (400 12px, 50% ink) · chip row of up to 4 short exercise names (`CATALOG.sh`, 600 10px on paper, radius 7) plus "+{k}" when more than 4 · chevron "›" (28% ink).
10. Dashed button "+ Add training day" (1.5px dashed 22% ink, radius 18, 600 14px, 55% ink).
11. Tab bar (Program active).

**Data sources.** `weeks = weeksData.length`; `weekChips` from `weeksData` (count = number of non-null schedule slots that point at an existing day); `sched` from `weeksData[curWeek].sched`; `days` from `state.days`; sets per day = Σ(`sets` + 1 if `drop`); minutes per day = round(Σ over exercises of `(sets + drop) × ((sup ? 12 : rest) + 42) / 60`) — i.e. **42 s of work per set** plus the exercise's rest, with a superset member's rest counted as **12 s**.

Seed values: Upper A "5 exercises · 18 sets · ~40 min", Lower A "4 exercises · 15 sets · ~37 min", Upper B "4 exercises · 15 sets · ~37 min", Lower B "3 exercises · 10 sets · ~31 min".

**Interactions.**
- "+" weeks (`weeksUp`): append a week whose schedule is a copy of the last week's, `deload:false`; select the new week. No upper limit in the prototype.
- "−" weeks (`weeksDown`): remove the last week; **minimum 2 weeks**; clamp `curWeek`.
- Week chip tap → `curWeek = i`. `curWeek` is a global "current week" that also drives Today, the watch, and the Day editor's prescription preview.
- Schedule slot tap (`cycle`): cycles `null → day 0 → day 1 → … → day n−1 → null`.
- "Copy week n−1" → copy previous week's `sched` into current week (no-op on week 1).
- "Apply to later weeks" → copy current week's `sched` into every later week (deload flags untouched).
- "Deload" → toggle `weeksData[curWeek].deload`.
- Day card tap → Day editor for that day (`dayIdx`, `openEx:null`).
- "+ Add training day" → append `{ name:'New day', tag:'D{n+1}', ex:[] }` and open it in Day editor.

### 3.3 Settings (v1 only) — `data-screen-label="Settings"`

**Layout (top → bottom).**
1. Back link "‹ Program" (500 13px, 50% ink). Title "Settings" (800 34px).
2. Section "TRAINING" — white card (radius 20, padding 4px 18px), rows separated by 8% hairlines:
   - "Units" / sub "Applies to every log and chart" — segmented control "LB" | "KG" (50×38 each, selected ink fill). State `units ∈ {'lb','kg'}`, default `lb`. **The prototype stores this only; no conversion is applied anywhere.**
   - "Default rest" / sub "Used for new exercises" — value `restDefaultLabel` (700 17px tabular) with 40×40 "−"/"+" buttons. Range **30–300 s, step 15 s**, default **90 s**. Formatting rule `restLbl`: `< 60` → `"45s"`; whole minutes → `"2 min"`; otherwise `"2:30"`.
   - Toggle "Plate math" / "Show the plates per side on each set" (`plateMath`, default on).
   - Toggle "Auto rest timer" / "Start the clock when a set is logged" (`autoRest`, default on).
   - Toggle "Watch haptic at zero" / "Buzz the wrist when rest ends" (`watchBuzz`, default on — **stored but not consulted by any logic in the prototype**).
   Toggle visual: 52×32 track, radius 16, orange when on / 16% ink when off; 26px white knob, `justify-content: flex-end` when on.
3. Section "ACCOUNT" — white card rows with label · value · "›": "Email" → "jd@example.com"; "Apple Health" → "Connected"; "Export data" → "CSV"; "Log out" (orange text, no value). Only "Log out" has behaviour (→ Home). 
4. Footer "Ledger 1.0 · build 214" (400 11.5px, 35% ink).
5. Tab bar (Program active).

### 3.4 Day editor (v1 only) — `data-screen-label="Day editor"`

**Purpose.** Edit one training day's exercise list and each exercise's prescription; manage supersets and drop sets; add exercises from the library.

**Layout (top → bottom).**
1. Fixed header (bottom hairline 10% ink): "‹ Program" · centre eyebrow `dayTag` = "DAY {i} OF {n}" · right pill button "Done" (ink pill, paper 700 12px) — both go back to Program builder.
   Below: editable day name input (800 29px, wdth 108; `onChange` renames the day live) and `dayMeta` = "Week {curWeek+1} · {n} exercises · {sets} sets · ~{min} min".
2. Scroll region of **exercise cards** (white; radius 18 for solo cards; superset members share one visual block — first member `18px 18px 0 0`, middle `0`, last `0 0 18px 18px`, with 1 px gap between members and 10 px between blocks).
   - Superset header on the first member only: "SUPERSET" (700 9px orange) + note "{k} exercises back to back · rest after {letter}" (e.g. "2 exercises back to back · rest after B").
   - Collapsed row (tap toggles expansion): index label `n` (solo: "1"; superset: "4A", "4B"…; 700 11px, 30% ink) · name (600 15px) · sub line · right column: scheme "{sets}×{reps}" (700 14px wdth 110; orange when expanded) and load "{load} lb" (600 11px, 48% ink) · caret "▾"/"▴".
   - Sub line format: `"{equipment} · {progShort}[ · drop] · RPE {rpe} · {rest} rest"`, where the rest segment is `"no rest"` for non-last superset members. `progShort` = `"+{step}/wk"` (linear), `"Reps {reps}–{repsHi}"` (double), `"Fixed"`. Example: "Barbell · +5/wk · RPE 8 · 2:30 rest".
   - Expanded panel (top hairline):
     a. Prescription preview for the currently selected week: eyebrow `weekLabel` = "WEEK {n}" + " · DELOAD" (deload week) or " · HELD" (previous week was a miss) — 700 9px orange; beside it `weekScheme` = "{sets} × {reps} @ {load} lb · RPE {rpe}" (700 15px).
     b. Stepper fields (label 700 9px 42% ink; value 700 19px wdth 110; 44×44 "−"/"+" buttons; 6% hairline separators):

        | Label | Field | Step | Min | Max | Notes |
        |---|---|---|---|---|---|
        | "SETS" | `sets` | 1 | 1 | 12 | |
        | "REPS" (linear/fixed) or "REP FLOOR" (double) | `reps` | 1 | 1 | 30 | Raising `reps` to ≥ `repsHi` pushes `repsHi = reps + 1` |
        | "TOP OF RANGE" (double only) | `repsHi` | 1 | 2 | 40 | Lowering to ≤ `reps` snaps to `reps + 1` |
        | "START LOAD" | `load` | `step` (5 barbell / 2.5 other) | 0 | — | Displayed "{load} lb" |
        | "TARGET RPE" | `rpe` | 0.5 | 5 | 10 | |
        | "REST" | `rest` | 15 s | 30 | 300 | Displayed via `restLbl` |
     c. "PROGRESSION" — three equal chips (min-height 44, radius 11): "Linear" | "Double" | "Fixed" (selected: ink fill). Choosing "Double" sets `repsHi = reps + 2` if it isn't already above `reps`. Explanatory note below (400 11.5px, 52% ink):
        - Linear: "Adds {step} lb a week from {start} lb. A week with a missed set holds the load."
        - Double: "Adds a rep each week up to {repsHi}, then +{step} lb back at {reps}."
        - Fixed: "Stays at {start} lb for the whole block."
     d. "Drop set" row with sub note and toggle. Off: "One extra set at −15% after the last working set." On: "One extra set at −15%, straight after the last working set."
     e. Superset actions (only when applicable; 1.5px border buttons, min-height 44): "Break out" (shown when this exercise is not the first of its group — detaches it from the previous exercise) and "Superset with next" (shown when this exercise is the last of its group and not the last in the day — attaches the next exercise). Both close the expanded panel.
     f. Row: "Move up" | "Move down" | "Remove" (Remove has orange 35% border and orange text). Move keeps the moved card expanded. **Known gap:** moving ignores superset grouping (listed under NEXT STEPS).
3. Dashed button "+ Add exercise from library" → opens picker sheet.

**Exercise library picker sheet** (scrim `rgba(22,21,15,.42)`; sheet 90% height, paper, radius 26 top):
1. Header: "Exercise library" (800 22px) · "Cancel".
2. Search input, placeholder "Search exercises" (white, radius 14). Filter is case-insensitive substring on name.
3. Muscle chips (`MUSCLES` = All, Chest, Back, Shoulders, Legs, Arms; 1.5px border pill; selected ink fill).
4. Equipment chips (`EQUIP` = All, Barbell, Dumbbell, Cable, Machine, Bodyweight; 1px border pill; selected: bg `rgba(255,91,34,.12)`, border `rgba(255,91,34,.5)`, text `#C63F0F`).
5. Scrollable result rows (radius 14, 1.5px border): 36×36 abbreviation tile (`abbr`: BB/DB/CB/MC/BW) · name · meta "{eq} · {mus}" or "{eq} · {mus} · already in this day" (orange when already present) · 26px circle checkbox (orange fill + "✓" when selected). Multi-select.
6. Empty state: "Nothing matches that filter." + "Clear filters" button (resets muscle, equipment, query).
7. Footer CTA: disabled look (bg 10% ink, text 38% ink) "Select exercises to add"; enabled orange "Add 1 exercise" / "Add {n} exercises".

**Add rule.** Each picked catalog entry is appended as: `sets:3, reps:8, rpe:8, rest: settings.restDefault, prog:'linear', repsHi:10, load: W0[name], step: eq==='Barbell' ? 5 : 2.5, misses:[]`. Duplicates are allowed (the "already in this day" hint is only a warning). Sheet closes and clears selection and query (muscle/equipment filters persist).

### 3.5 Today (v1) — `data-screen-label="Today"`

**Purpose.** The daily landing screen: what is scheduled today, start/resume it, week-at-a-glance, weekly stats, recent sessions.

**Layout (top → bottom).**
1. Header: eyebrow `todayDate` = "WEDNESDAY, AUG 19" (hard-coded) · title `todayTitle` = scheduled day's name before " — " (e.g. "Lower A") or "Rest day" · right: 44px ink circle avatar "JD" (700 14px paper).
2. **Week strip**: 7 columns; weekday letter (600 10px, 40% ink) above a 38 px tall rounded tile (radius 9) showing the date number `17 + i` (Aug 17–23). Tile states: `done` (ink fill, paper text), `today` (orange fill, paper text), `plan` (transparent, 20% border), none (transparent, 10% border, 50% ink text). `done` = `doneDow` contains i; `today` = `i === todayDow`; `plan` = week's schedule has a day at i.
3. One of three cards:
   - **Scheduled rest card** (white) when nothing scheduled today: eyebrow "SCHEDULED REST"; title "No session today"; body `restDayNote` = "Nothing scheduled for Wednesday in week {n}. Next up is {Weekday}." (or "…Next up is next Monday."); button "Edit this week" → Program builder.
   - **Logged card** (white) when today's day is scheduled and already logged: eyebrow "LOGGED · WEEK {n}" (orange) with right `loggedMins` (finished elapsed, e.g. "24:22"); title = day name; stats `"{done} of {total} sets · {volume} lb moved"` (or "Logged earlier today" if the receipt isn't in memory); button "View session" → Session receipt; footer `loggedNext` = "Next: {Weekday} · {tag}" (e.g. "Next: Friday · UB") or "Next: week {n+2}".
   - **Up-next card** (ink, paper text) when scheduled and not yet logged: eyebrow `blockLabel` = "UP NEXT · WEEK {n} OF {weeks}" + " · DELOAD" when applicable (orange) with right `todayMins` = "~{min} min"; title = full day name (800 27px); preview rows (name at 82% paper · scheme "{sets} × {reps} @ {load}" tabular, separated by 12% paper hairlines); orange CTA `startLabel` = "Start workout" or "Resume · {m:ss}" (when a live session exists for this week/day) with "→".
     `todayMins` here = round(Σ `p.sets × (p.rest + 42) / 60`) using the week's prescription (note: unlike the Program builder estimate, this ignores drop sets and the superset 12 s rule).
4. Two stat tiles (white, radius 18): "THIS WEEK" → `{sessionsDone}/{sessionsPlanned}` (800 30px wdth 112; denominator 16px 40% ink) + "sessions done"; "VOLUME" → `{volLabel}k` (e.g. "24.2k") + "lb moved · +8%". `sessionsDone = doneDow.length`; `sessionsPlanned` = scheduled slots this week; `volLabel = ((priorVolume + liveVolume)/1000).toFixed(1)`. The "+8%" is hard-coded.
5. "RECENT" card: rows with 34×34 tag tile · name · meta · "›". First row (if a session finished this launch): `{tag}` / `{day name}` / "Today · {m:ss} · {volume} lb" → Session receipt. Then sample rows (→ Exercise history), excluding any whose name equals today's finished day:

   | tag | name | meta |
   |---|---|---|
   | LA | Lower A — Squat focus | Mon · 58 min · 24,180 lb |
   | UB | Upper B — Pull focus | Sun · 49 min · 17,020 lb |
   | LB | Lower B — Hinge focus | Fri · 61 min · 26,400 lb |
6. Tab bar (Today active).

**Interactions.** "Start workout"/"Resume" → `openSession(curWeek, todayDayIdx)`: if a live session for the same week+day exists, resume it (keep `elapsed`, keep logged sets); otherwise build a fresh session from the prescription (§7.3) with `elapsed:0`. Sets `started:true, finished:false, exIdx:0, activeSet:0, rest:0`.

### 3.6 Session receipt (v1 only) — `data-screen-label="Session receipt"`

**Purpose.** Post-workout summary; also reachable later from Today ("View session", RECENT).

**Layout.**
1. Header: eyebrow `recDate` ("WEDNESDAY, AUG 19" hard-coded, or "NO SESSION YET") · title `recDay` (day name, or "Session receipt") · right ink pill "Done" → Today.
2. Three stat tiles: "TIME" (ink tile, orange label) → `m:ss`; "SETS" → "{done}/{total}"; "LB MOVED" → volume with thousands separators (800 23px wdth 112).
3. PR line (700 12px, `#C63F0F`), only when `prs > 0`: "1 new PR this session" / "{n} new PRs this session".
4. Row: "LOGGED" · right hint "Prescribed on the right".
5. White card of exercise rows: name (600 15px) · right target (600 12px, 45% ink) = the prescription before " · " (e.g. "5 × 5 @ 185 lb") · below, chips of actual logged sets (600 12px on paper, radius 7) using run-length grouping: consecutive identical `w×r` collapse to "{n} × {w}×{r}" (e.g. "5 × 185×5"), singletons stay "185×5", none logged → "—".
6. Empty state (no receipt): "Nothing logged yet. Finish a session and the receipt lands here."

No tab bar.

### 3.7 Active workout (v1) — `data-screen-label="Active workout"`

**Purpose.** The live logging screen shared with the watch.

**Layout (top → bottom).**
1. Fixed header (bottom hairline): "‹ Minimize" (→ Today, session stays live) · centre: 6px orange dot + `elapsed` "m:ss" (700 15px tabular) · "Finish" (ink pill) → finish (§7.6).
   Below: eyebrow `workoutDay` = session name; then **progress bars**: one bar per exercise, `flex = sets.length` (so widths are proportional to set count), 4 px tall, radius 2; colour ink for exercises before the current, orange for current, 14% ink for remaining.
2. **Exercise card** (white, radius 22, padding 22/20):
   - Eyebrow `exCounter`: "EXERCISE {i} OF {n}" or, in a superset block, "SUPERSET · BLOCK {b} OF {blocks}".
   - Title `exName` (800 27px wdth 108): exercise name, or in a superset "Round {r} of {n}" where r = the round containing the first undone row.
   - Solo exercises only: 40×40 swap button "⇄" (right of title).
   - Solo only: **TARGET** pill (ink bg, radius 12): "TARGET" orange + `exTarget` = "{sets} × {reps} @ {load} lb · RPE {rpe}" (600 13px paper).
   - Solo only, barbell only, when `plateMath` on and the plate line is non-empty: `exPlates` (500 12px tabular, 62% ink), e.g. "45 + 25 / side".
   - Solo only: **LAST** pill (paper bg): "LAST" + `exLast` (e.g. "Aug 12 · 5×5 @ 180 lb") + ink micro-button "REPEAT" (600 10px, 0.06em).
   - Superset only: **block legend** — one row per member: letter (A/B/…) · name · target scheme; the current member has ink bg with orange letter, others paper bg. Tapping a member makes it current (jumps `exIdx`, `activeSet` = its first undone set). Below: `groupRestLabel` = "Rest {restLbl} after {lastLetter}" (e.g. "Rest 1:15 after B").
   - Column header grid `30px 1fr 1fr 46px`: "#", "LB", "REPS", (blank) — 700 9px 0.12em 38% ink; bottom hairline 10%.
   - **Set rows** (7% hairline between): label `n` (700 13px) · weight (700 21px wdth 110 tabular) · reps (same) · 34×34 check button (radius 10). Row label: solo sets "1","2",…; drop set "D"; in a superset "A1","B1","A2","B2",…, with drop "AD"/"BD". Row states: done → all text dimmed `rgba(22,21,15,.34)`, check button orange fill with white "✓"; active (current exercise + `activeSet`, not done) → label orange, check border ink; drop set label `rgba(255,91,34,.7)`; default label 45% ink, check border 16% ink.
   - Tapping a row body selects it (`exIdx`, `activeSet`). Under the active row a stepper pair appears (paper bg, radius 11): "−" `{wStepLabel}` "+" where `wStepLabel` = "{step} LB" ("5 LB" or "2.5 LB"), and "−" "1 REP" "+".
   - "+ Add set" text button (600 13px, 45% ink).
3. "REMAINING" card (white, radius 18) when exercises remain after the current: rows `n` · name · "{sets} × {reps}" (from first set's reps) · tap → jump to that exercise (first undone set). Name colour: orange for current, dimmed for earlier, ink for later (only later ones are listed).
4. **Rest sheet** (overlay while `rest > 0`; ink bg, radius 26 top, shadow `0 -20px 50px rgba(22,21,15,.28)`): 74 px ring (r = 32, stroke 5, track 16% paper, orange progress, `stroke-dasharray 201`, `stroke-dashoffset = 201 − 201 × rest/restTotal`, rotated −90°) with "m:ss" centred (700 18px); right: "RESTING" (orange), `restNext` = "Set {activeSet+1} · {w} lb × {r}" or "Set {n} · next exercise", caption "Watch will buzz at zero"; buttons "+30s" (outlined 22% paper) and "Skip rest" (orange).
5. **Swap sheet** (overlay; scrim 42% ink; paper sheet radius 26 top): "Swap exercise" · "Cancel"; body "Same movement pattern, equipment you have."; up to 3 alternative rows (white, radius 14): name · sub (e.g. "Similar pattern · 2 × 70 lb") · "USE" (orange 600 11px). Picking replaces the current exercise's **name only** — sets, load, rest, step and slot position are kept.

**Interactions and effects.**
- Check button (`logSet`): toggles `done` on that set. When turning done: set `started=true`, clear `buzz`; if this row is the last of its round (always true for solo rows) and `autoRest` is on and the rest seconds > 0, start rest = the exercise's rest (solo) or the **max rest across the superset members** (group); then advance selection to `nextOf(row)`: the next undone row after this one in display order, else the earliest undone row before it, else the first set of the next block, else stay. Turning a set back to not-done does not advance or start rest.
- Row tap: select (`exIdx`, `activeSet`).
- "−"/"+" weight: select the row, then `w = max(0, w ± step)`. "−"/"+" reps: `r = max(1, r ± 1)`.
- "REPEAT": parse `last` with `/(\d+)×(\d+) @ ([\d.]+)/` and set **every** set of the current exercise to that weight and reps (done flags untouched).
- "+ Add set": append a copy of the last row's `w`/`r` with `done:false` (fallback `{w:0, r:8}` for an empty list). The added set carries no `drop` flag.
- "+30s": `rest += 30; restTotal += 30` (ring re-scales). "Skip rest": `rest = 0; buzz = false`.
- "Finish": see §7.6 → Session receipt. "‹ Minimize": → Today (timer keeps running; Today shows "Resume · m:ss").

### 3.8 Library (v1) — `data-screen-label="Library"`

**Layout.** Title "Library" (800 34px). Static search field (white, radius 14) with "⌕" and placeholder text "Search 214 exercises" (not functional). Filter pills "All", "Chest", "Back", "Legs", "Shoulders", "Arms" (selected: ink fill) — state `filter` is stored but **does not filter the lists** in the prototype. Two sections, each a white card of rows: 38×38 abbreviation tile · name · meta · right PR number (700 14px tabular, 75% ink). Every row → Exercise history. Tab bar (Library active).

| Section | abbr | name | meta | pr |
|---|---|---|---|---|
| RECENTLY LOGGED | BB | Bench Press | Barbell · chest · 34 sessions | 195 |
| RECENTLY LOGGED | BB | Back Squat | Barbell · quads · 41 sessions | 285 |
| RECENTLY LOGGED | DB | Incline DB Press | Dumbbell · chest · 22 sessions | 60 |
| ALL EXERCISES | BB | Barbell Row | Barbell · back | 165 |
| ALL EXERCISES | CB | Cable Lateral Raise | Cable · shoulders | 17.5 |
| ALL EXERCISES | MC | Chest-Supported Row | Machine · back | 80 |
| ALL EXERCISES | BB | Deadlift | Barbell · hamstrings | 365 |
| ALL EXERCISES | CB | Lat Pulldown | Cable · back | 110 |
| ALL EXERCISES | BB | Overhead Press | Barbell · shoulders | 125 |

### 3.9 Exercise history (v1) — `data-screen-label="Exercise history"`

Entirely hard-coded to Bench Press in the prototype (no exercise parameter is passed).

**Layout.**
1. "‹ Library" back link. Eyebrow "BARBELL · CHEST" (orange). Title "Bench Press" (800 36px).
2. Three stat tiles: "1RM EST" (ink tile) → "218"; "BEST SET" → "195" + "×5" (12px, 42% ink); "SESSIONS" → "34".
3. Chart card: header "ESTIMATED 1RM · 8 WEEKS" with right delta "+22 lb" (orange). Bar chart of 8 weeks, 132 px tall region: per bar a value label (700 10px; orange for the last bar, 45% ink otherwise), a bar (`height = 28 + (v − 194) × 2.6` px; orange for the last, 16% ink otherwise; radius 5 top / 2 bottom), and week label "W1"…"W8".
4. "SESSION LOG" card: per session a date (600 13px, 55% ink) · right tag (700 12px; "PR" orange, "+5 lb" 50% ink, "—" 35% ink) · chips of sets "w×r" on paper (radius 7).
5. Tab bar (History active).

Chart values and sessions are listed in §6.9.

### 3.10 v2 screens (dark) — deltas and the Onboarding screen

#### Onboarding (v2 only) — `data-screen-label="Onboarding"`
- Three steps, progress shown as three 2 px bars (orange for steps ≤ current, 12% text-colour otherwise).
- Title (600 38px, wdth 98), body (300 15.5px, 48%), then a single-select list of options separated by 9% hairlines: label (500 16px) + sub (300 12.5px, 36%) + a check icon (stroke orange when selected, transparent otherwise). Default picks `[2, 1, 0]` ("Both, honestly", "4 days", "Upper A · Push focus").
- CTA (orange pill): "Continue" on steps 1–2, "Start training" on step 3 → Today. Text button "Skip setup" → Today at any step. Step content in §6.7.
- The third step ("Your program") presents the four training days as *options with a tick*, although semantically it is a preview of the generated program; the product should clarify (§10).

#### Today (v2)
Same structure with hard-coded content: date "Wednesday, August 19" (sentence case, 400 12px); title "Upper A"; avatar "JD" as a 40px outlined circle; week strip is text-only: weekday (400 11px) + number (500 14px) + 5 px dot (orange today, 50% done, 18% planned, transparent none), seed `M17 done, T18 done, W19 today, T20 —, F21 plan, S22 —, S23 —`; "UP NEXT" (orange 500 10px 0.18em) with "Week 3 of 8 · ~52 min"; "Upper A — Push focus"; preview rows "{scheme} @ {target}" (e.g. "5 × 5 @ 185") from `EXERCISES`; orange pill CTA "Start workout" / "Resume workout · {m:ss}" with an arrow icon; stats "3/4 sessions this week" and "41.2k lb moved · +8%" (the "+8%" in orange); "RECENT" list (same three sample rows, → Exercise history). No rest-day or logged variants. Tab bar dark (3 tabs).

#### Active workout (v2)
Header "Minimize" with chevron icon, elapsed (500 14px), outlined pill "Finish" (→ Today, `finished:true`, no receipt). Progress bars 2 px tall (done 50% text, current orange, remaining 12%). `exCounter` sentence case "Exercise 1 of 5". Swap button always shown (no supersets). No TARGET pill, no plate line. "Last" (300 13px) + value + outlined pill "Repeat". Column headers "#", "lb", "reps" (lowercase, 400 11px, 30%). Numbers 700 24px wdth 90. Check button is a 32 px circle with a check icon (orange fill when done; border 50% when active). Active row's top rule is `rgba(255,91,34,.4)`. Steppers are outlined pills; weight step label always "5 LB". "+ Add set" left-aligned. "REMAINING" list. Rest panel: floating card inset 16 px from the sides and 22 px from the bottom, `rgba(26,26,30,.82)` with 28 px blur, 1px 10% border, radius 26; 64 px ring (r 29, stroke 2.5, dasharray 182); caption "Resting · watch buzzes at zero"; buttons "+30s" (outlined) / "Skip rest" (orange). Swap sheet bg `#131316`, rows as hairline list with "Use" in orange. Weight/reps rules identical (min 0 / min 1); rest always starts on log (no setting).

#### Library (v2)
Same content; search is an outlined pill with a magnifier icon; rows are hairline-separated with no abbreviation tile; PR numbers 700 15px wdth 90 at 72%.

#### Exercise history (v2)
Same content; eyebrow "Barbell · chest" (sentence case); stat labels lowercase "1RM est" (value in orange), "best set", "sessions"; chart bars are 2 px wide lines (`height = 24 + (v − 194) × 2.7` px, orange last / 22% otherwise); session-log sets are plain text (400 13px, 78%) instead of chips.

---

## 4. Watch app spec

Source: `LedgerWatch.dc.html`, a presentational component that receives one `state` object from the phone (§5) and keeps only a local `view` (`null | 'list' | 'end'`).

### 4.1 Display scale and chrome

- Drawn at **1.5× a 46 mm Apple Watch display (208 × 248 pt)**. Divide every pixel value by 1.5 for device points. Smallest label 17 px → **11 pt**; ± buttons 44 px → **29 pt**; the primary CTA is 21 px → 14 pt; the big weight numeral is 64 px → ~43 pt; the rest countdown is 52 px → ~35 pt.
- Prototype chrome: 334 × 406 px case (radius 80, dark gradient), 13 px bezel, inner screen radius 68, screen background `#000`. The Digital Crown (17 × 56 px) sits at the right; it scales to 1.12× while being dragged (`crownScale`). A second side button is decorative.
- The whole screen container gets `animation: buzz .38s ease 3` while `state.buzz` is true (three 0.38 s horizontal shakes — the visual stand-in for a haptic), otherwise `none`.

### 4.2 Mode state machine

`mode` is computed by the **phone** and pushed each render (v1):

```
mode = finishedSummary && finished ? 'summary'
     : !session                    ? 'idle'
     : rest > 0                    ? 'rest'
     : 'ready'
```

(v2 has no idle: `mode = finished ? 'summary' : rest > 0 ? 'rest' : 'ready'`.)

Local overlays exist only while `live = mode ∈ {ready, rest}`:
- `view:'list'` → **session list** (opened by tapping the exercise name on set-ready).
- `view:'end'` → **end-workout confirm** (opened from the list's "End workout").
- Any change of `mode` while the list is showing closes it (`componentDidUpdate`). The end overlay closes only via its own buttons.

```
            ┌──────────────── "Start" (onStart) ────────────────┐
            │                                                    ▼
          idle ◀── onReset ("Done") ── summary ◀── onFinish ── ready ◀──────────────┐
            ▲                                                    │ ▲                │
            └───────────── onDiscard ("Discard") ────────────────┤ │ rest hits 0 /  │
                                                                 │ │ onSkipRest     │
                                        set logged (onLog, last of round, rest>0)   │
                                                                 ▼ │                │
                                                                rest ───────────────┘
   overlays (ready|rest only):  ready/rest ──tap exercise name──▶ list ──"‹"──▶ back
                                list ──"End workout"──▶ end ──"Keep lifting"──▶ list
                                end ──"Save workout"──▶ onFinish → summary
                                end ──"Discard"──▶ onDiscard → idle
```

### 4.3 What each mode displays

**Watch — before workout (`idle`)**
- Top: `weekLabel` (700 17px, 0.09em, orange), e.g. "WEEK 1 OF 8" or "WEEK 8 OF 8 · DELOAD".
- Middle (vertically centred): `dayName` (700 30px wdth 96, max-width 230) e.g. "Lower A — Squat focus" or "Rest day"; `planLine` (600 17px, 55% white) — one of "Nothing scheduled today.", "Logged · {sets} sets · {volume} lb", "Logged earlier today", "{n} exercises · {sets} sets · {first exercise} first", "…· empty day".
- Bottom: if `hasPlan` an orange pill "Start" (600 21px) → `onStart`; otherwise an outlined pill (18% border) showing `nextSessionLine` ("Next: Friday · UB" / "Next: week {n}") — non-interactive.

**Watch — set ready (`ready`)**
- Row 1: `setLabel` (orange 700 17px 0.08em) e.g. "SET 1 OF 5" or "A · SET 2 OF 3" in a superset; right: `elapsed` "m:ss" (50% white).
- Row 2 (button → opens session list): `exName` (600 20px, 90% white, max-width 196) + "›".
- Centre block: weight `w` (700 64px wdth 92, −0.035em, tabular) + "LB" (700 18px, 45%); right of it a row of **set dots** (9 px; orange when done, 22% white otherwise, one per set). Next line: "× {r}" (700 40px wdth 92, 80%) + "REPS" (600 17px, 35%) and right `targetLine` ("RPE 8"; v1 only). Next line: 8 px orange dot + `hr` (700 19px) + "BPM" (600 17px 0.06em, 40%); right: two 44 px circular buttons "−" and "+" → `onRDown` / `onRUp` (reps).
- Bottom: orange pill "Done set" (600 21px) → `onLog`.
- Weight is adjusted with the crown only (no ± buttons for weight on the face).

**Watch — rest timer (`rest`)**
- Title `restTitle` = "REST", or "GO" while `buzz` is true (orange 700 17px 0.1em).
- Centred ring: 196 px, r 88, stroke 9, track 13% white, orange progress `stroke-dasharray 553`, `stroke-dashoffset = 553 − 553 × restFrac`, rotated −90° (full at start, empties as the countdown runs). Inside: `rest` "m:ss" (700 52px wdth 92), 7 px orange dot + `hr` (700 18px, 75%), then `nextLine` (600 17px, 52%, max-width 168) = "Next: {w} lb × {r}" or "Next exercise".
- Bottom: "+30s" (outlined 22% border, 700 18px) → `onAddRest`; "Skip" (orange) → `onSkipRest`.

**Watch — session list (overlay)**
- Header: "‹" (orange) → close; `listLabel` = "{doneExercises} OF {n} DONE" (700 17px 0.08em, 55%).
- Scrollable rows (radius 16, min-height 52; current: bg `rgba(255,91,34,.16)` + orange border; others 14% border): index `n` (orange when current, 35% otherwise) · name (600 18px; 50% when done) · scheme "{sets} × {reps} @ {w}" (600 17px, 40%) · "✓" in orange when the exercise is fully done. Tap → `exList[i].go` (phone jumps to that exercise) and closes the list.
- Bottom: outlined pill "End workout" → end overlay.

**Watch — end workout (overlay)**
- "End workout?" (700 26px wdth 96); `endLine` = "{done} of {total} sets logged · {volume} lb moved" (600 17px, 55%).
- Buttons: "Save workout" (orange, 700 19px) → `onFinish`; "Discard" (outlined, 75% white) → `onDiscard`; "Keep lifting" (text, 45%) → back to list.

**Watch — summary (`summary`)**
- "WORKOUT DONE" (orange 700 17px 0.1em).
- `elapsed` (700 52px wdth 92) with caption "ELAPSED"; row: `setsLine` "{done}/{total}" / "SETS" and `volume` / "LB MOVED"; row: orange dot + `avgHr` / "AVG BPM" and `prs` / "NEW PR" (value orange when > 0, else 55% white). Captions are 600 17px 0.07em at 40%.
- Bottom: outlined pill "Done" → `onReset`.

### 4.4 Interactions summary

| Gesture | Effect (via callback) |
|---|---|
| Crown drag up / down | `onCrownDown` starts a drag; every ≥ 9 px of vertical pointer travel calls the phone's `bumpW(±1 step)` (v1: `exercise.step` = 5 lb barbell / 2.5 lb other; v2: fixed 5 lb). Up = heavier. Applies to the active set. |
| "−" / "+" (set ready) | `onRDown` / `onRUp` → reps ± 1, min 1 |
| "Done set" | `onLog` → phone `logSet(current exercise, active set)` (toggle done; start rest; auto-advance) |
| "+30s" | `onAddRest` → rest += 30, restTotal += 30 |
| "Skip" | `onSkipRest` → rest = 0, buzz = false |
| Tap exercise name | open session list (local) |
| List row | `exList[i].go` → phone sets `exIdx = i`, `activeSet` = first undone set |
| "End workout" → "Save workout" | `onFinish` → phone finish (receipt + summary) |
| "End workout" → "Discard" | `onDiscard` → phone discards session (Today, idle) |
| "Keep lifting" | back to list |
| "Start" (idle) | `onStart` → phone opens today's session |
| "Done" (summary) | `onReset` → `finished = false` → idle |

### 4.5 Haptic / buzz behaviour at rest zero

- The phone tick sets `buzz = true` on the tick where `rest` transitions 1 → 0. At that instant `mode` also flips from `rest` to `ready`, so the wrist shakes on the set-ready screen (three shakes over ~1.1 s). The phone's rest sheet copy promises this: "Watch will buzz at zero" (v1) / "Resting · watch buzzes at zero" (v2).
- `buzz` is cleared when the next set is logged (`onLog`/check) or on "Skip". It is **not** cleared by time; if the user then taps "+30s", the rest screen returns with the title "GO" instead of "REST" while `buzz` is still true — an edge case to resolve in the real app (§10).
- The Settings toggle "Watch haptic at zero" (`watchBuzz`) is intended to gate this but is not wired in the prototype; implement it as the gate.
- Real implementation: a WatchKit haptic (e.g. `.notification` or `.success`) at zero, plus the phone's own haptic; both should honour `watchBuzz`.

---

## 5. Phone ↔ watch shared-state contract

The phone renders the watch by passing one object, `watch`, every time its state changes (`<dc-import name="LedgerWatch" state="{{ watch }}">`). The watch never owns workout state: every mutation is a callback into the phone. This is the live-workout sync surface; in a real app it maps to a bidirectional session channel (WatchConnectivity / shared model) where the phone is the source of truth and the watch sends intents.

### 5.1 Fields pushed phone → watch

| Field | Type | v1 | v2 | Meaning / derivation |
|---|---|---|---|---|
| `mode` | `'idle'|'ready'|'rest'|'summary'` | ✓ | ✓ (no idle) | See §4.2 |
| `weekLabel` | string | ✓ | — | "WEEK {n} OF {weeks}[ · DELOAD]" |
| `dayName` | string | ✓ | — | Today's scheduled day name or "Rest day" |
| `hasPlan` | bool | ✓ | — | A day is scheduled today and not yet logged |
| `planLine` | string | ✓ | — | Idle subtitle (§4.3) |
| `nextSessionLine` | string | ✓ | — | "Next: {Weekday} · {tag}" or "Next: week {n}" |
| `exName` | string | ✓ | ✓ | Current exercise name (post-swap name) |
| `setLabel` | string | ✓ | ✓ | "[{letter} · ]SET {activeSet+1} OF {sets}" |
| `targetLine` | string | ✓ | — | "RPE {rpe}" |
| `setDots` | `{bg}[]` | ✓ | — | One per set of the current exercise; orange when done |
| `exList` | `{n,name,scheme,done,cur,go}[]` | ✓ | — | Session list rows; `name` prefixed "{letter} · " in supersets; `scheme` = "{sets} × {reps} @ {w}" from the first set; `done` = all sets done; `cur` = is current; `go()` callback |
| `nextLine` | string | ✓ | — | "Next: {w} lb × {r}" for the active row, else "Next exercise" |
| `w` | number | ✓ | ✓ | Active set weight (v2 falls back to the last set if `activeSet` overflows) |
| `r` | number | ✓ | ✓ | Active set reps |
| `rest` | string | ✓ | ✓ | "m:ss" remaining |
| `restFrac` | number 0–1 | ✓ | ✓ | `rest / max(1, restTotal)` |
| `hr` | number | ✓ | ✓ | Live heart rate (sample random walk); after finish, the value captured at finish |
| `buzz` | bool | ✓ | ✓ | Rest just hit zero (§4.5) |
| `elapsed` | string | ✓ | ✓ | "m:ss" workout time (frozen to the finished value on summary) |
| `doneCount` | number | ✓ | ✓ | Logged sets across the session |
| `totalSets` | number | ✓ | ✓ | All sets across the session (incl. drop sets and added sets) |
| `volume` | string | ✓ | ✓ | Σ w×r of done sets, formatted with thousands separators |
| `prs` | number | ✓ | — | PR count from the finished summary (0 while live) |
| `crownDrag` | bool | ✓ | ✓ | Crown currently being dragged (visual only) |

### 5.2 Callbacks invoked watch → phone

| Callback | v1 | v2 | Phone behaviour |
|---|---|---|---|
| `onStart()` | ✓ | — | Open (or resume) today's scheduled session; watch goes `idle → ready` |
| `onLog()` | ✓ | ✓ | `logSet(current exercise, active set)` with default options: toggles done; on done → start rest = **that exercise's** rest (if `autoRest`), advance to the next undone set of the same exercise, else first set of the next exercise. **Note:** unlike the phone's check button, this path is not superset-aware (no group rest, no round-robin) — see §10. |
| `onAddRest()` | ✓ | ✓ | `rest += 30; restTotal += 30` |
| `onSkipRest()` | ✓ | ✓ | `rest = 0; buzz = false` |
| `onWUp()` / `onWDown()` | ✓ | ✓ | Active set weight ± step (min 0). Not bound to any watch control in the current face; available for a future ± affordance. |
| `onRUp()` / `onRDown()` | ✓ | ✓ | Active set reps ± 1 (min 1) |
| `onCrownDown(pointerEvent)` | ✓ | ✓ | Begin crown drag; subsequent moves call weight ± step per 9 px |
| `onFinish()` | ✓ | — | Same as phone "Finish" (§7.6); watch → summary |
| `onDiscard()` | ✓ | — | Drop the live session: `session=null, started=false, finished=false, finishedSummary=null, elapsed=0, rest=0, exIdx=0, activeSet=0`, phone → Today; watch → idle |
| `onReset()` | ✓ | ✓ | `finished = false` → leaves summary (v1 → idle; v2 → ready) |
| `exList[i].go()` | ✓ | — | `exIdx = i; activeSet = max(0, first undone set)` |

### 5.3 Sync semantics to preserve

- **Single source of truth:** all set values, done flags, rest countdown and elapsed time live on the phone; the watch mirrors them. Logging on either device must be reflected on the other within one tick.
- **Rest timer is shared:** starting, extending (+30s) and skipping on one device apply to both. The countdown is phone-driven in the prototype; a real app should anchor both devices to a shared end timestamp so they agree after backgrounding.
- **Selection is shared:** `exIdx`/`activeSet` are one cursor for both devices; jumping from the watch list moves the phone's active row and vice versa.
- **Idle / summary are phone-derived:** the watch can start a session only when the phone reports `hasPlan`.

---

## 6. Domain model implied by the prototype

### 6.1 Entities

**User / Account** — email (sample "jd@example.com"), avatar initials ("JD"), Apple Health connection state ("Connected"), units preference (`lb` | `kg`), `restDefault` (s), `plateMath`, `autoRest`, `watchBuzz`.

**Program (block)** — name (hard-coded "Upper / Lower"), `weeks[]` (ordered; min 2), `days[]` (training-day templates shared by every week). Onboarding (v2) also implies `goal` and `daysPerWeek` choices attached to the user/program.

**Week** — `sched[7]`: for each weekday Mon…Sun either a day index or `null` (rest); `deload: bool`.

**Training day (session template)** — `name` (e.g. "Upper A — Push focus"; the part before " — " is the short title), `tag` (2-letter code "UA"/"LA"/"UB"/"LB", or "D{n}" for added days), `ex[]` ordered exercise slots.

**Exercise slot (in a day)** — `c` (catalog index / exercise id), `sets` 1–12, `reps` 1–30, `repsHi` 2–40 (top of the double-progression range), `rpe` 5–10 step 0.5, `rest` 30–300 s step 15, `prog` `'linear'|'double'|'fixed'`, `load` (start load, lb), `step` (5 for Barbell, 2.5 otherwise), `misses[]` (week indices where the slot was missed), `sup: bool` (true = superset with the previous slot), `drop: 0|1` (carry one drop set).

**Exercise (catalog)** — `name`, `eq` equipment (Barbell | Dumbbell | Cable | Machine | Bodyweight), `mus` muscle group (Chest | Back | Shoulders | Legs | Arms), `abbr` (BB/DB/CB/MC/BW), `sh` short display name, starting load `W0`, `alts[]` (swap alternatives: `name`, `sub`), plus history-derived `last` line, PR/best set, sessions count, e1RM series. Library rows additionally show finer muscles ("quads", "hamstrings").

**Prescription (derived)** — for (week, slot): `load`, `sets`, `reps`, `rpe`, `rest`, `step`, `prog`, `held`, `deload` (§7.2).

**Workout (session instance)** — `week`, `day`, `name`, `tag`, `deload`, `ex[]` of session exercises, `started`, `elapsed` (s), `finished`; plus heart-rate samples.

**Session exercise** — `c`, `name` (mutable via swap), `rest`, `step`, `rpe`, `eq`, `sup`, `targetSets`, `targetReps`, `target` (display string), `last` (display string), `sets[]`.

**Logged set** — `w` (weight), `r` (reps), `done: bool`, `drop?: true`.

**Finished summary / receipt** — `elapsed` ("m:ss"), `done`, `total`, `volume`, `hr`, `prs`, `day`, `tag`, `date`, `rows[] {name, target, actual[]}`.

**History (per exercise)** — sessions `{date, tag ('PR' | '+5 lb' | '—'), sets[] 'w×r'}`, `e1RM[]` per week, best set, sessions count, 1RM estimate.

**Weekly stats** — `sessionsDone`, `sessionsPlanned`, `volume` (prior + live), week-over-week delta ("+8%").

### 6.2 Exercise catalog (`CATALOG`, 22 entries) with starting loads (`W0`, lb)

| # | name | eq | mus | abbr | sh | W0 | step |
|---|---|---|---|---|---|---|---|
| 0 | Barbell Bench Press | Barbell | Chest | BB | BENCH | 180 | 5 |
| 1 | Incline DB Press | Dumbbell | Chest | DB | INCLINE | 50 | 2.5 |
| 2 | Low-to-High Cable Fly | Cable | Chest | CB | FLY | 25 | 2.5 |
| 3 | Weighted Dip | Bodyweight | Chest | BW | DIP | 45 | 2.5 |
| 4 | Barbell Row | Barbell | Back | BB | ROW | 155 | 5 |
| 5 | Chest-Supported Row | Machine | Back | MC | CS ROW | 65 | 2.5 |
| 6 | Lat Pulldown | Cable | Back | CB | PULLDOWN | 100 | 2.5 |
| 7 | Weighted Pull-Up | Bodyweight | Back | BW | PULL-UP | 35 | 2.5 |
| 8 | Overhead Press | Barbell | Shoulders | BB | OHP | 115 | 5 |
| 9 | Cable Lateral Raise | Cable | Shoulders | CB | LATERAL | 12.5 | 2.5 |
| 10 | Rear Delt Fly | Machine | Shoulders | MC | REAR DELT | 50 | 2.5 |
| 11 | Back Squat | Barbell | Legs | BB | SQUAT | 250 | 5 |
| 12 | Front Squat | Barbell | Legs | BB | FRONT SQ | 185 | 5 |
| 13 | Romanian Deadlift | Barbell | Legs | BB | RDL | 205 | 5 |
| 14 | Deadlift | Barbell | Legs | BB | DEADLIFT | 315 | 5 |
| 15 | Leg Press | Machine | Legs | MC | LEG PRESS | 320 | 2.5 |
| 16 | Seated Leg Curl | Machine | Legs | MC | LEG CURL | 90 | 2.5 |
| 17 | Standing Calf Raise | Machine | Legs | MC | CALF | 160 | 2.5 |
| 18 | Barbell Curl | Barbell | Arms | BB | CURL | 75 | 5 |
| 19 | Incline DB Curl | Dumbbell | Arms | DB | DB CURL | 30 | 2.5 |
| 20 | Cable Triceps Pushdown | Cable | Arms | CB | PUSHDOWN | 60 | 2.5 |
| 21 | Overhead Cable Extension | Cable | Arms | CB | OH EXT | 45 | 2.5 |

Filter vocabularies: `MUSCLES = ['All','Chest','Back','Shoulders','Legs','Arms']`; `EQUIP = ['All','Barbell','Dumbbell','Cable','Machine','Bodyweight']`; Library tab filter order `['All','Chest','Back','Legs','Shoulders','Arms']`; `DOW = ['M','T','W','T','F','S','S']`.

### 6.3 Sample exercise metadata (`EXERCISES`, identical in v1 and v2)

In v2 these five entries *are* the workout. In v1 they supply only the `last` line and `alts` for the matching catalog exercise (the `scheme`/`target`/`reps`/`rest` columns are superseded by the day template and `W0`; note the v2 `target` 185 vs the v1 week-1 load 180).

| name | scheme | target | reps | rest (s) | last |
|---|---|---|---|---|---|
| Barbell Bench Press | 5 × 5 | 185 | 5 | 150 | Aug 12 · 5×5 @ 180 lb |
| Incline DB Press | 3 × 10 | 55 | 10 | 90 | Aug 12 · 3×10 @ 50 lb |
| Chest-Supported Row | 4 × 8 | 70 | 8 | 90 | Aug 12 · 4×8 @ 65 lb |
| Lat Pulldown | 3 × 12 | 100 | 12 | 75 | Aug 12 · 3×12 @ 100 lb |
| Cable Lateral Raise | 3 × 15 | 15 | 15 | 60 | Aug 12 · 3×15 @ 12.5 lb |

Alternatives (`alts`, shown in the Swap sheet):

| exercise | alt name | alt sub |
|---|---|---|
| Barbell Bench Press | Dumbbell Bench Press | Similar pattern · 2 × 70 lb |
| Barbell Bench Press | Smith Machine Press | Machine · bench occupied? |
| Barbell Bench Press | Weighted Dip | Bodyweight + 45 lb |
| Incline DB Press | Incline Barbell Press | Barbell · 135 lb |
| Incline DB Press | Machine Incline Press | Machine · 120 lb |
| Incline DB Press | Low-to-High Cable Fly | Cable · 25 lb |
| Chest-Supported Row | Seated Cable Row | Cable · 130 lb |
| Chest-Supported Row | Single-Arm DB Row | Dumbbell · 80 lb |
| Chest-Supported Row | Barbell Row | Barbell · 155 lb |
| Lat Pulldown | Assisted Pull-Up | Machine · −40 lb |
| Lat Pulldown | Neutral-Grip Pulldown | Cable · 95 lb |
| Lat Pulldown | Straight-Arm Pulldown | Cable · 45 lb |
| Cable Lateral Raise | DB Lateral Raise | Dumbbell · 2 × 15 lb |
| Cable Lateral Raise | Machine Lateral Raise | Machine · 50 lb |
| Cable Lateral Raise | Upright Row | Cable · 60 lb |

For catalog exercises without curated alts, v1 generates up to 3 alternatives: other catalog entries with the same muscle group, `sub = "{eq} · {W0} lb"`.

### 6.4 Seed program: training days (`DAYS`)

Slots are created by `mk(name, sets, reps, rpe, rest)` → `prog:'linear', repsHi: reps+2, load: W0[name], step: 5|2.5, misses:[]`, then overridden: `prog:'double'` for Incline DB Press, Lat Pulldown, Cable Lateral Raise, Leg Press, Seated Leg Curl, Barbell Curl; `prog:'fixed'` for Standing Calf Raise; `sup:true` on Upper A slot 5 and Lower A slot 4; `drop:1` on Upper B slot 4.

| day (tag) | # | exercise | sets | reps | repsHi | rpe | rest | prog | load | step | flags |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Upper A — Push focus (UA) | 1 | Barbell Bench Press | 5 | 5 | 7 | 8 | 150 | linear | 180 | 5 | |
| | 2 | Incline DB Press | 3 | 10 | 12 | 8 | 90 | double | 50 | 2.5 | |
| | 3 | Chest-Supported Row | 4 | 8 | 10 | 8 | 90 | linear | 65 | 2.5 | |
| | 4 | Lat Pulldown | 3 | 12 | 14 | 9 | 75 | double | 100 | 2.5 | superset A |
| | 5 | Cable Lateral Raise | 3 | 15 | 17 | 9 | 60 | double | 12.5 | 2.5 | superset B (`sup`) |
| Lower A — Squat focus (LA) | 1 | Back Squat | 5 | 5 | 7 | 8 | 180 | linear | 250 | 5 | |
| | 2 | Romanian Deadlift | 3 | 8 | 10 | 8 | 120 | linear | 205 | 5 | |
| | 3 | Leg Press | 3 | 12 | 14 | 9 | 90 | double | 320 | 2.5 | superset A |
| | 4 | Standing Calf Raise | 4 | 12 | 14 | 9 | 60 | fixed | 160 | 2.5 | superset B (`sup`) |
| Upper B — Pull focus (UB) | 1 | Weighted Pull-Up | 4 | 6 | 8 | 8 | 150 | linear | 35 | 2.5 | |
| | 2 | Overhead Press | 4 | 6 | 8 | 8 | 120 | linear | 115 | 5 | |
| | 3 | Barbell Row | 3 | 10 | 12 | 8 | 90 | linear | 155 | 5 | |
| | 4 | Barbell Curl | 3 | 12 | 14 | 9 | 60 | double | 75 | 5 | drop set |
| Lower B — Hinge focus (LB) | 1 | Deadlift | 4 | 4 | 6 | 8 | 210 | linear | 315 | 5 | |
| | 2 | Front Squat | 3 | 8 | 10 | 8 | 120 | linear | 185 | 5 | |
| | 3 | Seated Leg Curl | 3 | 12 | 14 | 9 | 75 | double | 90 | 2.5 | |

Seed schedule (weeks 1–7): Mon UA · Tue rest · Wed LA · Thu rest · Fri UB · Sat LB · Sun rest. Week 8: Mon UA · Wed LA · Fri UB, `deload:true`.

### 6.5 Week strip seed (Today)

v1 (computed): dates Aug 17–23; `todayDow = 2` (Wed 19); `doneDow = [0]` (Mon 17 done); planned = schedule slots.

v2 (hard-coded): `M 17 done · T 18 done · W 19 today · T 20 — · F 21 plan · S 22 — · S 23 —`.

### 6.6 Weekly stats seed

v1: `priorVolume = 24180` → "24.2k" (+ live volume), `sessionsDone = 1` of `4` planned. v2: "3/4 sessions this week", "41.2k lb moved · +8%". Both show "+8%" as static copy.

### 6.7 Onboarding steps (`ONB`, v2)

| step | title | body | cta | options (label — sub) |
|---|---|---|---|---|
| 1 | What are you training for? | This sets how Ledger progresses your loads week to week. | Continue | Get stronger — Low reps, linear load increases · Build muscle — Moderate reps, volume tracking · Both, honestly — Barbell strength + accessory volume · Stay consistent — Habit first, numbers second |
| 2 | How many days a week? | Pick the number you will actually hit, not the one you want to hit. | Continue | 3 days — Full body each session · 4 days — Upper / lower split · 5 days — Push, pull, legs + accessories · 6 days — Body-part split |
| 3 | Your program | Upper / Lower, 8 weeks, pounds. Editable any time. | Start training | Upper A · Push focus — Bench, incline, row, pulldown, laterals · Lower A · Squat focus — Squat, RDL, leg press, calves · Upper B · Pull focus — Weighted pull-up, OHP, row, curls · Lower B · Hinge focus — Deadlift, front squat, hamstring, abs |

Secondary action on every step: "Skip setup". Default selections: step 1 "Both, honestly", step 2 "4 days", step 3 "Upper A · Push focus". The picks are stored (`onbPick`) but do not alter the generated program in the prototype.

### 6.8 Library sections

See the table in §3.8 (identical content in v1 and v2; v2 omits the `abbr` tile).

### 6.9 Exercise history sample (Bench Press)

Stats: 1RM EST **218**, BEST SET **195×5**, SESSIONS **34**, chart delta **"+22 lb"** over 8 weeks.

Chart values (`chartVals`, estimated 1RM per week): 

| W1 | W2 | W3 | W4 | W5 | W6 | W7 | W8 |
|---|---|---|---|---|---|---|---|
| 196 | 199 | 203 | 201 | 208 | 211 | 214 | 218 |

Session log:

| date | tag | sets |
|---|---|---|
| Aug 12 | PR | 180×5, 180×5, 180×5, 180×5, 180×5 |
| Aug 5 | +5 lb | 175×5, 175×5, 175×5, 175×5, 175×4 |
| Jul 29 | — | 175×5, 175×5, 175×5, 175×5 |
| Jul 22 | +5 lb | 170×5, 170×5, 170×5, 170×5, 170×5 |

Interpretation implied by the tags: "+5 lb" marks a session whose load rose from the previous session; "—" marks a repeat at the same load (here also one fewer set); "PR" marks a new best. The receipt's "LB MOVED" and the Today "RECENT" rows use the same volume definition (§7.7).

### 6.10 Recent sessions sample

See §3.5 (Lower A / Upper B / Lower B rows with "Mon · 58 min · 24,180 lb" etc.).

---

## 7. Business rules implied by the prototype

Numbered for reference. "v1" rules are the working behaviour; v2 differences are flagged.

### 7.1 Editing limits and steps

1. Weight step per exercise = **5 lb for Barbell, 2.5 lb for every other equipment** (`step`); v2 uses a flat 5 lb. Minimum logged weight **0**.
2. Reps step **1**, minimum **1** (logged sets). Template reps 1–30; `repsHi` 2–40 and always > `reps` (auto-corrected).
3. Sets per slot 1–12. Target RPE 5–10 in 0.5 steps. Rest 30–300 s in 15 s steps; default rest for new slots = Settings "Default rest" (default 90 s, same 30–300/15 range).
4. Block length: minimum 2 weeks; no maximum. New weeks copy the previous week's schedule and are not deload.
5. Schedule slot cycling order: rest → day 1 → day 2 → … → last day → rest.
6. Start load stepper: ± `step`, minimum 0.
7. New exercise defaults: 3 × 8 @ RPE 8, rest = default rest, linear, `repsHi` 10, load = catalog `W0`.
8. Added training day: name "New day", tag "D{n}" where n = new count, empty exercise list.

### 7.2 Progression (`presc(weekIdx, slot)`)

```
adv   = number of weeks i < weekIdx that are NOT in slot.misses     // "advancement count"
start = slot.load ?? W0[slot]; step = slot.step ?? (Barbell ? 5 : 2.5)
linear:  load = start + step × adv;                     reps = slot.reps
double:  span = max(1, repsHi − reps + 1)
         load = start + step × floor(adv / span);       reps = slot.reps + (adv mod span)
fixed:   load = start;                                  reps = slot.reps
sets = slot.sets; rpe = slot.rpe; rest = slot.rest
held  = (weekIdx − 1) ∈ slot.misses                     // display flag " · HELD"
if week.deload: load = round(load × 0.85 / 5) × 5; sets = max(1, sets − 1); rpe = max(5, rpe − 2)
```

9. **Linear**: +`step` per successfully completed prior week. A missed week does not advance (the load "holds"): copy "A week with a missed set holds the load."
10. **Double progression**: reps climb one per week from `reps` to `repsHi`; when the range is exhausted the load rises by `step` and reps reset to `reps`. Example (Incline DB Press 10–12, step 2.5, start 50): W1 50×10, W2 50×11, W3 50×12, W4 52.5×10.
11. **Fixed**: load constant for the block.
12. **Deload week**: load × 0.85 rounded to the nearest 5 lb, one fewer set (min 1), RPE −2 (min 5). Example: Back Squat W8 = 250 + 5×7 = 285 → 240 lb, 4 × 5 @ RPE 6.
13. **Miss tracking** (on Finish): a slot is "missed" for the session's week if fewer sets were logged than `targetSets`, or any logged set's reps < `targetReps`. Missed → add the week to `misses`; not missed → remove it if present. Drop sets and extra added sets count toward "logged sets" (they are done sets), so a drop set can mask a missed working set — see §10.

### 7.3 Building a session (`buildSession(week, day)`)

14. For each slot: prescription `p` → session exercise with `target = "{sets} × {reps} @ {load} lb · RPE {rpe}"`, `last` = curated `EXERCISES.last` or synthetic `"Aug 12 · {sets}×{reps} @ {load − step} lb"`, and `sets` = `p.sets` rows of `{w: p.load, r: p.reps, done:false}`.
15. If the slot has a drop set, append one extra row `{w: round(p.load × 0.85 / 5) × 5, r: p.reps, done:false, drop:true}` — "One extra set at −15% after the last working set."
16. Superset flag, rest, step, rpe, equipment, `targetSets`, `targetReps` are copied onto the session exercise so later edits to the template don't alter a live session.
17. Resume rule: starting Today's session when a live session for the same week + day already exists resumes it (elapsed and logged sets preserved). A different week/day builds a new session and discards the old one.

### 7.4 Logging and auto-advance (`logSet`, `nextOf`)

18. Ticking a set toggles `done`. Only the not-done → done transition has side effects: `started = true`, `buzz = false`, optional rest start, cursor advance.
19. **Rest start**: if `autoRest` is on (v1; always in v2) and the applicable rest > 0, `rest = restTotal = secs`. Solo exercise: `secs = exercise.rest`. Superset (phone check button): rest only when the ticked row is the **last member of its round**; `secs = max(rest of all members)`. Copy: "only rests once the last exercise in the round is done."
20. **Cursor advance** (phone check button): next undone row later in display order → else earliest undone row earlier → else first set of the next block → else stay. Display order for a superset is round-major: A1, B1, A2, B2, …, then drop rows (`AD`, `BD`) as their own round.
21. **Cursor advance** (watch "Done set" / default path): next undone set of the same exercise → else first set of the next exercise → else stay. Rest = that exercise's own rest.
22. Un-ticking a set never moves the cursor or stops the rest timer.
23. Rest countdown: −1 s per second; at 1 → 0 set `buzz = true`. "+30s" adds 30 to both `rest` and `restTotal` (ring rescales). "Skip" zeroes rest and clears buzz.
24. Elapsed time counts from the first "Start"/"Resume" and pauses only when the session is finished or discarded (minimising does not pause).

### 7.5 In-session edits

25. **REPEAT** ("Repeat last"): parse the `last` string `"{sets}×{reps} @ {weight}"` and write that weight and reps into **all** sets of the current exercise (including drop and added sets; done flags unchanged).
26. **+ Add set**: duplicate the last row's weight/reps as a new undone set (no drop flag). Progress-bar widths, `totalSets`, watch dots and list schemes update accordingly.
27. **Swap exercise**: replaces the name in the current slot; sets, rest, step, RPE, target string and `last` line remain those of the original exercise. Alternatives are curated (`alts`) or same-muscle catalog entries. Swap is unavailable inside a superset block in v1 (button hidden).
28. Stepper edits apply to the selected (active) row only; tapping a stepper first selects that row.

### 7.6 Finishing (`finish`)

29. `prs` = number of session exercises with at least one done set whose weight exceeds the catalog starting load `W0` (a naive PR rule — see §10).
30. Receipt rows: `target` = prescription string before " · " (e.g. "5 × 5 @ 185 lb"); `actual` = run-length-grouped done sets ("{n} × {w}×{r}" when n > 1, else "{w}×{r}"), or "—" if none.
31. Side effects: update `misses` (rule 13); `screen = receipt`; `finished = true`; `rest = 0`; `started = false`; `finishedSummary = {elapsed, done, total, volume, hr, prs, day, tag, date, rows}`; mark today as done (`doneDow += todayDow`); `priorVolume += volume`; clear `session`; `elapsed = 0`.
32. Discard (watch "Discard"): drop the session with no receipt, no `doneDow` change, no volume change.
33. v2 "Finish" simply returns to Today with `finished = true` (watch summary), no receipt or persistence.

### 7.7 Derived numbers and formatting

34. **Volume** ("lb moved") = Σ over done sets of `w × r`. Formatted with thousands separators ("24,180"); the Today tile shows `(priorVolume + live volume) / 1000` to one decimal plus "k".
35. **Weekly sessions** = `doneDow.length` / number of scheduled slots in the current week.
36. **Progress bars** (workout header): one segment per exercise with width ∝ set count (`flex = sets.length`), coloured done / current / remaining.
37. **Time estimates**: Program builder/day meta = round(Σ (sets + drop) × ((sup ? 12 : rest) + 42) / 60) min; Today card = round(Σ p.sets × (p.rest + 42) / 60) min. 42 s is the assumed work time per set.
38. **Plate math** (`plateLine(load)`): per side = (load − 45) / 2 (45 lb bar). If per side < 2.5 → no line. Greedy fill with 45, 25, 10, 5, 2.5; output "{n}×{p}" for multiples, "{p}" for singles, joined by " + ", suffixed " / side". Examples: 185 → "45 + 25 / side"; 180 → "45 + 2×10 + 2.5 / side"; 250 → "2×45 + 10 + 2.5 / side". Shown only for Barbell exercises when "Plate math" is on.
39. **Rest label** (`restLbl`): "{s}s" under 60 s; "{m} min" for whole minutes; "m:ss" otherwise. Countdown always "m:ss".
40. **Estimated 1RM**: the prototype hard-codes 218 for a 195×5 best set, which matches the Brzycki formula (195 × 36 / (37 − 5) ≈ 219) far better than Epley (227.5). The formula is not specified — decide in §10. The 8-week chart is "ESTIMATED 1RM · 8 WEEKS" with delta = last − first (218 − 196 = "+22 lb").
41. **History tags**: "PR" (new best), "+{step} lb" (load increase vs previous session), "—" (no change).
42. **"Week n of N"**: `curWeek + 1` of `weeks.length`, with " · DELOAD" suffix on deload weeks; v2 hard-codes "Week 3 of 8".
43. **"lb moved · +8%"**: week-over-week volume change; hard-coded in both prototypes.
44. **Superset labelling**: members lettered A, B, C, D, E (`LET`); day-editor indices "4A"/"4B"; live rows "A1", "B1", drop rows "AD"; watch set label "A · SET 2 OF 3".
45. **Session name parsing**: Today title = name before " — "; tags are 2-letter codes shown in tiles.
46. **Today logic**: `todayDayIdx = week.sched[todayDow]`; scheduled & not logged → Up-next card; scheduled & logged → Logged card; not scheduled → Rest card. "Next:" lines look forward within the current week, else "Next: week {n+2}".

---

## 8. Design tokens

### 8.1 Colour — v1 light ("paper / ink / one accent")

| Token | Value | Use |
|---|---|---|
| `paper` | `#EFEDE6` | Screen background, tiles inside white cards, inverse text on ink, chips |
| `ink` | `#16150F` | Primary text, filled buttons/pills, selected chips, ink cards (Up-next, TIME/1RM tiles, TARGET pill, rest sheet) |
| `card` | `#FFFFFF` | Cards, inputs, selected segment |
| `accent` | `#FF5B22` | Orange accent (see usage rule) |
| `accentDeep` | `#C63F0F` | Orange **text** on light backgrounds (PR line, active Deload/equipment chip text) |
| `accentTint` | `rgba(255,91,34,.12)` | Active Deload button / equipment chip background |
| `accentBorder` | `rgba(255,91,34,.5)` | Active Deload / equipment chip border |
| `accentBorderSoft` | `rgba(255,91,34,.35)` | "Remove" button border |
| `accentMuted` | `rgba(255,91,34,.7)` | Drop-set row label |
| `scrim` | `rgba(22,21,15,.42)` | Sheet backdrop |
| `restSheetShadow` | `0 -20px 50px rgba(22,21,15,.28)` | Rest sheet |

Ink alphas (text and controls on paper/white) — `rgba(22,21,15, α)`:
- Hairlines/borders: `.06` (field separators), `.07` (set rows), `.08` (list rows), `.10` (header rules, tab bar), `.12` (chip borders, dividers), `.14` (button borders, unselected chips), `.16` (secondary button borders, toggle-off track, unchecked box), `.20` (planned day tile), `.22` (dashed add buttons).
- Muted text: `.28` (chevrons), `.30`/`.32` (row indices), `.34` (dimmed done rows — `dim`), `.35`, `.38` (column headers, hints), `.40`, `.42` (section labels), `.45`, `.48`, `.50` (metadata), `.52`, `.55`, `.58`, `.60` (body/secondary), `.62`, `.68`, `.70`, `.75`.
- Fills: `.07` (segmented track), `.10` (disabled CTA).

Paper alphas on ink surfaces — `rgba(239,237,230, α)`: `.12` (preview hairline), `.16` (rest ring track), `.22` (outlined "+30s"), `.5` (meta), `.55` (weekday on schedule), `.62`, `.82` (preview names), `.9` (rest next-set line).

### 8.2 Colour — v2 dark ("two greys and a hairline")

| Token | Value | Use |
|---|---|---|
| `pageBg` | `#08080A` | Prototype canvas |
| `ground` | `#0B0B0D` | Screen background (`GROUND`) |
| `sheet` | `#131316` | Swap sheet |
| `glass` | `rgba(26,26,30,.82)` + `backdrop-filter: blur(28px)` | Rest card |
| `text` | `#F4F2ED` | Primary text (`TEXT`) |
| `dim` | `rgba(244,242,237,.28)` | Done rows (`DIM`) |
| `line` | `rgba(244,242,237,.08)` | Default hairline (`LINE`) |
| `accent` | `#FF5B22` | Once per screen |
| `accentLine` | `rgba(255,91,34,.4)` | Active set row top rule |
| `scrim` | `rgba(8,8,10,.7)` + blur 8px | Sheet backdrop |
| `shadow` | `0 24px 60px rgba(0,0,0,.55)` | Rest card |

Text alphas — `rgba(244,242,237, α)`: borders `.08`, `.09`, `.10`, `.12`, `.13`, `.14`, `.16`, `.18`; text `.26`, `.28`, `.30`, `.32`, `.34`, `.36`, `.38`, `.40`, `.42`, `.45`, `.48`, `.50`, `.55`, `.60`, `.70`, `.72`, `.75`, `.78`, `.85`. Tab bar: `rgba(11,11,13,.86)` blur 20 px, inactive icon `rgba(244,242,237,.34)`.

### 8.3 Colour — watch (both versions)

Screen `#000`; text `#fff`; white alphas: `.13` (ring track), `.14` (list row border), `.18`/`.20`/`.22` (outlined buttons), `.35`, `.4`, `.45`, `.5`, `.52`, `.55`, `.75`, `.8`, `.9`; set-dot off `rgba(255,255,255,.22)`; current list row `rgba(255,91,34,.16)` with `#FF5B22` border; accent `#FF5B22`.

### 8.4 Accent usage rule

- v1: orange is the *action and status* colour — primary CTAs ("Log in", "Start workout", "Skip rest", "Add N exercises"), the live-timer dot, the current progress segment, the rest ring, done checkmarks, "today" in the week strip, toggles-on, and eyebrow labels that mark the live/next thing ("UP NEXT", "TARGET", "RESTING", "SUPERSET", "LOGGED · WEEK n"). Orange text on paper uses `#C63F0F` for contrast.
- v2: **"Orange appears once per screen, on the thing you are about to touch. Everywhere else it is a one-pixel rule."** Practically: one orange CTA/ring per screen, the eyebrow "UP NEXT", the "+8%" delta, "1RM est" value, the tab icon, and the current progress segment; everything else is text-alpha or hairline.

### 8.5 Typography

Font: **Archivo** (variable), loaded from Google Fonts. v1 axes `ital,wdth,wght@0,62..125,400..900`; v2 `0,62..125,300..900`. Fallback `system-ui, sans-serif`. Numbers everywhere use `font-variant-numeric: tabular-nums`.

v1 roles (weight size/line-height, `'wdth'`, letter-spacing):

| Role | Spec |
|---|---|
| Prototype hero | 800 76px/.92, wdth 112, −.03em |
| Screen title (Program, Settings, Library) | 800 34px/1, wdth 108, −.025em |
| Home headline | 800 42px/1.02, wdth 108, −.03em |
| History title | 800 36px/1, wdth 108, −.028em |
| Receipt title | 800 31px/1.04, wdth 108, −.025em |
| Day name input | 800 29px/1.05, wdth 108, −.025em |
| Card titles (Up-next day name, exercise name in workout) | 800 27px/1.1 (1.06), wdth 106–108, −.02/−.022em |
| Rest-day title | 800 24px/1.15, wdth 106, −.02em |
| Sheet title | 800 22px/1.1, wdth 108, −.02em |
| Stat numbers (THIS WEEK, VOLUME) | 800 30px/1, wdth 112, tabular |
| Stat numbers (history tiles) | 800 25px/1, wdth 112 |
| Stat numbers (receipt tiles) | 800 23px/1, wdth 112 |
| Set weight/reps | 700 21px/1, wdth 110, tabular |
| Field values (day editor) | 700 19px/1, wdth 110 |
| Rest countdown (phone ring) | 700 18px/1, tabular |
| Default-rest value | 700 17px/1, tabular |
| Elapsed timer | 700 15px/1, tabular, .02em |
| Primary CTA | 700 16px/1 (.01em) |
| Secondary buttons | 600 13–15px/1 |
| Row titles | 600 15px/1.2 |
| Row meta | 400 12px/1.3 |
| Body | 400 13–15px/1.4–1.5 |
| Helper / legal | 400 11.5px/1.4–1.45 |
| Hint (right-aligned) | 500 11px/1 |
| Section labels | 700 9px/1, .14–.18em, uppercase |
| Brand label "LEDGER" | 700 9px/1, .2em |
| Stat-tile labels | 700 8px/1, .14em |
| Chip text | 600 10–12px/1, .03–.08em |
| Micro button "REPEAT" | 600 10px/1, .06em |
| Stepper unit labels "5 LB"/"1 REP" | 600 10px/1, .1em |
| Tab label | 600 10px/1, .03em |
| Prototype captions | 400 12–13px/1.5–1.6 |

v2 roles: hero 700 84px/.9 wdth 96 −.045em; screen title 600 32px wdth 98 −.035em; onboarding title 600 38px wdth 98; card title 600 25–27px wdth 98 −.03em; sheet title 600 21px wdth 98; stat numbers **700 30–34px wdth 88, −.03em**; set numbers 700 24px wdth 90 −.025em; PR values 700 15px wdth 90; labels 500 10px .18em uppercase (only six all-caps labels: UP NEXT, RECENT, RECENTLY LOGGED, ALL EXERCISES, ESTIMATED 1RM · 8 WEEKS, SESSION LOG); row titles 500 15–16px; meta 300 12.5px; body 300 13–15.5px; buttons 500–600 12.5–16px; steppers 300 20px.

Watch roles: labels 700 17px (.08–.1em); elapsed 600 17px; exercise name 600 20px; weight 700 64px/.86 wdth 92 −.035em; reps 700 40px wdth 92 −.03em; BPM 700 19px; countdown / summary elapsed 700 52px wdth 92 −.035em; summary stats 700 30px wdth 92 −.03em; captions 600 17px .07em; buttons 600–700 18–21px; day name 700 30px/1.08 wdth 96; "End workout?" 700 26px wdth 96.

### 8.6 Spacing, radii, sizes

- Screen padding: top 64–78 px (status bar clearance), sides 20–26 px, bottom 24–40 px. Card padding 17–24 px; list-card inner padding `4px 18px` with 13–16 px row padding. Grid gaps 8–10 px; section gaps 14–26 px.
- Corner radii: **999 px** (pills, watch buttons, v2 everything interactive), **26** (bottom sheets; v2 rest card and 28 for v2 sheet), **22** (hero cards), **20** (settings/receipt/history cards), **18** (cards, dashed add buttons), **16** (CTAs, stat tiles), **14** (inputs, secondary buttons, picker rows, segmented track), **13** (week chips), **12** (schedule buttons, pills inside cards, stepper fields), **11** (steppers, tiles, chips), **10** (34 px buttons, tag tiles), **9** (week-strip tile), **8** (REPEAT), **7** (set chips), **5/2** (chart bar corners).
- Control sizes: primary CTA height ≈ 54 px (19 px padding); 44 × 44 icon/stepper buttons; 40 × 40 (settings steppers, swap); 34 × 34 (check box, week steppers); 38 × 38 / 36 × 36 / 34 × 34 tag tiles; toggles 52 × 32 with 26 px knob; avatar 44 (v1) / 40 (v2); week chip 54 × 58; schedule button min-height 66; tab bar 84 px (`11px 24px 30px` padding v1; `12px 26px 30px` v2); rest ring 74 px (v1) / 64 px (v2) / 196 px (watch).
- Progress bars: 4 px (v1) / 2 px (v2). Hairlines 1 px; borders 1.5 px (v1) / 1 px (v2).

### 8.7 Tab-bar icons (24 × 24 viewBox, `fill:none`, round caps/joins)

| key | path |
|---|---|
| today | `M4 19V9m5 10V5m5 14v-7m5 7V8` |
| program | `M4 5h16v15H4zM8 3v4m8-4v4M8 12h8m-8 4h5` |
| library | `M3 12h2m14 0h2M7 9v6m10-6v6M7 12h10` |
| history | `M12 7v5l3.5 2M12 3a9 9 0 1 0 9 9` |

v1: 23 px, stroke 1.9; active `#FF5B22`, inactive `rgba(22,21,15,.38)`; bar bg `rgba(239,237,230,.94)`, blur 12 px, top hairline `rgba(22,21,15,.1)`. v2: 22 px, stroke 1.5; inactive `rgba(244,242,237,.34)`.

Other icons: gear (Settings button), check `M4.5 12.5l5 5L20 7` / `M5 12.5l4.5 4.5L19 7`, chevrons `M9 5l7 7-7 7` / `M15 5l-7 7 7 7`, arrow `M5 12h13m-5-6l6 6-6 6`, swap `M4 8h13l-3.5-3.5M20 16H7l3.5 3.5`, search circle r 6.5 + `M16 16l4 4`.

### 8.8 Motion

- `@keyframes buzz { 0%,100% translateX(0); 20% −3px; 40% 3px; 60% −2px; 80% 2px }`, applied as `buzz .38s ease 3` to the watch screen when `buzz` is true.
- `@keyframes pulse { 0% opacity .4 scale(.85); 70% opacity 0 scale(1.45); 100% opacity 0 }` is declared in v1 but unused (candidate for the live-timer dot).
- Rest ring: circle circumference used as `stroke-dasharray` (phone v1 r 32 → 201; v2 r 29 → 182; watch r 88 → 553); `stroke-dashoffset = C − C × rest/restTotal`; rotate −90° so it drains clockwise from 12 o'clock. Updates once per second (should be animated smoothly in the real app).
- Crown scales to 1.12× while dragged.
- No screen-transition animations are specified.

---

## 9. Screens / states NOT yet designed

From the prototypes' own "NEXT STEPS":
- v1: (1) "Per-set schemes, for days that are not straight sets (5/3/1, pyramids, back-off sets)." (2) "Reordering exercises across a superset boundary — Move up / Move down currently ignores grouping." (3) "Custom exercise creation from the library sheet." (4) "History is still sample data — the finished session should feed Recent, the e1RM chart and each exercise's LAST line." (5) "A block-level view of the prescription: every week's load for every lift, on one screen."
- v2: (1) "Program builder — the one screen not designed yet, since it is the heaviest form in the app." (2) "Plate math on the set row, if you want it after all." (3) "Deload and failed-set states: what the card looks like when you miss reps." (4) "Watch complication and workout-start-from-wrist." — (1), (2) and (4b) exist in v1's light design but have no dark-theme treatment; (3) exists only as the " · HELD" label and miss tracking, with no in-workout failed-set UI.

Additional gaps a shippable app needs (not in either prototype):
- **Authentication reality**: validation, error states, password reset flow, Sign in with Apple entitlement, terms/privacy links, session persistence, log-out confirmation.
- **Onboarding ↔ program generation**: the v2 choices (goal, days/week) do not influence the program; v1 has no onboarding at all. Decide how a new user gets from zero to a program (template picker vs. builder vs. both).
- **Program management**: multiple programs, program name editing (hard-coded "Upper / Lower"), block start date / calendar mapping (the prototype has no real dates — "WEDNESDAY, AUG 19" and dates 17–23 are static), advancing `curWeek` automatically, end-of-block flow, program history.
- **Units**: `kg` is selectable but nothing converts; plate math assumes a 45 lb bar and lb plates; steps 5/2.5 are lb-specific. Need kg steps (2.5/1.25), 20 kg bar, plate inventory settings.
- **Exercise creation & editing**: custom exercises, editing catalog metadata, equipment/muscle taxonomy beyond 5 × 5, exercise detail screen (the History screen is hard-coded to Bench Press and not parameterised).
- **Workout history list**: the "History" tab lands on a single exercise; there is no list of past workouts, calendar, or per-workout detail beyond today's receipt; editing or deleting past workouts; notes/RPE per set.
- **Empty states**: empty program (no days), day with no exercises in Today/Watch ("empty day" string only), empty library search, first-ever session (no `last`), no history.
- **Error / offline states**: sync failures, watch disconnected, HealthKit denied.
- **HealthKit**: permission prompt, writing workouts, reading heart rate (the prototype's `hr` is random), "Apple Health · Connected" row behaviour.
- **Watch**: complication, standalone start when the phone is away, Always-On/wrist-down layout, crown haptics, weight ± affordance (callbacks `onWUp/onWDown` exist but no control), superset-aware logging from the wrist (§5.2), background rest notification, water-lock, workout auto-pause.
- **Notifications**: rest-over local notification on phone when backgrounded; scheduled-day reminders.
- **Live Activity / Dynamic Island** for the elapsed timer and rest countdown.
- **Set-level states**: failed set, partial reps, warm-up sets, AMRAP, bodyweight/assisted loads (negative loads like "−40 lb"), unilateral "2 × 70 lb" dumbbell notation.
- **Export**: the "Export data · CSV" row has no flow; account deletion; data privacy.
- **Accessibility**: Dynamic Type, VoiceOver labels for icon-only buttons ("⇄", gear, check), colour-contrast for 35–45 % alpha text, reduced-motion alternative to the buzz.
- **Avatar "JD"**: no profile screen; tapping does nothing.
- **Search**: the Library search field and filter pills are non-functional in the prototype.

---

## 10. Open questions for the product owner

1. **Which prototype is canonical?** v1 (light) carries the complete behaviour; v2 (dark) carries the intended visual direction but a reduced flow. Should the product be v1's flow in v2's dark visual system, and does the Program tab return?
2. **Onboarding vs. auth**: v1 opens with Log in / Create account; v2 opens with a 3-step setup. Do we need both (auth → onboarding → program)? Should onboarding answers (goal, days/week) generate the initial program, and how?
3. **Progression and PR rules**: confirm linear/double/fixed semantics and the deload formula (×0.85 → nearest 5 lb, −1 set, −2 RPE). The prototype's PR rule (any weight above the catalog starting load) is a placeholder — define PR as best set / best e1RM per exercise from real history?
4. **1RM formula**: Brzycki matches the sample (218 for 195×5); Epley does not. Choose one and define how the weekly chart point is computed (best set of the week?).
5. **Miss / hold rule**: a missed set holds the load for the next week. Should the drop set or added sets count toward "logged sets"? What about deload weeks (should misses in a deload week count)?
6. **Superset logging from the watch**: the watch's "Done set" uses per-exercise rest and per-exercise advance, while the phone's tick is round-robin with group rest. Which behaviour is correct? (Recommendation: make the watch call the same round-aware path.)
7. **Rest timer semantics**: should rest start on every logged set (v2), only when "Auto rest timer" is on (v1), and never for non-final superset members? Should un-ticking a set cancel a running rest? Should "+30s" after zero re-open the rest state (and what should the "GO" title mean)?
8. **Elapsed timer**: keeps counting while minimised; should it pause? What is the session timeout for an abandoned live session (currently never)?
9. **Units**: is kg support in scope for v1 of the product? If yes, define bar weight, plate set and steps per unit; if no, remove the toggle.
10. **Plate math**: bar weight and available plates configurable? Show on set row (v2 suggestion) or under TARGET (v1)?
11. **History tab**: what should the tab root be — a workout list, an exercise list, or a calendar? The prototype jumps straight to Bench Press.
12. **Library size**: copy says "Search 214 exercises" and build "214"; the catalog has 22. Is 214 the intended seed size, and where does the catalog come from?
13. **Swap semantics**: swapping only renames the slot; should the alternative bring its own last load / step / rest, and should the swap persist to the template or be one-off?
14. **Time estimates**: two different formulas (42 s/set + rest, superset rest 12 s vs. ignored) — pick one.
15. **Weekly volume delta ("+8%")** and "sessions this week": define the week boundary (Monday?) and whether "prior volume" is the current week only.
16. **Watch scope**: is "start from the wrist" (idle screen) required for launch, and must the watch work without the phone in range? Is heart rate required (HealthKit)?
17. **Copy tone**: v1 uses all-caps eyebrows extensively; v2 restricts to six. Confirm the v2 rule and the accent "once per screen" rule as design constraints.
18. **Dates**: how are block weeks anchored to calendar dates (start date, rolling Monday), and what happens when a user trains on an unscheduled day or skips a week?
19. **Account**: is Sign in with Apple the only social login? Is an account required at all for a local-first log?
20. **Export / Health**: what does "Export data · CSV" include, and which workout type is written to Apple Health?
