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

# Slice 2 — round 1 (`38d43a8`)

Scope: slice 2's components (`PrimaryButton`, `PillButton`, `IconPillButton`, `Eyebrow`, `HairlineList` / `HairlineRow`,
`SetRow` + `SetRowHeader` + `SetRowSteppers`, `RestRing`, `LedgerIcon`) against criteria 3 (these components), 5 and 6,
the v2 prototype (`Ledger v2.dc.html` rest card and set rows; `LedgerTabs*.dc.html` for the icon stroke idiom) and
Pete's decisions (AA with the look kept; the design lint is a frozen tripwire, so no new raw-value spellings were
hunted). Read: the brief, the slice-plan row, engineering-standards §7 and the public component interfaces. The tests
below were written and compiled before I read the implementation notes' "## Slice 2" section. Toolchain: Xcode 27.0,
iPhone 17 and Apple Watch Series 12 (46 mm) on 27.0.

## What was written

Four files in `LedgerKit/Tests/LedgerDesignTests/Adversarial/`, 26 test functions. There are no new snapshot
references: every assertion reads pixels, geometry or UIKit's accessibility tree, so no `--record-snapshots` run
was needed.

| File | Isolation | Attacks |
|---|---|---|
| `RestRingAdversarialTests.swift`: `RestRingGeometryAdversarialTests` | `nonisolated` (values; iOS and watchOS) | The arc against a model of the prototype's SVG (`circle` from 3 o'clock toward 6, `rotate(-90deg)`, `dasharray 182`, `dashoffset 182 − 182 × p`). 500 seeded progress values (`SplitMix64`, seed 20260929): starts at (32, 3), ends at the prototype's dash end. Tiny progress (least non-zero, least normal, 1e-12, 1e-6); −0, signalling NaN, the largest finite value; `1.0.nextDown` and 0.99; the phone geometry keeps r + stroke/2 inside the frame |
| `RestRingAdversarialTests.swift`: `RestRingRenderingAdversarialTests` | `RenderingSuites` (iOS) | Rendered at xSmall, large, xLarge, xxxLarge, AX3 and AX5 in both schemes: no ink in a 12 pt padding around the frame, ring centred; the labels "2:30", "10:00" and "0:05" inside the track's inner edge and on one line; a quarter only in the top-right quadrant (from 12, reaching 3), three quarters leaving the top-left empty; half = the right half and 0.5 ± 0.05 of a full ring's orange |
| `ComponentAccessibilityAdversarialTests.swift` | `RenderingSuites` (iOS) | At xSmall, xxxLarge and AX5: 12 tappable cases (both PrimaryButton forms, three pill styles, the icon button, two tappable HairlineRows, SetRow pending, active, done and drop set) are labelled buttons ≥ 44 × 44 in the expected number, and the steppers are adjustable and ≥ 44. What a done row and a done check say; stepper values; relabelling a set row and the ring from outside; decorative parts hidden (icon beside text, rules, the header's hidden check, the ring's arcs, the icon button's glyph); a button accessory inside an action-less HairlineRow stays reachable and fires; disabled pills report `.notEnabled` |
| `ComponentLayoutAdversarialTests.swift` | `RenderingSuites` (iOS) | At large, xxxLarge, AX1, AX3 and AX5, regular and Bold Text. **Truncation**: two views that differ only in their last character must render differently ("1,002.5" / "1,002.0"; "102.5"; reps "12"; set label "12"; a 45-character exercise name with a detail and an accessory; a long `PrimaryButton` title with an icon; a long pill; a long eyebrow). A positive control shows the probe sees a real cut ("1,002,002,002,002.5" at AX5). **Width**: a set row "12 · 1,002.5 × 12", steppers "2.5 kg" / "1 rep" and the header stay within the 350 pt content width. A disabled `PrimaryButton` looks disabled |
| `ComponentContrastAdversarialTests.swift` | `nonisolated` (iOS) | Every text/background pair the components introduce (4.5:1; 3:1 for the bold CTA label per Pete), and the non-text marks that identify a control or its state (WCAG 1.4.11, 3:1): the check's pending ring, active ring, done disc and done tick, and the glyphs. On ground and surface, light and dark, with and without Increase Contrast (resolved through SwiftUI's environment; a sanity test confirms `inkMuted` resolves to .74 under Increase Contrast) |

