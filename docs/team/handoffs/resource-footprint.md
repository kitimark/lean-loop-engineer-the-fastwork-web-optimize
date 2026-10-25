# resource-footprint handoff

- Branch `worktree-wf_d90774ee-051-1`, worktree `.claude/worktrees/wf_d90774ee-051-1`; last commit = `git log -1`
  (this handoff ships in it). No CI runs dispatched.
- Verified: Lean check suite green; measure-webkit 718/718, runner land-inputs 73/73, ci-paths 56/56; engine goldens
  `--check`; `VERDICT dry resource-footprint`; review ready returned `review`.
- Open: results/phone/2026-10-25-end-counts has not landed (the golden's phone rows cite it by name).
- Open: three writes outside the task list, each needing `--allow` on land: `lean/scripts/EngineGoldens.lean`
  (generator row), `lean/Fw/Ops/Premise.lean` (cite-lint `engineFiles`), `apps/runner/src/land.ts` (declared read).
- Open gaps: the extra WebKit layer at y=4500 under engine.events:quiet; no Chromium GPU peak for nav:logo-3d and
  morph.countdown:strip (both open); the Chromium events:quiet script sign.

## Files

| file | contents |
|---|---|
| `lean/Fw/Engine/Resource.lean` | resources, signs, repaint (CSS px² × DPR² × frames), GPU bytes, B, measured-sign check |
| `lean/Fw/Engine/ResourceVerdict.lean` | the verdict and its theorems (`trade_iff`, `win_iff`, `memory_only_not_trade`) |
| `lean/Fw/Engine/ResourceFlags.lean` | 18 footprints, observations, mechanisms, ledger comparison, golden rows |
| `packages/contracts/golden/engine/resource.jsonl` | golden from `lake env lean --run scripts/EngineGoldens.lean --write` |
| `packages/measure-webkit/{src,test}/resource-check*` | TS mirror and the test that replays the golden |

## Conventions

- A constant costing over 10k start allocations is a `(_ : Unit)` thunk (init-cost lint): `hiddenCr`, `hiddenWk`,
  `footprints`, `goldenRows`, `goldenText`.
- B is `budgetB` in Resource.lean; edit it, then regenerate the golden. Phone ranges are lo/hi only, raw passes local.

Read first: research/notes/2026/10-25-resource-footprint.md, then 10-25-webkit-ios-gpu-memory.md, then the
`verdicts`, `becomesWin`, `leavesWin` guards in ResourceFlags.lean.
