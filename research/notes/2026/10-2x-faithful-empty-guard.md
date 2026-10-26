# faithful.verdict: no pass without evidence (task faithful-empty-guard)

Follow-up 2 of `10-2x-verdict-evidence-audit.md`. Before: `faithful.verdict` passed a request with `zones: []` (no
zone judged) and a zone with 0 frames and no cells in both arms (shape `0 = 0`, no cell to fail).

Status: CONFIRMED by the Lean theorems below (`lake build`, `lean/scripts/check.sh`) and by the golden diff: the
regenerated `faithful.verdict.jsonl` only gained lines 16-21; lines 1-15 are byte-identical.

## Rule

- A zone has **evidence** (`Fw.Faithful.evidence`) when it is present in both arms, has frames in both arms and lists
  at least one count type.
- A zone that passes without evidence is **undecided** (`zoneJudged`); a failing zone stays failed (an absent zone
  still fails, as before).
- Zones `zs` (`judged`): fail when one fails; else undecided when `zs` is empty or one zone is undecided; else pass.
- Wire (`verdictReply`): `pass` is true only for a judged pass; an undecided zone gets `pass: false` and
  `undecided: true`; an undecided request gets `undecided: "<reason>"` (`no zone to judge` or `no evidence: <ids>`) and
  its undecided zones are not in `failedZones`. Fields appear only when undecided, so complete-evidence replies keep
  their bytes.

## Theorems

| Claim | Lean |
|---|---|
| (a) no pass without evidence | `Zone.lean` `evidence_of_judged_pass`; wire: `Wire.lean` `evidence_of_reply_pass` |
| (b) complete evidence gives the old verdict | `Zone.lean` `judged_eq_unguarded`; wire: `Wire.lean` `verdictReply_eq_unguarded` (the reply equals the pre-guard reply `unguardedReply`) |
| branches | `judged_fail_iff`, `judged_nil`, `judged_undecided_of_zone`, `judged_pass_iff`; `zoneJudged_pass_iff`, `zoneJudged_fail_iff`, `zoneJudged_undecided_iff` |
| what has no evidence | `not_evidence_of_absent`, `not_evidence_of_frames_a`, `not_evidence_of_frames_r`, `not_evidence_of_no_types` |

## Golden rows (`packages/contracts/golden/faithful/faithful.verdict.jsonl` 16-21)

`zones: []`; no zones anywhere with `zones: []`; tail with 0 frames and no cells; tail with 0 frames and equal cells;
tail with frames and no types; a failing zone next to an empty zone (request fails, the empty zone is undecided).

## TS caller

`packages/measure-chromium/src/faithful.mjs`: `stateOf` prints `PASS`, `UNDECIDED (<reason>)` or `FAIL <zones>`;
`verdictRun` prints `UNDECIDED: <p>: <reason>` and exits 1, like `NO DATA`; `leanSource` refuses an undecided verdict
(its theorems state `zoneVerdict.pass`). `test/faithful.test.mjs` replays every golden through fwcore and checks the
printed state of the undecided rows. The committed `results/faithful/*.verdict.json` and `Measured.lean` are unchanged.

## Open

- `Fw.Parts.NavFixedCounts.armOf` partial-arm question (audit open 3): not in scope.
- No CI measurement: the guard changes no complete-evidence verdict.
