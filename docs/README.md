# Ledger — Engineering plan index

Start here. Read top to bottom the first time; afterwards jump to what you need.

| Document | What it answers |
|---|---|
| [`product-spec.md`](product-spec.md) | What the app is, screen by screen, extracted from the Claude Design prototypes in `design/prototype/`. |
| [`product-decisions.md`](product-decisions.md) | The 20 product questions the prototypes left open, with assumed defaults to confirm. |
| [`architecture.md`](architecture.md) | Stack, repository layout, module map, domain model, workout engine, persistence, sync, HealthKit, design system, budgets. |
| [`engineering-standards.md`](engineering-standards.md) | The rules every agent and human follows; Definition of Done. |
| [`testing-strategy.md`](testing-strategy.md) | Test pyramid, per-layer approach, determinism, coverage gates, device protocol, `check.sh` contract. |
| [`ci-cd.md`](ci-cd.md) | GitHub Actions gates, Xcode Cloud delivery, release-please, branch protection, costs. |
| [`subagent-workflow.md`](subagent-workflow.md) | Implement → adversarial test → review → CI → human merge pipeline; prompt templates. |
| [`adr/`](adr/) | Why: native Swift (001), GRDB (002), committed project (003), event-sourced engine (004), sync channels (005), CI split (006). |
| [`research/`](research/) | Dated evidence (2026-09-16) behind the decisions: Apple platform (R1), data layer (R2), tooling/CI (R3). |
| [`../tasks/todo.md`](../tasks/todo.md) | Milestones M0–M5, feature IDs, dependencies, risk register, review log. |
| [`../tasks/features/`](../tasks/features/) | One brief per feature (F00–F32); the contract each subagent implements against. |

Conventions: decisions are recorded as ADRs before code depends on them;
research files are snapshots and carry their date; briefs are the only
authority for scope during implementation.
