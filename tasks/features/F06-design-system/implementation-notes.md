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
3. **Text styling is a modifier, `.ledgerFont(_:)`; every `Font` is scaled (fix round).**
   A `Font` cannot carry tracking, case or line height, so views use the
   modifier: it reads `dynamicTypeSize` and `legibilityWeight` from the
   environment, sizes the role with `LedgerFont.scaledSize`, and applies
   `tracking` (em × scaled size), `textCase(.uppercase)` and iOS 26's
   `lineHeight(.multiple(factor:))`. The `Font` entry points are
   `font(_:dynamicTypeSize:legibilityWeight:)` and
   `font(_:size:legibilityWeight:)` (explicit, already scaled size, floored);
   the brief's environment-free `font(_:)` is gone, so no caller can get an
   unscaled font. See "Dynamic Type" below for why the size must be passed.
   Since fix round 2 the modifier also places each line in its line box where
   CSS does (see "Fix round 2", finding 11).
4. **21 type roles**, values copied from the v2 and watch prototypes'
   `font:` declarations (table in `TypeScaleTests`). Added to the brief's 13:
   `subheading` (sheet title 21 pt), `caption` (400 12 pt metadata), `button`
   (16 pt CTA; 700 since the fix round, see "Contrast"), and watch `Countdown` / `Stat` / `Title` / `Button` /
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
   (`LedgerTypeSpec.minimumSize`), applied on every path including an explicit
   `font(_:size:)` (fix round, finding 2) and tested at `.xSmall`.
