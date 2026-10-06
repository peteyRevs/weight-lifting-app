# F09 Today: test findings

## Slice S1 — round 1 (G2 tester, 2026-10-04)

Branch `feat/F09-s1-tab-shell` at `59acf9d`. Specification: the brief's "Plan amendments" (S1 criteria 1 to 6) and
`docs/engineering-standards.md` §7 "Localization" as this slice wrote it.

**Result.** The tab shell held under every attack: no finding against criteria 1, 2, 3, 5 or 6. The copy
(criterion 4) is in the catalog and resolves from the built bundle on the host, on the simulator and inside
`Ledger.app`. The audit helper, which seven features will copy, has one bug, five gaps, one false alarm and one
unchecked rule, and the catalog carries a sentence that standards §7 forbids and criterion 4 freezes.

93 tests written (86 Swift Testing, many parameterized, and 7 XCUITest). On the host 79 run: 69 pass, 10 fail. On
the simulator 86 run: 76 pass, 10 fail (the same 10). The 7 UI tests pass. The final gate is red on those 10 and on
nothing else; the watch step, run after it, is green. Every failing test is one of the findings
below and is left failing on purpose.

**Independence.** I did not read `implementation-notes.md`. I read the implementer's Swift tests only after my own
had run on the host and on the simulator; the three last additions (the `locale:` test, the limit pins, the preview
rendering suite) had run on the host only and ran on the simulator in the final gate. Two exceptions, both data:
I read `Fixtures/Localizable.xcstrings` before writing the catalog-build tests, because they need its keys; and a
repository-wide `grep` for the can't-open sentence printed one line of `AppCopyTests.swift`.

### Findings

Severity is one of: bug, audit gap (a forbidden thing passes), audit false alarm, spec question, test-quality.

#### F9-S1-1 — bug (false alarm and gap): a key with a `%` and no interpolation is read wrongly

- **Rule.** §7: "The key is the English text with its format specifiers"; the catalog and the copy file agree in
  both directions.
- **Repro.** `CatalogBuildAdversarialTests.auditKey_isFoundationsKey`, case `"100% done"`. Copy file member
  `static func line() -> String { String(localized: "100% done", bundle: .module) }`, catalog key `100% done`.
- **Expected.** No finding. Foundation asks the table for `100% done`: `LocalizedStringResource("100% done").key`
  says so, and `String(localized: "100% done", bundle:)` against a `.strings` table that holds both spellings
  returns the `100% done` entry (checked with a script on macOS 27.0).
- **Actual.** Two findings: `FixtureCopy.swift:5: looks up "100%% done", which the catalog does not hold` and
  `"100% done" is not looked up by a copy file`. The other way round, a catalog keyed `100%% done` passes the audit
  and passes test 2 (the key is in the table), while the app's lookup misses it and shows its fallback: the entry is
  dead, and a translation of it would never show.
- **Cause.** `CopyAudit.key(of:)` doubles `%` in every literal. The compiler doubles it only in a literal that has
  an interpolation (`"\(week)% of the block"` is `%lld%% of the block`, which the audit reads correctly; 11 other
  shapes of key agree with Foundation).

#### F9-S1-2 — audit gap: a lookup inside another literal's interpolation is not held to the rule's form

- **Rule.** §7: "A lookup is always written `String(localized: "…", bundle: .module)`", "each with a literal key".
- **Repro.** `CopyFileAdversarialTests.nestedLookupNotWrittenAsTheRule_isAFinding`, 3 cases, in a copy file:
  `"\(String(localized: "Start workout")) · \(reps)"` (no bundle), the same with `bundle: .main`, and
  `"\(String(localized: key, bundle: .module)) · \(reps)"` (a key handed in).
- **Expected.** A finding each. **Actual.** None. The control, the same join written with `bundle: .module`, has
  none either, so a join in a copy file is otherwise accepted.
- **Why it matters.** §7 says "Two counts are two keys, joined with \" · \"": this is how that join is written.
  Without the bundle the lookup reads the app's main bundle, misses, and shows its key, which is the English text:
  right today, never translated, and test 2 cannot see it.
- **Cause.** `otherLookups` counts the forms in `compactCode`, which leaves interpolations out.

#### F9-S1-3 — audit gap: a lookup that formats a number without `locale:` passes

- **Rule.** §7: a lookup is written "with `locale:` when it formats a number (the caller passes the injected
  `@Dependency(\.locale)`, so a test fixes the digits and their grouping)".
- **Repro.** `CopyFileAdversarialTests.lookupThatFormatsANumber_withoutALocale_isAFinding`, 2 cases:
  `static func line(_ count: Int) -> String { String(localized: "\(count) sets", bundle: .module) }`, and the
  same for `Week %lld of %lld`.
- **Expected.** A finding. **Actual.** None. The implementer's own model of a sound copy file
  (`CopyAuditTests.copyFile`, `week(_:of:)`) formats two numbers without `locale:` and is asserted to have no
  finding.
- **Related observation**, pinned by `CatalogBuildAdversarialTests.pluralForm_followsTheLocalesLanguage` (passes):
  the locale a lookup is given also picks the plural rule. With the English fixture, `fr_FR` gives "0 fixture set",
  `ru_RU` gives "21 fixture set" and `ja_JP` gives "1 fixture sets"; `en_FR` gives "0 fixture sets". §7 says the
  locale fixes "the digits and their grouping". It fixes the plural form too, so a lookup without it takes both
  from `Locale.current`.
- If the rule is meant to be narrower (only where grouping can show), §7 should say so; then this is a spec
  question.

#### F9-S1-4 — spec question and audit gap: shipped copy names the product

- **Rule.** §7, "Not copy": "Shipped copy never contains the product name (`docs/product-decisions.md`, Naming)",
  and "a catalog entry that breaks the rules above" is a finding. Against it, criterion 4: the can't-open screen's
  "wording does not change in this slice".
- **Repro.** `AppCopyAdversarialTests.catalog_neverNamesTheProduct`: the catalog key "Your workouts are still on
  this iPhone. Ledger tries again when you come back to it." And
  `CopyFileAdversarialTests.productNameInTheCatalog_isAFinding`: the audit of a module whose one key is "Ledger
  tries again when you come back to it." has no finding.
- **Expected.** By Naming, no "Ledger" in a catalog; by §7, the audit says so. **Actual.** The sentence is in the
  catalog, word for word as `main` shows it (F07 wrote it; F07 review item 5 let the wording through), and the
  audit passes it.
- The implementer did what criterion 4 says. This needs Pete's wording, so the first test stays red until then.
  The watch shows the same sentence from a literal (`WatchRoot.swift:47`), outside this slice.

#### F9-S1-5 — audit false alarm: an identifier or an SF Symbol chosen by a condition

- **Rule.** §7: a literal counts "unless it is an accessibility identifier (`.accessibilityIdentifier("…")`, or an
  argument labelled `identifier:` / `…Identifier:`), an SF Symbol's name (`systemImage:`, `systemName:`) or a log
  line".
- **Repro.** `CopyAuditAllowedAdversarialTests.identifierOrSymbolChosenByCondition_isNoFinding`, 4 cases:
  `Image(systemName: isDone ? "checkmark.circle" : "circle")`,
  `Label(title, systemImage: isLive ? "pause.fill" : "play.fill")`,
  `.accessibilityIdentifier(isToday ? "strip.today" : "strip.day")`,
  `.accessibilityIdentifier("strip.\(isToday ? "today" : "day")")`.
- **Expected.** No finding: each literal is a symbol's name or an identifier. **Actual.** Two findings each
  ("a string literal outside the copy files").
- **Why it matters.** A week strip and a set row pick a symbol by state. The way out the tool offers is to exempt
  the file, which hides every literal in it (F9-S1-10 a). If the rule means "only a literal that stands directly
  after the label", §7 should say so; then this is a spec question.

#### F9-S1-6 — audit gap: a literal after a name that only reads like an allowed label

- **Repro.** `CopyAuditAdversarialTests.literalAfterALookalikeLabel_isAFinding`, 3 cases:
  `Text(isStock ? systemName : "Custom exercise")`, `Text(hasCode ? identifier : "No barcode")`, and
  `case .identifier: "Barcode"` in a `switch`.
- **Expected.** A finding each. **Actual.** None.
- **Cause.** `allowedLeads` is matched as the end of the code before the quote. A ternary's first arm or a case
  named `identifier`, `systemName` or `systemImage`, followed by its colon, ends the same way as the label.

#### F9-S1-7 — audit gap: two spellings of a lookup outside the copy files are not seen

- **Rule.** §7: other files "hold neither a user-facing literal nor a localized lookup".
- **Repro.** `CopyAuditAdversarialTests.lookupOutsideTheCopyFile_isAFinding`: 12 of 14 spellings are found. The two
  that pass: `Bundle.module.localizedString(` with `forKey: key,` on the next line, which is how SwiftFormat
  (`--wraparguments before-first`) wraps the call; and `Bundle.module.localizedAttributedString(forKey:…)`.
- **Cause.** Spellings are matched within one line of code; `localizedAttributedString(forKey` is not in the list.
- Low: it needs a key that is not a literal with a letter in it. With one, the literal itself is the finding.

#### F9-S1-8 — audit gap (low): a composed and a decomposed spelling of a key count as one key

- **Repro.** `CopyFileAdversarialTests.composedAndDecomposedKeys_areNotTheSameKey`: the source looks up
  `"Caf\u{E9} stop"`, the catalog's key is `"Cafe\u{301} stop"`.
- **Expected.** Findings in both directions: a strings table tells the two apart (`NSString.isEqual` is false; the
  test checks it). **Actual.** None: `Set<String>.contains` compares by canonical equivalence.

#### F9-S1-9 — audit gap (low): the catalog's layout is not checked

- **Rule.** §7: "A catalog is edited as text, in the layout Xcode writes (two-space indent, `"key" : value`, keys
  in order)", and "a catalog entry that breaks the rules above" is a finding.
