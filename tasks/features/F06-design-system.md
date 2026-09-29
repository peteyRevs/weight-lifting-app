# F06 — Design system: tokens, Archivo, components, snapshots

| | |
|---|---|
| Milestone | M0 |
| Status | ready |
| Depends on | F00 |
| Branch | `feat/F06-design-system` |
| Design refs | `design/prototype/Ledger v2.dc.html` (primary visual system), `Ledger.dc.html` (light tokens), `LedgerWatch.dc.html`, `LedgerTabsDark.dc.html` |
| Spec refs | `docs/product-spec.md` §8.1–§8.8; `docs/product-decisions.md` #1, #17; `docs/architecture.md` §11; R2 §5 |

## Goal
`LedgerDesign` turns the prototype's visual language into typed tokens and reusable SwiftUI components with snapshot tests, so every feature looks like the design without a single raw color, font or padding literal. It also settles the one open visual risk: rendering Archivo's width axis on iOS and watchOS.

## User stories
- As a feature implementer, I compose screens from `LedgerDesign` components and tokens only, and lint stops me if I don't.
- As Pete, the app matches the v2 prototype pixel-for-pixel in intent: dark ground, hairlines, one orange per screen, heavy narrow numerals.

## Scope
**In:** tokens (colors light/dark/watch, type, spacing, radius, hairline, motion), Archivo loading with `wdth` axis + spike, components below with previews and snapshots, the SwiftLint custom rules (config in F00; this brief adds the regexes' allowlist for `LedgerDesign`), a `DesignGallery` debug screen.
**Out:** feature screens, tab bar (native `TabView` tinted with `LedgerColor.accent` is used; the prototype's custom bar is not replicated).

## Touches
- `LedgerKit/Sources/LedgerDesign/Tokens/{LedgerColor,LedgerFont,LedgerSpacing,LedgerRadius,LedgerHairline,LedgerMotion}.swift`
- `LedgerKit/Sources/LedgerDesign/Fonts/{ArchivoFont,FontRegistration}.swift`
- `LedgerKit/Sources/LedgerDesign/Components/{PrimaryButton,PillButton,IconPillButton,Eyebrow,HairlineList,HairlineRow,SetRow,Stepper,RestRing,WeekStrip,StatTile,ProgressSegments,SheetChrome,EmptyState,WatchPrimaryButton,WatchRestRing}.swift`
- `LedgerKit/Sources/LedgerDesign/Gallery/DesignGallery.swift`
- `LedgerKit/Tests/LedgerDesignTests/**` + `__Snapshots__/`
- `Resources/Fonts/Archivo[wdth,wght].ttf` (already bundled by F00), `.swiftlint.yml` (allowlist tweaks only)

## Domain changes
None (no `LedgerDomain` dependency). Public surface:
```swift
public enum LedgerColor {   // SwiftUI Color, adaptive light/dark via asset catalog or dynamic provider
    public static let ground, surface, ink, inkSecondary /* .72 */, inkMuted /* .45 */, inkFaint /* .32 */, hairline /* .08 */, hairlineStrong /* .14 */, accent /* #FF5B22 */, accentSoft /* accent .16 */, onAccent, watchGround /* #000 */
}
public enum LedgerFont {
    public enum Role { case display, title, heading, body, bodyLight, label, eyebrow, numeralXL, numeralL, numeralM, numeralS, watchNumeral, watchLabel }
    public static func font(_ role: Role, dynamicTypeSize: DynamicTypeSize, legibilityWeight: LegibilityWeight? = nil) -> Font  // Dynamic Type–scaled; tabular numerals for numeral roles
    public static func font(_ role: Role, size: CGFloat, legibilityWeight: LegibilityWeight? = nil) -> Font                     // an already scaled size, floored
    public static func scaledSize(_ role: Role, dynamicTypeSize: DynamicTypeSize) -> CGFloat
    public static func archivo(size: CGFloat, weight: CGFloat /* 300…700 */, width: CGFloat /* 88…112 */) -> Font
}
public enum LedgerSpacing { public static let xs: CGFloat = 4, s = 8, m = 12, l = 16, xl = 24, xxl = 32, screen = 26 }
public enum LedgerRadius { public static let pill: CGFloat = 999, card = 26, sheet = 28, row = 16 }
extension View { public func ledgerFont(_ role: LedgerFont.Role) -> some View }  // the usual path: reads Dynamic Type and Bold Text from the environment
public enum LedgerMotion { public static let snappy: Animation; public static func buzzKeyframes(reduceMotion: Bool) -> some Keyframes<BuzzFrame> /* 3 × 0.38 s x-shake, or an opacity pulse under Reduce Motion */ }
extension View { public func ledgerBuzz(trigger: some Equatable & Sendable) -> some View }
```
Token values come from spec §8: dark ground `#0B0B0D`, text `#F4F2ED`, alphas .72/.45/.32/.08/.14; light paper `#EFEDE6`, ink `#16150F`; accent `#FF5B22`; type sizes/weights/widths per role from §8.5 (numerals weight 700, width 88–92; labels 300/500; eyebrows 10 px 500 letter-spacing .18em uppercase).

Components (each with all states + `#Preview` + snapshot):
`PrimaryButton(title:icon:action)` (orange pill, the one accent per screen) · `PillButton(title:style:.outline/.filled/.ghost)` · `IconPillButton` (44 pt) · `Eyebrow(text:tint:)` · `HairlineList { HairlineRow(...) }` (rows separated by 1 px `.hairline`, top rule) · `SetRow(number:weight:reps:state:.pending/.active/.done, onSelect:onCheck:)` + `SetRowSteppers(weightStep:repStep:...)` · `RestRing(progress:label:size:)` (dash math from §8.8; `stroke-dasharray` 553 / 182 equivalents) · `WeekStrip(days:[DayMark])` · `StatTile(value:unit:caption:delta:)` · `ProgressSegments(segments:[Segment])` · `SheetChrome(title:cancel:) { }` · `EmptyState(title:body:action:)` · watch: `WatchPrimaryButton`, `WatchRestRing`, `WatchStatBlock`.

## Acceptance criteria
1. **Spike (first task):** Given Archivo loaded via `UIFontDescriptor` + `kCTFontVariationAttribute` (axis `2003072104`), when rendered at width 88 and 112 on the iOS 26.5 **and** watchOS 26.5 simulators, then the two glyph widths differ (snapshot pixel-width assertion). If watchOS fails, the fallback (static `Archivo SemiCondensed`/`Narrow` instances mapped from width buckets) is implemented and the spike result recorded in `implementation-notes.md` and `docs/architecture.md` §17 risk 2.
2. Given `LedgerColor` in light and dark, when snapshotted, then hex values match spec §8.1–8.3 (test reads resolved `UIColor` components).
3. Given every component × {light, dark} × {`.large`, `.xLarge`, `.accessibility3`} Dynamic Type, when snapshotted at iPhone 17 width, then images match committed references (precision 0.995, perceptual 0.98).
4. Given watch components at 42, 46 and 49 mm, when snapshotted, then no label falls below 11 pt and nothing clips.
5. Given `RestRing(progress: 0.5)`, then the arc covers exactly half the circumference (path-length assertion on the rendered shape).
6. Given `PrimaryButton`, then it has `accessibilityLabel` = title, `.isButton` trait, and a 44 pt minimum hit target on iOS.
7. Given Reduce Motion enabled, when `LedgerMotion.buzz` is applied, then no transform animation runs (opacity pulse instead).
8. Given a feature file with `Color(red:…)`, `.font(.system(size:…))`, or `.padding(13)`, when SwiftLint runs, then the custom rules `ledger_raw_color`, `ledger_raw_font`, `ledger_raw_spacing` fail it; the same code inside `LedgerDesign` passes.
9. Given `DesignGallery`, when opened from the debug menu, then every component and every token is visible with its name.

## Test plan
- Unit (LedgerDesignTests): `ArchivoFontTests` (registration, width axis spike, fallback mapping), `TokenValueTests` (criterion 2), `MotionTests` (7).
- Snapshot (LedgerDesignTests, swift-snapshot-testing 1.19.x with Swift Testing): one suite per component, matrix per criterion 3; watch suite per criterion 4; `RestRingGeometryTests` (5).
- Accessibility: `ComponentAccessibilityTests` (6) using the accessibility snapshot strategy.
- Lint fixture: `scripts/tests/lint-rules.test.sh` with positive/negative Swift snippets (8).

## Non-functional
- Snapshot references ≤ 6 MB total (use 1× scale, JPEG-free PNG).
- Font loading once at process start (`FontRegistration.registerIfNeeded()`), < 5 ms.
- Contrast: informational text at ≥ 4.5:1 where it carries meaning; the .32 alpha is decorative only (decision list in notes).

## Risks / unknowns
- watchOS variable-font axis support (spike).
- Dynamic Type with a custom font on watchOS — verify `@ScaledMetric` behaviour.

## Decisions during delivery (Pete, 2026-09-29, after slice 1 failed the adversarial gate three times)
Recorded verbatim; they change this brief's contract. Implemented in fix round 3 (`F06-design-system/implementation-notes.md`).

1. **Text uses native SwiftUI line height only.** Keep `.lineHeight(.multiple(factor:))`. Remove the CSS half-leading emulation (the `lift` computed from `ArchivoFont.baselineBelowMiddle` and the `.padding(.top, -lift).padding(.bottom, lift)`) and any code that exists only for it. Single lines may sit 1–10 pt off the HTML prototype; slice-2 components absorb that with spacing tokens.
2. **The design lint is a tripwire, not a proof.**
   - Close finding 21's 16 raw spellings where a rule can do it simply.
   - Fix finding 23's false positives on sanctioned token use.
   - Then freeze the rule set. Document it as a list, and document its known limits, finding 22's escape hatches included, in docs/engineering-standards.md next to the design-lint rule, or wherever the lint is documented today.
   - State that "tokens only" is enforced by review (docs/subagent-workflow.md review point 4), and that the lint is not meant to catch every spelling.

For criterion 8 this means: the rules and their known limits are listed in `docs/engineering-standards.md` §7 ("Design lint"), and the lint is not expected to flag the listed limits.

## Definition of Done
Inherits `docs/engineering-standards.md` §12, plus:
- [ ] Side-by-side screenshots of `DesignGallery` vs prototype sections attached to the PR.
- [ ] Spike outcome recorded in architecture risk register.

---
_Filled in by agents during delivery:_
- `F06-design-system/implementation-notes.md`
- `F06-design-system/test-findings.md`
- `F06-design-system/review.md`