Two first-draft assertions were dropped once the implementation notes showed them to be documented decisions (below):
the ring's arc on paper, and a disabled look for `PillButton` / `IconPillButton`. The first iteration run still had
them: arc 2.65:1 on paper, and disabled pills and the icon button pixel-identical to enabled in both schemes. One
test was wrong and was fixed. At fractional ring sizes (xSmall, xLarge, xxxLarge) `ImageRenderer` leaves the image's
outer pixels partly transparent, so "ink = unlike pixel (0, 0)" counted the whole ground. It now counts opaque pixels
unlike `#0B0B0D`. A temporary probe that attached renders for an eye check (set rows at xxxLarge to AX5, the ring
with "10:00", a long HairlineRow) was deleted before the gate.

## Results

| Run | Result |
|---|---|
| `LedgerDesignTests` alone on iOS 27.0 via the lock (iteration) | 197 cases. Failures: this round's findings, the two documented items above, and the test fault above (fixed) |
| Slice-2 adversarial suites plus the probe on iOS via the lock (iteration) | 16 of 17 passed. The failure is S2-4. The frame test passes at all six sizes, and the positive control sees the cut |
| `scripts/check.sh`, full, **once**, via the lock (`scratchpad/f06s2-g2-check.log`; waited 372 s) | Steps 0–2 green: tools, format, lint (my four files included), package graph and pins, every `scripts/tests/*.test.sh`. **Step 3, PR plan on iPhone 17 / iOS 27.0: 892 tests, 885 passed, 2 skipped, 5 failed. The five are this round's red tests (S2-1 × 2, S2-2, S2-3, S2-4).** Every existing suite passed, including all 44 slice-2 snapshot references and `LedgerUITests/Smoke`. Longest case 5.93 s (`Smoke`); longest `LedgerDesignTests` case 0.68 s. No retry. `set -e` stopped the script before step 4 |
| Step 4 by hand (`scratchpad/f06s2-g2-step4.sh`: check.sh's own build, boot, test and `check-test-results.sh` lines), via the lock | PR-Watch on Apple Watch Series 12 (46 mm) / watchOS 27.0: 827 tests, 825 passed, 2 skipped, 0 failed; 8 of 8 targets. `RestRingGeometryAdversarialTests` 5/5 |
| Step 5 by hand: `scripts/coverage-gate.sh` on both bundles | Exit 0. LedgerDesign 96.20 % (887 / 922), overall 98.01 % |
| `scripts/check.sh --fast` | OK: 687 host tests. My files compile for macOS too |

## S2-1. A done set sounds like a pending one, and "selected" means two things — design question (accessibility)

Repro (iOS 27.0): `ComponentAccessibilityAdversarialTests.setRow_doneRow_isDistinguishableFromPending` and
`setRow_doneCheck_saysDoneInWords`, on `SetRow(number: "2", weight: "185", reps: "5", state: s, checkLabel: "Log set 2")`.

| State | Row element (selects the set) | Check element |
|---|---|---|
| pending | "2, 185, 5", no value, button | "Log set 2", no value, button |
| active | "2, 185, 5", button + **selected** | "Log set 2", button |
| done | "2, 185, 5", button (**same as pending**) | "Log set 2", button + **selected** |

A sighted lifter sees a done set at once: muted numbers and a filled orange disc. VoiceOver gives no sign of it on the
row, and on the check the only sign is "selected", the word the row next to it uses for "active". The check's label
also stays "Log set 2" on a set that is already logged, where activating it un-logs the set. The done state is
announced, as the brief asks, but only as an ambiguous trait. Options: a value on the row ("Done", "Current set"), a
value or `.isToggle` on the check, or a check label per state (`checkLabel` could take the state).

## S2-2. The steppers are adjustable with no value — minor bug (accessibility)

Repro: `ComponentAccessibilityAdversarialTests.steppers_adjustable_haveAValue`. Both elements are "5 lb" / "1 rep" with
the adjustable trait and an empty value. VoiceOver announces an adjustable element's value after each swipe, so a
swipe up on "5 lb" changes the weight and says nothing about it; the new weight is in the row above, which VoiceOver
is not on. The label names the step, not the quantity ("Weight"). `SetRowSteppers(weightStep:repStep:onWeight:onReps:)`
has no input for a value, so F10 cannot supply one. Suggested: label "Weight" / "Reps", value the current weight and
reps, and the step as a hint.

## S2-3. A set row cannot be given a spoken label, and an outer label renames the check — minor bug (accessibility API)

Repro: `ComponentAccessibilityAdversarialTests.setRow_outerLabel_relabelsTheRowOnly`. VoiceOver reads the row as its
bare strings, "2, 185, 5", with no units; a drop set reads "D, 155, 5". A feature's natural fix,
`SetRow(…).accessibilityLabel("Set 2, 185 pounds, 5 reps")`, reaches **both** elements: the check is then read as
"Set 2, 185 pounds, 5 reps" too, and loses "Log set 2". The component takes `checkLabel` but has no equivalent for the
row. By contrast, `RestRing` is one element, and relabelling it from outside works
(`restRing_outerLabel_replacesTheClockLabel`, held). That matters because VoiceOver reads a bare "2:30" like a time
of day. Suggested: a `rowLabel` (or `accessibilityLabel:`) parameter beside `checkLabel`.

## S2-4. The done check's orange disc is 2.65:1 on paper — design question (WCAG 1.4.11, light scheme)

Repro: `ComponentContrastAdversarialTests.nonText_meetsThreeToOne`, case "SetRow check, done disc: accent on ground":
light 2.65:1, and 2.65:1 with Increase Contrast, which leaves the accent family alone. It passes on the white card
(3.10) and in dark (6.34 ground, 5.98 sheet). Slice 2's decision 1 raises the pending and active rings to ≥ 3:1
because "the set row's check is the only mark of its control". In the done state that mark is the `accent` disc,
and on paper it falls below the same bar. The white tick inside is 3.10:1 against the disc, so the state can be read
from the tick. The control's outline cannot. Options: accept it (the tick carries the state; record it next to the
ring-arc exemption), ring the done disc in `accentText` on paper (5.14:1), or fill it with `accentText` on paper
(the tick would then be 6.03:1). Only light mode is affected.