- **Repro.** `StringCatalogAdversarialTests.keysOutOfOrder_areAProblem`: a catalog with "Today" before "History".
- **Expected.** A problem. **Actual.** None: the reader decodes the JSON, so order, indent and spacing are gone
  before any rule runs. The cost is a noisy diff the first time Xcode saves the file. Either check it or take the
  clause out of what the audit promises.

#### F9-S1-10 — spec question: §7 lists no known limits of the audit

The design lint's section of §7 lists what the lint misses, each kept as a `limit` case. The copy audit has limits
too, and §7 names none. Each is pinned by a passing test that fails if the audit starts to catch it:

- a. **An exemption covers the whole file.** `exemptFile_hidesALifterFacingLiteral`: in a file exempted for launch
  arguments, `Text("Start workout")` has no finding. This is the rule as written. In this module
  `AppComposition.swift`, the composition root every feature's wiring lands in, is exempt.
- b. **A regex literal.** `regexLiteralHoldingAQuote_hidesTheLiteralAfterIt`: `row(/"/, "Start workout")` has no
  finding, and a regex that holds `/*` (`/\/*/`) leaves the rest of the file unread. `SwiftSource`'s comment says
  it for the quote; §7 does not, and nothing says it for `/*`.
- c. **A text made from a name.** `textMadeFromAName_hasNoLiteralToFind`: `Text(card.rawValue.capitalized)` and
  `Text("\(Card.today)")` show a lifter a word that is in no catalog and in no literal.
- d. **`*+Previews.swift` is not read** (the rule as written): nothing checks that such a file is Debug-only.
- e. **A key written twice.** `duplicateKey_isReadAsTheCompilerReadsIt`: the reader takes the first entry, as
  `xcrun xcstringstool compile` does, so the two agree; neither says the key is there twice, and the second entry
  is dead text.

#### F9-S1-11 — test-quality

- a. No snapshot for the new `PlaceholderScreen`, nor for the `Tabs` and `Database unavailable` previews.
  Standards §12: "Snapshot tests added or updated for any new/changed UI, light and dark"; testing-strategy §2.6:
  "one per screen state (the `#Preview` list is the contract)". The registry has four previews; `Today` alone has
  references.
- b. Criterion 5's accent and criterion 6's drawing had screenshots and a wording test only. They are now pinned
  by `TabsAdversarial.test_selectedTab_isDrawnInTheAccent_andNoOtherIs_lightAndDark` and
  `AppRootAdversarialTests`.
- c. `CopyAuditTests.lookups_areKeyedAsTheCompilerKeysThem` checks the audit's keys against keys typed by hand,
  not against Foundation's (`LocalizedStringResource.key`), which is how F9-S1-1 passed it.
- d. Otherwise the implementer's tests assert behaviour: exact findings with their lines, both directions of the
  comparison, stale exemptions, the shell hosted and in the running app. I found no test that only restates the
  code.

### Attacked and held

**The router and the shell (criteria 1, 2, 3, 5, 6).**

- `AppRouterAdversarialTests`, 8 tests: Today selected in a new router; the four tabs in order; `open(_:in:)` on
  the selected tab and from each tab to every other; the same destination opened twice pushes twice; a stack of
  200; pop and return to root through the path; observers of a path and of the selected tab are told. Random
  sequences of selections, opens, pops and returns against a model: seeds 1 to 300, 60 steps each, no mismatch.
  Opening twice pushes twice, as criterion 3 reads: a control that emits a route on each of two quick taps will
  stack two screens unless its feature emits once.
- `AppTabsAdversarialTests` (simulator), 5 tests: the hosted shell shows one element at launch, "Today", a header;
  each tab's root is the placeholder that names it; a destination opened in a tab never visited shows there under
  a navigation bar, Today and History each keep their stack through a round trip, two pushes pop one at a time,
  and the root hides the bar again. Random sequences against a model: seeds 1 to 40, 25 steps each. At the largest
  text size (AX5) each of the five titles is whole and on one line at 375 pt and at 320 pt.
- `AppRootAdversarialTests`, 6 tests: the database-unavailable screen is pixel for pixel what `main`'s code draws
  (rebuilt from `git show a526874:…/AppRoot.swift`) in light and dark at three text sizes and at AX5; the root of
  a composition whose database did not open draws that screen; an idle root draws the ground alone and opens
  nothing; a ready root draws without trapping; VoiceOver reads the unavailable screen as `main`'s (title, a
  header, then the body) and nothing on an idle root.
