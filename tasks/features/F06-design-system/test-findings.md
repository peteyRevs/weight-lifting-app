# F06 slice 1 — adversarial test findings

Scope: commits `04cf7ee` (snapshot/lint tooling) and `8e3a273` (tokens + Archivo), branch
`feat/F06-design-system`. Written from the brief, `docs/product-spec.md` §4.1 and §8.1–§8.8, decisions
#1/#17, architecture §11/§17, testing-strategy §2.5/§6, the four prototypes, and the HIG. The
implementation was inspected only through its public declarations and doc comments.

## What was written

| File | Attacks |
|---|---|
| `LedgerKit/Tests/LedgerDesignTests/Adversarial/AdversarialDesignSupport.swift` | Helpers: sRGB/WCAG maths, SwiftUI colour resolution, pixel probes, Archivo loaded straight from the font file, synthetic PNGs |
| `…/Adversarial/LedgerColorAdversarialTests.swift` | Each phone token's hex and alpha in light and dark via `Color.resolve`, via `UIColor.resolvedColor` (criterion 2), via rendered pixels; watch tokens; watchOS always dark; alpha compositing against the browser |
| `…/Adversarial/ContrastAdversarialTests.swift` | WCAG ratios of every text/background pair the prototypes draw |
| `…/Adversarial/LedgerFontSpecAdversarialTests.swift` | All 20 specced roles: size, wght, wdth, tracking, line height, case, tabular (from the prototype declarations); numeral rule; design axis ranges |
| `…/Adversarial/LedgerFontRenderingAdversarialTests.swift` | Tabular figures (probe sensitivity checked), uppercase, rendered axes vs the font file, Dynamic Type monotonicity for every role, bare `font(_:)` scaling, Bold Text |
| `…/Adversarial/LedgerFontMetricsAdversarialTests.swift` | Rendered letter-spacing (em) and baseline-to-baseline line height vs CSS |
| `…/Adversarial/WatchTypeFloorAdversarialTests.swift` | 11 pt floor at every text size ≤ xLarge and at the 41/42/45/46 mm defaults; exact px ÷ 1.5 at 46 mm; `@ScaledMetric` base size per platform; explicit-size entry point |
| `…/Adversarial/ArchivoFontAdversarialTests.swift` | Registration idempotent, concurrent, after an external (UIAppFonts-style) registration; PostScript name not substituted; resolved file = bundled bytes; `wght`/`wdth` axes present and rendering on iOS and watchOS; clamping; pixel equality with the font file |
| `…/Adversarial/LedgerMotionAdversarialTests.swift` | Buzz keyframes, CSS `ease` per interval, 3 × 0.38 s, Reduce Motion (no translation, pulse per cycle), modifier at rest |
| `…/Adversarial/LayoutTokenAdversarialTests.swift` | Spacing, radius, hairline values and scale properties |
| `…/Adversarial/SnapshotHarnessAdversarialTests.swift` | Render determinism, lossless PNG round trip, readable failure, diff attachment, size mismatch, precision boundary, ΔE threshold, alpha, corrupt reference, criterion-3 matrix |
| `scripts/tests/lint-rules-adversarial.test.sh` | 55 fixtures against `ledger_raw_color/font/spacing/radius`: raw values in features and `Apps/`, legitimate token use, exemptions for `LedgerDesign` and tests. **Not wired into `check.sh`** (it fails today and would stop the gate at step 2) |

## Results

Run on the pinned simulators through the simulator lock.

| Run | Result |
|---|---|
| `scripts/check.sh` via the simulator lock | steps 0–2 green (format, lint incl. these files, package graph, `lint-rules.test.sh`); **step 3 fails**: PR plan on iOS 26.5 ran 519 tests, 512 passed, **7 failed — all adversarial**, every other target green. `set -e` stops the script before step 4 |
| Step 4 run by hand (same `xcodebuild` line as `check.sh`, via the lock) | PR-Watch on watchOS 26.5 ran 507 tests, 501 passed, **6 failed — all adversarial** |
| Adversarial test functions | 62 on iOS, 59 on watchOS (parameterised; several hundred cases). The implementer's LedgerDesign suites stay green on both |
| `lint-rules-adversarial.test.sh` (run by hand) | 55 cases, **25 fail** (21 raw values not flagged, 4 false positives) |

