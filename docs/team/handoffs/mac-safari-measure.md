branch `worktree-wf_f4a6ed0e-0c6-1`, worktree `.claude/worktrees/wf_f4a6ed0e-0c6-1`, last commit see `git log -1`; no CI runs (local named exception (c) lane).
**State:** Lean `Fw.Sup.Measure` (quiet rule, judge, cadence stat, outcome, kept, hitchesRecorded) proved, golden `golden/sup/measure.jsonl` (38 rows)
replayed by `safari-local-reduce.mjs`. Glue: `safari-local-run.mjs` (arms, sampler reading, quiet wait, cells, summary), `safari-local-lease.mjs` (sim slot
hold), `sim-local.mjs` (Simulator engine), `safari-local.mjs` (safaridriver engine), `sim-local-cli.mjs` (runs either/both), `sim-local-summary.mjs` (re-reduce +
verdict table), `xctrace/probe.mjs` + `parse.mjs`.
**Result:** 0 accepted passes of 30 attempts (macOS Safari 20 in 40 min, Simulator 10): the Mac is shared and never quiet (load median 3.6 on macOS, 32 with the
Simulator booted; the booted Simulator alone drives load to 300-500 and memory under the floor). So no cadence verdict; the rule was not weakened. Files:
`results/mac-safari/{safari,sim}/{passes,summary.json,meta.json}`. xctrace: Animation Hitches refuses the Simulator ("Hitches is not supported on this platform");
macOS Safari records hitches only with `--attach <pid>` (8 of 21 recordings); `results/mac-safari/xctrace*.json`. Per-zone hitch counts not added (whole-recording rows, unstable).
**Run:** build the site (`pnpm --filter @fw/site build`), then from the worktree root `node packages/measure-webkit/src/sim-local-cli.mjs --site apps/site/dist/aot --engine safari|sim|both --out results/mac-safari/<engine>`
(`--wait-s` = longest wait for a quiet reading per pass). `--debug-ignore-quiet` is for harness debugging only (rows `debug`, never under `results/`).
Re-reduce: `node packages/measure-webkit/src/sim-local-summary.mjs <dir> --write`. xctrace: `node packages/measure-webkit/src/xctrace/probe.mjs --site apps/site/dist/aot --target sim|mac|both --out <file>`.
**Facts:** safaridriver needs no admin step; it exposes no Inspector protocol, so macOS Safari gives cadence only. The slot daemon has no `measure` kind: the lane holds a
`sim` slot and Lean's `holders` reason refuses a pass while another holder is live. `spawnSync` in the probe blocks the lease renew (use `leaseS` 900).
**Open:** rerun both engines in a booked quiet window (an own Mac or an idle one); a `measure` slot kind; a quiet rule that accounts for the Simulator's own services
(Lean thresholds change = Lean + goldens + twin together); zone-bounded hitch rows. `lean/scripts/check.sh` was edited (one stage line, outside the task's file list).
**Read first:** the note `research/notes/2026/10-2x-mac-safari-measure.md`, then `lean/Fw/Sup/Measure.lean`.