## S2-5. The snapshot tests never show a pressed control, Increase Contrast, or light at AX5 — minor (test coverage)

Repro: `grep -rn "isPressed\|accessibilityContrast\|increasedContrast" LedgerKit/Tests/LedgerDesignTests/ComponentSnapshotTests.swift`
finds nothing. The galleries cover every other state asked for (disabled `PrimaryButton`; pending, active and done set
rows; the drop set "D"; every pill style; full, half and empty rings), in the 6-image matrix plus AX5 and Bold Text
sheets. Not covered:
- **Pressed**: `LedgerPressStyle`'s 0.6 dimming is in every button and in no test. `ButtonStyleConfiguration` cannot
  be built in a test, so this needs a seam (for example an internal view that takes `isPressed`).
- **Increase Contrast**: `hairline` and `hairlineStrong` step up to .20 / .30. Those are every rule, outline, pill
  border and the ring's track, and no component render shows them.
- **Light scheme at AX5 or with Bold Text**: both extra sheets are dark only.

## Documented, not re-raised

- The ring's `accent` arc is 2.65:1 on paper and 1.98:1 against its own light track. Decision 1 exempts it: the
  countdown carries the same information.
- `PillButton` and `IconPillButton` have no disabled look (decision 7). Measured: pixel-identical to enabled in both
  schemes; VoiceOver says "dimmed" (`disabledSecondaryButtons_areNotEnabled`, held). `LedgerPressStyle`'s doc comment
  ("the label draws its own idle and disabled looks") is true only of `PrimaryButton`.
- The ring label is `numeralS` (700 15) against the prototype's 500 16 (decision 2); the prototype's track is .12
  against `hairlineStrong` .14.

## Attacked and held

- **Ring geometry against the prototype.** For 500 seeded progress values the arc starts at (32, 3) and ends within
  0.25 pt of the SVG dash's end. The prototype's 182 dash on a 182.21 circumference accounts for up to 0.21 of that.
  Start at 12 o'clock and clockwise direction match `rotate(-90deg)` on an SVG circle. Tiny progress draws at most a
  dot at 12 o'clock, never a full or reversed ring. −0 and signalling NaN draw nothing, and the largest finite value
  draws the full 58 × 58 ring. `1.0.nextDown` ends at 12 o'clock, and 0.99 ends just left of it. Below 0, above 1,
  ±∞ and NaN are already covered by `RestRingGeometryTests`.
