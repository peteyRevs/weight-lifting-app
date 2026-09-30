# F06 — implementation notes

Branch `feat/F06-design-system` (from `main` 8404d02). F06 ships as three PRs,
each through the full gate (engineering-standards §10: ≤ 500 changed product
lines; the F02 waiver does not carry over). **This file covers slice 1:
tokens, Archivo loading and the width-axis spike, the lint allowlist, and
their tests and snapshots.** Slice 2 (the phone components) is in
"Slice 2" near the end, and slice 3 (the rest, the watch set and the gallery) in "Slice 3" at the end.

## Slice plan

| Slice | Contents | Criteria |
|---|---|---|
| **1** (#6, merged) | `Tokens/*` (colour light/dark/watch, type, spacing, radius, hairline, motion), `Fonts/*` (Archivo registration and axis instances), the `wdth` spike on both simulators, the design-lint allowlist and its fixture test, snapshot infrastructure in `LedgerSnapshotTesting` | 1, 2, 7, 8; the criterion 3 matrix is exercised by the token specimens |
| **2** (`feat/F06-slice2-components`) | The most-used phone primitives: `PrimaryButton`, `PillButton`, `IconPillButton`, `Eyebrow`, `HairlineList` / `HairlineRow`, `SetRow` + `SetRowSteppers` (the brief's `Stepper`), `RestRing`, with previews and the 6-image matrix each; `RestRingGeometryTests`, `ComponentAccessibilityTests` | 3 (these components), 5, 6 |
| **3** (`feat/F06-slice3`) | `WeekStrip`, `StatTile`, `ProgressSegments`, `SheetChrome`, `EmptyState`, `WatchPrimaryButton`, `WatchRestRing` (reuses slice 2's ring geometry), `WatchStatBlock` at 42 / 46 / 49 mm, and `DesignGallery` (token pages plus every component, named); side-by-side gallery vs prototype screenshots for the PR | 3 (the rest), 4, 9 |

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
   Fix round 2 made the modifier place each line where CSS does (finding 11);
   fix round 3 removed that again under Pete's decision 1 (2026-09-29): the
   line height is SwiftUI's own and the modifier moves nothing in the view.
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
   | `inkMuted`, dark | text .45 | 4.15 / 4.17 | text **.48** (fix round 3: **.51**) | 4.58 / 4.58 (5.05 / 5.04) |
   | `inkMuted`, light | ink .45 | 2.88 / 2.97 | ink **.60** (fix round 3: **.62**) | 4.53 / 4.78 (4.84 / 5.10) |
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
   | `inkMuted` | .51 / .62 (was .48 / .60) | .74 | 9.70 / 9.36 | 7.22 / 7.85 |
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
   **Fix round 3 (findings 21–23, Pete's decision 2):** see "Fix round 3"; the
   rule set is frozen and documented, limits included, in engineering-standards §7.
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

**11. Where a lone line sits in its line box (bug, fixed).** *Superseded in fix
round 3 by Pete's decision 1: the lift described here is removed.* The tester's CSS
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
- `.ledgerFont` uses SwiftUI's native line height, so a single line can sit up
  to ~10 pt from where the CSS prototype puts it (Pete's decision 1, fix round 3;
  fix round 2's CSS placement was removed).
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
- **For slices 2 and 3 (fix round 3):** with native line height (Pete's decision 1) a single line can sit up to
  ~10 pt from the prototype, and `watchNumeral` (line height 0.86) draws its figures 0.14 em (~6 pt at 46 mm) below
  its own frame; components leave room with spacing tokens. Phone matrix snapshots should apply
  `.snapshotAppearance(appearance)`, or `.sizeThatFits` measures them at `.large` and clips larger text sizes.
- **For Pete (finding 20):** `inkMuted` moved again under his AA decision, .48 → .51 dark and .60 → .62 light, so
  muted text keeps 4.5:1 on the selected-item tint (table in "Fix round 3").
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

## Fix round 3 (re-plan, 2026-09-29)

Slice 1 failed the adversarial gate three times, so the orchestrator stopped and
asked Pete. His decisions change the contract; this round implements them
against round 3's findings 18–23 (`3e9c106`).

### Pete's decisions (2026-09-29), verbatim

1. **Text uses native SwiftUI line height only.** Keep `.lineHeight(.multiple(factor:))`. Remove the CSS half-leading emulation (the `lift` computed from `ArchivoFont.baselineBelowMiddle` and the `.padding(.top, -lift).padding(.bottom, lift)`) and any code that exists only for it. Single lines may sit 1–10 pt off the HTML prototype; slice-2 components absorb that with spacing tokens.
2. **The design lint is a tripwire, not a proof.**
   - Close finding 21's 16 raw spellings where a rule can do it simply.
   - Fix finding 23's false positives on sanctioned token use.
   - Then freeze the rule set. Document it as a list, and document its known limits, finding 22's escape hatches included, in docs/engineering-standards.md next to the design-lint rule, or wherever the lint is documented today.
   - State that "tokens only" is enforced by review (docs/subagent-workflow.md review point 4), and that the lint is not meant to catch every spelling.

Also recorded verbatim in the brief ("Decisions during delivery").

### Findings 18–23 → what changed

| # | Change | Tests |
|---|---|---|
| 18 (and 11) | Decision 1. `.ledgerFont` sets the font, tracking, case and `lineHeight(.multiple(factor:))` and nothing else: the `lift`, both paddings and `ArchivoFont.baselineBelowMiddle` (which existed only for the lift) are gone, and the doc comment says a single line sits where SwiftUI puts it. SwiftUI puts a lone baseline 1 em below the frame top at any line height, so against CSS a line sits (0.666 − L/2) em lower: display +5.2 pt, body +1.0, bodyLight −1.8, watchNumeral +10.1 (0.236 em at 42.7 pt). watchNumeral (L 0.86) draws its figures 0.14 em (6 pt at 46 mm) below its own 0.86 em frame; slice-3 watch components leave room for that with a spacing token. | `LedgerFontLinePlacementAdversarialTests.nestedRoles_innerRole_placesItsOwnLine` (4) and `background_underText_staysOnFrame` (21) pass with their assertions unchanged; the CSS-placement tests are retargeted (below) |
| 19 | The tests' fault, fixed in the tests. (1) The four suites that only compare values are `nonisolated` (`TokenValueTests`, `ContrastAdversarialTests`, `LayoutTokenAdversarialTests`, `LedgerFontSpecAdversarialTests`, plus the `Resolve` helper) and run in parallel, off the main actor. (2) The 21 suites that need the main actor (they render, use `LedgerSnapshotTesting`'s main-actor pixel helpers, or build UIKit trait collections) are nested in `@Suite("Rendering (serialized)", .serialized) enum RenderingSuites` (`Support/RenderingSuites.swift`), so each test's allowance starts when it runs, not when the target starts. `IncreaseContrastTests` is in that group rather than `nonisolated`: `UITraitCollection { $0.… = … }` mutates main-actor state (two isolation warnings), and the non-mutating `init(traitsFrom:)` is deprecated. (3) `bareFont_everySizeAndWeight_matchesLedgerFont` (21 roles × 12 sizes × 2 weights × 2 = 1,008 renders) is tagged `.slow` and runs only when `LEDGER_TEST_LANE == nightly` (`TestLane.runsSlowTests`, `Support/Tags.swift`; testing-strategy §6 now says how a single slow test is gated); the PR lane runs `bareFont_representativeSizesAndWeights_matchesLedgerFont` at xSmall, large and AX5 × regular/bold (252 renders) with the same assertions. The plans' 60 s allowance is unchanged and no test leans on it. "Timed out while loading Accessibility" was the environment and is left alone. | Host: the value suites finish at the start of the run (1 ms); the PR subset is 6.4 s for 21 cases (≈0.3 s each). Gate: see Verification |
| 20 | Pete's standing decision (2026-09-27, "meet WCAG AA, keep the look"), as for 5–8 and 14. The smallest change is `inkMuted`'s alpha, one 0.01 step past the threshold on each scheme: **dark .48 → .51, light .60 → .62** (.50 gives 4.44 on the sheet tint, .61 gives 4.48 on the paper tint). The tint would have to fall from 12 % to 3.5 % (light) and 16 % to 7 % (dark), ΔE2000 6–9 on every chip, against ΔE2000 1.7–2.7 for the muted text. Increase Contrast (.74) and the watch tokens are unchanged; phone tokens resolve dark on the watch, so it gets .51. | `AccentChipContrastAdversarialTests.inkText_onSelectedItemTint_meetsAA` passes; `TokenValueTests` and `LedgerColorAdversarialTests` updated to .51 / .62 (commented `F06 fix round 3`) |
| 21 | Decision 2. 14 of the 16 spellings closed (B01–B09, B11–B15, table below). B16 and B17 (a comment inside the call) can't be closed simply: SwiftLint drops any match that spans a comment token, so they are documented limits. | round-3 script B01–B15 pass, each flagged by the rule it names; B16, B17 are `limit` cases |
| 22 | Decision 2: not closed. D01–D09 are the documented known limits in engineering-standards §7. | round-3 script D01–D09 are `limit` cases |
| 23 | Q01: a text-size pin is flagged in the modifier only at or below the default (`.dynamicTypeSize(.xSmall…large)`), so a `#Preview` can pin `.xLarge` / `.accessibility3`; constants passed on (`dynamicTypeSize: .large`, `\.dynamicTypeSize, .large`, `min(…, .accessibility2)`) stay flagged. Q02: token arithmetic flags `+`, `−`, `/` or a fractional `*` with a literal, not a whole multiple (`2 * LedgerSpacing.screen` is a count of tokens). Q03: hierarchical styles (`.primary` … `.quinary`) are flagged only in argument position; after `=`, `?`, `??`, `{`, `return` only colour names are. | Q01–Q03 pass; round 2's D01, D04, D06 and round 3's K03 still flagged |

`inkMuted` on the selected-item tint, as SwiftUI paints it (8-bit composites):

| `inkMuted` on `accentSoft` over… | before (.60 light / .48 dark) | after (.62 / .51) |
|---|---|---|
| paper (light `ground`) | 4.33 | **4.62** |
| card (light `surface`) | 4.55 | 4.87 |
| dark `ground` | 4.39 | **4.76** |
| sheet (dark `surface`) | 4.22 | **4.60** |
| plain ground / surface, light | 4.55 / 4.76 | 4.84 / 5.10 |
| plain ground / surface, dark | 4.59 / 4.58 | 5.05 / 5.04 |

### Retired and retargeted assertions (decision 1)

Both line-placement suites were kept and retargeted to the new contract: `.ledgerFont` moves nothing inside the view (a background stays on the frame, nested roles don't add up), lines are line height × size apart, first-baseline alignment across roles holds, and a lone line sits where SwiftUI's own line height puts it. Each file's doc comment cites decision 1.

- `LedgerFontLineBoxAdversarialTests.singleLine_baseline_matchesCSSHalfLeading` → `singleLine_baseline_matchesNativeLineHeight`: asserted the baseline at `L/2 + (ascent − descent)/2` em (CSS half-leading) ± 3 %; now the baseline equals the same "H" set with only the role's font and `lineHeight(.multiple(factor:))` (± ½ pt), and the frame is L × size. Retired because decision 1 drops CSS placement.
- `LedgerFontLineBoxAdversarialTests.singleLine_capitalInk_staysInsideFrame`: asserted the cap line and the baseline inside the frame for all 21 roles; the cap-line half is unchanged, the baseline half now applies to roles with line height ≥ 1. Natively watchNumeral's baseline is 0.14 em below its 0.86 em frame, which decision 1 accepts ("1–10 pt off").
- `LedgerFontLinePlacementAdversarialTests.singleLine_everyTextSize_matchesCSS` → `singleLine_everyTextSize_matchesNativeLineHeight`: asserted the CSS baseline at xSmall, xxxLarge, AX3 and AX5; now the native baseline at the same scaled size (± ½ pt). The cap line inside the frame and frame = L × size are unchanged.
- `LedgerFontLinePlacementAdversarialTests.twoLines_bothBaselines_matchCSS` → `twoLines_baselinePitch_isLineHeightTimesSize`: asserted both baselines at their CSS positions; now their distance is L × size (same 3 % + ½ pt tolerance). Frame = 2L × size unchanged.
- `nestedRoles_innerRole_placesItsOwnLine`, `firstTextBaseline_twoRoles_shareOneBaseline`, `background_underText_staysOnFrame`: assertions unchanged. The nested test's display name loses "(CSS: the child block's lines win)" for "nested roles never add up" (CSS is retired, and the line exceeded 120 columns once nested).
- Removed helpers: `verticalMetrics()` and `cssBaseline(_:size:line:)`, and `import CoreText` in both files.

Other test edits this round, none of which weakens an assertion:
- `TokenValueTests`, `LedgerColorAdversarialTests`: `inkMuted` .48 → .51 dark, .60 → .62 light (finding 20).
- `LedgerFontSizingAdversarialTests`: the body of the 1,008-render test moved into `expectBareFontMatchesLedgerFont(_:at:)`; the full matrix is `.slow` (nightly), the PR subset is a new test (finding 19).
- The 21 main-actor suites are nested in `RenderingSuites` (`git diff -w` shows only the wrapper lines). SwiftLint's `nesting` rule then needed three helper types moved into a trailing extension (`TypeScaleTests.Row`, `LedgerFontLineBoxAdversarialTests.Placement`, `IncreaseContrastTests.Step`); swiftformat re-wrapped the lines that the extra indent pushed past 120 columns, and one display name in `IncreaseContrastAdversarialTests` was shortened for the same reason ("…matches the UIKit trait." → "…matches UIKit."). Snapshot reference names come from the file and function, so no reference moved.
- `scripts/tests/lint-rules-adversarial-round3.test.sh`: B16, B17 and D01–D09 expect `limit` (was a rule or `any`), with a header citing decision 2; a `limit` case fails if a rule starts to flag it. B10's comment notes `.textScale(` is now a font-rule hit. Wired into `check.sh` step 2.

### Design lint: the frozen rule set

The list of what each rule flags, and the known limits, is in `docs/engineering-standards.md` §7 ("Design lint"), with the decision and the review-point-4 statement; `.swiftlint.yml` points there and says the set is frozen. This round's additions, each one alternative in a rule:

| Case | Rule change |
|---|---|
| B01, B02 | colour: a named colour after `{` or `return` |
| B03 | colour: `.quinary` joins the hierarchical styles |
| B04, B05 | colour: a raw alpha on a token also through `.secondary` … `.quinary`, and with the chain wrapped (`LedgerColor.ink⏎.opacity(`) |
| B06 | colour: `Color.Resolved(` |
| B07 | colour: `.color(red:…)` beside `.init(red:…)` |
| B08 | font: a system style assigned to a `Font` (`Font = .title`) |
| B09 | font: `.environment(\.font, …)` read like `.font(…)` |
| B11 | font: `.monospaced(`, `.monospacedDigit(`, `.textScale(` join the role-property modifiers |
| B12–B14 | spacing and radius: a literal in either arm of a simple ternary (`flag ? 13 : token`, `flag ? token : 13`) |
| B15 | radius: `.fixed(n)` after `corners:`, `minimum:` or `…Corner:` (iOS 26 corner styles) |

Known limits (engineering-standards §7): a comment inside the call (B16, B17); a raw value in a constant, a compound ternary, `??` or untracked arithmetic (D05); a size cap or a pin above the default (D01); `.minimumScaleFactor` (D02); a raw alpha on the view (D03); gaps made with a frame (D04); `.separator` and materials (D06, D07); `.baselineOffset` and `.textCase` (D08, D09); `LedgerFont.archivo` with literals (round 1's N12); and the accepted false positive of a feature enum case named like a style or colour.

Checks: rounds 1, 2 and 3 all pass (`lint-rules.test.sh` 12/12, 55/55, 39/39, 44/44 with 11 `limit`); the whole repo lints clean; a probe of 20 legitimate spellings (a feature enum with `.primary` after `=`, `{`, `return`; token-only ternaries; `spacing: flag ? 0 : token`; `GridItem(.fixed(80))`; `2 * LedgerSpacing.screen`; `LedgerSpacing.s * 2`; `.environment(\.font, LedgerFont.font(…))`; `.dynamicTypeSize(.xLarge)`; `.color(LedgerColor.accent)`; view `.opacity`) raised one hit, the documented enum false positive (`isCompact ? .secondary : .primary`).

### Snapshots, and a clipping bug the eye check found

The first `--record-snapshots` run (through the lock) re-recorded all 16 references, and checking them by eye showed that
the phone type ramp at `.xLarge` and `.accessibility3` was clipped at the top and bottom, in both schemes. That predates
this round: since `8e3a273` every phone ramp reference has had the `.large` height (733–734 px) at every text size, with
ink 0–4 px from the top and bottom edges where the specimen's padding is 16 pt. Cause: swift-snapshot-testing's `.image(layout: .sizeThatFits,
traits:)` measures the view with `UIHostingController.sizeThatFits(in:)` before it applies `traits`, so a sheet at a
larger text size is laid out in its `.large` size. Fix, in the test harness: `View.snapshotAppearance(_:)`
(`LedgerSnapshotTesting/SnapshotConfig.swift`) puts the appearance's text size and colour scheme in SwiftUI's
environment too, and `phoneTypeRamp_appearance_matchesReference` uses it. Slice 2's component matrix should use it on
every phone snapshot. A second recording run (through the lock) re-recorded the same 16 files; in both runs every
failure was a recording (iOS 5 tests, watchOS 4), nothing else failed.

| Re-recorded reference | Why it changed | Size | Eye check |
|---|---|---|---|
| `ArchivoFontTests/widthAxis_88versus112_rendersDifferentGlyphWidths.iOS.png`, `.watchOS.png` | the `wdth` labels are `caption` in `inkMuted`: native placement and the new alpha | 331×261, unchanged | labels and numerals inside; the five widths as before |
| `TokenSnapshotTests/phonePalette_scheme_matchesReference-_.light-large.png`, `.dark-large.png` | name labels' placement; the `inkMuted` swatch | 402×472, unchanged | inside |
| `TokenSnapshotTests/phonePalette_increasedContrast_matchesReference-_.increasedContrast-light-large.png`, `-dark-large.png` | name labels' placement | 402×472, unchanged | inside |
| `TokenSnapshotTests/phoneTypeRamp_appearance_matchesReference-_.light-large.png`, `.dark-large.png` | placement (each line up to ~6 pt lower in its row, bodyLight ~2 pt higher); `inkMuted` role names | 402×733, unchanged | inside |
| `TokenSnapshotTests/phoneTypeRamp_appearance_matchesReference-_.light-xLarge.png`, `.dark-xLarge.png` | as above, plus the harness fix | 402×733 → **402×795** | whole ramp visible, display to numeralS |
| `TokenSnapshotTests/phoneTypeRamp_appearance_matchesReference-_.light-accessibility3.png`, `.dark-accessibility3.png` | as above, plus the harness fix | 402×733 → **402×1249** | whole ramp visible; the longest samples end in "…" on one line, as they did before (not clipping) |
| `TokenSnapshotTests/phoneTypeRamp_boldText_matchesReference.bold-dark-large.png` | placement; `inkMuted` role names | 402×733, unchanged | inside |
| `TokenSnapshotTests/watchPalette_46mm_matchesReference.mm46.png` | name labels' placement | 208×280, unchanged | inside |
| `TokenSnapshotTests/watchTypeRamp_46mm_matchesReference.mm46.png`, `watchTypeRamp_boldText46mm_matchesReference.bold-mm46.png` | placement | 208×361, unchanged | inside; watchNumeral's figures now end ~6 pt below its frame, about 6 pt above the next row's label (decision 1) |

Measured, not only looked at: the ink of every reference stays at least 15 px from each edge at `.large` (the
specimens' 16 pt padding) and at least 9 px at `.xLarge` / `.accessibility3` (it was 0–4 px before the harness fix).
`__Snapshots__` is 16 PNGs, 864 KB (budget 6 MB).

### Verification — fix round 3 (2026-09-29)

- `scripts/check.sh --fast`: green (format, lint, the four lint fixture scripts, package graph, host Domain +
  Persistence 419 tests). Host `swift test --filter LedgerDesignTests`: every retargeted and new test passes; the only
  failures are the known macOS gaps (no Dynamic Type, and the spike records a macOS reference, deleted). iOS and watchOS
  `build-for-testing`: 0 warnings.
- **Full `scripts/check.sh` through the simulator lock: green on the first full run**
  (`scratchpad/f06-fix3-check.log`, 185 s: iOS 96 s, watchOS 82 s). The machine was not idle: another worktree's
  work kept the 1-minute load average at 135–509 while this gate held the lock (sampled every 30 s).
  - PR-iOS: **564 tests, 563 passed, 1 skipped** (the nightly-only full bare-font matrix); 17/17 test targets.
  - PR-watchOS: **543 tests, 542 passed, 1 skipped** (same); 8/8 test targets.
  - Step 2: `lint-rules.test.sh` 12/12, `lint-rules-adversarial.test.sh` 55/55, `…-round2` 39/39, `…-round3` 44/44
    (33 asserted plus 11 documented limits).
  - Finding 19, measured: the longest `LedgerDesignTests` test in the gate took **1.57 s on iOS** and 0.26 s on
    watchOS (fix round 2's green run had all 121 design tests ending at 55–61 s, against the 60 s allowance).
- LedgerDesign line coverage (xccov, `Sources/LedgerDesign/`): **95.4 %** iOS (187/196), **95.2 %** watchOS (180/189);
  target 60 %. The lines removed with the lift were covered, hence the small drop from 95.7 / 95.5.
- LedgerDesign product Swift against `main`: **+486 −4 = 490 changed lines** (≤ 500; was 497). This round: +11 −18.
- Not touched: `Ledger.xcodeproj` (Pete still has to delete the dangling `Fonts` group), the test plans, the plans' 60 s
  allowance.

## Fix round 4 (review should-fix)

Against the G3 review (`review.md`: 0 Blocking, S1, S2, N1–N8) and the adversarial round 4's finding 24, on
`e94b600`. No `LedgerDesign` source changed. Left alone, as the orchestrator asked: the review's merge note about
F01 (the `check.sh` conflict and the lint scripts running twice).

### Should fix → change → test

| # | Change | Test |
|---|---|---|
| S1 / finding 24 | `snapshotAppearance(_:)` now also applies `.fixedSize(horizontal: false, vertical: true)`. swift-snapshot-testing 1.19 sizes a `.sizeThatFits` view with `sizeThatFits(in: .zero)`, which offers text no height and cuts it to one line with "…"; with the fixed size the sheet takes its own height and text wraps as on a device. New `assertPhoneSnapshot(of:_:named:modifyingTraits:)` (`LedgerSnapshotTesting/PhoneSnapshot.swift`, iOS) is the one way a phone test takes a snapshot: `snapshotAppearance`, the appearance's traits (plus `modifyingTraits`, used for Increase Contrast) and `SnapshotConfig`'s precisions, forwarding `#file`/`#filePath`/`#function` so reference names don't move. All four phone tests in `TokenSnapshotTests` use it; the Bold Text ramp and both palettes used to skip `snapshotAppearance`. `docs/testing-strategy.md` §2.5 now names the helper and why. Test-only code. | `SnapshotAppearanceAdversarialTests.phoneRamp_strategyLayout_takesIdealHeight` passes at large, xLarge, AX3 and AX5 (it failed at AX3 and AX5 in round 4), and `…_notClipped` still holds. The re-recorded AX3 references pin the wrapped layout: dropping the fixed size would make them 1249 px again and fail on size. I did not add a second "two-line string is taller" test; the round-4 test is that test, at AX3 and AX5 |
| S2 | The four `ledger_raw_*` rules' `included` is now `'LedgerKit/Sources/(Feature\w*\|WatchFeature\w*\|LedgerAppKit\|LedgerWatchAppKit)/.*\|Apps/.*'`, written once (`&ui_modules`) and reused by the other three rules. The `*design_allowlist` excludes are kept. The regexes are unchanged. Under Pete's decision of 2026-09-29 (a tripwire with a frozen rule set) this is a false-positive fix: `LedgerDomain`, `LedgerDependencies`, the adapters and `LedgerActivityKit` are Foundation-only (standards §2), so any hit there is a false positive. Engineering-standards §7 says so next to the rule list, and names the scope. Module list checked against `LedgerKit/Package.swift` and architecture §3. | `lint-rules.test.sh`, 12 new checks: a Foundation-only file (`enum PlateColor { case black, red }`, `return .black`, `return .red`, `NameRule(minLength: 2)`) is flagged by exactly `ledger_raw_color` and `ledger_raw_spacing` in `FeatureToday`, `WatchFeatureWorkout`, `LedgerAppKit`, `LedgerWatchAppKit`, `Apps/Ledger` and `Apps/LedgerWatch`, and by nothing in the six Foundation-only modules. Against the old config the six Foundation-only checks fail (checked with a copy of the script pointed at `HEAD:.swiftlint.yml`). Rounds 1–3 unchanged: 55/55, 39/39, 44/44 |

### Nits

| # | Done? | Change | Test |
|---|---|---|---|
| N1 | Reworded | The `.png` comparator stays CIE76. Its doc comment and testing-strategy §2.5 now say it uses the library's ΔE threshold and that CIE76 is never smaller than the CIE94 Core Image measures, so it is at least as strict. I did not implement ΔE94: which chroma Core Image weights by (the reference's, or a mean) is not documented, so "matches the library" still wouldn't be provable, and the stricter comparison can't cause a false pass. | Comparator suites unchanged and green |
| N2 | **Skipped** | Needs slice 3: a `.performance` test on the watch simulator once the watch components exist, and a decision on where a font cache would live (standards §3, global mutable state). The review itself defers it. | — |
| N3 | Yes | The spike's `assertSnapshot` is `#if os(iOS) \|\| os(watchOS)`, so `swift test` on the Mac no longer writes `…macOS.png` into `__Snapshots__`. New `ConditionTrait.simulatorOnly` (`Support/Tags.swift`, `.disabled(if: SnapshotConfig.platform == "macOS")`) on the five tests that need Dynamic Type or pixel-stable renders: `TypeScaleTests` ×2, `LedgerFontRenderingAdversarialTests` ×2, `SnapshotHarnessAdversarialTests.render_sameViewRepeatedly_isPixelIdentical`. The three adversarial tests only gain the trait: no assertion changed, and the trait is a no-op on iOS and watchOS. `SnapshotConfig.platform`'s comment now says only the spike carries the platform in its name. | Host `swift test --filter LedgerDesignTests`: 122 tests, 0 failed (was 32 issues in 5 tests), 5 skipped on macOS plus the nightly-only matrix; no stray reference. Gate: the same tests run and pass on both simulators |
| N4 | Yes | `check.sh --record-snapshots`: after each plan, `xcresulttool get test-results summary` must report `totalTestCount > 0`, or the script exits 1 with "the record run failed before any test ran". A `[[ -d "$result" ]]` check would not do: xcodebuild writes a result bundle even when it fails before any test. | A deliberately failed `xcodebuild test` (unknown destination) left a bundle with `totalTestCount` 0 and the check trips; the real record run (below) passed it on both platforms |
| N5 | **Skipped** | No product or test change; it is a device check. F20's protocol is the M2 sync protocol, and its criterion 1 counts exactly 14 scenarios. The watch feature that first uses `ledgerBuzz` (F18) has no brief section for it yet. Which brief owns "buzz with Reduce Motion on shows an opacity pulse, no shake" is the orchestrator's call. | — |
| N6 | Yes | Deleted the stale "Not wired into check.sh…" lines from `lint-rules-adversarial-round2.test.sh`'s header. Comment only. | 39/39 |
| N7 | Yes | The brief's public-surface block now shows `font(_:dynamicTypeSize:legibilityWeight:)`, `font(_:size:legibilityWeight:)`, `scaledSize(_:dynamicTypeSize:)`, `View.ledgerFont(_:)`, `buzzKeyframes(reduceMotion:)` and `View.ledgerBuzz(trigger:)` in place of `font(_ role:)` and `buzz`. | — |
| N8 | Yes (documented) | Standards §7 known limits: "a role's design size passed back as a fixed size (`LedgerFont.font(.body, size: LedgerFont.Role.body.spec.size)`) drops Dynamic Type". The slice-3 option (make `spec` internal along with `archivo(…)`) is a design change and left to slice 3. | `lint-rules.test.sh`: that spelling is not flagged, and the check fails once a rule starts to flag it, like round 3's `limit` cases, so §7 stays true |

### Re-recorded references

`scripts/check.sh --record-snapshots` ran once, fully, through the lock (`scratchpad/f06-fix4-record.log`, 242 s). The
only failures were recordings: iOS 574 tests, 568 passed, 5 recordings, 1 skipped; watchOS 551 tests, 546 passed,
4 recordings, 1 skipped. All 16 references were rewritten, and 14 came back byte-identical, including the two
palettes, the two Increase Contrast palettes and the Bold Text ramp that now go through `assertPhoneSnapshot`. Two
changed, both compared pixel by pixel with `HEAD` and opened:

| Reference | Size | Eye check |
|---|---|---|
| `TokenSnapshotTests/phoneTypeRamp_appearance_matchesReference-_.dark-accessibility3.png` | 402×1249 → **402×1454** (finding 24's own-height figure) | No "…" anywhere. Each sample that was cut now wraps to two lines: display "Train four days / a week", title and heading "Upper A — / Push focus", bodyLight "Same movement pattern, / equipment you have.". The whole ramp is visible, display to numeralS. Ink margins: top 17, bottom 9, left 16, right 41 px |
| `TokenSnapshotTests/phoneTypeRamp_appearance_matchesReference-_.light-accessibility3.png` | 402×1249 → **402×1454** | Same as dark; same margins |

`__Snapshots__`: 16 PNGs, 908 KB (budget 6 MB).

A process note: my first N4 edit dropped the `else` in `run_plan`. I read the diff before the record run finished,
stopped that run (it hadn't written a reference), fixed the edit, checked it with `bash -n` and a diff, and restarted
the run. Rule for next time: when an edit replaces a line of control flow, read the diff before running anything.

### Verification — fix round 4 (2026-09-29)

- `scripts/check.sh --fast`: green (format, lint, the four lint fixture scripts, package graph, host Domain +
  Persistence 419 tests). `lint-rules.test.sh` is now 25 checks: 12 + 12 for the scope + 1 known limit.
- Host `swift test --package-path LedgerKit --filter LedgerDesignTests`: 122 tests pass, 6 skipped (5 `simulatorOnly`
  plus the nightly-only matrix), and nothing is written to `__Snapshots__` (N3). Before this round: 32 issues in 5
  tests and a stray `…macOS.png`.
- **Full `scripts/check.sh` through the simulator lock: green on the first run, once**
  (`scratchpad/f06-final-check.log`, 200 s: iOS 109 s, watchOS 79 s; it waited 306 s for another worktree's run).
  - PR-iOS: **574 tests, 573 passed, 0 failed, 1 skipped** (the nightly-only full bare-font matrix, `.slow`);
    17/17 test targets. `SnapshotAppearanceAdversarialTests` passed in full, including
    `phoneRamp_strategyLayout_takesIdealHeight` at AX3 and AX5 (finding 24), and all 11 `TokenSnapshots` cases
    matched their references.
  - PR-watchOS: **551 tests, 550 passed, 0 failed, 1 skipped** (the same `.slow` matrix); 8/8 test targets.
  - Step 2: `lint-rules.test.sh` 25/25, `…-adversarial` 55/55, `…-round2` 39/39, `…-round3` 44/44; package graph
    matches.
- LedgerDesign line coverage (xccov, `Sources/LedgerDesign/`, the `LedgerDesignTests` copy): **95.5 %** iOS
  (192/201), **95.2 %** watchOS (180/189); target 60 %. No product source changed. The uncovered lines are
  `FontRegistration`'s failure logging and `LedgerMotion`'s `accessibilityReduceMotion` read (N5).
- LedgerDesign product Swift against `main` (merge base `8404d02`): **+486 −4 = 490 changed lines**, unchanged
  (≤ 500). This round's Swift is all test-only: `LedgerSnapshotTesting` (+1 file, `PhoneSnapshot.swift`) and
  `LedgerDesignTests`.
- Not touched: `Ledger.xcodeproj`, the test plans and their 60 s allowance, the lint regexes, and the F01 merge note.

## Slice 2

Branch `feat/F06-slice2-components` (from `main` 638013d). Scope: the slice-plan row for slice 2 —
`PrimaryButton`, `PillButton`, `IconPillButton`, `Eyebrow`, `HairlineList` / `HairlineRow`, `SetRow` +
`SetRowSteppers` (the brief's `Stepper`) and `RestRing`, in `LedgerKit/Sources/LedgerDesign/Components/`, with
previews, the 6-image phone matrix each, `RestRingGeometryTests` (criterion 5) and `ComponentAccessibilityTests`
(criterion 6). Nothing from slice 3 was started.

### Components

Every component uses tokens only (colour, `.ledgerFont` roles, spacing, radius, hairline); the few raw numbers
are component dimensions that live here and nowhere else (54 pt CTA, 44 pt target, the ring's SVG proportions,
the icon grid), each named and sourced. Each takes display strings the caller has already localised: features
keep their copy in their own string catalogs (F09–F12 `Resources/Localizable.xcstrings`), and a
`LocalizedStringKey` resolved inside `LedgerDesign` would look in the main bundle instead.

| Component | Prototype source (v2 unless said) | Decisions |
|---|---|---|
| `PrimaryButton(_:icon:action:)` | Today "Start workout": `#FF5B22` pill, 600 16 px, 19 px padding, 10 px gap, 17 px arrow; disabled from v1 Library's add button (ink .10 fill, .38 text) | `button` role (700, decision 7), white on `accent`; full width, **min height 54** (spec §8.6) with `m` / `xl` padding so wrapped titles grow it; disabled: `hairline` fill, `inkMuted` label |
| `PillButton(_:style:action:)` | "Finish" / "Repeat" (outline .16, 500 11.5–12.5 px), selected filter (filled with text colour, ground label), "Cancel" / "Skip setup" / "+ Add set" (ghost, 400 13 px at .32–.40) | `.outline` (`hairlineStrong` border, `ink`), `.filled` (`ink` fill, `ground` label), `.ghost` (`inkMuted`, no horizontal padding); `caption` role; the pill is drawn at text size, the target is ≥ 44 × 44 around it |
| `IconPillButton(_:icon:action:)` | swap button: 38 pt circle, `.14` border, 17 px icon at .6 | 44 pt at the default size (the brief), growing with its icon; `hairlineStrong` ring, `inkSecondary` icon; the string is its VoiceOver label |
| `Eyebrow(_:tint:)` | 500 10 px, .18 em, uppercase: "UP NEXT" orange, "RECENT" / "REMAINING" at .32–.34 | `eyebrow` role; `.accent` → `accentText`, `.muted` → `inkMuted`; `.isHeader` for the VoiceOver rotor |
| `HairlineList { }`, `HairlineRule` | every v2 list: `border-top: 1px LINE` per row plus a closing rule | each row draws its own top rule (so `SetRow` can make its own orange), the list adds the closing one; `HairlineRule` is public for other rules |
| `HairlineRow(_:detail:action:accessory:)` | RECENT / Library / REMAINING / swap rows: 16 px vertical padding, 500 15 px title, 300 12.5 px meta at .36–.38, trailing chevron / PR / "Use" | `body` title in `ink`, `label` detail in `inkMuted`, a generic trailing accessory; with an action the whole row is one button; at accessibility sizes the accessory moves under the title |
| `SetRow(number:weight:reps:state:checkLabel:onSelect:onCheck:)`, `SetRowState` | set rows: grid `22px 1fr 1fr 42px`, gap 10, padding 15; label 400 12.5 px; values 700 24 px wdth 90 (= `numeralM`); 32 px check; colours from the script's `rows` mapping | row body and check are two sibling buttons; label `caption`; active: `accentText` label, `accentLine` rule, orange ring; done: muted values, tick in an `accent` disc; the label column is 22/12 em of `caption`, so it scales; values too long for their column at the largest sizes shrink (≥ 0.5) rather than break mid-number |
| `SetRowHeader(number:weight:reps:)` (added) | column headings "#", "lb", "reps", 400 11 px at .30 | shares `SetColumns` with the rows and reserves the check column with a hidden `SetRowCheck`, so header and rows line up at every text size; F10 would otherwise have to copy the grid |
| `SetRowSteppers(weightStep:repStep:onWeight:onReps:)` | two outlined pills (.12), "−" / "+" (300 20 px at .6), step "5 LB" / "1 REP" (400 10.5 px, .09 em, .32) | `hairlineStrong` pill, glyphs as `LedgerIcon.minus/plus` in `inkSecondary`, step in `eyebrow` / `inkMuted`; each "−" and "+" is a ≥ 44 pt target; pills stack at accessibility sizes |
| `RestRing(progress:label:size:)`, `RestRingGeometry` | rest card ring: 64 px, r 29, stroke 2.5, track .12, `stroke-dasharray 182`, rotated −90°, label 500 16 px tabular; spec §8.8 | `progress` is the fraction of rest left, clamped to 0…1 (NaN → 0); the arc runs from 12 o'clock clockwise; track `hairlineStrong`, arc `accent` with round caps, label `numeralS` in `ink`; the ring (and stroke) scale with the label's Dynamic Type size; `RestRingArc` animates `progress`; `RestRingGeometry.phone` is public so slice 3's `WatchRestRing` adds `.watch` (200 / 88 / 9) |
| `LedgerIcon`, `LedgerIconView(_:sizedAs:)` (supporting) | spec §8.7 "other icons": arrow, check, chevron, swap; the steppers' "−" / "+" | polylines on the 24-pt grid at the SVG stroke width, round caps and joins; sized like a type role so icons scale with the text beside them; stroke × 1.3 under Bold Text; hidden from VoiceOver |
| `.ledgerHitTarget()`, `.ledgerPill` (supporting) | HIG 44 pt; CSS `border-radius: 999px` | the target modifier goes inside a button's label so the button and its accessibility frame are the full target; `.ledgerPill` is `Capsule(style: .circular)` (below) |

Each component file ends with an internal `…Gallery` view holding every state (PrimaryButton: arrow, long title,
disabled; PillButton: the three styles and a long title; SetRow: done, active with steppers, pending, a drop set).
The `#Preview`s show those galleries and live together in `Components+Previews.swift`: testing-strategy §4 puts
every `#Preview` body in a `*+Previews.swift` file, which the coverage gate (F01's `excludedFiles`) leaves out. The
snapshot tests render the same galleries, and slice 3's `DesignGallery` can list them.

### Decisions and deviations

1. **Contrast, AA with the look kept (Pete, 2026-09-27).** Where the prototype draws meaningful text below AA,
   the component uses the lowest AA token instead: `inkMuted` for the muted eyebrow (.32–.34), ghost pills
   (.32–.40), row details (.36–.38), the set label (.40) and column headings (.30), the stepper step (.32), and
   done set values (`DIM`, .28: logged numbers still carry meaning). For non-text (WCAG 1.4.11, 3:1), the set
   row's check is the only mark of its control, so its rings move: pending .14 → `inkMuted` (5.0 dark / 4.8 light),
   active .5 white → `accentText` (6.3 / 5.1). The active check is then the row's orange, which F10's criterion 13
   already expects ("check on the active row"). Unchanged and still AA: white on `accent` in `PrimaryButton`
   (3.1:1 at 700, decision 7) and the done tick; icons in `inkSecondary`. The ring's `accent` arc on paper is
   2.6:1, but the countdown in its middle carries the same information, so the arc is not required to read it.
2. **No new type roles.** Pill labels use `caption` (400 12; the prototype's are 500 11.5–14), the ring label
   `numeralS` (700 15, tabular; the prototype's is 500 16 tabular: a ticking countdown needs tabular figures,
   and v2's numbers are 700), the set label `caption`, the stepper step `eyebrow`. The stepper "−" / "+" are
   drawn icons, not 300 20 px text.
3. **Native line height (Pete's decision 1).** Components size themselves with spacing tokens and minimum
   frames, not by matching CSS line boxes: the CTA is min 54 pt, rows pad `l` (16; prototype 13–17), the set row
   pads `s` around its 44 pt check target (the prototype's 15 around a 32 pt circle), header gaps `s` (10).
4. **Circular capsules.** `Capsule()` defaults to continuous corners on iOS 26 (Apple docs, `init(style:)`), and
   CSS `border-radius: 999px` draws circular ends, so every pill is `.ledgerPill`. It also fixed a harness
   problem found in the first recording: a continuous `Capsule` or `RoundedRectangle` stroke rendered through
   swift-snapshot-testing's `layer.render(in:)` gets stray vertical segments outside each end (reproduced in a
   throwaway test: `ImageRenderer`, a circular capsule and a custom path were all clean). Circles were unaffected.
5. **Dynamic Type through AX5.** Icons and the ring scale with a text role; `HairlineRow` and `SetRowSteppers`
   switch to a vertical layout at accessibility sizes; set numerals may shrink to half size only when a value
   cannot fit its column. `allComponents_accessibility5` records every gallery at AX5 (below): text wraps,
   nothing is cut.
6. **Accessibility.** Buttons get `.isButton` from `Button`; `SetRow` is two elements, the row (its visible
   text, `.isSelected` when active) and the check (`checkLabel`, `.isSelected` when done); each stepper is one
   adjustable element named by its step, whose increment and decrement call the matching direction; `Eyebrow`
   is a header; `RestRing` is one element with `.updatesFrequently`; icons are hidden.
7. **Not built:** a full-width `PillButton` (v2's rest card puts "+30s" and "Skip rest" side by side at
   flex 1) and designed disabled looks for `PillButton` / `IconPillButton`. Neither is in the brief; F10 can ask
   for them (a `controlSize` variant would be the SwiftUI way). SwiftUI still blocks taps on a disabled pill and
   reports `.notEnabled`.

### Test infrastructure (test-only)

- `LedgerSnapshotTesting/AccessibilityElements.swift`: `View.accessibilityElements(_:)` and
  `withAccessibilityElements(_:_:)` host a view in a window at a matrix appearance and read UIKit's accessibility
  tree. A probe showed a hosted SwiftUI view reports **no** elements in a test process until UIKit's
  accessibility automation is on (`_AXSSetAutomationEnabled` in libAccessibility, private and test-only, as KIF
  and AccessibilitySnapshot do); the helper turns it on while it reads and restores it. Without a window every
  frame is zero, and a package test process has no window scene (`connectedScenes` is empty), so the window is
  made with `UIWindow(frame:)`, deprecated in iOS 26, through a protocol and a deprecated wrapper so the build
  stays warning-free (swift-snapshot-testing makes its windows the same way). testing-strategy §2.5 describes it.
- A button's accessibility frame is its tappable area (probe: a 44 pt frame inside the label gives a 44 pt
  element; the same frame outside, after `.accessibilityLabel`, does not), which is why `.ledgerHitTarget()`
  goes inside the label and how the tests measure the target.
- Isolation, as slice 1 set it up: `RestRingGeometryTests` is `nonisolated` (values only); the render, snapshot
  and accessibility suites are nested in `RenderingSuites`. No matrix is heavy enough for `.slow`.

### Criteria → tests

| Criterion | Tests |
|---|---|
| 3 (slice-2 components) | `ComponentSnapshotTests.swift`, one suite per component, each `…_appearance_matchesReference` over `SnapshotAppearance.phoneMatrix` through `assertPhoneSnapshot`: `PrimaryButtonSnapshotTests`, `PillButtonSnapshotTests`, `IconPillButtonSnapshotTests`, `EyebrowSnapshotTests`, `HairlineListSnapshotTests` (with `HairlineRow`), `SetRowSnapshotTests` (with `SetRowHeader`, `SetRowSteppers`), `RestRingSnapshotTests`. Beyond the matrix, `ComponentSheetSnapshotTests` records every gallery at AX5 and with Bold Text |
| 5 | `RestRingGeometryTests`: half the circumference at 0.5 (half ÷ full ring = 0.5 to 1e-9; against 2π·29 within the 0.03 % Béziers allow, measured 0.014 %), 12 → 6 o'clock clockwise (a quarter ends at 3), proportional at 8 fractions, full ring = `stroke-dasharray` 182 and closes, empty at 0 / −0.001 / −0.5 / −∞ / NaN, full at 1 / 1.0001 / 1.5 / 30 / +∞, and half is half at the ring's rendered sizes up to AX5. `RestRingRenderTests.halfProgress_rendered_isOrangeOnTheRightHalfOnly` checks the rendered pixels (iOS and watchOS) |
| 6 | `ComponentAccessibilityTests` (iOS, at `.large` and `.accessibility3`): `PrimaryButton` label = title, `.button`, ≥ 44 × 44 (and ≥ 54 tall), one element; disabled → `.notEnabled`; `PillButton` (3 styles), `IconPillButton`, tappable `HairlineRow`: label, `.button`, ≥ 44; a static `HairlineRow` is one non-button element; `SetRow` (3 states): row and check are labelled buttons ≥ 44, `.selected` as the state says, and activating each calls its own action; `SetRowSteppers`: two adjustable elements ≥ 44, and VoiceOver's increment / decrement step the right value the right way; `Eyebrow` is a header; `RestRing` reads its countdown and updates frequently |

### New references (44 PNGs, 1×; recorded on iPhone 17 / iOS 26.5 under Xcode 26.6, re-recorded under Xcode 27.0)

All in `LedgerKit/Tests/LedgerDesignTests/__Snapshots__/ComponentSnapshotTests/`:

- `{primaryButton,pillButton,iconPillButton,eyebrow,hairlineList,setRow,restRing}_appearance_matchesReference-_.{light,dark}-{large,xLarge,accessibility3}.png`
  (42; heights at large / xLarge / AX3: PrimaryButton 262 / 262 / 313, PillButton 252 / 252 / 287,
  IconPillButton 96 / 96 / 112, Eyebrow 114 / 126 / 192, HairlineList 295 / 307 / 534, SetRow 409 / 409 / 483,
  RestRing 276 / 296 / 497; all 402 wide)
- `allComponents_accessibility5_matchesReference.dark-accessibility5.png` (402 × 3149)
- `allComponents_boldText_matchesReference.bold-dark-large.png` (402 × 1584)

Recorded with `scripts/check.sh --record-snapshots` through the simulator lock (`scratchpad/f06s2-record.log`):
the only failures were recordings (iOS 14 tests, watchOS 4, record mode fails every snapshot test), and every
slice-1 reference came back byte-identical. Each PNG was opened and checked: the prototype's intent, nothing cut
at any edge, text wrapping at AX3 (PrimaryButton's "Resume workout · 12:48", PillButton's long title, Eyebrow's
"Estimated 1RM · 8 weeks", HairlineRow's accessory under its title) and at AX5 on the sheet, dark variants on
`#0B0B0D`. Sampled rather than eyeballed where a thumbnail misleads: the active set row's rule is `#6D2B16`
(accent at 40 % over the ground). `__Snapshots__` is 2.0 MB in all (budget 6 MB).

### Size

Measured with a script that counts Swift lines that are not blank and not a whole-line `//`, `///` or `/* */`
comment, over the new files (everything here is new, so a diff adds nothing):

| | Code lines |
|---|---|
| `LedgerDesign/Components/` (product) | **650** |
| — of which galleries (`…Gallery`, reused by tests and slice 3) | ~87 |
| — of which `Components+Previews.swift` | 34 |
| Test-only: `LedgerSnapshotTesting/AccessibilityElements.swift` | 91 |
| Tests: `ComponentAccessibilityTests` 170, `ComponentSnapshotTests` 92, `RestRingGeometryTests` 138 | 400 |

Over the 500-line target and well under the ~1,000 split line (standards §10). The split considered: 2a,
the controls (`LedgerIcon`, the three buttons, `Eyebrow`, ~260 lines), then 2b, the lists (`HairlineList` /
`Row`, `SetRow` + header + steppers, `RestRing`, ~390). Not taken: 2b's set row needs 2a's icons and hit
target, the two halves would not merge independently any sooner, and neither is near 1,000. Nothing was
compressed to fit. The ~50 lines above the slice plan's 400–450 are `LedgerIcon` (the brief lists no icons,
but `PrimaryButton(icon:)` and `IconPillButton` need them) and `SetRowHeader`.

### Gate

- Iteration: `scripts/check.sh --fast` green (format, lint and the four lint fixture scripts, package graph,
  host Domain + Persistence 419 tests). Host `swift test --filter LedgerDesignTests`: 130 tests passed, no
  warnings. `LedgerDesignTests` on each simulator on its own: iOS 173 (all passing once references existed),
  watchOS 137 passed + 1 skipped.
- **Full `scripts/check.sh` through the lock: green** (Xcode 26.6, 17:04–17:08; 248 s: lint 7 s, iOS 155 s,
  watchOS 86 s):
  - PR-iOS: **603 tests, 602 passed, 0 failed, 1 skipped** (the nightly-only bare-font matrix); 17/17 test
    targets ran and passed. `LedgerDesignTests`: 173 results (slice 1: 143).
  - PR-watchOS: **559 tests, 558 passed, 0 failed, 1 skipped**; 8/8 test targets. `LedgerDesignTests`: 138.
  - Step 2: `lint-rules.test.sh` OK, round 1 55/55, round 2 39/39, round 3 44/44; package graph unchanged.
- LedgerDesign line coverage (xccov, `Sources/LedgerDesign/`): **96.2 % (887 / 922)**, iOS and merged the way
  testing-strategy §4 and F01's gate merge the bundles (per file, the larger measurement); slice 1: 95.5 %;
  threshold 60 %. The components alone: 96.4 % (695 / 721). On the watchOS bundle alone LedgerDesign reads
  25.4 %, because the phone components' snapshot and accessibility tests can only run on iOS
  (swift-snapshot-testing has no watchOS image strategy; the accessibility tree is UIKit's); slice 3's watch
  components bring their own watch snapshots.
- The bullets above are the Xcode 26.6 run. The previews then moved into `Components+Previews.swift`
  (testing-strategy §4's convention, no rendering change); the re-run on 26.6 could not build because
  `/Applications/Xcode.app` was auto-updated to 27.0 mid-session. The work was committed as `079ddcd`, and Pete's
  move to Xcode 27.0 (F32, PR #10) was merged into this branch (`9988347`).
- **Xcode 27 re-record.** `scripts/check.sh --record-snapshots` through the lock on `9988347`
  (`scratchpad/f06s2-27-record.log`; iPhone 17 / iOS 27.0, Apple Watch Series 12 46 mm / watchOS 27.0): **38 of
  the 44 slice-2 references changed, all font rendering only; no layout change.** Each was compared with its 26.6
  version from `079ddcd` (a side-by-side old | new | difference image per file, every one opened): identical
  dimensions, identical line breaks and positions, 0.2–1.2 % of pixels different, every difference on glyph
  edges, and no pixel off by more than 64 in any channel. Rules, rings, arcs, pill outlines, check discs and
  icons are unmarked. The 6 `iconPillButton_…` references, which hold no text, came back byte-identical, and so
  did every slice-1 reference (F32's). The only failures in that run were the recordings.
- **Full `scripts/check.sh` through the lock on Xcode 27.0: green** (`scratchpad/f06s2-27-check.log`, 344 s,
  after `rm -rf .derivedData/SourcePackages` for F32's new pins; step 0 confirmed the 27.0 pin):
  - PR-iOS: **866 tests, 864 passed, 0 failed, 2 skipped** (the nightly-only bare-font matrix and
    `ReplayPerformanceTests.replay_500Envelopes_under5ms`); 17/17 test targets. `LedgerDesignTests`: 173 results.
  - PR-watchOS: **822 tests, 820 passed, 0 failed, 2 skipped** (the same two); 8/8 test targets.
    `LedgerDesignTests`: 138.
  - Step 2: the lint fixture scripts (55/55, 39/39, 44/44, `lint-rules.test.sh`), F32's Xcode-pin checks and
    `coverage-gate.test.sh` (10 cases) pass; package graph unchanged.
  - Step 5, F01's coverage gate: **LedgerDesign 96.20 % (887 / 922)**, threshold 60 %; overall 98.01 %.

### How to verify by hand

- Open the 44 PNGs above (GitHub's image view, or Finder's Quick Look); compare
  `setRow_…dark-large` with the v2 prototype's "Active workout" set rows, `hairlineList_…dark-large` with
  Today's "RECENT", `primaryButton_…dark-large` with "Start workout", `restRing_…dark-large` with the rest card.
- Xcode canvas: `LedgerKit/Sources/LedgerDesign/Components/Components+Previews.swift` has one preview per
  component; use the canvas's Dynamic Type and colour-scheme variants, and Bold Text in Canvas Device Settings.
- VoiceOver (device or simulator, once a screen uses them): a set row reads "2, 185, 5, selected, button" then
  its check label; a stepper is "5 lb, adjustable" and swipe up / down steps it; eyebrows appear under the
  rotor's Headings.
- `ComponentAccessibilityTests` prints each element (label, traits, frame) in a failure message, so a failing
  target shows its actual size.

### Slice 2 — fix round 1

Against the adversarial round (`4543e13`, test-findings "# Slice 2 — round 1", S2-1 to S2-5) and the orchestrator's
decisions. The five red tests pass. One of the tester's files is edited, for S2-4 only (below).

| # | Decision | Change | Tests |
|---|---|---|---|
| S2-1 | Announce state distinctly; don't reuse `.isSelected` | The row element no longer carries `.isSelected`. Its value says the state: "Current set" (active), "Done" (logged), none (pending). The check keeps `.isSelected` when done, as the tester's test asserts, and adds the value "Done". So "selected" now means one thing, logged, and each state is spoken in words. The two strings go through `String(localized:bundle: .module)` (English keys; LedgerDesign has no string catalog yet, so they read in English until one lands) | `setRow_doneRow_isDistinguishableFromPending`, `setRow_doneCheck_saysDoneInWords` (tester's, unchanged, pass); `SetRowAccessibilityTests.setRow_state_isSpokenInWords` (3 states) |
| S2-2 | Steppers expose a value, and increment and decrement change it | `SetRowSteppers(weightStep:repStep:weight:reps:onWeight:onReps:)`: `weight` / `reps` are the current values in the row's units ("185 pounds", "5 reps"), each stepper's `accessibilityValue`. Both are optional, so the tester's call still compiles; without them the value is the step. The component stays stateless: the caller's new value is what VoiceOver announces after a swipe | `steppers_adjustable_haveAValue` (tester's, passes); `setRowSteppers_value_isTheCurrentQuantity`; `setRowSteppers_adjust_changesTheAnnouncedValue` (a `@State` harness: increment, 185 → 190 pounds; two decrements, 5 → 3 reps, read back through the tree) |
| S2-3 | A combined spoken label a caller can override without renaming the check | The row element is the one a feature relabels from outside: `SetRow(…).accessibilityLabel("Set 2, 185 pounds, 5 reps")` names the row, and its state value still follows ("…, Done"). The check stays its own button with `checkLabel`. A probe on iOS 27 compared eight structures: an outer label and value reach every element inside a view, including one that sets its own label, through overlays, `.ignore` elements, a representation and `accessibilityLabel(content:)`. The one boundary that stops them is `.accessibilityElement(children: .contain)` on the check, which stays a button with its own label. That modifier is the change. Without an outer label the row reads its strings ("2, 185, 5"), since the component knows neither units nor words | `setRow_outerLabel_relabelsTheRowOnly` (tester's, passes); `setRow_outerLabel_namesTheRowOnly` (label, value "Done" on both, check label kept) |
| S2-4 | Smallest change that brings the done disc to ≥ 3:1 on every background, both schemes, Increase Contrast | The done disc fills with `accentText` instead of `accent`. In dark the two are the same colour, so nothing changes there; on paper the disc is `#B2390E`. One token swap; no token value changes | `nonText_meetsThreeToOne` (tester's; pairs edited, see below) |
| S2-5 | Targeted snapshots: pressed, Increase Contrast for components with a contrast change, one light AX5 SetRow | A seam for the pressed look: `LedgerPressStyle` draws through a small `PressedLook` view, which also reads an internal `ledgerDrawsPressed` environment value that only previews and tests set. A `ButtonStyleConfiguration` cannot be made outside a button. Three tests, five images: every component pressed (light and dark), every component with Increase Contrast (light and dark; every slice-2 component uses a token that steps up, so the one all-components sheet covers them), and `SetRowGallery` light at AX5 | `ComponentSheetSnapshotTests.allComponents_pressed_matchesReference`, `…_increasedContrast_…`, `setRow_lightAccessibility5_matchesReference` |

S2-4, before and after (WCAG 2.x; Increase Contrast leaves the accent family alone, so it gives the same values):

| Done check, light | Before (`accent #FF5B22`) | After (`accentText #B2390E`) |
|---|---|---|
| Disc on paper (`ground`) | **2.65** | **5.14** |
| Disc on card (`surface`) | 3.10 | 6.03 |
| White tick on the disc | 3.10 | 6.03 |
| Dark (disc on ground / sheet, tick) | 6.34 / 5.98, 3.10 | unchanged |

**Edit to a tester's test (S2-4).** `ComponentContrastAdversarialTests.ComponentColorPair.nonText` named the disc's
colour, `LedgerColor.accent`, in two pairs ("done disc" on each ground, and "done tick" on the disc). The fix changes
that colour, so both pairs now name `accentText`, with a comment citing S2-4. The 3:1 minimum, the grounds, both schemes
and Increase Contrast are unchanged. No other tester test was touched.

Other changes this round:
- SwiftFormat's `environmentEntry` rule rewrote the hand-written environment key into `@Entry`. Under this module's
  default MainActor isolation the key that macro generates is main-actor-isolated and cannot conform to `EnvironmentKey`
  (build error). The fix, typechecked first on its own, is `nonisolated extension EnvironmentValues { @Entry var … }`:
  no suppression, and the formatter is satisfied.
- `LedgerSnapshotTesting`: `withLiveAccessibilityElements(_:_:)` hands a test a reader that lays the view out again, so
  a state change made through an element (an increment) is visible in the next read without waiting. The
  existing `withAccessibilityElements` is built on it.
- My SetRow and stepper accessibility tests moved to `SetRowAccessibilityTests.swift`, because
  `ComponentAccessibilityTests` would have passed SwiftLint's type-length limit. The old `.isSelected`-on-active assertion
  became the S2-1 test.

**References.** `scripts/check.sh --record-snapshots` through the lock (`scratchpad/f06s2-fix1-record.log`); the only
failures were the recordings. **3 changed:** `setRow_appearance_matchesReference-_.light-{large,xLarge,accessibility3}.png`,
compared with `HEAD` pixel by pixel, differ only inside the done disc (for example x 339–369, y 94–124 at large).
The disc turns `#B2390E`, and nothing else moves. The dark SetRow references, both sheets and every other reference came
back byte-identical. **5 new**, each opened:
- `allComponents_pressed_matchesReference-_.pressed-{light,dark}-large.png`: every button at 0.6 (the CTAs, pills, icon
  buttons, tappable rows, the set rows' row and check, the steppers). Eyebrows, static rows and rings are unchanged. Dark
  is `#0B0B0D`.
- `allComponents_increasedContrast_matchesReference-_.increasedContrast-{light,dark}-large.png`: rules, pill outlines,
  ring tracks, check rings and the disabled CTA's fill step up (.20 / .30), muted text to .74, and the grounds and the
  orange do not change.
- `setRow_lightAccessibility5_matchesReference.light-accessibility5.png`: nothing cut; the steppers stack; "102.5" shrinks
  beside a full-size "12".

`__Snapshots__` is still about 2 MB.

**Size.** Product `LedgerDesign/Components/`: **700 code lines** (was 650, +50: SetRow +24, of which ~10 are the
localised state strings; SetRowSteppers +8; ControlStyle +11 for the pressed seam; previews +7), measured as before
(non-blank, non-comment lines). Test-only: the helper +9 (91 → 100), tests +99, with the moved SetRow tests counted once.

**Gate.** Full `scripts/check.sh` through the lock (`scratchpad/f06s2-fix1-check.log`, 286 s after a 153 s wait for the
lock): **green**.
- PR-iOS: **899 tests, 897 passed, 0 failed, 2 skipped**; 17/17 targets; `LedgerDesignTests` 206.
- PR-watchOS: **827, 825 passed, 0 failed, 2 skipped**; 8/8; `LedgerDesignTests` 143.
- The two skips per plan are the nightly-only tests.
- Coverage gate: LedgerDesign **96.39 % (936 / 971)**, overall 98.05 %.

### Slice 2 — fix round 2

Against the close-out round (`8da388a`: test-findings "# Slice 2 — round 2", S2-6 and S2-7) and the slice-2 review
(R2-S1 to R2-S3, R2-N1 to R2-N11), under the orchestrator's decisions. The aim was to fix the class, not the instances:
pin the intended VoiceOver tree once, and make any structure change fail.

**Decision 1: one intended VoiceOver tree for SetRow (S2-6 and the class).**
- **What was wrong.** Fix round 1 stopped an outer label with `.accessibilityElement(children: .contain)` on the check.
  My round-1 probe showed that an outer `View.accessibilityLabel` reaches every element and every `.contain` container
  inside a view, whatever the structure: overlays, `.ignore`, a representation and `accessibilityLabel(content:)`. So a
  boundary made of a container can only ever relabel that container, which is S2-6.
- **Fix.** No container at all. `SetRow` owns its row summary. It has its own `accessibilityLabel(_:) -> SetRow`, the
  pattern SwiftUI uses for `Text`'s modifiers (`Text.bold() -> Text`), which replaces the row summary and nothing else.
  The tester's calls `AccessibilityCases.setRow(…).accessibilityLabel(spoken)` resolve to it unchanged, because a
  concrete type's method wins over the protocol extension's.
- **The tree is exactly two stops:**
  - the row summary: label "2, 185, 5", or the feature's "Set 2, 185 pounds, 5 reps"; value "Pending", "Current set" or
    "Done";
  - the check, a button of its own: label `checkLabel` ("Log set 2", or "Undo set 2" once logged), with the value
    "Done" and `.isSelected` when logged.
- **Limit (documented on the method).** The override must be applied to the `SetRow` itself. After another modifier,
  SwiftUI's own modifier applies and reaches both elements.
- "Pending" is new: the decision lists it among the row's states. It is the third `String(localized:bundle: .module)`
  word (architecture §11 notes the exception, R2-N5).

**`AccessibilityTreeTests` (new, one table-driven test).**
- `component_accessibilityTree_isExactlyTheTable` runs **37 cases**: every slice-2 component in every state it offers.
  - PrimaryButton: with and without an icon, disabled, pressed.
  - PillButton: outline, filled (selected), ghost, filled and pressed.
  - IconPillButton: normal and pressed.
  - Eyebrow: both tints.
  - Decorative icon and rule: no stops.
  - SetRowHeader.
  - HairlineRow: title; detail; text accessory; button accessory; action and chevron; action and pressed.
  - HairlineList.
  - SetRow: pending, active, done, done and named, pending and pressed, drop set.
  - Steppers: normal, pressed, stacked at AX3.
  - The whole SetRow gallery, in order, at large and at AX3.
  - RestRing: full, half, empty, named.
- **What it asserts, exactly:** element count, order, label, value, traits (raw), and the containers between each element
  and the hosting view. My helper flattens containers, so the test walks `accessibilityContainer` itself.
- **The tables are literals.** Every case expects no container.
- **Mutation check.** I put `.contain` back on the check for one run: all 8 SetRow cases failed, and the report shows
  `… in [""]`, an unlabelled container. Then I reverted it.
- **One case differed from my first table, and the component was right.** An action-less `HairlineRow` with a button
  accessory is one element, "Dumbbell Bench Press, Use", with the button trait, and activating it fires the accessory
  (the tester's `hairlineRow_buttonAccessory_isReachable` holds). It is one stop that names what "Use" applies to, so the
  table pins it, and `HairlineRow`'s doc now says so. It had claimed the button stays its own control.

**Decision 2: S2-7 = R2-S3.**
- **Change.** `SetRowSteppers(weightStep:repStep:weight:reps:onWeight:onReps:)` now requires `weight` and `reps`. The
  fallback that announced the step as the value is deleted.
- **Call sites in the tester's files, updated by decision:**
  - `ComponentAccessibilityAdversarialTests.swift`: two calls, which now pass "185 pounds" / "5 reps";
  - `ComponentLayoutAdversarialTests.swift`: one call, which now passes "82.5 kilograms" / "12 reps".
- The API changed by decision, and no assertion in those tests changed. The tester accepted the
  `steppers_adjustable_haveAValue` edit in advance.
- The rejected test, the second half of my `setRowSteppers_value_isTheCurrentQuantity`, which pinned the step as the
  value, is **removed**. The test now checks only the given values. There is no fallback left to test.

**Decision 3: R2-S1.**
- `SetRowState`, `PillButton.Style`, `Eyebrow.Tint` and `SetRowSteppers.Direction` are `nonisolated`. `LedgerIcon` and
  `RestRingGeometry` already were. These are all of slice 2's value types.
- `ComponentValueTests` (new, `nonisolated`, runs on iOS, watchOS and the host) is the compile-level guard. It holds:
  - a `nonisolated` `Equatable` presentation struct that stores all six types;
  - a `Set` of states;
  - an `actor` that compares a state.

  None of it compiles while a conformance is main-actor-isolated.

**Decision 4: R2-S2.** A `.filled` `PillButton` carries `.isSelected`, and the doc says `.filled` means selected. It is
pinned in the tree table ("PillButton, filled (selected)", plus the pressed variant).

**Decision 5: nits.**

| Nit | Done? | Change |
|---|---|---|
| R2-N1 | Yes | `HairlineRow` doc: with an action the accessory must not be interactive. Without one, a button accessory makes the row one stop that activates it (pinned) |
| R2-N2 | Yes | `SetRow` doc: `checkLabel` is the label of what activating it will do. The gallery's done row is "Undo set 1" (not drawn, so no reference changed) |
| R2-N3 | **Skipped** | A device check (Voice Control and Full Keyboard Access on the steppers) belongs in F20's device checklist. That is the orchestrator's brief, and the check can't be run in a simulator test |
| R2-N4 | Yes | `RestRing`'s label: `.lineLimit(1).minimumScaleFactor(0.5)`. Every current label fits, so no reference changed |
| R2-N5 | Yes | architecture §11 names the three VoiceOver state words as the exception to "caller-localised strings" |
| R2-N6 | **Skipped** | Keeping a chevron trailing at accessibility sizes (`ViewThatFits`) changes a layout and three references. It is a design decision the reviewer left to F09's review against Today |
| R2-N7 | Yes | `SetRowHeader` is one element, "#, lb, reps" (pinned) |
| R2-N8 | Yes | `select.label == "2, 185, 5"` exactly |
| R2-N9 | Yes | Criterion 5 measures `RestRingArc(progress: 0.5, geometry: .phone).path(in:)`, the shape the ring strokes |
| R2-N10 | Yes | The accessibility helper calls `Issue.record` when libAccessibility's switch is missing. The C prototypes use `UInt8` (`Boolean`) |
| R2-N11 | Yes | `ComponentSnapshotTests`' header says iOS 27.0. The tester's stale comment in `ComponentAccessibilityAdversarialTests` (row "selected" = active) is updated, comment only |

**Tester files touched this round:** the three stepper call sites (decision 2), one comment (R2-N11), and nothing else.
`SetRowContainerAdversarialTests` (S2-6) passes unchanged in all three states, as do round 1's outer-label and state
tests.

**References.** None changed: every slice-2 and slice-1 reference matched in the gate, so no `--record-snapshots` run was
needed. The gallery's changed `checkLabel`, the trait changes and the bounded ring label draw nothing new.

**Size.**
- Product `LedgerDesign/Components/`: **713 code lines**, up from 700 (+13), measured as before:
  - SetRow +9: the summary method, "Pending", the explicit row label, `.contain` removed;
  - RestRing +2: the label bound;
  - PillButton +1: the selected trait;
  - SetRowHeader +1: the combined element;
  - SetRowSteppers ±0: optional values became required, and the fallback went.
- Test-only: `AccessibilityTreeTests` 247 lines (new), `ComponentValueTests` 31 (new), and the helper +2 (100 → 102).

**Gate.** Full `scripts/check.sh` through the lock (`scratchpad/f06s2-fix2-check.log`, 278 s after a 331 s wait for the
lock): **green**.

| Plan | Tests | Passed | Failed | Skipped | Targets | `LedgerDesignTests` |
|---|---|---|---|---|---|---|
| PR-iOS | 903 | 901 | 0 | 2 | 17/17 | 210 |
| PR-watchOS | 828 | 826 | 0 | 2 | 8/8 | 144 |

The skips are the two nightly-only tests. Coverage gate: LedgerDesign **96.44 % (949 / 984)**, overall 98.06 %.

### Slice 2 — fix round 3 (Pete's re-plan)

Round 3 (`4afdb8f`, test-findings "# Slice 2 — round 3") failed on S2-8 only. The `SetRow.accessibilityLabel(_:) ->
SetRow` overload shadowed SwiftUI's modifier. It protected the check only for a `String` on a bare `SetRow`; a `Text`, a
`LocalizedStringKey`, any modifier before it and any type-erased path compiled silently to SwiftUI's modifier and renamed
the check too. Pete's re-plan, **"Rename & close"**, was done exactly as given, and nothing else changed in product code.

**Product (SetRow only).**
- **The overload is removed.** The row's spoken name is an initializer parameter, **`accessibilitySummary`**, which
  cannot collide with `accessibilityLabel`. It comes in three public forms:
  - `String?`, default `nil`: used as given, like every caller string in this module;
  - `LocalizedStringKey`: looked up in the main bundle, as SwiftUI's own key parameters are;
  - `Text`: for a feature's catalog with its bundle.

  All three delegate to one private initializer that holds a `Text?`. The row element's label is
  `summary ?? Text(verbatim: "2, 185, 5")`. The check keeps `checkLabel`.
- **Every calling form resolves one way.** Compiled and run on the Mac before the change:
  - omitted, `nil`, a literal, an interpolated literal, a `String` and `String(localized:)` take the `String?` form;
  - a `LocalizedStringKey` value takes the key form;
  - a `Text` takes the `Text` form.

  There is no ambiguity error and no silent fallback. A value of any other type fails to compile.
- **Doc on `SetRow`.** Name the row with `accessibilitySummary`, never with SwiftUI's `.accessibilityLabel` (or
  `.accessibilityHint` / `.accessibilityValue`) on a `SetRow`: a modifier from outside reaches every element inside,
  so the check would lose "Log set 2". The lint set is frozen, so there is no rule for it; review enforces it.

**Compile-level guard.** The repo has no "must not compile" convention: no `#if false` blocks, and no compile-failure
harness in `scripts/tests`. So, as the re-plan allows, **the guard is the removed overload**. `SetRow` has no
`accessibilityLabel` of its own, so no spelling can resolve to a row-only relabel by accident. The only way to name the
row is the typed initializer, and every form of that is pinned below.

**Tests.**
- **`AccessibilityTreeTests`.** The case "SetRow, done, named by the feature" is replaced by one case per initializer
  form:
  - a literal;
  - a `String` (`String(localized:)`);
  - a `LocalizedStringKey`;
  - a `Text`;
  - an explicit `nil`, which reads "2, 185, 5".

  Each asserts the exact tree: the row named "Set 2, 185 pounds, 5 reps", value "Done"; the check "Undo set 2", "Done",
  selected; no container. The table now has **41 cases**. The SetRow tables moved to `AccessibilityTreeSetRowTables.swift`,
  because the file had passed SwiftLint's file and type-length limits. The assertions are unchanged.
- **Tester's tests switched to the new API**, as round 3 accepted in advance. No assertion changed.
  - `ComponentAccessibilityAdversarialTests.setRow_outerLabel_relabelsTheRowOnly` and
    `SetRowContainerAdversarialTests.setRow_outerLabel_doesNotLabelTheCheckContainer` both applied
    `.accessibilityLabel(spoken)` to a `SetRow`. With the overload gone, that call is SwiftUI's modifier, which labels
    both elements, so both tests would fail for exactly the reason the doc now forbids it. They now build the row with
    `accessibilitySummary: spoken`, through a `summary: String? = nil` parameter added to the tester's
    `AccessibilityCases.setRow` helper. Each edit carries a comment citing S2-8.
  - The test names still say "outer label". The names are the tester's, so they stay.
- **My `SetRowAccessibilityTests`:** `setRow_outerLabel_namesTheRowOnly` became `setRow_summary_namesTheRowOnly`, with
  the same assertions (row name and "Done"; check "Log set 2" and "Done").

**References.** None changed: every reference matched in the gate, and nothing drawn changed.

**Size.** Product `LedgerDesign/Components/`: **747 code lines**, up from 713 (+34, all in `SetRow.swift`, 140 → 174):
three public initializers and one private one, less the removed method. The rest of the diff is tests and this note.

**Gate.**
- `scripts/check.sh --fast`: green (687 host tests; `LedgerDesignTests` builds on the host).
- **Full `scripts/check.sh` through the lock** (`scratchpad/f06s2-fix3.log`, 275 s): **green**.
  - PR-iOS: 903 tests, **901 passed, 0 failed**, 2 skipped (nightly-only); 17/17 targets.
  - PR-watchOS: 828 tests, **826 passed, 0 failed**, 2 skipped; 8/8 targets.
  - Coverage gate: LedgerDesign **96.46 % (956 / 991)**, overall 98.06 %.

## Slice 3

Branch `feat/F06-slice3` (from `main` 1d80613). Scope: the slice-plan row for slice 3: `WeekStrip`, `StatTile`,
`ProgressSegments`, `SheetChrome`, `EmptyState`, `WatchPrimaryButton`, `WatchRestRing`, `WatchStatBlock` and the
debug-only `DesignGallery`, against criteria 3 (these components), 4 and 9. Slice 2's lessons are built in from the
start:
- one intended VoiceOver tree per component, pinned in `AccessibilityTreeTests`;
- spoken text the component cannot know is an initializer parameter (`accessibilitySummary`, or `label` / `value`),
  never an overload of a SwiftUI modifier;
- stateful elements say their state as a value; the new value types are `nonisolated`;
- AA text and 3:1 state marks in both schemes and with Increase Contrast;
- pressed and Increase Contrast images where they differ;
- value suites `nonisolated`, rendering suites under `RenderingSuites`, no wall-clock asserts.

### Components

Slice 2's conventions carry over: tokens only; the few raw numbers are named, sourced component dimensions; each
component takes strings the caller has already localised; each file ends with an internal `…Gallery` holding every
state, which the previews (`Components+Previews.swift`), the snapshot tests and `DesignGallery` all render.

| Component | Prototype source | Decisions |
|---|---|---|
| `WeekStrip(days:)`, `WeekStrip.Day(weekday:date:mark:accessibilitySummary:)`, `WeekStrip.Mark` | v2 Today week row: 7 flex columns, gap 10; weekday 400 11 px at .34; date 500 14 px (.85 done, orange today, .4 otherwise); 5 px dot (.5 done, orange today, .18 planned, none); the script's `week` mapping (`done` wins over `today`, as in v1) | `Mark` is the prototype's four states: `rest`, `planned`, `today`, `done`. Weekday `caption` / `inkMuted`; date `body` in `ink` (done), `accentText` (today) or `inkMuted`; the dot scales with the caption (5/12 em). **Planned is a 1 pt `inkMuted` ring**, not the .18 dot (1.4:1): every mark reaches 3:1, and done (filled) and planned (ring) differ in shape, not only in shade. Gap `s`. Letters and dates `lineLimit(1)` and `minimumScaleFactor(0.5)`, so seven columns fit at AX5. VoiceOver: one element per day. Its label is the caller's `accessibilitySummary` ("Wednesday, August 19"), because "T" and "19" alone are ambiguous; its value is the mark in words |
| `StatTile(value:unit:caption:delta:accessibilitySummary:)`, `StatTileRow { }` (added) | v2 Today ("3/4 sessions this week", "41.2k lb moved · +8%"): 700 34 wdth 88 tabular, unit 300 19 at .32, caption 300 12.5 at .42, orange delta; Exercise history ("218 1RM est", "195×5 best set") | Value `numeralXL`. The unit is a `bodyLight` / `inkMuted` run inside the value's `Text` (an `AttributedString`): one baseline, and the numerals' line box alone sets the height, so a tile with a unit puts its caption where its neighbours do (the first recording, with two `Text`s in an `HStack`, put "best set" ~10 px below "1RM est"). No 300 ~19 pt role exists, so the unit is 13.5 pt (slice 2's "no new roles"). Caption `label` / `inkMuted`; the delta appended as " · +8%" in `accentText` (the iOS 26 SDK deprecates `Text + Text`). The value line shrinks (≥ 0.5) rather than breaks. `StatTileRow` lays tiles side by side (gap `xl`) and **stacks them at accessibility sizes**: the first AX3 recording broke "sessi / ons" inside the word in a three-tile row (HIG, Typography: reduce the columns as text grows). One element: `accessibilitySummary`, else "3/4, sessions this week" |
| `ProgressSegments(_:label:value:)`, `ProgressSegment(length:state:)` | v2 Active workout: flex row, gap 3, 2 px bars, flex = the exercise's set count; .5 done, orange current, .12 upcoming (`progressBars`) | `widths(of:in:)` (tested): the total less the gaps, shared by length; a zero or negative length draws nothing. Done `inkMuted`, current `accentText`, upcoming `hairlineStrong`. The bar draws no text, so `label` and `value` are **required** ("Workout progress", "Exercise 2 of 5"); they are its only VoiceOver stop |
| `SheetChrome(_:cancel:onCancel:content:)` | v2 swap sheet: `#131316`, top border 1 px .10, radius 28 28 0 0, padding 24; title 600 21 wdth 98; "Cancel" 400 13 at .4 | Title `subheading` / `ink`, a heading; cancel a ghost `PillButton` (≥ 44 pt, `inkMuted`); content under them, gap `s`. Surface in an `UnevenRoundedRectangle` (sheet radius, circular); the top rule drawn as CSS draws `border-top` on a rounded box, a `hairline` stroke masked to the corners' height. It also sets `presentationBackground(surface)` and `presentationCornerRadius(sheet)`, which apply when it is a `.sheet`'s content. **At accessibility sizes the cancel moves under the title**: the first AX5 recording broke "exercis / e". Padding `xl` / `l` (the 44 pt cancel target adds ~10 pt above the title) |
| `EmptyState(_:body:)`, `EmptyState(_:body:actionTitle:action:)` | none in v2; v1's "No session today" card (800 24 title, 400 14/1.5 body at .55, outlined "Edit this week"), "Nothing matches that filter." + "Clear filters", "Nothing logged yet…" | Set in v2's type and alignment: title `subheading` (a heading), body `bodyLight` / `inkMuted`, an optional outlined `PillButton`. The action is secondary on purpose: the screen's one orange stays with its primary action. Leading-aligned like the rest of v2; vertical padding `xl` |
| `WatchPrimaryButton(_:action:)` | LedgerWatch "Start", "Done set", "Skip", "Save workout": `#FF5B22` pill, full width, 600–700 21 px, padding 19 px (≈ 39 pt tall) | `watchButton` (700 14) in `watchInk` on `accent` (3.1:1, bold: Pete's decision 7). **At least 44 pt tall**, the HIG's default watchOS control size (Accessibility › Mobility: default 44 × 44 pt, minimum 28 × 28), rather than the prototype's ≈ 39; padding `m` / `l`. Long titles wrap. Pressed: `LedgerPressStyle`'s 0.6. Disabled: `watchHairline` fill, `watchInkMuted` label, like `PrimaryButton` |
| `WatchRestRing(progress:label:accessibilitySummary:)`, `RestRingGeometry.watch` | LedgerWatch rest timer: `viewBox 0 0 200 200`, r 88, stroke 9, track .13, orange round-cap arc, `stroke-dasharray` 553, drawn at 196 px; countdown 700 52 wdth 92 tabular | Reuses slice 2's `RestRingArc` and geometry. `.watch` is the SVG's 200 / 88 / 9 scaled to 196 px ÷ 1.5 = 130.7 pt (`scaled(toDiameter:)`). Track `watchTrack`, arc `accent`, label `watchCountdown` / `watchInk`. The ring scales with the label's text size (118.7 pt at 42 mm's `.large`, 130.7 at 46 / 49 mm, 149.3 at AX3); the label is bounded to the track's inner diameter and shrinks, never below 11 pt. One element, `.updatesFrequently`; label `accessibilitySummary` ("1 minute 15 seconds left") or the countdown |
| `WatchStatBlock(_:caption:isHighlighted:accessibilitySummary:)` | LedgerWatch summary: value 700 30 px wdth 92 tabular, caption 600 17 px .07 em uppercase at .40, 6 px apart; "NEW PR" orange when above 0 | Value `watchStat` in `watchInk`, or `accent` when highlighted; caption `watchCaption` / `watchInkMuted` (.46, the lowest watch ink at AA); gap `xs`. The value shrinks rather than truncates, never below 11 pt (`LedgerFont.shrinkLimit`); the caption wraps. One element: `accessibilitySummary`, else "12/15, Sets" |
| `DesignGallery` (Debug only) and `Gallery/TokenPages.swift` | criterion 9; F07's debug menu; slice 1's test specimens | A `ScrollView` of 22 sections, each under its name as a heading. First the token pages: `LedgerColor` (every colour as a named swatch; phone on the ground, watch on black), `LedgerFont` (every role, named, with a sample), `LedgerSpacing` / `LedgerRadius` / `LedgerHairline` (names and points), `LedgerMotion` ("Play" runs `snappy` and `buzz`; Reduce Motion respected), `LedgerIcon` (every icon, named). Then every public component's gallery, the watch ones on black at the 46 mm width |
| `LedgerFont.shrinkLimit(_:size:)`, `View.ledgerWatchPage()` (supporting) | criterion 4 | `shrinkLimit` is the `minimumScaleFactor` that lets a line shrink at most to half and never below the role's floor (11 pt for watch roles). `ledgerWatchPage()` is the watch gallery page: a 12 pt inset (prototype 20 px ÷ 1.5) on black |

### Decisions and deviations

1. **Contrast (Pete: AA while keeping the look).** New text uses the lowest AA token where the prototype is fainter:
   weekday (.34), stat unit (.32) and caption (.42), planned and rest dates (.4), sheet cancel (.4) and watch captions
   (.40 → `watchInkMuted` .46). State marks that alone carry a state reach 3:1 (WCAG 1.4.11): week dots and ring,
   done and current segments, the watch arc and pill. **Not required, as for slice 2's ring arc:** the unfilled
   remainder of a progress mark whose state is also in words. That is `ProgressSegments`' upcoming track
   (`hairlineStrong`, 1.3:1; "Exercise 2 of 5" beside it, and in its VoiceOver value) and the watch ring's track (the
   countdown in its middle). In the standard settings the done and current segments are also ≥ 3.6:1 against that
   track; with Increase Contrast the track steps up and the current segment drops to 2.6:1 against it, while staying
   ≥ 5.1:1 against the ground gap beside it. Done and current differ by hue and position, and the value says which is
   current. `Slice3ContrastTests` holds every pair.
2. **VoiceOver words.** `WeekStrip` localises its four mark words in `LedgerDesign` ("Rest day", "Planned", "Today",
   "Done"), as `SetRow` does its three; architecture §11 lists the exception. Everything else spoken comes from the
   caller.
3. **Hit targets.** Phone controls are ≥ 44 pt (`SheetChrome`'s cancel and `EmptyState`'s action are `PillButton`s).
   The watch has one control, `WatchPrimaryButton`: full width and ≥ 44 pt tall, the HIG's default watchOS control size
   (its minimum is 28). `Slice3ComponentAccessibilityTests` measures all three.
4. **Watch text.** Every watch component sets text only in the watch roles (review), and each of those is ≥ 11 pt at
   every watch text size, xSmall to AX3. Where a watch line may shrink, `shrinkLimit` stops it at 11 pt.
   "The largest watch text size" is `.accessibility3`: the HIG's watchOS larger accessibility sizes end at AX3.
5. **Watch sizes.** One watch simulator (Series 12 46 mm) renders all three sizes as fixed layouts, per
   testing-strategy §2.5: 42 mm 187 × 223, 46 mm 208 × 248, 49 mm 205 × 251 pt (`WatchSize`, pinned by the slice-1
   adversarial tests). No other simulator was needed or created. The Ultra 4 (49 mm) is installed, but not booted.
6. **Debug only.** `DesignGallery.swift` and `TokenPages.swift` are wholly `#if DEBUG`. SwiftPM and Xcode define
   `DEBUG` for the Debug configuration only. Checked on the host with `swift build --target LedgerDesign`, which uses
   the same build engine as Xcode here:
   - Debug `LedgerDesign.o` has **361** symbols matching `DesignGallery|GallerySection|TokenPage`;
   - Release has **0**, and its `DesignGallery.o` holds only autolink stubs.

   The test plans build Debug, and `DesignGalleryTests` is `#if DEBUG` too. F07's debug menu must be `#if DEBUG` to
   reference the gallery.
7. **Not built.**
   - An outlined full-width watch button: LedgerWatch's "+30s", "Discard", "End workout" and "Done". F18 can add a
     style.
   - `WatchStatBlock`'s large elapsed variant (52 px): F18 can compose it.
   - `accessibilitySummary` on slice 2's `RestRing`, for parity with `WatchRestRing`: `RestRing` is one element, so
     SwiftUI's own `.accessibilityLabel` from outside names it correctly (pinned), and slice 2 was left untouched.

### Test infrastructure (test-only)

- `LedgerSnapshotTesting/WatchSnapshot.swift`: `WatchAppearance.matrix` (each size at its default text size and at
  AX3) and `assertWatchSnapshot(of:_:)`, which renders through `RenderedImage` at the case's width and the view's own
  height and compares with `.png` at `SnapshotConfig`'s precisions: the watch counterpart of `assertPhoneSnapshot`.
  testing-strategy §2.5 describes it.
- `ComponentSnapshotTests`' `phonePage()` is now internal, so the new suites share it.
- The accessibility helper reads no elements through a hosted SwiftUI `ScrollView`, even at a fixed 874 pt height, so
  the gallery's tree test reads `DesignGalleryContent`, which is the scroll view's only child.

### Criteria → tests

| Criterion | Tests |
|---|---|
| 3 (slice-3 phone components) | `PhoneComponentSnapshotTests.swift`: `WeekStripSnapshotTests`, `StatTileSnapshotTests`, `ProgressSegmentsSnapshotTests`, `SheetChromeSnapshotTests`, `EmptyStateSnapshotTests`, each over `SnapshotAppearance.phoneMatrix` through `assertPhoneSnapshot`. `PhoneComponentSheetSnapshotTests` adds AX5 (dark), Bold Text, pressed (light, dark: the cancel and the action) and Increase Contrast (light, dark) |
| 4 (watch: 42 / 46 / 49 mm, no label < 11 pt, nothing clips) | `WatchComponentSnapshotTests.swift`: the three components over `WatchAppearance.matrix` (6 each), plus Bold Text at 46 mm. `WatchComponentLayoutTests`: at all six cells every gallery keeps its 12 pt inset (no ink reaches an edge); the rest ring with "10:00" fits inside the screen less its inset; at 42 mm AX3 no text is cut (a last character that differs renders differently, with a positive control that shows the probe sees a cut). `WatchTypeFloorTests`: every watch role ≥ 11 pt at every watch text size, xSmall to AX3, and so is the smallest it may shrink to; `shrinkLimit`'s rules. `WatchRestRingGeometryTests`: 196 px ÷ 1.5, r 88 and stroke 9 of 200, circumference 553 in SVG units, half = half from 12 to 6 |
| 9 (`DesignGallery`: every component and token, named) | `DesignGalleryTests`: the section names are exactly the 22 public component names and 6 token types, each once (literal lists); VoiceOver finds every section as a heading, in order, and every token by name (21 colours, 21 type roles, 7 spacing steps, 4 radii, the hairline, 2 motion tokens, 6 icons); the gallery matches its references in light and dark |
| Pete's rules | `AccessibilityTreeTests` + `AccessibilityTreeSlice3Tables.swift`: **24 new literal cases**, every slice-3 component in every state (count, order, label, value, traits, containers), 65 in all. `Slice3ComponentAccessibilityTests`: targets ≥ 44 pt and activation through VoiceOver (cancel, empty-state action, watch button; a disabled watch button is `.notEnabled` and does nothing). `Slice3ContrastTests` (`nonisolated`): 16 text pairs and 10 mark pairs in both schemes with and without Increase Contrast, and the segments against their track. `Slice3ComponentValueTests` (`nonisolated`): the new value types compare and hash off the main actor, in a struct and in an actor. `ProgressSegmentsLayoutTests` (`nonisolated`): the widths |

**Mutation check of the new tables** (one iOS run, `scratchpad/f06s3-mut/mutate.py`, then restored). Eight
non-visual mutations:
- `WeekStrip` loses its value;
- `SheetChrome`'s title loses its heading trait;
- `WatchRestRing` loses `.updatesFrequently`;
- `ProgressSegments` becomes a `.contain` container;
- `StatTile` and `WatchStatBlock` stop combining;
- `EmptyState` gains a `.contain` container;
- `WatchPrimaryButton` gains `.isSelected`.

**23 of the 24 slice-3 cases failed, each on exactly its mutated component's cases.** The 24th is an empty week, which
has nothing to change. No slice-2 case moved.

### New references (57 PNGs, 1×)

Recorded with `scripts/check.sh --record-snapshots` through the simulator lock
(`scratchpad/f06s3-record.log`: iPhone 17 / iOS 27.0 and Apple Watch Series 12 46 mm / watchOS 27.0). The phone
references were then re-recorded after the `StatTile` baseline fix, with `--record-snapshots --ios-only`
(`scratchpad/f06s3-record2.log`). In both runs:
- the only failures were the recordings (0 other failures in either bundle);
- **every slice-1 and slice-2 reference came back byte-identical** (`git status` shows no modified reference).

Every PNG below was opened and compared with its prototype. The 7,000 px gallery was checked in 1,800 px slices, in
both schemes.

- `PhoneComponentSnapshotTests/` (36; all 402 wide):
  - `{weekStrip,statTile,progressSegments,sheetChrome,emptyState}_appearance_matchesReference-_.{light,dark}-{large,xLarge,accessibility3}.png`
    (30). Against v2 Today's week row and stat tiles, the Active-workout progress bar and the swap sheet; v1's empty
    states.
  - `slice3Components_accessibility5_matchesReference.dark-accessibility5.png`: nothing cut or broken inside a word.
    The tiles and the sheet's cancel stack; the week's letters and dates shrink.
  - `slice3Components_boldText_matchesReference.bold-dark-large.png`.
  - `pressableComponents_pressed_matchesReference-_.pressed-{light,dark}-large.png`: the cancel, the swap rows and
    "Clear filters" at 0.6.
  - `slice3Components_increasedContrast_matchesReference-_.increasedContrast-{light,dark}-large.png`: the rules,
    track, planned ring and muted text step up; the orange does not.
- `WatchComponentSnapshotTests/` (19):
  - `{watchPrimaryButton,watchRestRing,watchStatBlock}_watchSize_matchesReference-_.{mm42-large,mm42-accessibility3,mm46-xLarge,mm46-accessibility3,mm49-xLarge,mm49-accessibility3}.png`
    (18; 187 / 208 / 205 wide). Against LedgerWatch's buttons, rest timer and summary. The rings are 118.7 / 130.7 /
    149.3 pt; the half ring runs from 12 to 6 clockwise; AX3 wraps "LB MOVED" and nothing clips.
  - `watchComponents_boldText_matchesReference.bold-mm46-xLarge.png`.
- `DesignGalleryTests/designGallery_scheme_matchesReference-_.{light,dark}-large.png` (2; 402 × 6946): every section
  and token under its name.

`__Snapshots__` is 4.8 MB in all (budget 6 MB): phone 1.3 MB, watch 0.3 MB, gallery 0.9 MB. The gallery pair is the
largest item. If the budget gets tight, it can drop to one scheme.

### Size

Measured as in slice 2, with `scratchpad/codelines.py`: Swift lines that are neither blank nor a whole-line `//`,
`///` or `/* */` comment. New files are counted whole; for edited files, the added code lines of the diff.

| | Code lines |
|---|---|
| **Product (`LedgerDesign`)** | **743** |
| — the 8 components (`Components/*.swift`, new) | 498 |
| — of which their `…Gallery` views (reused by the tests and `DesignGallery`) | 112 |
| — `Gallery/DesignGallery.swift` 71 + `Gallery/TokenPages.swift` 130 (Debug only) | 201 |
| — added to slice-2 files: `RestRing` +5 (`.watch`), `ControlStyle` +10 (`shrinkLimit`, `ledgerWatchPage`), `Components+Previews` +29 | 44 |
| Test-only: `LedgerSnapshotTesting/WatchSnapshot.swift` | 43 |
| Tests: 8 new files 682; edits to `ComponentValueTests` +28, `RestRingGeometryTests` +26, `AccessibilityTreeTests` +2, `ComponentSnapshotTests` +1 | 739 |

Over the 500-line target and under the ~1,000 split line (standards §10). The split considered was 3a, the phone
components and the gallery (~590), then 3b, the watch components (~155). It was not taken: the gallery shows the
watch components, so 3a would have to ship a gallery missing three components and 3b would reopen it, and neither
half is near 1,000. The components without their galleries are ~390 lines, inside the plan's 400–450. The rest is the
debug-only gallery (201), which the slice plan puts here, and the previews. Nothing was compressed.

### Gate

- `scripts/check.sh --fast`: green (687 host tests; `LedgerDesignTests` builds on the host). Run again after the last
  code change: green.
- **Full `scripts/check.sh` through the lock** (`scratchpad/f06s3-check.log`; 267 s, no wait for the lock: lint 43 s,
  iOS 114 s, watchOS 84 s): **green**.

  | Plan | Tests | Passed | Failed | Skipped | Targets | `LedgerDesignTests` |
  |---|---|---|---|---|---|---|
  | PR-iOS | 931 | 929 | 0 | 2 | 17/17 | 237 passed, 1 skipped |
  | PR-watchOS | 845 | 843 | 0 | 2 | 8/8 | 160 passed, 1 skipped |

  The skips are the two nightly-only tests. Step 2 (the lint fixture scripts, the package graph and pins, every
  `scripts/tests/*.test.sh`) passed. Coverage gate: **LedgerDesign 97.10 % (1915 / 1972)**, threshold 60 %; overall
  97.98 %.
- Earlier iterations, all through the lock: `LedgerDesignTests` alone on iOS and on watchOS
  (`scratchpad/f06s3-iter1.log`), then the mutation run (`scratchpad/f06s3-ios2.log`).

### How to verify by hand

- **References.** Open the 57 PNGs above (GitHub's image view, or Quick Look) beside the prototypes:
  - `weekStrip_…dark-large` and `statTile_…dark-large` with v2 Today;
  - `progressSegments_…dark-large` with Active workout's header;
  - `sheetChrome_…dark-large` with the swap sheet;
  - `watchRestRing_…mm46-xLarge` and `watchStatBlock_…mm46-xLarge` with LedgerWatch's rest timer and summary.
- **Xcode canvas.** `Components+Previews.swift` has one preview per new component and one for `DesignGallery`. Use
  the canvas's colour-scheme and Dynamic Type variants, and Bold Text in Canvas Device Settings. Preview a watch
  component on a watch run destination to see it at the watch's text sizes.
- **VoiceOver, once F07's debug menu opens `DesignGallery`** (simulator or device):
  - the rotor's Headings jump section to section;
  - a week day reads "Wednesday, August 19, Today";
  - a progress bar reads "Workout progress, Exercise 3 of 5";
  - the sheet reads "Swap exercise, heading", then "Cancel, button";
  - the watch ring updates frequently.
- **Release excludes the gallery.** Build the app in Release, then run
  `nm <app binary> | grep -c DesignGallery`; expect 0. Or on the host:
  `swift build -c release --package-path LedgerKit --target LedgerDesign`, then run `nm` on its `LedgerDesign.o`.
- **Device (F20's checklist).** Present a `SheetChrome` in a `.sheet` and check that the system sheet takes the
  surface and the 28 pt corners (`presentationBackground` / `presentationCornerRadius` cannot be snapshot-tested).
