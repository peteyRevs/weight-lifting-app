# F## — <Feature name>

| | |
|---|---|
| Milestone | M# |
| Status | proposed / ready / in-progress / in-review / done |
| Depends on | F##, F## |
| Branch | `feat/F##-<slug>` |
| Design refs | `design/prototype/<file>` → screen labels: `<label>`, `<label>` |
| Spec refs | `docs/product-spec.md` §<n>, §<n> |

## Goal
One paragraph: what the user can do after this ships that they could not before.

## User stories
- As a lifter, I can … so that …

## Scope
**In:** …
**Out (explicitly):** … (link the brief that covers it)

## Touches
Modules and files this feature creates or modifies. Anything outside this list
needs a note in implementation-notes.md.
- `LedgerKit/Sources/LedgerDomain/…`
- `LedgerKit/Sources/FeatureX/…`
- `LedgerKit/Tests/…`

## Domain changes
New/changed types, events, repository protocol methods, migrations. Be exact —
this is the contract other features build on.

## Acceptance criteria
Numbered, testable, Given/When/Then. Each one maps to at least one test or a
screenshot in the PR.
1. Given … when … then …
2. …

## Test plan
- Unit (LedgerDomainTests): `test_…`, `test_…`
- Integration (LedgerPersistenceTests): …
- Snapshot (FeatureXTests): `<View>` × {light, dark} × {default, XL type}
- UI (LedgerUITests): flow `…` (only if in the critical-path list)

## Non-functional
- Performance budget: …
- Accessibility: …
- Offline behaviour: …

## Risks / unknowns
- …

## Definition of Done
Inherits `docs/engineering-standards.md` §12, plus:
- [ ] …

---
_Filled in by agents during delivery:_
- `F##-<slug>/implementation-notes.md`
- `F##-<slug>/test-findings.md`
- `F##-<slug>/review.md`
