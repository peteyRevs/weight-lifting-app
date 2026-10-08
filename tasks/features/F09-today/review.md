# F09 — review

## Slice S1 — review (G3 reviewer, 2026-10-04)

Reviewed: `git diff a24eb60..59acf9d` on `feat/F09-s1-tab-shell`, against the brief's "Plan amendments" (S1's six
criteria), standards, architecture, the notes' S1 section and "M1 shared conventions". Paths that start with a
module name are under `LedgerKit/Sources/`; test paths are under `LedgerKit/Tests/`.

**Verdict: not approved. 1 Blocking, 7 Should fix, 12 Nits, 3 points I could not settle.**

The shell itself is sound: the six criteria are met, the `Tab` / `TabView(selection:)` / `NavigationStack(path:)`
use matches Apple's own example, isolation is right, nothing from S2–S6 leaked in, and no forbidden construct or
lint suppression was added. The Blocking finding is in the shared check, not in the shell: for one class of key
the audit rejects the correct catalog and accepts only a wrong one. Most of the Should-fix findings are about the
two rules as later features will read them.

### What I ran

- `/code-review` at effort `high` on the range (ran as a forked skill; 10 findings, each triaged below).
- Host, on the committed tree before the tester's files appeared: `swift test --package-path LedgerKit
  --only-use-versions-from-resolved-file --filter LedgerAppKitTests`: 89 tests in 16 suites passed (the notes'
  number). This includes `PreviewTests` for LedgerAppKit's four previews through the new Mac path.
- `xcrun xcstringstool` (Xcode 27.0, 27A266a) `compile`, `sync`, `extract` and `generate-symbols` on scratch catalogs.
- Foundation probes on the host (`String(localized:)` against a bundle compiled from a scratch catalog) and
  `swiftc -emit-localized-strings` to read the compiler's own keys.
- The three helper files as committed, copied into a scratch package with a stub `PreviewScan`, run against about
  70 source lines. Every row marked "run" in the tables below is that harness's output.
- The iOS 27.0 SDK's `.swiftinterface` for `Tab`, `toolbar(_:for:)` and `Text`'s `+`; sosumi for `Tab`, `TabView`,
  `NavigationStack`.
- The four screenshots, pixel-sampled for contrast.

Scratch folder: `/private/tmp/claude-501/-Users-peterarevalo-Dev-workout-app/1007ba2a-4cb4-4801-a9fe-bc3f1e348a39/scratchpad/f09s1-g3`
(`xc/` catalogs and probes, `audit/` the harness, `extract/` compiler keys, `px/` contrast).

### Blocking

**B1. The audit doubles `%` in every lookup key; the compiler doubles it only when the key has an interpolation.**
`LedgerTestSupport/Localization/CopyAudit.swift:217` (`key += text.replacing("%", with: "%%")`).

- Measured three ways. `dump("100% done" as String.LocalizationValue)` gives `key: "100% done"`; with an
  interpolation, `"%lld%% done"`. `swiftc -emit-localized-strings` extracts
  `"One extra set at −15% after the last working set."` unchanged. `xcstringstool extract` agrees.
- The harness, with `String(localized: "One extra set at −15% after the last working set.", bundle: .module)`:
  - catalog key written as the English text (what standards §7 says to write): two findings, `looks up "…−15%%
    after…", which the catalog does not hold` and `"…−15% after…" is not looked up by a copy file`;
  - catalog key written with `%%`: no findings.
- At run time, with the `%%` catalog the audit demands, the lookup misses the table
  (`localizedString(forKey:value:table:)` returns the fallback) and the lifter sees the key. That is the right
  English by accident, the catalog's entry is dead, and `builtBundle_resolvesEveryKey` still passes because it asks
  only for the catalog's own keys. So both tests of the standard are green while the string does not come from the
  catalog.
- Why it matters: that exact string is F11's copy (`tasks/features/F11-program-builder.md:60`). The notes tell the
  next lanes the wrong rule: "A literal `%` in copy is `%%` in the catalog key"
  (`implementation-notes.md:1092`). The only `%` test has interpolations (`CopyAuditTests.swift:27`, `:50`).
