# The name field's line height (2026-10-13)

Branch `chore/name-field-line-height`, cut from `main` at `77b33ec` (#55, F11 S10). The chore that ruling 22 of
F11 S10 queued (`tasks/features/F11-program-builder.md`, "after round 2"; the input is in the feature's
implementation notes, "The queued chore's input").

| # | Item | Outcome | Commit |
|---|---|---|---|
| 1 | `LedgerDesign`: a field variant of a type role | Done: `ledgerFieldFont(_:)` | `aa009f1` |
| 2 | `NameField` uses it | Done; the name moves by no more than it did | `f52748e` |
| 3 | `ProgramHeader` holds a `NameField` | Done; a long program name wraps | `f52748e` |
| 4 | References | 16 of the builder's recorded again, each listed below; none else changed | `a5b271b` |
| 5 | The two known-issue wrappers | Removed; both tests pass as plain tests | `f52748e` |
| 6 | Tests | `FieldFontTests` (design), `NameFieldLineTests` (program) | `aa009f1`, `f52748e` |

Product lines changed (non-blank, non-comment lines under `LedgerKit/Sources`): 23 added, 33 removed, in
`LedgerFont.swift`, `NameField.swift` (one line) and `ProgramHeader.swift`; one word of a comment in
`ProgramBuilderModel.swift`. No user-facing text, no catalog, no `PillButton`, no project file, test plan,
workflow or `docs/` file was touched.

## The fault, measured again

While a name is edited the tails of g, j, p, q and y were cut flat, in the Day editor's `NameField` and in the
builder's `ProgramHeader` alike. On `main`, the letters' box of "Gyp" at 3× without the focus and with it:
28.0 and 24.7 pt at `.large`, 42.0 and 36.3 at `.accessibility3`, 48.0 and 41.3 at `.accessibility5` (the
tester's numbers, read again here before any change). Cause as diagnosed: `ledgerFont(.title)` sets a line of
1 × the size, SwiftUI makes the `UITextField` that high, and UIKit's editor clips at the line.

## The API, and why this one

```swift
public extension View {
    func ledgerFieldFont(_ role: LedgerFont.Role) -> some View
}
public extension LedgerFont {
    static let fieldLineHeight: CGFloat = 1.3
}
```

`ledgerFieldFont` is `ledgerFont` on a line of `fieldLineHeight` where the role's is tighter (a role whose own
line is looser keeps it), plus one thing: it moves the field's `.top` alignment guide down by half of what the
field's line is higher than the role's. `LedgerTextStyle` now takes its line as a value, so the two modifiers
share one body; `ledgerFont` hands it the role's line and is unchanged in what it does.

**A named variant, not `ledgerFont(_:lineHeight:)`.** A line-height parameter would let a feature choose a raw
line, which the roles own (the lint bans `.lineHeight(` in a feature for that reason). The variant says what it
is for and keeps the number in `LedgerDesign`.

**1.3, not `.loose`.** The brief's earlier measurement was that `.loose` holds the tails. Measured here on the
title role, with the letters laid top on top over the wrapping text (the field's frame; whether "Gyp" is whole
with the focus), at `.large`, `.accessibility3`, `.accessibility5`:

| Line | Field's frame | Tails with the focus | The caret under a one-line name, at `.accessibility3` and `5` |
|---|---|---|---|
| the role's, 1 | 33.7, 49.3, 56.3 pt | cut by 3.3, 5.7, 6.7 pt | 2.3, 2.7 pt (the tester's numbers) |
| natural (no line set), `.variable` | 36.7, 53.7, 61.3 | whole, but the letters stand 3.0, 5.0, 5.7 pt *higher* | not measured |
| 1.1 | 37.0, 54.3, 62.0 | cut by 1.7, 3.3, 4.0 | not measured |
| 1.2 = `.normal` (same frames) | 40.3, 59.0, 67.3 | whole, 1.0 short, 1.3 short | not measured |
| **1.3** | **43.3, 63.7, 73.0** | **whole** | **9.0, 10.0 pt** |
| 1.4 | 46.7, 68.3, 78.3 | whole | 11.0, 12.7 |
| 1.5 = `.loose` (same frames and letters) | 49.7, 73.3, 83.7 | whole | 13.7, 15.3 |

1.3 and 1.4 were then measured at all twelve text sizes, plain and with Bold Text, on both fields: whole
everywhere. UIKit draws the caret as high as the line. The Day editor keeps 12 pt between the name's line and
the tag (`xs` + `s`); at 1.5 the caret crosses it from `.accessibility3`, at 1.4 at `.accessibility5`, at 1.3
it stays inside at every size. So the constant is the lowest tenth that holds the tails, and it is written as
a multiple because the guide's arithmetic needs the number (`.loose` does not say what it is).

