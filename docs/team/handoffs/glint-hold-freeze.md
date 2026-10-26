branch: worktree-wf_8596d321-474-1; worktree: .claude/worktrees/wf_8596d321-474-1; code commit cf69a9052 (pushed to ci/glint-hold-freeze; push 2 of 2 used, main merged incl. wk-sim-hang)
runs (all at a5e170b94 unless noted): premise-tests 40345059212 success (webkit job re-run once after a 20 min setup-pnpm hang); breakpoint-gate 40345141093 success; chromium-counts base 40345261186, flag 40345253392 success.
webkit-sim at cf69a9052 (3 VMs each, ~1 h): base and flag dispatched in background by the builder; ids in note once filed. If this file still says waiting: run the two commands under dispatch below with --ref ci/glint-hold-freeze and read with packages/measure-webkit/src/offscreen-webkit-cli.mjs.
verified: look premise glint.hold-pixels class E (Chromium worst 1, WebKit 0, bound 12); gate pass both engines; Chromium windows approach/finish gain (RasterTask about 5 percent), end windows noGain. Found and fixed: ring ids with hyphens left the begin chain unresolved in both engines (now fwglint<side>X1S0). Backward seek into segment 0 after the first cycle wrong in Chromium (235), no flag path seeks backward.
open: WebKit z5000 verdict (n VMs); check.sh at the final commit; dry land.
---
branch: worktree-wf_8596d321-474-1; worktree: .claude/worktrees/wf_8596d321-474-1; CI branch ci/glint-hold-freeze (one push, lean lane only)
state: built and proved; waiting on lead dispatches (no gate, look, counts run exists yet) and on wk-sim-hang (not on main).
done: Lean PlatformGlintHold (no sorry) + golden (107 lines) replayed by apps/site/src/parts/platform.glint/hold.test.ts (sample, ticking, plan, const, pause/seek runs through createPause); TS twin logic.ts (fixed a float edge at elapsed 6000: segment index now from ms); flag platform.glint:hold-freeze (part.json, Visuals.tsx HoldRing + Dash hold prop, platform/index.tsx subs.glintHold); ledger row n=90; note research/notes/2026/10-2x-glint-hold-freeze.md (engine tick citations CONFIRMED with code shown); no new SMIL clock writer.
checks: check.sh green (exit 0); @fw/site, @fw/runner tests, ci-paths test pass; plan lint 0 errors.
files outside task writes: apps/site/src/parts/platform/index.tsx (subs mapping), lean/Fw/Parts/FootprintData.lean, packages/contracts/golden/parts/footprint.gen.json and footprint-diff.gen.json (generated), packages/contracts/golden/preset/v2-proved.decisions.jsonl (generated).
dispatch (lead), all --ref ci/glint-hold-freeze:
  pnpm -s fw run --gate --engines both --fw platform.glint:hold-freeze --ref ci/glint-hold-freeze
  look premise (class E, bound 12, both engines): pixels equal to the original over the glint cycle
  pnpm -s fw run --target rewrite --engines chromium --runs 3 --ref ci/glint-hold-freeze   (base)  and  same with --fw platform.glint:hold-freeze (flag), same commit, read with the Lean window reader
  WebKit z5000 (webkit-sim, 3 VMs) only after wk-sim-hang lands: pnpm -s fw run --target rewrite --engines webkit --ref ci/glint-hold-freeze --fw platform.glint:hold-freeze (and a base run)
open: INFERRED that each engine re-evaluates the begin chain after setCurrentTime and keeps one piece active per attribute (the look premise decides); the look-premise run needs a harness input the lead names.
conventions: golden text is a function (init-cost lint bound 10000); regenerate footprint goldens with apps/site/scripts/part-footprint.mjs --write.
