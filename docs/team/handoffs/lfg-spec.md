# lfg-spec handoff (round 2)

**State:** branch `worktree-wf_00095d9e-b76-1`, see `git log` (tip: this note). `sh lean/scripts/check.sh` run at the
tip. Not wired into land (that is `lfg-land-wire`). Threat model: never pass decision code without proved, reached,
killed properties; a false refuse or pending is acceptable.

**Round 2 (closed design from the lead)**
- Decision paths: allowlist `docs/**`, `research/**`, `.md` outside `lean/` (spec `Allowed`, `DecisionWrite` over
  `GlobCovers` in `LeanFirstProps.lean`). `isDecisionWrite_iff` (`LeanFirstDecision.lean`) proves the gate's prefix
  test equals `DecisionWrite`; `NoPropsRefuses` names a `DecisionWrite` write. Golden: `apps/runner/**` refuses.
- Binding by identity: `ThmFact.implArg`/`reachFromWire`; `Discharges` needs `implArg ≠ none`; `PropOk` needs the
  discharging theorem's own `reachFromWire = some true`; `RefusesUnreached` (stub case) proved and killed
  (`gAnyReached`). A candidate with `reachFromWire = null` gives pending `reach`.
- Stage: `ops.leanFirst` ignores a request `stage` (guards + golden rows); only `LeanFirst.stage` (`shadow`) counts,
  so every golden row is judged at shadow (pass with LEANFIRST lines).
- `exempt.tsv` and `killOf` read at main: `Facts.mainAt`/`exemptAt`; else pending `exempt-main` (spec `AllPresent`).

**Stated limits**
- `GlobCovers ⊇ PathCheck.matchesPath` is argued, not proved (`String.splitOn` does not reduce in the kernel).
- Paths are assumed normalized (no empty or `.` segments). A `.md` glob outside docs/research is decision code
  (it also covers the paths below it): a false refuse, the fail-closed side.
- The land glue must supply `mainAt`, `exemptAt`, `writes`, `implArg` and `reachFromWire` honestly.

**For the lead (research/ is outside my writes):** note §7 states two theorems stronger than proved:
item 1 `land_refuses_unproved` (proved: `unproved P ∈ refusals` only when rule 1 is enforced and `Present(F)`, not
`g F = refuse(unproved P)`), item 10 `missing_fact_not_pass` (proved as `MissingFactPending`: pending only when some
rule is enforced; at shadow it passes). §1(a) still lists `lean/Fw/**` path classes; replace with the allowlist.

**Helper gap:** no spawn tool in this session, so the 6-item docstring checklist was self-applied, not by `checker`.

**Read first:** `LeanFirstProps.lean` (spec), `LeanFirstDecision.lean`, then note §7.
