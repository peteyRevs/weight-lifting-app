# F06 slice 1 — review

Branch `feat/F06-design-system` at `aaaaca1`, against `main` (`8404d02`). Scope: tokens, the Archivo variable
font with `wdth` on iPhone and Apple Watch, pixel snapshot support, the design lint. Reviewed against the brief,
engineering-standards, architecture §11/§17, testing-strategy §2.5/§6, and Pete's decisions of 2026-09-27
(WCAG AA keeping the look; Bold Text) and 2026-09-29 (native `.lineHeight` only; the lint as a frozen
tripwire). Those decisions are treated as settled.

What I ran, besides reading the diff:

- `/code-review high` on the diff (bug pass; its nine findings are handled at the end of this file).
- `scripts/check.sh --fast`: **green**. It ran format, lint, the four lint fixture scripts (12/12, 55/55, 39/39,
  44/44 with 11 `limit`), the package graph check, and 419 host tests. I did not run a simulator gate; the
  adversarial tester is running one.
- All 16 references under `__Snapshots__`, opened and inspected.
- Three scratch probes, in the session scratchpad only (no repo edits):
  - a lint probe of Foundation-only code in a `LedgerDomain` path (S2);
  - an `NSHostingController.sizeThatFits` probe of the snapshot sizing (S1);
  - a host micro-benchmark of the per-body font cost (N2).

**Verdict: approve. 0 Blocking, 2 Should fix, 8 Nits.**

---

## Blocking

None.

## Should fix

### S1. The phone snapshot harness truncates text instead of wrapping it, so the matrix hides wrapping at large sizes

`LedgerKit/Sources/LedgerSnapshotTesting/SnapshotConfig.swift:78-80` (`snapshotAppearance`);
`LedgerKit/Tests/LedgerDesignTests/TokenSnapshotTests.swift:13-57`.

**Cause.** swift-snapshot-testing 1.19.6's `.image(layout: .sizeThatFits)` measures the view with
`hostingController.sizeThatFits(in: CGSize(width: 0, height: 0))`. The call is in
`.derivedData/SourcePackages/checkouts/swift-snapshot-testing/Sources/SnapshotTesting/Snapshotting/SwiftUIView.swift:84-85`.
Every `Text` is therefore proposed almost no height, so it keeps one line and truncates.

**Evidence.**
- The committed `phoneTypeRamp_appearance_matchesReference-_.{light,dark}-accessibility3.png` show `display`,
  `title`, `heading` and `bodyLight` ending in "…" ("Train four day…"). On a device these would wrap.
- The implementation notes record the "…" as "not clipping". It is not clipping, but it is not how the text
  lays out on a device either.
- Host probe with `NSHostingController`, 402 pt wide, a 30 pt paragraph:

  | Proposal | Size | Result |
  |---|---|---|
  | `.zero` | 402×90 | one truncated line |
  | `.zero` with `.fixedSize(horizontal: false, vertical: true)` | 402×160 | wrapped |
  | unbounded | 402×160 | wrapped, same as above |

**Impact.** Slice 1's references are test-only specimens, so no slice-1 criterion is false. But the notes tell
slice 2 to put every component on this harness. The criterion 3 matrix at `.accessibility3`, and standards
§12's "Dynamic Type verified at XL", would then record truncation instead of the layout a user sees.

**Fix.** This is test-only code, so it doesn't count against the 500-line budget.
1. Add `.fixedSize(horizontal: false, vertical: true)` inside `snapshotAppearance(_:)`. Better, also add one
   helper in `LedgerSnapshotTesting`, for example `assertPhoneSnapshot(of:_ appearance:named:)`. It would apply
   `snapshotAppearance`, the fixed size, the traits and `SnapshotConfig`'s precisions, so no test can leave
   one out. Today `phoneTypeRamp_boldText` and both palette tests skip `snapshotAppearance`. That is harmless at
   `.large`, but it is the same trap.
2. Re-record the two `accessibility3` ramp references. They are the only ones with truncated lines.
3. Add a harness test: a two-line string at `.accessibility3` renders taller than one line.

The adversarial tester's in-progress round 4 targets the same behaviour: the test "…is as tall as the sheet
(text wraps)" in `Adversarial/SnapshotAppearanceAdversarialTests.swift`, untracked in this worktree while this
review was written. Its result and this finding should be resolved together.

### S2. The design lint's scope reaches modules that cannot import SwiftUI, where every hit is a false positive

`.swiftlint.yml:75, 92, 105, 117` (`included: 'LedgerKit/Sources/.*|Apps/.*'`);
`docs/engineering-standards.md:167`.

**Evidence.** I linted a Foundation-only file placed at `LedgerKit/Sources/LedgerDomain/Probe.swift` with the
repo's `.swiftlint.yml`. It raised **6 errors**:
- `ledger_raw_color` on `return .red`, `return .black`, `[25: .red, 20: .blue]` (a plate-colour enum) and
  `weight(of: .secondary)` (a muscle-role enum);
- `ledger_raw_spacing` on `NameRule(minLength: 2)`.

Standards §2 keeps `LedgerDomain` Foundation-only, and Persistence, Health and Sync are adapters. A raw colour,
font or padding cannot exist there, so every hit in those modules is a false positive. Near-term work will
write exactly these spellings:
- F12's "Name must be 2–40 characters" validator (`minLength:`);
- F03's primary and secondary muscles;
- any plate or band colour enum.

Standards §7's "accepted false positive" note covers feature enums, not domain code.

**Fix.** Narrow `included` to the modules that can draw UI. The four regexes are untouched, so the frozen rule
set stays frozen; this is decision 2's "fix false positives" applied to scope, not a new spelling. Use:
`'LedgerKit/Sources/(Feature\w*|WatchFeature\w*|LedgerAppKit|LedgerWatchAppKit)/.*|Apps/.*'`
(keep the `*design_allowlist` excludes).

Then:
- update the sentence at standards `:167`;
- add a `none` fixture in `LedgerKit/Sources/LedgerDomain` to `scripts/tests/lint-rules.test.sh` (for example
  `return .black` and `minLength: 2`).

If the orchestrator reads "frozen" as covering scope too, this becomes a one-line question for Pete at G5
rather than a change in this PR.

## Nits