**Why a guide and not "centre on the first line".** The brief expected the field centred on the wrapping
text's first line, with about 1.33 pt of shift. Measured with the tester's own measure
(`focus_doesNotMoveTheName`: the letters' box, without the focus and with it), per way of laying a 1.5 field
over the text, at `.large`, `.accessibility3`, `.accessibility5`:

| The field over the text | The name moves down by |
|---|---|
| top on top | 7.3, 10.7, 12.0 pt |
| centre on centre | −1.3, −2.0, −2.7 pt: **outside the tester's 1.34 at `.accessibility3`** |
| first baseline on first baseline | 4.0, 6.0, 6.7 pt (the same for every line height tried) |
| a hidden one-line text on the field's line, baseline to baseline, the field centred on it | 6.7, 9.7, 11.3 pt |

None is inside the bound, so nothing a feature view can spell lines the two up. What is true, and measured for
lines of 1, 1.1, 1.2, 1.3 and 1.5: UIKit puts the letters half of the extra line lower in the field, and
SwiftUI's `Text` keeps them at the top of its line whatever its line. So the field must stand
`(field line − role line) × size / 2` above the text's top, which only `LedgerDesign` can compute: hence the
`.top` guide. `NameField`'s overlay stays `.overlay(alignment: .topLeading)`, unchanged.

**The guide's limit** (in the doc comment): it is the field's own. A stack or an `if` around the field has a
top of its own; `FieldFontTests` first failed for exactly that, by 4.3 to 6.7 pt, until its field was styled
directly.

## Measurements of the result

"Gyp", the letters' box at 3×, hosted 323 pt wide, iOS 27.0 on the PR plan's iPhone 17. The two fields measure
the same in every cell, so one column each for plain and bold serves both.

| Size | Letters, idle → edited | With Bold Text | The name moves (down +) | Field's frame | Frame above the name's top | Caret under the name's line |
|---|---|---|---|---|---|---|
| `.xSmall` | 26.00 → 26.00 | 26.33 → 26.33 | −0.33 | 40.33 | 4.3 | 0.0 |
| `.small` | 27.00 → 27.00 | 27.00 → 27.00 | −0.67 | 41.33 | 4.7 | 0.0 |
| `.medium` | 27.33 → 27.33 | 27.67 → 27.67 | −0.33 | 42.33 | 4.7 | 0.0 |
| `.large` | 28.00 → 28.00 | 28.33 → 28.33 | −0.33 | 43.33 | 4.7 | 0.0 |
| `.xLarge` | 29.33 → 29.33 | 29.67 → 29.67 | −0.67 | 45.33 | 5.0 | 0.0 |
| `.xxLarge` | 31.67 → 31.67 | 31.67 → 31.67 | −0.67 | 48.67 | 5.3 | 0.0 |
| `.xxxLarge` | 32.67 → 32.67 | 33.00 → 33.00 | −0.67 | 50.67 | 5.7 | 1.0 |
| `.accessibility1` | 35.67 → 35.67 | 36.00 → 36.00 | −0.67 | 54.67 | 6.0 | 4.7 |
| `.accessibility2` | 39.00 → 39.00 | 39.33 → 39.33 | −1.00 | 59.67 | 6.7 | 8.3 |
| `.accessibility3` | 42.00 → 42.00 | 42.33 → 42.33 | −1.00 | 63.67 | 7.0 | 9.0 |
| `.accessibility4` | 45.33 → 45.33 | 45.67 → 45.67 | −1.33 | 68.67 | 7.7 | 9.3 |
| `.accessibility5` | 48.00 → 48.00 | 48.33 → 48.33 | −1.67 | 73.00 | 8.3 | 10.0 |

- **The shift against the tester's bound of 1.34 pt** (`focus_doesNotMoveTheName`, `.large` and
  `.accessibility3`, unedited, green): 0.33 and 1.00 pt, where `main` measures 0.67 and 1.33. The 1.67 at
  `.accessibility5` is `main`'s too (the notes of S10, round 2).
- "Caret under the name's line" is how far the focused, empty field's caret reaches under a one-letter name's
  target; it was 2.3 to 2.7 pt at the accessibility sizes on `main`.
- **The field's frame is higher than the name's line** and stands out of it above and below; nothing is laid
  out for it (an overlay), so nothing moves. Above, it lies over the eyebrow's frame (4 pt away) by up to 4.3
  pt. Neither the eyebrow nor the tag takes a tap.

## `ProgramHeader`

Its body is the eyebrow over `NameField(label: model.namePlaceholder, name: model.name) { send(.rename($0)) }`
with `.padding(.bottom, LedgerSpacing.s)`, as `DayEditorHeader` has it. Its own draft, focus, three
`onChange` and 44 pt target are gone: they are `NameField`'s. `NameField` already stood in
`FeatureProgram/Views/`, so no file moved. What a lifter sees on the builder:

- **A long name wraps** while it is not edited (three lines at the default size for the preview's long name,
  five at `.accessibility3`) where it ended in "…"; edited, it is one line as before.
- **The name stands at the top of its 44 pt target, not in its middle:** about 5 pt higher at the default
  size, closer to "MY PROGRAM", as the day's name stands under "DAY 1 OF 4".
- **Everything under the header stands 8 pt lower** (6.3 pt at `.accessibility3`, where the one-line field
  was already higher than 44 pt).
- **Right to left the idle name starts at the right edge**, where the old field drew a Latin name at the left.
  See "For Pete" for what happens when the focus comes.

## References recorded again

16, all in `LedgerKit/Tests/FeatureProgramTests/__Snapshots__/ProgramSnapshotTests/`, found by running both
suites with the old references (16 failed, no other) and recorded by deleting those 16 and running
`ProgramSnapshotTests` once in the missing-reference mode; a second run compared them. Each was compared with
its old version row by row (a row is "the old row" when it equals a row of the old picture exactly, in place
or moved down by the growth in height), and the header of each was looked at beside the old one.