Failing tests (left in place):

| # | Test | Severity |
|---|---|---|
| 1 | `LedgerFontRenderingAdversarialTests.bareFont_accessibilitySize_scalesUp` (body, numeralL; iOS + watchOS) | **bug** (brief contract) |
| 2 | `WatchTypeFloorAdversarialTests.smallWatchRole_explicitSmallSize_neverBelowElevenPoints` (watchTitle, watchLabel, watchCaption; iOS + watchOS) | minor bug / design question |
| 3 | `SnapshotHarnessAdversarialTests.pngDiffing_exactlyAtPrecision_passes` (iOS + watchOS) | minor bug (harness) |
| 4 | `SnapshotHarnessAdversarialTests.pngDiffing_failure_attachesDifferenceImage` (iOS + watchOS) | minor bug (harness) |
| 5 | `ContrastAdversarialTests.phonePair_meetsAA` — onAccent on accent (light, dark) | design question (fails brief NFR) |
| 6 | `ContrastAdversarialTests.phonePair_meetsAA` — accentText on ground (light) | design question (fails brief NFR) |
| 7 | `ContrastAdversarialTests.phonePair_meetsAA` — inkMuted on ground/surface (light, dark) | design question (fails brief NFR / decisions) |
| 8 | `ContrastAdversarialTests.watchPair_meetsAA` — watchInkMuted, watch CTA | design question |
| 9 | `LedgerFontRenderingAdversarialTests.role_boldTextSetting_addsWeight` (body, label, numeralL; iOS + watchOS) | design question (HIG accessibility) |
| 10 | `scripts/tests/lint-rules-adversarial.test.sh` | bug (14 cases) + design questions (11 cases) |

---

## 1. `LedgerFont.font(_:)` does not follow Dynamic Type — bug (brief contract)

- **Test:** `LedgerFontRenderingAdversarialTests.bareFont_accessibilitySize_scalesUp`.
- **Attacks:** the brief's public surface, `public static func font(_ role: Role) -> Font // Dynamic Type–scaled`,
  and engineering-standards §7 ("Dynamic Type supported up to accessibility sizes").
