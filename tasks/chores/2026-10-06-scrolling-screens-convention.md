# Scrolling screens: the convention, lifted out of F08 S2 (2026-10-06)

F08 S2 (`origin/feat/F08-s2-onboarding-ui`, tip `24b610b`) settled how a screen that scrolls is built and
tested, and changed two shared pieces on the way (the hosted accessibility reader, `PillButton`). That
branch is parked for a product decision; F09's Today views and F10's first workout screen need the
convention alone. This change holds the shared pieces and nothing of onboarding.

Branch `chore/scrolling-screens-convention`, cut from `main` at `9f7ab85`. Nothing is committed by the
agent that did the move; the orchestrator commits.

## How the pieces were found

S2's own change is `git diff 844a583 24b610b`: `844a583` is the merge of the tab-shell branch into F08 S2,
and the six commits after it are S2 (`ec6c370` … `24b610b`). The diff against S1 (`c685d65`) also shows the
tab shell, which `main` has as #28. Outside `FeatureOnboarding`, `FeatureOnboardingTests` and
`tasks/features/F08-onboarding*`, S2 touched 24 files.

`main` has not changed any of the Swift files taken since `844a583` (each is byte for byte the same on
`main` and at `844a583`), so S2's hunks were applied to `main`'s files as they are
(`git diff --binary 844a583 24b610b -- <paths> | git apply`). After it, every Swift file and every PNG
taken is byte for byte the branch's. `main` has edited the two documents since, in other paragraphs; S2's
hunks applied without a conflict and `main`'s edits stand.

## Pieces taken

| File (under `LedgerKit/` unless it starts `docs/`) | What S2 changed | Adapted to `main` |
|---|---|---|
| `Sources/LedgerSnapshotTesting/AccessibilityElements.swift` (+61 −12) | The reader's walk fails the test when a scroll view yields no element, and says to host the page. `outsideScrollViews: Bool = false` on the three readers leaves every scroll view out without failing | none |
| `Tests/LedgerDesignTests/AccessibilityReaderTests.swift` (new, 104 lines, 7 tests) | The loud default and the opt-in, on each of the three readers | none |
| `Tests/LedgerDesignTests/Adversarial/ReaderCloseOutAdversarialTests.swift` (new, 225 lines, 5 tests) | The tester's close-out: sideways rows, inner scroll views, `List`, `Form`, the text-editor limit (F8-S2-8), F06's helper | none; it uses nothing of onboarding |
| `Tests/LedgerDesignTests/Adversarial/Slice3CloseoutSheetAdversarialTests.swift` (+8 −5) | F06's `sheetChrome_scrollingContent_titleAtTheTopAndWhole` reads a title over scrolling rows: it passes `outsideScrollViews: true` (the sanctioned edit; a frame that does not own what scrolls inside it) | none |
| `Sources/LedgerDesign/Components/PillButton.swift` (+78 −6) | A disabled pill looks disabled; `flush: HorizontalEdge?` stands the pill at an edge of its target; `PillButtonStatesGallery` | none |
| `Sources/LedgerDesign/Components/ControlStyle.swift` (+6 −4) | `ledgerHitTarget(alignment:)`, which `flush` needs; `LedgerPressStyle`'s comment | none |
| `Sources/LedgerDesign/Components/Components+Previews.swift` (+6) | The registry case and `#Preview` "PillButton states" | none |
| `Tests/LedgerDesignTests/PillButtonStateTests.swift` (new, 117 lines, 6 tests and 1 snapshot test) | The disabled and flush states | none |
| `Tests/LedgerDesignTests/__Snapshots__/PillButtonStateTests/` (6 PNGs, 96,025 bytes) | The states gallery in the phone matrix | none; they matched what this machine renders (below), nothing was recorded |
| `Tests/LedgerDesignTests/AccessibilityTreeTests.swift` (+12) | Four rows: a flush ghost pill, and each style disabled | none |
| `Sources/LedgerDesign/Components/ProgressSegments.swift` (+3, a comment) | Says that an empty value makes VoiceOver speak the label alone (review nit N1) | none. Its example is onboarding's bars, which `main` does not have yet |
| `Sources/LedgerTestSupport/Localization/CopyAuditRules.swift` (+4 −2) | The copy audit no longer reads a logger's category as copy (`logger.category("today")`; SF3, F8-S2-2). Not onboarding's: standards §8 asks every module to log under its own category, and each feature's store would trip the audit | none |
| `Tests/LedgerAppKitTests/CopyAuditTests.swift` (+5 −1), `CopyAuditLimitTests.swift` (+1) | Two allowed cases, two lookalikes that stay findings, one limit case | none |
| `docs/testing-strategy.md` (+62) | §2.5: the reader cannot see inside a scroll view. §2.6: "A screen that scrolls", all eight points | Applied to `main`'s text; `main`'s two later edits (§1's table, §6's seeded matrix) stand. S2's wording is unchanged: see "Dangling references" |
| `docs/engineering-standards.md` (+12 −5) | §7: the bullet on a screen that scrolls. §7's copy rules: a logger's category is allowed, and the limit. §8: a store logs under its module's category and never logs a cancellation as an error | Applied to `main`'s text; `main`'s later edit of §3 stands |

`docs/architecture.md`: S2 changed nothing in it.

Line counts: product (`LedgerDesign`) +93 −10 in four files, of which 26 are the states gallery and 6 the
preview. Test support (`LedgerSnapshotTesting`, `LedgerTestSupport`) +65 −14 in two files. Tests: three new
files (446 lines) and +26 −6 in four. Documents +74 −5.

### Dangling references (for the orchestrator to rule on)

