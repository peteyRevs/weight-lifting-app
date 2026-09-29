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

---

# Round 2 — after the fix round (`7439e3d`)

Scope: the fix round's new public surface (`scaledSize(_:dynamicTypeSize:)`,
`font(_:dynamicTypeSize:legibilityWeight:)`, `font(_:size:legibilityWeight:)`, `boldTextWeightStep`), the AA
palette and the iOS Increase Contrast ladder, the fixed `.png` comparator, and the rewritten `ledger_raw_*`
regexes. Pete's decisions of 2026-09-27 are treated as requirements: WCAG AA and keep the look (inkMuted .48 dark /
.60 light, watchInkMuted .46, light accentText `#C03D0F`), white on the accent with 700-weight labels (3:1, HIG
"All sizes, Bold"), an Increase Contrast ladder on iOS, Bold Text = +100. Written from the brief, spec §8.1/§8.5,
the v1 prototype, the public declarations and doc comments, and Archivo's own metrics (read from the font file).
`implementation-notes.md` was not read.

## What was written

| File | Attacks |
|---|---|
| `…/Adversarial/LedgerFontSizingAdversarialTests.swift` | `scaledSize` exact at the reference size; follows `@ScaledMetric`'s curve for the role's text style at all 12 sizes; monotonic, uncapped, 11 pt floor; `font(_:size:)` clamps any request below the floor; `font(_:dynamicTypeSize:legibilityWeight:)` draws exactly what `.ledgerFont` draws (21 roles × 12 sizes × regular/bold); nil legibility weight = regular; `.ledgerFont` restyles when the environment changes under the same renderer |
| `…/Adversarial/BoldTextAdversarialTests.swift` | +100 for every role and never past `wght` 900; every role, 700 numerals included, lays down more ink; rendered weight = Archivo from the file at `wght` + 100 (not + 200); the explicit-size path agrees; the accent labels (`button`, `watchButton`) render at 700 without Bold Text |
| `…/Adversarial/IncreaseContrastAdversarialTests.swift` (iOS) | The ladder's own promise (text 7:1, inkFaint 4.5:1) on ground and surface, light and dark; never worse, order kept; grounds/accent/onAccent unchanged; **SwiftUI's environment** (`_colorSchemeContrast`) reaches the ladder through `Color.resolve` and through rendered pixels; §8.1's accentDeep-on-accentTint chip pair |
| `…/Adversarial/SnapshotDiffAdversarialTests.swift` | Precision boundary from both sides at six sizes (integer `floor(0.5 %)`); `difference.png` has the reference's size and marks exactly the pixels beyond ΔE 2 (sub-threshold changes unmarked); a size mismatch attaches a difference image; an undecodable reference still attaches the new image |
| `…/Adversarial/LedgerFontLineBoxAdversarialTests.swift` | Where a lone line sits in its own frame vs CSS half-leading (Archivo ascent .878 / descent .210 from the file); capitals and figures stay inside the frame |
| `scripts/tests/lint-rules-adversarial-round2.test.sh` | 39 fixtures: 11 ordinary raw spellings, 8 design-system escape hatches, 13 must-pass (sanctioned API, tokens, zero, comments, multi-line and raw strings), 7 controls. **Not wired into `check.sh`** (it fails today and would stop the gate at step 2) |

The crashed session's drafts were finished and corrected: `IncreaseContrastAdversarialTests` did not compile
(`high:` label, a 4-tuple lint error); the lint draft listed `LedgerFont.font(.title, size: 32)` and
`Eyebrow(tint: .primary)` as must-pass and `.padding(2 * LedgerSpacing.m)` as a false positive (all three are raw
values; dropped); it also expected `LedgerFont.archivo(size:…)` to be flagged, which contradicts round 1's N12 (the
brief makes `archivo` public; dropped, see 17).

## Results

Run on the pinned simulators through the simulator lock, one lock hold for both platforms.

