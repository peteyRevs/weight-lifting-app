# F12 — review

## Slice S1 — review (G3, 2026-10-21)

The orchestrator relayed this review to G1 in brief; it is recorded as given. Verdict: **not approved**.

**M1 (Major). `Apps/LedgerUITests/LibraryAuditAdversarial.swift`: the measurement test cannot fail on the defect,
and the exclusion is too wide.** The test only shows that some ink lies between the pill's strokes.
- **(a) No height floor.** Text clipped by the TextField's own bounds passes, and those bounds sit about 24 px
  inside the pill at 3×. A one-row sliver passes too. The ink has to span at least the expected glyph height, or be
  compared with an unclipped `Text` of the same string in `.ledgerFieldFont(.body)`, the way `FieldFontTests`
  measures "Gyp".
- **(b) No horizontal check.** In the XXXL picture the ink spans 312 pt and ends 4 pt inside the 16-pt trailing
  padding. On a 375 or 390 pt phone the field's inner width is about 306 pt or less, so the placeholder probably
  truncates there for real, in the Library and in F11's picker.
- **(c) No control.** Nothing shows the guards fail on a clipped or truncated placeholder.
- **The exclusion matches by label alone** (about line 109). The field's `accessibilityLabel` stays the placeholder
  while a query is typed (`SearchField.swift:33`), so a real clip of an edited query would be excluded too. It
  should match on element type `.textField` with an empty value.

**m1 (minor). `LibraryAuditAdversarial.swift:114`: the contrast exclusion is by frame alone.** It would also hide a
real contrast failure on a tab-bar item. It should exclude only elements that are not tab items, as Today's
precedent does. The comment at about line 89 has to match.

**m2 (minor). "New exercise" does nothing until S3.** This goes to Pete in the PR.

**m3 (minor). `FilterChipRow` and `SearchField` have no snapshot suite of their own.** Standards §11 and plan flag
A3 require one.

**m4 (minor). The "· Custom" wording in RECENTLY LOGGED** ("Barbell · Chest · 1 session · Custom") is G1's own.
This goes to Pete in the PR.

**n1 (nit). "PR 1 pounds".** A one-unit best is spoken with a plural unit. Recorded as a follow-up.

**n2 (nit). `GRDBStatsQueries+Library.swift:29` logs an exercise id as a `workout_exercise` row id.**

**n3 (nit).** Recorded as a follow-up, as the orchestrator ruled.

### Orchestrator's ruling (round 4)

- **Fix M1 (a), (b), (c), the exclusion's match, m1, m3 and n2.**
- **(b) is to be verified in a hosted LedgerDesign test** of `SearchField` at narrow widths and `.accessibility5`,
  through `TestSweep`.
  - If the placeholder truncates, the product falls back to a shorter placeholder when "Search N exercises" does
    not fit. Any new wording is flagged for Pete.
  - If it does not truncate, a trailing-column guard is added anyway.
- **n1 and n3** are follow-ups in the notes.
- **m2 and m4** are open questions for Pete in the PR.
