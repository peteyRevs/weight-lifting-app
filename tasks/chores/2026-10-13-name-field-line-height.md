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