- **Ring as drawn, xSmall to AX5, both schemes.** Nothing lands in the padding: the stroke stays inside its frame
  with margin, and the ring is centred to within 1 px. The quarter and three-quarter direction checks, and half as
  the right half at 0.5 ± 0.05 of a full ring's orange, all hold at every size. "2:30", "10:00" and "0:05" stay
  inside the track's inner edge by more than 1 pt, on one line, up to AX5.
- **Reduce Motion.** No component animates on its own: there is no `.animation` or `withAnimation` in `Components/`.
  `RestRingArc` sweeps only when a caller animates it, so honouring Reduce Motion is F10's job.
- **Hit targets and labels at xSmall, xxxLarge and AX5.** All 12 tappable cases hold, and the steppers are 44 pt tall
  at every size. Decorative icons, rules, the header's hidden check and the ring's arcs are hidden. A `PillButton`
  inside an action-less `HairlineRow` stays a reachable button and fires.
- **Dynamic Type through AX5, with and without Bold Text.** Nothing in the truncation list is cut, and the positive
  control proves the probe can see a cut. Set rows, steppers and the header stay within 350 pt. Observed by eye: at
  AX5 a four-digit weight shrinks to about half its scaled size beside full-size reps. That is decision 5's 0.5
  floor, and it is still larger than at the default size.
- **Contrast.** Every text pair holds in both schemes, with and without Increase Contrast. Lowest: `inkMuted` on
  paper, 4.83:1. The rest: `accentText` 5.14 on paper, 6.34 on dark; the filled pill's ground on ink, 15.6 / 17.6;
  white on accent, 3.10, which holds under Pete's 3:1 rule for the bold label. Non-text marks: pending ring ≥ 4.83,
  active ring ≥ 5.14, done tick 3.10, glyphs (`inkSecondary`) ≥ 6.74. The one exception is S2-4.
- **Tokens only (review).** Colour, type, spacing, radius and hairline all come from tokens. The remaining raw numbers
  are named, sourced component dimensions inside `LedgerDesign`: 54 pt CTA, 44 pt target, ring 64 / 29 / 2.5, the
  icon grid and stroke widths, the 22 / 12 label column, 0.6 pressed opacity, 1.3 Bold Text stroke and the 0.5 scale
  floor.
- **Criteria 5 and 6** hold beyond their own tests: the rendered half ring at every size and in both schemes, and
  `PrimaryButton`'s label, button trait and 44 pt target at xSmall, xxxLarge and AX5.
- **Previews compile.** `Components+Previews.swift` builds in the gate's Debug builds for iOS and watchOS.
- **Isolation.** The two value suites are `nonisolated`, and the three rendering suites sit under `RenderingSuites`.
  The only randomness is seeded.

Verdict: criteria 3, 5 and 6 hold for slice 2, and the geometry, layout, hit targets and token use have no bugs. The
slice is not ready to close: two minor accessibility bugs (S2-2, S2-3) and two design questions (S2-1 on the done-state
announcement, S2-4 on the light-mode done disc) need a fix or Pete's call, and S2-5 is a test-coverage gap.

# Slice 2 — round 2 (close-out, `e085375`)

Scope: fix round 1 only (implementation notes, "### Slice 2 — fix round 1"; `git show e085375`): the VoiceOver
strings, the stepper values, the done disc in `accentText`, the `.contain` boundary on the check, the pressed seam and
the five new references. Pete's rules applied: WCAG AA with the look kept, and Bold Text followed. The design lint is a
frozen tripwire, so no spellings were hunted. Toolchain: Xcode 27.0, iPhone 17 and Apple Watch Series 12 (46 mm) on
27.0.

## What was written

- `Adversarial/SetRowContainerAdversarialTests.swift` (`RenderingSuites`, iOS): two functions, four cases. It reads the
  accessibility containers above each element, which `accessibilityElements` flattens away: a positive control with no
  outer label (passes), and S2-6 in the pending, active and done states (red).
- A temporary probe, deleted before the gate. It dumped UIKit's whole tree, containers included, for each SetRow state,
  with and without an outer label and hint, and for `SetRowGallery` at light large and dark AX5. It drove three stepper
  harnesses (lb, kg, no value) and a live row through `accessibilityIncrement` / `Decrement` / `Activate`, and read
  the values back from the same element objects VoiceOver holds.