- `TabsAdversarial` (XCUITest, 7 tests, all pass): the tab bar's buttons are Today, Program, Library, History,
  left to right, Today selected, each at least 44 pt; no navigation bar on a root; each tab shows its
  placeholder by identifier (`today.title`, `program.title`, `library.title`, `history.title`) and is the only one
  selected, both ways round; the debug menu opens from a long press on Today's title after a tour of the tabs and
  from no other title; the selected tab, and only it, is drawn in the accent, for each of the four tabs in light
  and in dark (pixels of the tab's own screenshot); at AX5 every title is on screen, hittable and on one line; the
  app stays upright when the device turns (the target allows portrait alone); the system's accessibility audit
  reports nothing on any of the four roots.
- Routes are in `LedgerAppKit/Routes.swift`; `Apps/Ledger/` holds `LedgerApp.swift` and assets only, with no
  `Sources/Navigation/`.

**The copy (criterion 4).**

- `AppCopyAdversarialTests`, 10 tests, 9 pass: the four tab titles are the prototype's labels; the pushed
  placeholder is "Settings"; the two can't-open strings are word for word `main`'s; the catalog holds those seven
  strings and nothing else, each sound; the built bundle holds each in a compiled table (a sentinel proves a miss
  is seen); a scan of the module's sources that does not use the audit finds no drawn literal and no lookup outside
  `AppCopy.swift`, whose lookups are exactly the catalog's keys; the audit with no file exempt names nothing in the
  shell's files. The tenth is F9-S1-4.
- By hand: `Ledger.app/LedgerKit_LedgerAppKit.bundle/en.lproj/Localizable.strings` in the simulator build holds the
  seven keys.

**The audit and the readers** (inputs in memory; the rule quoted is §7).

- Outside a copy file, forbidden and found: 36 of 36 ways to draw or hold a literal (`Text`, `Label`, `Button`,
  `.navigationTitle`, the three accessibility modifiers, `Text(verbatim:)`, multi-line and raw literals,
  concatenation, text around and inside interpolations, a constant, a default argument, a raw value, an array,
  letters outside ASCII and as escapes, `#if DEBUG` and its `#else`, a tab's and an alert's title,
  `String(format:)`, `AttributedString`, an asset name). 22 of 22 literals found on the right line after text that
  could put a reader out of step (comment marks and quotes inside literals, quotes inside comments, nested
  comments, escapes, raw literals, multi-line literals, parentheses and closures in interpolations, CRLF). 12 of
  14 lookups (F9-S1-7). A finding carries the file's path in the module and the line.
- Outside a copy file, allowed and passed: 31 of 31 (identifiers, also with an index and wrapped; `identifier:` and
  `…Identifier:` arguments; `systemImage:` and `systemName:`; log lines on a logger, wrapped, on a nested logger,
  quoting a lookup; " · " and other letterless literals; an empty literal; comments, doc comments and nested block
  comments that hold literals and lookups; `localizedStandardCompare` and the like). 5 of 5 calls that only look like log lines are findings (a banner's
  `error(`, a toast's `notice(`, `print`).
- Exemptions: by the file's path, not its name; a stale one is a finding (missing file, file with no literal, a
  copy file); a lookup in an exempt file is still a finding. `+Previews.swift` is not read; `TodayPreviews.swift`
  is.
- Inside a copy file: 13 of 13 wrong forms are findings (no bundle, `.main`, a table, a default value, a key handed
  in or from a raw value, `NSLocalizedString`, `Bundle.localizedString`, a `Text`'s own lookup, a
  `LocalizedStringResource`, a bare literal, a constant, a multi-line key); 11 of 11 interpolations that are not a
  bare `Int` or `String` parameter are findings; 11 of 11 right forms pass (with `comment:`, `locale:`, wrapped,
  labels, defaults, one lookup per case, one name with two types in two members); a member that returns a `Text`
  built from a looked-up `String`, " · " and a view passes; a lookup in a comment is not a lookup; a parameter's
  type decides `%lld` or `%@`.
- Both directions: 7 of 7 near-misses between catalog and copy file give two findings each (case, a leading, a
  trailing and a doubled space, a no-break space, a full stop, an en dash). A module with no copy file, a catalog
  with no keys, a module with no catalog or that does not exist: findings or a thrown error, never a pass on
  nothing.
- `StringCatalog`: 10 of 10 sound catalogs have no problem (among them a comment and Xcode's extraction state, an
  escaped percent, a quote and a line break in a key, a second language beside English); 20 of 20 unsound ones
  have one (no localization, German only, `new`, `needs_review`, `stale`, no state, text that is not the key by a
  space or a case, an empty text, another source language, a plural without `one`, without `other`, with another
  `other`, left `new`, with two counts, with none, counting a text, a device variation); 3 of 3 `one` forms with
  other specifiers than the key's; 7 of 7 texts that are not a catalog throw; keys that differ in case or a space
  are different keys; specifiers are read in order with positions left out and `%%` as text.
- `SwiftSource`: escapes, raw literals, the order of literals, lines, leads and code match Swift's rules; every
  prefix of a hostile source and random text for seeds 1 to 200 are read to the end, and audited, without a trap.
- What the compiler does (by hand, `xcrun xcstringstool compile`, Xcode 27.0): a key left `new` or with no
  localization is left out, as §7 says; `needs_review` and an unknown state are compiled, so the reader is stricter
  than the build; a missing `state` is a compile error; a plural's `zero` form and a `one` form left `new` are
  compiled; a trailing comma is accepted by the compiler and by the reader alike.

**The catalog build.** `CatalogBuildAdversarialTests`, 9 tests, 8 pass, on the host and on the simulator: a plain,
a text-formatted and a number-formatted string come from the fixture catalog, and a missing key gives the key;
counts 0, 1, 2, 21, 101 and 1,000,000 take English's forms; `de_DE` gives "1.000.000", `en_IN` "10,00,000",
`en_GB` "1,000,000"; every fixture key is in the test bundle's table and in no other bundle's; a module's bundle is
found by name and is not the test's own. The ninth is F9-S1-1.

**Previews.** `PreviewTests` of LedgerAppKit (4 previews), LedgerDesign (20) and LedgerWatchAppKit pass on the
host; LedgerAppKit's and LedgerDesign's pass on the simulator in the gate. `PreviewRenderingAdversarialTests`,
2 tests: a preview is built and shown in the preview context; the shell draws with each tab selected, at depth 0, 1
and 3, in light and dark, at the default size and AX5 (48 renders).

**Launch time** (reported, never gated: decision #30). `LaunchPerformance`: mean 2.649 s over five launches
(2.606 to 2.677 s); the in-app figure under XCUITest is 2312 ms. F07's notes record 2.484 s and 2308 ms on `main`.

### Not attacked

- What VoiceOver speaks ("tab, 1 of 4"): XCUITest sees buttons in a tab bar, their labels and their selected
  state, not speech. No device, no iPad, no right-to-left layout; Increase Contrast, Bold Text and Reduce Motion on
  the tab bar were not tried.
- A tap on the selected tab returning to its root, and the back swipe: nothing in the slice pushes a screen from
  the UI. The router and the hosted shell cover pops written through the path.
- The router's life across a database that fails and reopens (`MainRoot` owns it as `@State`).
- A translated catalog in the app: the app target declares no language beyond English, and a package's
  translations show only for languages the app declares. Not tested; it matters when a second language arrives.
- A catalog on watchOS (no watch module has one; §7 says it is unproven) and SwiftPM's `native` build system (I
  was told not to pass it).
- The Nightly plan as a whole: I ran its five `LedgerUITests` classes and `LedgerAppKitTests`, not the rest.
- Launch time against `main` on the same day: the figures above are from different runs on a shared machine.

### Commands and exit statuses

All from the worktree root. Simulator work went through `sim-lock.py`. Logs are in the session's scratch folder
(`f09s1-g2/`).

| Command | Exit | Result |
|---|---|---|
| `swift test --package-path LedgerKit --only-use-versions-from-resolved-file --filter LedgerAppKitTests` (host) | 1 | 168 tests, 10 fail, all mine (below) |
| `swift test … --filter "PreviewTests\|PreviewRenderingAdversarialTests\|PreviewScan"` (host) | 0 | every module's previews render |
| `scripts/check.sh --lint-only` | 0 | format, lint, script tests |
| `xcodebuild build-for-testing` + `test-without-building`, scheme Ledger, plan Nightly, iPhone 17 (27.0), `-only-testing:LedgerAppKitTests` | 65 | 175 tests, 9 fail, all mine (before the last three additions) |
| the same, light, `-only-testing:LedgerUITests/{Smoke,DebugMenu,LaunchPerformance,Tabs,TabsAdversarial}` | 0 | 12 of 12 pass |
| the same, simulator set to dark, `-only-testing:LedgerUITests/{Smoke,DebugMenu,Tabs}` | 0 | 4 of 4 pass |
| `scripts/check.sh` (full gate, last) | 65 | **red**, at step 3 (iOS PR plan): 1764 tests, 1736 pass, 10 fail, 12 skipped, 6 expected failures. The 10 are mine (below). `LedgerAppKitTests` is the one bundle that failed; the other 16, `LedgerUITests` (Smoke) among them, passed |
| watchOS step and coverage gate, run as `check.sh` runs them (the gate stops at its first red step, so I ran its steps 4 and 5 after it, in the same hold of the lock) | 0, 0 | PR-Watch: 1454 tests, none failed, "8 test targets ran and passed"; coverage gate passes on both bundles (overall 98.48 %) |

UI tests, each run by me: `Smoke` passes in light and dark; `DebugMenu` passes in light and dark; `Tabs` (2 tests)
passes in light and dark; `LaunchPerformance` passes in light (it reports, it does not gate); `TabsAdversarial`
(7 tests) passes, and its accent test sets light and dark itself.

The 10 failing tests, all mine, all in `LedgerAppKitTests/Adversarial/`:

| Test | Finding |
|---|---|
| `CatalogBuildAdversarialTests.auditKey_isFoundationsKey` (1 of 12 cases) | F9-S1-1 |
| `CopyFileAdversarialTests.nestedLookupNotWrittenAsTheRule_isAFinding` (3 of 3) | F9-S1-2 |
| `CopyFileAdversarialTests.lookupThatFormatsANumber_withoutALocale_isAFinding` (2 of 2) | F9-S1-3 |
| `AppCopyAdversarialTests.catalog_neverNamesTheProduct` | F9-S1-4 |
| `CopyFileAdversarialTests.productNameInTheCatalog_isAFinding` | F9-S1-4 |
| `CopyAuditAllowedAdversarialTests.identifierOrSymbolChosenByCondition_isNoFinding` (4 of 4) | F9-S1-5 |
| `CopyAuditAdversarialTests.literalAfterALookalikeLabel_isAFinding` (3 of 3) | F9-S1-6 |
| `CopyAuditAdversarialTests.lookupOutsideTheCopyFile_isAFinding` (2 of 14) | F9-S1-7 |
| `CopyFileAdversarialTests.composedAndDecomposedKeys_areNotTheSameKey` | F9-S1-8 |
| `StringCatalogAdversarialTests.keysOutOfOrder_areAProblem` | F9-S1-9 |

## Slice S1 — round 2, close-out (G2 tester, 2026-10-05)

Branch `feat/F09-s1-tab-shell` at `6555960` (fix round 1). Specification: standards §7 as rewritten, the brief's
S1 criteria 4 to 6 as revised, and the two rulings of 2026-10-05.

**Result.** Nine of the eleven round-1 findings are closed and two are closed but for a named remainder
(F9-S1-3, F9-S1-10). The edits to my files are sound: no case lost its input, and the one test whose expectation was
lost is restored as far as the rulings keep it. The new gate step held against 36 of 37 fresh cases. Three new
findings, all low: one bug in the step and two questions for a ruling.

**G2 can close** once (1) the two rulings are built, which turns my three failing Swift tests green, and (2)
F9-S1-12 is fixed (one line) or accepted. F9-S1-13 and F9-S1-14 need a sentence each from the orchestrator and no
code unless ruled otherwise; they are pinned by passing tests. Nothing else is open on my side.

### Status of round 1's findings

| Finding | Status | Shown by |
|---|---|---|
| F9-S1-1 `%` in a key without a value | closed | the gate step compares with the compiler's keys: `string-catalogs.adv.sh` SC03–SC06, SC35, SC36 |
| F9-S1-2 lookup inside an interpolation | closed | `nestedLookupNotWrittenAsTheRule_isAFinding` (3, and the right form nested is now a finding); `CopyAuditCloseOutAdversarialTests.nestedLookup_isAFinding` (4 fresh: two deep, inside a call, in a multi-line literal, inside the timer form) |
| F9-S1-3 a value without `locale:` | closed as ruled (any value); remainder is F9-S1-14 | `lookupThatFormatsANumber_withoutALocale_isAFinding` (2); `valueWithoutALocale_isAFinding` (3 fresh: a text, with a comment, wrapped) |
| F9-S1-4 the product's name | closed | the sentence reads "The app tries again when you come back to it."; `catalog_neverNamesTheProduct` and `productNameInTheCatalog_isAFinding` pass; `productName_isAProblemInEveryEnglishText` (lower and upper case, a plural's `one` form; a comment and "Knowledge" are not problems) |
| F9-S1-5 identifier or symbol by a condition | closed | `identifierOrSymbolChosenByCondition_isNoFinding` (4); `literalUnderAnAllowedLabel_isNoFinding` (8 fresh) |
| F9-S1-6 a name that reads like a label | closed | `literalAfterALookalikeLabel_isAFinding` (3); `literalAfterALookalike_isAFinding` (11 fresh) |
| F9-S1-7 two lookup spellings | closed | `lookupOutsideTheCopyFile_isAFinding` (14 of 14); `lookupOutsideTheCopyFiles_isAFinding` (9 fresh, a letterless `Text("\(count)")` among them) |
| F9-S1-8 composed and decomposed keys | closed | SC13, SC14; catalog texts are compared scalar by scalar |
| F9-S1-9 the catalog's layout | closed | SC10–SC12, SC28, SC29; my ST10–ST15 (CRLF, indent, a tab, the colon, a byte-order mark, a trailing space) |
| F9-S1-10 limits not listed | closed; two edits to the list are due | §7 "Known limits", each pinned (`CopyAuditLimitTests`, my two "Limit" tests). a: exemptions name literals (`exemption_namesLiterals_aTitleInTheFileIsStillAFinding`, `exemption_neverCoversALiteralHandedToText`). d: an unread file must be wholly inside `#if DEBUG` (`previewsFile_isNotRead_othersAre`, `debugOnlyFileThatShips_isAFinding`, 8 fresh). e: SC10. Due: the list loses "a `Text` joined from parts" when ruling (a) is built, and gains F9-S1-14 unless it is found |
| F9-S1-11 test-quality | closed | `ShellSnapshotTests`: 12 references (two screens, light and dark, three sizes), two looked at, all pass in the gate. The Tabs preview has none, and the suite says why |

### Audit of the edits to my files (`git diff f45f5e9..6555960`)

- **Moved to `string-catalogs.adv.sh`: every case kept its input and its expectation.** Checked one by one:
  `auditKey_isFoundationsKey`'s twelve lookups (SC32–SC43; the keys are now proven by the real compiler, not by
  `LocalizedStringResource`), `parameterType_decidesTheSpecifier`'s four (SC44–SC47), `lookupInAComment_isNotALookup`
  (SC48), the composed and decomposed key (SC13, SC14), the seven near-misses (SC49–SC55), the two one-sided modules
  (SC56, SC57), keys out of order (SC11, SC12).
