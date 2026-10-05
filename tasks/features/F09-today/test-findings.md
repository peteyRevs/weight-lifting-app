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