**N1. The `.png` comparator uses CIE76, but the comments and docs say it matches the library.**
`LedgerKit/Sources/LedgerSnapshotTesting/PixelSnapshotting.swift:8-10, 66-74`; `docs/testing-strategy.md:173`.
swift-snapshot-testing compares with Core Image's `applyingLabDeltaE` (`UIImage.swift:300`), which is ΔE 1994.
CIE76 is never smaller than ΔE94, so the watch and spike references are held to a stricter tolerance than the
phone ones, most visibly on saturated orange. It can't cause a false pass, only a spurious watch-only failure.
**Fix:** implement ΔE94 (kL = kC = kH = 1, K1 = 0.045, K2 = 0.015; about 8 lines, test-only), or reword both
places: "CIE76 at the library's ΔE threshold, at least as strict as its CIE94".

**N2. `.ledgerFont` builds a new Core Text font on every body evaluation.**
`LedgerKit/Sources/LedgerDesign/Tokens/LedgerFont.swift:153-161`, `Fonts/ArchivoFont.swift:21-38`.
- Measured on this M-series host over 2,000 iterations: `ArchivoFont.make` costs **43 µs** per call and
  `scaledSize` 0.5 µs. So each `.ledgerFont` body evaluation costs about 43 µs.
- That is fine for slice 1. A watch countdown or crown-driven numeral re-evaluates every tick on a much slower
  CPU, and a fresh `CTFont` each time may also defeat SwiftUI's text-layout reuse.

**Fix:** when slice 3 lands the watch components, add a `.performance` test (architecture §15: crown detent
→ next frame) and measure on the watch simulator. If it is over budget, cache by (role, size, weight). A static
cache is global mutable state (standards §3), so decide where it lives then.

**N3. `swift test` on the host fails and writes a stray reference into the source tree.**
`LedgerKit/Sources/LedgerSnapshotTesting/SnapshotConfig.swift:29-39`;
`LedgerKit/Tests/LedgerDesignTests/ArchivoFontTests.swift:65-66`.
- A plain `swift test` (or `--filter LedgerDesignTests`) records
  `widthAxis_88versus112_rendersDifferentGlyphWidths.macOS.png` into `__Snapshots__` and fails.
- `render_sameViewRepeatedly_isPixelIdentical` also fails on macOS (notes, fix round 1).
- A later `git add -A` would commit the stray file.
- The `platform` doc comment says the platform is "part of every reference name"; only the spike's names
  carry it.

**Fix:** guard the snapshot assertion and the host-only failures with `#if os(iOS) || os(watchOS)` or
`.enabled(if: SnapshotConfig.platform != "macOS")`, and correct the comment.

**N4. `check.sh --record-snapshots` reports success for a build that never ran the tests.**
`scripts/check.sh:93-94, 140-143`. `xcodebuild … | beautify || true` swallows a compile error or a failed
simulator boot, and the script still prints "snapshot references recorded". It exits 1 either way, so a broken
build looks like a recording. **Fix:** in record mode, exit with xcodebuild's status when the result bundle
has no test results (for example `[[ -d "$result" ]] || exit 1` after the pipeline), or print "record run
failed before any test ran".

**N5. Criterion 7's evidence stops at the keyframes.**
`LedgerKit/Sources/LedgerDesign/Tokens/LedgerMotion.swift:61-72`. The line that reads
`@Environment(\.accessibilityReduceMotion)` is uncovered, as the notes' coverage section says.
`accessibilityReduceMotion` is get-only in the 26.5 SDK (only the underscored `_accessibilityReduceMotion` is
settable), and `ImageRenderer` can't sample mid-animation. **Fix:** no product change. Add "buzz with Reduce
Motion on shows an opacity pulse, no shake" to F20's device checklist, or to F11's UI smoke test once the
watch uses the buzz.

**N6. Stale header in the round-2 lint script.**
`scripts/tests/lint-rules-adversarial-round2.test.sh:7-8` still says "Not wired into check.sh". It is wired
(`scripts/check.sh:70`). **Fix:** delete the two lines. This is the tester's file, so the tester or the
orchestrator should make the change.

**N7. The brief's public-surface block no longer matches the shipped API.**
`tasks/features/F06-design-system.md:39, 44` still shows `font(_ role: Role) -> Font` and
`static let buzz: Animation`. The notes list these as deviations for the orchestrator. **Fix:** replace them
with `font(_:dynamicTypeSize:legibilityWeight:)`, `font(_:size:legibilityWeight:)`,
`scaledSize(_:dynamicTypeSize:)`, `View.ledgerFont(_:)`, and `buzzKeyframes(reduceMotion:)` plus
`View.ledgerBuzz(trigger:)`.

**N8. A public escape hatch to the unscaled size.**
`LedgerKit/Sources/LedgerDesign/Tokens/LedgerFont.swift:64-79`. `LedgerTypeSpec` and `Role.spec` are
public, so `LedgerFont.font(.body, size: LedgerFont.Role.body.spec.size)` lints clean and drops Dynamic Type.
It is the same class of hatch as `archivo(size:weight:width:)`, already an open point. **Fix:** either:
- add one line to the known-limits list in standards §7; or
- in slice 3, make `spec` internal together with `archivo(…)`, and move the adversarial suites that read it to
  `@testable import`.

## Merge notes (not findings)

- **Conflict with F01.** `feat/F01-ci-gates` and this branch conflict in `scripts/check.sh` (`git merge-tree`).
  F01's step 2 runs `for test in scripts/tests/*.test.sh`, which already picks up the four F06 lint scripts.
  Whichever PR lands second should keep F01's loop and F06's `run_plan` / record-mode block, and drop the four
  explicit lines at `scripts/check.sh:68-71`. Otherwise every lint script runs twice.
- **pbxproj.** `Ledger.xcodeproj` is untouched. The dangling `Fonts` synchronized group (`project.pbxproj:116-119`,
  `path = Resources/Fonts`, referenced from a group and from the `Ledger` and `LedgerWatch` targets) is known;
  Pete removes it in Xcode. Per G5, a pending
  human pbxproj edit is a stop-for-Pete item.

---

## The seven review points

1. **Module boundaries: pass.**
   - `LedgerDesign` imports SwiftUI, CoreText, Foundation, OSLog, and UIKit (iOS only, for the dynamic
     `UIColor`; no UIKit views).
   - It takes no `LedgerDomain` dependency, as the brief requires.
   - `LedgerSnapshotTesting` is test-only.
   - The package graph is unchanged (`check-package-graph.sh` green).
   - The font moved into `LedgerDesign`'s resources, and both `UIAppFonts` point into
     `LedgerKit_LedgerDesign.bundle`.
