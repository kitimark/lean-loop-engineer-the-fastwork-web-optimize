# gate-shard-balance handoff (round 2)

State: branch worktree-wf_42bb95c8-4f0-1 (pushed as ci/gate-shard-balance-r2: ci/gate-shard-balance holds round 1 and cannot be
force-pushed). `sh lean/scripts/check.sh` green. Package tests green (`node --test test/*.test.mjs` in packages/gate-breakpoints).

## What round 2 did
- 5107fcc: engine verdict counts unsettled from the Lean settle wait (`Fw.Gate.Exit`, `exit.jsonl`).
- Frozen page clock in both arms: `lean/Fw/Gate/Freeze.lean`, `golden/gate/freeze.jsonl`, `src/freeze.mjs`, `page.mjs` (KIT_SRC,
  freezeAnimations), `engines.mjs` (freezeClock; Chromium now playwright-core with CDP emulation), `run.mjs` (resizeTo, frozen).
  `FW_GATE_FROZEN=0` is a debug switch; the gaps lane stays native. check.sh stage `GateGolden.lean` checks exit and freeze goldens.
- anchors.json: mount steps of morph.countdown and morph.columns carry `kind: mount`; the runner refuses unknown kinds.

## Result (MEASURED, 3 runs on d9a6744 -> 39115860145, 39115867180, 39116538316)
392/392 samples settled per engine (baselines 80/392). Gate wall 5.0 min, 25.9 job-minutes, 15 parts (252 cells/engine).
Vs main run 39102911533: Chromium 0 cells differ; WebKit 12 hero.countdown/hero.exit cells fail -> pass (in-flight frames);
platform.stageBg x desktop sweep fails on WebKit in every run and on main. Details: research/notes/2026/10-18-gate-shard-balance.md.

## Open
- The 33-part cells (desk-rm-861 hero.orbit, desk-rm-1279 commission) are not reproducible on 15 parts; re-run after integrate-ports-3.
- Regenerate `ShardObs.lean` (scripts/shard-obs.mjs) from a frozen run: costs changed from 65 to 26 job-minutes.
- HOLD_LOAD_MS 8000 and ORIG_GRACE_MS 1500 are harness choices; check them when a part's entrance runs longer.
- Worktree needs `pnpm install --offline --frozen-lockfile` before `pnpm fw` works.
