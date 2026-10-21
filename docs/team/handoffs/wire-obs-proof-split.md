# wire-obs-proof-split handoff (lean-prover)

Branch `worktree-wf_36d7a05a-5ea-1`. Read `lean/Fw/Wire/Obs.lean`, section "Round trips", from `systemFields_keys` on.

## State
- `systemJson s` is now `Json.mkObj (systemFields s)` (same fields, same order, same JSON).
- `systemFields_keys` (keys pairwise distinct, `decide +kernel`) + `getObjVal_mkObj` give each field's value without
  evaluating the object; one private lemma per field (`systemOf_diskFreeGB`, ..., `systemOf_alivePids`), then
  `systemOf_systemJson` (statement unchanged) is one `simp only` over them plus `rfl`.
- No `maxHeartbeats` option left in `Fw.Wire.Obs` (was 16000000).

## Measured
- CI, lean.yml step `lake build` (same workflow, same rebuilt cone as main's last lean seed): before 14 m 58 s (run
  39586503888, review-feedback branch), after 1 m 19 s (run 39589493586, `ci/wire-obs-proof-split` at 614d3792; whole
  workflow pass). The review-feedback land leg's `fwcore build` was 14 m 24 s (land run 39586503981).
- Local, `lake env lean lean/Fw/Wire/Obs.lean` (debug, machine at load ~8): before 13 m 15 s wall (about 9 m 20 s CPU), after 7 s and 6 s.

## Verified
- `sh lean/scripts/check.sh` exit 0 (axiom check 0 failing, obs golden 99 cases); `node --test scripts/ci-paths.test.mjs`
  54/54; `apps/runner` `land-inputs.test.ts` 55/55; `pnpm -s fw land --dry` ends `VERDICT dry wire-obs-proof-split`.
- No `maxHeartbeats` in `lean/Fw/` outside `Fw.Spec.MathFacts` (a budget parameter there, not an option raise).

## Open (follow-ups)
- Other `rfl` round trips over a whole `Json.mkObj` in this file (`ciOf_ciJson` 7 keys, `reqOf_reqJson` field lookups,
  `ghOf_ghJson`) are fast today; they would want the same pattern if their objects grow.

## Conventions
- A new `System` field: add it to `systemFields` and `systemOf`, add one `systemOf_<field>` lemma (pattern:
  `unfold <reader> opt; rw [systemJson_get (by unfold systemFields; mem_lit)]; rfl`, arrays via `systemJson_arrD`), and
  name it in the `simp only` of `systemOf_systemJson`. Never prove a round trip by `rfl` over a whole `Json.mkObj`.