2. **Concurrency: pass.**
   - Product types are `nonisolated` value types or `Sendable`.
   - `FontRegistration` runs once through a `static let` initialiser (thread-safe), with no locks.
   - No `Date()`, `UUID()`, clocks, `DispatchQueue` or `Task.detached` anywhere in the diff.
   - Test isolation is consistent. The four value-only suites are `nonisolated`: `TokenValueTests`,
     `ContrastAdversarialTests`, `LayoutTokenAdversarialTests` and `LedgerFontSpecAdversarialTests`.
   - Every suite that renders or builds `UITraitCollection`s is nested in
     `@Suite(.serialized) enum RenderingSuites` (`Support/RenderingSuites.swift`).
   - The one async test carries `.timeLimit(.minutes(1))`.
3. **Error handling: pass.** `FontRegistration` logs failures through `os.Logger` (subsystem
   `com.petearevalo.Ledger`, category `LedgerDesign`) and reports a `Bool`; "already registered" counts as
   success. There is no `try?`, `!` or `fatalError` in product code. Test infrastructure turns undecodable PNGs
   into failure messages.
4. **Design fidelity: pass.** Colour tokens match spec §8.1–8.3:
   - `#0B0B0D` / `#131316` / `#F4F2ED`, and `#EFEDE6` / `#FFFFFF` / `#16150F`;
   - accent `#FF5B22`, alphas .72 / .32 / .28 / .08 / .14 / .16 / .12 / .40, and the watch family.
   - The AA changes are Pete's decision: `inkMuted` .51 / .62, light `accentText` `#B2390E`, `watchInkMuted`
     .46.

   The 21 type roles match the `font:` declarations in `Ledger v2.dc.html` and `LedgerWatch.dc.html`, checked
   one by one: display 600 38/1.06 wdth 98 −.035; heading 600 27/1.08 −.032; numerals 700 wdth 88/90 with
   tabular figures; eyebrow 500 10 .18em; watch 64/.86, 52, 30, 20/1.12, 21, 17 ÷ 1.5. The only change is
   `button` 600 → 700, from the AA decision. The snapshots look right:
   - the spike sheet shows five distinct widths, identical on iOS and watchOS;
   - the light and dark ramps and palettes, the Increase Contrast palettes, the Bold Text ramps and the watch
     sheets all render as expected;
   - no clipping at `.xLarge`.

   The one defect is S1's truncation at `.accessibility3`. `watchNumeral`'s figures sitting below its frame is
   decision 1, already recorded for slice 3.
5. **Accessibility: pass.**
   - Dynamic Type: every role scales on SwiftUI's own curve for its text style, with no cap. The tests
     check it against `@ScaledMetric` at all 12 sizes on both platforms.
   - Bold Text: +100 `wght` on both the `.ledgerFont` path and the `Font` path.
   - Contrast: AA on ground, surface and the `accentSoft` tint. Increase Contrast raises text to AAA on iOS.
     `inkFaint` and `inkDim` stay decorative.
   - Watch: an 11 pt floor on every path, tested at `.xSmall` and at the 41/42/45/46 mm default sizes.
   - `textCase` is applied at display time, so VoiceOver reads the original string.
   - HIG's 12 pt watch minimum is still an open point for Pete.
6. **Test quality: pass, with S1, N3 and N5.**
   - Assertions are behavioural: resolved colours, rendered pixels, `KeyframeTimeline` samples, and Core Text
     axis values read back.
   - No sleeps or wall-clock time. Randomness is seeded (`SplitMix64`, 40 seeds).
   - The 1,008-render matrix is `.slow` and runs only in the nightly lane; `Nightly*.xctestplan` set
     `LEDGER_TEST_LANE=nightly`.
   - Remaining flakiness vectors are the known host-only ones (N3).
   - The retargeted line-box tests compare `.ledgerFont` with the same font plus native `lineHeight`. That is
     close to tautological, but it pins decision 1's contract that "`.ledgerFont` moves nothing".
7. **Brief compliance: pass for slice 1.** See the table below.

## Additional checks

- **500-line budget: 490, confirmed.** `git diff --numstat main...HEAD` on `LedgerKit/Sources/LedgerDesign/**/*.swift`
  gives +486 −4. The font and OFL moves are 100 % renames. By category:

  | Category | Changed lines |
  |---|---|
  | `LedgerSnapshotTesting` (test-only) | 333 |
  | Build and config (`Package.swift`, two plists, `.swiftlint.yml`, `check.sh`, `lefthook.yml`) | 143 |
  | `scripts/tests` | 567 |
  | `LedgerDesignTests` | 3,503 |
  | docs and tasks | 1,466 |

  Standards §10 excludes tests and snapshots but says nothing about config. Under the strictest reading,
  product plus config is 633. The orchestrator's measure (product Swift) is met.
- **Scripts: correct.**
  - The four fixture scripts lint throwaway trees with the repo's config.
  - Rounds 2 and 3 parse one JSON report and fail if it doesn't parse.
  - `limit` cases fail if a rule starts flagging them, which keeps standards §7's list true.
  - `lint-rules.test.sh` fails loudly when SwiftLint produces nothing, because its positive checks fail. Its
    "passes inside LedgerDesign" check would pass on empty output, but the positives guard that.
  - `check.sh`'s `run_plan` keeps `set -e`/`pipefail` behaviour outside record mode (N4 covers record mode).
- **Ledger.xcodeproj: not touched.** The dangling group is known (merge notes).

## `/code-review high`: what happened to its nine findings

| Code-review finding | Disposition |
|---|---|
| pbxproj `Fonts` group points at a deleted folder | Known; Pete removes it (merge notes) |
| CIE76 comparator vs the library's CIE94 | N1 |
| Lint scope covers non-UI modules | S2 (verified with a probe) |
| `.ledgerFont` rebuilds the font every body | N2 (measured) |
| `identifier_name` exclusion of `xs…xl` is repo-wide | Accepted: a file-level disable would add a lint suppression (DoD "no new lint suppressions"); recorded in the config comment |
| Record mode hides build failures | N4 |
| `SnapshotConfig.platform` / a macOS reference on `swift test` | N3 |
| `lint-rules.test.sh` starts SwiftLint 12 times | Rejected: the whole lint step takes 6 s in `--fast` |
| Buzz keyframe tracks that stay constant | Rejected: equal-length tracks keep the duration identical in both modes, which criterion 7's tests rely on; the cost is negligible |

