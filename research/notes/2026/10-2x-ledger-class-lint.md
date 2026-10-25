# ledger-class-lint: the ledger's structured visClass against part.json

Task `ledger-class-lint` (incident 2026-10-25: `toolbar-proof-morph` was refused twice because a flag moved to look
change L in `part.json` kept E prose in the ledger).

## Check (Lean)

- `research/findings/ledger.json` rows carry an optional `visClass` (E, E-s, Q or L), read by `Fw.Preset.Gen.parseRow`.
- `Fw.Preset.Gen.classDisagreements reg ledger` looks at every registered variant with a `part.json` `visClass`. It
  names the variant when no ledger row has its `flag`, when two or more rows do, or when the single row's
  `visClass` differs. `Fw.Preset.Gen.run` throws on any such variant, so `lean/scripts/check.sh` (job
  "preset v2-proved check") fails.
- Theorem `classDisagreements_eq_nil_iff`: the check passes iff every classed flag has exactly one row with that flag
  and an equal `visClass` (`ClassAgrees`). Each branch has its own theorem: `classIssue_of_noRow`,
  `classIssue_of_rowCount`, `classIssue_of_differs`, `classIssue_of_unclassed`, plus `mem_classDisagreements`.
- `#guard` cases cover agree, unclassed, no row, wrong class, missing field, two rows, a mixed registry, and
  `parseRow` reading, omitting and rejecting `visClass`.
- The check compares one field against one source. The prose fields (`visual`, `missingWhy`, `next`) stay free text and
  are not linted.

## Backfill

There are 18 classed flags. 17 existing rows got `visClass` equal to `part.json`: n 9, 19, 39, 40, 47, 49, 50, 52,
67, 68, 69, 71, 73, 76, 77, 78, 79. Row n 80 `pain:dark-static` is new (L). It holds the measurements and proofs
that `pain-dark-followups` recorded under n 47 and in `10-2x-pain-dark-scroll.md` ("Arrangement tried").

## The four ambiguous rows (for the lead to confirm)

In each row, part.json and the row's own latest prose both say L. The E text in the prose is about a rest-state or
settled-frame check, and that check cannot see the change. No same-look run covers the frames mid-morph. Decision
for all four: L. part.json stays as it is.

| n | flag | evidence for L | the E/equal evidence and why it does not decide |
|---|---|---|---|
| 39 | nav:earn-no-transition | prose: "not equal mid-transition: an L-class look change, accepted by the user 2026-10-21"; strips CI run 39473950464; Lean `NavEarnOpt.faithful_lags`; look-change.candidates.jsonl line 12 (userDecision kept) | "equal on settled frames" (`visSame_settled`) covers settled frames only |
| 49 | nav:bar-fixed | prose "Now CLASS L"; CI morph trajectory red on both engines, run 39887331854; Simulator mid-morph 1,012,655 changed px at m0.5 against a floor of 0; Lean `Footprint.barFixed_look`; candidates line 9 | "E: same-look breakpoint gate ... PASS run 39860402069" is rest state only (`rest_blind`, `cell_blind`) |
| 50 | nav:logo-3d | prose "Now CLASS L"; trajectory red on both engines, run 39887335005; 1,012,932 changed px at m0.5; Lean `Footprint.logo3d_look`; candidates line 13 | gate PASS run 39862686589 is rest state only |
| 52 | nav:clip-box | prose "Now CLASS L"; trajectory red on both engines, run 39887328839; 1,012,015 changed px at m0.5; Lean `Footprint.clipBox_look`; candidates line 10 | gate PASS run 39857031808 is rest state only |

## Accepted limits

- Prose fields are not linted, and no `status` field changed.
- A ledger row with a `visClass` whose flag has no `part.json` class is not checked. Every row that has one today
  matches a classed flag.
- The lead confirms the four decisions after review.