- **Repro:** `Text("H").font(LedgerFont.font(.body))` rendered at 2× with `.dynamicTypeSize(.large)` and
  `.accessibility3` → cap height 21 px in both (numeralL: 41 px in both), on iOS and watchOS. Expected: larger
  at AX3 (for `.body`'s own curve, subheadline 15 → 36 pt, ≈ 2.4×).
- **Observed:** the doc comment now says "at its design size, before Dynamic Type"; architecture §11 was edited in
  the same commit to route scaling through `.ledgerFont`. Nothing stops a feature from writing
  `.font(LedgerFont.font(.body))` — the lint fixture N05 confirms it passes `ledger_raw_font` — and getting text
  that ignores the user's text size. Either restore the brief's contract, or record the deviation in the brief and
  make the non-scaling entry point hard to reach from features (e.g. `package`/internal, or a lint rule).

## 2. The explicit-size entry point bypasses the 11 pt watch floor — minor bug / design question

- **Test:** `WatchTypeFloorAdversarialTests.smallWatchRole_explicitSmallSize_neverBelowElevenPoints`.
- **Attacks:** criterion 4 and `LedgerTypeSpec.minimumSize` ("The size never scales below this (watch roles:
  11 pt, F06 criterion 4)"), through `LedgerFont.font(_:size:)`, documented as "an explicit, already *scaled*
  point size".
- **Repro:** `Text("H").font(LedgerFont.font(.watchLabel, size: 9))` → cap height 37 px at 6× (≈ 9 pt); an 11 pt
  Archivo "H" from the font file is 45 px. Same for watchTitle and watchCaption.
- **Why it matters:** `.ledgerFont` honours the floor (verified at every size and watch case); the second public
  path doesn't, so a watch component that scales its own size (e.g. with `@ScaledMetric` for layout) can fall
  below 11 pt. Clamp in `font(_:size:)` too, or state that callers must.

## 3. Snapshot comparator rejects a match of exactly `precision` — minor bug (harness)

- **Test:** `SnapshotHarnessAdversarialTests.pngDiffing_exactlyAtPrecision_passes`.
- **Repro:** reference = 1000×1 grey strip; actual = the same with 5 pixels red. 995/1000 = 99.5 % match, which
  meets `precision: 0.995`. `Snapshotting<CGImage, Data>.png.diffing.diffV2` fails with
  "5 pixels differ by more than ΔE 1.9999980926513672: 0.995 match, 0.995 required".
- **Cause (from the message):** the Double match fraction is compared with `Double(Float(0.995))` =
  0.99500000477. Compare mismatched-pixel counts against an integer threshold, or do the comparison in `Float`.
  The ΔE in the message is Float noise too (2.0 prints as 1.9999980926513672).

## 4. `.png` failures attach no difference image — minor bug (harness)

- **Test:** `SnapshotHarnessAdversarialTests.pngDiffing_failure_attachesDifferenceImage`.
- **Repro:** any failing `.png` comparison (100×1 strip, 50 pixels changed) → attachments are exactly
  `actual.png` and `reference.png`.
- **Expected:** testing-strategy §2.5 "Failures attach diff images to the xcresult". `.png` is the only strategy
  on watchOS, so every watch snapshot failure is reviewed by eyeballing two images. Add a difference image
  (e.g. mismatched pixels in magenta over a dimmed reference).

## 5–8. Contrast below WCAG AA — design questions (the spec's values fail the brief's NFR)

Brief, non-functional: "informational text at ≥ 4.5:1 where it carries meaning; the .32 alpha is decorative
only". Decisions (additional scoping calls): "contrast fixes for the 35–45 % alpha text are launch
requirements". Ratios are computed from the resolved tokens, alpha composited in gamma sRGB as the prototype's
browser does (`inkMuted_renderedOverGround_matchesBrowserComposite` confirms SwiftUI paints the same composite).
None of these texts is WCAG "large" (≥ 18.66 px bold / 24 px regular), so 4.5:1 applies.

| Pair | Where the prototypes use it | Ratio | Needs |
|---|---|---|---|
| onAccent `#FFF` on accent `#FF5B22` (both schemes, watch) | every primary CTA label, 600 16 px; watch CTA | **3.10** | AA fails; only the 3:1 large-text bar passes. `#0B0B0D` on orange is 6.34, `#16150F` 5.90 |
| accentText `#C63F0F` on paper `#EFEDE6` (light) | "UP NEXT"-style eyebrows (10 px), PR line, active chip text | **4.35** (5.10 on white card) | §8.1 introduces it "for contrast"; 3 % darker, `#C03D0F`, gives 4.57 |
| inkMuted `.45` on ground / surface (dark) | dates, "Week 3 of 8 · ~52 min", "sessions this week", "1RM est", stat captions | **4.15 / 4.17** | alpha ≥ .48 |
| inkMuted `.45` on paper / card (light) | same | **2.88 / 2.97** | alpha ≥ .60 |
| watchInkMuted white `.4` on `#000` | ELAPSED, SETS, LB MOVED, NEW PR captions (11 pt) | **3.66** | alpha ≥ .46 |

The token doc comment classes `inkMuted` as "supplementary" (so exempt); the prototype uses .38–.45 for exactly
the metadata decision list calls out. These tests stay red until Pete decides per pair (change the value, accept
and document the exception, or add an Increase Contrast variant).

Passing pairs, for the record: ink 15.61 / 18.29 (light ground / surface), 17.58 / 16.58 (dark);
inkSecondary 6.74 / 7.30 (light), 9.21 / 8.91 (dark); accentText dark 6.34 / 5.98; watchInk 21.0;
watchInkSecondary 6.27; accent on `#000` 6.77. Decorative only (not asserted): inkFaint 2.04 light /
2.64 dark, inkDim 1.84 / 2.28.

## 9. Bold Text is ignored by every role — design question (accessibility)

- **Test:** `LedgerFontRenderingAdversarialTests.role_boldTextSetting_addsWeight`.
- **Repro:** `Text("Upper A 185").ledgerFont(.body)` with `.environment(\.legibilityWeight, .bold)` lays down the
  same ink as `.regular` (body 1215 → 1215 px at 2× on iOS, 999 → 999 on watchOS; numeralL 4645 → 4645).
- **Expected:** HIG Typography, "Implement accessibility features for custom fonts… respond when people turn on
  accessibility features, such as Bold Text". `Font(CTFont)` opts out of the system's handling. Not in the brief
  or decisions list, hence a design question; the variable `wght` axis makes it cheap (e.g. +100–200 when
  `legibilityWeight == .bold`).

## 10. Design-lint rules: 21 raw values slip through, 4 false positives

`scripts/tests/lint-rules-adversarial.test.sh` builds a throwaway tree with the repo's `.swiftlint.yml`, one
fixture file per case, and runs the pinned SwiftLint once. Exemptions hold: raw values inside
`LedgerKit/Sources/LedgerDesign/` and under `LedgerKit/Tests/` are not flagged; `Apps/` is covered.

**Bugs** — ordinary feature code that defeats the rule's stated purpose:

| Case | Snippet | Rule that should fire |
|---|---|---|
| C02 | `Color(⏎ red: 1, ⏎ green: 0.36, ⏎ blue: 0.13 ⏎)` — how SwiftFormat's `--wraparguments before-first` lays out a long literal | `ledger_raw_color` |
| C03 | `Color.init(red: 1, green: 0.36, blue: 0.13)` | `ledger_raw_color` |
| C05 | `.foregroundStyle(Color(.systemBackground))` | `ledger_raw_color` |
| C06, C07 | `.foregroundStyle(.purple)`, `.tint(.pink)` — the `.modifier(.x)` branch lists 8 colours, the `Color.x` branch 20 | `ledger_raw_color` |
| C08, C09 | `.shadow(color: .black, radius: 4)`, `Rectangle().stroke(.orange)` | `ledger_raw_color` |
| F02 | `.font(.custom("Helvetica", size: 13))` — only `Font.custom(` with the type name is caught | `ledger_raw_font` |
| S03, S04 | `.padding([.top, .bottom], 13)`, `.padding(EdgeInsets(top: 13, …))` | `ledger_raw_spacing` |
| S07, S08 | `LazyVGrid(columns: …, spacing: 13)`, `Grid(horizontalSpacing: 13, …)` | `ledger_raw_spacing` |
| R03 | `UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28)` — the natural way to draw a sheet's top corners | `ledger_raw_radius` |
| N11 (false positive) | `.foregroundStyle(highlightColor(red: true))` — `Color\(` has no word boundary, so any `…Color(red:/white:/hue:` call is flagged | none |

**Design questions:**

| Case | Snippet | Question |
|---|---|---|
| C04, F07 | `Color(UIColor.systemOrange)`, `Font(UIFont.systemFont(ofSize: 12))` | §11 forbids UIKit in features, but no rule enforces it |
| C10 | `Color("BrandOrange")` | Asset-catalogue colours bypass tokens |
| F05, F06 | `.bold()`, `.fontWidth(.condensed)` | `.fontWeight(` is flagged, its siblings aren't |
| S09, S10, R04 | `.safeAreaPadding(13)`, `.padding(.horizontal, CGFloat(13))`, `RoundedRectangle(cornerSize: CGSize(…))` | Wrapped or less common spellings |
| N08 (false positive) | `VStack(spacing: 0)` | No zero token exists, so flush stacks (hairline lists) can't be written in a feature. Add `LedgerSpacing.none` or exempt `0` |
| N09, N10 (false positives) | a comment mentioning `.padding(13)`/`Color(red:`, and a string literal containing `Color(red:` | Add `excluded_match_kinds: [comment, doccomment, string]` |

After the regexes are fixed, add the script to `check.sh` step 2 next to `lint-rules.test.sh`.

---

## Design observations (no failing test)

- **HIG minimum sizes.** The v2 eyebrow is 10 pt; the HIG's iOS minimum is 11 pt. The watch floor is 11 pt;
  the HIG's watchOS minimum is **12 pt** (Typography, "Ensuring legibility"). Both are exactly what the prototypes
  and criterion 4 ask for.
- **".32 is decorative only" is contradicted by the prototype.** v2 draws meaning-carrying text at .32: the
  section eyebrows REMAINING / ALL EXERCISES / ESTIMATED 1RM · 8 WEEKS / SESSION LOG, the search placeholder,
  stepper units "5 LB" / "1 REP", "Skip setup", unit suffixes "/4", "k", "×5". inkFaint is 2.64:1 dark,
  2.04:1 light. Features will need to be told which token to use for those.
- **Brief API deviations, not failures:** `LedgerMotion.buzz: Animation` became
  `buzzKeyframes(reduceMotion:)` + `.ledgerBuzz(trigger:)` (architecture §11 updated); `LedgerFont.Role` has 21
  cases, a superset of the brief's 13.
- **Not testable through the public API:** `FontRegistration`'s missing-resource path (the bundle is fixed at
  build time; no seam to point it elsewhere) and the Reduce Motion branch inside `.ledgerBuzz`
  (`accessibilityReduceMotion` is read-only in `EnvironmentValues`; only `buzzKeyframes(reduceMotion:)` is
  verified).