## Criteria → evidence

| # | Criterion | Slice | Evidence |
|---|---|---|---|
| 1 | Spike: `wdth` 88 vs 112 differ on iOS 26.5 **and** watchOS 26.5 | 1 | `ArchivoFontTests.widthAxis_88versus112_rendersDifferentGlyphWidths` (> 1.15× on each simulator, plus `.iOS`/`.watchOS` reference sheets); `ArchivoFontAdversarialTests.archivo_widthAxis_growsMonotonically`, `…_matchesFileReference`; recorded in `implementation-notes.md` and architecture §17 risk 2 (closed, no fallback). `CTFontDescriptor` in place of `UIFontDescriptor` is a documented deviation (toll-free bridged) |
| 2 | `LedgerColor` light and dark hex values match §8.1–8.3 | 1 | `TokenValueTests` (dark, light, watch; watchOS stays dark); `LedgerColorAdversarialTests` (via `UIColor.resolvedColor`, the literal wording, and via rendered pixels); `IncreaseContrastTests`. The AA deviations are Pete's decision |
| 3 | Every component × {light, dark} × {L, XL, AX3} at iPhone 17 width | 1 (infra), 2–3 (components) | Harness: `SnapshotAppearance.phoneMatrix`, `SnapshotConfig` (0.995 / 0.98, 402 pt, 1×), `SnapshotHarnessAdversarialTests.phoneMatrix_coversCriterionThree`. Exercised by `TokenSnapshotTests.phoneTypeRamp_appearance_matchesReference` (6 references). **S1 must be fixed before components record references** |
| 4 | Watch components at 42/46/49 mm: no label < 11 pt, nothing clips | 3 | Slice 1 lays the floor: `TypeScaleTests.watchLabel_smallestTextSize_staysAtElevenPoints`, `WatchTypeFloorAdversarialTests` (41/42/45/46 mm default sizes, the explicit-size path), `WatchSize`. Components and the 42/49 mm snapshots are slice 3 |
| 5 | `RestRing(progress: 0.5)` covers half the circumference | 2 | Deferred (`RestRingGeometryTests`) |
| 6 | `PrimaryButton` label, `.isButton` trait, 44 pt hit target | 2 | Deferred (`ComponentAccessibilityTests`) |
| 7 | Reduce Motion: no transform, opacity pulse instead | 1 | `MotionTests` (every ms: offset 0, opacity min 0.4; ±3 pt shake otherwise; 3 × 0.38 s), `LedgerMotionAdversarialTests` (CSS keyframes and `ease`, one pulse per cycle), `ledgerBuzz_atRest_rendersUnchanged`. Modifier wiring: N5 |
| 8 | Raw `Color(red:)`, `.font(.system(size:))`, `.padding(13)` fail the `ledger_raw_*` rules in a feature; pass in `LedgerDesign` | 1 | `scripts/tests/lint-rules.test.sh` (4 rules × feature / app shell / `LedgerDesign`, 12/12), adversarial rounds 1–3 (55 + 39 + 44 cases, 11 documented `limit`s), all in `check.sh` step 2; rules and known limits listed in standards §7. S2 narrows the scope |
| 9 | `DesignGallery` shows every component and token by name | 3 | Deferred |
| NFR | References ≤ 6 MB, 1× PNG | 1 | 16 PNGs, 864 KB |
| NFR | Font registered once, < 5 ms | 1 | `static let` once-initialiser; notes measure 1–3.5 ms on the app path (7–33 ms only for previews and package tests, where the system hasn't registered it). No timing test, which is correct given the flakiness policy |
| NFR | Informational text ≥ 4.5:1; .32 decorative | 1 | `ContrastAdversarialTests`, `AccentChipContrastAdversarialTests`, `IncreaseContrastAdversarialTests` |

## Verdict

**Approve: 0 Blocking.**

- S1 is a test-harness change with no product-budget cost and should land in this PR, before slice 2 records
  any component reference.
- S2 is a scope change to the lint config. It should land here too, or go to Pete at G5 if "frozen" is taken to
  include scope.
- The Nits can go to slice 2 or 3, or to the orchestrator (N6, N7).

---

## Slice 2

Branch `feat/F06-slice2-components` at `e085375`. Scope: `git diff chore/F32-xcode-27...HEAD` (merge base `ac2a08a`).
F32's files are reviewed separately (PR #10) and ignored here. In scope: the phone components (`PrimaryButton`,
`PillButton`, `IconPillButton`, `Eyebrow`, `HairlineList` / `HairlineRow` / `HairlineRule`, `SetRow` + `SetRowHeader`
+ `SetRowSteppers`, `RestRing`, `LedgerIcon`, `ControlStyle`), the test helper `AccessibilityElements.swift`, 49 new
references, and fix round 1 (S2-1 to S2-5). Reviewed against the brief (criteria 3, 5 and 6, and Pete's decisions of
2026-09-29), the slice plan, engineering-standards §7 and §10, architecture §11, testing-strategy §2.5 and §6, and
Pete's standing rules (WCAG AA while keeping the look; follow Bold Text). Findings are numbered R2-… so they don't
collide with slice 1's S1/N1 or the tester's S2-1 to S2-5.

What I ran, besides reading the diff:

- `/code-review high` on the slice-2 diff. It returned 10 findings; their dispositions are at the end.
- `scripts/check.sh --lint-only` fails, but only on `LedgerKit/Tests/LedgerDesignTests/Adversarial/ZZS2R2Probe.swift`. That
  file is untracked, belongs to the tester's in-progress round 2, and is not in the diff, so I left it alone. On the diff's
  22 committed Swift files:
  - SwiftFormat `--lint`: 0 of 22 need formatting.
  - SwiftLint: clean.
  - All six `scripts/tests/*.test.sh`: OK.
  - `check-package-graph.sh`: matches.
- No simulator run, because the tester holds the lock. The gate evidence is the implementer's full `check.sh` on
  Xcode 27 (notes, fix round 1): iOS 899 tests with 0 failed, watchOS 827 with 0 failed, LedgerDesign coverage 96.39 %.