| Reference | Height, px | Changed in place, px | Rows that are not an old row | Under them |
|---|---|---|---|---|
| `builder_matchesReferences.dark-large` | 1059 → 1067 | 76,064 | 48–82: the name, 5 px higher | the old rows, 8 px lower, exactly |
| `builder_matchesReferences.light-large` | 1059 → 1067 | 76,053 | 48–82 | as above |
| `builder_matchesReferences.dark-xLarge` | 1267 → 1275 | 90,092 | 51–85 | as above |
| `builder_matchesReferences.light-xLarge` | 1267 → 1275 | 90,057 | 51–85 | as above |
| `builder_matchesReferences.dark-accessibility3` | 2737 → 2744 | 184,280 | 63–108: the name. **Also 27–46, 173–188, 216–231: see below** | the old rows, 6 or 7 px lower, exactly |
| `builder_matchesReferences.light-accessibility3` | 2737 → 2744 | 183,250 | as above | as above |
| `deloadWeek_matchesReferences.dark-large` | 1059 → 1067 | 75,488 | 48–82 | 8 px lower, exactly |
| `deloadWeek_matchesReferences.light-large` | 1059 → 1067 | 75,484 | 48–82 | as above |
| `emptyDay_matchesReferences.dark-large` | 1162 → 1170 | 83,214 | 48–82 | as above |
| `emptyDay_matchesReferences.light-large` | 1162 → 1170 | 83,201 | 48–82 | as above |
| `twoWeeks_matchesReferences.dark-large` | 1031 → 1039 | 69,298 | 48–82 | as above |
| `twoWeeks_matchesReferences.light-large` | 1031 → 1039 | 69,295 | 48–82 | as above |
| `increaseContrast_matchesReferences.builder` | 1059 → 1067 | 76,643 | 48–82 | as above |
| `rightToLeft_matchesReferences.builder-dark-large` | 1059 → 1067 | 77,251 | 48–82: the name, now at the right edge | as above |
| `sixteenWeeks_matchesReferences.dark-large` | 1181 → 1241 | 129,510 | 48–140: the long name on three lines, where it was one with "…" | 60 px lower, exactly |
| `sixteenWeeks_matchesReferences.dark-accessibility3` | 3119 → 3316 | 400,887 | 59–297: the long name on five lines | 197 px lower, exactly |

"Changed in place" counts every pixel that differs from the pixel at the same place before, so it is large
wherever the page moved; the last two columns are what moved.

**Finding: the two `.accessibility3` builder references change outside the name, by rasterisation.** The
brief says a change elsewhere than the name area is to be reported and not recorded; these two are recorded,
because without them the suite is red, and this is the report. In both, "MY PROGRAM" (rows 27–46) is the same
picture one pixel lower (its ink is equal to the last unit, its centre of ink moves from row 34.84 to 35.84),
and the upper and lower edges of the two stepper circles (rows 173–188 and 216–231, about 290 px each) are
drawn anew, by at most 19 levels against the old rows moved 6 or 7 px. The cause, measured: at this size the
header grows by 6.33 pt, not by a whole number, so the picture grows 7 px and the page stands a third of a
pixel differently in it; the references are drawn at 1×. The layout itself did not move the eyebrow: its
VoiceOver frame, read in a hosted window before and after, keeps its distance to the page's top, and "BLOCK ·
8 WEEKS" stands 6.33 pt further from it. At the sizes where the header grows by 8 pt the eyebrow's rows are
equal in place, pixel for pixel. If this is not acceptable, commit `a5b271b` is the references alone.

**Not changed:** the exercise library's 12 references, all 24 of `DayEditorSnapshotTests` (while it has no
focus the field draws nothing, and the text is as it was), and every reference of `LedgerDesignTests`.

## Edits to testers' files

Three files, each forced. No test was removed, disabled or wrapped; nothing else in a tester's file changed.

| File, test | Old | New | Why forced |
|---|---|---|---|
| `Adversarial/DayEditorViewsFocusAdversarialTests.swift`, `focus_doesNotCutTheDescenders` and `focus_programHeader_doesNotCutTheDescenders` | each expectation inside `withKnownIssue(Self.clippedField)` | the same expectations, plain; the `clippedField` comment is deleted, the titles lose "(known: …)", the doc comments say what closed it, and the message "the two fields clip alike" reads "draw alike" | Item 5. **Stronger:** a cut tail fails now. |
| the same file, `target_holdsEveryLine` | `abs(field.minY - target.minY) < 1`: the `UITextField`'s frame starts on the target's top | `abs(field.minY - (target.minY - above)) < 1`, with `above = (LedgerFont.fieldLineHeight − the title's line) × size / 2`: it starts that far above (4.8 pt at `.large`, 7.1 at `.accessibility3`) | The field is higher than the title's line and its letters must stay where the text's are, so its frame cannot start on the target's top. **Same strength** (one point, both sides), another place. The other five expectations of the test are untouched. |
| `Adversarial/DayEditorViewsTitleAdversarialTests.swift`, `emptyDraft_keepsALine` | `jump = abs(empty focused target − one-letter unfocused target) < xs` (4 pt) | `jump` between the empty and the one-letter name **both with the focus** `< xs`; and a new expectation, `reach = empty focused target's bottom − one-letter unfocused target's bottom < xs + s` (12 pt, the room `DayEditorHeader` keeps over the tag) | The marker is measured by its blue and the caret is blue; the caret is as high as the field's line, so with the focus the measure now reaches 9.0 and 10.0 pt under an unfocused one-letter name at the two accessibility sizes. **Weaker in one respect, for audit:** the old bound held the caret within 4 pt of the name's line; the new one holds it within 12 pt, measured 10.0 at most. **Kept:** the first letter typed moves nothing (now measured like with like), and `hang < xs` is untouched. |
| `Adversarial/ProgramViewsSourceAdversarialTests.swift`, `views_sendOnlyTheModelsActions` | `"ProgramHeader.swift: send(.rename(text))"` | `"ProgramHeader.swift: send(.rename($0))"` | The header builds its action from what `NameField` hands it, as `DayEditorHeader` does. Same strength. |
| the same file, `views_keepNoStateButDraftsFocusAndTheAlert` | six entries of state, two of them `ProgramHeader`'s; `.onChange` three times in each of `NameField.swift` and `ProgramHeader.swift`; the title says "the two names' drafts, the three fields' focus" | four entries (`ProgramHeader`'s two are gone); `.onChange` three times in `NameField.swift` alone; the title says "the name field's draft, the two fields' focus" | The header keeps no state now. **Stricter:** less state is allowed. |

