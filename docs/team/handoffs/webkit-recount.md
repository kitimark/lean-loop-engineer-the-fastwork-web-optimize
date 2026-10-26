branch: worktree-wf_60f31c57-bb5-1 | worktree: .claude/worktrees/wf_60f31c57-bb5-1 | last commit: 60ee5c326 (main, nothing of mine committed yet) | CI branch: ci/webkit-recount @60ee5c326 (= main; every arm measures this sha)
State: dispatch wave 1 running (base + fill-release, `pnpm -s fw run --target rewrite --engines webkit --ref ci/webkit-recount --runs 3 --no-route [--fw ...]`; --no-route keeps all 3 VMs on GitHub, Codemagic cells have other hardware).
CI runs:
- base (default): 40349554405 running (nonce 1163cafa8d429157)
- platform.entries:fill-release: 40349566685 running (queued title "webkit-sim"; confirm by nonce 6c0279d8bc0d217b)
Next waves in order: layer-sweep (platform.sweep:layer-sweep), hero.exit:contain, platform.entries:probe-off, platform.marquee:probe-off.
Lane takes one site config per VM job (no several arms per VM): 6 dispatches x 3 VMs = 18 jobs.
Reader: packages/measure-webkit/src/offscreen-webkit-cli.mjs (zones z4500 z5000 finish whole); hero.exit:contain also results/hero-relayout-boundary/read-webkit.mjs windows.
Verified: nothing yet. Open: everything after the runs (notes, ledger, recount note, check.sh, dry land, review).
