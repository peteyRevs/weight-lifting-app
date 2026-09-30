# Ledger — Subagent Delivery Workflow

Goal: no bad code reaches `main`, and therefore never reaches TestFlight or the
App Store. Every feature passes through independent implement → test → review
stages run by *separate* agents with *separate* context, then CI, then a human
merge. No single agent both writes and approves its own code.

```
 Orchestrator            Implementer         Adversarial Tester        Reviewer          CI        Human
 (main session)          (worktree A)        (worktree A, fresh ctx)   (fresh ctx)
 ─────────────           ───────────         ─────────────────────     ────────          ──        ─────
 pick feature brief ──▶  implement + tests
                         run scripts/check.sh
                         write impl notes  ──▶  write tests from brief
                                               ONLY (not from impl)
                                               run; report failures ─┐
                         fix ◀────────────────────────────────────────┘
                         (loop until green) ──────────────────────▶  review diff vs brief
                                                                     + standards
                         fix blocking ◀──────────────────────────────┘
 verify DoD, run app,
 open PR ───────────────────────────────────────────────────────────────────────▶ checks ─▶ merge
                                                                                            │
                                                                                   main ─▶ TestFlight
```

---

## Roles

### Orchestrator (the main Claude Code session)

- Owns `tasks/todo.md`, picks the next feature whose dependencies are done.
- Prepares or refreshes the feature brief `tasks/features/F##-name.md`.
- Spawns agents with the prompts below. Never implements features itself in the
  main context (keeps context clean for coordination).
- Reads only agent *summaries* and the files they write; never full transcripts.
- Runs final verification (`scripts/check.sh`, launches the simulator and
  compares against the design), opens the PR with `gh pr create`.
- Reports to the user: what shipped, what was left out, and why.

### Implementer

- Runs in an isolated git worktree on branch `feat/F##-name`.
- Reads, in order: `docs/engineering-standards.md`, `docs/architecture.md`,
  the feature brief, the relevant sections of `docs/product-spec.md`, and the
  design prototype file for the screen.
- Implements product code **and** the tests listed in the brief's test plan.
- Iterates until `scripts/check.sh` is green.
- Writes `tasks/features/F##-name/implementation-notes.md`: decisions,
  deviations from the brief (with reasons), known limitations, how to verify
  manually.
- Returns a ≤ 200-word summary. Does not open the PR.

### Adversarial Tester

- Fresh agent, same worktree, **does not read** the implementation notes or
  the implementer's tests first. Reads the brief, the product spec, and the
  public interfaces of the new code.
- Writes additional tests that attack each acceptance criterion and the edge
  cases the brief lists (and ones it finds). Property-style tests for domain
  logic (idempotence, commutativity of sync events, bounds).
- Runs the suite. Any failure is written to
  `tasks/features/F##-name/test-findings.md` with a minimal repro and returned
  to the orchestrator, who sends it back to the implementer.
- Keeps its tests in the branch; they become permanent regression tests.

### Reviewer

- Fresh agent. Reads the diff (`git diff main...HEAD`), the brief, and the
  standards. Uses the `/code-review` skill at effort `high` for a bug pass, then
  checks explicitly:
  1. Module boundary violations (imports).
  2. Concurrency: isolation, Sendable, structured tasks, injected clock/UUID.
  3. Error handling: nothing swallowed, user-facing mapping.
  4. Design fidelity: tokens only; matches the prototype screen.
  5. Accessibility: labels, Dynamic Type, hit targets.
  6. Test quality: tests assert behaviour, not implementation; no sleeps; no flakiness vectors.
  7. Brief compliance: every acceptance criterion has a test or a screenshot.
- Writes `tasks/features/F##-name/review.md` with findings ranked
  **Blocking / Should fix / Nit**. Blocking findings go back to the implementer.
- Approves only when there are zero blocking findings.

---

## Gates

| Gate | Owner | Passes when |
|---|---|---|
| G0 Brief | Orchestrator + user | Brief has numbered acceptance criteria, test plan, and clear scope. User has seen the milestone plan. |
| G1 Local | Implementer | `scripts/check.sh` green; implementation notes written. |
| G2 Adversarial | Tester | Tester's tests green after fixes; findings file empty or all resolved. |
| G3 Review | Reviewer | Zero blocking findings. |
| G4 CI | GitHub Actions | Lint, iOS build and tests, coverage threshold, snapshot diff = 0. iOS only since 2026-09-30 (Pete; `docs/ci-cd.md`): the full local `check.sh` at G1 and G5 covers watchOS. |
| G5 Merge | Orchestrator (delegated by Pete, 2026-09-27) | G1–G4 green and zero Blocking findings → the orchestrator squash-merges with a conventional title and reports afterwards. It stops for Pete's review first when a PR carries a product/architecture decision or ADR, a waiver of a standard, anything touching signing, the App Store or releases, a pbxproj edit, or a finding it is unsure about. |
| G6 Release | Human | TestFlight build validated on device (phone + watch) via the release checklist before tagging. |

