# Handoff: engine-model-fix

State: branch `worktree-wf_a05f488a-b8f-1` (head: see `git log -1`; WIP of the stalled builder is commit 898c416).
CI: `ci/engine-model-fix` pushed at 898c416; engine-premises confirmation run 39106547260 (result in the note below).

Done
- Engine models fixed so every cell of run 39088367495 is predicted: `Fw.Ops.EnginePremise.cr_recorded_holds`,
  `wk_recorded_holds` (records `crRecorded`/`wkRecorded`, verified against that run's `premise-verdict` artifact).
- Chromium: `keyLevel` (layoutMove for top/left/margin @own; raster for scale/blur/toggle @own), level order = stage
  inclusion, `base = [props]`, hover hit test in `crWorkH`. WebKit: `filter` with outset change is Layout, `props` from
  `wkCompUpdate`.
- 7 refuted rules moved into `registry` (p24-p30, `refuted_registered`); 5 untested left.
- Parts restated with "Changed since CI run 39088367495" in each docstring (MorphPanelOpt, HeroExitOpt, PainNotes,
  PeopleCard, plus proof fixes in HeroCountdownOpt, MorphMountOpt, MorphTweenOpt).
- Goldens regenerated from Lean (engine/*.jsonl, ops/engine-premises.jsonl, ops/premise.jsonl); all match generators.
- Ledger: n=11 fade Chromium trade->no-win, n=11 rest WebKit trade->win; notes keyed (entry, engine-model-fix).

Read first: `research/notes/2026/10-18-engine-premises.md` section "Model fix" (changes, sign-change table).

Conventions: a restated theorem says "Changed since CI run 39088367495" and names the replaced theorem; engine goldens
are checked with a scratch script (no committed generator for `golden/engine/*`: each module has `goldenText`/
`goldenJsonl`; only chromium has `goldenRun`).

Open items
- No check.sh stage compares `golden/engine/*.jsonl` with Lean (drift is silent); add an EngineGolden script (check.sh
  is outside this task's writes).
- cr.props rests on one fixture order (script step after padding@own+idle); a second order would confirm the base rule.
- MorphPanelOpt rest variant: the WebKit run-level dominance is not one theorem yet (ledger missingWhy updated).
- The checker helper could not be spawned in this session (no agent tool); docstrings were self-reviewed.