- I opened 12 references:
  - `setRow_…` dark-large, light-large and dark-AX3, and the light AX5 SetRow sheet;
  - `hairlineList_…` dark-large and light-AX3;
  - `primaryButton_…dark-large`, `restRing_…dark-large`, `pillButton_…light-large`;
  - the Bold Text, AX5 and Increase Contrast (light) sheets.

  I compared them with `Ledger v2.dc.html`:
  - markup: the Today CTA and RECENT rows, the set grid and steppers, the rest card, the swap sheet, the filter chips;
  - script: the `rows` colour mapping and `restOffset2`.

  I also compared the icon idiom with `LedgerTabs.dc.html` / `LedgerTabsDark.dc.html`: 24-point grid, `fill:none`,
  round caps and joins, stroke 1.9.
- A scratch SwiftPM probe, kept in the session scratchpad with no repo edits: isolated conformances under
  `.defaultIsolation(MainActor.self)`, Swift 6.4 (R2-S1).
- Size, counted with a script that skips blank and comment-only lines: **700 code lines** in
  `LedgerDesign/Components/`, which confirms the notes. `AccessibilityElements.swift` has 100 test-only lines.

**Verdict: approve. 0 Blocking, 3 Should fix, 11 Nits.**

### Blocking

None.

### Should fix

#### R2-S1. Four public value enums are main-actor-isolated, so their `Equatable` can't be used off the main actor

`LedgerKit/Sources/LedgerDesign/Components/SetRow.swift:3` (`SetRowState`), `PillButton.swift:7` (`Style`),
`Eyebrow.swift:6` (`Tint`), `SetRowSteppers.swift:10` (`Direction`).

**Cause.**
- `LedgerDesign` builds with `.defaultIsolation(MainActor.self)`.
- These four enums are not marked `nonisolated`. The value types that are marked include slice 1's types and this
  slice's own `LedgerIcon`, `RestRingGeometry`, `LedgerHitTarget` and `SetRowSpeech`.
- So the four enums' synthesized conformances are main-actor-isolated (SE-0470).

**Evidence.** A probe package with the same settings on Swift 6.4:

| Code in a second MainActor-default module | Result |
|---|---|
| `nonisolated func isDone(_ s: SetRowState) -> Bool { s == .done }` | error: main actor-isolated conformance of 'SetRowState' to 'Equatable' cannot be used in nonisolated context |
| `nonisolated struct RowModel: Equatable, Sendable { var state: SetRowState }` | same error |
| `a == b` on `PillButton.Style` inside an `actor` | same error (actor-isolated context) |
| all three, with `nonisolated` on the enums | builds |

**Impact.** F10's nonisolated presentation values, and its value-only suites, can't compare a set's state. Testing-strategy
and slice 1 make value-only suites `nonisolated`. The compiler catches it rather than a user, but F10 would then have to
reopen `LedgerDesign`.

**Fix.**
- Declare all four as `public nonisolated enum …`. There is no behaviour change.
- Add a `nonisolated` test that compares a value of each type. It works as a compile-time guard, for example a small
  `ComponentValueTests`, or a case in `RestRingGeometryTests`.

#### R2-S2. A filled `PillButton` means "selected", but VoiceOver isn't told

`PillButton.swift:3-4` (the doc calls `.filled` "the selected filter"); `:21-33`.

**Evidence.**
- In v2 a filled pill only ever marks the selected Library filter or jump chip (script:
  `bg: s.filter === f ? TEXT : 'transparent'`).
- The component draws that state but adds no `.isSelected` trait.
- So VoiceOver reads "Chest, button" and "Back, button" the same way. The state is visual only, which fails WCAG
  1.3.1 / 4.1.2 under Pete's AA rule.
- The style that means "selected" belongs to the component, so the trait does too.

**Fix.**
- Add `.accessibilityAddTraits(style == .filled ? .isSelected : [])` on the `Button`, and a line in the doc comment.
- Add one assertion to `ComponentAccessibilityTests.pillButton_accessibility_labelledButtonWithTarget`: `.filled` is
  `.selected`, and the other two styles are not.

If the orchestrator would rather keep `.filled` as a neutral emphasis, the doc must say instead that the caller adds
`.isSelected`. Either way, the contract should be written down before F-Library uses it.

#### R2-S3. The steppers' current values are optional, and without them the step is read twice

`SetRowSteppers.swift:25-26, 43-44`; doc `:7-8`.

**Cause.** S2-2's fix made `weight` / `reps` each stepper's accessibility value, but kept them optional "so the tester's
call still compiles". Without them, the value falls back to the step.

**Impact.**
- Without the values, the element has label "5 lb" and value "5 lb". VoiceOver reads "5 lb, 5 lb, adjustable".
- After a swipe it announces the step again instead of the new weight. That is the S2-2 bug again, reached through
  the default arguments.
- F10 always knows the current weight and reps, so nothing needs the fallback.

**Fix.**
1. Make `weight:` and `reps:` required `String`s, and delete the fallback and its doc sentence.
2. Update the call sites:
   - the tester's `Adversarial/ComponentAccessibilityAdversarialTests.swift:93, 133` and
     `Adversarial/ComponentLayoutAdversarialTests.swift:140`;
   - this slice's `SetRowAccessibilityTests.swift:87, 109`. Delete the fallback half of
     `setRowSteppers_value_isTheCurrentQuantity`.
3. Handle the tester's files as S2-4 was handled: the orchestrator approves the call-site edits, and no assertion in
   them changes.

### Nits

**R2-N1. A tappable `HairlineRow` wraps an interactive accessory in its own button.** `HairlineRow.swift:29-31, 50`.
- `HairlineRow(…, action: select) { PillButton("Use") { use() } }` puts a button inside a button. VoiceOver merges
  "Use" into the row, and activating it runs `select`.
- The adversarial test covers only the row without an action.
- v2's swap row is a single button with a plain-text "Use", and the gallery reproduces that correctly.

**Fix:** state in the doc comment that with an `action`, the accessory must be non-interactive (text or an icon).

**R2-N2. The done check's label.** `SetRow.swift:17-21, 141`. The doc and the gallery give a done row
`checkLabel: "Log set 1"`, but activating that check un-logs the set. The API already lets a caller pass a label per
state; nothing tells the caller to. **Fix:** give the gallery's done row, say, "Undo set 1", and add to the doc: "pass the
label of what activating it will do". Hearing both "selected" and "Done" is S2-1's accepted outcome.

**R2-N3. The stepper buttons are out of the accessibility tree.** `SetRowSteppers.swift:66`.
- `.accessibilityElement(children: .ignore)` leaves one adjustable element per pill.
- VoiceOver and Switch Control can step it.
- Voice Control ("tap plus") and Full Keyboard Access may not be able to, and activating the pill does nothing.