A gate cannot be skipped. If a gate fails three times on the same feature, the
orchestrator stops and re-plans (per CLAUDE.md: "if something goes sideways,
STOP and re-plan").

---

## Parallelism rules

- Features whose `Touches` sections (in the brief) are disjoint may run in
  parallel worktrees.
- Any feature that changes `LedgerDomain` public types or adds a migration is
  serialized: it merges before dependents start.
- `Package.swift` edits are allowed in parallel (small, mergeable) but the
  orchestrator rebases before opening each PR.
- Maximum 3 features in flight at once; more than that and review quality drops.

## Context hygiene

- One feature per agent. Never "while you're in there".
- Agents write results to files under `tasks/features/F##-name/`; the
  orchestrator reads files, not transcripts.
- Agents receive absolute paths to the exact docs they need, not "look around".
- Prompts state the branch, the worktree path, and the command that defines
  success (`scripts/check.sh`).

## Documentation lookups (MCP)

`.mcp.json` at the repo root gives every session and worktree agent the same
servers. Training data lags the SDKs, so agents look an API up before writing
code against it instead of relying on memory:

| Need | Server | Notes |
|---|---|---|
| Apple APIs, HIG, WWDC sessions | `sosumi` | Hosted; works without Xcode. First stop for SwiftUI, HealthKit, WatchConnectivity, ActivityKit, CloudKit. |
| GRDB, swift-dependencies, SQLiteData, snapshot-testing | `context7` | Query the version pinned in `Package.swift`. Optional `CONTEXT7_API_KEY` in the shell env raises rate limits; never commit it. |
| Build, run, screenshot on simulators (iOS + watch) | `XcodeBuildMCP` | For iteration and the orchestrator's design-fidelity check. **Not a gate**: `scripts/check.sh` is. |
| SwiftUI preview renders, live diagnostics | `xcode` | Needs Xcode running with the project open and Settings ▸ Intelligence ▸ Model Context Protocol ▸ "Allow external agents to use Xcode tools" on; Xcode asks to approve each new connection. Acts on the open project only, so main session only; worktree agents use XcodeBuildMCP. |

If a looked-up doc contradicts a brief or ADR, the agent records it in
implementation-notes.md and follows the brief; the orchestrator decides
whether the brief changes.

## Optional: deterministic orchestration

The implement → test → review pipeline maps directly onto the `Workflow` tool
(`pipeline()` of `agent()` calls). It is only used when the user explicitly
opts in (say "use a workflow" or "ultracode"). Default is the manual
orchestration above, which is easier to inspect feature by feature.

---

## Prompt templates

### Implementer

```
You are implementing feature F## "<name>" for Ledger, a native Swift/SwiftUI
iPhone + Apple Watch lifting log.

Worktree: <abs path>   Branch: feat/F##-<slug>
Read first, fully, in this order:
  1. <abs>/docs/engineering-standards.md   (rules; violations are rejected)
  2. <abs>/docs/architecture.md             (module map, patterns, data model)
  3. <abs>/tasks/features/F##-<slug>.md     (your brief; acceptance criteria are the contract)
  4. <abs>/docs/product-spec.md  sections: <list>
  5. <abs>/design/prototype/<file>          (screen labels: <list>)

Deliver: product code + every test in the brief's test plan, under the modules
named in "Touches". Look up Apple and third-party APIs via the sosumi / context7 MCP servers
before using them (docs/subagent-workflow.md, Documentation lookups).
Run <abs>/scripts/check.sh until green. Do not modify
files outside "Touches" without recording why in implementation-notes.md.
Write <abs>/tasks/features/F##-<slug>/implementation-notes.md.
Do NOT commit or open a PR. Return a ≤200-word summary: what you built, what
you deviated on, what you could not finish.
```

### Adversarial tester

```
You are the independent test engineer for feature F## "<name>". Do NOT read
implementation-notes.md or the existing tests before writing yours.
Read: the brief <path>, product-spec sections <list>, standards <path>.
Inspect only public interfaces: `grep -rn "public" <module paths>`.
Write tests in <test target> that try to break each acceptance criterion and
each edge case; add property-style tests for any reducer or pure function.
Run <abs>/scripts/check.sh. Record every failure in
<abs>/tasks/features/F##-<slug>/test-findings.md with a minimal repro.
Keep your tests in place. Return a ≤150-word summary and the pass/fail count.
```

### Reviewer

```
You are reviewing feature F## "<name>" before it may be merged.
Worktree: <abs path>. Diff: `git diff main...HEAD`.
Read the brief <path> and <abs>/docs/engineering-standards.md.
Run the /code-review skill at level high on the diff. Then check the seven
review points in docs/subagent-workflow.md. Write findings ranked
Blocking / Should fix / Nit to <abs>/tasks/features/F##-<slug>/review.md,
each with file:line and a concrete fix. Return a ≤150-word summary and the
count of blocking findings. Do not edit product code.
```
