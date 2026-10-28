branch: worktree-wf_066a7844-684-1 (CI branch ci/geom-prewarm)
worktree: .claude/worktrees/wf_066a7844-684-1 (under the main checkout)
last commit: see `git log -1`
CI runs: push 1 (4db117d42): wktr 40636360090 success, lean 40636359994 success, breakpoint-gate 40636360067 (see below); push 2: pending

Push 1 result (wktr, pref OFF, phone width 402): the held set was NOT used. j1 arm all: prewarmed 19 tracks (not 55), createdOnPush 55; arm all-again: prewarmed 55, createdOnPush 55. Cause candidates (fixed in push 2, traced): set built before the images exist (19 nav tracks), and innerHeight differing between warm and push (fresh() false). Push 2 adds: ready() (images exist), fresh() (vp and image count), warm() rebuilds a stale held set, resize cools now and rebuilds after 250 ms, trace hook `__fwPrewarmTrace` (events build/fast/stale-push/stale-warm/resize/create/not-ready) in the probe output `trace`.

State
- Lean `lean/Fw/Parts/MorphGeomPrewarm.lean` (refStep vs newStep, same_look, held_push_no_create, ...), golden morph-geom-prewarm.jsonl (11 scenarios), check.sh job, Trigger row, triggers.jsonl regenerated.
- TS `apps/site/src/parts/morph.tween/geom-timed.driver.ts` warm/cool/resize; `driver.ts` calls warm when near and idle at 0; `morph.geom/index.tsx` env (ready, fresh, later, trace).
- Probe `packages/measure-wktr/src/mid-page.mjs` adopts held tracks; wktr.yml token `[accel-prewarm]` runs modes mid,mid-thr-off arms all,all-again.
- part-footprint.mjs emits maxRecDepth for `accesses` (list grew past the elaboration depth).
Open: push 2 numbers, gate flip cell/verify, look report, note research/notes/2026/10-2x-geom-prewarm.md, ledger, dry land, review ready.
TS stand-ins: when the tween driver calls warm/cool (no Lean golden of the call sites); resize debounce.