**Fix:**
- Add a line to F20's device checklist: step the weight with Voice Control, and again with Full Keyboard Access.
- If either can't, add `.accessibilityAction(named:)` pairs ("Add 5 lb" / "Remove 5 lb").

**R2-N4. The `RestRing` label has no bound.** `RestRing.swift:28-30`. It takes any string with no `lineLimit(1)`.
"10:00" fits up to AX5 (the tester checked). "1:30:00", or a longer localised string, would wrap inside the track.
**Fix:** `.lineLimit(1).minimumScaleFactor(0.5)`, as `SetRow`'s numerals do, or document "a clock string of at most five
characters".

**R2-N5. `LedgerDesign` now owns two user-facing strings.** `SetRow.swift:88-106` against `docs/architecture.md:396-397`.
- The same diff adds to architecture: "Components take display strings the caller has already localised."
- "Done" and "Current set" are English keys in `Bundle.module`. The package has no catalog and no `defaultLocalization`.
- That is harmless while the app is English-only, but the new sentence is already untrue.

**Fix:** add "except `SetRow`'s two VoiceOver state words" to §11, or take the two strings as parameters.

**R2-N6. At accessibility sizes a disclosure chevron drops under the text.** `HairlineRow.swift:39-41`; visible in
`hairlineList_…light-accessibility3.png`.
- Stacking is right for "Use" or a long "5 × 5 @ 185".
- A chevron conventionally stays trailing, but here it lands at the leading edge under the detail.

**Fix (optional):** use `ViewThatFits(in: .horizontal)` over the horizontal and vertical layouts, so a short title keeps
its trailing chevron. That would also retire the `AnyLayout` switch repeated at `SetRowSteppers.swift:39-41`. Or leave
it to F09's review against Today.

**R2-N7. `SetRowHeader` reads as three VoiceOver stops.** `SetRowHeader.swift:15-21`: "#", "lb" and "reps" are three
separate elements. **Fix:** `.accessibilityElement(children: .combine)`, so it is one stop that still gives the units.

**R2-N8. An assertion that can't catch missing reps.** `SetRowAccessibilityTests.swift:29`:
`["2", "185", "5"].allSatisfy(select.label.contains)`. "185" contains "5", so a label that lost its reps still passes.
**Fix:** `#expect(select.label == "2, 185, 5")` (the reading the notes document), or give the fixture distinct reps such
as "8".

**R2-N9. Criterion 5 measures the geometry helper, not the shape the ring strokes.** `RestRingGeometryTests.swift:25-26`.
`RestRing` strokes `RestRingArc`, which delegates to `RestRingGeometry.arc`. **Fix:** in
`halfProgress_arcLength_isHalfTheCircumference`, measure `RestRingArc(progress: 0.5, geometry: .phone).path(in: Self.frame)`,
so the brief's "path-length assertion on the rendered shape" holds literally. The pixel test already covers the view.

**R2-N10. The accessibility helper falls back silently.** `LedgerSnapshotTesting/AccessibilityElements.swift:100-105`.
- If `dlopen` or `dlsym` fails, every tree comes back empty.
- The comment says each lookup then "fails and says why", but a failure only prints `[]`.
- `decorativeParts_areHidden`'s header check (`!header.contains { … }`) would even pass on an empty tree.

**Fix:**
- Put `assertionFailure("libAccessibility automation is unavailable")` in the `else` branch, or import Testing and
  `Issue.record` there.
- While there, declare the two C prototypes with `UInt8` (the C `Boolean`) instead of `Int32`.

**R2-N11. Two stale comments.**
- `ComponentSnapshotTests.swift:9` says "iPhone 17, iOS 26.5". The references were re-recorded on iOS 27.0, the pin in
  `scripts/check.sh:19`.
- `Adversarial/ComponentAccessibilityAdversarialTests.swift:102-103`, the tester's file, says "selected" on the row means
  "active". Since S2-1 the row carries no `.isSelected`.

**For F10 (not a finding).** Inside the component, an active set differs from a pending one by colour only: the label,
the rule and the ring. v2's non-colour cue is the steppers under the active row, so F10 should keep that composition
(WCAG 1.4.1). VoiceOver already says "Current set".

### Merge notes (not findings)

- **PR description** (standards §10, testing-strategy §2.5):
  - Include one line on size: 700 code lines, over the 500 target. The split considered was 2a, the controls (~260
    lines), and 2b, the lists (~390); it was not taken because 2b needs 2a's icons and hit target.
  - List the 49 new PNGs under "Screenshots". They are new references for new components, not re-recordings. On my
    reading, the ">20 changed PNGs → `chore(snapshots):` PR" rule doesn't apply; the orchestrator should confirm.
- **F32 has moved on.** `chore/F32-xcode-27` is now at `f8b2a0c` ("PR CI runs iOS only"), past this branch's merge base
  `ac2a08a`. Land F32 first, then merge `main` into this branch before opening the slice-2 PR. No stacked PRs.
- **The tester's round 2 is in progress in this worktree.** Its untracked files change as it runs: `ZZS2R2Probe.swift`
  during my lint run, which failed SwiftFormat, and later `SetRowContainerAdversarialTests.swift`. This review covers
  `e085375` only. Round 2's results, and any fixes they lead to, need their own check before merge.

### The seven review points

1. **Module boundaries: pass.**
   - The components import only SwiftUI.
   - `AccessibilityElements.swift` (Darwin, UIKit) lives in `LedgerSnapshotTesting`. The only targets that depend on it
     are test targets (`package-graph.expected.txt`), and it is not a product.
   - The package graph is unchanged.
2. **Concurrency: pass, with R2-S1.**
   - Views are MainActor through the module default.
   - Types that must be nonisolated are marked: `LedgerIconShape` and `RestRingArc` (`Shape`), `RestRingGeometry`,
     `LedgerIcon`, `LedgerHitTarget` and `SetRowSpeech`.
   - `@Entry var ledgerDrawsPressed` sits in a `nonisolated extension EnvironmentValues`, so its generated key isn't
     main-actor-bound.
   - No `Task`, timers, clocks or `Date()`.
   - Tests follow slice 1's rule:
     - `RestRingGeometryTests`, `RestRingGeometryAdversarialTests` and `ComponentContrastAdversarialTests` hold values
       only and are `nonisolated`.
     - Every suite that renders or reads the accessibility tree is nested in `.serialized` `RenderingSuites`.
   - The accessibility helper is synchronous on the main actor, so two reads can't interleave.
