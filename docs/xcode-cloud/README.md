# Xcode Cloud, branch protection, repository settings: Pete's checklist (F01)

The workflows, scripts and config are in the repo. Everything below needs the
repository owner or the Apple Developer account, so agents do not do it. Work
top to bottom. Save screenshots to `tasks/features/F01-ci-gates/` under the
names given. *Verified* means checked on 2026-09-27.

## 0. Decide first

- [ ] **GitHub plan.** Branch protection on a private repo owned by a personal account needs
  GitHub Pro. *Verified:* the API answers `403 Upgrade to GitHub Pro or make this repository public`.
  The options: **Pro** ($4/month, recommended), **make the repo public**, or no protection.
  Without protection, criterion 6 fails and the gates only advise.
- [ ] **Actions budget.** macOS minutes count 10×. Free includes 200 macOS minutes a month and
  Pro 300. One PR run is about 2 minutes of Lint plus 10–20 of Check. Past the included minutes,
  jobs stop unless Settings ▸ Billing ▸ Budgets allows Actions spend (`docs/ci-cd.md` §9).

## 1. Repository settings (github.com/peteyRevs/weight-lifting-app ▸ Settings)

- [ ] **Actions ▸ General ▸ Workflow permissions:** keep *Read repository contents*. Tick
  **Allow GitHub Actions to create and approve pull requests**, which release-please needs.
- [ ] **General ▸ Pull Requests:** untick *Allow merge commits* and *Allow rebase merging* (squash
  only). Tick **Automatically delete head branches**. *Verified:* all three merge types are on today.
- [ ] **Branches ▸ Add classic branch protection rule** for `main`:
  - **Require a pull request before merging**: on. *Required approvals*: **0**.
    *Require review from Code Owners*: **off** (see below).
  - **Require status checks to pass**: on, with *Require branches to be up to date*. Add
    **`Lint`** and **`Check (iOS + watchOS)`** (source: GitHub Actions). They appear only after
    `pr.yml` has run once, i.e. on the F01 PR.
  - **Require conversation resolution**, **Require linear history**, and
    **Do not allow bypassing the above settings**: all on, so the rule binds you too.
  - *Allow force pushes* and *Allow deletions*: off. Personal repos have no *Restrict who can
    push* and no merge queue; *up to date* does the queue's job.
  - Screenshot: `branch-protection.png`.

Why 0 approvals: `peteyRevs` opens and merges every PR, because the orchestrator
uses your login (*verified* for #1–#4). GitHub never lets an author approve their
own PR. A required approval would therefore need bypass, and bypass would also
skip the required checks. Review is gates G3/G5 (`docs/subagent-workflow.md`).
Switch to 1 approval plus Code Owners when a second maintainer joins.

## 2. Criterion 6: a direct push to `main` is rejected

```sh
git switch main && git pull --ff-only
git commit --allow-empty -m "chore: branch protection probe"
git push origin main            # expect: protected branch hook declined (GH006)
git reset --hard origin/main    # drop the probe commit
```
- [ ] Paste the rejection into the F01 PR.

## 3. Apple prerequisites

- [ ] **Identifiers** (developer.apple.com): explicit App IDs `com.petearevalo.Ledger` and
  `com.petearevalo.Ledger.watchkitapp`, both with HealthKit. Xcode Cloud needs the watch one registered by hand.
- [ ] **App record** (App Store Connect ▸ Apps ▸ + ▸ New App): iOS, bundle ID `com.petearevalo.Ledger`,
  SKU `ledger-ios`, English (U.S.). Names are unique store-wide, so use a placeholder until F31.
- [ ] **TestFlight groups:** an internal group **Ledger Team** (add yourself) and an external group **Beta**.
- [ ] **Export compliance:** each build waits at *Missing Compliance* until you answer *None of the
  algorithms mentioned above*. Adding `ITSAppUsesNonExemptEncryption = NO` stops the question; ask the orchestrator for that one-line change.

## 4. Connect Xcode Cloud (Xcode 26.6, once F01 is on `main`)

- [ ] Open `Ledger.xcodeproj` on an up-to-date `main`. Go to Report navigator ▸ **Cloud ▸ Get Started**
  and choose product **Ledger**; the watch app is embedded. Install the **Xcode Cloud** GitHub App
  on only `peteyRevs/weight-lifting-app`. The package dependencies are public.

## 5. Workflow "Beta": `main` → TestFlight internal

| Section | Setting |
|---|---|
| Environment | Xcode **26.6**, not *Latest Release* (F32 moves it). Clean: off |
| Start condition | **Branch Changes** ▸ Custom Branches ▸ `main`, and nothing else |
| Actions | **Archive** ▸ iOS ▸ `Ledger` ▸ Deployment Preparation **TestFlight (Internal Testing Only)**. No Build or Test action; GitHub Actions tests |
| Post-actions | **TestFlight Internal Testing** ▸ *Ledger Team* |

- [ ] Screenshot: `xcode-cloud-beta.png`.

## 6. Workflow "Release": tag `v*` → TestFlight external and App Store

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

## 7. Criteria 7 and 9

- [ ] **7:** merge any PR to `main`. In the "Beta" log, `ci_post_clone.sh` prints
  `CURRENT_PROJECT_VERSION = N`, where N is the Xcode Cloud build number. TestFlight should show
  **0.1.0 (N)** with the same N. Install it on the iPhone; the watch app comes with it.
  Screenshot: `testflight-beta.png`.
- [ ] **9:** merge release-please's release PR (criterion 8). The run on that merge tags `v0.2.0`.
  "Release" should start through the Xcode Cloud GitHub App; the `GITHUB_TOKEN` tag still sends
  the webhook. If it doesn't start, use Manual Start and tell the orchestrator.
  Screenshot: `xcode-cloud-release-run.png`.
