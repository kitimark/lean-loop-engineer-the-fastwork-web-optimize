# Handoff: hero-exit-anim-units

* Branch `worktree-wf_6b79182b-802-1`, worktree `.claude/worktrees/wf_6b79182b-802-1`.
* Last sha: see `git log -1` on the branch (the task's final commit).
* CI run ids: none (no CI in this task).
* Verified: `lake build` (all Fw), engine goldens rewritten by `scripts/EngineGoldens.lean --write`, preset rewritten
  by `Fw.Preset.Gen.run []`, check.sh via `fw slot run --kind check`.
* Open: the engines still count style per change and per compositor animation; per-element style units in
  `Fw.Engine` are a follow-up. The site test does not check `nameProp` against the CSS. `ResourceFlags.lean` and
  `golden/engine/resource.jsonl` were edited outside the graph row's writes (a guard broke).

## State

* `HeroExitOpt`: the animation list comes from `exitNames` through `nameProp` (`exitAnims`, `animCount_eq`: 2N + 5).
  `crAnims`, `wkAnims`, `wkTargets` map that list. New: `anim_comp`, `wk_style_elems`, `cr_lane_style_elems`,
  `mem_cardAnims_fst`.
* Changed statements: `wk_trade`, `wk_tradeE` gain `V.units .style = O.units .style`; `cr_lane_mixed` style
  `+ (N + 2)`, props `+ (N + 3)`; `crVar_eq` compAnims `2N + 4 − [¬ℓ]`; `wk_anim_comp` takes an `AnimProp`.
* `HeroExitWork`: `cr_style_saving`, `cr_lane_style_saving` and `wkEdgeChanges_eq` re-proved, statements unchanged.
* `Gen.lean`: `threadedRowNames` (resolved names), `#guard`s on the proved evidence text and on inline ledgers; the
  link check against the ledger file runs in `run` (no `include_str`: `research/` is outside the Lean cone).
* Ledger row n 6: new links, mechanism and lesson counts, one note (task hero-exit-anim-units). Decision: `enter`.

## Read first

* `research/notes/2026/10-2x-hero-exit-anim-units.md` (source citations, strict/equality table).
* `lean/Fw/Parts/HeroExitOpt.lean` section "The variant's animations, from its CSS names".
