# Xcode Cloud and repository settings: Pete's checklist (F01)

The workflows, scripts and config are in the repo. Everything below needs the
repository owner or the Apple Developer account, so agents do not do it. Work
top to bottom. Save screenshots to `tasks/features/F01-ci-gates/` under the
names given. *Verified* means checked on 2026-09-27.

Decided 2026-09-27: GitHub Free, **no branch protection**, and Actions within the
free minutes (`docs/ci-cd.md` §4). Criterion 6 (a direct push is rejected) is
therefore waived; the merge gate is the orchestrator's policy.

## 1. Repository settings (github.com/peteyRevs/weight-lifting-app ▸ Settings)

- [ ] **Billing ▸ Budgets (or Spending limits):** Actions at **$0**, so an exhausted month
  stops CI rather than charging. Free includes about 200 macOS minutes a month (macOS counts
  10×). A PR run is about 12–15 of them, and docs-only PRs use none.
- [ ] **Actions ▸ General ▸ Workflow permissions:** keep *Read repository contents*. Tick
  **Allow GitHub Actions to create and approve pull requests**, which release-please needs.
- [ ] **General ▸ Pull Requests:** untick *Allow merge commits* and *Allow rebase merging* (squash
  only; a merge commit would put branch commits on `main` for release-please). Tick **Automatically
  delete head branches**. *Verified:* all three merge types are on today.

## 2. Apple prerequisites

- [ ] **Identifiers** (developer.apple.com): explicit App IDs `com.petearevalo.Ledger` and
  `com.petearevalo.Ledger.watchkitapp`, both with HealthKit. Xcode Cloud needs the watch one registered by hand.
- [ ] **App record** (App Store Connect ▸ Apps ▸ + ▸ New App): iOS, bundle ID `com.petearevalo.Ledger`,
  SKU `ledger-ios`, English (U.S.). Names are unique store-wide, so use a placeholder until F31.
- [ ] **TestFlight groups:** an internal group **Ledger Team** (add yourself) and an external group **Beta**.
- [ ] **Export compliance:** each build waits at *Missing Compliance* until you answer *None of the
  algorithms mentioned above*. Adding `ITSAppUsesNonExemptEncryption = NO` stops the question; ask the orchestrator for that one-line change.

## 3. Connect Xcode Cloud (Xcode 27.0, once F01 is on `main`)

- [ ] Open `Ledger.xcodeproj` on an up-to-date `main`. Go to Report navigator ▸ **Cloud ▸ Get Started**
  and choose product **Ledger**; the watch app is embedded. Install the **Xcode Cloud** GitHub App
  on only `peteyRevs/weight-lifting-app`. The package dependencies are public.

## 4. Workflow "Beta": `main` → TestFlight internal

| Section | Setting |
|---|---|
| Environment | Xcode **27.0**, as `.xcode-version` pins it (F32), not *Latest Release*. Clean: off |
| Start condition | **Branch Changes** ▸ Custom Branches ▸ `main`, and nothing else |
| Actions | **Archive** ▸ iOS ▸ `Ledger` ▸ Deployment Preparation **TestFlight (Internal Testing Only)**. No Build or Test action; GitHub Actions tests |
| Post-actions | **TestFlight Internal Testing** ▸ *Ledger Team* |

- [ ] Screenshot: `xcode-cloud-beta.png`.

## 5. Workflow "Release": tag `v*` → TestFlight external and App Store

| Section | Setting |
|---|---|
| Environment | Xcode **27.0**. **Clean: on**, because Apple requires a clean build for external TestFlight |
| Start condition | **Tag Changes** ▸ Custom Tags ▸ `v` ▸ **Tags beginning with v**. Also add **Manual Start**, as a fallback |
| Actions | **Archive** ▸ iOS ▸ `Ledger` ▸ Deployment Preparation **TestFlight and App Store** |
| Post-actions | **TestFlight External Testing** ▸ *Beta* |

No post-action submits for App Review. Submit the uploaded build in App Store
Connect with **Manually release this version**. The first external build also
waits for Beta App Review (about 1–2 days).

- [ ] Screenshot: `xcode-cloud-release.png`.

## 6. Criteria 7 and 9, and F32's criterion 3

- [ ] **7:** merge any PR to `main`. In the "Beta" log, `ci_post_clone.sh` prints
  `CURRENT_PROJECT_VERSION = N`, where N is the Xcode Cloud build number. TestFlight should show
  **0.1.0 (N)** with the same N. Install it on the iPhone; the watch app comes with it.
  Screenshot: `testflight-beta.png`.
- [ ] **9:** run `scripts/check.sh` on release-please's release PR (CI does not run on it), then merge
  it (criterion 8). The run on that merge tags `v0.2.0`, and "Release" should start through the Xcode
  Cloud GitHub App (a `GITHUB_TOKEN` tag still sends the webhook). If it doesn't, use Manual Start
  and tell the orchestrator. Screenshot: `xcode-cloud-release-run.png`.
- [ ] **F32 criterion 3:** the "Beta" build from criterion 7, archived on Xcode 27.0, installs from
  TestFlight on the iPhone, and its watch app installs on a watchOS 26 watch and a watchOS 27 watch (the
  minimum stays watchOS 26). With one watch, tell the orchestrator which watchOS version you tried.
