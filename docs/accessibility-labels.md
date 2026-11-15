# Accessibility labels of icon-only buttons

F15 criterion 8. Every button in the iPhone and watch sources that draws an icon and no text is listed here, with
what VoiceOver reads for it. An icon has no words, so each of these gets its words from the copy, never from the
icon.

`AccessibilityLabelsDocTests` (LedgerAppKitTests) reads this table and the sources, and fails when:
- a button in `LedgerKit/Sources` draws only an icon and has no row here;
- a row names a call that is no longer in its file;
- a row's copy no longer holds its English words (the copy is found by its type's name in any module: a design
  component's words come from the feature that uses it).

A button counts as icon-only when it is one of these:
- an `IconPillButton(` call;
- a `Button` whose label is a `LedgerIconView` or the set row's `SetRowCheck` and nothing else, on the line after
  `} label: {` or inside the `Button(…) { … }` on the same line.

Previews and galleries are not counted. `IconPillButton`'s own definition is not counted either: its calls are.

The spoken words are pinned in the running layout by each module's hosted accessibility trees, named in the last
column. The UI audits (`Apps/LedgerUITests/Audit*.swift`) check in the running app that each one has a label.

## Buttons VoiceOver reads as buttons

| Control | Source | Call | Copy | English | Pinned by |
|---|---|---|---|---|---|
| Today's gear, opens Settings | `FeatureToday/Views/TodayHeader.swift` | `IconPillButton(model.settings.title, systemImage: "gearshape")` | `TodayCopy.settings` | `Settings` | `TodayAccessibilityTrees` |
| The solo card's swap button | `FeatureWorkout/Views/ExerciseCard.swift` | `IconPillButton(swap, icon: .swap)` | `WorkoutCopy.swapExercise` | `Swap exercise` | `WorkoutAccessibilityTrees` |
| A superset member's swap button | `FeatureWorkout/Views/SupersetBlock.swift` | `IconPillButton(swap, icon: .swap)` | `WorkoutCopy.swapMember` | `Swap \(name)` | `WorkoutAccessibilityTrees` |
| A set row's check, a numbered set not logged | `LedgerDesign/Components/SetRow.swift` | `Button(action: onCheck) { SetRowCheck(state: state) }` | `WorkoutCopy.logSet` | `Log set \(number)` | `WorkoutAccessibilityTrees` |
| A set row's check, a numbered set logged | `LedgerDesign/Components/SetRow.swift` | `Button(action: onCheck) { SetRowCheck(state: state) }` | `WorkoutCopy.undoSet` | `Undo set \(number)` | `WorkoutAccessibilityTrees` |
| A set row's check, a drop set not logged | `LedgerDesign/Components/SetRow.swift` | `Button(action: onCheck) { SetRowCheck(state: state) }` | `WorkoutCopy.logDropSet` | `Log drop set` | `WorkoutAccessibilityTrees` |
| A set row's check, a drop set logged | `LedgerDesign/Components/SetRow.swift` | `Button(action: onCheck) { SetRowCheck(state: state) }` | `WorkoutCopy.undoDropSet` | `Undo drop set` | `WorkoutAccessibilityTrees` |
| A set row's check, a superset row not logged ("A2") | `LedgerDesign/Components/SetRow.swift` | `Button(action: onCheck) { SetRowCheck(state: state) }` | `WorkoutCopy.logRow` | `Log set \(label)` | `WorkoutAccessibilityTrees` |
| A set row's check, a superset row logged | `LedgerDesign/Components/SetRow.swift` | `Button(action: onCheck) { SetRowCheck(state: state) }` | `WorkoutCopy.undoRow` | `Undo set \(label)` | `WorkoutAccessibilityTrees` |

## Buttons folded into one adjustable element

Each of these pairs, "−" and "+", is one element to VoiceOver. It reads the field's label and its value, and a
swipe up or down takes a step. The buttons' own labels are never read.

| Control | Source | Call | Copy | English | Pinned by |
|---|---|---|---|---|---|
| The builder's block length, "−" | `FeatureProgram/Views/BlockSection.swift` | `IconPillButton(model.spokenLabel, icon: .minus)` | `ProgramCopy.blockLength` | `Block length` | `ProgramAccessibilityTrees` |
| The builder's block length, "+" | `FeatureProgram/Views/BlockSection.swift` | `IconPillButton(model.spokenLabel, icon: .plus)` | `ProgramCopy.blockLength` | `Block length` | `ProgramAccessibilityTrees` |
| A set row's weight and reps steppers (the workout, the edit-sets sheet) | `LedgerDesign/Components/SetRowSteppers.swift` | `LedgerIconView(icon, sizedAs: .subheading)` | — | the stepper's own label, given by its caller | `AccessibilityTreeSetRowTables` |
| A stepped field: Default rest, Bar, a slot's sets and reps | `LedgerDesign/Components/StepperField.swift` | `LedgerIconView(icon, sizedAs: .subheading)` | — | the field's own label, given by its caller | `StepperFieldTests` |

## Not icon-only

These draw their words, so VoiceOver reads what is drawn:
- the cover header's "Minimize" and "Finish";
- the rest panel's "+30s" and "Skip rest";
- the picker's rows, which draw "+" or a check beside the exercise's name.
