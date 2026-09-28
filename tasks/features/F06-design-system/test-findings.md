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
