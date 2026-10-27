branch: worktree-wf_aa7de68b-30e-1; worktree: .claude/worktrees/wf_aa7de68b-30e-1; state: PARTIAL (Lean + golden done, no TS, no premises, no CI, no push)
CI runs: none (0 of 3 pushes used).
verified (local `lake env lean`, no sorry): lean/Fw/Parts/MorphGeomTimed.lean (about 700 lines) proves
- rebase_eval (cutL/cutR/pull for a push up, mirror for a push down), rebase_start, rebase_end
- timed_eq_ideal_set / timed_eq_ideal (any push sequence, run_in keeps state in [0,1]), reverse_continuous
- faithful_gap (<= 3 Delta/680 both signs, via ease_lip), solver_gap (reuses solver_exact, curveY_eq_ease, bezier_eq_ease)
- commit_eq (all bands, non-time Ks: last keyframe = f 1 = goalCss value; down push ends at f 0)
- crossMs / firstFrom_spec / crossMs_some (first whole ms with tween past c, up or down)
Generated: lean/Fw/Parts/MorphGeomTimedGen.lean, lean/scripts/MorphGeomTimedGolden.lean, packages/contracts/golden/morph-geom-timed.jsonl
(25 lines: scenario x6, rebase x7, cross x12); check.sh job added; Trigger.lean + triggers.jsonl + apps/runner/src/land.ts read rows added.
NOT run yet: sh lean/scripts/check.sh (via fw slot), node --test scripts/ci-paths.test.mjs, runner land-inputs test, plan lint, dry land.
open (design decisions already made, build next):
1. TS: apps/site/src/parts/morph.tween/geom-timed.logic.ts (rebase on tracks.ts offsets/values, mirror for close, golden test vs
   morph-geom-timed.jsonl), geom-timed.driver.ts, part.json variant "geom-timed" (requires morph.geom:on), index.tsx wiring.
   Hook: createTweenDriver.apply() (driver.ts ~l.200) replaces clock.subscribe(tick) when timed: set st.value = idealM at event time
   before moveStep/push, call timed.push(from,to,start): cancel live anims, one el.animate per track (duration 680, easing
   cubic-bezier(1/3,1,2/3,1), fill backwards, startTime = e), goal CSS as one root attribute rule, end timer -> publish final value
   once. Thresholds 0.001/0.2/0.4/0.55/0.72/0.92 and platform pointer cut 0.5225 via env clock.interval at crossMs (nav reads
   data-fw-morph through a MutationObserver). MorphGeom (morph.geom/index.tsx) must skip its own observer when morph.tween is geom-timed
   (a file outside the task writes; list it in open). Fallback to the faithful tween when morph.panel:rest, reduced motion, not on dark.
2. Time tracks (ks time, 60 Hz earn): only a push from rest up is exact (T = t, linear easing, keyframes trimmed at 680). Other
   pushes need keyframes sampled at the 60 Hz grid with Math.cbrt (TS stand-in; list it). Lean has no spec for it yet.
3. Premises (shared start across tracks, reversal jump) in packages/premise-tests + lean/Fw/Ops/Premise.lean; breakpoint gate with
   morph.geom:on,morph.tween:geom-timed; webkit-sim base vs flag; Chromium swipe-touch-v1 x3 (see task prompt for waiting rules).
4. Ledger row, research/notes/2026/10-2x-morph-timed.md, review ready report, dry land `VERDICT dry morph-timed`.
conventions: Lean file imports MorphGeomGen; Vp clash needs Fw.Parts.Nav.Vp; grind handles Rat division with nonzero facts.
read first: lean/Fw/Parts/MorphGeomTimed.lean (statements are the docstrings of rebase_eval, timed_eq_ideal, faithful_gap, commit_eq).