6. **Colours.** Adaptive tokens are a dynamic `UIColor` on iOS (resolves from
   SwiftUI's colour scheme, verified by criterion 2's tests); watchOS has one
   appearance and no dynamic `UIColor`, so it takes the dark value; macOS
   exists only for the host build. Added to the brief's list, each from the
   spec: `accentText` (spec §8.1 "orange text on paper uses #C63F0F for
   contrast", now `#B2390E`, see decision 7 and fix round 2), `accentLine` (accent 40 %, the active-set rule),
   `inkDim` (28 %, the v2 `DIM` done rows), and the watch ink family
   (`watchInk`, `…Secondary` 55 %, `…Muted` 46 % (was 40 %, decision 7), `watchOutline` 22 %,
   `watchHairline` 14 %, `watchTrack` 13 %). `accentSoft` is 12 % on paper
   (`accentTint`, §8.1) and 16 % on dark (§8.3).
7. **Contrast — Pete's decision (2026-09-27): meet WCAG AA, keep the look.**
   Ratios are WCAG 2.x against the grounds the spec pairs each token with
   (dark: ground `#0B0B0D` / sheet `#131316`; light: paper `#EFEDE6` / card `#FFFFFF`).

   | Token | Old | Old ratio | New | New ratio |
   |---|---|---|---|---|
   | `inkMuted`, dark | text .45 | 4.15 / 4.17 | text **.48** | 4.58 / 4.58 |
   | `inkMuted`, light | ink .45 | 2.88 / 2.97 | ink **.60** | 4.53 / 4.78 |
   | `watchInkMuted` | white .40 | 3.66 | white **.46** | 4.58 |
   | `accentText`, light | `#C63F0F` | 4.35 / 5.10 | **`#B2390E`** (× 0.90; fix round 1 had `#C03D0F`, × 0.97) | 5.14 / 6.03 |
   | `onAccent` on `accent` | white | 3.10 | white (unchanged) | 3.10 |

   White stays on the accent. Its only text is the button label, and the HIG
   contrast table (from WCAG AA) allows 3:1 for bold text at any size. So
   `button` goes 600 → **700** (v1's CTA weight, spec §8.5) and `watchButton`
   600 → **700** (inside the watch spec's 600–700). Unchanged and already AA:
   `ink`, `inkSecondary` (9.2 dark / 6.7 light), dark `accentText` 6.3,
   `watchInkSecondary` 6.3. `inkFaint` (.32) and `inkDim` (.28) stay decorative.

   **Increase Contrast (iOS, `accessibilityContrast == .high`):** the ink ladder
   steps up so that text reaches AAA and `inkFaint` reaches AA. Grounds, `ink`
   and the accent family do not change. watchOS has no dynamic colours.

   | Token | Normal | Increased | Increased ratio dark (ground / sheet) | light (paper / card) |
   |---|---|---|---|---|
   | `inkSecondary` | .72 | .86 | 12.97 / 12.37 | 10.77 / 12.16 |
   | `inkMuted` | .48 / .60 | .74 | 9.70 / 9.36 | 7.22 / 7.85 |
   | `inkFaint` | .32 | .60 | 6.62 / 6.50 | 4.53 / 4.78 |
   | `inkDim` | .28 | .50 | 4.88 / 4.87 | 3.33 / 3.46 |
   | `hairline` | .08 | .20 | 1.71 / 1.78 | 1.53 / 1.54 |
   | `hairlineStrong` | .14 | .30 | 2.45 / 2.53 | 1.94 / 1.97 |

   Tests that asserted the prototype's old values and were updated (the fix
   round's only edits to the adversarial tester's files, each marked
   `F06 fix round` in the source):
   - `TokenValueTests`: inkMuted dark .45 → .48, light .45 → .60; light
     accentText `#C63F0F` → `#C03D0F`; watchInkMuted .4 → .46.
   - `TypeScaleTests`: button and watchButton weight 600 → 700.
   - `Adversarial/LedgerColorAdversarialTests`: `orangeDeep`, the inkMuted
     alphas (now per scheme), watchInkMuted, and the browser-composite test's
     alpha .45 → .48.
   - `Adversarial/ContrastAdversarialTests`: onAccent pairs (phone and watch)
     held to 3:1, with a new test that the label roles are ≥ 700.
   - `Adversarial/LedgerFontSpecAdversarialTests`: `.button` weight 600 → 700.
8. **Motion.** `LedgerMotion.buzzKeyframes(reduceMotion:)` is spec §8.8's
   `@keyframes buzz` (offsets −3, 3, −2, 2, 0 at 20 % steps, CSS `ease` as a
   cubic Bézier, 3 × 0.38 s); `View.ledgerBuzz(trigger:)` plays it with
   `keyframeAnimator`. Under Reduce Motion the offset track is 0 throughout
   and opacity dips to 0.4 once per cycle. Tests sample the same keyframes
   through `KeyframeTimeline` every millisecond. The brief's
   `static let buzz: Animation` cannot express a transform or a Reduce Motion
   alternative, so it is replaced by these two (`buzzCycle`, `buzzRepeats`
   remain as values).
9. **Bold Text — Pete's decision (2026-09-27).** With `legibilityWeight ==
   .bold` every role moves one weight step up (+100 `wght`: 500 → 600,
   700 → 800), through `.ledgerFont` and through the `Font` entry points'
   `legibilityWeight` argument (`BoldTextTests`; snapshots
   `phoneTypeRamp_boldText`, `watchTypeRamp_boldText46mm`).
10. **Design lint.** F00's `feature_raw_*` rules are renamed to the brief's
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
   **Fix round (finding 10):** the regexes were rewritten against the tester's
   55 fixtures (`scripts/tests/lint-rules-adversarial.test.sh`, now also run in
   `check.sh` step 2), which went from 25 failing to 0. Changes: any `Color(…)` /
   `Color.init(…)` construction (multi-line, `Color(.system…)`, asset names), a
   named colour as a leading-dot argument (`.foregroundStyle(.purple)`,
   `.tint(.pink)`, `.shadow(color: .black…)`, `.stroke(.orange)`),
   `UIColor`/`NSColor`/`UIFont`/`NSFont`, `Font(…)`, `.font(.custom(…))`, `.bold()`,
   `.italic()`, `.fontWidth(`/`.fontDesign(`; padding with an edge set or
   `EdgeInsets`, `.safeAreaPadding`, `CGFloat(13)`, every `spacing:` /
   `horizontalSpacing:` / `verticalSpacing:` argument (grids included); every
   corner-radius label (`topLeadingRadius:` …) and `cornerSize:`. A literal `0`
   is allowed for spacing and radii (`VStack(spacing: 0)`), `\bColor(` no longer
   matches `highlightColor(red:)`, and `excluded_match_kinds` ignores comments and
   string literals. **Fix round 2 (findings 12, 13, 17):** see "Fix round 2";
   `lint-rules-adversarial-round2.test.sh` (39/39) now also runs in step 2.
11. **Snapshot infrastructure (`LedgerSnapshotTesting`, test-only).**
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
    **Fix round (findings 3, 4):** the match fraction is compared in `Float`,
    like `precision` itself, so exactly 995 of 1000 pixels passes; the ΔE
    threshold prints as 2.0. A failing `.png` comparison now attaches
    `difference.png` (the reference at a third of its brightness, mismatches in
    magenta) next to `actual.png` and `reference.png`. **Fix round 2 (findings
    15, 16):** mismatches are counted in whole pixels against the precision in
    parts per million, and a size change attaches a difference image too.
12. **`check.sh --record-snapshots` now works.** It exported
    `SNAPSHOT_TESTING_RECORD`, which `xcodebuild` does not forward to the
    simulator's test runner, and `set -e` stopped at the iOS step, so watch
    references could never be recorded. It now exports
    `TEST_RUNNER_SNAPSHOT_TESTING_RECORD=all`, runs both plans, lists
    `__Snapshots__` changes and exits 1 (F00 note 8 left this to F06).
13. **`Package.swift`:** the `LedgerDesign` resources, and `exclude:
    ["__Snapshots__"]` for test targets listed in `snapshotTestTargets`
    (otherwise SwiftPM warns about unhandled PNGs; an exclude of a missing
    folder also warns, hence the explicit list). The package graph is unchanged.

## Dynamic Type for a bare `Font` (fix round, finding 1)

The adversarial finding asked for `LedgerFont.font(role)` to follow the
environment's text size. A `Font` value can only do that if SwiftUI builds it
itself, by name, with `Font.custom(_:size:relativeTo:)`, and that path cannot
set Archivo's `wdth`. A probe on both simulators (2026-09-27, "0123456789" at
24 pt, 2×; reference widths wdth 88 → 252 px, 90 → 258, 100 → 282):

- `Font.custom("Archivo", …).weight(.bold).width(Font.Width(x))` for x from −1
  to 0.5: always 282 px on iOS (270 on watch at `.large`). `.width()` is
  ignored because the variable font has no named width instances.
- Registering a variation instance as a graphics font
  (`CTFontCopyGraphicsFont` + `CTFontManagerRegisterGraphicsFont`) resolves by its
  synthesized name (`Archivo-SemiBold_wght2BC0000_wdth5A0000`), but it renders
  519 px with every glyph the same width, which means missing outlines.
- `Font(ctFont)` is exact but fixed-size (258 px at both `.large` and AX3).

So a static `font(role)` can be exact or scaled, not both. The fix makes the
text size an argument: `font(_:dynamicTypeSize:legibilityWeight:)` sizes the
role on SwiftUI's own custom-font curve. `scaledSize` resolves
`Font.custom(…, relativeTo: role.textStyle)` in an `EnvironmentValues` with that
size and reads the factor at 1000 pt, because resolved sizes are whole points.
`.ledgerFont` uses the same function, so the two paths cannot disagree.
The brief's environment-free `font(_:)` was removed rather than kept as a
design-size font, because it would have been the unscaled trap the finding
describes. "The brief's caps": the brief sets no maximum size, so the only
bound is the 11 pt watch floor, applied on every path. The adversarial tests
that called `font(role)` now pass the text size (`LedgerFontRenderingAdversarialTests`
×3, `LedgerFontMetricsAdversarialTests.trackingGain`).

## Fix round 2 (adversarial round 2, findings 11–17)

**11. Where a lone line sits in its line box (bug, fixed).** The tester's CSS
model is the right one: the prototypes are CSS, and spec §8.5's line heights
are CSS `line-height`, which centres the font's ascent + descent in an `L` em
box. Probe on the host (confirmed by the tests on both simulators): with
`.lineHeight(.multiple(factor:))` or `.exact(points:)`, SwiftUI puts a single
line's baseline exactly **1 em** below the frame top whatever `L` is (0.5, 0.86,
1, 1.2, 1.6, 2 at 20 and 40 pt), and the frame is `L` em. CSS puts it at
`L/2 + (ascent − descent)/2` em; Archivo's ascent is .878 em and descent .210 em
at every axis position (`CTFontGetAscent`/`Descent` on the file). So
`.ledgerFont` lifts the text by `(1 − L/2 − 0.334) × size` with
`.padding(.top, −lift).padding(.bottom, lift)`. `ArchivoFont.baselineBelowMiddle`
reads the 0.334 from the font rather than hard-coding it.
- Padding, not `offset`: the frame keeps its exact height (measured identical to
  the unlifted text at 1×, 2× and 3× for 11–42.67 pt × `L` 0.86–1.6), and the
  text-baseline alignment guides move with the glyphs, so
  `HStack(alignment: .firstTextBaseline)` / `.lastTextBaseline` still line up
  mixed roles (probe: numeralXL/bodyLight, watchNumeral/caption,
  display/eyebrow align to the pixel). An `offset` would leave the guides behind.
- Multi-line pitch is unchanged (the whole block moves), so round 1's
  baseline-to-baseline tests still hold; each line lands where CSS stacks it.
- `watchNumeral` (0.86) now has its baseline at 0.764 em inside its 0.86 em
  frame instead of 0.996 em (0.14 em below it).
- Limitation: the lift is applied to whatever view `.ledgerFont` modifies. On
  a container of text in one role that is still right (every line moves
  together); a non-text child in that container moves with it.
- Line budget: the lift cost 12 lines (the metric in `ArchivoFont`, the
  modifier's comment, `lift` and two paddings, one doc line); folding the
  `numeral` spec builder into `text(…, tabular: true)` saved 12, so
  LedgerDesign stays at 497.

**12. `ledger_raw_font` flagged `LedgerFont.font(.title/.body/.caption, …)` (bug, fixed).**
The `.font(` branch now has a negative lookbehind, `(?<!LedgerFont)\.font\(`.

**13. Eleven raw spellings passed (bug, fixed).** B01–B04: the colour
leading-dot branch also fires after an assignment `=` (not `==`, `!=`, `<=`,
`>=`), a ternary `? ` and `??`, and `.init(red:|white:|hue:|uiColor:|…)` is a
colour construction. B05: any system style anywhere inside a `.font(…)`
argument (so ternaries), not only right after the paren. B06/B07: `.init(top:…)`
is `EdgeInsets`. B08: `.contentMargins(` (with `.listRowSpacing(` /
`.listSectionSpacing(`) joins the padding branch. B09: `minLength:` joins the
spacing labels. B10/B11: RectangleCornerRadii's `topLeading:` … labels join the
radius labels.

**14. `accentText` on `accentSoft` over paper was 4.04:1 (design question) — an
application of Pete's decision of 2026-09-27, "meet WCAG AA, keep the look".**
The tint cannot fix it alone: even at 3 % alpha (a near-invisible chip) the
text is 4.44:1. So the text moves, along the same line as fix round 1 (the
spec's `accentDeep` scaled down): round 1 used × 0.97 (`#C03D0F`); × 0.905
(`#B3390E`) is 4.51 exact but 4.49 once the tint is quantised to 8 bits, so
× 0.90, **`#B2390E`**, is the smallest step on that line that holds. It is one
token value, light only; the tint, the dark value and Increase Contrast are
unchanged. Colour distance: ΔE2000 3.1 from `#C03D0F`, 4.5 from the spec's
`#C63F0F` (the smallest possible change for this pair, any hue, is ΔE2000 2.8
and lands exactly on 4.50).

| `accentText` light over… | `#C63F0F` (spec) | `#C03D0F` (before) | **`#B2390E` (after)** |
|---|---|---|---|
| `accentSoft` on paper (`ground`) | 3.83 | **4.04** | **4.54** (4.52 with an 8-bit tint) |
| `accentSoft` on card (`surface`) | 4.43 | 4.67 | 5.25 |
| paper (`ground`) | 4.35 | 4.58 | 5.14 |
| card (`surface`) | 5.10 | 5.36 | 6.03 |

Increase Contrast leaves the accent family alone, so the ratios are the same
with it on. Dark mode already passed and is unchanged: `#FF5B22` on the 16 %
tint is 5.32 over ground, 4.92 over sheet. Tests updated to the decided value
(each commented `F06 fix round 2`): `TokenValueTests` (accentText light) and
`Adversarial/LedgerColorAdversarialTests.orangeDeep`.

**15. One pixel too many passed at some sizes (bug, fixed).** The comparator
no longer divides: it passes when `mismatched × 1 000 000 ≤ pixels ×
allowedPerMillion`, where `allowedPerMillion` is `(1 − precision) × 10⁶`
rounded (5 000), so exactly floor(0.5 %) of the pixels may differ at every size.

**16. A size change attached no difference image (bug, fixed).** The
comparison now lays both images on a canvas the size of the larger: the
overlap is compared pixel by pixel, every pixel only one image has is a
mismatch, and `difference.png` is that canvas (reference dimmed, mismatches
magenta). A size change still always fails and its message still names both
sizes.

**17. Lint escape hatches (design questions).** Decided one by one; the rule is
"close what a feature author would write without meaning to bypass tokens".

| Case | Decision | Why |
|---|---|---|
| D01 `LedgerFont.font(.numeralL, dynamicTypeSize: .large)` | Closed: a constant `dynamicTypeSize:` is flagged | It looks like the sanctioned call but drops Dynamic Type; the real call passes `@Environment(\.dynamicTypeSize)` |
| D02 `LedgerFont.font(.label, size: 13)` | Closed: a literal `size:` is flagged | The parameter's contract is an already scaled size; a literal never is |
| D04 `.dynamicTypeSize(.large)` | Closed, with `.environment(\.dynamicTypeSize, .large)`: a single pinned size is flagged | It turns Dynamic Type off for a subtree (standards §7). Cost: a preview can't pin a size in code; previews use the canvas's Dynamic Type variants and the snapshot matrix covers the sizes |
| — `.dynamicTypeSize(...DynamicTypeSize.accessibility2)` | Left open | Apple's documented way to bound growth where a layout truly can't grow; deliberate, rare and visible in review, and it still supports accessibility sizes |
| D05 `LedgerColor.ink.opacity(0.6)` | Closed: `.opacity(` on a `LedgerColor` token is flagged | A hand-made alpha leaves the AA ladder and Increase Contrast; view `.opacity` (fades) is unaffected |
| D06 `LedgerSpacing.m + 1` | Closed, for spacing and radius tokens | "Nudge by one" is the classic accident; token-to-token arithmetic (concentric radii) stays legal |
| D07, D08 `.tracking(2)`, `.lineSpacing(4)` | Closed, with `.kerning(` and `.lineHeight(` | Letter-spacing and leading belong to the roles |
| D09 `.font(.init(CTFont…))` | Closed: `.init` inside `.font(…)` | Costs one alternative |
| P04 `cornerSize: CGSize(width: LedgerRadius.row, …)` | Fixed: flagged only with a literal | False positive on tokens |
| N12 `LedgerFont.archivo(size: 30, …)` | Left open | The brief makes it public and round 1's N12 requires it to lint; see "Open points" |

Residual breadth, accepted: the colour leading-dot branch now also fires after
`=`, `?` and `??`, so a feature enum case named like a colour (`primary`,
`secondary`, …) written with a leading dot there is flagged; the workaround is
to qualify it (`Rank.primary`). `LedgerDomain` has no such case and the whole
repo lints clean. A probe of 14 legitimate spellings (token arithmetic
between tokens, `Spacer(minLength: 0)`, range caps, `LedgerFont.font` with a
role ternary or a scaled size, view `.opacity`, `.task(priority: .background)`,
`dynamicTypeSize >= .accessibility1`, …) raised nothing, with a raw control in
the same tree flagged.

No test is disputed. Test edits this round: the two `accentText` values above,
nothing else. The round-2 lint script's header still says it is not wired into
`check.sh`; it is the tester's file, so the comment was left as is.

## Deviations from the brief

- Criterion 1 names `UIFontDescriptor`; `CTFontDescriptor` is used (decision 2).
- **`LedgerFont`'s `Font` entry points.** The brief's public surface still reads
  `public static func font(_ role: Role) -> Font // Dynamic Type–scaled`. That
  function does not exist: the entry points are
  `font(_:dynamicTypeSize:legibilityWeight:)` and
  `font(_:size:legibilityWeight:)`, plus `scaledSize(_:dynamicTypeSize:)` and
  `boldTextWeightStep`, because a `Font` built from a Core Text instance cannot
  follow the environment by itself (decision 3, "Dynamic Type"). Architecture
  §11 already says so; the brief's code block is the orchestrator's to update.
- `.ledgerFont` lifts each line inside its line box to match CSS half-leading
  (fix round 2, finding 11); the brief says nothing about vertical placement.
- `accentText` light is `#B2390E`, not spec §8.1's `#C63F0F` (decision 7, fix
  round 2, finding 14).
- Role list and colour list extended (decisions 4, 6); `LedgerMotion.buzz` replaced (decision 8).
- Criterion 3 uses `.xLarge` as the brief says; testing-strategy §2.5 said
  `.xxxLarge` and now follows the brief.
- Lint rules renamed and re-scoped rather than only allowlisted (decision 10);
  since fix round 2 they also cover tracking/leading modifiers, a constant text
  size and raw alphas on tokens, which the brief's three examples don't name.
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
- Contrast and Bold Text: decided by Pete 2026-09-27 and implemented (decisions 7, 9).
- F00's open question (feature targets linking `LedgerTestSupport` for preview
  fixtures) is not touched here; it matters once slice 2 adds previews.
- **For Pete (finding 14):** `accentText` light moved again under his AA
  decision, `#C03D0F` → `#B2390E`, so orange chip text on its tint reaches
  4.5:1 (table in "Fix round 2").
- **Brief question (finding 17):** `LedgerFont.archivo(size:weight:width:)` is
  public per the brief and still lints with literals in a feature (round 1's
  N12 requires it). Its only intended callers are `LedgerDesign` components
  and `DesignGallery`, both inside the module, so the brief could make it
  internal in slice 3; that would close the last font escape hatch.

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

## Verification — fix round (2026-09-27)

Adversarial findings addressed: 1 (Dynamic Type for the bare `Font`), 2 (the
floor on the explicit-size path), 3 (precision boundary), 4 (difference image),
5–8 (contrast, Pete's decision), 9 (Bold Text, Pete's decision), 10 (lint).

- `scripts/check.sh --record-snapshots` (through the lock): every failure was a
  recording: 5 on iOS, 4 on watchOS. All 13 adversarial tests that had failed now
  pass. Re-recorded: 12 existing PNGs changed (both spike sheets, both palettes,
  the six phone ramps, the watch ramp and the watch palette, because of the
  inkMuted / accentText / watchInkMuted / button weight changes). New: 4 (phone
  and watch Bold Text ramps, phone Increase Contrast palette light and dark).
  `__Snapshots__` is 796 KB.
- `scripts/check.sh` (full gate, through the lock): **green**. Step 2 runs
  `lint-rules.test.sh` (12/12) and `lint-rules-adversarial.test.sh` (55/55).
  - PR-iOS: **528 tests, 528 passed**; 17/17 test targets.
  - PR-watchOS: **513 tests, 513 passed**; 8/8 test targets.
- LedgerDesign line coverage: **95.7 %** iOS (198/207), **95.4 %** watchOS (186/195).
- LedgerDesign product Swift against `main`: **+493 −4 = 497 changed lines**
  (≤ 500; this round +82 −73). The motion helpers were folded into their enum
  and the `clamped` extension inlined to stay under the limit, so nothing had
  to move to slice 2.
- `check.sh --record-snapshots` now lists changed references with a working
  pathspec (`':(glob)**/__Snapshots__/**'`; the old `'**/__Snapshots__'` matched
  nothing).
- On the macOS host only, `render_sameViewRepeatedly_isPixelIdentical` differs
  from the third render on (181 pixels, glyph rasterisation), with or without
  this round's changes. It passes on both simulators, which is where the suite runs.

## Verification — fix round 2 (2026-09-28)

Adversarial round-2 findings addressed: 11–17 (see "Fix round 2"). Commit
`7689a74`.

- Host (`swift test --filter LedgerDesignTests`): all round-2 targets pass
  (line box ×21 roles both tests, bare font = `.ledgerFont` ×21, precision
  boundary ×6, size-change and marked difference images). The remaining host
  failures are the known macOS gaps (no Dynamic Type; the spike records a
  macOS reference, which was deleted, not committed).
- Lint: `lint-rules.test.sh` 12/12, `lint-rules-adversarial.test.sh` 55/55,
  `lint-rules-adversarial-round2.test.sh` 39/39 (was 16/39), all in `check.sh`
  step 2; the whole repo lints clean.
- `scripts/check.sh --record-snapshots` (through the lock): 14 references
  re-recorded, every one because of this round:
  - line placement (text lifted inside unchanged frames): the six
    `phoneTypeRamp_appearance` images, `phoneTypeRamp_boldText.bold-dark-large`,
    `watchTypeRamp_46mm.mm46`, `watchTypeRamp_boldText46mm.bold-mm46`, and
    `watchPalette_46mm.mm46`, `phonePalette_scheme` dark, `phonePalette_increasedContrast`
    dark (their name labels use `.ledgerFont`);
  - line placement and the `accentText` swatch: `phonePalette_scheme` light and
    `phonePalette_increasedContrast` light.
  Image sizes are unchanged; the spike sheets re-recorded byte-identical.
  `__Snapshots__` is 16 PNGs, 764 KB.
- Full `scripts/check.sh` through the lock, three runs. The machine was
  saturated while the gate cold-booted its simulator clones (load average
  100–258; first-boot daemons in every clone). Run 1 failed on a 60 s time
  allowance (`registration_resolvedFont_isTheBundledFile`, round 1, unchanged
  here); run 2 failed only because the UI test runner "Timed out while loading
  Accessibility", with every unit test passing. **Run 3 green**
  (`check-full-3.log`, 2377 s):
  - PR-iOS: **551 tests, 551 passed**; 17/17 test targets.
  - PR-watchOS: **530 tests, 530 passed**; 8/8 test targets.
- LedgerDesign line coverage: **95.7 %** iOS (201/210), **95.5 %** watchOS (189/198).
- LedgerDesign product Swift against `main`: **+493 −4 = 497 changed lines**.

## How to verify by hand

- Open `LedgerKit/Tests/LedgerDesignTests/__Snapshots__/ArchivoFontTests/*.png`:
  the iOS and watchOS sheets show the same five widths.
- `scripts/tests/lint-rules.test.sh` prints the 12 checks.
- `.derivedData/` in this worktree (2.8 GB) holds the gate's build and results
  (`Results/PR-iOS.xcresult`, `Results/PR-watchOS.xcresult`); delete it when the
  PR is merged.
