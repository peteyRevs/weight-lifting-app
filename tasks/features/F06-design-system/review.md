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