- The new and re-recorded references were opened and sampled pixel by pixel with a CoreGraphics tool (scratchpad
  `s2r2/px`). The three changed `setRow_appearance` light references were diffed against `4543e13`.

## Results

| Run | Result |
|---|---|
| `LedgerDesignTests` alone on iOS 27.0 via the lock (iteration, with the new file) | 208 cases: 206 passed, 1 skipped, **1 failed: S2-6** in all three states. The positive control passes. Every fix-round test and every round-1 adversarial test passes |
| `scripts/check.sh`, full, **once**, via the lock (`scratchpad/f06s2-closeout.log`) | Steps 0–2 green: tools, format, lint (my new file included), package graph and pins, every `scripts/tests/*.test.sh`. **Step 3, PR plan on iPhone 17 / iOS 27.0: 901 tests, 898 passed, 2 skipped, 1 failed. The failure is S2-6's red test (three arguments).** Every other test passed, including the five new and three re-recorded references. `set -e` stopped the script before step 4 (193 s; the lock was free) |
| Step 4 by hand (`scratchpad/s2r2/step4.sh`: check.sh's own build, boot, test and `check-test-results.sh` lines), via the lock | PR-Watch on Apple Watch Series 12 (46 mm) / watchOS 27.0: 827 tests, 825 passed, 2 skipped, 0 failed; 8 of 8 targets |
| Step 5 by hand: `scripts/coverage-gate.sh` on both bundles | Exit 0. LedgerDesign 96.39 % (936 / 971), overall 98.05 % |

## Close-out of S2-1 to S2-5

| # | Status | Evidence |
|---|---|---|
| S2-1 | **Resolved** | The row's value is "Current set" when active, "Done" when done, and empty when pending. The row is never selected. The check is selected only when done, and then its value is "Done" (probe, `setRow_state_isSpokenInWords`, round 1's two tests green). On a live row, activating the check turns the same element object to "Log set 2", "Done", selected, in place. The label stays "Log set 2" on a logged set. That is the caller's `checkLabel`, which F10 can word per state, so it is not re-raised |
| S2-2 | **Resolved when the caller passes a value; still open without one (S2-7)** | lb: "185 pounds", then "190 pounds" after an increment. kg: "82.5 kilograms", then "85.0 kilograms". Reps: "2 reps", then "1 rep", then "0 reps". All were read from the same element object, which the re-read returned identically, so VoiceOver keeps focus on it. Without a value, the value is the step and never changes (S2-7) |
| S2-3 | **Resolved for the two elements; the label leaks one level up (S2-6)** | `.accessibilityLabel(…)` from outside renames the row, keeps its state value ("Done", "Current set") and leaves the check "Log set 2". But the same label now sits on the check's new container |
| S2-4 | **Resolved** | The disc is `#B2390E` on paper (sampled in `setRow_appearance…light-large` and the light Increase Contrast sheet) and `#FF5B22` in dark. It is at least 3:1 on every background (table under "Attacked and held"). The re-recorded light references differ from `4543e13` only inside the disc: x 339–369, y 94–124 at large, x 338–369, y 93–124 at xLarge, x 328–375, y 91–139 at AX3 |
| S2-5 | **Resolved** | Pressed and Increase Contrast are really drawn, and light AX5 is covered (pixel evidence under "Attacked and held") |

## Audit of fix round 1's test edits

- `ComponentContrastAdversarialTests.nonText`: the done disc and tick pairs now name `accentText`. **Accept.** They name
  the colour the check now draws, and the bar, grounds, schemes and Increase Contrast are unchanged. This value test
  would not notice a revert to `accent`, but the three light `setRow_appearance` references would, since they pin
  `#B2390E`. No other file of mine was touched (`git show --stat e085375`).
- `ComponentAccessibilityTests`: SetRow and stepper tests moved out, and `expectButton` / `expectTarget` became
  internal. **Accept.** Nothing was lost. The dropped `.selected` checks live on in `setRow_state_isSpokenInWords`,
  which is stricter (the row is never selected).
