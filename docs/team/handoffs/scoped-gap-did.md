# scoped-gap-did handoff

State: branch `worktree-wf_46bb397b-fab-1`, last commit in the report. No CI dispatch, no push, no new run.
Read first: `research/notes/2026/10-21-scoped-gap-did.md` (identification, pre-registration committed before any g, result).
Result: NOT SHOWN at 5 vs 5. Run-level permutation (252 labelings, one-sided scoped > faithful): count 124, p 0.492,
T = +0.0012 in ln g (scoped mean -0.0493, A/A mean -0.0506). Pooled run SD 0.181, MDE (80 % power, t method of the note)
0.314 in ln g (g x 1.37). No part-fix task is opened. Identification: 5 scoped (hash 8d213de6) and 5 faithful (hash =
base ede2c764) by `search` and `hash`, all 10 at headSha 82b10b3b.

Delivered
- `lean/Fw/Gate/RunPerm.lean`: `identify`, `balanced`, `runNano` (Float), exact-integer `count`/`verdict`, `mde`, 16 theorems.
- Golden `packages/contracts/golden/gate/run-perm.jsonl` (Lean output) and `run-perm-cells.jsonl` (parser output, input of Lean's real lines).
- `packages/gate-breakpoints/src/trajectory/closegap-did.mjs` (parser; TS stand-in of identify/runNano/count/verdict/mde) and its test.
- `sh lean/scripts/check.sh` green (init-cost lint needed `caseLines` as a function of Unit).

Writes outside the task's graph writes: `lean/Fw.lean` (import line, allowed), `lean/scripts/RunPermGolden.lean`,
`lean/scripts/check.sh` (one golden job), `lean/Fw/Ci/Trigger.lean` (two reads in the lean.yml row) and
`packages/contracts/golden/ci/triggers.jsonl` (regenerated with `lake test -- --write-ci-trigger-golden`).

Ledger row text (row `hero.exit.scoped.inline`, keys `next` and `missingWhy`; lead edits, not me)
- `next`, replace "Pending B (...)" with: "B (task scoped-gap-did) closed: not shown at 5 vs 5. Run-level permutation of 5 scoped and
  5 A/A fresh mac-webkit runs at 82b10b3b (39514533027, 39514585897, 39514619612, 39515982760, 39516056860 scoped;
  39514655614, 39514696773, 39514734504, 39516021307, 39516092834 A/A): p 0.492 (124 of 252), mean ln g difference
  +0.0012, minimum detectable effect 0.31 in ln g at 80 % power (run SD 0.18). The class-removal gap is not shown longer
  under the flag; a lengthening below about 37 % is not excluded. Note 10-21-scoped-gap-did; Lean Fw.Gate.RunPerm."
- `evidence`: append the ten run ids and the note. `missingWhy`: add "gap g under scoped not shown longer; effects below 0.31 in ln g not excluded (5 vs 5)".
- Perf question (B) of `10-21-scoped-close-start-cause` can be marked closed; C (earn rule) and A (close-start-identity-rule) are untouched.

Conventions: arms by `search`/`hash`, never run order; `trajectory-apple` artifact only; p counted on rounded 1e-9 integers (no float tie).
Open: none. A smaller-effect question needs a new pre-registration and a sample size from SD 0.181.
