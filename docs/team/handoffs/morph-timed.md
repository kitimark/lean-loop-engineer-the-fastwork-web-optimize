branch: worktree-wf_aa7de68b-30e-1; worktree: .claude/worktrees/wf_aa7de68b-30e-1; CI branch ci/morph-timed at 7fe3e525e (pushes used 1 of 3); last work commit 80dc50d74
CI runs DONE: premise-tests 40454239481 success; gate 40454266249 success; chromium swipe-touch-v1 x3 base 40454388920, flag 40454426552:
 windows noGain in all windows (results/morph-timed/chromium-windows.md). webkit-sim base 40454309560 (r1 rerun) vs flag 40454356842: noGain all zones, equal counts (profile dispatches no wheel/touch: the timeline key check moved to morph-push-sim and phone-morph-push).
done: Lean spec + golden (MorphGeomTimed.lean, morph-geom-timed.jsonl); TS: morph.tween/geom-timed.{logic,driver,bus}.ts, driver.ts hook (env.timed, timers at Lean crossMs, no rAF),
 index.tsx (env.timed = timedBus.sink), part.json variant geom-timed (requires morph.geom:on); morph.geom/index.tsx owns the DOM env (timed geometry on the bus; skips its observer)
 = the one edit outside morph.tween; tests geom-timed.golden.test.ts (all 6 scenarios, 7 rebase, 12 cross) and geom-timed.driver.test.ts; premises anim.shared-start and anim.reversal-jump
 (pages, tests.mjs, Premise.lean, golden; CI 40454239481 success); ledger row n=93; footprint/contracts/premise/trigger goldens regenerated after merge.
open: WebKit Simulator timeline check (no morph style/layout/paint/rAF between push and end) moved to morph-push-sim and phone-morph-push (graph r534); look review (class L) by the user; faithful memory level undecided.
conventions: lake env lean --run does not rebuild imports: lake build Fw.Parts.FootprintData Fw.Parts.Contract before --rows. Ledger edits: scratchpad/morph-timed/ledger.py row.json.
read first: lean/Fw/Parts/MorphGeomTimed.lean statements; apps/site/src/parts/morph.tween/geom-timed.*.
