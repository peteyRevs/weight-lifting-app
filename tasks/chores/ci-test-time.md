# PR CI in one try, in about 30 minutes (2026-10-20)

Branch `chore/ci-test-time`, cut from `origin/main` at `685314c`. Goal: a PR's `Check` run finishes on its
first try, in about 30 minutes, with no test coverage lost.

## Plan

- [ ] 1. Cold first run: verify the hypothesis (nothing saves a cache on `main`), then fix it.
- [ ] 2. Route the six suites added 2026-10-18/19 through `TestSweep`.
- [ ] 3. NameFieldLine: host once per (place, weight), not per case, if isolation allows.
- [ ] 4. Flake: `eventually(...)` waits on the condition with a bound in seconds, not a yield count.
- [ ] 5. `docs/ci-cd.md` and `pr.yml`'s comments: the cache story and the deadline re-derived.
- [ ] Verify: the six suites under `TEST_RUNNER_LEDGER_SWEEP=pr`, before and after; the full gate.

## 1. Cold first run

**Hypothesis confirmed.** `pr.yml` runs on `pull_request` and `workflow_dispatch` only, so no run ever saves
in `main`'s scope; GitHub lets a PR's run read its own ref's caches and its base branch's, nothing else.
`gh cache list` on 2026-10-20: every `compilation-…` and `spm-…` entry is on a `refs/pull/<n>/merge` ref (#57
to #66), none on `refs/heads/main`; 8.9 GB of the repository's 10 GB in use. The SwiftPM checkout cache has
the same gap, and worse: its key is the same on every PR (`spm-90b6e60…`), so each PR resolved packages cold
and saved its own 411 MB copy of an identical entry.

**Fix: the unmerged commit of 2026-10-17** (`646c66f`, branch `worktree-agent-a92dc1ccb90626738`,
`tasks/chores/2026-10-17-main-cache.md`), held back then only for its cost on paid minutes. The repository is
public now, so it is cherry-picked here: `.github/workflows/main-cache.yml` runs on each code push to `main`
and runs the new `scripts/check.sh --build-only` (step 0 and step 3's iOS `build-for-testing`, through the
same `test_platform` code, so every compile's arguments, and with them every cache entry's key, are Check's;
no boot, catalogs, tests or coverage). It saves the compilation cache under Check's key scheme and the package
checkouts under their exact key, both in `main`'s scope, after a green build only. A PR whose lockfiles match
`main`'s then hits the package cache exactly (and saves no copy of it), and its compilation restore-keys find
`main`'s newest entry.

Conflicts resolved against `main`: `ARCHS=arm64` (the arm64 chore, 2026-10-18) stays on the build's
arguments; check-wiring's `--build-only` cases are W77 and W78, since that chore took W76.
