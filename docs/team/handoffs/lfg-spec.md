# lfg-spec handoff

**State:** branch `worktree-wf_a5c6e36f-9fd-1`, see `git log` (tip: this note). `sh lean/scripts/check.sh` green
(mathview, props-lint, goldens). Not wired into land (that is `lfg-land-wire`).

**What exists**
- `lean/Fw/Ops/LeanFirst.lean`: Facts, rules, `enforced` stage table, `reasons`, `judge`/`gate`, `out` (lines, exit
  0/1/75), `run`, `emptyFacts`, about 25 `#guard`s. `stage` constant = `.shadow`.
- `lean/Fw/Ops/LeanFirstProps.lean`: spec vocabulary (`PassSpec`, `PropsOk` … `RatchetOk`) and 22 properties (the
  15 theorems of note section 7 plus PassIff, UnregisteredPremise, MissingFactPending/PendingExit split,
  ShadowPasses, NoNewline, OneVerdict/ExitZeroIff split).
- `lean/Fw/Ops/LeanFirstProofs.lean`: the 22 `<P>_impl` proofs, standard axioms only.
- `lean/Fw/Ops/LeanFirstSearch.lean`: `Enum Facts` (fault grid of 1226 facts: base, 35 single faults, all ordered
  pairs), `q<P>` checks with `q<P>_iff` exactness, bounded search guards.
- `lean/FwTest/Mutants/LeanFirst/{Gate,Out,Parts,Wire}.lean`: 22 tier-K kills `<P>_rejects_<mutant>` via
  `refutes_of_search … (by decide +kernel)`; codec round trip over the grid; op reply = `out` over stages × faults.
- `lean/Fw/Ops/Wire.lean`: op `ops.leanFirst` (decoder `lfFactsOf`, encoder `lfFactsJson`, optional `stage`).
- `lean/Fw/Ops/Golden.lean` + `packages/contracts/golden/ops/lean-first.jsonl` (52 cases, Lean-generated:
  `cd lean && lake env lean --run scripts/OpsGolden.lean`; `--check` for staleness).

**Conventions:** lfg-props-shape: properties over the signature first, kills in kernel, no registry rows (no ledger
incident yet). Every docstring has `$$` math with all fields written as `F.field` (no free abbreviations).

**Open items**
- `lfg-land-wire`: call `ops.leanFirst` from land with real fact sources (mathview export, kills list, TS lint);
  missing sources must be sent as `present.* = false` (gives pending, exit 75 when a rule is enforced).
- Stage stays `shadow` until the lead raises it (the request may override it with `"stage"`).
- The 6-item docstring checker was not run by a `checker` helper (no spawn tool in this session); self-reviewed.

**Read first:** note section 7 (`research/notes/2026/10-18-lean-first-gate.md`), then `LeanFirstProps.lean`.