3. **Error handling: pass.** There is nothing to handle, and there is no `try?`, `!` or `fatalError`. The
   `@unknown default: break` in the adjustable action is right. R2-N10 covers the test helper.
4. **Design fidelity and tokens only: pass.** See the table below.
5. **Accessibility: pass, with R2-S2, R2-S3, R2-N1 to N3 and R2-N7.** See below.
6. **Test quality: pass, with R2-N8 to N10.**
   - Assertions read UIKit's accessibility tree, pixels and path geometry, not implementation details.
   - No sleeps and no wall-clock time. Randomness is seeded (`SplitMix64`).
   - The tester's truncation probe has a positive control.
   - The stepper round trip (`SteppersHarness`, 185 → 190 pounds) checks what VoiceOver would announce, through the
     tree.
7. **Brief compliance: pass.** See the criteria table.

#### Design fidelity (review point 4)

| Component | v2 source | What the references show |
|---|---|---|
| `PrimaryButton` | Today "Start workout": `#FF5B22` pill, 600 16/1, padding 19 (≈ 54 tall), gap 10, 17 px arrow at stroke 1.9 | 54 pt pill, white 700 label with the arrow beside it; the gap is `s` (8). At AX5 the title wraps and the pill grows. Disabled: `hairline` fill, `inkMuted` label |
| `PillButton` | "Finish" / "Repeat" outline at .16, 500 11.5–12.5; selected filter filled with the text colour; "Skip setup" ghost at .32, 400 13 | All three styles; the ghost sits flush left. `caption` 400 12 and `hairlineStrong` .14 are the nearest tokens (decision 2) |
| `IconPillButton` | swap: 38 pt circle at .14, 17 px icon at .6, stroke 1.6 | 44 pt circle (the brief's size), `inkSecondary` icon; grows at AX5 |
| `Eyebrow` | 500 10, .18 em; "UP NEXT" orange, "RECENT" .34 | Exactly the `eyebrow` role; muted raised to `inkMuted` |
| `HairlineList` / `Row` | RECENT: padding 16, 500 15/1.2 title, 300 12.5 meta at .38, 15 px chevron at stroke 1.8 and .28, rules .08, a closing rule | Rules above every row plus a closing one; detail and chevron `inkMuted`; "Use" in `accentText`. AX3 stacks the accessory (R2-N6) |
| `SetRow` + header | grid `22px 1fr 1fr 42px`, gap 10, padding 15. Label 400 12.5: .4 pending, orange active, DIM done. Values 700 24 wdth 90. Check 32 pt, ring .14 / .5 / orange disc with a white 2.4 tick. Active rule orange .4 | Columns line up under the header at every size. Active label, rule and ring are orange. Done values are muted and the disc filled (`#B2390E` on paper, S2-4). Drop set "D" shown; "102.5" shrinks only at AX5. The changes from v2 are the AA ones (decision 1) |
| `SetRowSteppers` | two flex pills at .12; "−" / "+" 300 20 at .6; step 400 10.5, .09 em, .32 | Two equal pills with drawn glyphs in `inkSecondary`. The step uses `eyebrow`, whose tracking (.18 em) is wider than v2's .09 em (decision 2). Stacked at AX sizes |
| `RestRing` | 64 pt, r 29, stroke 2.5, track .12, orange round-cap arc from 12 o'clock clockwise, label 500 16 tabular | Full, half and empty all correct; half is the right half. Label `numeralS` 700 15 (decision 2). Grows with Dynamic Type (137 pt at AX3) |
| Icons | `LedgerTabs*.dc.html`: 24 grid, round caps and joins | `LedgerIcon` follows it. The tab bar itself is out of scope (native `TabView`) |

The three sheets:
- **Bold Text:** every label steps up one weight, icon strokes are 1.3× heavier, and numerals go to 800.
- **Increase Contrast (light):** rules, pill outlines, ring tracks, check rings and the disabled fill step up, and the
  orange stays the same.
- **AX5:** nothing is cut. CTA titles wrap, steppers stack, and the ring reaches 186 pt.

**Tokens only.**
- Every colour is a `LedgerColor`, every text a `.ledgerFont` role, every gap a `LedgerSpacing` token, and every rule
  `LedgerHairline.width`.
- The raw numbers are named, sourced component dimensions inside `LedgerDesign`: 44 / 54 pt, the ring's 64 / 29 / 2.5,
  the icon grid and stroke widths, the 22/12 label column, the 0.6 pressed opacity, the 1.3 Bold Text stroke and the 0.5
  scale floor.
- The diff has no `swiftlint:disable`, force unwrap, `@unchecked`, `DispatchQueue` or timer.

#### Accessibility (review point 5)

- **Labels and traits.**
  - Every control is a `Button`, so it gets `.isButton`, and is labelled by its text. `IconPillButton` is labelled by
    its string.
  - Icons, rules and the header's spacer check are hidden. `Eyebrow` is `.isHeader`. `RestRing` is one element with
    `.updatesFrequently`.
  - `SetRow` is two buttons:
    - the row, with the value "Current set" or "Done";
    - the check, named by `checkLabel`, with `.isSelected` and the value "Done" once logged. Its `.contain` boundary
      stops an outer label at the row.
  - The steppers are one adjustable element each, whose value is the current quantity.
- **44 pt targets.**
  - `.ledgerHitTarget()` sits inside each label, so the accessibility frame is the target.
  - Measured at xSmall, large, xxxLarge, AX3 and AX5 over 12 tappable cases plus the steppers.
  - Each "−" and "+" is 44 pt by construction (`SetRowSteppers.swift:85`). Only the whole pill can be measured, because
    it is one element.
- **Dynamic Type to AX5.**
  - All text uses roles. Icons, the label column, the check and the ring scale with a role.
  - `HairlineRow` and the steppers stack at accessibility sizes.
  - Numerals shrink, never below half size, only when they cannot fit.
  - Covered by the AX5 sheets (dark, and light for SetRow) and by the tester's truncation probe.
- **Bold Text.** Roles step up, and `LedgerIconView` strokes 1.3× heavier. Covered by the sheet, plus Bold Text in the
  layout tests.
- **Contrast.**
  - `ComponentContrastAdversarialTests` covers every text pair at 4.5:1 and every control mark at 3:1 (WCAG 1.4.11),
    in both schemes, with and without Increase Contrast.
  - White on accent at 3.1:1 is Pete's decision 7 (HIG: bold text at any size needs 3:1).
  - The arc's exemption on paper is documented: the countdown carries the same information.

#### The two additions beyond the brief

- **`LedgerIcon`: justified.** 86 lines, 60 of them code.
  - The brief's `PrimaryButton(title:icon:action)` and `IconPillButton` need an icon type, and the brief never defines
    one.
  - Spec §8.7 lists these exact paths ("Other icons: … check, chevrons, arrow, swap").
  - SF Symbols would change the geometry and weights. A `Shape` on the 24-point grid keeps the SVG stroke widths and
    lets Bold Text thicken them.
  - Drawing "−" / "+" replaces v2's 300 20 px text glyphs, which have no role (decision 2).
  - The scope stays tight: only the icons slice 2 draws. No gear, search or back chevron yet.
- **`SetRowHeader`: justified.** 50 lines, 38 of them code.
  - v2's set grid has a heading row.
  - Aligning it with the rows at every text size needs the same column maths: the label column in `caption` ems, and
    the check column. So it shares `SetColumns` and reserves a hidden `SetRowCheck`.
  - Without it, F10 would have to copy internal geometry.
  - It is listed in architecture §11. R2-N7 covers its VoiceOver reading.

#### `AccessibilityElements.swift` and the private automation flag

- **Confined to tests: yes.**
  - It lives in `LedgerSnapshotTesting`. Every target that depends on it is a `test` target
    (`package-graph.expected.txt`), and it is not a package product.
  - `Ledger.xcodeproj` does not reference it, and only files under `LedgerKit/Tests/LedgerDesignTests/` import it.
  - The whole file is `#if os(iOS)`.
  - `_AXSAutomationEnabled` / `_AXSSetAutomationEnabled` are looked up with `dlsym` at run time, so no binary links
    against a private symbol, and nothing reaches an app build.
- **Safe: yes.**
  - It saves the previous automation state and restores it in `defer`.
  - It runs synchronously on the main actor inside `.serialized` `RenderingSuites`, so no reads overlap.
  - The window is hidden and detached in `defer`.
  - The flag only makes UIKit and SwiftUI build their accessibility trees; it doesn't change rendering. In the same
    record runs, every slice-1 reference came back byte-identical.
  - KIF and AccessibilitySnapshot use the same technique, and testing-strategy §2.5 documents it.
  - `UIWindow(frame:)`'s deprecation goes through a deprecated protocol witness rather than a suppression. That is fine
    for test code, and swift-snapshot-testing builds its windows the same way.
- **Residual risk.** A future iOS could rename the symbols. Today the tests would then fail without saying why; R2-N10
  makes that loud.

### `/code-review high`: what happened to its ten findings

| Code-review finding | Disposition |
|---|---|
| A tappable `HairlineRow` nests an interactive accessory in its button | R2-N1 (a doc fix; v2 has no such row) |
| The done check still says "Log set 2", and "Done" is heard twice | R2-N2. The caller can already pass a label per state; the double announcement is S2-1's decision |
| The steppers' `.ignore` shuts out Voice Control and Full Keyboard Access | R2-N3 (verify on a device) |
| The `RestRing` label is unbounded | R2-N4 |
| White on accent (3.1:1) is under 14 pt at `.xSmall` | Rejected: Pete's decision 7 applies the HIG table, 3:1 for bold text at any size, which the notes cite |
| `allSatisfy(contains)` can't catch missing reps | R2-N8 |
| `scaledSize` runs on every body pass | Rejected here. Slice 1 measured `scaledSize` at 0.5 µs. The real cost is `.ledgerFont` at 43 µs, which is already slice 1's N2 (measure with slice 3's watch performance test) |
| A stale doc comment in the adversarial test | R2-N11 |
| `.filled` has no `.isSelected` | R2-S2 |
| The `AnyLayout` switch is duplicated | Not a finding: two sites with different alignment and spacing. R2-N6's `ViewThatFits` would remove it anyway |

