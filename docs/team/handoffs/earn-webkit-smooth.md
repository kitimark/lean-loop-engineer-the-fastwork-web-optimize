# earn-webkit-smooth handoff
Branch: worktree-wf_bbd9b85f-6e4-1 (CI branch ci/earn-webkit-smooth). Worktree: .claude/worktrees/wf_bbd9b85f-6e4-1.
Last sha: see `git log -1`. Dispatches used: 2 of 3.
CI runs: 40100235090 trajectory-probe (push 1, fd711461f): FAILED, the flag arm opened '/' without its search (identity mismatch; fixed);
40100235131 lean (push 1): failure, footprint-diff.gen.json stale (fixed in 3247a6d76).
Push 2 (5d781cab7): trajectory-probe 40100783726, breakpoint-gate 40100783656 (default config; the variant gate is a lead dispatch, see open),
lean 40100783678: queued. Download: `gh run download <id> -n transitions-apple-1280`.

## What exists
- Variant `nav:earn-logical` (look-change class L, "engine parity"): `apps/site/src/parts/nav/` (index.tsx sets class `is-earn-logical`, nav.module.css
  last two rules list `padding-inline-start, padding-inline-end` in place of `padding-inline`, part.json, logic.ts constants).
- Lean `lean/Fw/Parts/NavEarnWebkit.lean` against Fw.Engine.TransitionStart: `variant_entry_webkit`, `variant_exit_webkit`, `variant_webkit_padding`,
  `variant_firstFrame`, `variant_chromium_set`, `variant_chromium_timing`, `variant_webkit_set_eq_chromium_faithful`, `hero_exit_chromium`, `hero_exit_webkit`.
- Golden `packages/contracts/golden/parts/nav.earn.webkit.jsonl` (generator `lean/scripts/NavEarnWebkitGolden.lean`, job in check.sh), replayed by
  `apps/site/src/parts/nav/earn.webkit.golden.test.ts`.
- Lane: `transitions.mjs` / `transitions-safari.mjs` gain `--search` (a `flag` arm), workflow passes it from the `[frames:...]` token.
- Ledger row n=67 `nav.earn.logicalPadding` (look-change, review pending). Note: research/notes/2026/10-2x-earn-webkit-smooth.md.

## Outside the task's writes (listed in open)
lean/Fw.lean, lean/scripts/check.sh, lean/scripts/NavEarnWebkitGolden.lean, lean/Fw/Ci/Trigger.lean, packages/contracts/golden/ci/triggers.jsonl,
packages/contracts/golden/preset/look-change.candidates.jsonl, lean/Fw/Gate/Trajectory.lean (+ golden gate/trajectory.jsonl, gate-breakpoints reduce.mjs: the
transition table must equal nav.module.css), packages/gate-breakpoints/src/trajectory/transitions*.mjs, .github/workflows/trajectory-probe.yml,
docs/team/tools/trajectory-frames.md.

## Open
- Breakpoint gate with the variant needs a dispatch with `fw` (lead): `gh workflow run breakpoint-gate.yml --ref ci/earn-webkit-smooth -f engines=chromium -f fw=nav:earn-logical`.
  A push does not start the gate (head commit lacks `[ci:breakpoint-gate]`).
- User's Safari and iPhone review of the felt result.
