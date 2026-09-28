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
  only). Tick **Automatically delete head branches**. *Verified:* all three merge types are on today.

## 2. Apple prerequisites

- [ ] **Identifiers** (developer.apple.com): explicit App IDs `com.petearevalo.Ledger` and
  `com.petearevalo.Ledger.watchkitapp`, both with HealthKit. Xcode Cloud needs the watch one registered by hand.
- [ ] **App record** (App Store Connect ▸ Apps ▸ + ▸ New App): iOS, bundle ID `com.petearevalo.Ledger`,
  SKU `ledger-ios`, English (U.S.). Names are unique store-wide, so use a placeholder until F31.
- [ ] **TestFlight groups:** an internal group **Ledger Team** (add yourself) and an external group **Beta**.
- [ ] **Export compliance:** each build waits at *Missing Compliance* until you answer *None of the
  algorithms mentioned above*. Adding `ITSAppUsesNonExemptEncryption = NO` stops the question; ask the orchestrator for that one-line change.

## 3. Connect Xcode Cloud (Xcode 26.6, once F01 is on `main`)

- [ ] Open `Ledger.xcodeproj` on an up-to-date `main`. Go to Report navigator ▸ **Cloud ▸ Get Started**
  and choose product **Ledger**; the watch app is embedded. Install the **Xcode Cloud** GitHub App
  on only `peteyRevs/weight-lifting-app`. The package dependencies are public.

## 4. Workflow "Beta": `main` → TestFlight internal

| Section | Setting |
|---|---|
| Environment | Xcode **26.6**, not *Latest Release* (F32 moves it). Clean: off |
| Start condition | **Branch Changes** ▸ Custom Branches ▸ `main`, and nothing else |
| Actions | **Archive** ▸ iOS ▸ `Ledger` ▸ Deployment Preparation **TestFlight (Internal Testing Only)**. No Build or Test action; GitHub Actions tests |
| Post-actions | **TestFlight Internal Testing** ▸ *Ledger Team* |

- [ ] Screenshot: `xcode-cloud-beta.png`.

## 5. Workflow "Release": tag `v*` → TestFlight external and App Store

| Section | Setting |
|---|---|
| Environment | Xcode **26.6**. **Clean: on**, because Apple requires a clean build for external TestFlight |
| Start condition | **Tag Changes** ▸ Custom Tags ▸ `v` ▸ **Tags beginning with v**. Also add **Manual Start**, as a fallback |
| Actions | **Archive** ▸ iOS ▸ `Ledger` ▸ Deployment Preparation **TestFlight and App Store** |
| Post-actions | **TestFlight External Testing** ▸ *Beta* |

No post-action submits for App Review. Submit the uploaded build in App Store
Connect with **Manually release this version**. The first external build also
waits for Beta App Review (about 1–2 days).

- [ ] Screenshot: `xcode-cloud-release.png`.

## 6. Criteria 7 and 9

- [ ] **7:** merge any PR to `main`. In the "Beta" log, `ci_post_clone.sh` prints
  `CURRENT_PROJECT_VERSION = N`, where N is the Xcode Cloud build number. TestFlight should show
  **0.1.0 (N)** with the same N. Install it on the iPhone; the watch app comes with it.
  Screenshot: `testflight-beta.png`.
- [ ] **9:** run `scripts/check.sh` on release-please's release PR (CI does not run on it),
  then merge it (criterion 8). The run on that merge tags `v0.2.0`.
  "Release" should start through the Xcode Cloud GitHub App; the `GITHUB_TOKEN` tag still sends
  the webhook. If it doesn't start, use Manual Start and tell the orchestrator.
  Screenshot: `xcode-cloud-release-run.png`.