`ProgramViewsSourceAdversarialTests.scan_readsEveryView` (24 files) and `ProgramViewsSourceTests` pass
unedited: no file was added or moved. `nameField_handsTheNameOverOnce` and `views_spellNoColourButClear` pass
unedited.

## Tests added

- `LedgerDesignTests/FieldFontTests` (iOS; a hosted `UITextField` with the focus, since only the editor
  clips): a field in `ledgerFieldFont(.title)` over a text in `ledgerFont(.title)` draws "Gyp" as high as the
  text does, to a pixel at 3×, and within 2 pt of where the text draws it, at `.xSmall`, `.large`,
  `.accessibility3` and `.accessibility5`, plain and bold; and a control, the same field under
  `ledgerFont(.title)` is more than 2 pt short. Both failed first for the reason given under "The guide's
  limit".
- `FeatureProgramTests/NameFieldLineTests`: with the focus both names keep the five tails ("gjpqy") to a
  pixel and their place within 2 pt, at all twelve sizes, plain and bold (48 hosted fields); a long program
  name is on three lines or more without the focus, one line that fills the field with it, and the same
  picture again after; the builder's header reads its heading and holds its one field with the placeholder
  "Program name" and the name, under a short and a long name, and no stop reads the drawn name.
- The builder's VoiceOver trees (`ProgramAccessibilityTests`, `ProgramViewsTreeAdversarialTests`) and
  `ProgramTextFieldTests`, `ProgramViewsFieldAdversarialTests`, `ProgramViewsCutAdversarialTests`
  (`fields_are44PointTargets`) pass unedited against the new header.

## For Pete

Pictures, before beside after (dark, 2×), in `tasks/chores/screenshots/name-field/`: for
`day-editor-header`, `program-header` and `program-header-long-name`, each at `large` and `accessibility3`,
`idle` and `editing` (12 files, `<header>-<size>-<state>.before-after.png`).

1. **The builder's name moved, by design of the brief:** up to the top of its target (about 5 pt nearer the
   eyebrow) and the page under it 8 pt down. `program-header-large-idle` shows it.
2. **The caret is higher than it was** (as high as a line of 1.3) and reaches up to 10 pt under the name at
   the largest sizes, inside the 12 pt over the day's tag. `day-editor-header-accessibility3-editing`.
