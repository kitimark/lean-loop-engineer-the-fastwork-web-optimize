# Handoff: countdown-hidden-pause (O2)

State: branch `worktree-wf_176e2293-c7b-2`; Lean 7dd3aa7f, TS 9a1d2f87, docstring fixes 473e4f4c. CI branch
`ci/countdown-hidden-pause`; one breakpoint-gate dispatch (engines=chromium, parts=hero.countdown,
fw=hero.countdown:hidden-pause): run 39205809122. Its hero.countdown row passes in desk, desk-rm, touch and all 3 sweeps
(0 failing items, 0 unsettled). The merged verdict is `refused` (exit 1) only on coverage: 7 envs were not-run, and
the readings say "narrowed: false" with 6752 missing readings even though the run was narrowed. This may be a gate bug.
Verified:
- `lean/Fw/Parts/HeroCountdownHidden.lean` builds clean, axioms propext/Classical.choice/Quot.sound.
  Results: exit zone `exitOpacity_eq_zero_iff`, `exitZeroAt_iff` (y ≥ T + max(1, h−v)), `exitFrame_zero_iff`;
  `sentinel_not_hidden` (e = 1/25: pointerOff, not hidden); `hidden_iff`, `hidden_iff_exit`, `hidden_iff_far`;
  `hidden_scene_empty`; gate `first_visible_rewrites`, `gate_sync`; `visSame` (via `hiddenPause_visSame`);
  `hidden_work` (reuses `cr_countdown_style`, `wk_countdown_style`, `unhide_le`).
- The golden `packages/contracts/golden/parts/hero.countdown.hidden.jsonl` (13 zones) passes `--check`
  (`cd lean && lake env lean --run scripts/CountdownHiddenGolden.lean --check <file>`).
- Site typecheck and tests pass (5170), with `hidden.test.ts` run against the golden. `ci-paths` passes (32), and so does
  runner `land-inputs` (40). Footprint files were regenerated (`part-footprint.mjs --write`, ContractsGolden `--diff`).
TS: `apps/site/src/parts/hero.countdown/hidden.ts` (`installHiddenGate`: MO on the stage `--exit-opacity` plus IO on
the track with `rootMargin 100% 0px`, driving `createWriteGate`). Only the hero instance (`fwId === 'hero-countdown'`)
gets the gate; morph keeps its own gate. part.json variant `hidden-pause`, ledger `O2 countdown-hidden-pause`.
Open:
- No preset entry. The measured verdict comes from the wave-2 whole-page run.
- Accepted limit (in part.json): the IO callback is a posted task, so it arrives one frame late. A jump of more than
  1 vh toward the hero within one frame can paint the held faces for one frame (INFERRED).
- Finding outside this write set: a morph.countdown comment says its IO runs "before paint". IO is a posted task
  (intersection_observer_controller.cc:90-97@f842f52), so the comment is likely wrong.
- No checker subagent could be spawned (this run had no Agent tool). The 6-point docstring checklist was self-applied;
  a checker pass is still owed.
Read first: the Lean module §3 (decision) and §6 (visSame), then `hidden.ts`.