- **The deleted test, `interpolationNotABareParameter_isAFinding`.** Its eleven inputs are all there (SC58–SC66,
  SC69, SC70), each with the compiler's key as the new expectation. What was lost is the audit's refusal of a value
  that is not a bare `Int` or `String` parameter. Of that, the rulings keep two things. A `Double` or another type
  formatted into a key is refused through its specifier: restored as `doubleFormattedIntoAKey_isAFinding` and
  `keyWithAnotherSpecifier_isAProblem`, both failing until ruling (b) is built. An optional (keyed `%@`, shown as
  `Optional(3)`) stays a known limit: pinned by `CopyAuditLimitTests.limit_valueOfAKey` and SC63, SC67. The rest
  (an expression, a property, an `Int64`, a `Substring`, a formatted value) is harmless once the catalog is held
  to the compiler's key.
- **The edits flagged as beyond the sanctioned kinds: each follows a ruling and none weakens a test.** The exemption
  limit became a finding on a named line. `Text("\(Card.today)")` left the limit and is asserted as a finding. A
  bare previews file is asserted as a finding. The nested lookup's control is the join in two statements, and the
  nested right form is asserted as a finding. Two right lookups pass `locale:` for a text value. The sentence and
  `AppCopy.settingsTitle` follow criterion 4 and N8. The UI test's light bounds are the deep accent's (`#B2390E`;
  `#A73107` as displayed), with both thresholds as I set them.
- **What I changed this round.** `textMember_builtFromLookupsAndAView_hasNoFinding` is now
  `textJoinedFromParts_isAFinding` (ruling a; 3 cases, with the timer form as its control). New:
  `keyWithAnotherSpecifier_isAProblem` (ruling b; `%lf`, `%d`, `%f`, `%s`, `%i`) with its control
  `keyWithWholeNumbersAndTexts_isNoProblem` (`%lld`, `%@`, positional forms, `%%`, and "100% done"),
  `doubleFormattedIntoAKey_isAFinding`, the suite `CopyAuditCloseOutAdversarialTests` (9 tests), and one assertion
  in `TabsAdversarial`: on the light theme no tab wears the plain accent. One line outside my files:
  `check-wiring.adv.sh` W68 now lists six suites that need macOS, so that it accepts
  `string-catalogs-tester.adv.sh`.

### New findings

#### F9-S1-12 — bug (low): the gate step fails a matching catalog that is read-only

- **Rule.** §7: the step "reads the committed catalog and never writes it". A step that only reads works on a
  tree it cannot write.
- **Repro.** `string-catalogs-tester.adv.sh` ST23: a repository whose catalog matches, after `chmod -R a-w`.
- **Expected.** Exit 0. **Actual.** Exit 1, "is not written as Xcode's tool writes it", with a diff whose only
  difference is `\ No newline at end of file`, after `line 91: …/synced: Permission denied`.
- **Cause.** `with_final_newline` copies with `cp`, which keeps the file's mode, then appends a newline to the
  copy. The append fails on the read-only copy and the comparison runs without it. `cat "$1" >"$2"` would do.
- A catalog in a normal checkout is writable, so the gate is not affected today. This case fails `check.sh` at
  step 2 until it is fixed.

#### F9-S1-13 — spec question (low): a comment that only the catalog gives passes the step

- **Rule.** §7: "A translator's comment is written in code (`comment:`), and the catalog's `"comment"` is the same
  sentence, word for word."
- **What happens.** ST03 (passes, as a pin): the code gives no comment, the catalog's entry has one, exit 0. The
  tool keeps a comment the code does not give. The implementer's SC15 builds its sound module with one ("A comment
  only the catalog gives"). The other direction holds: a comment the code gives and the catalog lacks fails (ST01),
  a differing one fails (SC16), and one key looked up with two comments needs both in the catalog, in order, on
  two lines (ST04).
- **To rule.** Either the step refuses a catalog comment no lookup gives, or §7 says a comment may stand in the
  catalog alone.

#### F9-S1-14 — spec question (low): a locale written into a copy member passes the audit

- **Rule.** §7: "The caller passes the injected `@Dependency(\.locale)`", because a lookup that takes its locale
  from the device is one "a test cannot fix".
- **What happens.** `CopyAuditCloseOutAdversarialTests.limit_localeWrittenIntoTheMember` (passes, as a pin):
  `String(localized: "\(count) sets", bundle: .module, locale: .current)`, and the same with `Locale.current` and
  `.autoupdatingCurrent`, have no finding. The audit reads as far as `locale:`.
- **To rule.** Find it, or add it to "Known limits".

### What held

**The audit, re-checked** (`CopyAuditCloseOutAdversarialTests`, 9 tests, all pass, host and simulator): the rows
above, and the limit pins of round 1 (`regexLiteralHoldingAQuote_hidesTheLiteralAfterIt`,
`textMadeFromAName_hasNoLiteralToFind`).

**The gate step** (`string-catalogs-tester.adv.sh`, 37 cases, 36 pass; the implementer's 71 pass; three broken
variants of the script fail 11, 11 and 32 of my cases):

- Comments: ST01, ST02, ST04 as above.
- Modules beside each other: a module whose name starts with another's keeps its lookups (ST05); the same lookups
  in two modules with one catalog short of a key fail that module alone, by name (ST06); a catalog in a module with
  no Swift file fails (ST07).
- Layout: ST10–ST15. A second language beside English passes (ST16), and an unused key with a translation still
  fails (ST17).
- Paths with spaces: the repository, the build folder and the temporary folder (ST19–ST22); the temporary folder
  is left empty.
- A repository that cannot be written: a key failure and a layout failure are reported the same (ST24, ST25); a
  temporary folder that cannot be written fails the step (ST26).
- Keys with `$`, backticks, `*`, `$(…)` and a leading dash are compared as written (ST27, ST28). Five more
  near-misses fail both ways: a typographic apostrophe, a zero-width space, a tab, a trailing line feed, a
  fullwidth letter (ST29–ST33).
- A failing `xcstringstool` fails the step with what the tool said (ST34). An empty `.stringsdata` does not pass
  a catalog that lacks its key (ST37; the message is the layout diff with the script's own extra key in it, which
  is confusing but red).
- Reach, pinned so that a change shows: lookups in a module without a catalog are `CopyAudit`'s (ST08); a counted
  key's forms are `StringCatalog.problems`' (ST18); an x86_64 build's output is not read, with the clear failure
  (ST36); a source edited since the build is compared as it was built (ST09: `check.sh` builds first, a run by
  hand must too).

**Where the step runs in `check.sh`.** After the iOS build and before the iOS tests in the full gate,
`--ios-only`, `--skip-lint`, `--skip-static` and `--record-snapshots` (W02, W09, W49, W54, W62, W70–W74, all
pass; in my `--skip-lint` run it printed its line and checked one catalog of seven keys). `--fast`, `--lint-only`
and `--static-only` build no iOS and do not run it (W75). Those three runs do not say so: nothing in their output
mentions catalogs. §7 "Tiers" says the full gate proves copy; a line in the output would be one `echo`.

**Never writes into the repository.** SC21–SC23 hash every file before and after; ST23–ST25 run it on a tree
without write permission.

**The tint.** `TabsAdversarial.test_selectedTab_isDrawnInTheAccent_andNoOtherIs_lightAndDark` passes: the selected
tab alone wears the tint in both themes, and on the light theme no tab wears the plain accent. That the tint ends
at each stack is the implementer's `AppTabsTests.tabContentTint_setsTheTintBack` (passes) and one line of
`AppTabs.stack`; nothing a tab draws wears a tint yet, so the running app cannot show it (ruled: F09 S5).

**`MainRoot`'s three members.** `body`, `content`, `tabs`: the Debug menu still opens from Today's title after a
tour of the tabs and from no other title, and a ready root shows the shell on Today (`TabsAdversarial`,
`AppRootAdversarialTests`).

**Snapshots and the unchanged states.** `ShellSnapshotTests` pass; my pixel comparison of the can't-open screen
with `main`'s code, now with criterion 4's sentence, passes at seven appearances.

### Not verified

- CI itself: the runner with a compilation cache another run saved (the implementer measured a cache hit on a Mac;
  `docs/ci-cd.md` says the runner is not yet seen).