- **Same font everywhere (verified by hand after the gate build):** `Archivo[wdth,wght].ttf` has MD5
  `3084864834b6b421c5cf0a225c5abab3` in `LedgerKit/Sources/LedgerDesign/Resources/`, `Ledger.app`,
  `Ledger.app/Watch/LedgerWatch.app` and the standalone `LedgerWatch.app`; both apps' `UIAppFonts` entry
  (`LedgerKit_LedgerDesign.bundle/Archivo[wdth,wght].ttf`) resolves to that file. In tests, the font Core Text
  resolves is byte-identical to the bundled file (`registration_resolvedFont_isTheBundledFile`).

## Attacked and held

On both iOS 26.5 and watchOS 26.5: every colour token's hex/alpha (three independent paths on iOS, including
rendered pixels in both schemes); phone tokens resolve dark in either scheme on watchOS; all 20 specced roles'
size/wght/wdth/tracking/line height/case/figures; rendered numeral roles match Archivo read from the font file
at the spec's axes; tabular figures for all seven numeral roles through both entry points; uppercase roles;
letter-spacing in em and CSS line height (including the tighter-than-natural 1.0 and 0.86) as rendered;
`.ledgerFont` grows monotonically across all 12 Dynamic Type sizes with no cap; 11 pt floor at every size up
to xLarge and at the 41/42/45/46 mm defaults; watch roles render at exactly px ÷ 1.5 at the 46 mm default and
watchOS `@ScaledMetric` is unscaled at `.xLarge` (the harness's premise); Archivo registration idempotent,
concurrent-safe and fine after an external registration; `wght` 100–900 and `wdth` 62–125 present and rendering
monotonically on watchOS (the spike), with clamping at both ends; buzz keyframes, CSS `ease` between keyframes,
1.14 s, Reduce Motion never translates and pulses once per cycle; spacing/radius/hairline values; rendering is
pixel-identical across repeated renders and the committed references pass on both platforms.
