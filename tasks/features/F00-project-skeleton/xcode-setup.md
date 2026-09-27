# F00 — the Xcode sitting (human, ~25 min, done once)

Everything the project needs to *reference* already exists on the
`feat/F00-project-skeleton` branch: `Config/*.xcconfig`, `LedgerKit/`,
`Apps/Ledger`, `Apps/LedgerWatch` (+ their test folders), `TestPlans/*.xctestplan`,
`Resources/Fonts`. This sitting only creates `Ledger.xcodeproj` and wires it to
them, in one go — stopping half way is what produced the broken project that was
scrapped on 2026-09-24.

Xcode must be **26.6**. `xcodebuild -version` and `cat .xcode-version` agree.

---

## 1. Create the project

File ▸ New ▸ Project ▸ iOS ▸ **App**

| Field | Value |
|---|---|
| Product Name | `Ledger` |
| Team | Peter Arevalo (the paid Individual team — **not** "Personal Team") |
| Organization Identifier | `com.petearevalo` (bundle id shows `com.petearevalo.Ledger`) |
| Interface | SwiftUI |
| Language | Swift |
| Testing System | **Swift Testing** |
| Storage | None |
| Include Tests | ✅ |

Save at the **repo root** `/Users/peterarevalo/Dev/workout-app`, and **untick
"Create Git repository"**.

Xcode generates `Ledger/`, `LedgerTests/`, `LedgerUITests/` at the repo root.
**Delete all three folders** (Finder → Trash) — the real sources are already in
`Apps/`. In Xcode the three groups go red; delete them from the navigator too
("Remove Reference" or Delete, either is fine now that the files are gone).

## 2. Re-add the sources as synchronized folders

File ▸ Add Files to "Ledger"… and add, one at a time:

| Folder | Target | Note |
|---|---|---|
| `Apps/Ledger` | `Ledger` | |
| `Apps/LedgerTests` | `LedgerTests` | |
| `Apps/LedgerUITests` | `LedgerUITests` | |

In the sheet, **"Create folder references"** is what produces a synchronized
folder on Xcode 16+ — the navigator must show a **plain folder icon**, not a
yellow group. Adding a file to these folders must never touch the pbxproj again
(ADR-003).

## 3. Add the watch target

File ▸ New ▸ Target ▸ watchOS ▸ **App**

- Product Name `LedgerWatch`
- "Watch App for Existing iOS App" = `Ledger`
- Testing System Swift Testing, include tests

Xcode generates `LedgerWatch/`, `LedgerWatchTests/`, `LedgerWatchUITests/` at the
repo root. **Delete those three folders too**, then add
`Apps/LedgerWatch`, `Apps/LedgerWatchTests`, `Apps/LedgerWatchUITests` as
synchronized folders exactly as in step 2.

## 4. Point every configuration at the xcconfigs

The Configurations menus only list xcconfig files that are in the project, so
first add the `Config` folder: Add Files to "Ledger"… ▸ `Config` ▸ Reference
files in place, **Create folders**, and **no target ticked** (nothing in it is
compiled).

Project ▸ Info ▸ Configurations:

| Level | Debug | Release |
|---|---|---|
| **Project** (`Ledger`) | `Debug` | `Release` |
| Target `Ledger` | `Ledger` | `Ledger` |
| Target `LedgerWatch` | `LedgerWatch` | `LedgerWatch` |
| Targets `LedgerTests`, `LedgerUITests` | `Tests` | `Tests` |
| Targets `LedgerWatchTests`, `LedgerWatchUITests` | `WatchTests` | `WatchTests` |

Never pick `Base`; `Debug` and `Release` include it.

Then clear every build setting the templates wrote, on the project **and** all
six targets: Build Settings ▸ **All** + **Levels**, click a row, ⌘A, Delete.
The column named after the project/target must end up empty. This also deletes
the three settings that legitimately stay at target level (`TEST_HOST`,
`BUNDLE_LOADER`, `TEST_TARGET_NAME` — they differ per test target and xcconfig
has no per-target conditionals), so put them back by choosing General ▸
Testing ▸ **Host Application** (`LedgerTests` → `Ledger`, `LedgerWatchTests` →
`LedgerWatch`) and **Target Application** (`LedgerUITests` → `Ledger`,
`LedgerWatchUITests` → `LedgerWatch`).