- Texts of other languages: the catalog rules read English only (state, specifiers, the product's name).
- A lookup compiled only for Release or only for watchOS: the step reads the iOS Debug build (§7 says so for
  watchOS).
- Housekeeping I did not do, because the files are not mine: `docs/ci-cd.md:40` and §7's "Known limits" name the
  suites and limit tests; `string-catalogs-tester.adv.sh` and `limit_localeWrittenIntoTheMember` are not named.

### UI tests (run by me, through the lock, iPhone 17, iOS 27.0, Nightly plan)

Light: `Smoke` 1 of 1, `DebugMenu` 1 of 1, `LaunchPerformance` 1 of 1 (mean 2.617 s; reports, never gates), `Tabs`
2 of 2, `TabsAdversarial` 7 of 7. Dark: `Smoke` 1 of 1, `DebugMenu` 1 of 1, `Tabs` 2 of 2. No failure.

### Commands and exit statuses

| Command | Exit | Result |
|---|---|---|
| `swift test --package-path LedgerKit --only-use-versions-from-resolved-file --filter LedgerAppKitTests` (host) | 1 | 191 tests, 3 fail, all mine (below) |
| `scripts/tests/adversarial/run.sh` | 1 | 12 suites; 559 cases pass, 1 fails (ST23) |
| UI tests, light, five classes | 0 | 12 of 12 |
| UI tests, simulator set to dark, three classes | 0 | 4 of 4 |
| `scripts/check.sh` (full gate, last) | 1 | **red at step 2**, on ST23 alone |
| `scripts/check.sh --skip-lint` (what the red step hides) | 65 | the string catalog step passes; **red at step 3**: 1788 tests, 1767 pass, 3 fail, 12 skipped, 6 expected failures; `LedgerAppKitTests` is the one bundle that failed |
| watchOS step and coverage gate, as `check.sh` runs them | 0, 0 | PR-Watch: 1454 tests, none failed, 8 targets passed; coverage 98.48 % overall |

Failing, all mine:

| Test | Why |
|---|---|
| `string-catalogs-tester.adv.sh` ST23 | F9-S1-12 |
| `CopyFileAdversarialTests.textJoinedFromParts_isAFinding` (3 of 3) | ruling (a): expected until the audit refuses `Text + Text` |
| `StringCatalogAdversarialTests.keyWithAnotherSpecifier_isAProblem` (5 of 5) | ruling (b): expected until the catalog check refuses other specifiers |
| `CopyFileAdversarialTests.doubleFormattedIntoAKey_isAFinding` | ruling (b), through the audit: green with the same change |

## Slice S2 — round 1 (G2 tester, 2026-10-05)

Branch `feat/F09-s2-domain` at `a016f8b`. Specification: the brief's "Plan amendments — slice S2, Domain additions"
(criteria 1 to 5), standards §5, ADR-007, spec §7.7 rules 34, 43 and 46.

**Result.** `nextScheduledDay`, `percentChange` and `Loadable` held under every attack. `thousands(in:)` agrees with
`compact(in:)` on every volume a lifter can store, and fails on one input the brief names, the smallest non-zero
volume: it reads an arbitrary number that changes from call to call (F9-S2-1, a hole it inherits from F02's
`compact`). One failing test, left failing on purpose. The other findings are two spec questions and one
test-quality note, none with a failing test.

61 tests written, in nine suites under `LedgerDomainTests/Adversarial/` (23 are parameterized: 1,816 cases in all).
On the host 61 run: 60 pass, 1 fails. Three are exit tests and run on macOS only, so a simulator runs 58.
No full gate was run (free disk under the floor; see the commands table), so nothing here ran on a simulator.

**Independence.** I did not read `implementation-notes.md`. I read the implementer's tests after my own had run on
the host. One slip: my first `grep` for the declarations printed four body lines of `nextScheduledDay`
(`blockStart`, `blockEnd`, the week index and the schedule lookup) before I had written a test. It suggested the
repeated-week-index attack, which found nothing. I read the bodies in full after my tests had run, and then added
three things: the 39-digit rows of `percentChange_thirtyEightDigitTotals_roundOnTheExactValue`, and two tests the
mutation run showed I lacked (`nextScheduledDay_weekIndexAtTheBlocksLength_isOutsideTheBlock`,
`nextScheduledDay_repeatedWeekIndex_readsTheFirst`).

### Findings

Severity is one of: bug, spec question, test-quality.

#### F9-S2-1 — bug (low; inherited from F02): the smallest volumes read an arbitrary number, not "0.0"

- **Criterion.** 3: `thousands(in:)` "is the number `compact(in:)` prints, without its k"; "Zero reads "0"; every
  other volume keeps one decimal". Rule 34: thousands of units to one decimal. The declaration adds: "It is cut from
  `compact(in:)`, so the two cannot disagree."
- **Minimal repro.** One input, the smallest non-zero `Decimal` (10⁻¹²⁷ g), through both functions:

  ```swift
  let volume = Volume(gramReps: .leastNonzeroMagnitude)
  volume.thousands(in: .lb)   // S2's function
  volume.compact(in: .lb)     // F02's function, which thousands(in:) is cut from
  ```

  Kept test: `VolumeThousandsAdversarialTests.thousands_smallestDecimalVolume_readsZeroPointZero` (4 expectations
  on `thousands(in:)`: the volume and its negative, in lb and kg). It fails, and stays failing.
- **Expected.** `thousands(in: .lb)` is "0.0" and `compact(in: .lb)` is "0.0k": the volume is not zero and is far
  under 50 units.
- **Actual.** Both misprint, so the fault is inherited from `compact(in:)`, and each call prints its own number.
  A scratch executable linking `LedgerDomain`, first call of each, in this order (log `probe-f9s2-1.log`):

  | Run | `thousands(in: .lb)` | `compact(in: .lb)` | `thousands(in: .kg)` | `compact(in: .kg)` |
  |---|---|---|---|---|
  | 1 | "431,782,111.3" | "431,784,903.3k" | "431,784,903.3" | "431,785,354.5k" |
  | 2 | "433,954,629.7" | "433,957,421.7k" | "433,957,421.7" | "433,957,872.9k" |

  So the two also disagree with each other on one volume, which criterion 3 and the declaration say cannot
  happen. In the test bundle the same call read "435,194,010.5", "438,344,975.3" and "436,742,180.1" on three
  host runs.
- **Where.** At 10⁻⁸⁸ g and at every smaller size I tried, of either sign, in both units (10⁻⁸⁰ g reads "0.0"),
  and for a volume that is not a number. No stored volume is near it: ADR-007 stores whole 10⁻⁷ g, which reads
  "0.0" (tested).
- **Cause.** `compact(in:)` divides twice; the second quotient underflows `Decimal`, which gives NaN.
  `Decimal.roundedToInt()` then asks `NSDecimalNumber.intValue` for a NaN, and Foundation does not define that
  value (it looks like stack contents). `percentChange` guards with `isFinite`; `thousands` and `compact` do not.
  `formatted(in:)` has the same hole (10⁻¹²⁴ g reads "4,335,603,657").
- **The other end, same root, not failing.** Above about 4 × 10²³ g the tenths no longer fit an `Int` and both
  texts wrap: 10²⁵ g reads "-89,866,669,963,703,866.9" in pounds, and the largest `Decimal` reads "0.0". There
  `thousands` and `compact` agree, so criterion 3 holds as written; the number is F02's.

#### F9-S2-2 — spec question: `percentChange` is `nil` in more cases than criterion 2 names, and sooner than its declaration says

- **Criterion.** 2: "It is `nil` when the previous volume is zero. It never traps". The declaration: `nil` too when
  "a volume is NaN, or the arithmetic leaves `Decimal`'s own range, about 10¹⁶⁵"; "A change too large for `Int` is
  clamped".
- **Observed.** `Volume(gramReps: 10¹²⁶).percentChange(from: Volume(gramReps: 1))` is `nil`. The change, 10¹²⁸
  percent, is a `Decimal` and too large for `Int`, so by the declaration it is `Int.max`; 10¹²⁵ after 1 is
  `Int.max`. Foundation's `× 100` adds exponents and overflows at 127.
- **Also.** Foundation divides −1 by 2¹²⁸ − 1 to NaN (and 1 by it to 0), so a volume one unit under a previous
  volume of 2¹²⁸ − 1 gives `nil`, not 0. Totals of up to 38 digits rounded exactly in every case I tried.
- **Ask.** Say in criterion 2 that NaN and overflow give `nil`, and correct "about 10¹⁶⁵" in the declaration. No
  volume a lifter moves is within a hundred orders of magnitude of this. My rows accept `nil` or the clamp
  (`percentChange_atTheLimitsOfDecimal_doesNotTrap`).

#### F9-S2-3 — spec question: a day the zone never had can be the answer

- **Criterion.** 1: "the first day after the given moment's calendar day, in the calendar's time zone, on which
  the program schedules a session"; each day judged "as `scheduledDay(on:in:)` judges it".
- **Observed.** Pacific/Apia went from Thursday 2011-12-29 23:59:59 to Saturday 2011-12-31 00:00. For a block that
  trains every day, the answer after that Thursday is Friday 2011-12-30: a day no instant of the zone falls on,
  and one `scheduledDay(on:in:)` can never return. The declaration promises that a 23- or 25-hour day is neither
  skipped nor counted twice; it does not speak of a day with no hours.
- **Reach.** Historic only as far as I know (Apia and Fakaofo 2011, Kiritimati 1994, Kwajalein 1993). It returns
  only if a country crosses the date line again.
- **Test.** `nextScheduledDay_acrossADayTheZoneSkipped_keepsToTheCalendar` pins what is not in question: the
  answer is the Friday or the Saturday and is consistent with itself, and from Saturday 00:00 it is Sunday.

#### F9-S2-4 — test-quality: three places where the implementer's tests assert less than they seem to

The implementer's tests are strong (see "Mutation run" below). Three weak spots:

- `VolumeTests.thousands_extremes_neverTrap` feeds `thousands` the two inputs of F9-S2-1
  (`.leastNonzeroMagnitude`, `.nan`) and asserts only that the text is not empty and has no "k". It passes on the
  arbitrary number.
- `Fixtures.everyDayProgram` schedules one template on every day of every week, so the midnight rows cannot see an
  answer that reads another weekday's or another week's schedule entry: the date and the week index are asserted,
  the template is the same everywhere. (Other tests do catch that mutant.)
- `LoadableTests.sendable_whenItsValueIs` proves a `Loadable` of a `Sendable` value crosses; it cannot see an
  unconditional conformance. `LoadableAdversarialTests.loadable_sendable_followsItsValue` asserts "only then".

### Attacked and held

**`nextScheduledDay` (criterion 1).**

- The brief's three examples at three times of day, and 25 hand-computed rows through the block (before it, its
  first day, every kind of day in weeks 1, 7 and 8, the last session, after it), each in 10 zones and all 7 week
  starts: 1,750 answers.
- One instant at both ends of UTC (Thursday on Kiritimati, Tuesday at UTC−12), and one second and one millisecond
  either side of midnight there.
- Every weekday as the block's first day × every week start × two schedules (the seed's, and one that trains
  every day with a template of its own for each week and weekday), at seven moments of every day from three days
  before the block to three after: 42,532 answers against two references that must also agree with each other
  (one walks noons with `scheduledDay(on:in:)`, one uses no `WeekCalendar` at all).
- 15 zones (Cairo, Santiago, Havana, Beirut, the Azores, Nuuk, Lord Howe, Chatham, Kiritimati, UTC−12, Pago
  Pago, New York, Berlin, Kathmandu, UTC), blocks that hold every 2026 clock change of each, the same seven
  moments a day including start + 23 h and start + 24 h: 136,710 answers. 15 more by hand: skipped midnights
  (Santiago, Havana), a second midnight (Havana), a 25-hour Thursday whose start + 24 h is still Thursday (Cairo),
  a 23-hour Saturday (Nuuk). Each hand row first confirms the zone's rule with Foundation.
