# F06 — implementation notes

Branch `feat/F06-design-system` (from `main` 8404d02). F06 ships as three PRs,
each through the full gate (engineering-standards §10: ≤ 500 changed product
lines; the F02 waiver does not carry over). **This file covers slice 1:
tokens, Archivo loading and the width-axis spike, the lint allowlist, and
their tests and snapshots.**

## Slice plan

| Slice | Contents | Criteria |
|---|---|---|
| **1 (this PR)** | `Tokens/*` (colour light/dark/watch, type, spacing, radius, hairline, motion), `Fonts/*` (Archivo registration and axis instances), the `wdth` spike on both simulators, the design-lint allowlist and its fixture test, snapshot infrastructure in `LedgerSnapshotTesting` | 1, 2, 7, 8; the criterion 3 matrix is exercised by the token specimens |
| 2 | The most-used phone primitives: `PrimaryButton`, `PillButton`, `IconPillButton`, `Eyebrow`, `HairlineList` / `HairlineRow`, `SetRow` + `SetRowSteppers` (the brief's `Stepper`), `RestRing`, with previews and the 6-image matrix each; `RestRingGeometryTests`, `ComponentAccessibilityTests` | 3 (these components), 5, 6 |
| 3 | `WeekStrip`, `StatTile`, `ProgressSegments`, `SheetChrome`, `EmptyState`, `WatchPrimaryButton`, `WatchRestRing` (reuses slice 2's ring geometry), `WatchStatBlock` at 42 / 46 / 49 mm, and `DesignGallery` (token pages plus every component, named); side-by-side gallery vs prototype screenshots for the PR | 3 (the rest), 4, 9 |

Slice 2 goes first because every Today and Active-workout screen (F09, F10)
needs those eight views; slice 3 holds the watch set and the gallery, which
depends on everything else existing. Each slice is roughly 400–450 product
lines by the same measure as below.

## Archivo width axis on watchOS — spike result (criterion 1, risk R2)

**Verdict: the variable `wdth` axis works on the watchOS 26.5 simulator. No
static-instance fallback was needed or built.**

- Path: a `CTFontDescriptor` for the variable font's default instance
  (`Archivo-SemiBold`) with `kCTFontVariationAttribute` =
  `['wght': w, 'wdth': x]`, `CTFontCreateWithFontDescriptor`, wrapped as
  SwiftUI `Font(ctFont)` (`Fonts/ArchivoFont.swift`).
- Evidence, from the recorded sheets (`"0123456789"`, 30 pt, wght 700, 1×,
  inked width per row, measured from the PNGs):

  | wdth | 62 | 88 | 100 | 112 | 125 |
  |---|---|---|---|---|---|
  | iPhone 17, iOS 26.5 | 118 px | 158 px | 176 px | 198 px | 223 px |
  | Apple Watch Series 11 46 mm, watchOS 26.5 | 118 px | 158 px | 176 px | 198 px | 223 px |

  The two platforms render identically. The sheets are committed as
  `__Snapshots__/ArchivoFontTests/widthAxis_88versus112_rendersDifferentGlyphWidths.{iOS,watchOS}.png`.
- The test asserts, on each simulator, that wdth 112 renders more than 1.15×
  wider than wdth 88 (host advance ratio 1.26), that wght 700 lays down > 1.3×
  the ink of wght 300, that Core Text reports the requested axis values on the
  instance, and that the bundled file's `fvar` is wght 100–900 / wdth 62–125.
- Recorded in `docs/architecture.md` §17 risk 2 (closed). Not yet seen on
  hardware (F20's device checklist should include one glance at a numeral) or
  in complications, which R2 §6.2 flags as possibly ignoring custom fonts.

## Decisions

1. **The font ships once, inside `LedgerDesign`.** `Archivo[wdth,wght].ttf` and
   `OFL.txt` moved from `Resources/Fonts/` to
   `LedgerKit/Sources/LedgerDesign/Resources/` (`.copy` resources). Package test
   bundles and Xcode previews have no app bundle, so the design system has to
   carry its own font; a second copy would put two 658 KB files in git and in
   each app. Both apps' `UIAppFonts` now name
   `LedgerKit_LedgerDesign.bundle/Archivo[wdth,wght].ttf`, so the system still
   registers the font at launch, and F00's `archivo_isRegistered` smoke tests
   (unchanged) guard that path. Verified in the built products: the resource
   bundle holds the font in both `Ledger.app` and `LedgerWatch.app`.
   `FontRegistration.registerIfNeeded()` registers from `Bundle.module` once per
   process (a `static let` initializer), treats "already registered" as success
   by checking the name resolves, and is called by `ArchivoFont.make` before
   every instance, so previews and tests need no setup.
   Cost (host, M-series, `ContinuousClock`): app path (already registered by the
   system) 1–3.5 ms; package-only path (previews/tests) ~7 ms warm, 33 ms cold.
   The < 5 ms budget holds where it matters, in the apps.
2. **`CTFontDescriptor` instead of `UIFontDescriptor`.** They are toll-free
   bridged; Core Text keeps UIKit out of font code and builds on the macOS host
   slice that `swift test` uses.
3. **Text styling is a modifier, `.ledgerFont(_:)`.** A `Font` cannot carry
   tracking, case or line height, and a `Font(ctFont)` does not follow Dynamic
   Type. The modifier scales the role's size with `@ScaledMetric(relativeTo:)`
   (architecture §11), then applies `tracking` (em × scaled size),
   `textCase(.uppercase)` and iOS 26's `lineHeight(.multiple(factor:))` — the
   CSS line-height, exactly. `LedgerFont.font(_:)` stays as the bare `Font` at
   the design size (the brief's comment called it "Dynamic Type–scaled"; it
   cannot be) and `font(_:size:)` takes an already scaled size.
4. **21 type roles**, values copied from the v2 and watch prototypes'
   `font:` declarations (table in `TypeScaleTests`). Added to the brief's 13:
   `subheading` (sheet title 21 pt), `caption` (400 12 pt metadata), `button`
   (600 16 pt CTA), and watch `Countdown` / `Stat` / `Title` / `Button` /
   `Caption`, which the slice 3 watch components need. `display` is the
   onboarding title (38 pt): the 84 pt hero is prototype-page chrome, not app UI.
5. **Watch Dynamic Type (the brief's second risk).** Measured on the watch
   simulator: `@ScaledMetric` returns its base value at **`.xLarge`**, not
   `.large` (body 95 / 100 / 105 at large / xLarge / xxLarge), and HIG lists
   xLarge as the 44–49 mm default and Large as the 40–42 mm default.
   `ImageRenderer` does not inherit the simulator's text size, so tests set it:
   `SnapshotConfig.referenceDynamicTypeSize` (iOS `.large`, watchOS `.xLarge`)
   and `WatchSize.dynamicTypeSize` (42 mm `.large`, 46 / 49 mm `.xLarge`). Watch
   role sizes are the prototype's px ÷ 1.5, exact at xLarge. At the 42 mm
   default they scale to ~94 %, which would put the 11.3 pt labels at 10.6 pt and
   break criterion 4, so watch roles carry an **11 pt floor**
   (`LedgerTypeSpec.minimumSize`, tested at `.xSmall`).
6. **Colours.** Adaptive tokens are a dynamic `UIColor` on iOS (resolves from
   SwiftUI's colour scheme, verified by criterion 2's tests); watchOS has one
   appearance and no dynamic `UIColor`, so it takes the dark value; macOS
   exists only for the host build. Added to the brief's list, each from the
   spec: `accentText` (`#C63F0F` on paper, spec §8.1 "orange text on paper uses
   #C63F0F for contrast"), `accentLine` (accent 40 %, the active-set rule),
   `inkDim` (28 %, the v2 `DIM` done rows), and the watch ink family
   (`watchInk`, `…Secondary` 55 %, `…Muted` 40 %, `watchOutline` 22 %,
   `watchHairline` 14 %, `watchTrack` 13 %). `accentSoft` is 12 % on paper
   (`accentTint`, §8.1) and 16 % on dark (§8.3).
7. **Contrast (non-functional requirement).** WCAG ratios against the ground:

   | Token | dark | light (paper) |
   |---|---|---|
   | `ink` | 17.6 | 15.6 |
   | `inkSecondary` .72 | 9.2 | 6.7 |
   | `inkMuted` .45 | 4.2 | 2.9 |
   | `inkFaint` .32 / `inkDim` .28 | 2.6 / 2.3 | 2.0 / 1.8 |
   | `accent` (text) | 6.3 | 2.7 → use `accentText` 4.35 |
   | `onAccent` on `accent` | 3.1 | 3.1 |
   | watch `…Secondary` / `…Muted` on black | 6.3 / 3.7 | — |

   Only `ink` and `inkSecondary` meet 4.5:1 on both grounds, so only they may
   carry meaning in small text (documented on `LedgerColor`). `inkMuted`,
   `accentText` on paper (4.35) and white on orange (3.1, which passes only
   WCAG's 3:1 for large text; the 16 pt semibold CTA label is borderline) sit
   below 4.5:1 exactly as the prototype has them. **For Pete:** accept these as designed, or darken
   `inkMuted` / `accentDeep` in the light theme.
8. **Motion.** `LedgerMotion.buzzKeyframes(reduceMotion:)` is spec §8.8's
   `@keyframes buzz` (offsets −3, 3, −2, 2, 0 at 20 % steps, CSS `ease` as a
   cubic Bézier, 3 × 0.38 s); `View.ledgerBuzz(trigger:)` plays it with
   `keyframeAnimator`. Under Reduce Motion the offset track is 0 throughout
   and opacity dips to 0.4 once per cycle. Tests sample the same keyframes
   through `KeyframeTimeline` every millisecond. The brief's
   `static let buzz: Animation` cannot express a transform or a Reduce Motion
   alternative, so it is replaced by these two (`buzzCycle`, `buzzRepeats`
   remain as values).
9. **Design lint.** F00's `feature_raw_*` rules are renamed to the brief's
   `ledger_raw_color` / `_font` / `_spacing` / `_radius` and their scope is
   inverted: they now cover all of `LedgerKit/Sources` and `Apps`, with
   `LedgerDesign` (and the test-only targets) as the one allowlisted module
   (a YAML anchor keeps the four lists identical). Before, only `Feature*`
   modules were checked, so the umbrella roots and app shells, where F07 builds
   the tab shell, could spell raw values. `identifier_name` now excludes
   `^(xs|s|m|l|xl)$` for `LedgerSpacing`'s steps (nested configs are ignored
   under `--config`, so the exclusion is repo-wide). `scripts/tests/lint-rules.test.sh`
   (run by `check.sh` step 2) lints each rule's snippet in a feature module, an
   app shell and `LedgerDesign`; mutation-checked against both a missing
   allowlist and F00's feature-only scope.
10. **Snapshot infrastructure (`LedgerSnapshotTesting`, test-only).**
    swift-snapshot-testing 1.19.6 has no image strategy on watchOS (its SwiftUI
    and `UIImage` strategies are `#if os(iOS) || os(tvOS)`), and its newest
    device config is `iPhone13ProMax` (no iPhone 17). So: iOS uses the
    library's `.image(precision:perceptualPrecision:layout:traits:)` at 1× and
    402 pt width; watchOS (and pixel measurements everywhere) use
    `RenderedImage.render` (`ImageRenderer`, 1×) plus a `.png` strategy whose
    diff applies the same thresholds (CIE76 ΔE ≤ 2, 99.5 % of pixels). The
    matrix (`SnapshotAppearance.phoneMatrix`), tolerances and watch sizes live
    in `SnapshotConfig`. Reference names carry the platform where a test runs
    on both. `testing-strategy.md` §2.5 is updated with these findings.
11. **`check.sh --record-snapshots` now works.** It exported
    `SNAPSHOT_TESTING_RECORD`, which `xcodebuild` does not forward to the
    simulator's test runner, and `set -e` stopped at the iOS step, so watch
    references could never be recorded. It now exports
    `TEST_RUNNER_SNAPSHOT_TESTING_RECORD=all`, runs both plans, lists
    `__Snapshots__` changes and exits 1 (F00 note 8 left this to F06).
12. **`Package.swift`:** the `LedgerDesign` resources, and `exclude:
    ["__Snapshots__"]` for test targets listed in `snapshotTestTargets`
    (otherwise SwiftPM warns about unhandled PNGs; an exclude of a missing
    folder also warns, hence the explicit list). The package graph is unchanged.

## Deviations from the brief

- Criterion 1 names `UIFontDescriptor`; `CTFontDescriptor` is used (decision 2).
- `LedgerFont.font(_:)` is not Dynamic Type–scaled; `.ledgerFont(_:)` is (decision 3).
- Role list and colour list extended (decisions 4, 6); `LedgerMotion.buzz` replaced (decision 8).
- Criterion 3 uses `.xLarge` as the brief says; testing-strategy §2.5 said
  `.xxxLarge` and now follows the brief.
- Lint rules renamed and re-scoped rather than only allowlisted (decision 9).
- `Resources/Fonts/` removed (decision 1): **the pbxproj still has the `Fonts`
  synchronized group pointing at it.** Builds report 0 warnings with the folder
  gone (checked in the build result bundle), but the dangling group should be
  deleted in Xcode by Pete (ADR-003: no hand-edits of `project.pbxproj`).
- No `#Preview`s: slice 1 adds no views (only modifiers); the token pages
  arrive with `DesignGallery` in slice 3. Test-only specimen views
  (`Support/TokenSpecimens.swift`) render the snapshots meanwhile.

## Open points for the orchestrator / Pete

- Delete the dangling `Fonts` group in Xcode (see above).
- HIG's watchOS minimum is 12 pt; the prototype's smallest watch labels are
  17 px ÷ 1.5 = 11.3 pt and criterion 4 asks for ≥ 11 pt. Kept as designed.
- Contrast choices in decision 7.
- F00's open question (feature targets linking `LedgerTestSupport` for preview
  fixtures) is not touched here; it matters once slice 2 adds previews.

## Verification (2026-09-27)

- `scripts/check.sh --record-snapshots` (through the simulator lock): both
  plans ran; the only failures were the 6 "reference recorded" snapshot tests
  (3 per platform); it listed the new PNGs and exited 1 as designed.
- `scripts/check.sh` (full gate, through the lock): **green**, 195 s.
  - PR-iOS: 457 tests, 457 passed; 17/17 test targets ran and passed.
  - PR-watchOS: 448 tests, 448 passed; 8/8 test targets ran and passed.
  - LedgerDesignTests: 27 test functions on each platform (71 argument cases
    on iOS, 65 on watchOS), references matching on both.
- LedgerDesign line coverage (xccov, `Sources/LedgerDesign/` only): **95.5 %**
  iOS (190/199), **95.3 %** watchOS (183/192); target 60 %. Uncovered: the
  registration failure branches and the modifier's keyframe-animator closure.
- Build result bundle for `Ledger` with `Resources/Fonts/` deleted: 0 warnings,
  0 errors; the font sits in `LedgerKit_LedgerDesign.bundle` in both apps.
- Lint fixture: 12/12 checks pass; each of two mutated configs (LedgerDesign
  not allowlisted; F00's feature-only scope) fails 4 of them.
- Snapshot references: 12 PNGs, 612 KB (budget 6 MB).

Changed lines, excluding snapshots (untracked files counted in full):

| Category | + | − |
|---|---|---|
| Product: `LedgerKit/Sources/LedgerDesign/**/*.swift` | 484 | 4 |
| Build / config: `Package.swift`, two `Info.plist`, `.swiftlint.yml`, `check.sh` | 68 | 37 |
| Test infrastructure: `LedgerSnapshotTesting`, `scripts/tests` | 330 | 4 |
| Tests: `LedgerDesignTests` | 593 | 10 |
| Docs: `docs/`, `tasks/` | 225 | 22 |

Product Swift is 488 changed lines; with build configuration, 593. The font
and licence moves are renames with no line changes.

## How to verify by hand

- Open `LedgerKit/Tests/LedgerDesignTests/__Snapshots__/ArchivoFontTests/*.png`:
  the iOS and watchOS sheets show the same five widths.
- `scripts/tests/lint-rules.test.sh` prints the 12 checks.
- `.derivedData/` in this worktree (2.8 GB) holds the gate's build and results
  (`Results/PR-iOS.xcresult`, `Results/PR-watchOS.xcresult`); delete it when the
  PR is merged.