The move kept S2's words, so that the parked branches merge with identical content. Until F08 S2 is on
`main`, four places on `main` name things that only that branch has:

- `docs/testing-strategy.md` §2.6: "The model to copy is onboarding's", with paths under
  `LedgerKit/Sources/FeatureOnboarding/Views/` and `LedgerKit/Tests/FeatureOnboardingTests/`, and
  `OnboardingRootTests` twice more. A reader on `main` finds them with
  `git show origin/feat/F08-s2-onboarding-ui:<path>`.
- `docs/engineering-standards.md` §7 and §8 use `logger.category("onboarding")` as their example (it reads
  as an example and needs nothing).
- `ProgressSegments.swift` and `PillButton.swift`: the comments' examples are onboarding's bars and "Back".

Nothing checks these paths (no script or test reads the documents for file names). Adding "on the parked
branch" to §2.6 would be a change of S2's text and a real conflict when `main` is merged into F08; it was
not made.

## Pieces left

| What | Why |
|---|---|
| `LedgerKit/Sources/FeatureOnboarding/**`, `LedgerKit/Tests/FeatureOnboardingTests/**` (its snapshots, and `OnboardingPillAdversarialTests`, which tests the pill through onboarding) | the feature |
| `LedgerKit/Package.swift`: `FeatureOnboarding` in `snapshotTestTargets`, and its `resources:` | onboarding's line in a shared one-line file (M1 convention 4) |
| `LedgerTestSupport/Previews/PreviewScan.swift`: `FeatureOnboarding` in `registeredModules` | the same; on `main` the module has no preview registry and the scan would fail |
| `scripts/coverage-thresholds.json`: `FeatureOnboarding` in `required` | the same |
| `tasks/features/F08-onboarding.md` and `tasks/features/F08-onboarding/**` (notes, review, findings, screenshots) | onboarding's records. Rule 7 of "M1 shared conventions" lives in those notes; the document is its source |
| Everything in `c685d65..844a583` (the tab shell, localization, the copy audit itself, `Apps/LedgerUITests/Tabs*`) | `main` has it as #28 |
| S1 (`ProgramTemplates` and its tests) | not S2's, and onboarding's |
| S3's edit of `docs/testing-strategy.md` §2.7 (`origin/feat/F08-s3-root-gate`) | onboarding's UI tests and launch |

Nothing had to be rewritten to be separated.

## Runs (2026-10-06, from the worktree root; logs in the scratch folder `scroll-conv/`)

| Run | Result | Exit |
|---|---|---|
| Simulator, PR plan, iPhone 17 (iOS 27.0), through the lock, as `scripts/check.sh` runs the plan: `-only-testing:LedgerDesignTests -only-testing:LedgerAppKitTests` (`sim-1.log`) | 542 tests: 535 passed, 0 failed, 1 skipped, 6 expected failures (tests that catch the reader's loud failure with `withKnownIssue`). `LedgerDesignTests` 306 cases, `LedgerAppKitTests` 236 | build 0, test 0 |
| `scripts/check.sh --lint-only` (`lint-1.log`) | OK | 0 |
| Host: `swift test --package-path LedgerKit --only-use-versions-from-resolved-file --filter "LedgerDesignTests\|LedgerAppKitTests"` (`host-1.log`) | `LedgerAppKitTests`: 224 tests in 36 suites passed, the copy audit's new cases among them. `LedgerDesignTests`: 165 tests in 43 suites, **52 issues, all in four font suites** ("Archivo loading", "Bold Text", "LedgerFont rendering", "Watch type floor": "Archivo not found next to the test bundle") | 1 |

- **No existing test on `main` tripped the louder reader**, beyond F06's sheet test, whose opt-in is S2's own
  sanctioned edit and came with the move. The reader's callers are in `LedgerDesignTests` (14 files) and
  `LedgerAppKitTests` (3 files) and nowhere else on `main`; both targets ran.
- **The six snapshot references matched** in a comparing run (`PillButtonStatesSnapshots` passed; no PNG in
  the tree changed). Nothing was recorded.
- **The host's font failures** are in files this change does not touch, and in suites that need the font
  file beside the test bundle; the gate runs `LedgerDesignTests` on the simulator, where all 306 cases
  passed. They were **not** shown to fail on `main` without this change (no second build was made).
  The new suites are iOS only (`#if canImport(UIKit)`), so the host run says nothing about them.

Not run: the full gate, coverage, watchOS, the nightly lane, CI.

## When `main` is merged into the parked F08 branches

- **`feat/F08-s2-onboarding-ui` and `feat/F08-s3-root-gate`** hold every change above already. Each Swift
  file and PNG here is byte for byte theirs, and `main` did not touch those files in between, so git should
  merge them without a conflict (the same change on both sides). The two documents carry the same hunks plus
  `main`'s edits elsewhere, and should merge cleanly too. If any of these is reported as a conflict, the
  resolution is **identical content: take either side**: the thirteen Swift files in the table,
  the six PNGs, `docs/testing-strategy.md` (§2.5, §2.6) and `docs/engineering-standards.md` (§7, §8).
- **Real conflicts to expect there are not this change's:** the shared one-line files (`Package.swift`,
  `PreviewScan.swift`, `scripts/coverage-thresholds.json`), where the branch adds `FeatureOnboarding` beside
  whatever `main` added, and the tab shell's files, which the branches hold as an older copy of #28.
- **`feat/F08-s3-root-gate`** also edits `docs/testing-strategy.md` §2.7; that is another paragraph.
- **`feat/F08-s1-templates`** has none of this and gains it from `main` like any other change.