## 5. Add the local package

Drag the `LedgerKit` folder from Finder onto the project in the navigator
(Reference files in place, no targets). **Not** File ▸ Add Package
Dependencies… ▸ Add Local…: that makes LedgerKit a *dependency*, whose test
targets Xcode never builds, so every LedgerKit test silently drops out of the
test plans (implementation-notes #17).

Then per target ▸ General ▸ Frameworks, Libraries and Embedded Content:

- `Ledger` → `LedgerAppKit` **only**
- `LedgerWatch` → `LedgerWatchAppKit` **only**

## 6. Capabilities — check only, nothing to add

The committed files already carry them: HealthKit in `Apps/Ledger.entitlements`
and `Apps/LedgerWatch.entitlements` (via `CODE_SIGN_ENTITLEMENTS`), and
`WKBackgroundModes = workout-processing` in `Apps/LedgerWatch-Info.plist` (via
`INFOPLIST_FILE`; `GENERATE_INFOPLIST_FILE` stays YES so Xcode merges its keys
in). Once step 4 is done, Signing & Capabilities on both targets should list
HealthKit. If Xcode writes a new `.entitlements` or `Info.plist` anywhere, trash
it. These files sit **beside** the synchronized folders, not inside them, because
a synchronized folder copies everything it holds into the bundle
(implementation-notes #11).

## 7. Bundle the font

Add Files ▸ `Resources/Fonts` ▸ Reference files in place, **Create folders**,
targets **`Ledger` and `LedgerWatch`** only. A synchronized folder copies its
files *flat* into the bundle, so each app ends up with
`Archivo[wdth,wght].ttf` (and `OFL.txt`, which the licence wants shipped with
the font) at the bundle root — which is what `UIAppFonts` names in both
Info.plists.

## 8. Schemes and test plans

Product ▸ Scheme ▸ Manage Schemes: keep exactly `Ledger` and `LedgerWatch`,
delete any others, tick **Shared** on both.

Add the `TestPlans` folder like `Config` (Create folders, no target).

Attaching the plans is **not** done in the scheme editor: Xcode 26.6 creates
schemes with `shouldAutocreateTestPlan = "YES"`, which has no "Convert to use
Test Plans…" button. With Xcode quit, the orchestrator replaces each scheme's
`<Testables>` with `<TestPlans>` in `Ledger.xcodeproj/xcshareddata/xcschemes/`
(scheme XML is not the pbxproj, so ADR-003 allows it):

| Scheme | Plans (default first) |
|---|---|
| `Ledger` | `TestPlans/PR.xctestplan`, `Nightly`, `Device` |
| `LedgerWatch` | `TestPlans/PR-Watch.xctestplan`, `Nightly-Watch`, `Device-Watch` |

`xcodebuild -showTestPlans -scheme Ledger` must list all three. The plans refer
to the four app test targets by their pbxproj target IDs (a plan written before
the project existed can only guess, so they were filled in once the project
existed) and set `targetForVariableExpansion` to the host app so
`$(PROJECT_DIR)` in `SNAPSHOT_ARTIFACTS` expands. Otherwise they already carry
coverage targets, the lane env vars and the `Smoke`-only UI selection.

## 9. Verify, then commit

```bash
scripts/check.sh                       # the real gate: format, lint, iOS, watchOS
grep -c PBXFileSystemSynchronizedRootGroup Ledger.xcodeproj/project.pbxproj   # expect 6
grep -c "PBXFileReference.*sourcecode.swift" Ledger.xcodeproj/project.pbxproj # expect 0
git status --short                     # nothing under Ledger/ or LedgerWatch/ at the root
```

`SWIFT_DEFAULT_ACTOR_ISOLATION` is confirmed as a real 26.6 key (the 26.6
templates write it; values `nonisolated` | `MainActor`). Build Settings ▸
Levels ▸ "Default Actor Isolation" must read **MainActor** on `Ledger` and
`LedgerWatch` (from their own xcconfigs) and **nonisolated** on the four test
targets. Same check for "Swift Language Version": `6.0` from
`Config/Base.xcconfig`, with every target column empty.

Commit the project on its own:

```bash
git add Ledger.xcodeproj
git commit -m "chore(project): create Xcode project"
```

Agents never edit `project.pbxproj` after this.
