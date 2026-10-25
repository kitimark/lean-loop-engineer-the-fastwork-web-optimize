# resource-footprint handoff

- Branch `worktree-wf_d90774ee-051-1`, worktree `.claude/worktrees/wf_d90774ee-051-1`; last commit = `git log -1`
  (this handoff ships in it). Round 2 (review r1 findings). No CI runs dispatched, no phone use.
- Verified: Lean check suite, package tests, ci-paths, engine goldens `--check` and the dry land, run at the last commit.
- Round 2 verdicts: scene-pause Cr open / Wk win; idle-none open/open; panel:rest Wk open; logo-3d open/open; quiet Cr
  open. `becomesWin` = strip on WebKit; `leavesWin` = idle-none on both engines and panel:rest on WebKit (all open).
- Deviation from the r1 decision: the idle-none event sign is unknown, not same. animation-name none cancels and
  re-creates the tracks, so start and cancel events arise (cited in the note). Its paint, repaint and script are unknown.
- Bounds kept: strip layers 72, strip Wk GPU 2,287,000 bytes, panel Wk layers 1; `boundHolds` guards them against
  the check rows by unit and size. Every check row carries a `unit`.
- Open: results/phone/2026-10-25-end-counts has not landed (the golden's phone rows cite it by name).
- Follow-ups: derive repaint from `changePx`/`repaintPx` at DPR 3 (logo-3d, strip, panel:rest); count the idle-none and
  hidden-pause observer callbacks in script; read Chromium source for the remaining Chromium event signs; the extra
  WebKit layer at y=4500 under engine.events:quiet; panel-rest-n11 measures panel:rest.

## Files

- Lean: `lean/Fw/Engine/{Resource,ResourceVerdict,ResourceFlags}.lean` (model, verdict theorems, 18 footprints, checks).
- Golden `packages/contracts/golden/engine/resource.jsonl` (`lake env lean --run scripts/EngineGoldens.lean --write`),
  replayed by `packages/measure-webkit/test/resource-check.test.mjs`.

## Conventions

- A constant costing over 10k start allocations is a `(_ : Unit)` thunk (init-cost lint): `hiddenCr`, `hiddenWk`,
  `footprints`, `bounded`, `goldenRows`, `goldenText`.
- B is `budgetB` in Resource.lean; edit it, then regenerate the golden. Phone ranges are lo/hi only, raw passes local.

Read first: research/notes/2026/10-25-resource-footprint.md, then the `verdicts`, `becomesWin`, `leavesWin` and
`bounded` guards in ResourceFlags.lean.
