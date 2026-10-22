branch `worktree-wf_f4a6ed0e-0c6-1`, worktree `.claude/worktrees/wf_f4a6ed0e-0c6-1`, last commit see `git log -1`; no CI runs (local lane, named exception (c)).
**State (round 2):** Lean `Fw.Sup.Measure`: quiet ceiling = measured idle floor + margin (`ceilCenti`, `baselineFloor`, `simFloor`, `quiet_load_le`, `accepted_load_le_cap`) and the recorder bounds
(`probeAct`, `mayRecord`); golden `golden/sup/measure.jsonl` (55 rows) replayed by `safari-local-reduce.mjs`. Glue: `safari-local-run.mjs` (`takeBaseline`, cells, summary), `sim-local.mjs`
(`ensureDevice` reuses `fw-mac-safari-27`, never deletes), `safari-local.mjs`, `sim-local-cli.mjs` (`--base-wait-s`), `safari-local-lease.mjs` (sim slot), `xctrace/{guard,attempt,probe,parse}.mjs`.
**Result:** 0 accepted passes of 30 (round 1, old fixed ceiling 2.5 below this Mac's idle floor 3.2-4.3). Round 2 debug run (read-only, 156 s): baseline refused, a slot holder was live. No cadence verdict.
**Verified:** Lean builds; golden `--check`; `pnpm --filter @fw/measure-webkit test` (376 pass, incl. 12 guard tests); see the report for check.sh, ci-paths, land-inputs, dry land.
**xctrace safety:** `--time-limit`, own process group, TMPDIR in `<out>/.xctrace/work-<pid>`, wipe in `finally`, sim slot held while recording, dies with parent, 30 GB free gate, 12 GB trace cap.
**Run:** build the site, then `node packages/measure-webkit/src/sim-local-cli.mjs --site apps/site/dist/aot --engine safari|sim|both --out results/mac-safari/<engine>`; `--debug-ignore-quiet` is harness debugging only.
Re-reduce: `node packages/measure-webkit/src/sim-local-summary.mjs <dir> --write`. xctrace: `node packages/measure-webkit/src/xctrace/probe.mjs --site apps/site/dist/aot --target sim|mac|both --out <file>`.
**Slots:** macOS Safari and the macOS probe hold `measure` + `pass start|stop` per window (`holdMeasureSlot`); the Simulator keeps `sim` (the daemon shuts a booted device down 600 s after the last `sim` holder).
**Open:** a Simulator pass inside a measure window (daemon would treat `measure` as a device holder); ~58 GB of leaked `instruments*.ktrace` files
(Oct 22 22:22-22:47) still sit in the user temp folder: the lead decides on deleting them; the first real Simulator run creates the device once; rerun both engines in a measure window as a separate task;
zone-bounded hitch rows. `lean/scripts/check.sh` has one stage line ("sup-measure golden check") outside the task's file list.
**Read first:** `research/notes/2026/10-2x-mac-safari-measure.md`, then `lean/Fw/Sup/Measure.lean`.