- `SetRowAccessibilityTests.setRow_accessibility_rowAndCheckAreButtons`, `setRow_activation_callsTheMatchingAction`,
  `setRowSteppers_accessibility_twoAdjustableSteppers`, `setRowSteppers_adjust_stepsTheMatchingValue` (moved): **Accept.**
- `setRow_state_isSpokenInWords`: **Accept.**
- `setRow_outerLabel_namesTheRowOnly`: **Accept as far as it reaches.** It reads leaf elements only, so it cannot see the
  label landing on the check's container (S2-6).
- `setRowSteppers_value_isTheCurrentQuantity`: **Reject the second half.** It asserts that a stepper without a value has
  its label as its value (`["5 lb", "1 rep"]`), which pins the duplicate in S2-7. The first half is accepted.
- `setRowSteppers_adjust_changesTheAnnouncedValue`: **Accept.** The probe adds what its re-read hides: the value changes
  on the same element object, and the re-read returns that object.
- `ComponentSheetSnapshotTests.allComponents_pressed_…`, `…_increasedContrast_…`, `setRow_lightAccessibility5_…`:
  **Accept.** The pixels show the states are real (below).
- `LedgerSnapshotTesting.withLiveAccessibilityElements`: **Accept.** It is test support, and `withAccessibilityElements`
  keeps its behaviour on top of it.
- Round 1's own `steppers_adjustable_haveAValue` was not edited. It now passes only on S2-7's fallback. It was written
  before the API could take a value. The S2-7 fix may edit its call to pass one, and I accept that edit in advance.

## S2-6. A label set on a SetRow from outside also labels the container around its check — minor bug (accessibility)

Repro (iOS 27.0): `SetRowContainerAdversarialTests.setRow_outerLabel_doesNotLabelTheCheckContainer`, red in the pending,
active and done states. The fix for S2-3 stops the outer label at `.accessibilityElement(children: .contain)` on the
check. It stops there by landing on the container that modifier creates. The probe's tree for
`SetRow(… .done …).accessibilityLabel("Set 2, 185 pounds, 5 reps")`:

| Node | Element | Label | Value | Container type |
|---|---|---|---|---|
| row button | yes | "Set 2, 185 pounds, 5 reps" | "Done" | none |
| the check's container | no | **"Set 2, 185 pounds, 5 reps"** (and an outer hint too) | — | `semanticGroup` (4), `shouldGroupAccessibilityChildren` |
| └ check button | yes | "Log set 2" | "Done", selected | none |

Without an outer label the container is unlabelled. That case is the positive control, and it passes. With one, the
row's words are on a labelled semantic group that VoiceOver moves into on its way to the check. UIKit's documentation
for `semanticGroup` says assistive technologies may read the container's `accessibilityLabel` "to output appropriate
information about the semantic group". Apple's `.contain` example labels its containers ("Users", "Messages"). WWDC21
10119 adds that these containers join VoiceOver's Containers rotor. So the set is likely spoken twice in a
row: "Set 2, 185 pounds, 5 reps, Done, button", then the same words again before "Log set 2". This was not heard on a
device this round; the tree state is measured. The doc comment on `SetRow` says the outer label "stops at the row",
which the tree contradicts. `.contain` also puts every check alone in the Containers rotor, so that rotor jumps from
check to check and skips the rows. The fix round's probe found `.contain` to be the only boundary an outer label
respects, so the likely fix is S2-3's first suggestion: a spoken-label parameter on `SetRow` (for example
`accessibilityLabel:` beside `checkLabel`) applied to the row button inside the component, with no outer label and no
`.contain` needed.

## S2-7. A stepper without a value repeats its label as its value, and a swipe changes nothing VoiceOver says — minor bug (accessibility API)

Repro: the fix round's own `setRowSteppers_value_isTheCurrentQuantity` asserts that
`SetRowSteppers(weightStep: "5 lb", repStep: "1 rep") { _ in } onReps: { _ in }` has values `["5 lb", "1 rep"]`: label
"5 lb", value "5 lb". In the probe, a harness that omits the value moved its weight 185 → 190 → 180 (one increment,
two decrements), and the element's value stayed "5 lb" throughout. That is S2-2 exactly: the swipe changes the weight, and VoiceOver
repeats the step. It also says the step twice ("5 lb, 5 lb, adjustable"). `weight` and `reps` are optional with a `nil`
default, so this is the API's default path, and F10 gets it silently by leaving them out. There is no new red test: the
fix is an API shape (required parameters), which a runtime test cannot pin without failing to compile afterwards. The
assertion above is the repro. Suggested: make `weight` and `reps` required and drop the fallback. My round-1 call and
the fix round's no-value calls then pass values.
Design question folded in: with a value, the label is still the step, so VoiceOver reads "5 lb, 185 pounds, adjustable"
and "1 rep, 5 reps, adjustable". S2-2 suggested "Weight" / "Reps" as the label, with the step as a hint. That half was
not taken, and a listener has to work out which of the two numbers is the weight.