- Fix: in `key(of:)`, double `%` only when the literal has at least one interpolation. Add two cases to
  `CopyAuditTests`: a plain key with `%` is keyed as written, and a catalog that doubles it is a finding. Correct
  `implementation-notes.md:1092` and add one sentence to standards §7 ("`%` is written `%%` in a key that carries a
  value, and `%` in one that carries none, as the compiler keys them").

### Should fix

**S1. The one exception in the rule, a copy member that returns `Text` around a timer, has no spelling that is both
warning-free and audited.** `docs/engineering-standards.md:190-193`; `implementation-notes.md:1057-1061` (open
question 10).

- The notes recommend building the `Text` from the looked-up word, " · " and `Text(timerInterval:)`. Joining
  `Text`s with `+` is deprecated at this project's deployment target (SDK: `deprecated: 26.0, "Use string
  interpolation on Text instead"`; `swiftc -target …26.0` warns on it).
- The two spellings that compile cleanly from a `nonisolated enum`:
  - `Text("\(word) · \(Text(timerInterval: …))")`: the audit passes it only because " · " has no letter. It is a
    bare `Text("…")` (the thing the same paragraph forbids), and the compiler extracts the key `%@ · %@`, which
    Xcode's sync would add to the module's catalog.
  - `Text("Resume · \(timerInterval: …)", bundle: .module)`: a real format key, `Resume · %@`, which is the brief's
    key (`F09-today.md:48`). The audit rejects it (run: "a string literal that is not a lookup").
- Why it matters: F09 S4's "Resume · m:ss" is the first use, and F10 has timers too. Left as written, each lane
  picks its own way.
- Fix: decide now. I recommend the second spelling: teach `CopyAudit.copyFile` one more lookup form
  (`Text("…", bundle: .module)` whose only interpolation is `timerInterval:`, keyed `%@`), test it, and write the
  spelling into §7.

**S2. Misses that matter for M1 screens, and no check against the compiler's own keys.**
`CopyAudit.swift:147-155`, `:209-227`, `:231-245`.

- `Text("\(done)/\(total)")` and `Text("\(sets) × \(reps)")` in a view pass (run). Both are bare `Text("…")`
  lookups (compiler keys `%lld/%lld`, `%lld × %lld`), both are listed as copy in the F09 and F10 briefs, and the
  numbers are formatted with the environment's locale, not the injected one.
- A lookup with an `Int` in its key and no `locale:` passes; §7 says "with `locale:` when it formats a number".
- A local that shadows a parameter (`let count = String(count)`) is keyed `%lld` by the audit and `%@` by the
  compiler (run, and `-emit-localized-strings`).
- Fix, in the helper: outside a copy file, a literal with an interpolation is a finding unless its lead is allowed;
  in a copy file, a lookup with an `Int` parameter must carry `locale:`.
- Fix, at the root: every build already writes the compiler's keys (`…/LedgerAppKit-t.build/Objects-normal/arm64/
  *.stringsdata`). A gate step that runs `xcrun xcstringstool sync` on a temporary copy of each catalog with its
  target's `.stringsdata` and compares the result with the committed file (ignoring the final newline) would catch
  B1, the shadowing case, stray `Text` keys and preview literals with types, and would prove on every gate what
  proof 3 showed once by hand. I ran it for `LedgerAppKit`: no difference.

**S3. An exemption is a whole file, on a free-text reason nobody checks.** `CopyAudit.swift:25`, `:55-59`;
`LedgerAppKitTests/AppCopyTests.swift:10-13`.

- Run: an exempt `TodayStore.swift` holding `LedgerLogger(category: "today")` and
  `var failure = "Can't show today right now"` has no findings.
- `AppComposition.swift` is exempt for four literals (`"-LEDGER_UITEST"` twice, `"launch"`, the temporary database
  path). F10 edits that file next; anything it adds there is unread.
- The false alarms listed below (a symbol or identifier chosen by state, a logger's category, `reportIssue`, a URL)
  are common in views and stores, so the cheapest way out for a later implementer is to exempt the file that holds
  the copy.
- Fix: exempt literals, not files (`exempting: ["AppComposition.swift": ["-LEDGER_UITEST", "launch", …]]`, a new
  literal in the file is a finding), or add the missing leads (`category:`) so `LedgerAppKit` needs one exemption.
  Verify a "Debug only" exemption mechanically (the file is wrapped in `#if DEBUG`). In §7, say who decides: the
  G3 reviewer confirms each exemption, and a file that declares a view, a store or a presentation builder is never
  exempt.

**S4. Test 2 of the standard is never shown to fail.** `StringCatalog.swift:111-116`;
`AppCopyTests.swift:22-25`, `CatalogFixtureTests.swift:53-58`.

- Both callers assert `unresolvedKeys(in:) == []`. No committed test shows a key the bundle lacks being returned;
  the native-build failure was measured in a scratch package only.
- Fix: one test, `try TestCatalog.plain("Not in the bundle").unresolvedKeys(in: .module) == ["Not in the bundle"]`.
  While there: a multi-line `"""` key is refused (run: it is, untested), and a `needs_review` unit.

**S5. `MainRoot.body` is one expression that F08 and F10 both have to edit, and the routing text does not say where
a route that is not a push is resolved.** `LedgerAppKit/MainRoot.swift:18-25`; `docs/architecture.md:174-185`;
`implementation-notes.md:156`, `:1075-1078`.

- F08 wraps `AppTabs(…)` and its `#if DEBUG` sheet in a branch (re-indenting lines 19–24); F10 appends a modifier
  to the same chain. The seams table says "different lines of one small file"; they are the same lines, and the
  second lane to merge also has to decide whether the cover sits inside or outside F08's branch.
- Architecture §4 says the app resolves a route "into calls on the router", and the notes say to write
  `extension AppRouter { func handle(_:) }` and pass `router.handle`. `.startWorkout` and `.resumeWorkout` go to
  F10's presenter, which `MainRoot` owns and `AppRouter` cannot see. The first lane to need it will invent the
  shape.
- Fix: give `MainRoot` three members now: `body` (where F10 adds its modifier), a `@ViewBuilder` `content` (where
  F08 adds its branch), and `tabs` (`AppTabs` with the Debug sheet). In §4, name the resolver: for example "
  `MainRoot` builds each feature's `onRoute` from the router and the presenters it owns and hands it to `AppTabs`".
  Also say what a pushed screen of a feature is called (F12, F13 and F14 each need a second public entry point
  besides `<Feature>Root`).

**S6. `.tint(LedgerColor.accent)` on the `TabView`: the selected tab fails contrast in the light theme, and the
tint reaches everything inside the tabs.** `LedgerAppKit/AppTabs.swift:30`.

- Light screenshots: the selected icon and label render `#F7691F` on the selection capsule `#E9E8E2`, 2.44:1. The
  label is 10 pt text (AA asks 4.5:1; 3:1 for the icon). Dark is 6.9:1. `LedgerDesign` has `accentText` (`#B2390E`
  on paper) for exactly this case (`LedgerDesign/Tokens/LedgerColor.swift:44-46`), and contrast is a launch
  requirement (product decisions, Accessibility). Selection is also shown by the capsule, so it is not colour alone.
- `tint` is inherited: every system control a feature puts in a tab (a toggle, a default button, a text cursor, a
  progress view) is orange by default, against decision #17's "once per screen". Nothing says so.
- Criterion 5 says "the accent colour", so this is a call for Pete with the screenshots. I recommend
  `.tint(LedgerColor.accentText)` (same colour in dark), re-measured, and one sentence in architecture §4 on what
  tab content inherits (or a reset at each stack's root).

**S7. Standards §7 is not yet true of two modules, nothing forces a module with copy to have the two tests, and
five things are left for each lane to settle.** `docs/engineering-standards.md:169-238`.

- Not true today: `LedgerDesign` holds seven lookups outside a copy file with no catalog
  (`Components/SetRow.swift:146-154`, `WeekStrip.swift:108-114`), which architecture §11 still allows
  (`docs/architecture.md:433-437`); `LedgerWatchAppKit/TodayPlaceholder.swift:11` is `Text("Today")`. §7 reads as
  universal. Name both as not yet converted, with the slice that converts them.
- No registry: `PreviewScan.registeredModules` makes a module with a `#Preview` fail until it has `PreviewTests`.
  Copy has no equivalent, so a feature can ship a catalog, or bare literals, with no audit. Add the same check
  (modules with a catalog, or the M1 feature list, must be in a set the copy tests cover).
- Left open:
  1. "%lld of %lld sets" (F09 and F10 briefs; the DoD asks for plural rules for sets). A counted key takes one
     `%lld`. `%@ of %lld sets` compiles correctly (measured: `%2$#@value@`, "3 of 1 set"), and the audit accepts it,
     but §7 does not say so.
  2. Where the translator's comment goes. `AppCopy` puts it in the catalog; `LedgerDesign` and the test's demo put
     it in code (`comment:`). Xcode's sync writes the code's comment over the catalog's (measured).
  3. What `locale:` does. The notes say "the locale formats the number, the bundle picks the language"
     (`implementation-notes.md:752`). It also picks the plural form and the digits: `ru_RU` gives "21 set", `fr_FR`
     "0 set", `ar_EG` "٢١ sets" from the English catalog (measured). Production is safe (`Locale.current` carries
     the app's language); a test with another locale is not. Say it, and pin one case.
  4. Spoken text. §7 says "read"; VoiceOver labels, values and hints are copy too. The audit flags the literals,
     but the rule should say they are members of the copy file.
  5. Display names of Domain enums used by several features (goal, equipment, muscle): each module repeats the
     keys, or they live somewhere shared. §7 does not say.

### Nits

- N1. `AppTabs.swift:58`: `toolbar(_:for:)` is renamed `toolbarVisibility(_:for:)` since iOS 18 (soft-deprecated in
  the SDK).
- N2. `StringCatalog.swift:75-77`: "is not marked translated, so the build leaves it out" is false for
  `needs_review` (it is compiled; only a missing unit and `new` are dropped). Keep the rule, fix the sentence.
- N3. `StringCatalog.swift:134-138`: `specifiers(in:)` knows a fixed list; `%.1f`, `%s`, `%i` are invisible to the
  plural checks. Harmless while values are only `Int` and `String`.
- N4. `CopyAudit.swift:231-245`: a member whose parameter list holds parentheses or generics is not matched, so its
  lookups take the previous member's parameters. The cases I ran failed safe ("cannot read"); the shadowing case
  in S2 does not.
- N5. `CopyAudit.swift:111-113`: `*+Previews.swift` is skipped without checking it is `#if DEBUG`. A
  `Text("…")` in a preview is also extracted by the compiler, so Xcode's sync would add it to the catalog.
- N6. `CopyAudit.swift:27`: the enumerator has no error handler; an unreadable folder is skipped in silence, which
  for an audit is a pass. (`PreviewScan` has the same.)
- N7. `Routes.swift:33-36` and `AppRouterTests.swift:39-45`: `open` twice pushes the same screen twice, pinned as
  intended. Fine for a router; decide in S5 whether the store's "one pending route" is the only guard.
- N8. `AppCopy.swift:18-22`: `title(of: AppDestination)` has to stay exhaustive, so a destination whose feature has
  landed still needs a title. Pass the placeholder's title at its line in `AppTabs.screen(for:)` instead.
- N9. `PlaceholderScreen.swift:17-25` repeats `TodayPlaceholder`'s body; the tab identifiers are typed in
  `AppTabs`, the previews and (derived) the UI test. Goes away in S5; F15 owns identifiers.
- N10. `docs/architecture.md:460-461` (§12) still says each feature exposes a `Route`; §4 says onboarding has none.
- N11. `MainRoot.swift:10`: `@State private var router = AppRouter()` builds a router on every `init` and keeps
  the first. Cheap here; worth a word in the comment because F10's presenter will sit beside it.
- N12. `LedgerAppKitTests/Fixtures/Localizable.xcstrings` is the test target's default table, so any localizable
  literal a later test in this target compiles would be added to it by Xcode's sync, and
  `CatalogFixtureTests.swift:56` pins the key set. A table of its own (`Fixture.xcstrings`, `table: "Fixture"`)
  avoids that. §7's "keys in order" is code-unit order (what the tool writes); say so.

### Could not settle

- U1. `AppTabsTests.swift:42-58` reads the tree straight after a programmatic push, with no wait for the
  navigation transition. It passed in every run cited. If UIKit animates the push in a scene-less window, both
  screens could be in the tree for a moment. What would settle it: `-only-testing:LedgerAppKitTests/AppTabsTests
  -test-iterations 50` under the lock. I did not run it (the tester's files were in the build by then).
- U2. Whether the gate turns the `Text` `+` deprecation (S1) into an error for a package target.
  `Config/Base.xcconfig:11` sets warnings as errors for the project; I did not check that it reaches `LedgerKit`.
- U3. `PreviewRendering.swift:44-56`: an `NSHostingView` as a window's content view can resize the window to a
  fixed-size view's ideal size, which would make `bitmap.size == size` false for a view that did render (a false
  failure, not a hidden one). LedgerAppKit's four previews pass; I could not re-run LedgerDesign's twenty.

### The two rules as written

**Routing (architecture §4).** Consistent with the conventions (synchronous `onRoute`, one `AppDestination`, a
feature never presents another feature or sees the router) and true of the code: `AppTab`, `AppDestination`,
`AppRouter`, one registration per stack, `open(_:in:)`. What an F08 or F10 implementer can still get wrong: the
resolver's shape for a route that goes to a presenter (S5); the name of a feature's pushed screen (S5); that tab
content inherits the accent (S6); §12's "each feature exposes a Route" (N10). Not said, and fine for now: a pushed
screen pops itself with `dismiss`; hiding the tab bar on a pushed screen (the prototype hides it on the day editor)
is that screen's line in `AppTabs.screen(for:)`.

**Localization (standards §7).** Consistent with the conventions (copy files return `String`; `Text` only around a
live view; one counted value per key; fragments joined with " · "; no product name). True of `LedgerAppKit`. Not
true of `LedgerDesign` and `LedgerWatchAppKit` (S7). What a later implementer can still get wrong: `%` (B1); the
timer `Text` (S1); "X of Y sets" (S7.1); comments in two places (S7.2); `locale:` and plurals (S7.3); a bare
interpolated `Text` with no letters (S2); exempting a file to silence a false alarm (S3). Debug-only text is
covered by the exemption rule, with the caveat that a `LocalizedStringKey` literal in Debug code is still extracted
by the compiler (N5): Debug UI should take `String`s.

**An alternative the notes do not weigh.** The pinned toolchain generates typed symbols from a catalog's manual
entries, in packages too: both builds already write an (empty) `GeneratedStringSymbols_Localizable.swift` for
`LedgerAppKit`, and `xcstringstool generate-symbols` on a scratch catalog with `"extractionState" : "manual"` gave
`static var cantOpenYourDataRightNow` and `static func weekOf(_ arg1: Int, _ arg2: Int)` over `Bundle.module`.
That gives "every key the code uses exists, with the right argument types" from the compiler, which is the half of
the audit that B1, S2's shadowing and N4 are about. It does not give "no unused key" or "no literal elsewhere". I
did not build a target that uses the symbols. This is not a finding against the slice; it is worth ten minutes
before three lanes copy the hand-written form.

### The audit: what it misses, what it wrongly rejects

"Run" means the committed helper produced that result in the scratch harness.

**Passes, and should not**

| # | Source line (outside a copy file unless noted) | Result | Matters for |
|---|---|---|---|
| 1 | `Text("\(done)/\(total)")`, `Text("\(sets) × \(reps)")` | no findings (run) | F09 S4, F10: both are brief copy (S2) |
| 2 | `Text("#")`, `Text("—")`, `Text("1")` | no findings (run); by design, no letter | F10's column header and empty chip; low |
| 3 | `Text(goal.rawValue.capitalized)`, `Text(String(describing: route))`, `Text(error.localizedDescription)` | no findings (run); no literal | F08 (`TrainingGoal: String`); every store's failed state (standards §8) |
| 4 | any literal in an exempt file | no findings (run) | wherever a file is exempted (S3) |
| 5 | `Row(identifier: "Start workout")`, `Locale(identifier: "en_US")`, `dialogger.error("Can't save")`, `model.log.info("Start workout")` | no findings (run); the allowances are lexical | low |
| 6 | copy file: `let count = String(count)` then `"\(count) sets"` | keyed `%lld sets`; the compiler keys `%@ sets` (run) | low (S2) |
| 7 | copy file: plain key with `%` and a `%%` catalog | no findings (run) | F11 (B1) |
| 8 | copy file: `value.formatted()`, `goal.rawValue.capitalized` beside the lookups | no findings (run); "nothing but lookups" is checked for literals only | low |
| 9 | copy file: `Wrapper(comment: "Start workout")` | no findings (run); any `comment:` literal is skipped | low |
| 10 | a shipped view in `X+Previews.swift` | not read (run) | low (N5) |
| 11 | a module with copy and no audit test | nothing fails | `LedgerWatchAppKit`, `LedgerDesign` today (S7) |
| 12 | `let r = /"/; Text("Start workout")` | the rest of the line is read as one literal (run); documented | low |

**Rejected, and harmless**

| # | Source line | Result | Matters for |
|---|---|---|---|
| 1 | `Image(systemName: isDone ? "checkmark.circle.fill" : "circle")` | both names flagged (run) | F10–F14 views |
| 2 | `.accessibilityIdentifier(isLive ? "today.resume" : "today.start")`, `static let titleIdentifier = "today.title"`, a symbol name in a `switch` | flagged (run) | F09 S4, F15's central identifiers |
| 3 | `LedgerLogger(category: "today")`, `Logger(subsystem: "…", category: "…")` | flagged (run) | any file that makes a logger |
| 4 | `reportIssue("…")`, `assertionFailure("…")` | flagged (run) | stores |
| 5 | `logger.log.error("Today failed for \(workout?.name ?? "none")")` | "none" flagged (run) | stores |
| 6 | `URL(string: "https://…")`, `Image("plate-45", bundle: .module)`, `proxy.scrollTo("current")`, `.coordinateSpace(.named("scroll"))`, `@SceneStorage("selectedTab")`, `String(format: "%d:%02d", …)` | flagged (run) | F10 (scroll anchor), F14 (links) |
| 7 | `Text("Debug overlay")` inside `#if DEBUG` in a product file; `#Preview("Today")` outside a `+Previews` file | flagged (run) | any Debug affordance |
| 8 | copy file: `table: nil`, a `UInt` parameter, a `"""` key, a generic member | "cannot read" or "not written …" (run); the safe side | low |

Rows 1–5 each have a rewrite that passes (two `Image`s, the identifier at its call, the injected logger). The risk
is not the rewrite; it is the implementer exempting the view or store instead (S3).

The helper's own code: no force unwrap, `try?`, sleep or suppression; errors are thrown, not swallowed (N6 aside);
246, 170 and 255 lines; nothing compressed. Each catalog rule and each audit rule has a failing and a passing test
except those in B1 and S4.

### The catalog

- Format: matches what the tool writes (two-space indent, `"key" : value`, code-unit key order). `xcstringstool
  compile` on it gives the seven keys; the built app bundle holds the same seven
  (`Ledger.app/LedgerKit_LedgerAppKit.bundle/en.lproj/Localizable.strings`). The compiler's extraction
  (`AppCopy.stringsdata`) lists the same seven and nothing for any other file.
- The notes' two claims hold on Xcode 27.0: a key with no localization and a unit left `new` are not emitted.
  `needs_review` is emitted (N2).
- Plural layout: `variations.plural` with `one` and `other` compiles to a `.stringsdict` and resolves ("1 set",
  "21 sets"). Two `%lld` in a counted key makes the tool warn that it cannot infer the argument, which is the
  audit's rule. `%@` before the one `%lld` is inferred correctly.
- What opening the project in Xcode would do, emulated with `xcstringstool sync` and the build's `.stringsdata`:
  nothing today (byte-identical). When it does have something to write it rewrites the whole file without the
  final newline: a key added in code becomes an empty entry (which the audit then reports), a key removed from code
  gains `"extractionState" : "stale"`, and a `comment:` in code replaces the catalog's comment. The Xcode app itself
  was not opened.
- `defaultLocalization: "en"` and `resources: [.process("Resources")]` are right; the resource bundle's
  development region is `en`. No dependency edge changed.

### The seven points

1. Module boundaries: pass. No new edge; `LedgerAppKit` imports `LedgerDesign`, SwiftUI, Foundation, Observation;
   AppKit only in the test-only `LedgerSnapshotTesting`, on the Mac.
2. Concurrency: pass. `AppRouter` is `@MainActor @Observable`, owned in `@State`; `AppTab` and `AppDestination`
   are `nonisolated`, `Hashable`, `Sendable`; no task, clock or lock.
3. Error handling: pass for the product. The helper throws; N6.
4. Design fidelity: tokens only; order, labels, title position and the dark ground match. The system bar draws
   filled symbols and full-strength unselected items where the prototype has 1.5 pt strokes at 34–38 %; accepted by
   architecture §11. S6 on the light tint.
5. Accessibility: the tree is as pinned (title a heading; four tab buttons by title, one selected). System bar for
   hit targets and large text. S6 for contrast.
6. Test quality: behaviour, no sleeps, names per §6, no async suite (so no `.timeLimit` needed). Gaps: B1's missing
   case, S4, U1. The suites carry no layer tag, as none in this target does.
7. Brief compliance: each of the six criteria has a test, a UI test or a screenshot. `Tabs` and `DebugMenu` are
   nightly, run by hand for this slice; "a tab keeps its stack" is proven on the router and the hosted shell, not
   by taps (open question 9, accepted).

Also checked: nothing from S2–S6; `project.pbxproj`, `package-graph.expected.txt`, test plans and lint config
untouched; no new suppression; the two files outside the list (`PreviewRendering.swift`, `TodayPlaceholder.swift`)
have recorded reasons; the two decision-#29 strings are byte-for-byte `main`'s (the product name in the second is
with the product owner and is not a finding here).

`/code-review`'s ten: the `%` key (B1), member parameters (N4), specifiers (N3), previews (N5), duplicate push
(N7), placeholder duplication (N9) and the Mac window's size (U3) are above. Not taken: the product name (not
changed by the slice); "the router is lost if the state leaves ready" (`DatabaseLaunch` never leaves `.ready`; the
throwaway instance is N11); "helper tests belong in their own target" (`Package.swift:40-41` puts helper suites in
the targets that use them).

### The 15 decisions

1. One line of `TodayPlaceholder` changed: agree. Criterion 4 needs it; the two references are untouched.
2. The Mac host draws previews in a window: agree. Recorded; the iOS and watchOS paths are unchanged, so no
   snapshot or gate assertion moved; it checks "lays out without trapping", as the old path did. U3.
3. `AppDestination` starts with `.settings` only: agree.
4. The shell's types are internal: agree.
5. Every key spells out its English text, `translated`: agree; verified with the tool.
6. The check reads sources, not a key list: agree with the aim. Reading text is where B1 and S2 come from; the
   compiler's `.stringsdata` is the missing second opinion.
7. `Bundle.module` in a test target with resources is the test target's: agree; the build generates an accessor
   for `LedgerAppKitTests`.
8. Tab roots hide the navigation bar: agree. N1.
9. SF Symbols at `systemImage:`: agree (Pete's decision 4).
10. Four `Tab`s written out: agree. Note the audit also forces it (a symbol name in a `switch` is a finding).
11. No pixel reference of the shell: agree. It leaves the accent to screenshots; S6 is what they show.
12. `MainRoot` keeps the composition: fine.
13. No tab restoration: agree.
14. Three helper files: agree. `TestCatalog` lives in `LedgerAppKitTests`, so other modules' tests cannot use it.
15. Size: 153 product lines; nothing compressed.

Open questions: 2 (LedgerDesign's words) is S7; 5 and 6 (the last byte, Xcode) are answered under "The catalog";
10 (a `Text` member) needs a ruling now (S1); the rest stand as written.

### What I did not check

- Nothing on a simulator: the gate, `AppTabsTests`, the UI tests and `DebugMenu` are the implementer's and the
  orchestrator's runs. No repeat run for flakiness (U1).
- The Xcode app was not opened; the sync was emulated with the command-line tool.
- Host `PreviewTests` for `LedgerDesign` and `LedgerWatchAppKit` through the new Mac path: the tester's in-progress
  files broke the host build before I ran them.
- The tester's files and `test-findings.md` were not read.
- The F08 and F10 notes' copies of the conventions (other worktrees); watchOS catalogs; the generated-symbols
  alternative end to end; `accentText` as the tint (it needs a new screenshot).

## Slice S1 — re-review of fix round 1 (G3 reviewer, 2026-10-05)

Reviewed: `git diff f45f5e9..6555960`, against my findings above and the three sets of rulings in the notes. A
scoped re-review, except for `scripts/check-string-catalogs.sh`, its suite and its wiring, which I read in full
as new infrastructure.

**Verdict: approve. 0 Blocking, 3 Should fix, 8 Nits.** B1 is closed at the root, and every Should-fix item of
the first review is closed or ruled. The three new Should-fix items can ride with the touch-up already ruled.

### A correction to my first review

S6 said the light theme's selected tab measured 2.44:1 and the dark 6.9:1. Both were mis-measured: my tool
converted the screenshots' colours where it should have read them as they are (the files are tagged sRGB, and read
that way their ground is the token exactly, `#EFEDE6` and `#0B0B0D`). Read from the files' own bytes the first
round's figures were **2.70:1** (`#F25219` on `#E4E2DB`) and 6.37:1. The finding stood either way (2.70 is under
both 4.5 and 3), but `tasks/features/F09-today.md:119` now quotes 2.44; it should say 2.70 (R3).

### What I ran

- `bash scripts/tests/adversarial/string-catalogs.adv.sh`: 71 passed, 0 failed, 7 s.
- `scripts/check-string-catalogs.sh` on this tree's build, from the root and from another directory: 1 catalog,
  7 keys, exit 0, tree untouched. `shellcheck` on the script and the suite: clean.
- The script on two scratch repositories whose `.stringsdata` the real compiler wrote: a path with a space, a
  source in a sub-folder with `+` in its name, a comment only the catalog gives, a used key marked stale, a
  source edited after the build, catalogs in other places, and R1's case.
- A scratch package built twice with `COMPILATION_CACHE_ENABLE_CACHING=YES`, the whole `Build` folder deleted in
  between and only the cache kept (what the runner has): 5 cache hits, 0 misses, every `.stringsdata` written again.
- Host, on the clean tree at `6555960`: `swift test … --filter LedgerAppKitTests`, 179 tests in 29 suites passed.
- The six rewritten helper files, copied into a scratch package, against about 75 source lines.
- The four re-shot screenshots and the first round's, read from their bytes.

### Status of the first review's items

| Item | Status |
|---|---|
| B1 `%` in a plain key | **Closed.** The audit derives no key; the gate holds the catalog to the compiler's keys (SC03–SC06, run). §7 states the rule; the notes' sentence is corrected (`implementation-notes.md:1093-1095`). |
| S1 the timer `Text` | **Closed.** Two lookup forms in §7 and in `copyFileProblems`; `Text("\(word) · \(timer)")` in a copy file is now a finding (run). `Text + Text` is ruled for the next touch-up. |
| S2 misses; the compiler's keys | **Closed**, with one edge left (R1). `Text("\(done)/\(total)")` is a finding; a key with a value needs `locale:`; the shadowing case cannot arise. |
| S3 exemptions | **Closed.** Per literal, stale entries are findings, Debug-only files are verified. As §7 asks of the reviewer, I confirm `LedgerAppKit`'s: `"-LEDGER_UITEST"` and the temporary database path in `AppComposition.swift`, and `AppComposition+Diagnostics.swift` as Debug-only. |
| S4 the bundle check can fail | **Closed** (`ModuleCopyTests.swift:116-122`). |
| S5 `MainRoot`; the resolver | **Closed.** Three members; §4 names `MainRoot` as the resolver and the `…Root` naming. The notes' hand-off text was not updated (R3). |
| S6 tint | **Closed.** `accentText`, reset on each stack, said in §4. The notes' table is right: 5.25:1 light (`#A73107` on `#E4E2DB`), 6.37:1 dark, by my corrected reading too. The reset is tested on the modifier, not on `AppTabs` (ruled). |
| S7 §7 | **Closed for iOS modules.** True of `LedgerAppKit`; the two unconverted modules are named and held in a table that only shrinks; points 1–4 are settled and 5 is left open on purpose, with who decides. The watch half is R2. |
| N1, N2, N8, N10, N11 | Closed. |
| N3 specifiers | Ruled for the next touch-up. |
| N4 member parameters | Gone with the derivation. |
| N5 previews | Closed in the audit (`#if DEBUG` is verified). The gate reads a preview's keys; see R1 for what it then accepts. |
| N6 unreadable folder | Closed in the audit. `PreviewScan` is as it was (not this slice's). |
| N7 a route pushed twice | Open by ruling (S5). |
| N9 the placeholder's twin | Open until S5 deletes it. |
| N12 key order; the fixture's table | Order stated (UTF-8 bytes, which I had called code-unit order). The fixture's own table is ruled for the next touch-up. |
| U1 | Closed: fifty iterations, the implementer's run. |
| U2 | Answered: a deprecation in a package target is a warning, not an error; a queued chore. |
| U3 | Closed: 26 previews on the host (implementer); I re-ran LedgerAppKit's four. |

### The gate step

`scripts/check-string-catalogs.sh` (190 lines), `string-catalogs.adv.sh` (71 cases), `check.sh:200-204`.

- **Correctness.** Keys are compared as bytes by `jq`, both ways, with the file and line of each lookup; then the
  tool's own `sync` on a temporary copy, forced to write by adding and dropping one key, and a diff. Verified by
  the suite and by my runs. A used key that the catalog marks stale fails with the diff (run).
- **It cannot pass on nothing.** No catalog: exit 1 (SC26). No `.stringsdata` for the module: exit 1 (SC17, SC18).
  A source without one: exit 1, naming the file (SC20). A catalog that is not JSON, or `jq` or the tool failing:
  exit 1. `check_catalog` runs with `errexit` off (it is called before `||`); I traced each unchecked command and
  each fails closed.
- **Stale output.** A deleted or renamed source's file is ignored (SC19). A source edited since the build is not
  noticed (n1); inside `check.sh` the build has just run, so it cannot happen there.
- **Modes.** After the iOS build in the full gate, `--skip-lint`, `--ios-only`, `--ios-only --skip-static` and
  `--record-snapshots`; not in `--lint-only`, `--static-only`, `--fast` (W70–W75). `test_platform` is a plain
  statement, so a failure stops the gate.
- **The runner with a restored cache.** The `.stringsdata` files being absent there is unlikely: a cache hit
  replays every output of the compile, this one included (the implementer's measurement on the real module, and
  mine on a scratch package with the whole build folder gone). If they were absent, the step exits 1 with "has
  nothing to be compared with" or names the files: red on every PR, never a pass. The message would then send the
  author to rebuild, which would not help; it could name the cache.
- **Shell.** Bash 3.2 safe (no empty-array expansion under `set -u`), every path quoted (a root with a space
  passes), `/bin/bash` forced in the suite, nothing written outside `mktemp` (SC21–SC23, and `git status` after
  my runs).
- **The suite.** Real compiler, real tool, no timing, no network, in the house style. It also pins how the
  compiler keys a lookup. It has no case for a path with a space or a source in a sub-folder; both pass by hand.

### The rewritten audit

Sound on what I threw at it: multi-line and raw literals, nested interpolations with parentheses, escapes, block
comments holding quotes and parentheses, wrapped lookups. No force unwrap, no `try?`, files 106 to 210 lines,
unreadable folders throw. The argument model fixes the false alarms that pushed towards exempting files (a symbol
or an identifier chosen by a ternary, a log line with a default, a logger's category: all pass now, run). The
listed limits are the real ones, with one missing (n3). The one that matters for F08–F14 is "a text made from a
name" (`Text(goal.rawValue.capitalized)`), which only review finds.

### `ModuleCopyTests`

- A new module is audited by default; a renamed one or a typo in a table fails `everyModule_isAuditedOrNamed`. A
  catalog in the wrong place, or one that does not read, makes the module's copy file a finding.
- The reasons hold: in this build the eight "no copy by design" modules have no extracted key at all;
  `LedgerDesign` has 14, in six files (`SetRow`, `WeekStrip`, `HairlineList`, `SheetChrome`, `DebugMenu`,
  `DiagnosticsPage`), which is the size of its conversion.
- The bundle check asks the module's own bundle, found inside the test bundle, which embeds the bundles of
  `LedgerAppKit`'s dependencies: every iOS feature, and no watch module (R2).

### Should fix

**R1. A lookup outside the copy file passes every check once its key is in the catalog, and the step's message
tells the author to add it.** `scripts/check-string-catalogs.sh:77-85`, `:137-145`.

- Run, on a scratch module: `Text("Sample row")` in a `+Previews.swift` inside `#if DEBUG`, and
  `Button("\(done)/\(total)") {}` in a view, with `Sample row` and `%lld/%lld` added to the catalog. The step
  exits 0, the audit has no findings (it does not read the preview, and the button's literal has no letter), and
  the bundle would resolve both.
- Why it matters: §7 says every lookup is in the copy file. The button's lookup goes to the main bundle, so its
  catalog entry is dead; the preview's key ships in the catalog. `LedgerDesign`'s conversion meets this at once
  (its Debug gallery samples and Debug menu account for seven of the 14 keys: bare `Text("…")` and
  `.navigationTitle("…")` in Debug-only code), and the message's first sentence is "Give the catalog a key for
  each lookup it lacks".
- Fix: the script already knows each lookup's file. Make a lookup whose file is not `<Name>Copy.swift` or
  `<Name>Copy+<Area>.swift` a failure of its own ("looked up in DemoView.swift:4, which is not a copy file: hand
  the view a `String`; in Debug code use `Text(verbatim:)`"), with two cases in the suite. That also closes the
  audit's first limit for every module with a catalog.

**R2. A watch module cannot pass checks 1 and 3, and §7 promises it only needs a catalog and a copy file.**
`scripts/check-string-catalogs.sh:46`, `:113-122`; `LedgerAppKitTests/ModuleCopyTests.swift:103-109`;
`docs/engineering-standards.md:173-175`, `:309-312`, `:349-351`.

- The iOS build compiles neither `LedgerWatchAppKit` nor `WatchFeatureWorkout` (their folders exist only under
  `Debug-watchsimulator`), so a catalog in either fails check 1 with "has nothing to be compared with … iOS has
  not been built" (SC18 pins it). `LedgerAppKitTests` does not embed their bundles, so check 3's `#require` fails.
  PR CI builds no watch target at all.
- Why it matters: the ruled chore converts `LedgerWatchAppKit` next. §7's sentence on reach describes a milder
  failure (a key seen as unused) than the one the chore will meet.
- Fix: decide the scope now and write it in §7 and in the table's reason. Either the chore converts `LedgerDesign`
  only and `LedgerWatchAppKit` waits for F18, or the step first learns to read the watch build (the full gate
  only) and a watch test target runs check 3. Either way, make the step's message name the case.

**R3. The hand-off text for F08 and F10 is stale, and the brief quotes my wrong figure.**
`implementation-notes.md:1068-1080`; `tasks/features/F09-today.md:119`.

- "Inputs for F08's and F10's slices" still tells F08 to branch around `AppTabs(…)` in `body`, F10 to add its
  modifier after the Debug sheet, both to write `extension AppRouter { func handle(_:) }` and pass
  `router.handle`, and a new destination to add its title to `AppCopy.title(of:)`. The round replaced all four
  (`MainRoot`'s `content` and `body`, §4's resolver, one `…Title` member per placeholder). The note at `:1082`
  covers only the catalog half.
- Fix: rewrite those four bullets, or replace them with a pointer to architecture §4 and `MainRoot.swift`. Change
  2.44:1 to 2.70:1 in the brief.

### Nits

- n1. `check-string-catalogs.sh:103-111`: a source edited after the build is compared by its old `.stringsdata`
  (run: the step passed on a key the code no longer has). Only outside the gate. Fail when a source is newer than
  its `.stringsdata`.
- n2. `docs/engineering-standards.md:198-199`: "a translator's comment is written in code". A comment only the
  catalog gives passes the step (run; SC15 uses one). Say it is accepted, or fail it.
- n3. `SwiftLexer.swift:159-170`: parentheses that do not balance in the text leave later literals inside that
  argument. Run: `foo(identifier:` in both branches of an `#if`, closed after `#endif`, and
  `let r = /\(identifier: /`, each hide a later `let s = "Start workout"`. Add the case to "Known limits", beside
  the regex line.
- n4. `check-string-catalogs.sh:175`: a catalog anywhere else (`Sources/X/Localizable.xcstrings`,
  `Resources/Other.xcstrings`) is not seen (run). Harmless today; fail on any other `*.xcstrings` under
  `LedgerKit/Sources`.
- n5. `CopyAuditRules.swift:154-165`: form 2 passes with another value in it
  (`Text("Set \(n) · \(timerInterval: …)", bundle: .module)`), which can take no `locale:`; and `locale: .current`
  satisfies form 1. Say in §7 that form 2 carries the timer and no other value.
- n6. `ModuleCopyTests.swift:37-44` is one more file every lane edits (an exemption); add it to convention 4's
  list. "Localization, for a feature author" (`implementation-notes.md:1258-1267`) should give the two commands:
  `swift test --package-path LedgerKit --only-use-versions-from-resolved-file --filter ModuleCopyTests` for
  checks 2 and 3, and the gate for check 1.
- n7. When the ruled specifier rule lands, the step's hint (`check-string-catalogs.sh:142-143`) and
  `docs/testing-strategy.md:457-458` still offer `%lf` for a `Double`.
- n8. `implementation-notes.md:907-908`, `:1016-1017`: the first round's "Criteria → tests" rows 4 and 5 and "How
  to verify by hand" name tests that no longer exist (`copy_followsTheStandard`). Mark them superseded.

### What a feature author could still get wrong

- Adding a key because the gate asks for it, when the lookup should not exist (R1).
- Giving a watch module a catalog (R2).
- A text made from a name: `Text(goal.rawValue.capitalized)` for F08's `TrainingGoal`. Each case needs its own
  lookup; nothing mechanical says so.
- Until the ruled touch-up: joining `Text + Text` in a copy file, and an optional or a `Double` in a key.
- Running only their own module's tests: the audit lives in `LedgerAppKitTests`, and check 1 only in the gate.
- Expecting the accent inside a tab: a system control there is the system's blue until the screen tints it; the
  cover and onboarding sit outside the tabs and get neither.

### What I did not check

- Nothing on a simulator: the gate on `6555960`, `AppTabsTests`' fifty iterations and the UI tests are the
  implementer's and the orchestrator's runs.
- GitHub's runner itself; the cache behaviour is measured on this Mac only.
- `--record-snapshots` for real; the Xcode app; host previews of `LedgerDesign` and `LedgerWatchAppKit`.
- The tester's files, including the implementer's edits to them (`TabsAdversarial.swift` and the adversarial
  suites), and the close-out in progress.

## Slice S2 — review (G3 reviewer, 2026-10-05)

Reviewed: `git diff 985a8fb..a016f8b` on `feat/F09-s2-domain` (54 product lines, 908 test lines, one line of
`docs/architecture.md`, the notes), against the brief's "Plan amendments — slice S2" (five criteria), standards,
architecture §5, ADR-007, decisions #15, #18 and #26, and the notes' S2 sections.

**Verdict: approved. 0 Blocking, 0 Should fix, 6 Nits.**

The three additions do what the five criteria say, and I could not make any of them give a wrong answer or trap.
The Nits are two doc or naming points, one line of test, one small refactor and one sentence of the notes that
would mislead S3. None needs to hold the PR.

### What I ran

- `/code-review` at effort `high` on the range (forked skill; 7 findings, triaged below). It built and ran nothing.
- A standalone copy of `percentChange`'s arithmetic and of `Decimal.roundedToInt()` against exact `Int128`
  arithmetic: 252,000 cases placed on an exact tie and one unit either side of it, with mantissas of 6 to 24
  digits, plain, times the pound factor and times 10⁻⁷. No mismatch. The same probe ran every `nil` and clamp path.
- The 56 `LedgerDomain` sources as committed (no tracked file was modified), compiled with `swiftc` in Swift 6
  mode beside a search of my own that walks civil days and asks `scheduledDay(on:in:)` and `weekIndex(for:)`:
  36,000 moments at any second of the day, 13 zones, a random week start, blocks of 2 to 9 weeks, a third of
  them with weeks shuffled or an index moved to between −2 and count + 2. No mismatch.
- Timing in that harness, optimised: a block that trains only on its last day answers in 0.14 ms at 1,000 weeks,
  1.3 ms at 10,000 and 17 ms at 100,000; when the answer is tomorrow, 0.04, 0.4 and 3.8 ms.

Scratch folder: `/private/tmp/claude-501/-Users-peterarevalo-Dev-workout-app/1007ba2a-4cb4-4801-a9fe-bc3f1e348a39/scratchpad/f09s2-g3`
(`pc.swift` the percent probe, `brute/` the search).

### Blocking

None.

### Should fix

None.

### Nits

- n1. `LedgerDomain/Units/Volume.swift:40-51`: for a negative `previous` the sign follows the formula, so a rise
  from −100 to 100 is −200 (run; pinned by `percentChange_negativePrevious_followsTheFormula`). The comment gives
  the formula and not this consequence, and neither `Volume` nor `Weight` refuses a negative value, so "no volume
  is negative" is a habit of the callers and not a property of the type. Fix: one sentence in the comment ("for a
  negative `previous` the sign is the formula's, not the direction of the change"). Dividing by the magnitude
  instead would be a change to the brief's formula, which is the orchestrator's to make.
- n2. `LedgerDomain/Units/Volume.swift:37`: `thousands(in:)` is made by cutting the last character off
  `compact(in:)`. It is right today and three tests hold the two together, but it formats, appends "k" and strips
  it again, and it depends on the suffix being one character. Fix: a private `compactDigits(in:)` that returns
  the `NumberText.fixed` string, with `compact` returning it plus "k". That changes `compact`'s body and not its
  declaration or its output, which the existing tests pin; the notes' reading of "no existing declaration
  changes" (decision 4) is stricter than the criterion.
- n3. `LedgerDomainTests/Rules/WeekCalendarTests+NextScheduledDay.swift:60`: the length of the fixture's day is
  checked with `#expect`, so after a change of zone rules the test goes on and can also report a wrong session
  (Santiago 04-04 at 24 h 10 min would). The notes' decision 11 says it fails "with that message and not with a
  wrong session". Fix: `try #require(end.timeIntervalSince(start) == Double(row.hours) * 3600, …)`.
- n4. `LedgerDomainTests/Rules/NextScheduledDayPropertyTests.swift:8`: the suite is named for a function, where
  testing-strategy §6 names suites for the source type and `VolumePropertyTests` in the same slice does. Fix:
  `WeekCalendarPropertyTests` (25 characters, inside the lint's limit; the name is free).
- n5. `LedgerDomain/Model/Loadable.swift:4`: the parameter is `T`, as §5 writes it; every other generic in
  `Sources` has a word, and the brief's criterion 4 writes `Value`. I agree with the implementer's open question
  1: rename it and change §5's sketch in one small change before S5, F08 or F10 write an extension with a `where`
  clause. Nothing a caller writes today changes.
- n6. `tasks/features/F09-today/implementation-notes.md:1901-1902` ("Inputs for S3"): "`nil` means … the rest
  card says the last-week sentence". `nil` means no session is left in the block, which is also true in week 3 of
  8 when the later weeks are empty; "This is the last week of the block" would then be false. Fix the sentence:
  S3 says the last-week sentence only when `weekIndex(for: now) == weeks.count - 1`, and decides what an earlier
  week with nothing left says (the brief has no copy for it).

### The points the task named

- **`nextScheduledDay`.** The moment becomes a day number once, in the calendar's zone; everything after is
  integer days, so there is no second arithmetic to go wrong. The range `max(today + 1, blockStart) ..< blockEnd`
  cannot invert: the guard gives `today + 1 <= blockEnd`, and `blockStart <= blockEnd` because a count is not
  negative. It runs at most `7 × weeks.count` steps and stops at the first scheduled day past 9999-12-31, so it
  ends for every program. It agrees with `scheduledDay(on:in:)` on every day of the block (my search, above),
  including first-wins for a repeated index. Outside the block it follows `isBlockComplete` and not
  `scheduledDay(on:in:)`: a week whose index is negative or not below `weeks.count` is never read (notes,
  decision 6; no validated program has one). Before the block it gives the first session; on or after the last
  day, `nil`. The table of all weeks is built on every call; at eight weeks that is microseconds and at 100,000
  it is 4 ms, so I would not change it.
- **`ScheduledDay` for S3.** `date` and the computed `weekday` give "Friday"; `dayTemplateID` finds the tag in
  `program.days`; `weekIndex` against `weekIndex(for: now)` separates "Next up is Friday" from "next Monday" and
  gives "Next: week %lld". Rule 46's "current week" is the program week, which is what `weekIndex` is. Enough,
  with n6's caution.
- **`percentChange`.** Exact: the subtraction and the multiplication by 100 are exact, a tie is a terminating
  decimal, and the one division put every case on the right side of its tie with operands of 6 to more than 24
  digits (run). One rounding, `.plain`, which is half away from zero for negatives too (−0.5 gives −1, −0.4
  gives 0, −2.5 gives −3; run). Paths: zero `previous` gives `nil`; NaN in either volume gives `nil`; arithmetic
  past `Decimal`'s range gives `nil`; beyond `Int` it clamps. Each is in the comment. The `nil` range starts
  lower than the comment's "about 10¹⁶⁵" reads: Foundation overflows on the exponent (past 127) whatever room
  the mantissa has, so 1 against 10⁻¹²⁷ is `nil` (10¹²⁹ in truth), and the greatest `Decimal` is `Int.max`
  against 100 and `nil` against 1 (run). No lifter reaches either, so I rank nothing here. Nothing traps:
  `Decimal` arithmetic returns NaN, and `Decimal(Int.min)` and `Decimal(Int.max)` go back to those `Int`s (run).
- **`thousands(in:)`.** One source of truth by construction, kilograms included. Zero is tested on `gramReps`,
  so only the zero volume reads "0", as criterion 3 says word for word; a small negative volume reads "0.0"
  without a sign.
- **`Loadable`.** §5's four cases, `failed(any Error)` being `failed(Error)`. `Sendable` when `T` is, which
  compiles because `Error` is `Sendable`. Nothing surplus (no `Equatable`, no accessor, no `map`). Nothing
  missing for S5: a store holds `Loadable<TodayModel>`, a view switches over it, a test matches with `if case`.
  It has no `Equatable` (an `any Error` has none), so a view cannot hand it to `onChange(of:)` or
  `animation(_:value:)`; S5, F08 and F10 should know that before they reach for either.

### `/code-review`'s seven findings

| Finding | Result |
|---|---|
| Negative baseline gives the wrong sign | n1 |
| "0" and "0.0" for volumes that both round to zero | Criterion 3 as written; the implementer's open question 3. Not a defect of the slice. See "The deviations" |
| `thousands` by string surgery | n2 |
| A table of every week on each call | Measured; no action |
| The midnight table depends on the zone database | The dependence is F02's too and each row checks its day's length; the `#expect` is n3 |
| `ScheduledDay` beside `scheduledDay(on:in:)`, which returns a bare ID | The criterion names the type, and S2 may not change the older function. No action |
| `Volume.thousands` beside `NumberText.thousands` | The criterion's name; `NumberText` is internal. No action |

### The seven points

1. **Module boundaries**: pass. 54 of the module's 56 files import Foundation and two import nothing
   (`Loadable.swift` is one). No `Package.swift` change.
2. **Concurrency**: pass. `ScheduledDay` is `Hashable, Sendable`; `Loadable` is conditionally `Sendable`; the
   moment is a parameter, and nothing reads a clock, a UUID or `Calendar.current`.
3. **Error handling**: pass. Nothing throws and nothing is swallowed; every `nil` and the clamp are documented.
   `Loadable`'s comment says a raw error is never shown (§8).
4. **Design fidelity**: not applicable (no UI). "24.2" and "0" fit the brief's "%@k" and criterion 8's "0k".
5. **Accessibility**: not applicable.
6. **Test quality**: pass, with n3 and n4. The references are independent of the new code (a day-by-day search
   through `scheduledDay(on:in:)` with Foundation's calendar; `Int64` arithmetic for the percent); expected days
   are read off the calendar; seeds come from `PropertySeed.all`; the two calendar tables are `Sendable` structs
   with a `description` (the tie table is tuples of text); names follow §6; no sleep, no `withKnownIssue`,
   nothing disabled.
7. **Brief compliance**: pass. Each of the five criteria has tests, the three dated examples and the three
   percent examples among them. Sources are additions only (99 lines added, none removed); `VolumeTests.swift` is
   149 lines appended after the suite's closing brace and no line removed; the architecture line names the
   function and its type; nothing of S3 is in the range; no lint suppression, `try!`, `as!` or `@unchecked`.

### The deviations

- **`percentChange` is `nil` when the result is not a number, and clamps beyond `Int`**: right. `Decimal` has no
  honest integer for NaN, a sign chosen for an overflow can be wrong (the greatest `Decimal` after its own
  negative is −200 in truth), and `nil` already means "hide the delta". Keep it.
- **`Loadable<T>`, unconstrained**: right against §5. A constraint would stop a store holding a model that is not
  `Sendable` and buys nothing the conditional conformance does not give. The name is n5.
- **`ScheduledDay.weekday` computed**: right. A stored weekday could disagree with the date.
- **`thousands` cut from `compact`; only exact zero reads "0"**: the zero rule is the criterion's. The
  consequence is the implementer's open question 3: a week whose only set is under 50 units reads "0.0k". Look at
  it in S4's screenshots and put it to Pete if it reads badly; the other rule is one condition. The cut is n2.
- **The seeded suite's name**: the reason given (41 characters) is true of the name tried; a shorter one that
  follows §6 exists (n4).

### What I did not check

- The slice's own tests. I ran none of them, on the host or on a simulator: the tester's untracked files were in
  the tree, and the gate on `a016f8b` is the orchestrator's. The pass counts, the coverage figures and the
  twenty mutants are the implementer's.
- A device, and a watch whose `Int` is 32 bits.
- GitHub's runner and its zone database (the three 25-hour rows are new).
- The tester's files.

## Slice S3 — review (G3 reviewer, 2026-10-05)

Reviewed: `git diff 4abfb8f..906d5a8` on `feat/F09-s3-presentation` (815 product lines in eleven files of
`FeatureToday`, a 49-key catalog, 2,162 lines of tests, six lines of `Package.swift`, one of
`coverage-thresholds.json`, the notes), against the brief's "Plan amendments — slice S3" (twelve criteria), the
body's criteria 1 and 3–11 and its "Copy (exact)", standards §5 and §7, architecture §4, §11 and §12, the product
spec's Today sections and rules 34–35, 42–43, 45–46, decisions #14, #15, #17, #18, #25, #26 and Naming, and the
notes' S3 sections. Paths that start with `Today` are under `LedgerKit/Sources/FeatureToday/`; test paths are
under `LedgerKit/Tests/FeatureTodayTests/`.

**Verdict: approved. 0 Blocking, 4 Should fix, 7 Nits.**

The function does what the twelve criteria say. I found no input a shipped flow can produce for which the card,
the strip, the tiles or the list is wrong, and no arithmetic in seconds, no `Double` and no ambient clock,
calendar, locale or zone. The four Should-fix items are one spoken line assembled outside the copy file, a
source test that will not see the spellings S4 and S5 are most likely to write, one combination of the decision
table with no worked example, and two rest-day sentences that are false for inputs the specification names and
no shipped flow can reach yet. None needs to hold the PR; R2 and R3 are cheap enough to do before S4 starts.

### What I ran

- `/code-review` at effort `high` on the range (forked skill; 10 findings, triaged below). It built nothing.
- The committed catalog (`git show 906d5a8:…/Localizable.xcstrings`) decoded and compared by script with the
  quoted texts of the brief's copy paragraph (`F09-today.md:48`): source language, state, plural forms, comments,
  the keys' order by UTF-8 bytes, and the three non-ASCII characters (U+00D7, U+00B7, U+2212).
- A three-test scratch package to see what Swift Testing in this toolchain (Swift 6.4) writes for a failed
  expectation: for `#expect(make(input).kind == "x")` only the two sides; for `#expect(input.items.isEmpty)`
  and the like, the receiver in full (2,000 strings were printed).
- No test of the slice, on the host or on a simulator (see "What I did not check").

Scratch folder: `/private/tmp/claude-501/-Users-peterarevalo-Dev-workout-app/1007ba2a-4cb4-4801-a9fe-bc3f1e348a39/scratchpad/f09s3-g3`
(`catalog.json`, `capture/`).

### Blocking

None.

### Should fix

- **R1. The volume tile's spoken text is put together in the presentation, with a literal of its own.**
  `TodayPresentation+Stats.swift:43-49`: `[TodayCopy.moved(…), delta]` joined with `", "` gives "24,180 lb moved,
  +8%". Standards §7: spoken text is copy, a lookup in the copy file like any other line, and a presentation
  builder holds no user-facing literal. `" · "` is the join the convention names; `", "` is not, and the audit
  cannot see a literal without a letter (its first known limit, left to review). It matters twice: a translator
  cannot move or qualify the change, and the line as heard says neither "this week" nor what the change is
  against (the sessions tile says "this week"; this one does not). Criteria 8 and 10. Fix, either: (a) a member
  per unit in `TodayCopy` for the tile's spoken line with a change (`%@ lb moved, %@`, `%@ kg moved, %@`, or the
  sentence Pete prefers, such as "24,180 lb moved this week, up 8% on last week", which needs a key per
  direction), the line without a change staying `%@ lb moved`; or (b) the orchestrator adds ", " to §7 as the
  join of spoken fragments and it becomes a named constant beside `separator`. (a) is two to six keys and no
  change to the `stats_*` tests if the English stays.
- **R2. The source test will not see the ambient reads S4 and S5 are most likely to write.**
  `FeatureTodaySourceTests.swift:10-15`: the seventeen spellings do not include `.dateTime` (a `Date.FormatStyle`
  with the device's locale, calendar and zone, the usual way to format a date in a view), `Calendar(identifier:`
  (a new calendar takes the device's zone), a bare `.formatted()`, `Date.init()`, or the formatter classes
  (`DateFormatter(`, `NumberFormatter(`, `DateComponentsFormatter(`). And `SwiftSource.lines(ofCode:)` does not
  search the code inside a string interpolation (`LedgerTestSupport/Localization/SwiftSource.swift:104-105`),
  which is where a copy member would format a date. None of these is in the module today (searched), so the
  slice is clean; the test is criterion 11's proof for the 800 lines the next two slices add. Fix: add the
  spellings; add one interpolated case to `check_findsASpellingInCodeOnly` and either search the literals' parts
  or say in the suite's comment that interpolations are not read. `presentation_neverNamesDouble` (`:36`) has the
  same kind of gap (`.doubleValue`, a float literal typed as `Decimal`); one more spelling covers the first.
- **R3. No worked example of "today's session is logged and another workout is live".**
  `TodayPresentation+Card.swift:13-15` puts the live workout before `:22` (Logged); the `live_*` tests never have
  a finished workout of today's session in the input, and `live_finishes_flipsToLoggedInOneUpdate`
  (`TodayPresentationTests+Live.swift:177-203`) is the other direction. The seeded reference
  (`TodayPresentationPropertyTests.swift:136-139`) has the rule, but the combination needs a live session, a
  session day and one of up to eight workouts with today's source started today: by my estimate about one case
  in the PR lane's 800 inputs, which I did not confirm. It is one of the two rows a product decision can swap.
  Fix: `live_afterTodaysSessionIsLogged_takesOverTheCard`: week workouts = Lower A finished today, session = a
  live Lower B; expect Resume, the title "Lower A", today's mark done and "1" session. About fifteen lines.
- **R4. Two rest-day sentences are false for inputs the specification names.** `TodayPresentation+Card.swift:206`
  and `:221-231`.
  (a) Before the block the card's week is clamped to 0, so the body says "in week 1" and "Next up is {weekday}"
  however far the start is: three weeks before, "Nothing scheduled for Tuesday in week 1. Next up is Monday."
  (pinned at `TodayPresentationTests+RestDay.swift:91`), and on a Monday a week or more before a block whose
  first session is a Monday, "Nothing scheduled for Monday in week 1. Next up is Monday." (by reading: `today`
  and `next` are both "Monday" and `next.weekIndex == 0`).
  (b) With no session left the body says "This is the last week of the block." in any week: week 2 of 8 at
  `TodayPresentationTests+RestDay.swift:57`. S2's review (n6) left this sentence to S3.
  Neither can be reached with a program F08 generates (it starts in the current week and trains every week),
  except (a) for the one day after flying west on day one, where it reads acceptably. Both become reachable when
  F11 can empty a week or date a start, and the tests now pin them as if they were the specification. Fix: two
  sentences from Pete, each one key and one branch of `restBody` (for example "Your block starts on %@." and
  "Nothing scheduled for %@ in week %lld. No sessions are left in this block."), asked with the other texts of
  this PR; until then a comment on the two tests that the wording is a placeholder, and an item in F11's brief.
  The Logged card is right in both cases: it leaves the "Next:" line out.

### Nits

- n1. `TodayInput.swift:13-17`: `weekWorkouts` does not say "newest first", and two rules need it:
  `loggedWorkout` takes the first match as "the newest" (`TodayPresentation+Card.swift:46-48`) and
  `withFinishedSession` places the session's workout by scanning for the first that started no later
  (`TodayPresentation.swift:160-167`). `workouts(in:)` returns that order, so one read is right and two reads
  appended would not be. Fix: say it in the comment as `recentWorkouts` does, or sort once in `Context.init` (at
  most a fortnight of workouts) so that `make` asks nothing of the store.
- n2. `TodayPresentation+Card.swift:228-230` (and `:195`): "later this week" is the program week. When the stats
  week starts on another weekday than the block did (a week start changed mid-block), the last day of a program
  week reads "Next up is next Wednesday." for a session that is tomorrow and in the strip the lifter is looking
  at, and the Logged card reads "Next: week 2". "Next: week n" has to follow the program week; the word "next"
  in the rest body would read better by the strip's week (`context.stripDays` holds `next.date` or not). Deviation
  7 chose the program week because the same sentence says "in week 1"; I would change only the word, and only
  if R4 reopens this function.
- n3. `TodayPresentation+Card.swift:180`: the Logged card's title is the program's day name; the RECENT row of
  the same workout (`TodayPresentation+Recent.swift:37`) and the live card (`+Card.swift:137`) use the workout's
  own. They differ only when the day is renamed after the workout began. The brief says "title day name" and the
  prototype reads the program's day (v1:1220), so this is to the letter; `workout.name` would keep the card and
  the row under it in step. Either; say which in the comment.
- n4. `TodayPresentation+Card.swift:31-39`: the comment says decision 1's other answer is a change to this
  function. It also needs the `Day` (the function is given only the context), so its signature and the call at
  `:13` change with it. Still small; correct the comment so that the estimate given to Pete is right.
  `loggedWorkout`'s other answer is one condition, as stated.
- n5. Translators' comments are missing where a translator most needs one: the keys with two or three values.
  `TodayCopy+Cards.swift:12-14` (`Week %lld of %lld`), `:40-42` (`Resume · %@`), `:56-58` (`%@ of %lld sets`),
  `:65-67` (`Next: %@ · %@`), `:85-109` (the three rest bodies: which `%@` is today and which the next
  session's weekday), `TodayCopy.swift:75-80` and `:109-114` (the unit lines). Fix: a `comment:` naming each
  value in order, in the code and the catalog together, before the first translation.
- n6. `TodayPresentationPropertyTests.swift:225-239`: the seeded check compares planned marks and "/N" with the
  reference only when there is no program. The generator already makes blocks begun on any weekday under every
  week start and ten zones, and the one example of a strip across two program weeks
  (`TodayPresentationTests+WeekStrip.swift:118-138`) is in UTC. Fix: in `checkTiles`, count the strip days whose
  day of the block is inside it and whose weekday that week schedules; expect `unit == "/\(count)"` and every
  planned mark on one of those days.
- n7. `TodayPresentation+Card.swift:190-201` and `:221-231`: `nextLine` and `restBody` each call
  `nextScheduledDay`, compare its week and format its weekday. One small value ("later this week: weekday and
  tag; a later week: weekday and week; none") read by both would hold the rule once. Worth doing with R4, not
  alone.

### Which card

**Right in every combination I could construct.** The order in `card(_:_:)` is the decision table's, and the
title never depends on the session.

| Combination | Card | Title | Evidence |
|---|---|---|---|
| Live workout, no program | Up next (the workout's rows, no meta), Resume | "Today" | `live_blockCompleteOrNoProgram_takesOverTheCard` |
| Live workout after the block | Up next, Resume; the meta is the workout's own week ("Week 8 of 8 · Deload · ~27 min") | "Today" | the same test |
| Today's session finished today, a new workout live | Up next, Resume | today's day | by reading (`+Card.swift:13-15`); no example: R3 |
| Finished yesterday for today's day | Up next, Start (decision 2, default A); the strip marks yesterday done and the tile counts it | today's day | `logged_doneEarlierThisWeek_isOfferedAgain` |
| The session's own workout finished in the input | Logged at once; strip, tile and RECENT in the same model; counted once when history reports it | today's day | `live_finishes_flipsToLoggedInOneUpdate` |
| The session's workout discarded | as if there were none | by the calendar | `live_discarded_offersTheSessionAgain` |
| A workout begun before midnight, still live | Up next, Resume, the workout's name | the new day's | `live_startedYesterday_takesOverTheCard` |
| The same, finished after midnight | yesterday's (decision #26); today by the calendar | by the calendar | `logged_lateNightWorkout_belongsToItsStartDay` |

- **The two open questions.** `loggedWorkout(for:_:)` is one function and its other answer one condition
  (dropping `startedToday`); it then needs the program week's workouts in `weekWorkouts`, which the notes'
  "Inputs for S5" already ask for. `workoutTakingOver(_:)` is one function whose other answer also changes its
  signature and one call (n4): about five lines and the `live_*` tests. Both are small changes.
- **The title.** Rows 2 to 6 decide it and the live workout never does, as criterion 1 defines it. The
  consequence is the notes' deviation 10: "Rest day" over a card that says "UP NEXT … Resume". It is to the
  letter of the specification and it is the first thing Pete will notice; see the list for him.
- **Before the block and with nothing left**, the card and its routes are right and the body's wording is R4.

### Dates and weeks

**Right.**

- Every day is a `CivilDate` in the input calendar's zone: today (`TodayPresentation.swift:123`), the strip's
  seven (`:128-129`, by `adding(days:)`), a workout's day (`:137-139`). The module holds no `addingTimeInterval`,
  no 86,400 and no `timeIntervalSince` (searched); the one division by 60 is a `Duration`'s whole seconds into
  minutes (`TodayPresentation+Recent.swift:29`).
- The strip is the stats week from the settings' week start, independent of the block's start
  (`firstDayOfWeek(containing:)` reads only the week start). Each strip day is judged by its own program week
  through `scheduledDay(on:in:)` at that day's first instant, which is inside the day also when midnight is
  skipped. "Sessions planned" counts those same seven days. "Week n of N", the eyebrow, "Edit this week", the
  off-schedule list and the rest body use the program week of the moment (clamped to the first before the
  block). That is the split the notes describe, and `misalignedWeekStart_stripLooksUpEachDate` pins it; n2 is its
  one awkward reading and n6 the missing seeded check.
- DST: the dates printed for a strip day are formatted from `CivilDate.startOfDay`, 01:00 on a day whose
  midnight is skipped; five zone weeks at 01:30, 12:30 and 23:30 on each day, and a workout either side of
  Santiago's skipped midnight, are tested.
- Before the first day: a rest day whose card speaks of week 1 and whose strip plans nothing before the start.
  After the last: block complete, nothing planned, what was trained still shown.
- `nextScheduledDay` returning nil is read as "no later session": the Logged card drops its line and the rest
  body takes its third form, which is where R4 (b) comes from.
- Not a defect, for S5's knowledge: the header and the strip are formatted with the injected calendar, so a
  lifter whose calendar is not Gregorian sees that calendar's month and day numbers there, over days that are
  still found on the Gregorian day count. That is consistent and probably wanted; no test has such a calendar.
  A date a zone once skipped (Apia, 30 December 2011) would be printed as the next day in the strip; no device
  clock is there.

### Numbers

**Right.**

- Sessions done, the done marks and the week's volume are all read from `Context.finished` filtered by the
  strip's seven days, so they agree by construction; the Logged card and the off-schedule marks read the same
  list. RECENT is its own input, with the same merge of the session's workout.
- The change is `Volume.percentChange(from:)` on exact decimals; its size is clamped before the sign is dropped
  (`TodayPresentation+Stats.swift:55-61`). The volume is a sum of `Volume`s. Loads, volumes and clock times go
  to the copy as the Domain's strings. Nothing in the presentation, the copy or the model names `Double`.
- Units are the settings' everywhere, a key per unit; the percent is the same in either unit (tested).
- Minutes in RECENT are whole minutes rounded down, as `ClockText` rounds seconds, so a workout never reads
  longer here than on its receipt; the estimate is `TimeEstimate`'s (half up), a different number. A workout
  under a minute reads "0 min" (pinned).
- The estimate counts a slot whose exercise is not stored and the row count does not ("3 exercises · ~38 min"):
  the plan chose it ("Behaviour the brief leaves open") and two tests pin it. See S5 below for what happens when
  that card's button is tapped.

### The words

**The 49 keys are the brief's, character for character, where the brief gives them.** 39 are quoted texts of the
copy paragraph or fragments of one cut at " · ". Of the other ten, five are the brief's lines cut again
(`%@ of %lld sets`, `/%lld`, `k`, `+%lld%%`, `−%lld%%`), one is the spoken line of `F09-today.md:73`
(`%@ of %lld sessions this week`), and four the brief does not give (`Today, %@`, `%lld%%`, `%@ kg`,
`%@ kg moved`). × is U+00D7, · is U+00B7 and the minus is U+2212, as in the brief. No text names the product
("Program" is the tab).

**The splits are right.** Each counted key counts one number and the other number is text (`%@ of %lld sets`,
`%@ of %lld sessions this week`); the noun agrees with the total, which is also what governs it in the languages
I can judge ("0 of 1 set", "5 of 1 session this week"). The fragments joined with " · " are independent phrases
in every case (week, "Deload", estimate; count of exercises, estimate; sets, volume; weekday, minutes, volume),
so no language needs to reorder across a join. `/%lld` and `k` are drawn straight after the number by `StatTile`,
and a translation can carry its own leading space. Every key with a value passes `locale:`. Two things will need
thought at the first translation and are not caused by the splits: the rest bodies place a weekday's name inside
a sentence ("for %@", "next %@"), which an inflected language cannot do with one form of the name; and "Today"
is one key for a title and for a day in a list.

**Texts the brief did not give (for Pete).**

| Text | Where | Judgement |
|---|---|---|
| "Today, Wednesday, September 16" (`Today, %@`) | VoiceOver, today's strip cell once it is trained; the component then says "Done" | Good. Keep |
| "0%" (`%lld%%`) | the volume tile, a change within half a percent | Reasonable; it is drawn in orange like a rise or a fall. Hiding it is one line |
| "1 of 1 set", "0 of 1 set" | Logged card | Correct English |
| "1 exercise" | off-schedule row | Correct |
| "1 week done. Start the next block from Program." | cannot appear: a program has at least two weeks | Harmless |
| "0 of 1 session this week", "5 of 1 session this week" | VoiceOver, sessions tile | Correct; the second reads oddly and is right |
| "567 kg moved", "3,683 kg" | Logged card, RECENT | Obvious analogues |
| "24,180 lb moved, +8%"; "0 lb moved" | VoiceOver, volume tile | Thin: no "this week", nothing to say what the 8% is against, and built in code. R1 |
| "Today" as the big title | no program; block complete | Decision 5's default. Fine |
| "Deload", "k", "/4" as texts of their own | cut from the brief's lines | Fine |
| 24 translators' comments | catalog | Accurate. The many-valued keys have none (n5) |

**The brief's own texts used where it did not foresee them (also for Pete).**

- "Rest day" as the title while a workout runs on a rest day, and "UP NEXT" over a workout that is running
  (deviations 10 and 11). To the letter of the specification. The eight planned screenshots do not include this
  state; ask S4 for it.
- "Nothing scheduled for Sunday in week 1. Next up is Monday." before the block, and "This is the last week of
  the block." when it is not (R4).
- "Next up is next Monday." when Monday is two weeks away (criterion 12; accepted).
- "0 k lb moved · −100%" every Monday morning once last week has volume: decision #15 compares the week so far
  with the whole week before. Correct by the decision; it will read as bad news until late in each week. Options
  if it reads badly in S4's screenshots: no change until this week has a workout, or a comparison of the week to
  date.
- "1/0 sessions this week" after the block or without a program, once something is trained (criterion 8 gives
  "0/0").
- "Wed · 58 min · 100 lb" for a workout of any age; "0 min" under a minute; "135 min" rather than hours.
- A day marked "Logged" in the off-schedule list can still be picked, and starts that day again.

### The model as an interface

**Right for S4, and fillable by S5 from the calls on `main` without another read.**

- `WeekStrip(days: model.weekStrip)` and `StatTile(value:unit:caption:delta:accessibilitySummary:)` take the
  model's values field for field (checked against both components). `Message` is `EmptyState`'s arguments,
  `RecentRow` is `HairlineRow`'s, `OffSchedule` is `SheetChrome`'s title and cancel with rows.
- Every action carries its route; `.startWorkout(program:weekIndex:day:)` is `WorkoutSource`'s three fields,
  which is what `StartWorkoutUseCase.start(_:replacingLive:)` on `main` takes.
- Nothing in it is a decision a view must make again. The view tells a live card from a scheduled one by the
  action's case, and the eyebrow's tint by the card's case; both are drawing, not logic.
- Nothing in it is more than S4 needs, except `PreviewRow.isHeld` and `isDeload`, carried for F24 as the plan
  asks.
- Only `TodayRoute` public is right: `LedgerAppKit` will see `TodayRoot` (S5) and the route, and maps the route
  with `LedgerDomain`'s public ids.
- `TodayInput`: each field has its call (the notes' table is right against `Repositories.swift`). One piece of
  calendar logic falls to the store unless S5 lifts it: the range of `weekWorkouts`. See S5 below.

### `/code-review`'s ten findings

| # | Finding | Verdict |
|---|---|---|
| 1 | Before the block the rest body says "week 1" and "Next up is Monday" at any distance | R4 (a) |
| 2 | "This is the last week of the block" whenever no session is left | R4 (b) |
| 3 | "This week" and "next" follow the program week, not the strip's | By deviation 7; n2 |
| 4 | The header's title ignores the live workout | By criterion 1 and the decision table; for Pete |
| 5 | The estimate counts a slot whose exercise is missing; the rows and the count do not | Chosen in the plan and pinned by two tests; S5 note |
| 6 | The change compares the week so far with a whole week ("−100%" on Monday) | Decision #15 as written; for Pete |
| 7 | "/0" when nothing is planned | Criterion 8 ("0/0"); for Pete |
| 8 | A finished workout with no end keeps counting | Not reachable: `materialize` refuses one (`Repositories.swift:64`) and the engine sets the end. No action |
| 9 | Logged's title is the program's day name, RECENT's the workout's | n3 |
| 10 | `nextLine` and `restBody` repeat the lookup | n7 |

### The seven points

1. **Module boundaries**: pass. The module imports Foundation, `LedgerDomain` and `LedgerDesign` (for
   `WeekStrip.Day`); nothing in `LedgerDomain` changes; `Package.swift` gains `resources` on one target and no
   edge; only `TodayRoute` is public.
2. **Concurrency**: pass. Every type and every extension is `nonisolated`; the model, the input and the route
   are `Sendable` values; no task; the moment, the calendar and the locale are fields of the input.
3. **Error handling**: pass. Nothing throws and nothing is swallowed; each "no value" (no calendar date, no such
   week, no such day, no stored exercise) is a documented nil with a test. What the lifter is told when a start
   fails is S5's.
4. **Design fidelity**: no view in this slice. The model's shapes are v2's (the value and its unit apart, the
   caption and its change apart; v2:108-117) and the copy is the brief's.
5. **Accessibility**: pass for what the slice owns: each strip cell and each tile carries its spoken text. The
   cards' lines have none ("~38 min", "5 × 5 @ 250"); see S4 below. R1.
6. **Test quality**: pass, with R2, R3 and n6. Tests go through `make` and the copy file and assert what is
   shown; the seeded reference is written with Foundation's calendar alone; seeds come from `PropertySeed.all`
   and a failure prints the seed and one line of the input; no sleep, nothing disabled. Names follow §6.
   **No large value is compared inside `#expect`**: the two model equalities are computed first
   (`TodayPresentationTests.swift:146`, `TodayPresentationTests+Live.swift:201`), and the largest operands
   anywhere are arrays of at most seven short strings. By the probe above, a failed
   `#expect(TodayPresentation.make(input)… == …)` records only the two sides, not `input`. Two `#require`s would
   record a large receiver if they ever failed, once per test because `#require` throws:
   `TodayPresentationTests+UpNext.swift:17` (the program) and `:24` (the 214-exercise dictionary). Not a risk to
   the disk; named because the task asked for every one.
7. **Brief compliance**: pass. Each of the twelve criteria has tests; I checked every name in the notes'
   "Criteria → tests" table against the files. Nothing of S4 to S6 is in the range (no view, no store, no root);
   no lint suppression, `try!`, `as!`, `fatalError` or `@unchecked`; the largest file is 248 lines (the lint warns
   at 300) and the longest function body about 30 (it warns at 40). Nothing reads as compressed to fit.
   `coverage-thresholds.json` gains `"FeatureToday"` in `required`, and `Package.swift` the six lines of one
   target written as `LedgerAppKit`'s is.

Also asked: **the two catalog tests the plan named are not needed.** `catalog_holdsEveryKey` is the gate's
string-catalog step (the catalog against the compiler's keys, both ways) and check 3 of `ModuleCopyTests` (the
built bundle resolves each key); `catalog_pluralRules` is `StringCatalog.problems`, which `ModuleCopyTests` runs
on every module and `TodayCopyTests.swift:126-128` runs again, and `countedTexts_haveOneAndSeveral` reads each
counted text with one and with several. **What the 65 mutants could not reach**: R3's combination; that each
`locale:` in the presentation is the input's (every number in the tests prints the same in `en_US` whatever
locale is passed, and only the date is tested in another; the source test stops `.current`, not a constructed
`Locale`); and code not yet written, which is R2.

### What S4 must be told

- Draw the model and call nothing else, but for the one timer `Text` in the copy file, whose key must be the
  same `Resume · %@`. `UpNext.meta` is nil for a live workout that is not a session of the active program, and
  `rows` can be empty.
- Rows carry no ids and two rows can be equal: draw by offset.
- The model has spoken text for the strip's cells and the tiles only. If the device pass hears "tilde 38 min" or
  "5 multiplication sign 5", the spoken forms are new keys in `TodayCopy` and new fields of the model, not labels
  written in a view.
- The model does not hold its moment. A preview or a snapshot that freezes the timer passes its own `pauseTime`;
  `action.title` is the label as it reads at the model's moment.
- Every off-schedule row carries a route, a "Logged" one too, and `days` can be empty.
- Add to the previews and screenshots the states that carry Pete's open questions: a workout live on a rest day
  ("Rest day" over "UP NEXT … Resume"), the volume tile on a Monday ("0" "k", "−100%"), and "1/0".
- An extension of a `nonisolated` type must itself be written `nonisolated` (the notes' deviation 3), and the
  source test reads every file of the module, views included (R2).

### What S5 must be told

- `weekWorkouts` is one `workouts(in:)` read over the union the notes give, newest first (n1). Put the range in a
  pure, tested function of `FeatureToday` beside the presentation, not in the store: it is the one piece of
  calendar logic the input needs, and the presentation already builds the same `WeekCalendar`.
- Build each input from one refresh's reads. A model made from a newer RECENT and an older week read shows "Up
  next" over a list that says "Today · 24:22".
- S6: a finished session state arrives once and nothing follows it. The presentation merges it by id for as long
  as it is in the input, so drop it once a history read made after it has returned; otherwise a workout deleted
  in History stays on Today's strip, tiles, card and list until the next session update or a relaunch. A
  discarded state can be passed as it is.
- `.startWorkout` can be refused for a card the model still offers: `emptyDay` (a day with no slots),
  `unknownExercise` (a slot whose exercise is not stored: the card shows fewer rows and the estimate still counts
  it), `programNotActive` and `weekOutOfRange` (a model older than the program). The route's handler needs an
  answer the lifter can read.
- The model is `Equatable`: skip a publish that changes nothing. It is a function of `now` and does not tick;
  the day and the week roll over only when the input is filled again.
- Under decision 2's other answer the program-week half of `weekWorkouts` decides the card, not only the
  off-schedule marks.

### What I did not check

- The slice's tests. I ran none, on the host or on a simulator: the tester's untracked files are in the target,
  and the gate on `906d5a8` is the orchestrator's. The 89 tests, 535 of 535 lines and the 65 mutants are the
  implementer's figures; I did not run a mutant (no edits to product code, no copy of the repository).
- Whether one of the 200 seeds produces R3's combination.
- The catalog against the compiler's keys and Xcode's layout (the gate's step). I compared the committed file
  with the brief and with the copy files by reading and by script.
- How VoiceOver speaks any of the texts; any locale but `en_US` on a device; a calendar that is not Gregorian.
- The tester's files, which I did not open.


## Slice S4 — review (G3 reviewer, 2026-10-08)

Reviewed: `git diff a00584e..398ec9a` on `feat/F09-s4-views` (one commit, 125 files, 91 of them PNG). Paths that
start with a module name are under `LedgerKit/Sources/`; test paths are under `LedgerKit/Tests/`. Screenshot names
are files of `tasks/features/F09-today/screenshots/s4/`. v2 is `design/prototype/Ledger v2.dc.html`.

**Verdict: approved. 0 Blocking, 4 Should fix, 9 Nits.** The views draw the model and nothing else, the split for
a screen that scrolls is the convention's, the trees are the ones a lifter should hear but for the resume button,
and no existing reference changed. Two of the Should-fix items are choices for Pete (S1, S2); two are things the
next slice must be handed in writing (S3, S4). None needs a fix round before the PR if the orchestrator records
them for S5.

### What I ran

- `/code-review` at effort `high` on the diff, through the Skill tool (it ran as a forked agent). Ten findings; each
  is placed in "`/code-review`'s ten findings" below. **One thing to know:** that agent ran `git checkout 398ec9a`
  in the main checkout (`/Users/peterarevalo/Dev/workout-app`), which my rules forbid, and then switched back. I
  checked afterwards: the main checkout is on `main` at `1d16e28` and clean, and its reflog shows the two
  checkouts. This worktree was never touched by it (`feat/F09-s4-views` at `398ec9a`).
- Host: `swift test --package-path LedgerKit --only-use-versions-from-resolved-file --filter
  'FeatureTodaySourceTests|TodayPurityAdversarialTests|TodayCopyTests|ModuleCopyTests'`: exit 0, the four suites
  passed ("Module copy", "Adversarial F09 S3 · purity", "TodayCopy", "FeatureToday sources"). The tester's
  untracked `TodayViewsAdversarialSupport.swift` was in the tree by then and the build still passed.
- A Core Text script in my scratch folder that measures Archivo's digits at the button's size and weight (see
  "The timer").
- Read: 14 of the 24 screenshots (01 to 07 and 09 to 13 dark; 01 and 04 light) and five references
  (`offSchedule…dark-accessibility3`, `logged…light-accessibility3`, the two design galleries). I did not open all
  67.

### Blocking

None.

### Should fix

**S1. The resume button tells VoiceOver a time that is no longer true, in a form VoiceOver reads as a clock
time.** `FeatureToday/Views/UpNextCard.swift:40-44`, `LedgerDesign/Components/PrimaryButton.swift:41-47`.
The button draws a live `Text(timerInterval:)`; its spoken label is `action.title`, the string made when the model
was made, and `.updatesFrequently` is taken off. "Liveness" in the notes says Today does not refetch while sets are
logged, so the label is as old as the last reload: a lifter who leaves Today open for twenty minutes sees
"Resume · 23:00" and hears "Resume · 3:00". And "3:00" is a spelling VoiceOver is likely to read as three o'clock
(not verified: no device). The implementer raised the staleness (open question 3); the reason given in the code,
"a label that changed each second would be read again and again", is not how VoiceOver behaves: it reads a label
when the element gets focus, and `.updatesFrequently` exists to tell it to poll such an element politely.
- Why it matters: criterion 7 ("labels from the model's spoken texts"), and the brief's criterion 3. It is the one
  stop on the screen whose spoken text can be false.
- Fix, one of (Pete's choice, before S5 puts the screen in the app): (a) the spoken label carries no time: a new
  key "Resume workout" and a model field for it, the review's rule for a spoken form (S3, "What S4 must be told");
  (b) the button reads its live label: make `accessibilityLabel` optional in `PrimaryButton(label:…)`, and with
  nil neither override the label nor remove `.updatesFrequently`. I recommend (a): it is true at every moment and
  cannot be misread. Either way make the parameter optional: as written every later caller (F10's workout screen)
  is forced to hand a fixed string to a counting button.
- What would settle (b): the hosted tree of the button without the override, frozen, and one listen on a device.

**S2. The Up-next rows are heavier and brighter than v2's.** `FeatureToday/Views/UpNextCard.swift:22-30`;
`01-up-next-dark.png`. v2:95-98 sets the exercise at 400 14 px in ink at 72 % and the scheme at 500 14 px at 45 %,
13 px above and below: a quiet list under a loud title. The slice draws F06's `HairlineRow`: 500 15 pt in full ink
and the scheme in 700 `numeralS` at `inkSecondary`, 16 pt above and below. In the screenshot the four rows weigh
as much as the RECENT rows' titles and compete with "Lower A — Squat focus". The implementer says so (decision 13)
and the row is the one F06's gallery draws, so this is deliberate, not a slip; it is still the largest visible
difference from the one state v2 does draw.
- Why it matters: criterion 4.
- Fix: either Pete accepts it from `01-up-next-dark.png`, or `HairlineRow` gains a quiet style in `LedgerDesign`
  (a `body`-size 400 title in `inkSecondary`, `m` padding) with its gallery row and references, and `UpNextCard`
  uses it. Not a literal in the feature.

**S3. The screen's own behaviour has no test, and S5's specification must name the one that covers it.**
`FeatureToday/Views/TodayScreen.swift:23-56` (`handle`, `pick`, `offSchedule`, the `onChange`). Nothing presents the
sheet, picks a day, cancels, or sees the sheet go when the card changes. I agree a hosted test cannot do it here:
the two pills are inside the scroll view, which the reader cannot enter. So it is S5's UI test, and it must be
written into S5's criteria, not left as an open question: open the sheet, cancel; open, pick a day, the sheet is
gone **and the destination of `.startWorkout` is on screen** (see "Could not settle" 1). The long press is covered
by `LedgerUITests` once S5 wires `onTitleLongPress`; nothing to add now.
- Why it matters: the body's criterion 5 ("picking a day emits `.startWorkout` for that day") rests on untested
  view code, and the nightly lane is not a merge gate.
- One test worth adding now, on the host: `EnvironmentValues().todayTimerPause == nil`. It is the only thing
  between the app and a frozen resume time, and it costs three lines.

**S4. The sheet closes whenever the state is not a loaded rest day, which includes a reload that passes through
`.loading`.** `FeatureToday/Views/TodayScreen.swift:29-33, 36-41`. The comment says "a model that stops offering
the list takes the sheet away", which is right for a card that changed. But `offSchedule` is also nil for `.idle`,
`.loading` and `.failed`. If S5's store ever publishes `.loading` on a refresh (the scene becomes active, the tab's
task restarts), a lifter with the sheet open sees it close under the finger and the page go blank.
- Fix: nothing in this slice's code, if S5 is told: **once loaded, the store never goes back to `.loading`; a
  refresh replaces `.loaded(old)` with `.loaded(new)`**, and a test of the store pins it. Put it in S5's
  criteria. (A refresh on the same rest day keeps the sheet: its content is read from the new model. Good.)

### Nits

- **n1. A blank sheet while it leaves.** `TodayScreen.swift:25-27`: when the list goes, the sheet's content is
  empty for the length of the dismissal, without `SheetChrome`'s surface. `.sheet(item:)` over a held copy would
  keep the last list drawn; rare, and cosmetic.
- **n2. The pills and the eyebrow line change layout by size class, not by fit.** `RestDayCard.swift:14-16`,
  `CardEyebrowLine.swift:15-17`. At `.xxxLarge` on a 375 pt phone "Edit this week" and "Train off-schedule" side by
  side are near the width (my estimate from `04-rest-day-dark.png`: about 322 of 323 pt); no reference is drawn
  there. `ViewThatFits` decides by fit. What would settle it: one snapshot at `.xxxLarge`, 375 pt wide.
- **n3. `IconPillButton(_:systemImage:)` takes any string.** `LedgerDesign/Components/IconPillButton.swift:27`. A
  mistyped name draws an empty circle and no test fails. For F10 and F11 a small enum in `LedgerDesign` (the
  symbols the product uses: the gear, a magnifying glass) keeps the names in one place. The gallery already shows
  a second symbol nothing uses ("Search").
- **n4. The two new galleries are not in the Debug menu's `DesignGallery`** (`Gallery/DesignGallery.swift:67-69`),
  so the in-app gallery does not show a timer label or a symbol button. Stated (decision 10) and it is why no
  reference changed. Add them with the next slice that re-records that page.
- **n5. `TodayScreenTests.swift:1` and `TodayAccessibilityTests.swift:1` guard on `os(iOS)` but use `TodayPreview`,
  which is Debug-only.** The other new suites guard on `DEBUG`. No lane tests a release build today; write
  `#if os(iOS) && DEBUG`.
- **n6. Comment drift.** The specification's criterion 2 and standards §7 say "`<Screen>Page(model:)`";
  `TodayPage` takes `state:`. Accepted (see the point below); the two documents should say "its model or the
  `Loadable` of it" when the orchestrator next edits them.
- **n7. `TodayAction.titleLongPress` exists in release builds** though nothing can send it there
  (`TodayAction.swift:10`, `TodayHeader.swift:25-27`). Harmless; the case could sit in the same `#if DEBUG`.
- **n8. The tester's scan still reads the top folder only** (`Adversarial/TodayPurityAdversarialTests.swift:21`),
  so its own word and ambient scans never see `Views/`. Not this slice's change, and the views are read by
  `CopyAudit` and `FeatureTodaySourceTests`, both recursive; for the tester to decide.
- **n9. "30,370" and "lb moved" part at a line break** at `accessibility3`
  (`logged_matchesReferences.light-accessibility3.png`). The model's string; a no-break space between a number
  and its unit is a change to the copy, for a later slice.

### Could not settle

1. **A pick closes the sheet and hands the route on in the same turn** (`TodayScreen.swift:53-56`). If the app
   answers `.startWorkout` by presenting something (a full-screen workout) while the sheet is still leaving, UIKit
   can refuse the second presentation and the lifter sees the sheet close and nothing open. Whether it does
   depends on how F10 presents a workout and on the store's `.task(id:)` delivery, neither of which exists here.
   What settles it: S5's UI test of the pick (S3 above). If it fails, hand the route on from the sheet's
   `onDismiss`.
2. **How VoiceOver speaks** "Resume · 3:00", "24:22", "5 × 5 @ 250", "~38 min", "Mon · 58 min". The trees pin the
   strings, not the speech. The device pass, as the implementer says (open question 4).

### The points the task named

- **No decision in a view: holds.** I read all thirteen bodies. Every branch is on the model's own cases or
  optionals (`TodayPage.swift:23-38, 44-50`; `UpNextCard.swift:35-46`; `RecentList.swift:13`;
  `LoggedCard.swift:25`; `CardEyebrowLine.swift:20`; `OffSchedulePage.swift:21`), or on
  `dynamicTypeSize.isAccessibilitySize`, which is layout. No number or date is formatted; the only `Text` not made
  from a model string is the timer, from the copy file. Texts not from the model: the two of the failed state,
  from `TodayCopy` (the criterion allows it). Ambient reads: `dynamicTypeSize` and `todayTimerPause` only. The one
  place the screen "decides" is `TodayScreen.offSchedule`, which finds the rest-day card's list: presentation
  state, and correct.
- **Design fidelity:** the list below. One "wrong enough to ask" (S2); the rest matches or is deliberate.
- **The convention for a screen that scrolls: followed.** Nothing is pinned, as v2:68 has it. Trees and references
  come from `TodayParts` and `OffScheduleParts`; `TodayScreenTests` pins one scroll view per state, taller than
  the phone at `accessibility3` and never wider. No `outsideScrollViews: true` anywhere in the slice. **`TodayPage`
  taking the `Loadable` is acceptable and better than the letter of the rule:** with `TodayPage(model:)` the
  loading and failed states would live only inside the scroll view, where no tree could be read. The loading
  reference is drawn from the screen itself, which is fine for a state that draws nothing.
- **Actions: right.** `TodayAction` never leaves the module's views: the screen's surface is
  `onRoute: (TodayRoute) -> Void` and `onTitleLongPress`, both synchronous, which is what S5's store intent and
  `LedgerAppKit`'s route mapping take. One closure down the tree is simpler than five and the tests read it well.
  The long press built now is justified (the tree is pinned with the gesture on the title; traits stay heading and
  text, so `app.staticTexts["today.title"]` still finds it). The sheet's state is the screen's `@State`; it
  survives a refresh that stays a loaded rest day, and does not survive a pass through `.loading` (S4).
- **VoiceOver:** date, title (heading), gear, seven days with their marks as values, the card under one heading,
  two tiles as one stop each with the model's sentence, "RECENT" (heading), the rows as buttons. That is what a
  lifter should hear. The seven day stops stand between the gear and the card on every visit; the headings rotor
  skips them. The gear reads "Settings, button" (the body's criterion 13). The sheet reads title, Cancel, the
  sentence, the days with "Logged", and escape cancels (tested). The resume button: S1.
  `PrimaryButton`'s `accessibilityLabel`: needed by this design, wrong to require (S1).
- **Dynamic Type:** at `accessibility3` and `accessibility5` nothing is clipped or overlapping in the references I
  read (`12-…`, `13-…`, the sheet and Logged at `accessibility3`). The tiles and the pills stack, "Cancel" and
  "Logged" drop under their titles, the strip keeps seven columns and shrinks "20" at `accessibility5` (F06's
  component). 44-point targets are tested per state at two sizes. Between `.xLarge` and `accessibility1` nothing
  is drawn (n2).
- **The timer:** `Text(timerInterval:pauseTime:countsDown:)` inside the catalog key `Resume · %@`, the form
  standards §7 allows a copy file; frozen through `todayTimerPause` in previews, trees and references, nil in the
  app. Nothing else animates. `/code-review` suspected the centred label shifts each second because the `button`
  role is not tabular. **Measured, not so:** Archivo's digits are 9.52 to 9.53 pt wide at 16 pt, so "3:00" and
  "3:11" differ by 0.03 pt. The label moves only when a digit is added (9:59 to 10:00).
- **The design components:** both are small, additive and keep the old initialisers; no existing caller or
  reference changed (`git diff --name-status` shows every PNG as added). Each has a gallery, six references and
  tree rows. As written for F10 and F11: `PrimaryButton(label:…)` after S1's optional parameter, and
  `IconPillButton(systemImage:)` with n3, are reusable.
- **Failed and loading:** loading draws the ground alone, by the orchestrator's ruling; failed is `EmptyState`
  with the two texts and no header, so no gear and no `today.title` (the implementer tells S5). Fine for a state
  a lifter should never meet.
- **The edit to the tester's file: mechanical and justified.** The count follows the two ruled keys. The
  `*+Previews.swift` exemption is the one `CopyAudit` already makes (standards §7: a previews file wholly inside
  `#if DEBUG` goes unread), and `Today+Previews.swift` is wholly inside it. The ambient scan of that suite still
  reads the previews file, and `FeatureTodaySourceTests` reads every file. Not weakened. The scan's blindness to
  `Views/` is older than the slice (n8).
- **Tests:** the trees prove the stops, order, labels, values and traits of eleven states at two sizes, from the
  page; the action tests prove each control sends the model's route once. They do not prove the order inside the
  real scroll view (S5's nightly test), speech, or the screen's sheet logic (S3). The 67 references prove layout
  at six appearances per state with the time frozen. No tree is handed to `#expect` whole (`firstDifference`);
  the largest values compared in place are an array of five actions and one of eleven short strings, which is
  fine. Names follow §6. **Recording in the default missing-reference mode is the project's way** (§2.5: "Record
  policy: swift-snapshot-testing's default `.missing`"); `--record-snapshots` is for re-recording all. Recorded on
  the pinned iPhone 17 (iOS 27.0), then compared green twice, and the orchestrator's gate compared them again.
  The PR lists the 67 under "Screenshots".
- **Boundaries, tokens, size:** the views import `LedgerDesign`, `LedgerDomain` and SwiftUI; the previews import
  `LedgerFakes` inside `#if DEBUG`, as standards §7 asks. No change to `LedgerAppKit`, the presentation or the
  Domain. No literal colour, font, radius or spacing in the feature but `spacing: 0`. 631 lines against 610: the
  previews' fixtures. 3.6 MB of references is the specification's matrix and far under the 300 MB line. No lint
  suppression added.

### Design fidelity

| Part | Screenshot | Verdict |
|---|---|---|
| Side inset 26, column order, hairlines | `01-up-next-dark` | matches |
| Date 12 pt muted over 32 pt title | `01` | matches; the date is `inkMuted`, brighter than v2's 40 %, deliberate (AA) |
| Gear in a 44 pt outlined circle for v2's 40 px "JD" | `01` | deliberate (decision #19; a tap needs 44 pt) |
| Week strip, today's number and dot orange | `01`, `04` | matches |
| "UP NEXT" orange, the note on its baseline | `01` | matches; the note is brighter than v2's 38 %, deliberate (AA) |
| Card title 27 pt for 25 px | `01` | deliberate (nearest role) |
| Exercise rows | `01` | **heavier and brighter than v2: S2** |
| Orange button with arrow | `01`, `02` | matches |
| Tiles, "/4" and "k" light, "+8%" orange, rule under | `01` | matches |
| RECENT eyebrow, rows, chevron | `01` | matches |
| Gaps 32 and 24 for v2's 30 to 34 and 26 to 30; 16 for 20 | `01` | deliberate (the scale's steps); reads as v2 |
| Orange only on the button, today, "UP NEXT", the change | all | matches (criterion 12); "LOGGED · WEEK 1" is grey |
| Logged, rest day, no program, block complete, the sheet | `03` to `07` | no design; consistent with Up next's type; for Pete |
| Light mode | `01-…-light`, `04-…-light` | legible; the orange text is the darker `accentText`; nothing faint |

### For the product owner

- `01-up-next-dark`: the exercise rows' weight (S2).
- `02-live-workout-dark`: "Resume · 3:00", and what VoiceOver should say for it (S1).
- `03-logged-dark`: the card v2 never drew. Also: **once today is logged, the strip no longer shows which day is
  today**; the 16 is white with a grey dot, like Monday. That is the presentation's rule (done before today) and
  F06's cell, not this slice's, but this is the first picture of it.
- `04-rest-day-dark`, `05-off-schedule-sheet-dark`: the pills and the sheet.
- `06-no-program-dark`, `07-block-complete-dark`: the orange "Set up program" and "Open Program"; "1/0".
- `10-live-workout-on-a-rest-day-dark`: "Rest day" over "UP NEXT" and Resume.
- `11-monday-nothing-moved-dark`: "0k" and "−100%" on a Monday morning.
- `09-failed-dark`: the two new texts: **"Can't show today right now"** and **"Your workouts are still on this
  iPhone. Open the app again to try once more."** The sibling screen in `LedgerAppKit` now ends "The app tries
  again when you come back to it." (`AppCopy.swift:39`, revised in S1). The two should end the same way, and
  S5's root does retry when the app comes back, so the sibling's ending is the truer one.

### `/code-review`'s ten findings

1 stale spoken resume time: S1. 2 the purity scan does not read `Views/`: true, older than the slice, n8.
3 the sheet closes on any state that is not a loaded rest day: S4. 4 pick and route in one turn: "Could not
settle" 1. 5 the pills switch by size class: n2. 6 the timer `Text` takes the environment's locale, not the
input's: true and unavoidable for a `Text`; the app has one locale; no finding. 7 an empty sheet while it leaves:
n1. 8 the label shifts each second: refuted by measurement. 9 `os(iOS)` guard around Debug-only names: n5.
10 the stack-or-row switch written three times: true; a helper in `LedgerDesign` when a fourth appears; no
finding.

### The seven points

1. **Boundaries:** clean. 2. **Concurrency:** no task, no actor hop; `TodayAction` is `Sendable`; the `@Entry` key
is `nonisolated`. 3. **Errors:** `.failed`'s payload is ignored by the view by design; the two `try?` in the
previews carry their comments. 4. **Design fidelity:** tokens only; matches v2 but for S2. 5. **Accessibility:**
labels, order, headings and targets pinned; S1 open. 6. **Tests:** behaviour, no sleeps, serialized hosted suites;
S3's gap. 7. **Brief:** each of the nine criteria has a test or a screenshot; criterion 5's "ticks" and criterion
6's sheet are by review and S5.

### What S5 must be told

- Once loaded, never publish `.loading` again; replace the model (S4). Pin it in the store's tests.
- Its UI test covers: the sheet opens, cancels, a pick closes it and the route's destination appears (S3, "Could
  not settle" 1); the stops in order inside the real scroll view at an accessibility size.
- A reload must rebuild the model when Today comes back on screen, or the spoken resume time is older still (S1,
  if Pete keeps the time in the label).
- `today.title` exists only when loaded; the failed state has no gear.
- The views do not debounce: a double tap calls `onRoute` twice.
- Leave `todayTimerPause` unset.

### What I did not check

- Anything on a simulator or a device: the hosted suites, the snapshot comparison, VoiceOver's speech, the timer
  counting. I rely on the orchestrator's gate for green.
- About 48 of the 67 references (the whole `xLarge` set, most light ones, most `accessibility3` ones) and 10 of
  the 24 screenshots (08, and the light ones but 01 and 04); the watch build of `LedgerDesign`.
- The tester's `TodayViews…` files, which I did not open.
- The full text of `docs/architecture.md` §4–§5 and §11–§12 and of `docs/product-spec.md` §3.10: I read the
  standards' and the testing strategy's sections on views, localisation and scrolling screens, and v2:66-129, and
  took the architecture's rules from those and from the notes.