- Seeded: 200 seeds (`17 + 7919·i`, i in 0..<200), each a random block (2 to 10 weeks, any start day in 2026 or
  2027, empty weeks, deloads, weeks handed over shuffled, one calendar in four starting on another day than the
  program says), a random zone of 18 and 40 moments. Four properties each: equal to the reference; strictly later
  than the moment's day, inside the block, scheduled as it says and with no earlier session (the day-by-day
  walk); chaining from each answer visits every session once, in order, and ends; a later moment never gets an
  earlier answer. No seed failed.
- Edited programs: no weeks; one week; empty weeks at the start, middle and end; only empty weeks; weeks out of
  order; scattered and negative indices; a week whose index equals the block's length; two weeks with one index
  (in process, and as an exit test); indices of `Int.max` and `Int.min`. All as `scheduledDay(on:in:)` and
  `isBlockComplete` read them. A schedule that names a template the program no longer has is returned as
  `scheduledDay(on:in:)` returns it: S3 must expect a `ScheduledDay` whose template it cannot find.
- Edges of time: 10 moments back to 31 million years ago and `Date.distantPast` give the first session; 7 moments
  forward to 31 million years and `Date.distantFuture` give `nil`; ±infinity, NaN and ±1e300 do not trap (exit
  test). A block running past 9999-12-31 answers up to that day; a block from 0001-01-01 answers from it.
- A block of 5,000 weeks whose only session is its last day: 8 calls and building the program took 0.04 s on the
  host. No time is asserted.
- A Buddhist, Hebrew, Islamic, Japanese, Persian or ISO 8601 calendar with another first weekday gives the same
  answers: only the zone is read.

**`percentChange` (criterion 2).**

- The brief's examples in pounds, kilograms and raw gram-reps. 28 hand rows of exact halves and the hundredth
  either side. Every half from −5.5 % to +5.5 % on 1,000 pound totals and 1,000 kilogram totals (24,000 answers).
  Totals summed set by set in pounds (185,000 lb ± 925 lb is ±0.5 %, ± one hundredth of a pound).
- Seeded, 200 seeds × 25 pairs each: weekly totals of up to 300 sets against an oracle that only multiplies
  (`|100·Δ − p·previous| ≤ |previous| ÷ 2`, ties away from zero) and against the formula in another order of
  operations; one stored unit (10⁻⁷ g) either side of an exact half on totals of up to 2 × 10¹² g; exact decimals
  of any sign and scale.
- 38-digit totals one unit either side of a half, and 39-digit ones 2.5 × 10⁻³⁹ percent either side.
- Zero previous in four spellings × six currents; NaN; negative volumes (10 rows, the formula as written).
- Tiny after huge (30 pairs, down to the smallest and up to the largest `Decimal`) is −100; huge after tiny
  clamps; exact at `Int.max − 1`, `Int.max`, `Int.min + 1`, `Int.min` and clamped one past each, also from a half.

**`thousands(in:)` (criterion 3).**

- 32 boundary rows in both units (49, 49.99, 50, 949.99, 950, 999,949.99, 999,950 …), eight conversion rows
  across units, a sweep of three values at each of the first 5,000 boundaries in both units (30,000 values) and
  200 seeds × 10 random totals: all equal to `compact(in:)` without its "k" and to a formatter written from rule
  34.
- Zero in six spellings reads "0" in both units; 10⁻⁷ g, 10⁻³⁸ g, ±1 g and other volumes under 50 units read "0.0".
- Negative and enormous volumes (to the largest `Decimal`) agree with `compact(in:)`.
- Locale: a scratch executable linking `LedgerDomain` printed the same bytes under `-AppleLocale` en_US, de_DE,
  fr_FR, ar_SA, hi_IN and fa_IR (each run printed its locale's separators to show the override took). Kept in the
  branch: every output is ASCII in the shape `-?d{1,3}(,ddd)*.d`.

**`Loadable` (criterion 4).** Exactly four cases (a switch with no `default`); `loaded` and `failed` carry what
they were given, for an optional, `Void`, nested and reference value; `Sendable` when its value is, and not when
it is not. §5 and the brief promise no equality and no accessors; there are none.

**Criterion 5.** Every file of `LedgerDomain` imports Foundation and nothing else. `git show --numstat a016f8b`:
the three source files and `VolumeTests.swift` have additions only, and the other test files are new. In a
scratch copy, the slice's test files alone (with the two existing suites they extend) leave no line of
`WeekCalendar.swift` or `Volume.swift` unexecuted; `Loadable.swift` is a declaration with no line to execute.

**Mutation run** (scratch copy of `LedgerDomain`, 28 hand-written mutants: 13 of `nextScheduledDay`, 10 of
`percentChange`, 5 of `thousands`). The implementer's tests killed 28 of 28. Mine killed 27 at first: "the block
is one day longer" survived until I added `nextScheduledDay_weekIndexAtTheBlocksLength_isOutsideTheBlock`.

### Not attacked

- Speed beyond the 5,000-week block; nothing asserts a time.
- An `Int` of 32 bits (a watch's arm64_32): simulators and the host have 64. My files hold no literal that needs
  more than 32 bits, but rows past ±2³¹ assume 64.
- Time zone data other than this machine's. The hand rows fail on their own first line if a rule changes.
- The device's locale inside the test bundle: the six-locale run was a scratch executable, not a kept test.
- How S3 uses a `ScheduledDay` ("Next: Friday · UB", "next Monday") and how a store uses `Loadable`.
- More mutants than the 28, and any mutant of `Loadable` (its checks are the compiler's).

### Commands and exit statuses

All from the worktree root. Logs are in the session's scratch folder (`f09s2-g2/`).

| Command | Exit | Result |
|---|---|---|
| `swift test --package-path LedgerKit --only-use-versions-from-resolved-file --filter "LoadableAdversarialTests\|NextScheduledDay.*AdversarialTests\|PercentChange.*AdversarialTests\|VolumeThousandsAdversarialTests"` (host) | 1 | 61 tests, 60 pass, 1 fails (F9-S2-1) |
| `swift test … --filter LedgerDomainTests` (host) | 1 | 884 tests in 144 suites; the same 1 fails, nothing else |
| `scripts/check.sh --lint-only` | 0 | format, lint, script tests |
| scratch package: the slice's tests with coverage (`swift test --enable-code-coverage`, `llvm-cov show`) | 0 | 46 tests; no line with a zero count in `WeekCalendar.swift` or `Volume.swift` |
| scratch package: 28 mutants × two test sets | 0 | see "Mutation run" |
| scratch executable: `thousands(in:)` and `compact(in:)` on the inputs of F9-S2-1, two runs | 0 | F9-S2-1's table |
| scratch executable: eight volumes through `thousands`, `compact`, `formatted` and `percentChange` under `-AppleLocale` en_US, de_DE, fr_FR, ar_SA, hi_IN, fa_IR | 0 | the same bytes six times |
| `scripts/check.sh` (full gate, through the lock) | not run | Free disk was 6.4 GiB and falling, under the 8 GB floor, with two other worktrees' gates ahead of mine on the lock. I did not start it and deleted nothing. Ruled by the orchestrator (2026-10-05): its own full gate on this branch, after the fix round for F9-S2-1, replaces mine |

Not verified, because the gate did not run: my 58 non-exit tests on the iOS and watchOS simulators (they build
and run on the host only so far), the string-catalog step, and the coverage gate with my tests in the bundle.
Expect the gate red at step 3 on `thousands_smallestDecimalVolume_readsZeroPointZero` until F9-S2-1 is fixed, if
the simulator's Foundation reads the same arbitrary number.

The failing test, mine:

| Test | Finding |
|---|---|
| `VolumeThousandsAdversarialTests.thousands_smallestDecimalVolume_readsZeroPointZero` (4 expectations) | F9-S2-1 |

## Slice S3 — round 1 (G2 tester, 2026-10-05)

Branch `feat/F09-s3-presentation` at `906d5a8`. Specification: the brief's "Plan amendments — slice S3, the
presentation" (criteria 1 to 12), the body's criteria 1 and 3 to 11 and its "Copy (exact)", spec §3.5, §6.4 and
§7.7, decisions #14, #15, #18 and #26, standards §5 and §7.

**Result.** The presentation held against almost everything. Every worked example of the brief reads text for text
and number for number, in pounds and in kilograms, with a Monday and a Sunday week start. For 4,000 seeded inputs
the card, its routes, the header, the strip's seven cells and both tiles are what my own model of the
specification gives. Two things broke, each with a failing test left failing:

- **F9-S3-1** (bug, low): with two finished workouts of today's session, the Logged card shows the one that comes
  first in `weekWorkouts`, not the one that started last, unless the caller sorted them. The input promises no order.
- **F9-S3-2** (copy, low): the volume tile's spoken text is joined with a `", "` written in the presentation, not
  in the catalog.

Four spec questions and one test-quality note follow, none with a failing test. Nothing trapped.

96 tests written, in 12 suites and 26 files under `LedgerKit/Tests/FeatureTodayTests/Adversarial/` (47 are
parameterized: 341 cases). Host: 93 pass, 3 fail. iPhone 17 simulator (iOS 27.0), the whole target: 185 tests, 182
pass, the same 3 fail; the implementer's 89 all pass.

**Independence.** I did not read `implementation-notes.md` or `review.md`. I learned the code from a `grep` of
declarations and doc comments. What that showed me beyond signatures, before my tests existed: the doc comment of
`+Card` lists the order of the card rules (a live workout first, also with no program and after the block), which
is how my model reads criterion 4's first sentence too; and one `grep` for a tag printed two declaration lines of
the implementer's `Support/TodayTesting.swift` (`@Tag static var feature`, `struct SeededGenerator`), which I used
only to avoid a name clash. I read the String Catalog after the worked-example, card, date, week, tile, preview and
recent suites had run; the expected text "Today, Wednesday, September 16" in the spoken suite comes from it, since
the brief gives none. While repairing my own source scan I read one screen of `TodayCopy.swift` (how a lookup is
written) and grepped the sources for joiners; that grep is where I first saw the line of F9-S3-2, before the test
that now reports it existed. I read the feature's bodies and the implementer's tests after all my suites had run,
and added no test afterwards.

The round was interrupted once by a usage limit. Every number below is from runs made after it.

### Findings

Severity is one of: bug, copy, spec question, test-quality.

#### F9-S3-1 — bug (low): of two workouts that log today's session, the card shows the first handed in, not the newest

- **Criterion.** 5: "When today's session was finished today (a finished workout of the same program, week and day
  that started today …) the card shows … the elapsed time, "{done} of {total} sets · {volume} lb moved", "View
  session" carrying `.openWorkout(id)`". The declaration of `loggedWorkout(for:_:)` adds "the newest if there are
  several". `TodayInput.weekWorkouts` states no order; its neighbour `recentWorkouts` states "newest first".
- **Minimal repro.** `TodayCardAdversarialTests.sessionDoneTwice_showsTheLaterOne(_:)`, case `newestFirst: false`.
  The seed program from Monday 2026-09-14, now Wednesday 09-16 11:00 UTC, and Lower A of week 1 finished twice
  today: started 06:00 (ten minutes long) and started 09:00 (24:22 long), handed in as `[06:00, 09:00]`.
- **Expected.** The card of the 09:00 workout: `.openWorkout` of its id, elapsed "24:22".
- **Actual.** The 06:00 workout: its id, elapsed "10:00". Handed in as `[09:00, 06:00]` the same test passes.
- **Where.** `TodayPresentation+Card.swift:47`, `context.finished.first { … }`. `withFinishedSession` places the
  session's own workout by its start under the same assumption.
- **Seeded.** `TodayCardModelAdversarialTests.seededInputsInAnyOrder_showWhatTheSpecificationGives(_:)`: 12 of
  4,000 seeds, in 7 of the 8 batches: 26, 485, 896, 999, 1135, 1403, 1834, 2115, 2746, 2906, 3046, 3264. Each
  reports only this ("logged carries openWorkout(…), not the newest of today's"). With the same 4,000 inputs handed
  in newest first, nothing disagrees.
- **Why low.** `WorkoutRepository.workouts(in:)` returns newest first, so a store that makes one read over the
  union of the stats week and the program week satisfies it. Nothing says it must: S5 is not written, and the type
  that carries the list is silent. Either pick the newest by `startedAt`, or state the order on
  `TodayInput.weekWorkouts` and pin it in the store's test.

#### F9-S3-2 — copy (low): the volume tile's spoken text is joined by a literal outside the catalog

- **Criterion.** 10: "Every text is the body's "Copy (exact)", resolved in `TodayCopy` … (a counted value per key,
  fragments joined with " · " …), and spoken texts are copy too." Standards §7: presentation builders "hold
  neither a user-facing literal nor a localized lookup".
- **Minimal repro.** `TodayPurityAdversarialTests.joiner_isTheMiddleDot()`: a scan of the module's sources outside
  the copy files for any string literal that is not empty and not `" · "`. One hit:
  `TodayPresentation+Stats.swift:49`, `spoken.compactMap(\.self).joined(separator: ", ")`.
- **Expected.** The join comes from `TodayCopy` (one key for the whole spoken line, such as "%@, %@"), or is the
  " · " every other line uses.
- **Actual.** VoiceOver's text for the tile is "24,180 lb moved, +8%" with a comma and a space no translator sees.
  The repository's copy audit passes it because the literal holds no letter.
- **Judgement.** Small, and a one-key fix. I report it because the criterion names spoken text, not because a
  lifter would notice in English.

#### F9-S3-3 — spec question: "next Wednesday" for tomorrow, when the block began on another weekday than the week starts on

- **Criterion.** 6: "The three bodies of the copy, by where the next session is (later this week, in a later week,
  none left)". It does not say which week: the strip's or the program's.