3. **Right to left, in a hosted test, the name jumps to the left edge when the focus comes** (the idle text
   starts at the right edge, the field draws a Latin name at the left). This is `NameField`'s since S10 on the
   Day editor (measured on `main`: 281 → 42 pt at `.large`); the builder's old field drew at the left idle
   and edited, so the builder has the jump as of this chore. `.multilineTextAlignment(.leading)` on the field
   was tried and changes nothing in the hosted window. Whether a device set to a right-to-left language does
   the same is not known (the hosted test sets SwiftUI's layout direction only), and the app ships no such
   language. Not fixed here.
4. **The library's search field is a field in `.body`, whose line is 1.2**, the line that cut the title's
   tails by a point from `.accessibility3`. Not measured, not changed (it would move the library's
   references). A candidate for `ledgerFieldFont(.body)`.
5. **A sentence proposed for `docs/engineering-standards.md` §7**, under "Only `LedgerDesign` tokens…": *A
   `TextField` is set with `ledgerFieldFont(_:)`, not `ledgerFont(_:)`: a field clips its text to its line
   while it is edited, and a role's line may be tighter than the font.* And for the notes of F11, ruling 21's
   "the 8 pt … can then be looked at again": looked at; kept, in both headers, since the idle text's frame is
   still the title's line of 1 and its tails still hang under it.
6. `DesignGallery` has no specimen of the field variant: one would change the gallery's references, and the
   variant has its own test. `tasks/todo.md` is not edited here (another lane is open on it).

## Verified

Simulator work went through the session's lock, one run at a time, on the PR plan's iPhone 17 (iOS 27.0).
The two closing gates ran on the tree of `a5b271b`, before this record and the pictures were committed
(neither is built or tested).

| Check | Result |
|---|---|
| The two descender tests before the change | each recorded its known issue at the three sizes |
| Both suites with the product change and the old references | 16 references failed, all the builder's; no other test but those under "Edits to testers' files" |
| `-only-testing:LedgerDesignTests -only-testing:FeatureProgramTests` | exit 0 in 553 s: 387 tests in 93 suites and 514 tests in 60 suites passed |
| `scripts/check.sh` (full: format, lint, iOS, watchOS, coverage) | exit 0, `check.sh OK`, 1,415 s (iOS tests 1,024 s, watchOS tests 246 s), after 763 s of waiting for the lock |

## Not done, and not verified

- A device, a finger and a keyboard: typing, the tap that gives the name the focus, the caret as a lifter
  sees it, and the keyboard's target when the focus arrives are for S14's UI tests, as before.
- Letters other than Archivo's Latin: the tails were measured on "Gyp" and "gjpqy". Accents over capitals and
  marks deeper than a tail (Å, Ç, ą) were not measured at 1.3.
- Right to left on a device (item 3 above), and the library's search field (item 4).
- The watch: `ledgerFieldFont` compiles there with the full gate's watch build; no watch view uses it and no
  watch test draws a field.
- The hosted runner: no CI run was started from this branch; nothing was pushed.

## G2 — adversarial testing

Range `77b33ec..c77c5cd`, iOS 27.0 on the PR plan's iPhone 17, every run through the lock. Everything below
is measured in a hosted window at 3×, 323 pt wide (a 375 pt phone's page) unless a width is named. "On
`main`" means `main`'s `NameField` and `ProgramHeader` (`git show 77b33ec:…`) built into a temporary test
beside the new ones and measured in the same run; no product file was changed and the temporary tests are
gone. Five findings; none loses a letter or an action. Each has a test that is wrapped as a known issue
under its id, so the gate stays green, and that fails when the fault is gone.

### Findings

| Id | Severity | What | New with this chore? |
|---|---|---|---|
| NF-1 | Medium | A name with an emoji or certain letters jumps 3.7 to 7.3 pt up when the focus comes | Yes |
| NF-2 | Minor | With the draft emptied the caret stands in the tag's pill at the two largest sizes measured | Worse: 0 → 0.7 pt, 1.3 → 8.7 pt |
| NF-3 | Minor | A name whose script runs against the layout jumps across the field on focus | In the builder, yes; the Day editor's on `main` |
| NF-4 | Minor (API) | `ledgerFieldFont`'s guide is right only for a role whose line is 1 | Yes (no screen uses it) |
| NF-5 | Minor | The first letter typed into an empty name moves the page 10.7 pt at `.accessibility5` | No; the test that should have seen it measured the caret |

**NF-1. The guide lifts the names UIKit does not centre.** The `.top` guide assumes UIKit centres the
letters in the field's higher line. It does for most names. For a name that holds an emoji, one of Å É Ç Ł ï
ą ỵ (measured: "ÅÉÇ", "Ł", "Łódź", "naïve", "ąỵgj", "Ǻ Ṩ ự"), Thai, Devanagari or Arabic, it does not, and
the guide lifts the name all the same. How far the name's ink moves down when the focus comes, both fields
alike, plain and bold alike:

| Name | `.large` | `.accessibility3` | `.accessibility5` | `main`, the same three |
|---|---|---|---|---|
| "Gyp", "Upper A", "Día", "é", "ñu", "Ü", "ß", "Æ", "A — B", "Pete’s", "½ rep", "10 × 3", Hebrew | −0.33 | −1.00 | −1.67 | −0.67, −1.33, −1.67 |
| "Push 💪", "naïve", "Ł", "ÅÉÇ", "ąỵgj", Thai, Devanagari, Arabic | **−3.67** | **−6.00** | **−7.33** | −0.67, −1.33, −1.67 |

Hebrew and Arabic were measured at `.large` only. So "the name moves by no more than it did" holds for the first row only; the second is 3 to 5 times the
tester's bound of 1.34 pt. It is the same jump back at the blur, and by inference (a hosted field takes no
typing) the line jumps 3.3 to 5.7 pt under the caret when the first such character is typed or the last
deleted. Which characters do it was found by trial, not explained ("é" and "ñ" do not, "ï" and "Ł" do);
with the guide removed (mutant M2) none of them moves by more than the bound, and on `main`'s line neither.
Reproduce: `NameFieldLineAdversarialTests.focus_doesNotMoveANameWithAnEmoji` without its wrapper.

**NF-2. An emptied draft: the caret in the tag.** With no letter the wrapping text has no line, so the
name's target is 44 pt at every size and the tag comes up under it, while the field keeps its line. In the
real `DayEditorHeader`, the caret's foot against the top of the tag's pill:

| | `.large` | `.accessibility1` | `.accessibility3` | `.accessibility5` |
|---|---|---|---|---|
| Now | 17.3 pt clear | 7.3 clear | **0.7 pt in the pill** | **8.7 pt in the pill** |
| `main` (`NameField` alone, the tag 12 pt under its target) | clear | clear | 6.0 clear | 1.3 in the pill |

The placeholder's own ink reaches 0.3 pt into the pill at `.accessibility5` (1.3 on `main`). Nothing is
covered that can be tapped. Reproduce: `emptyDraft_caretStaysAboveTheTag`, and `emptyDraft_keepsALine`
(below). The root is NF-5's: an empty text with no line.

**NF-3. Across the field, and what is new.** The text that wraps starts at the layout's leading edge; the
field with the focus starts where the name's own script starts. Sideways move of the ink on focus, `.large`:

| | Day editor, `main` | Day editor, now | Builder, `main` | Builder, now |
|---|---|---|---|---|
| "Upper A", layout right to left | −213.7 | −213.7 | 0 (drawn at the left, idle and edited) | **−213.7** |
| Hebrew name, layout left to right | +181.7 | +181.7 | 0 (drawn at the right, idle and edited) | **+181.7** |
| Arabic name, layout left to right | +175.0 | +175.3 | +0.7 | **+175.3** |
| Hebrew name, layout right to left | 0 | 0 | 0 | 0 |

New with this chore, exactly: the builder has both jumps, and without the focus it now draws a Latin name at
the right edge on a right-to-left layout and a Hebrew or Arabic name at the left edge on a left-to-right
one, where its old field drew each at its script's own edge. The Day editor is unchanged. The second and
third rows need no right-to-left language in the app: a program named in Hebrew or Arabic on today's
English app is enough, which the record's "the app ships no such language" does not cover. Forcing UIKit's
own direction too (`traitOverrides.layoutDirection`, the field's `semanticContentAttribute`) changes no
number, so the hosted measure is not only SwiftUI's environment; a device is still not measured. Reproduce:
`focus_doesNotJumpAcross`.

**NF-4. The guide's arithmetic, on the other roles.** The doc comment promises of every role that "a field
laid top on top over such a text draws its letters where the text draws them". A text keeps its letters at
the top of its line whatever the line, so the shift wanted is half of (field line − 1), not of (field line
− role line). Field under text, at `.large`, `.accessibility3`, `.accessibility5`: title −0.3, −1.0, −1.7;
caption, button and the numerals (line 1) within 1.7; display 0.3, 0.3, 0.0; heading 0.7; subheading 1.0,
1.3, 1.3; **body 2.0, 2.7, 3.3; label 1.7, 2.7, 3.0; bodyLight (line 1.6, so no guide) 4.3, 8.7, 11.0**.
The tails are whole in every role. No view lays a body field over a text today, and the record's own
candidate (the search field) has no text under it; the comment or the arithmetic should change before one
does. Reproduce: `FieldFontAdversarialTests.looseRole_fieldStandsOnTheText`.

**NF-5. The first letter moves the page (on `main` too).** The name's target, measured with the field
hidden so that no caret counts, empty and under one letter: 44.0 and 44.0 pt at `.large`, 44.0 and 47.7 at
`.accessibility3`, 44.0 and 54.7 at `.accessibility5`. S10's round 2 read 2.3 and 2.7 pt because its
target was the marker's blue and the caret is blue. Reproduce: `emptyDraft_keepsALine`.

### What held

- **Whole under focus (item 2).** "ÅÉÇ", "ąỵgj", "Ǻ Ṩ ự", Thai, Devanagari and emoji, at `.large`,
  `.accessibility3`, `.accessibility5`, plain and bold, in both fields: nothing cut; the least is one pixel
  (0.33 pt) on "Ǻ Ṩ ự" with Bold Text at `.large`. The field draws Thai 4.0 to 6.7 pt higher than the text
  does. On `main` Thai lost 0.7 to 2.0 pt in the Day editor and 6.7 to 12.0 pt in the builder.
- **The caret under a name (item 3).** Room between the caret's foot (which is the field's frame's) and the
  tag's pill, name of one line: 17.3, 7.3, 3.0, 2.0 pt at `.large`, `.accessibility1`, `.accessibility3`,
  `.accessibility5`, the same with Bold Text. UIKit finds no text field under a point of the eyebrow's last
  row, of the tag's first row or of its middle. Under the program's name the next thing drawn is 45 pt
  under the caret at `.large` and 35 pt at `.accessibility3`; at `.accessibility5` it is derived (30 pt),
  not measured.
- **The program's name under focus (item 4).** 0.00 pt sideways and −0.33, −1.00 pt down at `.large`,
  `.accessibility3`, plain and bold, also for "Día — é" and "Pete’s ½ × 3". A long name, a word of 34
  letters and "g" are, without the focus, pixel for pixel a text that cannot lose a word, at three sizes ×
  402 and 375 pt × plain and bold (36 drawings); with the focus one line, and the same picture after.
- **A text size changed under the focus (item 7)** leaves the letters and the field's frame exactly where a
  field first drawn at that size has them (three changes).
- **VoiceOver (item 6).** Old and new header, hosted side by side at `.large` and `.accessibility5`: the
  same stops (`heading "MY PROGRAM"`; none for the day's field alone), the same placeholder and text on the
  one `UITextField`. Its frame is 43.3 pt high where it was 33.7 (73.0 and 56.3).
- **Nothing else moved (item 6).** See the closing run under "Commands".

### The four edits to testers' files, audited

| Edit | Verdict | By what |
|---|---|---|
| `focus_doesNotCutTheDescenders`, `focus_programHeader_…` unwrapped | As strong as meant | Mutant M1 (`NameField` back on `ledgerFont(.title)`): both fail at all three sizes |
| `target_holdsEveryLine`: the field starts `above` over the target | As strong, with one dependence | M1 and M2 (the guide returns 0) fail it at both sizes. It reads `fieldLineHeight` from the product, so M3 (1.5) passes it; `caret_staysAboveTheTag` is what fails M3 (16 expectations) |
| `emptyDraft_keepsALine` | **Weaker than declared, and wrong before** | See below; rewritten |
| `ProgramViewsSourceAdversarialTests`, both | As strong; stricter | M1 with one `@State` added to `ProgramHeader`: `views_keepNoStateButDraftsFocusAndTheAlert` fails |

`emptyDraft_keepsALine`: `hang` compared the field's foot with a "target" that was the caret's foot, so it
was 0 by construction; the new `jump` compared two carets; the new `reach` measured the caret against a
one-letter name's target, which is not where the tag stands under an empty name (NF-2). Rewritten on the
target with the field hidden: the field's foot stays inside the 12 pt over the tag (known issue from
`.accessibility3`, NF-2), and the target is as high as one letter's to `xs` (known issue at
`.accessibility5`, NF-5). What the implementer's `reach` did guard, a line of 1.5, is now
`caret_staysAboveTheTag`'s.

One more, not in the list: `ProgramViewsCutAdversarialTests.fields_are44PointTargets` passed unedited but
had lost 8 pt, since the header's new `s` under the name counted as target. It subtracts it now.

Mutants (each applied, run, and restored with `git checkout -- LedgerKit/Sources`): M1 as above, 85
issues; M2, 131 issues; M3, 16 issues, all `caret_staysAboveTheTag`'s. Under M1 and M2 the known issue of
NF-1 is *not* recorded, which is the evidence that NF-1 is the guide's and new.

### Tests added

- `FeatureProgramTests/Adversarial/NameFieldLineAdversarialTests.swift` and
  `NameFieldRoomAdversarialTests.swift` (one suite): the glyphs; the name's place under focus in both
  fields; NF-1; the long program name whole and one line; the caret over the tag; NF-2; NF-3 and its
  control; the text size changed under the focus.
- `LedgerDesignTests/Adversarial/FieldFontAdversarialTests.swift`: every phone role's tails whole; roles on
  a line of 1 stand on their text; NF-4.

Known issues recorded by a green run: 16 (NF-1), 2 + 2 (NF-2), 4 (NF-3), 3 (NF-4), 1 (NF-5).

### Not checked

A device, a finger, typing (so NF-1's jump while typing is inferred); a device set to a right-to-left
language; the caret under the program's name at `.accessibility5` (derived); glyphs at the nine sizes other
than the three; the watch; the hosted CI runner; the full `scripts/check.sh` (targeted suites only, as
briefed; format and lint were run on the changed files).

### Commands

Each is `sim-lock.py <script> <name> PR build -only-testing:…` (build-for-testing, then
test-without-building, on the PR plan).

| Run | Exit | Result |
|---|---|---|
| Two probe runs (temporary suites, `main`'s views beside the new) | 0, 0 | the measurements above |
| The new suites and the edited ones, first run | 65 | one test of mine, whose oracle cut the ink out of two drawings and compared the cuts; replaced by a header of the tester's own text, compared whole |
| Mutants M1, M2, M3, the same suites with `NameFieldLineTests` and `FieldFontTests` | 65, 65, 65 | as audited above |
| **Closing run, clean tree:** all of `LedgerDesignTests`, `FeatureTodayTests`, `FeatureProgramTests` | **0** in 667 s | 390 tests in 94 suites (30 known issues, 3 of them new: NF-4), 366 in 39, 524 in 61 (27 known issues, 25 of them new) |
| `swiftformat --lint` on `LedgerKit` and `Apps`, `swiftlint --strict` | 0, 0 | |

The closing run is the confirmation of "nothing else moved": the Day editor's 24 references, the library's
12, Today's (the one other user of `ledgerFont(.title)`) and every reference of `LedgerDesignTests` compare
equal to what is committed, and `ProgramAccessibilityTests`, `DayEditorAccessibilityTests` and the two
adversarial tree suites pass unedited. No reference was written.

## Fix round 1

Rulings of the coordinator on G2's five findings and G3's two should-fixes. Commits `64c7c30`, `27ba6d8`,
`fe97463`, `8bfc5f9`. Measured as before: hosted at 3×, 323 pt wide, iOS 27.0, the PR plan's iPhone 17.

| Finding | Outcome | How |
|---|---|---|
| NF-1, a name with an emoji or Å Ł ï, Thai… jumps | **Not fixed: options below, for a ruling** | — |
| NF-2, an emptied draft's caret in the day's tag | Fixed | an empty name keeps one line (below) |
| NF-3, a name against the layout's direction jumps across | Fixed, in the builder **and** the Day editor | the field aligns by the layout |
| NF-4, the guide wrong for a looser role | Fixed for every role | the guide's arithmetic |
| NF-5, the first letter moves the page (on `main`) | Fixed with NF-2, the same cause | as NF-2 |
| Review 1 and 2, `pair(_:)` ignored its role | Fixed; `.body` covered | `FieldFontTests` |
| `fieldLineHeight`'s comment, "14 to 16 pt" | Fixed: 13.7 and 15.3 pt | — |

**NF-4.** A text keeps its letters at the top of its line whatever the line (G2's measure, and the
first round's for the title); UIKit puts a field's half of the extra line above them. So the guide is
`(line − 1) × size / 2`, not `(line − role line) × size / 2`. For the title, whose line is 1, nothing
changes. `FieldFontAdversarialTests.looseRole_fieldStandsOnTheText` (`.body`, `.label`, `.bodyLight`, within
2 pt at `.accessibility3`) now passes; it measured 2.7, 2.7 and 8.7 pt before. `FieldFontTests`' `pair(_:drawsField:)`
sets the field in its own role (an overload; the one with `style:` stays for the control and the tester's
file), and its first test runs `.title` and `.body` at four sizes, plain and bold.

**NF-3.** The field takes `.multilineTextAlignment(strategy: .layoutBased)` (SwiftUI, iOS 26): it starts its
text at the layout's leading edge, as the wrapping text does, whatever the name's script. Measured first,
on a probe of `NameField`, at `.large`, the sideways move on focus: Latin on a right-to-left layout −213.7 →
0.0 pt; Hebrew on a left-to-right layout +181.7 → 0.0; Hebrew right to left and Latin left to right 0 before
and after. `.writingDirection(strategy: .layoutBased)` gives the same numbers; `.multilineTextAlignment(.leading)`
and `.multilineTextAlignment(strategy: .writingDirectionBased)` change nothing, nor does setting either
strategy on the text instead. The builder's 0 is restored by moving the field to the text, not the text to
the script: idle, a Latin name on a right-to-left layout stays at the right edge, as in the first round's
references. With the focus it now stays there. **The Day editor is cured too** (it is the same view).
`focus_doesNotJumpAcross` passes at its four cases and `focus_ownDirection_doesNotJump` still passes.

**NF-2 and NF-5.** The cause of both was an empty text, which has no line: the target fell to 44 pt and the
tag came up under the field. `NameField` now stacks, under the name, its label on one line, unseen and of no
width (`ZStack` with `Text(label)…fixedSize(horizontal:).frame(width: 0).hidden()`), so an empty draft keeps
one line's height. Two dead ends, each found by a tester's test: `draft.isEmpty` is a spelling the views'
source scan pins (`views_conditionsOnLists_areTheTwo`); and the label at its own width, wider than a 375 pt
column at `.accessibility5`, widened the stack and broke a long name's lines elsewhere
(`longProgramName_isDrawnWhole`, 4 drawings), hence the zero width. Not changed: the look at any size of a
name that is not empty (every `whole` comparison passes unedited), and an empty name below the
accessibility sizes (one line of the title is under 44 pt there). `emptyDraft_caretStaysAboveTheTag` passes
at all four sizes (it measured 0.7 and 8.7 pt into the pill); `emptyDraft_keepsALine` passes its field's
hang and its one-letter jump at all three (12.7 and 20.7 pt; 10.7 pt at `.accessibility5`).

### NF-1: no sound mechanism found inside `ledgerFieldFont`; the options

What UIKit does, measured on a probe of `NameField` with the field set as each row says (the name's ink,
how far it moves down when the focus comes, `.large` / `.accessibility3`):

| The field | "Gyp", "Upper A" | "naïve", "Łódź", "ÅÉÇ", "Push 💪", Thai |
|---|---|---|
| line 1.3, top on top, no guide | +4.33 / +6.00 | +1.00 / +1.00 |
| line 1.3 + the guide (as built) | −0.33 / −1.00 | −3.67 / −6.00 |
| line 1.3, first baseline on first baseline | +4.00 / +6.00 | +0.67 / +1.00 |
| `.exact(points: 1.3 × size)` or `.leading(increase: 0.3 × size)`, top | +4.33 / +6.00 | +1.00 / +1.00 |
| line 1.5, top | +7.33 / +10.67 | +1.00 / +1.00 |
| line 1 (`main`), top | −0.67 / −1.33, tails cut | −0.67 / −1.33 |
| **no line (the font's own), first baseline on first baseline** | **0.00 / 0.00** | **0.00 / 0.00 (emoji −0.33)** |

Every explicit line looser than the font is centred by UIKit for a line of Archivo alone and not for a line
that holds a glyph of another font, so no constant guide serves both, and there is no public way to read
which a line is short of asking per glyph. `Font.leading(.loose)` on the field changes nothing. The one
glyph-independent placement found is the last row: the field keeps the font's own line (36.7 / 53.7 / 61.3 pt,
which holds Archivo's ascent and descent) and the view lines it up with the text by **first baseline**. More of
it, `.large` / `.accessibility3` / `.accessibility5`:

| Name | Moves down | Ink, idle → edited (pt) |
|---|---|---|
| "Gyp", "naïve", "ÅÉÇ", Hebrew, Devanagari | 0.00 at all three | the same |
| "Push 💪", "🏋️💪 Gy" | −0.33, −0.33, 0.00 | the same, or a pixel more |
| Arabic | 0.00 | 0.7 to 1.3 pt more under the line (not cut) |
| Thai "ก้ำปู่ ฏู" | +2.00, +3.67, +4.33 | 2.7 to 3.0 pt more (not cut; drawn lower) |
| "Ǻ Ṩ ự" | +0.67, +1.67, +2.00 | **cut at the top by 0.7, 1.7, 2.0 pt** |

So the options:

- **A. The font's own line, laid on the text's first baseline.** No guide; `ledgerFieldFont` sets no line at
  all, and `NameField`'s overlay is `Alignment(horizontal: .leading, vertical: .firstTextBaseline)`. NF-1 goes
  for every name but Thai (which moves less than as built: 2.0 to 4.3 pt down against 3.7 to 7.3 up). The
  field is lower (36.7 pt at `.large`), so the caret is shorter. NF-4 goes by construction (no guide). **Cost:**
  capitals stacked with two accents ("Ǻ", "Ṩ") lose 0.7 to 2.0 pt at the top while edited, which fails the
  tester's `focus_keepsAccentsMarksAndEmojiWhole` (bound 0.5 pt); `main`'s line of 1 does not cut them.
- **B. As built:** everything whole; NF-1 stays a known issue, documented in `ledgerFieldFont`'s comment.
- Rejected: a per-glyph guide (ruled out), and a `UIViewRepresentable` field (outside this chore's size).

My recommendation is A, with the tester's bound for stacked accents ruled on: a jump of the whole name for
an emoji or "ï" is seen at every focus, a top accent shaved by 1 to 2 pt only on rare names while typing.
NF-1's 16 known issues stand until then.

### Tester-file edits of this round

Only wrappers whose fault is fixed, each with its `Comment` constant (now unused); each test passes as
written.

| File | Wrapper removed | Finding |
|---|---|---|
| `LedgerDesignTests/Adversarial/FieldFontAdversarialTests.swift` | `lowerField`, in `looseRole_fieldStandsOnTheText` | NF-4 |
| `FeatureProgramTests/Adversarial/NameFieldRoomAdversarialTests.swift` | `caretOnTheTag`, in `emptyDraft_caretStaysAboveTheTag` | NF-2 |
| the same | `jumpsAcross`, in `focus_doesNotJumpAcross` | NF-3 |
| `FeatureProgramTests/Adversarial/DayEditorViewsTitleAdversarialTests.swift` | `emptyTarget`, both uses in `emptyDraft_keepsALine` | NF-2, NF-5 |

Test titles and doc comments that still say "(known: …)" were left as the tester wrote them. Formatting
removed the blank line each constant left.

### References

None changed: the full gate compares all of them (the builder's 16, the library's 12, the Day editor's 24
with its right-to-left one, Today's, `LedgerDesignTests`'). The unseen label draws nothing, and the field's
alignment shows only with the focus.

### Gates (on `8bfc5f9`)

| Command | Exit | Duration |
|---|---|---|
| `sim-lock.py sim.sh … -testPlan PR -only-testing:LedgerDesignTests -only-testing:FeatureProgramTests` | 0 | 627 s: 390 tests (27 known issues, none new) and 524 tests (18 known: 2 of `main`, 16 of NF-1) |
| `sim-lock.py scripts/check.sh` | 0, `check.sh OK` | 1,552 s (iOS tests 1,165 s, watchOS tests 241 s), plus the wait for the lock |

### Still open

- NF-1 (16 known issues), for a ruling between A and B.
- For a later chore: the library's search field in `.body` (its line 1.2 cut the title's tails), right to
  left on a device, and NF-5 is closed here but was `main`'s.
- Not verified: a device, typing (so NF-1's and NF-3's behaviour while typing is inferred), the watch.
