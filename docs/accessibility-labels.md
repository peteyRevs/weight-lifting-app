# Accessibility labels of icon-only buttons

F15 criterion 8. Every button in the iPhone and watch sources that draws an icon and no text is listed here, with
what VoiceOver reads for it. An icon has no words, so each of these gets its words from the copy, never from the
icon.

The columns:
- **Source** and **Call**: the file under `LedgerKit/Sources` and the start of the line that draws the button.
- **Wired by**: the file that hands the shipped button its words, by naming the copy.
- **Copy** and **English**: the copy property and its English words. Each `\(…)` is filled in when the app runs.
- **Pinned by**: the test file that holds those words where the app draws them. That is a hosted accessibility tree,
  except where the row says otherwise.

`AccessibilityLabelsDocTests` (LedgerAppKitTests) reads these tables and the sources. It fails when:
- a button in `LedgerKit/Sources` draws only an icon and has no row here;
- a row names a call that is no longer in its file;
- a row's copy no longer holds its English words (the copy is found by its type's name in any module, since a design
  component's words come from the feature that uses it);
- a row's "Wired by" file does not name its copy;
- a row's "Pinned by" file holds neither its English words (with each `\(…)` filled by any text) nor its copy, or,
  for a row with no copy, does not name its component;
- a row is malformed.

A button counts as icon-only when it is one of these:
- an `IconPillButton(` call;
- a `Button` or a `Menu` whose label starts with a `LedgerIconView`, a `SetRowCheck` or an `Image(`, either inside
  its braces on the same line or on the line after its opening brace or `label: {`;
- anything given `.labelStyle(.iconOnly)`.

Previews and galleries are not counted. `IconPillButton`'s own definition is not counted either: its calls are.

## Buttons VoiceOver reads as buttons

| Control | Source | Call | Wired by | Copy | English | Pinned by |
|---|---|---|---|---|---|---|
| Today's gear, opens Settings | `FeatureToday/Views/TodayHeader.swift` | `IconPillButton(model.settings.title, systemImage: "gearshape")` | `TodayPresentation.swift` | `TodayCopy.settings` | `Settings` | `TodayAccessibilityTrees` |
| The solo card's swap button | `FeatureWorkout/Views/ExerciseCard.swift` | `IconPillButton(swap, icon: .swap)` | `WorkoutPresentation+Card.swift` | `WorkoutCopy.swapExercise` | `Swap exercise` | `WorkoutAccessibilityTrees` |
| A superset member's swap button | `FeatureWorkout/Views/SupersetBlock.swift` | `IconPillButton(swap, icon: .swap)` | `WorkoutPresentation+Superset.swift` | `WorkoutCopy.swapMember` | `Swap \(name)` | `WorkoutAccessibilityTrees+Block` |
| A set row's check, a numbered set not logged | `LedgerDesign/Components/SetRow.swift` | `Button(action: onCheck) { SetRowCheck(state: state) }` | `WorkoutPresentation+Card.swift` | `WorkoutCopy.logSet` | `Log set \(number)` | `WorkoutAccessibilityTrees` |
| A set row's check, a numbered set logged | `LedgerDesign/Components/SetRow.swift` | `Button(action: onCheck) { SetRowCheck(state: state) }` | `WorkoutPresentation+Card.swift` | `WorkoutCopy.undoSet` | `Undo set \(number)` | `WorkoutAccessibilityTrees` |
| A set row's check, a drop set not logged | `LedgerDesign/Components/SetRow.swift` | `Button(action: onCheck) { SetRowCheck(state: state) }` | `WorkoutPresentation+Card.swift` | `WorkoutCopy.logDropSet` | `Log drop set` | `AccessibilityTreeSetRowTables` |
| A set row's check, a drop set logged | `LedgerDesign/Components/SetRow.swift` | `Button(action: onCheck) { SetRowCheck(state: state) }` | `WorkoutPresentation+Card.swift` | `WorkoutCopy.undoDropSet` | `Undo drop set` | `WorkoutPresentationCardTests` |
| A set row's check, a superset row not logged ("A2") | `LedgerDesign/Components/SetRow.swift` | `Button(action: onCheck) { SetRowCheck(state: state) }` | `WorkoutPresentation+Card.swift` | `WorkoutCopy.logRow` | `Log set \(label)` | `WorkoutAccessibilityTrees+Block` |
| A set row's check, a superset row logged | `LedgerDesign/Components/SetRow.swift` | `Button(action: onCheck) { SetRowCheck(state: state) }` | `WorkoutPresentation+Card.swift` | `WorkoutCopy.undoRow` | `Undo set \(label)` | `WorkoutAccessibilityTrees+Block` |

"Undo drop set" is pinned by `WorkoutPresentationCardTests`, which holds the label the card hands the set row: no
hosted tree draws a logged drop set. How the set row reads any check label it is given is pinned once, by
`AccessibilityTreeSetRowTables`.

## Buttons folded into one adjustable element

Each of these pairs, "−" and "+", is one element to VoiceOver. It reads the field's label and its value, and a
swipe up or down takes a step. The buttons' own labels are never read.

| Control | Source | Call | Wired by | Copy | English | Pinned by |
|---|---|---|---|---|---|---|
| The builder's block length, "−" | `FeatureProgram/Views/BlockSection.swift` | `IconPillButton(model.spokenLabel, icon: .minus)` | `ProgramPresentation+Weeks.swift` | `ProgramCopy.blockLength` | `Block length` | `ProgramAccessibilityTrees` |
| The builder's block length, "+" | `FeatureProgram/Views/BlockSection.swift` | `IconPillButton(model.spokenLabel, icon: .plus)` | `ProgramPresentation+Weeks.swift` | `ProgramCopy.blockLength` | `Block length` | `ProgramAccessibilityTrees` |
| A set row's weight and reps steppers (the workout, the edit-sets sheet) | `LedgerDesign/Components/SetRowSteppers.swift` | `LedgerIconView(icon, sizedAs: .subheading)` | — | — | the stepper's own label, given by its caller | `AccessibilityTreeSetRowTables` |
| A stepped field: Default rest, Bar, a slot's sets and reps | `LedgerDesign/Components/StepperField.swift` | `LedgerIconView(icon, sizedAs: .subheading)` | — | — | the field's own label, given by its caller | `StepperFieldTests` |

## Not icon-only

These draw their words, so VoiceOver reads what is drawn:
- the cover header's "Minimize" and "Finish";
- the rest panel's "+30s" and "Skip rest";
- the picker's rows, which draw "+" or a check beside the exercise's name.