- **What happens.** The code uses the program week (as its declaration says). With the block begun on Wednesday
  2026-09-16 and the week starting on Monday, Tuesday 11-03 reads "Nothing scheduled for Tuesday in week 7. Next up
  is next Wednesday." Wednesday 11-04 is tomorrow, the next cell of the same strip, marked planned. The same on
  Tuesday 09-22 in week 1, and the Logged card on Monday 09-21 reads "Next: week 2" for Wednesday.
- **Pinned as it behaves** by `TodayWeeksAdversarialTests.blockBegunOnWednesday_usesEachDaysOwnWeek(_:)`,
  `…loggedCard_namesTheNextSession(_:)` and `TodayTilesAdversarialTests.straddlingWeek_keepsTheTwoWeeksApart()`.
  Those tests change if the answer does.
- **Question.** Should "next {weekday}" and "Next: week n" follow the seven days the lifter sees? It arises only
  when the start date's weekday is not the week start (a week start changed in Settings after the block began).

#### F9-S3-4 — spec question: the rest-day body before the block begins

- **Criterion.** 6: "a day before the block begins is a rest day whose next session is the block's first".
- **What happens.** Twelve days before a block that begins on Monday 2026-09-28: "Nothing scheduled for Wednesday
  in week 1. Next up is Monday." The day is in no week, and "Monday" is not the coming one. Two days before a block
  that begins on a Friday: "… Next up is Friday.", which reads right.
