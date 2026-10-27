branch: worktree-wf_aa7de68b-30e-1; worktree: .claude/worktrees/wf_aa7de68b-30e-1; CI branch ci/morph-timed at 7fe3e525e (pushes used 1 of 3); last work commit 80dc50d74
CI runs (ids not yet read; dispatch nonces, outputs in scratchpad/morph-timed/*.out): push runs lean + premise-tests (wait: pnpm fw ci wait --branch ci/morph-timed);
 gate morph.geom:on,morph.tween:geom-timed both engines nonce ca25171b2714d8fd; webkit-sim base (morph.geom:on) 3 VMs nonce bd48867d939f6fd3, flag nonce 1488ea8ebc2d6119;
 chromium-counts swipe-touch-v1 x3 base nonce 992efba9d27bdd06, flag nonce cb13edbcc703d153 (all state running; the fw run processes wait and file results).
done: Lean spec + golden (MorphGeomTimed.lean, morph-geom-timed.jsonl); TS: morph.tween/geom-timed.{logic,driver,bus}.ts, driver.ts hook (env.timed, timers at Lean crossMs, no rAF),
 index.tsx (env.timed = timedBus.sink), part.json variant geom-timed (requires morph.geom:on); morph.geom/index.tsx owns the DOM env (timed geometry on the bus; skips its observer)
 = the one edit outside morph.tween; tests geom-timed.golden.test.ts (all 6 scenarios, 7 rebase, 12 cross) and geom-timed.driver.test.ts; premises anim.shared-start and anim.reversal-jump
 (pages, tests.mjs, Premise.lean, golden; local debug run held on both engines, CI result pending); ledger row n=93 (status pending fields); footprint/contracts/premise/trigger goldens regenerated after merge.
open: read CI results, fill ledger chromium/webkit/premises fields, note research/notes/2026/10-2x-morph-timed.md, final check.sh via slot, ci-paths test, land-inputs test, plan lint, dry land, review ready.
 WebKit Simulator timeline check (no morph style/layout/paint/rAF between push and end) needs the sim artifact; read it from the webkit flag run.
conventions: lake env lean --run does not rebuild imports: lake build Fw.Parts.FootprintData Fw.Parts.Contract before --rows. Ledger edits: scratchpad/morph-timed/ledger.py row.json.
read first: lean/Fw/Parts/MorphGeomTimed.lean statements; apps/site/src/parts/morph.tween/geom-timed.*.
