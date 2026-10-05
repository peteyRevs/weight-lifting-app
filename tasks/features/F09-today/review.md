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