### Criteria → evidence (slice 2)

| # | Criterion | Evidence |
|---|---|---|
| 3 | These components × {light, dark} × {L, XL, AX3} at the iPhone 17 width | Seven suites in `ComponentSnapshotTests.swift` over `SnapshotAppearance.phoneMatrix`, through `assertPhoneSnapshot`: 402 pt, 1×, precision 0.995 / 0.98. 42 references, recorded on iPhone 17 / iOS 27.0 (the `check.sh` pin). Another 7 targeted images: AX5 dark, Bold Text, pressed ×2, Increase Contrast ×2, SetRow light at AX5. The galleries hold every state: the disabled CTA, three pill styles, done / active / pending / drop set, full / half / empty ring. 12 opened and checked. **Met** |
| 5 | `RestRing(progress: 0.5)` covers exactly half the circumference | `RestRingGeometryTests.halfProgress_arcLength_isHalfTheCircumference`: half ÷ full is 0.5 within 1e-9, and against 2π·29 within 0.03 %. Also: proportional at 8 fractions, the 182 dash, clamping, half is half at every size up to AX5. `RestRingRenderTests.halfProgress_rendered_isOrangeOnTheRightHalfOnly` checks pixels. The tester added 500 seeded values against the SVG dash, and "half is the right half" at 6 sizes × 2 schemes. **Met** (R2-N9 makes "rendered shape" literal) |
| 6 | `PrimaryButton`: label = title, `.isButton`, ≥ 44 pt target | `ComponentAccessibilityTests.primaryButton_accessibility_labelledButtonWithTarget`, at large and AX3: label = title, `.button`, ≥ 44 × 44 and ≥ 54 tall, one element. `primaryButton_disabled_isNotEnabled`. The tester's extremes: xSmall, xxxLarge, AX5. **Met**, and extended to every tappable slice-2 component |
| NFR | References ≤ 6 MB, 1× PNG | `__Snapshots__` totals 2.3 MB |
| DoD | Previews for every state | `Components+Previews.swift`: one per component, each rendering its full gallery |

### Verdict

**Approve: 0 Blocking.** Land the three Should fix items in this PR, before F10 builds on the API. Each is small:
- **R2-S1:** four keywords and one test.
- **R2-S2:** one modifier and one assertion.
- **R2-S3:** a signature change and five call sites, three of them in the tester's files.

The Nits can go with them, or to the orchestrator: the second half of R2-N11 is in the tester's file, and R2-N3 is a
device check for F20.