## Attacked and held (round 2)

- **"Current set" and "Done" on the right elements.** The active row says "Current set" and its check says nothing extra.
  A done row says "Done", and its check says "Done" with `selected`. A pending row and check have no value. This held at
  light large and at dark AX5 in the gallery. "Selected … Done" on one check is redundant, not wrong: round 1's own test
  required the trait.
- **The check's own "Log set N" under `.contain`.** The check is a leaf button labelled "Log set 1/2/3" or "Log drop set",
  44 × 44 at large and 59.3 × 59.3 at AX5, and activation fires `onCheck`. An outer label and hint never reach it.
- **Rotor order through a row.** The swipe order is the same at light large and dark AX5 (steppers stacked): "#", "lb",
  "reps", row 1, check 1, row 2, check 2, the weight stepper, the reps stepper, row 3, check 3, row D, check D. Each
  row's check follows it, and the steppers sit between the active row and the next one. Without an outer label nothing
  new is spoken (S2-6 covers the case with one).
- **Stepper values.** lb and kg both announce the caller's words, and increment and decrement update the value on the
  same element object in both directions. The component passes the caller's words through unchanged: "2 reps", then "1 rep",
  then "0 reps". Singular and clamping are the caller's job.
- **The `accentText` disc**, WCAG 2.x, ≥ 3:1. Increase Contrast leaves the accent family and both grounds unchanged, so
  every row holds with it too:

  | Scheme | Disc | On ground | On surface | On `accentSoft` over ground / surface | White tick on the disc |
  |---|---|---|---|---|---|
  | light | `#B2390E` | 5.14 (paper) | 6.03 (card) | 4.54 / 5.25 | 6.03 |
  | dark | `#FF5B22` | 6.34 | 5.98 (sheet) | 5.32 / 4.92 | 3.10 |

  While a finger is down the whole check is at 0.6. The disc is then 2.62–2.89:1 against the ground, and the light
  tick 1.92–2.04:1 against the dimmed disc. That is transient press feedback over a state already announced, so it is
  noted, not raised.
- **The new snapshots, opened and sampled.** Pressed is real 0.6 compositing. The `PrimaryButton` fill is `#F99670`,
  which is accent at .6 on paper, and the done disc is `#CB8164`. Static parts are unchanged: the rule under a static
  row is `#DEDCD5`, hairline .08. Increase Contrast is real. That same rule is `#C3C2BB` (.20), in dark `#3A3939` against
  `#1E1D1F`. Ring tracks, check rings and outlines are visibly darker, and muted text steps up. The disc is `#B2390E` in
  light and `#FF5B22` in dark. Light AX5: nothing is cut, the steppers stack, and "102.5" shrinks beside a full-size
  "12" (decision 5). One harmless oddity: the pressed sheet also dims the disabled "Save workout", a state a disabled
  button never reaches.
- **Scope of the edit.** Product changes are confined to `SetRow`, `SetRowSteppers`, `ControlStyle`, the previews and
  the snapshot helper. The `ledgerDrawsPressed` key is internal, defaults to off, and only previews and tests set it.

**G2 cannot close yet, because S2-6 is open.** With the outer label that `SetRow`'s doc comment prescribes,
the row's spoken label also sits on a labelled semantic group around the check, where VoiceOver is likely to read it
a second time. S2-7 is open too: the no-value default brings S2-2 back. It needs a small API change, or Pete accepting
the optional default. Everything else in fix round 1 holds. S2-1, S2-4 and S2-5 are resolved; S2-2 and S2-3 are
resolved on their main paths. The disc meets 3:1 everywhere with the tick intact, and the new snapshots really
exercise pressed and Increase Contrast.
