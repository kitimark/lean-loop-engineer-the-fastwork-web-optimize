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
