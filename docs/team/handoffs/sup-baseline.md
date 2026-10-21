# sup-baseline handoff (measure-engineer, round 2)

Branch `worktree-wf_f3ac4663-d82-1`; state = the commit that adds this file (`git log -1 -- docs/team/handoffs/sup-baseline.md`).

## Done (stage 0 of the daemon design: logs, sampler, verdict, smoke-sample note)
- Lean `Fw.Obs.Health.Res` (lean/Fw/Obs/Health.lean, end of file): the classifier is by identity, not name: `kindTable` name -> `Role`, first argument
  (`lake serve` = leanServe, else leanBuild), ancestry (`launchd_sim` of a booted `fw-*` device = simulator subtree; Safari only under `safaridriver`),
  device names from `device.plist`. 10 kinds; heavy = leanBuild, chromium, simulator, webkit. CoreSimulatorService, system WebKit helpers, a user's Safari
  are not heavy. Theorems: `verdict_rank_mono`, `quiet_with_background`, `busy_with_one_heavy`, `background_procs_not_heavy`, `simulator_of_sim_root`, role lemmas.
  Golden: packages/contracts/golden/obs/sup-health.jsonl (ops sup.kinds/table/classify/sample/tripped/verdict) from lean/scripts/SupHealthGolden.lean.
  `Params` are first guesses; `swapPct` is on dynamic swap and flagged for revision.
- Footprint = top MEM (phys_footprint, includes compressed; xnu task.c:1226-1233@f6217f8); per-kind rows only, no total (shared pages).
- Sampler (watch-collect.ts `sampleOnce`): `ps -A pid,ppid,comm`, args only for lake/lean/launchd_sim (not stored), `plutil` for the device name, no CoreSimulator call.
- Lock events: heavy-lock.mjs, lake-slot-lib.sh, sim-lock.sh. `lake_slot` keeps `exec` and logs the acquire only (`"exec":1`); the hold is not
  derived from the next acquire (idle time). The group form logs both lines.
- Note: research/notes/2026/10-2x-sup-baseline.md is GENERATED (`node apps/runner/src/sup-report.ts --dir <console dir> --out <note> [--check]`) and is a SMOKE SAMPLE.
  It has a pressure-cause table and a design section 5 mapping table (15 rows; the uncollected ones say why).

## Verified
See the report: check.sh, apps/runner `pnpm test` (tsc), scripts node tests, land-inputs test, `fw land --dry`.

## Open (next steps)
- RESTART the watch process on the landed code (post-land routine): the sampler starts only then; collection of the first day begins at that restart.
- First-day tables are a follow-up: re-run the generator on the real `.fw-console` after a day, then revise `Params` and `swapPct` in Lean (golden regenerates).
- Stage-0 replay of 3.5 days of logs, fwcore starts, op latency, hook footprint, watch re-arm, boot time: not collected (section 5 table).
- mac-safari-measure: a Safari counts only under a `safaridriver` ancestor; macOS WebKit helpers have ppid 1 and are `system` unless under such a Safari.
  Extend the Lean rule (and golden) if that lane starts Safari another way. The old claim that it can reuse classify unchanged is superseded.
- TS stand-ins: classifier and verdict mirror (golden-checked), note generator (sup-report.ts).

## Conventions
Raw files stay under `.fw-console/` (gitignored); events are reduced rows. Never hand-edit the golden or the note. Read first: the note, then Health.lean `Res`.