| Run | Result |
|---|---|
| `scripts/check.sh` | steps 0–2 green (format, lint, `lint-rules.test.sh`, `lint-rules-adversarial.test.sh` 55/55, package graph); **step 3 fails**: PR plan on iOS 26.5 ran 551 tests, 546 passed, **5 failed — all round 2**. `set -e` stops the script before step 4 |
| Step 4 by hand (`check.sh`'s own `xcodebuild` line, same lock hold) | PR-Watch on watchOS 26.5 ran 530 tests, 526 passed, **4 failed — all round 2** (the Increase Contrast suite is iOS-only) |
| `LedgerDesignTests` by origin | implementer 35/35 iOS, 32/32 watchOS; round-1 adversarial **63/63 iOS, 60/60 watchOS**; round-2 adversarial 23 functions on iOS (18 pass), 17 on watchOS (13 pass) |
| `lint-rules-adversarial-round2.test.sh` (by hand) | 39 cases, **23 fail**: 11 raw values not flagged, 3 false positives on the sanctioned API, 8 design questions, 1 false positive (P04) |
| Host `swift test` | compiles and agrees; macOS has no Dynamic Type, so the round-2 growth checks run on iOS/watchOS only |

Failing tests (left in place):

| # | Test | Severity |
|---|---|---|
| 11 | `LedgerFontLineBoxAdversarialTests.singleLine_baseline_matchesCSSHalfLeading` (20 of 21 roles; `label` passes) and `singleLine_capitalInk_staysInsideFrame` (watchNumeral; iOS + watchOS) | **bug** (spec §8.5 fidelity; criterion 4 "nothing clips") |
| 12 | `lint-rules-adversarial-round2.test.sh` P01–P03 | **bug** (false positive on the fix round's own API) |
| 13 | `lint-rules-adversarial-round2.test.sh` B01–B11 | **bug** (11 raw values not flagged) |
| 14 | `IncreaseContrastAdversarialTests.accentText_onAccentSoft_meetsAA` (light, on ground; iOS) | design question (fails brief NFR / Pete's AA decision) |
| 15 | `SnapshotDiffAdversarialTests.precision_boundary_holdsFromBothSides` (402×999; iOS + watchOS) | minor bug (harness) |
| 16 | `SnapshotDiffAdversarialTests.sizeChange_attachesDifferenceImage` (iOS + watchOS) | minor bug (harness) |
| 17 | `lint-rules-adversarial-round2.test.sh` D01, D02, D04–D09, P04 | design questions |

---

## 11. `.ledgerFont` puts a lone line's baseline 1 em below its frame top, whatever the line height — bug

- **Tests:** `LedgerFontLineBoxAdversarialTests.singleLine_baseline_matchesCSSHalfLeading`,
  `singleLine_capitalInk_staysInsideFrame`.
- **Attacks:** spec §8.5's line heights (`64px/0.86`, `30px/1`, `15px/1.2`, `13.5px/1.6`…) as CSS applies them to a
  single line: the line box is `L` em tall and the leading `L − (ascent + descent)` is split evenly above and below,
  so the baseline sits `L/2 + (ascent − descent)/2` em from the top. Archivo's ascent is .878 em and descent .210 em
  (hhea; OS/2 typo metrics are identical with USE_TYPO_METRICS), so the baseline belongs at `L/2 + 0.334` em.
- **Repro:** render `Text("H").ledgerFont(role)` at the reference text size inside a 60 pt margin and compare the
  "H"'s bottom with the text's own frame (`ImageRenderer` of the bare `Text`). For every role the baseline lands at
  **1.000 em** below the frame top; the frame itself is `L` em (round 1's line-pitch tests still hold):

  | Role | size / L | Frame (pt) | Baseline from frame top, pt (em) | CSS, pt (em) | Δ pt |
  |---|---|---|---|---|---|
  | watchNumeral | 42.67 / 0.86 | 37 | **42.5 (0.996) — 5.5 pt below the frame** | 32.6 (0.764) | +9.9 |
  | numeralXL, title | 34, 32 / 1 | 34, 32 | 34, 32 (1.000) | 28.4, 26.7 (0.834) | +5.6, +5.3 |
  | watchCountdown, numeralL, numeralM | 34.67, 30, 24 / 1 | = size | = size (≈ 1.000) | 0.834 em | +5.6, +5.0, +4.0 |
  | watchStat, button, numeralS, watchButton | 20, 16, 15, 14 / 1 | = size | = size (1.000) | 0.834 em | +3.3, +2.7, +2.5, +2.3 |
  | caption, watchLabel, watchCaption, eyebrow | 12, 11.33, 11.33, 10 / 1 | ≈ size | ≈ size (1.000–1.015) | 0.834 em | +2.0, +2.0, +2.0, +1.7 |
  | display, heading, subheading, watchTitle | 38 / 1.06, 27 / 1.08, 21 / 1.1, 13.33 / 1.12 | L × size | 1.000 em | 0.864–0.894 em | +5.2, +3.4, +2.4, +1.6 |
  | body (label passes at +0.8) | 15 / 1.2 | 18 | 15 (1.000) | 14.0 (0.934) | +1.0 |
  | bodyLight | 13.5 / 1.6 | 22 | 13.5 (1.000) | 15.3 (1.134) | −1.8 |

  (iOS 26.5, reference text size; the watchOS simulator and the host give the same numbers. Tolerance 0.03 em + ½ px.)

- **Why it matters:** (1) Fidelity: against the prototype, text sits lower in its box for every line height under
  1.33 — by up to 0.24 em, ~10 pt for the watch weight numeral and ~5 pt for the phone numerals and titles — and
  higher for bodyLight (1.6), so layouts built from the prototype's gaps won't match it. (2) Overflow:
  `watchNumeral` (0.86) puts its baseline below its own frame, so the digits spill ~0.14 em (≈ 6 pt at 46 mm, more
  at larger text sizes) out of the bottom; at 1.0 the digits sit on the frame's bottom edge and descenders hang
  0.21 em out. Anything stacked under the numeral overlaps it, and a clipping container or a snapshot edge cuts it
  (criterion 4, "nothing clips"). This round's first run hit it: on iOS at AX3–AX5 an 8 pt margin did not keep
  `.ledgerFont(.watchNumeral)`'s digits inside an `ImageRenderer` image, while the bare
  `font(.watchNumeral, dynamicTypeSize:)` stayed inside.
- **Fix direction:** move the glyphs up by `(1 − L/2 − (ascent − descent)/2) × size` inside the frame (0.236 em at
  0.86, 0.166 em at 1.0, −0.134 em at 1.6), e.g. with an offset or alignment guide, or size the frame to the CSS box
  another way; multi-line pitch is already right.

## 12. `ledger_raw_font` flags the sanctioned `LedgerFont.font(.title / .body / .caption, …)` — bug

- **Fixtures:** P01 `Text("x").font(LedgerFont.font(.body, dynamicTypeSize: dynamicTypeSize))`,
  P02 `…font(LedgerFont.font(.title, size: titleSize, legibilityWeight: legibilityWeight))`,
  P03 `…font(LedgerFont.font(.caption, dynamicTypeSize: dynamicTypeSize))` → all three flagged.
- **Cause:** the branch `\.font\(\s*\.(…|title[23]?|…|body|…|caption2?)\b` matches the `.font(.body` inside
  `LedgerFont.font(.body, …`. Architecture §11 (fix round) sends features to exactly this API ("The `Font` entry
  points take the text size explicitly (`LedgerFont.font(_:dynamicTypeSize:)`)"), and three role names collide
  with system text styles. Other roles pass (round 1's N05 uses `.numeralL`). A negative lookbehind
  (`(?<!LedgerFont)\.font\(`) or anchoring the branch to a view modifier fixes it.

## 13. Design-lint rules: 11 more raw spellings slip through — bug

| Case | Snippet | Rule that should fire |
|---|---|---|
| B01 | `let tint: Color = .orange` — the leading-dot branch needs `(`, `[`, `,` or `:` before the dot, not `=` | `ledger_raw_color` |
| B02 | `.foregroundStyle(isDone ? .green : LedgerColor.inkMuted)` — `?` isn't in the class either | `ledger_raw_color` |
| B03 | `.foregroundStyle(custom ?? .red)` | `ledger_raw_color` |
| B04 | `let brand: Color = .init(red: 1, green: 0.36, blue: 0.13)` | `ledger_raw_color` |
| B05 | `.font(isCompact ? .footnote : .body)` — the `.font(` branch needs the style right after the paren | `ledger_raw_font` |
| B06 | `.padding(.init(top: 13, leading: 0, bottom: 0, trailing: 0))` — `EdgeInsets(` is caught, `.init(` isn't | `ledger_raw_spacing` |
| B07 | `.listRowInsets(.init(top: 8, leading: 26, bottom: 8, trailing: 26))` | `ledger_raw_spacing` |
| B08 | `.contentMargins(.horizontal, 26, for: .scrollContent)` | `ledger_raw_spacing` |
| B09 | `Spacer(minLength: 13)` | `ledger_raw_spacing` |
| B10 | `.clipShape(.rect(cornerRadii: .init(topLeading: 28, topTrailing: 28)))` | `ledger_raw_radius` |
| B11 | `UnevenRoundedRectangle(cornerRadii: RectangleCornerRadii(topLeading: 28, topTrailing: 28))` | `ledger_raw_radius` |

B10/B11 are the other two spellings of round 1's R03 (a sheet's top corners). Controls K01–K07 still pass
(multi-line `.padding`, `.shadow(color: .black…)`, `GridItem(spacing: 13)`, a raw value inside `EdgeInsets` with
tokens, `.rect(topLeadingRadius:)`, `.font(.title3.weight(.bold))`, and all of the above inside `LedgerDesign`).

## 14. Orange chip text on its orange tint is 4.04:1 on paper — design question (fails the AA decision)

- **Test:** `IncreaseContrastAdversarialTests.accentText_onAccentSoft_meetsAA` (iOS).
- **Attacks:** spec §8.1 pairs `accentDeep` text with `accentTint` (`rgba(255,91,34,.12)`) for the active Deload
  button and equipment chips; the v1 program builder draws "Deload" as `600 11.5px` `#C63F0F` on that tint, so
  4.5:1 applies (not bold, not large).
- **Repro:** `LedgerColor.accentText` (`#C03D0F`) on `LedgerColor.accentSoft` composited over `LedgerColor.ground`,
  light: **4.04:1** (with and without Increase Contrast, which leaves both tokens alone). Over `surface` (white card)
  it passes, as does dark (`#FF5B22` on the 16 % tint over `#0B0B0D`). The fix round darkened accentDeep 3 % to reach
  4.58 on bare paper; the tint takes it back under (the spec's `#C63F0F` was 3.84). Options: a darker chip text
  (`#B0380D` gives 4.63 on the tint, 5.25 on paper), a lighter tint, or a documented exception.

## 15. Comparator: one pixel over the limit passes at some sizes — minor bug (harness)

- **Test:** `SnapshotDiffAdversarialTests.precision_boundary_holdsFromBothSides` (402×999).
- **Repro:** a 402×999 grey reference (401,598 pixels; 0.5 % is 2,007.99, so 2,007 may differ) and the same with
  2,008 pixels red → `diffV2` returns nil. The boundary at exactly `precision` is now inclusive (finding 3 fixed), but
  `Float(401598 − 2008) / Float(401598)` = 0.99499997 rounds up to `Float(0.995)`. For phone-width (402 pt)
  references it happens at 33 of the heights 1…3000 (999, 1099, 1199, …); 200×1, 999×1, 1000×1, 1001×1 and 402×874
  are right. Compare counts in integers (`mismatched * 1000 <= pixels * 5`, or
  `mismatched <= Int((1 - Double(precision)) * Double(pixels))` with the constant as a decimal), as round 1 suggested.

## 16. A size mismatch attaches no difference image — minor bug (harness)

- **Test:** `SnapshotDiffAdversarialTests.sizeChange_attachesDifferenceImage`.
- **Repro:** reference 100×10, actual 104×10 → attachments `actual.png`, `reference.png` only. Testing-strategy §2.5
  "Failures attach diff images to the xcresult"; a size change is the most common snapshot failure at AX sizes (a
  label wraps to another line), and swift-snapshot-testing's own image strategy attaches a difference for it. Draw
  both onto the larger canvas and mark the non-overlap. (Every same-size failure now attaches `difference.png`, and
  it marks exactly the pixels beyond ΔE 2: finding 4 is fixed.)

## 17. Design-lint escape hatches — design questions

| Case | Snippet | Question |
|---|---|---|
| D01 | `.font(LedgerFont.font(.numeralL, dynamicTypeSize: .large))` | The residue of finding 1: the non-scaling `font(_:)` is gone, but any constant text size still compiles and lints. Flag a literal `dynamicTypeSize:` outside LedgerDesign? |
| D02 | `.font(LedgerFont.font(.label, size: 13))` | `font(_:size:)` is documented for an "already scaled" size; a literal isn't one. (Round 1's N12 keeps `LedgerFont.archivo(size: 30, …)` legal because the brief makes it public; the same answer should cover both) |
| D04 | `.ledgerFont(.body).dynamicTypeSize(.large)` | Pins the text size for a subtree |
| D05 | `.foregroundStyle(LedgerColor.ink.opacity(0.6))` | A raw alpha on a token leaves the AA ladder and Increase Contrast; spec §8.1 lists 20+ alphas features may be tempted to copy |
| D06 | `.padding(.horizontal, LedgerSpacing.m + 1)` | Token arithmetic with a literal |
| D07, D08 | `.tracking(2)`, `.lineSpacing(4)` after `.ledgerFont` | Letter-spacing and leading are role properties |
| D09 | `.font(.init(CTFontCreateWithName(…)))` | `Font(` and `Font.init(` are caught, `.init(` isn't |
| P04 (false positive) | `RoundedRectangle(cornerSize: CGSize(width: LedgerRadius.row, height: LedgerRadius.row))` | `cornerSize: CGSize(` is flagged even when both values are tokens |

---

## Audit of the fix round's edits to the round-1 adversarial tests

`git diff eaf5705 7439e3d -- LedgerKit/Tests scripts/tests`: five files, 45 insertions / 23 deletions. No test
function deleted, renamed, disabled or wrapped in `withKnownIssue` (67 → 68 `@Test`, same function names); no test
plan changed; `lint-rules-adversarial.test.sh` untouched and now wired into `check.sh` step 2 (55/55).

| Edit | Verdict |
|---|---|
| `ContrastAdversarialTests`: onAccent on accent 4.5 → 3:1 (phone and watch), plus `accentLabelRoles_areBold` (spec weight ≥ 700) | Legitimate — Pete's decision (white on accent, 700 labels, HIG "All sizes, Bold: 3:1"). The new assertion only reads the spec table; round 2 adds a rendered check (`accentLabelRole_rendered_isBold`, holds). |
| `LedgerColorAdversarialTests`: accentDeep `#C63F0F` → `#C03D0F`, inkMuted .45 → .48 dark / .60 light, watchInkMuted .40 → .46; the browser-composite test at .48 | Legitimate — the decided values, each commented. Spec §8.1–§8.3 still list the old values. |
| `LedgerFontSpecAdversarialTests`: `.button` weight 600 → 700 | Legitimate — Pete's decision (and v1's "Primary CTA 700 16px"). |
| `LedgerFontMetricsAdversarialTests`, `LedgerFontRenderingAdversarialTests` (tabular, rendered axes): `font(role)` → `font(role, dynamicTypeSize:)` at the size under test / the reference size | Neutral — same comparison at the same size. |
| `LedgerFontRenderingAdversarialTests.bareFont_accessibilitySize_scalesUp` (finding 1): now passes `.large` / `.accessibility3` explicitly | Re-expected, not weakened: `font(_:)` no longer exists, so the unscaled `Font` path finding 1 described is gone (every `Font` entry point needs a size), and the environment path is covered by `.ledgerFont`'s monotonic tests and round 2's `bareFont_everySizeAndWeight_matchesLedgerFont`. Two loose ends: the brief's public surface still reads `font(_ role:) -> Font // Dynamic Type–scaled` (the deviation is in architecture §11 only), and a constant size still gets through (17, D01). |

**Verdict: no round-1 test was weakened to pass without the behaviour being fixed.** Findings 1–10 are fixed as
tested: all round-1 adversarial tests pass on iOS 26.5 and watchOS 26.5.

## Design observations (no failing test)

- **Increase Contrast stops at the ink.** accentText (light 4.58:1) and white on the accent (3.1:1) are unchanged
  under Increase Contrast; the doc comment only promises the ink ladder, and Pete's decision doesn't say more. If
  "text to 7:1" is meant for all text, the orange needs a high-contrast variant too.
- **3:1 on the accent rests on the HIG table, not WCAG.** `watchButton` is 14 pt at 44–49 mm but ~13.2 pt at the
  40–42 mm default (`.large`), under WCAG's 14 pt bold "large text" line. The HIG's "All sizes, Bold: 3:1" row, which
  the decision cites, still holds.
- **The colour regex's leading-dot branch is broad.** Any enum case named like a colour after `(`, `[`, `,` or `:`
  (`.primary`, `.secondary`, `.white`…) is flagged. `LedgerDomain` has no such case today (checked), so there's no
  failing fixture; a feature-local `enum Rank { case primary, secondary }` would be flagged.
- **Host runs.** macOS has no Dynamic Type, so `swift test` on the host resolves every text size to the design size;
  round 2's Dynamic Type growth checks are compiled for iOS and watchOS only.

## Attacked and held (round 2)

On iOS 26.5 and watchOS 26.5: `scaledSize` is the design size at the reference text size (`.large` iOS, `.xLarge`
watchOS) for all 21 roles, follows `@ScaledMetric`'s curve for each role's text style at all 12 sizes (the brief's
watchOS `@ScaledMetric` risk), is monotonic and uncapped, and never goes below 11 pt for watch roles;
`font(_:size:)` clamps 10.5, 9 and 1 pt requests to the floor; `font(_:dynamicTypeSize:legibilityWeight:)` renders
identically to `.ledgerFont` for 21 roles × 12 sizes × regular/bold; a nil legibility weight is regular;
`.ledgerFont` restyles in place when text size or Bold Text changes. Bold Text: +100 for every role (never past 900),
visibly heavier for all 21 roles including the 700 numerals, rendered weight equals Archivo at `wght` + 100 and is
nearer it than + 200, the explicit-size path agrees; the accent labels render at 700 without Bold Text. Increase
Contrast (iOS): text ≥ 7:1 and inkFaint ≥ 4.5:1 on ground and surface in both schemes, no token gets worse, the
ladder keeps its order, grounds/accent/onAccent unchanged, and SwiftUI's own environment (`Color.resolve` and a
rendered view) gets the stronger ink, not just a `UITraitCollection`. Comparator: exactly `precision` passes and one
more pixel fails at 200×1, 999×1, 1000×1, 1001×1 and 402×874; every same-size failure attaches `difference.png` of
the reference's size marking exactly the pixels beyond ΔE 2; an undecodable reference still attaches the new image.
Lint: comments, doc comments, multi-line and raw string literals are exempt; `0` is allowed for spacing and radii;
tokens inside `EdgeInsets`, negative tokens, `GridItem(spacing: LedgerSpacing.s)` and `.ledgerFont` pass; raw values
inside LedgerDesign pass.

---

# Round 3 — after fix round 2 (`7689a74`)

Scope: fix round 2's changes — `.ledgerFont`'s CSS half-leading lift, `accentText` light `#B2390E`, the `.png`
comparator's whole-pixel boundary and size-change difference image, the rewritten `ledger_raw_*` regexes — plus the
gate's flakiness (review point 6). Pete's decisions of 2026-09-27 are requirements (WCAG AA while keeping the look;
Bold Text followed). Written from the brief, spec §8, the v1 and watch prototypes, the public declarations, `git show
7689a74`, Archivo's own tables and the xcresults. `implementation-notes.md` was not read.

## What was written

| File | Attacks |
|---|---|
| `…/Adversarial/LedgerFontLinePlacementAdversarialTests.swift` | The lift at xSmall, xxxLarge, AX3 and AX5 for all 21 roles (baseline vs CSS for the scaled size, caps inside, frame = `L` × size); both baselines of a two-line block; `.firstTextBaseline` across four role pairs; a role set on a container around a child with its own role; a background under the text |
| `…/Adversarial/AccentChipContrastAdversarialTests.swift` | Finding 14 as SwiftUI paints it: `accentText` on `accentSoft` over ground and surface, light and dark, with and without Increase Contrast (iOS), ratio from painted pixels; the watch's current exercise row (orange number, white name, muted scheme line on the 16 % tint over `#000`); `inkSecondary`/`inkMuted` on the tint `accentSoft`'s doc comment offers "behind a selected item" |
| `…/Adversarial/ComparatorPropertyAdversarialTests.swift` | Property tests with a seeded SplitMix64: 40 random sizes up to 402×200 (every fifth an exact multiple of 200 px) with the changed pixels at random positions and sub-threshold noise on a third of the rest — `floor(0.5 %)` passes, one more fails; 24 random size changes — the difference image is the union canvas and marks exactly the non-overlap plus real changes; a transposed size; a 1×1 image |
| `scripts/tests/lint-rules-adversarial-round3.test.sh` | 44 fixtures: 17 raw spellings, 9 escape hatches, 10 sanctioned uses that must pass, 3 false positives on sanctioned use, 5 controls. **Not wired into `check.sh`** (it fails today and would stop the gate at step 2) |

Also run by hand: a Swift Testing probe package on the host (`swift test`, scratch, not committed) and a serial host run
of `LedgerDesignTests` (`swift test --filter LedgerDesignTests --no-parallel`) for the flakiness analysis; Archivo's
`MVAR`/metrics at five axis positions (Core Text, scratch).

## Results

Run on the pinned simulators through the simulator lock.

| Run | Result |
|---|---|
| `scripts/check.sh --fast` | green: format, lint (round 3's Swift files included), the three wired lint scripts, package graph, host Domain + Persistence (419 tests) |
| `scripts/check.sh` (full gate, via the lock) | steps 0–2 green; **step 3 fails**: the PR plan on iOS 26.5 recorded 431 tests, 430 passed, **1 failed: `TokenValueTests.geometryTokens_values_matchBrief`, "Test exceeded execution time allowance of 1 minute"** (finding 19). XCTest killed the `LedgerDesignTests` runner, so that target recorded no other result; every other target passed, `LedgerUITests/Smoke` included. `set -e` stops before step 4 |
| `LedgerDesignTests` alone on iOS 26.5, the gate's flags plus `-only-testing:LedgerDesignTests` (same lock hold as the next row) | 133 test functions, 130 passed, **3 failed — all round 3**; implementer 35/35, round 1 63/63, round 2 23/23, round 3 9/12. 71 s, no timeout |
| Step 4 by hand (`check.sh`'s own `xcodebuild` line) | PR-Watch on watchOS 26.5: 542 tests, 539 passed, **3 failed — all round 3**; implementer 32/32, round 1 60/60, round 2 17/17, round 3 9/12 |
| `lint-rules-adversarial-round3.test.sh` (by hand) | 44 cases, **28 fail**: 16 raw spellings not flagged, 9 escape hatches, 3 false positives on sanctioned use; P01–P10, K01–K05 and B10 pass |
| `lint-rules-adversarial.test.sh`, `…-round2.test.sh` | 55/55, 39/39 |
| Host `swift test` | round 3's suites compile and agree; macOS resolves both schemes to the dark value, so only the dark contrast numbers mean anything there |

Round 3's Swift suites: 12 test functions (71 cases for line placement, 15 contrast cases on iOS / 11 on watchOS, 66
comparator cases).

Failing tests (left in place):

| # | Test | Severity |
|---|---|---|
| 18 | `LedgerFontLinePlacementAdversarialTests.nestedRoles_innerRole_placesItsOwnLine` (4/4 cases) and `background_underText_staysOnFrame` (21/21 roles); iOS + watchOS | **bug** |
| 19 | the gate itself: `TokenValueTests.geometryTokens_values_matchBrief` timed out (fix round 2's run 1: `registration_resolvedFont_isTheBundledFile`) | **bug** (flaky gate, test-caused) |
| 20 | `AccentChipContrastAdversarialTests.inkText_onSelectedItemTint_meetsAA` (3 of 4 cases on iOS; 4 of 4 on watchOS, where phone tokens resolve dark) | design question |
| 21 | `lint-rules-adversarial-round3.test.sh` B01–B09, B11–B17 | **bug** |
| 22 | `lint-rules-adversarial-round3.test.sh` D01–D09 | design questions |
| 23 | `lint-rules-adversarial-round3.test.sh` Q01–Q03 | design questions (false positives) |

## Close-out of findings 11–17

| # | Status | Evidence (iOS 26.5 and watchOS 26.5 unless noted) |
|---|---|---|
| 11 | **Resolved** | `LedgerFontLineBoxAdversarialTests.singleLine_baseline_matchesCSSHalfLeading` 21/21 and `singleLine_capitalInk_staysInsideFrame` 21/21 pass. Round 3 extends it — every text size, two lines and baseline alignment hold — but the mechanism has side effects: finding 18 |
| 12 | **Resolved** | round 2 lint P01–P03 pass (`lint-rules-adversarial-round2.test.sh` 39/39, now in `check.sh` step 2) |
| 13 | **Resolved** | B01–B11 flagged (39/39); 16 further spellings in finding 21 |
| 14 | **Resolved** | `IncreaseContrastAdversarialTests.accentText_onAccentSoft_meetsAA` passes (light/dark × ground/surface × Increase Contrast, iOS). Round 3 checks it as painted: `accentText_onPaintedAccentSoft_meetsAA` passes all 8 iOS cases (8-bit composites, which is what SwiftUI paints: light 4.52 on ground / 5.24 on surface, dark 5.32 / 4.90, unchanged by Increase Contrast), and `watchCurrentRow_textOnTint_meetsAA` the watch's current row (orange number 5.81, white name 18.0, muted scheme line 4.55). The margin on paper is 0.02 (observations); the neighbouring muted-text pair is finding 20 |
| 15 | **Resolved** | `SnapshotDiffAdversarialTests.precision_boundary_holdsFromBothSides` 6/6, 402×999 included; round 3's 40-seed property holds |
| 16 | **Resolved** | `sizeChange_attachesDifferenceImage` passes; round 3 checks the image's content (union canvas, 24 seeds) |
| 17 | **Resolved as decided** | D01, D02, D04–D09 flagged and P04 passes (39/39); the escape hatches next to them are findings 22 and 23 |

Pete's decisions hold: every round-1 contrast test (#5–8) and Bold Text test (#9) still passes on both platforms.

## 18. `.ledgerFont`'s lift moves the whole modified view: nested roles add up and backgrounds leave their frame — bug

- **Tests:** `LedgerFontLinePlacementAdversarialTests.nestedRoles_innerRole_placesItsOwnLine` (4 cases),
  `background_underText_staysOnFrame` (21 cases).
- **Cause (from `git show 7689a74`):** the CSS placement is `.padding(.top, -lift).padding(.bottom, lift)` on the
  modifier's content, so it shifts everything inside the modified view, not the glyphs. `.ledgerFont` reads like
  `.font` and SwiftUI code sets fonts on containers all the time (a row, a button label, a screen default).
- **Repro 1, a role set on a container:** `VStack(spacing: 0) { Text("H").ledgerFont(inner) }.ledgerFont(outer)` against
  `Text("H").ledgerFont(inner)`: same frame, but the inner baseline moves by the outer role's lift. In CSS a child
  block's lines are placed by its own `line-height`.

  | outer → inner | baseline shift |
  |---|---|
  | `display` → `numeralL` | 5.0 pt up (baseline 20.0 pt below the frame top, alone 25.0 pt); cap line 0.5 pt above the frame |
  | `watchNumeral` → `caption` | 10.0 pt up (baseline 0.0 pt, alone 10.0 pt); capitals 8.0 pt above the frame |
  | `eyebrow` → `numeralXL` | 2.0 pt up |
  | `bodyLight` → `title` | 2.0 pt down |

  (iOS 26.5 at the reference text size; the host gives the same numbers.)

  With `watchNumeral` around a caption the caption's capitals are drawn ~8 pt above its own frame; a `.clipped()`
  container, a scroll edge or a snapshot bound cuts them off.
- **Repro 2, content that is not text:** `Text("H").padding(LedgerSpacing.s).background(Color.red).ledgerFont(role)` —
  the red box should cover the view's frame exactly. It is drawn `lift` pt higher for **every** role:
  `button` −2.5…29.5 pt over a 0…32 pt frame, `numeralL` −5.0…41.0 over 0…46,
  `display` −5.0…51.5 over 0…56.5, `watchNumeral` −10.0…43.0 over 0…53, `body` −1.0…33.0 over 0…34, and `bodyLight`
  +2.0…40.0 over 0…38 (its lift is negative). The box overflows the frame at the top, leaves a gap at the bottom, and no longer matches the
  hit-test frame. The same happens to a hairline row's top rule, a capsule behind a button title, a set row's
  background, an SF Symbol next to the title — whatever sits inside the view the role is applied to.
- **Fix direction:** lift the text's lines, not the view — e.g. draw `Text` through a `TextRenderer` (iOS 18 /
  watchOS 11) that translates each line by `-lift` for the innermost role, and move `.firstTextBaseline` /
  `.lastTextBaseline` by the same amount so baseline alignment keeps working (it does today:
  `firstTextBaseline_twoRoles_shareOneBaseline` holds and must keep holding). Whatever the mechanism, the four tests
  above plus round 2's `LedgerFontLineBoxAdversarialTests` pin the behaviour.

## 19. The 60 s allowance counts time spent waiting for the main actor, and `LedgerDesignTests` keeps it busy for about a minute — bug (flaky gate, P1 per standards §9)

This is review point 6. Fix round 2's run 1 failed the allowance in `registration_resolvedFont_isTheBundledFile`, and
**this round's gate failed the same way** in `TokenValueTests.geometryTokens_values_matchBrief`:
`Test exceeded execution time allowance of 1 minute` at 60.000 s. Both tests do about a millisecond of work. The
tests cause this; the saturated machine only moves the total over the line.

- **Mechanism, reproduced deterministically on the host** (a scratch package, `swift test`, Swift Testing 1902):
  a main-actor test with `.timeLimit(.minutes(1))` whose body ran for **0.0003 s** fails with
  `Time limit was exceeded: 60.000 seconds` because another main-actor test held the main actor for 75 s. Swift
  Testing starts every test case at once (48 one-second sleepers finish in 1.06 s on this host, so there is no
  width limit), so each test's clock starts before it gets the main actor. Xcode applies the plan's allowance to
  Swift Testing tests the same way: the gate's failure is XCTest's own "exceeded execution time allowance", and the
  xcresult times below count the wait (`libXCTestSwiftSupport` reads `defaultTestExecutionTimeAllowance`).
- **Why it hits LedgerDesignTests:** the target uses `defaultIsolation(MainActor.self)` (`Package.swift`
  `uiSettings`), so every suite — the rendering ones and the ones that only compare constants — runs on the main
  actor, one job at a time. A serial host run (`swift test --filter LedgerDesignTests --no-parallel`) puts the
  target's main-actor work at 26.6 s, and **22.2 s of it is one test function**:
  `LedgerFontSizingAdversarialTests.bareFont_everySizeAndWeight_matchesLedgerFont` (round 2, 21 roles × 12 text
  sizes × 2 weights × 2 renders = 1,008 renders). On the iPhone 17 simulator of a busy machine that is about a
  minute: the last green run (fix round 2) reports all 121 `LedgerDesignTests` tests ending between 55 and 61 s,
  trivial ones such as "Spacing is the brief's 4/8/12/16/24/32 scale…" at 60.96 s, i.e. at the allowance. This
  round's design-only iOS run (less load, 71 s in all) shows the queue directly: `geometryTokens_values_matchBrief`
  reports 10.1 s and `registration_resolvedFont_isTheBundledFile` 10.2 s for 0.001 s of work, and the hog plus the
  47 tests behind it end at 35–39 s. With the whole PR plan on parallel clones, the same queue crossed 60 s.
- **Consequence beyond one red test:** when the allowance fires, XCTest kills the runner process, and every other
  result in it is lost. This round's gate recorded **1** `LedgerDesignTests` result (431 tests in the plan, against
  551 in fix round 2's green run); no design test, adversarial or not, reported pass or fail.
- **Not the cause:** font registration. `FontRegistration` is a `static let` initialised once, and the tests show it
  idempotent (`registration_calledRepeatedly_alwaysSucceeds`), safe under 64 concurrent callers, fine when someone
  registered first (`registration_afterExternalRegistration_succeeds` covers the other order), and nothing
  unregisters the font. Both victims finish in 0.001 s in the serial host run (`geometryTokens_values_matchBrief`
  compares five constants).
- **Concrete fix** (in the tests, not the product):
  1. Make the suites that need no main actor `nonisolated` (token values, layout tokens, spec tables, contrast
     maths, motion keyframes, registration): they stop queueing behind rendering.
  2. Nest the rendering suites under one `@Suite(.serialized)` parent. Main-actor tests already run one at a time,
     so this costs no parallelism, but each test's allowance then starts when it runs. Checked on the host: under a
     serialized parent the same 0.001 s test passes after the 75 s hog.
  3. Tag the 1,008-render matrix (round 2's own test) `.slow` (testing-strategy §6: `.slow` is > 2 s, skipped in
     PR plans, run nightly) and keep a PR subset (e.g. xSmall, large, AX5 × regular/bold). Serialising alone is not enough: that one
     function is itself about a minute under load.

  Not a fix: raising the allowance or retrying (testing-strategy §5). Round 3's own suites add a few seconds of
  main-actor work too (parameterised per role, so no single case is long); they belong under the same parent.

**Run 2 of fix round 2 ("Timed out while loading Accessibility") is environmental.** The message comes from
`XCUIApplication.launch()` waiting for the simulator's accessibility runtime, before any line of `Smoke` runs; the
test's only time limit is `waitForExistence(timeout: 10)`, which is not the step that failed. It passed in this
round's gate. The iOS lane runs `-parallel-testing-enabled YES` with no worker count, so Xcode boots fresh iPhone 17
clones, and a clone's accessibility bootstrap is what times out on a machine running three worktrees' simulators.
Nothing in the test can change that. If it recurs, pin the iOS worker count as step 4 already does for the watch
("one worker = one watch clone"), or boot the destination before `xcodebuild test`.

## 20. Muted text on the selected-item tint is below 4.5:1 — design question

- **Test:** `AccentChipContrastAdversarialTests.inkText_onSelectedItemTint_meetsAA`.
- **Attacks:** `accentSoft`'s doc comment ("Tinted fill behind a selected item") and the brief's NFR (informational
  text ≥ 4.5:1). A selected row keeps its metadata line; the watch prototype does exactly that (current exercise
  row: `.4` white scheme line on the 16 % tint), and on the watch it passes.
- **Repro (painted by SwiftUI, standard contrast):** light on ground **4.33:1**, dark on ground **4.39:1**, dark on surface **4.22:1**
  (light on surface 4.55:1 passes; iOS 26.5). `inkSecondary` passes everywhere
  (6.3–8.2:1); with Increase Contrast `inkMuted` passes (.74 alpha).
- **Question for Pete:** is muted text allowed on `accentSoft`? Options: say in the token docs that text on the tint
  uses `inkSecondary` or `accentText`; raise `inkMuted` when it sits on the tint; or a lighter tint (12 % → ~9 %
  light), which also widens finding 14's 0.02–0.04 margin.

## 21. Design lint: 16 more raw spellings slip through — bug

`scripts/tests/lint-rules-adversarial-round3.test.sh`, same harness as rounds 1 and 2.

| Case | Snippet | Rule that should fire |
|---|---|---|
| B01 | `var accent: Color { .orange }` — a named colour after `{` (implicit return) | `ledger_raw_color` |
| B02 | `return .green` in a computed colour | `ledger_raw_color` |
| B03 | `.foregroundStyle(.quinary)` — the list stops at `quaternary` | `ledger_raw_color` |
| B04 | `.foregroundStyle(LedgerColor.accent.secondary)` — a raw alpha on a token through `ShapeStyle`'s hierarchy, the same thing D05 (`.opacity(0.6)`) was decided to flag | `ledger_raw_color` |
| B05 | `LedgerColor.ink⏎.opacity(0.6)` — D05 with the chain wrapped | `ledger_raw_color` |
| B06 | `.foregroundStyle(Color.Resolved(red: 1, green: 0.36, blue: 0.13))` — `Color.Resolved` is a `ShapeStyle` | `ledger_raw_color` |
| B07 | `context.fill(path, with: .color(red: 1, green: 0.36, blue: 0.13))` in a `Canvas` (a chart) | `ledger_raw_color` |
| B08 | `let titleFont: Font = .title` then `.font(titleFont)` — the font rule has no `=` branch | `ledger_raw_font` |
| B09 | `.environment(\.font, .system(size: 13))` | `ledger_raw_font` |
| B11 | `.monospaced()` — the design sibling of `.fontDesign(` | `ledger_raw_font` |
| B12 | `.padding(.horizontal, isCompact ? 13 : LedgerSpacing.l)` | `ledger_raw_spacing` |
| B13 | `HStack(spacing: isCompact ? 4 : LedgerSpacing.s)` | `ledger_raw_spacing` |
| B14 | `RoundedRectangle(cornerRadius: isSheet ? 28 : LedgerRadius.card)` | `ledger_raw_radius` |
| B15 | `.clipShape(.rect(corners: .concentric(minimum: .fixed(13))))` — iOS 26's corner API (`Edge.Corner.Style.fixed`, `ConcentricRectangle`) | `ledger_raw_radius` |
| B16 | a multi-line `.font(` ternary with a trailing `// comment` inside the call | `ledger_raw_font` |
| B17 | a multi-line `.padding(` with a trailing `// comment` after `.horizontal,` | `ledger_raw_spacing` |

B12–B14 are the spacing/radius versions of round 2's B02/B05 (a ternary). B16: `excluded_match_kinds` drops a
match that contains a comment token, and the `.font(` branch's `[^()]*?` spans the whole argument; B17: `\s*` cannot
cross the comment. The same call with the comment after it is flagged (K02, K04). B10 (`.textScale(.secondary)`) is
flagged, but only because the colour rule reads `(.secondary` as a colour, so its message is wrong.

## 22. Design lint: escape hatches next to the decided ones — design questions

| Case | Snippet | Question |
|---|---|---|
| D01 | `.dynamicTypeSize(...DynamicTypeSize.large)` | Finding 17 flagged a pinned size (`.dynamicTypeSize(.large)`); a cap at the reference size has the same effect on every larger setting and passes. (`min(dynamicTypeSize, .accessibility2)` is flagged, by accident of the `,` branch: K03) |
| D02 | `.ledgerFont(.watchLabel).minimumScaleFactor(0.5)` | Shrinks a watch role under the 11 pt floor (criterion 4) |
| D03 | `.foregroundStyle(LedgerColor.ink).opacity(0.6)` | The raw alpha D05 bans, applied to the view |
| D04, D05 | `Spacer().frame(height: 13)`; `private let rowGap: CGFloat = 13` then `.padding(.vertical, rowGap)` | Gaps made with a frame or a named constant; the regexes cannot follow a constant |
| D06, D07 | `.fill(.separator)`, `.background(.ultraThinMaterial)` | System colours by another name; the spec has its own hairline and glass |
| D08, D09 | `.baselineOffset(2)`, `.textCase(.uppercase)` after `.ledgerFont` | Role properties, like tracking and leading (finding 17 flagged those) |

## 23. Design lint: false positives on sanctioned use — design questions

| Case | Snippet | Flagged by |
|---|---|---|
| Q01 | `#Preview("AX3") { … .dynamicTypeSize(.accessibility3) }` in a feature — standards §7 asks for a preview per meaningful state and the DoD for Dynamic Type at XL | `ledger_raw_font` |
| Q02 | `.frame(width: proxy.size.width - 2 * LedgerSpacing.screen)` — the content width between the screen insets | `ledger_raw_spacing` |
| Q03 | `private let emphasis: Emphasis = .primary` with a feature enum `Emphasis { case primary, secondary }` — the new `=` branch widens round 2's observation about colour-named enum cases to every assignment | `ledger_raw_color` |

Options: exempt `#Preview` bodies / `*+Previews.swift` from the text-size branch; flag token arithmetic only in spacing
positions (`padding`, `spacing:`, `EdgeInsets`); accept Q03 and keep colour names out of feature enums.

---

## Audit of fix round 2's edits to the adversarial tests

`git diff c39464c 7689a74 -- LedgerKit/Tests scripts TestPlans`: two Swift files (3 insertions / 2 deletions), one line
in `check.sh` (round 2's lint script wired into step 2) and 14 re-recorded PNGs. `e39f72b` touches only `implementation-notes.md`.

| Edit | Verdict |
|---|---|
| `LedgerColorAdversarialTests`: `orangeDeep` `0xC03D0F` → `0xB2390E`, with a comment citing finding 14 | Legitimate — the value Pete's AA decision now produces; the test still reads the token through three independent paths. Spec §8.1 still lists `#C63F0F` (see observations). |
| `TokenValueTests` (implementer's): `accentText` → `0xB2390E` | Same. |
| 14 references re-recorded (`phonePalette_*`, `phoneTypeRamp_*`, `watchPalette_46mm`, `watchTypeRamp_*`) | Justified by the stated causes: the labels and ramp lines move with the line placement (checked `watchPalette_46mm` before/after: labels ~1 pt higher, swatches unchanged) and the light `accentText` swatch changed. |

No test function deleted, renamed, disabled, wrapped in `withKnownIssue` or given a wider tolerance (91 adversarial
`@Test` functions before and after); no test plan changed; `lint-rules-adversarial.test.sh` and
`lint-rules-adversarial-round2.test.sh` are unchanged and both now run in `check.sh` step 2. **Verdict: no
adversarial test was weakened.**

## Design observations (no failing test)

- **Finding 14 passes by 0.02–0.04.** `accentText` on `accentSoft` over paper paints at 4.52:1; the painted values
  match 8-bit sRGB compositing exactly (the failing `inkMuted` cases agree with that computation to three decimals).
  Any change to paper, the tint or the text breaks it; `accentText_onPaintedAccentSoft_meetsAA` now pins it.
- **"Keep the look".** `#B2390E` is ΔE76 7.8 from the spec's `#C63F0F` (L\* 41.9 against 46.4, same hue): a
  visible darkening. On paper it is 5.14:1 (the spec value was 4.35). Spec §8.1 still lists `#C63F0F`.
- **Archivo's vertical metrics are constant.** No `MVAR` table; ascent 878, descent 210, cap height 686 units at
  wght 100–900 × wdth 62–125, so `ArchivoFont.baselineBelowMiddle` as one constant is sound.
- **The watch lane did not enforce the allowance the way iOS does.** Fix round 2's green PR-Watch run reports
  ~1,005–1,010 s for almost every `LedgerDesignTests` test with no timeout (this round's watch run: ~28 s); the iOS
  lane kills the runner at 60 s. iOS is where finding 19 bites, but the fix applies to both.

## Attacked and held (round 3)

On iOS 26.5 and watchOS 26.5: `.ledgerFont` puts a lone line's baseline at CSS half-leading for the scaled size at
xSmall, xxxLarge, AX3 and AX5 for all 21 roles, keeps capitals inside the frame and the frame at `L` × size; both
baselines of a two-line block sit at CSS positions and the frame is `2L` × size; `.firstTextBaseline` aligns the ink
of numeralXL/eyebrow, watchNumeral/watchLabel, display/bodyLight and numeralL/caption within a pixel (the lift
moves the guides with the text). Archivo has no `MVAR`, so one ascent/descent constant is right at every axis
position. `accentText` on `accentSoft` as painted meets 4.5:1 in both schemes, over ground and surface, with and
without Increase Contrast; the watch's current exercise row meets it for all three texts. The comparator: 40 seeded
sizes up to 402×200 with the changed pixels anywhere and sub-threshold noise elsewhere — exactly `floor(0.5 %)`
passes and one more fails; 24 seeded size changes fail with a difference image the size of the union that marks
exactly the non-overlap plus the real changes; a transposed size fails; a 1×1 image behaves. Lint: ten sanctioned
spellings pass (`LedgerFont.font(_:size:)` with `scaledSize`, `.lineLimit`, `Spacer(minLength: 0)`, `Color.clear`
and `.clear` in a gradient, adaptive layout on `dynamicTypeSize`, token-only radius and spacing arithmetic, a 44 pt
frame, `.primaryAction`, ternaries between tokens); `LedgerDesign` may still spell everything. Font registration is
not a flakiness source (idempotent, safe under 64 racing callers, order-independent, never unregistered). Fix round
2's test edits weaken nothing, and its 14 re-recorded references have a stated visual cause.

---

# Round 4 — close-out after the re-plan (`aaaaca1`)

Scope: Pete's decisions of 2026-09-29 are the contract (brief, "Decisions during delivery"): (1) text uses SwiftUI's
native `.lineHeight` only, and the CSS half-leading emulation is gone; (2) the design lint is a tripwire with a frozen,
documented rule list (engineering-standards §7), and "tokens only" is enforced by review. This round closes out
findings 18–23, audits every test edit fix round 3 made, and attacks only what fix round 3 introduced: the native
line-height contract, `snapshotAppearance(_:)`, and the isolation and serialization of the design suites. New raw-value
spellings are out of scope (decision 2). Read: the brief, rounds 1–3 of this file, only the "Fix round 3 (re-plan)"
section of `implementation-notes.md`, engineering-standards §7, and `git show aaaaca1`.

## What was written

| File | Attacks |
|---|---|
| `…/Adversarial/NativeLineHeightAdversarialTests.swift` | Every role as a container around a child with its own role, and as a second `.ledgerFont` on top of it, pixel for pixel; a role on a container reaching a child with no role, pixel for pixel; a background under a symbol and two lines at xSmall and AX5; three hard-broken and three soft-wrapped lines at xSmall and AX5 (pitch = L × size ± 1 pt); every role's first and last baselines against a one-line partner at the reference size and AX5 (168 cases) |
| `…/Adversarial/MutedTextContrastAdversarialTests.swift` | `inkMuted` as SwiftUI paints it on ground and surface, bare and under `accentSoft`, both schemes, with and without Increase Contrast (iOS); phone `inkMuted` on `watchGround`, bare and under the tint |
| `…/Adversarial/SnapshotAppearanceAdversarialTests.swift` | The phone type ramp as swift-snapshot-testing's `.sizeThatFits` strategy lays it out with `snapshotAppearance`, at large, xLarge, AX3 and AX5: ink away from both edges, and the image as tall as the sheet at its own height (iOS); every watch snapshot sheet (ramp, bold ramp, palette) at 42, 46 and 49 mm and at AX3/AX5 on 46 mm: ink away from both edges |

The first version of the height test compared the strategy's image with `ImageRenderer`'s and failed at xLarge by
12 px. That was the two renderers rounding non-integral text sizes differently (observations), not truncation; the
test now compares the strategy with itself at the sheet's own height (`.fixedSize(horizontal: false, vertical: true)`),
same renderer and traits, and xLarge passes exactly.

## Results

Run through the simulator lock on the pinned simulators.

| Run | Result |
|---|---|
| `scripts/check.sh`, full, **once**, via the lock (`scratchpad/f06-closeout-check.log`; waited 122 s for another worktree's gate; 1-minute load average 23–206 while it ran) | Steps 0–2 green: format, lint, `lint-rules.test.sh` (4 rules × 3 modules), `…-adversarial` 55/55, `…-round2` 39/39, `…-round3` 44/44 (33 asserted plus 11 `limit`), package graph. **Step 3 fails only on round 4's finding:** the PR plan on iOS 26.5 recorded 574 tests, 572 passed, 1 skipped (the nightly-only full bare-font matrix), and **1 failed, `SnapshotAppearanceAdversarialTests.phoneRamp_strategyLayout_takesIdealHeight` at AX3 and AX5 (finding 24)**. There was no timeout, every other target passed (`LedgerUITests/Smoke` included), and nothing was retried. `set -e` stopped the script before step 4 |
| Step 4 run by hand, with `check.sh`'s own `xcodebuild` line and `check-test-results.sh`, via the lock | PR-Watch on watchOS 26.5: 551 tests, 550 passed, 1 skipped (the same matrix), 0 failed; 8 of 8 targets |
| Finding 19, measured in the gate | `LedgerDesignTests` recorded all its results (143 on iOS, 129 on watchOS; round 3's failing gate had recorded 1). The longest took **1.10 s on iOS** and 0.42 s on watchOS, against the 60 s allowance |
| Before the gate: `LedgerDesignTests` alone on both simulators with the gate's flags, via the lock | watchOS: 129 passed, 1 skipped; every round-4 suite passed. iOS: every round-4 suite passed except the first version of the height test (see above). Then `SnapshotAppearanceAdversarialTests` alone on iOS twice: once for the diagnosis, and once to confirm the corrected test (large and xLarge pass; AX3 and AX5 fail) |
| Host `swift test` | Round 4's suites compile, and the 8 host-runnable tests pass (the two strategy tests are iOS-only; macOS has no Dynamic Type) |

## Close-out of findings 18–23

| # | Status | Evidence (iOS 26.5 and watchOS 26.5 unless noted) |
|---|---|---|
| 18 | **Resolved** | The lift and both paddings are gone (`git show aaaaca1`, `LedgerFont.swift`). `LedgerFontLinePlacementAdversarialTests.nestedRoles_innerRole_placesItsOwnLine` 4/4 and `background_underText_staysOnFrame` 21/21 pass with their round-3 assertions. Round 4 pushes it further and it holds: `nestedRoles_everyOuterRole_leavesInnerRoleUntouched` 21/21 (all 21 roles as container and as a second modifier, pixel-identical), `containerRole_childWithoutRole_matchesDirectRole` 21/21, `background_extremeTextSizes_staysOnFrame` 42/42 |
| (11) | **Resolved by decision** | Superseded by decision 1: the CSS positions are retired, and the retargeted tests (audit below) pass |
| 19 | **Resolved** | `scripts/check.sh` ran once and was not retried. Every result was recorded on both lanes: 143 `LedgerDesignTests` results on iOS and 129 on watchOS, against 1 in round 3's gate. The longest took 1.10 s on iOS and 0.42 s on watchOS, against the 60 s allowance, while the 1-minute load average was 23–206. The only failure is round 4's new finding 24. The value suites are `nonisolated`, the rendering suites are serialized, and the 1,008-render matrix is nightly-only (audit below) |
| 20 | **Resolved** (under Pete's AA decision of 2026-09-27) | `inkMuted` .51 dark / .62 light. `AccentChipContrastAdversarialTests.inkText_onSelectedItemTint_meetsAA` 4/4 on both platforms; round 4's `inkMuted_everyGroundAndTint_meetsAA` 8/8 on iOS (Increase Contrast included), 4/4 on watchOS, and `inkMuted_onWatchGround_meetsAA` passes. Recomputed below: the lowest is 4.60:1 |
| 21 | **Resolved** (B01–B15); **resolved by decision** (B16, B17) | `lint-rules-adversarial-round3.test.sh`: B01–B15 each flagged by the rule it names (B10 by both colour and font); B16 and B17 are `limit` cases and documented in §7 ("A comment inside the call") |
| 22 | **Resolved by decision** | D01–D09 are `limit` cases; each is one bullet of §7's known limits (D01 size cap; D02 `.minimumScaleFactor`; D03 alpha on the view; D04 frame gap; D05 constant; D06/D07 `.separator`, materials; D08/D09 `.baselineOffset`, `.textCase`) |
| 23 | **Resolved** | Q01–Q03 pass; the spellings next to them are still flagged (round 2's D01, D04, D06 in `…-round2.test.sh` 39/39; round 3's K03 in `…-round3.test.sh` 44/44) |

`inkMuted` recomputed from the token values, composited in gamma sRGB with 8-bit rounding at each layer, which is what
SwiftUI paints (the painted-pixel tests agree). WCAG 2.x ratio against the surface directly behind the text; the
tint is `accentSoft` (12 % light, 16 % dark) over that ground:

| Scheme | Ground | bare | under `accentSoft` | Increase Contrast (.74), bare | Increase Contrast, under `accentSoft` |
|---|---|---|---|---|---|
| light (.62) | paper (`ground`) | 4.84 | 4.62 | 7.24 | 6.75 |
| light (.62) | card (`surface`) | 5.10 | 4.87 | 7.83 | 7.25 |
| dark (.51) | `ground` `#0B0B0D` | 5.05 | 4.76 | 9.70 | 8.55 |
| dark (.51) | sheet (`surface`) `#131316` | 5.04 | 4.60 | 9.37 | 8.03 |
| watch (phone tokens resolve dark, .51) | `watchGround` `#000` | 4.97 | 4.92 | n/a | n/a |

Every cell is ≥ 4.5:1, so finding 20 closes. The margins are thin by design (one 0.01 alpha step past the threshold;
.50 gives 4.44 on the sheet tint, .61 gives 4.48 on the paper tint). The unrounded composites differ from these by at
most 0.02.

## Audit of fix round 3's test edits

`git show -w aaaaca1 -- LedgerKit/Tests scripts`: 143 → 144 `@Test` functions (one added, three renamed, none deleted,
disabled or wrapped in `withKnownIssue`); no test plan changed; no tolerance widened.

| Edit | Verdict |
|---|---|
| `LedgerFontLineBoxAdversarialTests.singleLine_baseline_matchesCSSHalfLeading` → `…_matchesNativeLineHeight`: the baseline equals the same "H" set with only the role's font and `.lineHeight(.multiple(factor:))` (± ½ pt), and the frame is L × size (± 1 pt) | **Accept** — decision 1 drops CSS placement. It still catches a lift coming back: the smallest former lift (`label`, 0.8 pt) is over ½ pt |
| `LedgerFontLineBoxAdversarialTests.singleLine_capitalInk_staysInsideFrame`: the baseline-inside-the-frame half now skips roles with L < 1 | **Accept** — decision 1 ("1–10 pt off"). Only `watchNumeral` (0.86) is skipped; the cap-line half still covers all 21 roles |
| `LedgerFontLinePlacementAdversarialTests.singleLine_everyTextSize_matchesCSS` → `…_matchesNativeLineHeight` | **Accept** — decision 1. The tolerance tightened, from 3 % + ½ pt to ½ pt; the cap-line and frame checks are unchanged |
| `twoLines_bothBaselines_matchCSS` → `twoLines_baselinePitch_isLineHeightTimesSize` | **Accept** — decision 1 retires absolute positions and keeps the pitch. The 3 % + ½ pt tolerance is loose (1.6 pt for `display`), so round 4 adds ± 1 pt over three lines at xSmall and AX5 (holds) |
| `nestedRoles_innerRole_placesItsOwnLine`, `firstTextBaseline_twoRoles_shareOneBaseline`, `background_underText_staysOnFrame`: assertions unchanged, one display name reworded | **Accept** |
| `verticalMetrics()`, `cssBaseline(_:size:line:)` and `import CoreText` removed from both files | **Accept** — they served only the retired CSS assertions |
| Round-3 lint script: B16, B17 from a rule to `limit` | **Accept** — decision 2 closes spellings "where a rule can do it simply". SwiftLint's `excluded_match_kinds` drops any match that spans a comment token, and removing `comment` from the list would bring back round 1's N09 false positive. Listed in §7 |
| Round-3 lint script: D01–D09 from `any` to `limit` | **Accept** — decision 2 makes finding 22's escape hatches documented limits. All nine map to a §7 bullet (close-out table) |
| The `limit` expectation itself: passes only while no rule flags the case, and fails with "update docs/engineering-standards.md §7" once one does | **Accept** — it keeps §7's list true |
| Round-3 lint script wired into `check.sh` step 2 | **Accept** |
| `TokenValueTests`, `ContrastAdversarialTests`, `LayoutTokenAdversarialTests`, `LedgerFontSpecAdversarialTests` and the `Resolve` helper made `nonisolated` | **Accept** — finding 19's root cause, main-actor queueing. They use no main-actor API (no `MainActor`, `await`, `Probe`, `ImageRenderer` or `UITraitCollection`), and Swift 6 checks it under `defaultIsolation(MainActor.self)` |
| The other 21 suites nested in `@Suite("Rendering (serialized)", .serialized) enum RenderingSuites` | **Accept** — finding 19. With `-w` the diff is the wrapper, re-wrapped lines, three helper types moved into trailing extensions (SwiftLint `nesting`) and one display name shortened. `.serialized` is recursive, so each test's allowance starts when that test runs |
| `IncreaseContrastTests` kept in the serialized group rather than made `nonisolated` | **Accept** — `UITraitCollection { $0.… = … }` mutates main-actor state |
| `bareFont_everySizeAndWeight_matchesLedgerFont` tagged `.slow` and `.enabled(if: TestLane.runsSlowTests)`; new PR test `bareFont_representativeSizesAndWeights_matchesLedgerFont` (xSmall, large, AX5 × regular/bold) | **Accept** — finding 19, part 3. This is the one test whose own work (22 s serial on the host, about a minute on a loaded simulator) nears the 60 s allowance even when serialized; this is not about machine speed. `Nightly` and `Nightly-Watch` set `LEDGER_TEST_LANE=nightly` and allow 600 s, so the full matrix still runs there. The subset still guards what the matrix guards: both paths go through the same `scaledSize` and `font(_:size:legibilityWeight:)`, and the only size-dependent code is the floor (`max(size, minimumSize)`, reached at xSmall by the watch roles) and the AX curve (reached at AX5). The middle sizes stay pinned in the PR lane by `scaledSize_everyTextSize_followsScaledMetric` (all 12 sizes), `scaledSize_acrossTextSizes_monotonicUncappedFloored`, round 1's `.ledgerFont` growth test, and round 3's line placement at xxxLarge and AX3 (frame = L × `scaledSize` for `.ledgerFont`). The subset loses the bold comparison at the nine middle sizes, and weight does not depend on size in the code |
| `TokenValueTests`, `LedgerColorAdversarialTests` (and its browser-composite check): `inkMuted` .48 → .51 dark, .60 → .62 light | **Accept** — finding 20's fix under the AA decision; the token changed, and three independent paths still read it |
| 16 references re-recorded | **Accept** for the stated causes (native placement, the `inkMuted` swatch, the harness fix). The two AX3 phone ramps still record four samples cut to one line: finding 24 |

**Verdict: no test was weakened beyond what decisions 1 and 2 retire.**

## 24. The snapshot strategy still cuts wrapping text at AX3 and AX5 — minor bug (harness)

- **Test:** `SnapshotAppearanceAdversarialTests.phoneRamp_strategyLayout_takesIdealHeight` (iOS). AX3 and AX5 fail;
  large and xLarge pass.
- **Attacks:** fix round 3's `snapshotAppearance(_:)` and what the notes say about it: after the fix the "whole ramp [is]
  visible", the "…" endings at AX3 are "not clipping", and slice 2 "should use it on every phone snapshot".
- **Cause:** swift-snapshot-testing 1.19 sizes a `.sizeThatFits` view with
  `hostingController.sizeThatFits(in: CGSize(width: 0.0, height: 0.0))` (`SwiftUIView.swift`). The sheet's
  `.frame(width: 402)` fixes the width, but every `Text` is offered zero height, and a `Text` offered no height takes
  one line and truncates. `snapshotAppearance` fixed the text size the sheet is measured at. It did not change that
  proposal.
- **Repro** (iOS 26.5, dark): the strategy's image against the same strategy with
  `.fixedSize(horizontal: false, vertical: true)`, which is the sheet at its own height with the same renderer and
  traits. large 733 = 733 px, xLarge 795 = 795 px, but **AX3 1249 against 1454 px** and **AX5 1522 against 1919 px**.
  The committed `phoneTypeRamp_appearance_matchesReference-_.{light,dark}-accessibility3.png` show "Train four day…",
  "Upper A — Pus…", "Upper A — Push…" and "Same movement pattern,…". With `.fixedSize` each of those wraps to two
  lines (the failing run attaches `snapshot-*.png` and `ownHeight-*.png`).
- **Why it matters:**
  - Criterion 3's AX3 cell is where a layout has to wrap, and the references record truncation instead (the HIG says
    not to truncate at large text sizes).
  - Multi-line text at an accessibility size, where decision 1's native line height is the whole contract, never
    appears in a reference.
  - Slice 2's components (an empty state's body, a sheet title, a set row) would be recorded the same way, so a
    wrapping or line-height regression at AX3 could not fail a snapshot.

  Nothing is clipped at the edges: `phoneRamp_strategyLayout_notClipped` holds up to AX5, with ink at least 8 px
  from both edges.
- **Fix direction:** in the harness, not the product. For example, `snapshotAppearance` (or a phone-sheet helper) adds
  `.fixedSize(horizontal: false, vertical: true)`, and the two AX3 references are re-recorded. At large and xLarge
  the height is unchanged (733 and 795 px).

## Out of scope, noted

- **Increase Contrast under the tint.** On paper under `accentSoft`, Increase Contrast `inkMuted` (.74) is 6.75:1 and
  `inkFaint` (.60) 4.33:1. The ladder promises 7:1 and 4.5:1 on bare ground and surface only, and the brief's
  4.5:1 holds for text, so this is not a re-plan item. If the ladder's promise is meant to hold on a selected item
  too, it needs a step there.
- **Two renderers, two roundings.** The same phone sheet is 12 px taller in `ImageRenderer` (807 px) than in the
  snapshot strategy (795 px) at xLarge, and 14 px taller at AX3 and AX5 once wrapped. They agree at large (733 px),
  where sizes are whole points. Watch snapshots and pixel probes use `ImageRenderer` and phone snapshots use
  `UIHostingController`, so a test must not compare heights across the two.
- **`watchNumeral` below its frame at large watch text sizes.** The 0.14 em overflow that decision 1 accepts grows with
  the scaled size. Slice 3's watch components should size their spacing token for the largest supported watch text
  size, not only the 46 mm default.

- **The next gate timeout is in `LedgerDomainTests`, not F06.** In this gate's iOS lane, 369 of LedgerDomainTests'
  413 results report more than 30 s (median 36 s, longest 44.25 s, "A drop row on the shorter member still waits for
  the working rounds to finish"). The watch lane's longest is 27 s. Trivial tests such as
  `ProgramTests.init_oneWeek_throwsTooFewWeeks` report 43 s. This is finding 19's pattern: every test's clock starts
  at once, and the tests wait for workers. It leaves 16 s of headroom under the 60 s allowance on a loaded machine.
  That target belongs to F02/F04 and is not part of this re-plan.

## Attacked and held (round 4)

On iOS 26.5 and watchOS 26.5:

- **Nested roles.** Every one of the 21 roles, set on a container around a `bodyLight` or `watchNumeral` child, or
  applied as a second `.ledgerFont` on top of it, draws the child pixel-identical to the child alone: case, tracking,
  figures and line pitch included. A role on a container reaches a child without a role pixel-identically, for all
  21 roles.
- **Backgrounds.** A background under a symbol and two lines of text stays on the view's frame (± ½ pt) at xSmall and
  AX5, for all 21 roles.
- **Line pitch.** Three hard-broken and three soft-wrapped lines are L × size apart (± 1 pt), in a frame of 3L × size
  (± 1 pt), at xSmall and AX5, for all 21 roles, `watchNumeral`'s 0.86 included.
- **Baselines.** Each role's two-line block aligns its first and its last baseline with an `eyebrow` or `watchLabel`
  partner, within 1 px at 2×, at the reference size and at AX5.
- **`inkMuted` contrast.** As painted, it is ≥ 4.5:1 on every ground and tint (lowest 4.60, dark sheet under the
  tint). With Increase Contrast it is ≥ 6.75, and on `watchGround` 4.97 bare and 4.92 under the tint.
- **Snapshot sheets.** The phone ramp, as the snapshot strategy lays it out, keeps ink at least 8 px from both edges
  at large, xLarge, AX3 and AX5. The watch ramp, bold ramp and palette keep ink at least 8 px from both edges at
  42/46/49 mm defaults and at AX3/AX5.
- **Isolation.** LedgerDesignTests has 25 suites: 21 under `RenderingSuites` and 4 `nonisolated`, and none of the
  four touches the main actor. No other test target renders: no `ImageRenderer`, `assertSnapshot` or
  `RenderedImage` in `LedgerKit/Tests` outside LedgerDesignTests, or in `Apps`.
- **Lint.** The round-3 script passes 44/44, 11 of them `limit` cases, and §7's known limits match those 11 one for
  one.
- **Gate.** One run of `check.sh`, with no retry. Apart from finding 24, every test in both PR plans passes: iOS 572 passed and 1 skipped, and PR-Watch 550 passed and 1 skipped (step 4 by hand). No `LedgerDesignTests` test comes near the allowance
