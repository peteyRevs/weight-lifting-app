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

Project ▸ Info ▸ Configurations:

| Level | Debug | Release |
|---|---|---|
| **Project** (`Ledger`) | `Config/Debug.xcconfig` | `Config/Release.xcconfig` |
| Target `Ledger` | `Config/Ledger.xcconfig` | `Config/Ledger.xcconfig` |
| Target `LedgerWatch` | `Config/LedgerWatch.xcconfig` | `Config/LedgerWatch.xcconfig` |
| Targets `LedgerTests`, `LedgerUITests`, `LedgerWatchTests`, `LedgerWatchUITests` | `Config/Tests.xcconfig` | `Config/Tests.xcconfig` |

Then, per target, Build Settings ▸ **Levels** and delete every setting still
shown in the target column (select the row, press Delete) so the value comes
from the xcconfig. The three exceptions that stay target-level, because they
differ per test target: `TEST_HOST`, `BUNDLE_LOADER`, `TEST_TARGET_NAME`.

## 5. Add the local package

File ▸ Add Package Dependencies… ▸ **Add Local…** ▸ `LedgerKit`.

Then per target ▸ General ▸ Frameworks, Libraries and Embedded Content:

- `Ledger` → `LedgerAppKit` **only**
- `LedgerWatch` → `LedgerWatchAppKit` **only**

## 6. Capabilities

- `Ledger` ▸ Signing & Capabilities ▸ + **HealthKit**
- `LedgerWatch` ▸ + **HealthKit**, + **Background Modes** ▸ ✅ Workout processing

If Xcode writes new `.entitlements` files, delete them: the xcconfigs already
point `CODE_SIGN_ENTITLEMENTS` at `Apps/Ledger/Ledger.entitlements` and
`Apps/LedgerWatch/LedgerWatch.entitlements`, which are committed. Same for
`Info.plist` — `INFOPLIST_FILE` already points at the committed ones and
`GENERATE_INFOPLIST_FILE` stays YES so Xcode merges its keys in.

## 7. Bundle the font

Drag `Resources/Fonts` into the navigator with **"Create folder references"**
(blue folder) and tick **both** `Ledger` and `LedgerWatch`. The bundle must end
up with `Fonts/Archivo[wdth,wght].ttf`, which is what `UIAppFonts` names in both
Info.plists.

## 8. Schemes and test plans

Product ▸ Scheme ▸ Manage Schemes: keep exactly `Ledger` and `LedgerWatch`,
delete any others, tick **Shared** on both.

Edit Scheme ▸ Test ▸ ▾ ▸ **Convert to use Test Plans…** ▸ *choose an existing
plan*, then add the rest with +:

| Scheme | Plans (default first) |
|---|---|
| `Ledger` | `TestPlans/PR.xctestplan`, `Nightly`, `Device` |
| `LedgerWatch` | `TestPlans/PR-Watch.xctestplan`, `Nightly-Watch`, `Device-Watch` |

The plans already carry coverage targets, the lane env vars and the
`Smoke`-only UI selection — don't re-edit them in the UI.

## 9. Verify, then commit

```bash
scripts/check.sh                       # the real gate: format, lint, iOS, watchOS
grep -c PBXFileSystemSynchronizedRootGroup Ledger.xcodeproj/project.pbxproj   # expect 6
grep -c "PBXFileReference.*sourcecode.swift" Ledger.xcodeproj/project.pbxproj # expect 0
git status --short                     # nothing under Ledger/ or LedgerWatch/ at the root
```

Also confirm the setting name that the brief flagged as unverified:
Build Settings ▸ search "Default Actor Isolation" on the `Ledger` target — it
must read **MainActor** and come from `Config/Base.xcconfig`. If the row does
not exist, the key `SWIFT_DEFAULT_ACTOR_ISOLATION` is wrong for 26.6; say so and
it moves to a per-target `OTHER_SWIFT_FLAGS = -default-isolation MainActor`.

Commit the project on its own:

```bash
git add Ledger.xcodeproj
git commit -m "chore(project): create Xcode project"
```

Agents never edit `project.pbxproj` after this.