- **Pinned loosely** by `TodayWeeksAdversarialTests.beforeTheBlock_isARestDayOfWeekOne(_:)` (either form of "next
  up" passes; the edit route and the sheet name week 1).
- **Question.** Does this day want its own sentence ("Your block starts Monday."), which the brief does not give?

#### F9-S3-5 — spec question (copy): "This is the last week of the block." in week 1 of 8

- **Criterion.** 6 picks the third body when no session is left. The body's text says more than that.
- **What happens.** With weeks 2 to 8 emptied, Sunday of week 1 reads "Nothing scheduled for Sunday in week 1. This
  is the last week of the block." It is not. Pinned as specified by
  `TodayWeeksAdversarialTests.nothingLeftBeforeTheLastWeek_saysSo()`. Only an edited block reaches it.

#### F9-S3-6 — spec question: a session whose exercises are not stored still shows its full estimate and "Start workout"

- **Criterion.** 12: "a slot whose exercise is no longer stored has no preview row". Nothing about the rest.
- **What happens.** With one of Lower A's four exercises gone the card has three rows and "Week 1 of 8 · ~38 min",
  and the off-schedule list reads "3 exercises · ~38 min". With all four gone: no rows, "~38 min", "0 exercises ·
  ~38 min", and "Start workout" all the same. `SessionBuilder.build` throws `.unknownExercise` for such a day, so
  the button leads to a failure F10 has to show. Printed by
  `TodayPreviewAdversarialTests.slotWithoutItsExercise_hasNoRow(_:)`; not judged.

#### F9-S3-7 — test-quality: no test of the implementer's hands the week's workouts in another order

`TodayPresentationPropertyTests` sorts `weekWorkouts` newest first before every call, and
`logged_twiceToday_showsTheNewest` hands `[second, first]` under the comment "The repository hands workouts newest
first". So the precondition behind F9-S3-1 is known, not written on the input, and not pinned. Otherwise the
implementer's 89 tests assert behaviour: literals from the brief, a reference written with Foundation's calendar
alone, small values in every `#expect`, nothing disabled. Their seeded reference checks the card's kind, the
strip's days and spoken dates, the sessions done and the volume; it does not check planned marks or the planned
count under a program, the week and day of a route, the header's title, or which workout is logged. Their example
tests cover those, and my seeded model now does for 4,000 inputs.

### Texts the brief does not give

Everything drawn or spoken comes from the catalog's 49 keys, from data (names, tags) or from the Domain's and
Foundation's formatters, but for the join of F9-S3-2. Each key is asserted with a literal by at least one of my
tests.

| Text | Where | Judgement |
|---|---|---|
| "Today, %@" ("Today, Wednesday, September 16") | spoken label of today's strip cell once it is trained | Good: the mark then says "Done", so nothing else says which day is today. |
| "%lld%%" ("0%") | the change when it rounds to nothing | Good. The brief has only "+8%" and "−3%"; "+0%" would be worse. |
| "24,180 lb moved, +8%", "10,968 kg moved", "0 lb moved" | spoken text of the volume tile | Sensible: the whole number the tile rounds, then the change as drawn. The join is F9-S3-2. It does not say what the change is against, and neither does the tile. |
| "%@ of %lld session this week", "%@ of %lld set", "%lld exercise", "%lld week done. …" | singular forms | Needed. The form follows the counted number, so "2 of 1 session this week" can be heard; correct, slightly odd. |
| "/%lld" and "k" | the tiles' light suffixes | The brief's "%lld/%lld" and "%@k" in two parts, for `StatTile`. Joined they read the same. |
| "Deload", "~%lld min", "%lld min", "%lld exercises", "%@ lb", "%@ lb moved", "Week %lld of %lld", "%@ of %lld sets" | fragments | The brief's lines cut at each " · ", as standards §7 asks. Joined they are the brief's. |
| "kg moved", "%@ kg", "%@ kg moved" | kilograms | The brief names them in brackets. |
| "Today" as the header's title | no program, block complete | S3 criterion 1, not the body. |
| "Next: week 4" | Logged, with an empty week 3 ahead | The brief says "week {n+1}"; the code names the week the next session is in. Better than naming a week with nothing in it. |
| U+2068 … U+2069 around a right-to-left tag in "Next: Friday · {tag}" | Foundation | Not a text: the isolates keep the line's order. Names and tags are otherwise shown byte for byte. |

The tile's caption and its change are two fields ("lb moved", "+8%"); the brief's "lb moved · +8%" is left for S4's
view to join.

### Attacked and held

**Worked examples** (15 tests, `TodayWorkedExamplesAdversarialTests`). Criteria 1, 3, 4, 5, 6, 7, 8, 9 and 11 with
every number worked out by hand in a comment: "Week 1 of 8 · ~38 min", the four rows in pounds and in kilograms
("5 × 5 @ 113.4" …), "Resume · 3:00", "15 of 15 sets · 30,370 lb moved" and "13,776 kg moved", "Next: Friday · UB",
the deload week ("Week 8 of 8 · Deload · ~29 min", "2 × 11 @ 47.5" …), all four off-schedule details, "2/4",
"24.2k", "+8%", a real minus in "−3%", "11.0" thousand kilograms, the Sunday strip. Criterion 10 is in the recent
suite.

**Which card** (`TodayCardModelAdversarialTests`, `TodayCardAdversarialTests`; `TodayOracle` is my model, written
from criteria 1, 2 and 4 to 8 with Foundation's calendar and integer day arithmetic).
- Seeds 0 to 3999, handed in newest first: 0 disagreements on the card and its route (program, week, day or
  workout id), the title, the header's date, each cell's letter, number, mark and spoken date, sessions done and
  planned, the volume, its caption and its change. The seeds give 794 resume, 537 start, 518 logged, 1,363 rest,
  336 no program and 452 block complete, over 11 time zones, 7 week starts, both units, blocks begun on any
  weekday within ten days of 09-14 with weeks emptied, a Sunday session added, a weekday removed or the block cut
  to two weeks, moments from nine days before the block to nine days after it (the first instant of a day, its
  second second, its last second, noon, any other), and a session that is absent, live, finished and unknown to
  history, finished and known, or discarded.
- Seeds 0 to 299: the same input gives the same model, twice from one input and once from a rebuilt one.
- Case by case, by hand: a workout live for another day, on a rest day, after the block and with no program; the
  session done yesterday (offered again), twice today, for another program, another week, another day and no
  program; the session's finished workout with and without history's copy (counted once; in the strip, the tiles
  and the list); a discarded session and unfinished rows of history (count for nothing); a workout that goes live
  after today's was logged; a start still ahead of the clock ("Resume · 0:00").

**Dates and weeks** (`TodayDatesAdversarialTests`, `TodayWeeksAdversarialTests`).
- Twelve hand rows at UTC+14, UTC−12, UTC+5:45 and UTC, a second before and at midnight.
- Every clock change of 2026 in ten zones (Santiago, Cairo, Havana, Beirut, Lord Howe, Chatham, St John's,
  London, New York, Lisbon): 16 moments each, 160 in all, from a day before to a day after, against a civil date
  found by adding the zone's offset and against the model. Leap day 2028 and the turn of 2026 to 2027.
- The weekdays named in the rest-day body, the Next line and a recent row in six far zones; a next session on the
  Sunday whose midnight Santiago skips.
- The block's first day, its last two and the day after; a block begun on a Wednesday (six days, each cell by its
  own program week, the routes and the sheet naming the program week); a week with no sessions (no planned marks,
  "/0", "next Monday" from both sides of it); a block of one week ("Week 1 of 1", "1 week done."); a block that
  has not begun; the six ordinary rest-day rows; eight Next lines.

**The strip, the tiles and the card agree** (`TodayTilesAdversarialTests`). "5/4" with two workouts on one day;
seven volumes on and around rounding ties in both units, up to 123,456,789 lb; seeds 1 to 400: the tile and its
spoken number against my own sum of grams × reps over done sets of every kind, in eighths of a pound and of a
kilogram; twelve changes (+8, −3, 0, none, a zero week, ±0.5 % ties, ±0.49 %, +100, −100, +1,999,900); the Logged
card with 15, 9, 1 and 0 of 15 sets done, the drop set counted, in both units; "0 of 0 sets", "1 of 1 set";
off-schedule marks by program week while the tiles follow the strip.

**Preview rows and time** (`TodayPreviewAdversarialTests`). All 32 days of the seed (4 days × 8 weeks) in both
units against `ProgressionRules.prescribe` and `TimeEstimate.minutes` called by me, with two slots' misses set;
the off-schedule estimates of all 8 weeks; a held load by hand; missing exercises; catalog start loads in both
units; a live workout's own rows for 12 workouts in both units, a swapped exercise, a renamed workout, an
exercise the catalog no longer holds, a workout of another program and one with no exercises.

**Recent** (`TodayRecentAdversarialTests`). Criterion 10 in both units; 0, 1, 4, 5, 6 and 7 handed in; twelve
timings ("Today · 0:00" to "Today · 10:22:05", "Tue · 1 min" to "Tue · 120 min", a workout that crossed midnight,
the same weekday a week ago); Today by the injected zone at UTC+14 and UTC−12; the session's workout placed by
its start and listed once; two workouts with one start; volumes to "1,234,567 lb".

**The words** (`TodayCopyAdversarialTests`, `TodaySpokenAdversarialTests`). Exercises and minutes for 0, 1 and 2;
weeks for 1, 2 and 8; the scalars of "−3%", " · ", "×" and "—"; six English locales (en_US, en_DE, en_CH, en_IN,
en_ZA, en_SE) on a 1,200-week block with 1,500 workouts: weeks, sessions and minutes grouped as the locale groups
them, and every other text equal once separators between digits are removed, the Domain's volumes unmoved; 48,400
texts of 1,000 seeded models: none empty, untrimmed, with a placeholder, "nil", a double space, a stray "·" or the
product's name. Spoken: the seven dates, today's cell once trained, the sessions tile for six pairs, the volume
tile for seven.

**Purity** (`TodayPurityAdversarialTests`). My own scan of the module's 11 sources for 16 patterns (a clock,
`.current`, formatters with defaults, a calendar, locale or zone built in place, `Double` and its kin, random):
no hit. No worded literal and no lookup outside the copy files; all 49 lookups read `.module`, and each that
carries a value passes `locale: locale`. The date's words in fr_FR, de_DE, ja_JP, es_MX and en_GB against a style
I built; the calendar's own locale and first weekday change nothing; seven other calendars name one day in the
header, the cell and its spoken date; ten loads on rounding ties print as the Domain prints the exact weight.

**Robustness** (`TodayRobustnessAdversarialTests`): no trap. A program with no weeks and no days; a schedule
naming a day the program lost; weeks out of place on 21 days; eleven names (format specifiers, empty, only a
dash, right-to-left, emoji, 400 characters, a line break); six weights (zero, negative, not a number, the largest
and smallest decimal, 2⁵³ + 1 lb) against seven previous volumes in both units; thirteen moments for the clock and
for a workout's start and end (to infinity and not-a-number); the first and last day a `CivilDate` holds; a source
week of `Int.max`, `Int.min`, −1, 8 and a million.

Seen there and not judged: a moment outside the years 1 to 9999 gives a card and an empty strip, and a
not-a-number moment an empty date; on 9999-12-31 and 0001-01-01 the strip is shorter than seven where the week
runs past the calendar; a schedule that names a lost day gives a rest-day card while the strip and "/4" still
count that day as planned; a program with no weeks reads "0 weeks done." from its start date on; minutes round
down ("58 min" for 58:59); a recent list handed in out of order is shown in that order (its declaration says
"newest first"); a live workout of week 2 on a week-1 day reads "Week 2 of 8 · ~37 min", and one of another
program has no meta line.

### Not attacked

- Line coverage of `TodayPresentation` (criterion 11): not measured by me. The coverage gate is the orchestrator's.
- The catalog against the compiler's keys (`scripts/check-string-catalogs.sh`): the gate's step.
- No mutation run this round.
- Views, snapshots, the store, `Text(timerInterval:)` counting up, a double tap: S4 to S6.
- Plural rules and words in a language other than English; right-to-left layout.
- watchOS, a 32-bit `Int`, and time zone data other than this machine's and the simulator's.
- Speed: nothing asserts a time. The 1,200-week block with 1,500 workouts ran in under 0.2 s on the host.
- The device's own locale and zone inside the bundle: the host ran in America/Chicago and the simulator under the
  PR plan; both gave the same results, but neither was varied.

### Commands and exit statuses

All from the worktree root. Logs are in the session's scratch folder (`f09s3-g2/`). The full gate is the
orchestrator's and was not run.

| Command | Exit | Result |
|---|---|---|
| `swift test --package-path LedgerKit --only-use-versions-from-resolved-file --filter "FeatureTodayTests\..*AdversarialTests"` (host) | 1 | 96 tests in 12 suites: 93 pass, 3 fail (10 issues) |
| `swift test … --filter FeatureTodayTests` (host) | 1 | 185 tests in 16 suites: 182 pass, the same 3 fail |
| `sim-lock.py` → `scripts/sim-destination.sh`, `scripts/sim-boot.sh`, `xcodebuild build-for-testing` and `test-without-building -only-testing:FeatureTodayTests`, Ledger scheme, PR plan, iPhone 17, iOS 27.0, with `check.sh`'s flags | 65 | 185 tests: 182 pass, the same 3 fail. Build exit 0. |
| `scripts/check.sh --lint-only` | 0 | format, lint, script tests |

The simulator ran twice, not once as briefed. The first run's build printed a compiler warning in my
`TodayAdversarialScenario.swift` (a redundant `#require`). I fixed it, checked on the host that the 4,000 inputs
and their outcome counts were unchanged, and ran again so that the result is for the files as they are. Both runs
gave 182 of 185. Both result bundles are deleted; free disk stayed at 16 GiB.

The failing tests, mine, left failing:

| Test | Finding |
|---|---|
| `TodayCardAdversarialTests.sessionDoneTwice_showsTheLaterOne(_:)`, case `newestFirst: false` (2 expectations) | F9-S3-1 |
| `TodayCardModelAdversarialTests.seededInputsInAnyOrder_showWhatTheSpecificationGives(_:)`, 7 of 8 batches | F9-S3-1 |
| `TodayPurityAdversarialTests.joiner_isTheMiddleDot()` | F9-S3-2 |

Expect the gate red at its iOS test step on these three until the two findings are settled.
