branch: worktree-wf_60f31c57-bb5-1 | worktree: .claude/worktrees/wf_60f31c57-bb5-1 | last commit: see git log | CI branch: ci/webkit-recount @60ee5c326 (= main; every arm measures this sha)
Dispatch form: `pnpm -s fw run --target rewrite --engines webkit --ref ci/webkit-recount --runs 3 --no-route [--fw part:variant]` (--no-route keeps all VMs on GitHub: Codemagic cells have other hardware; `--runs` must be 2..10, so a retry is --runs 2 and only the needed VM id is used). Artifacts of a failed run: `gh run download <id> --repo kitimark/lean-loop-engineer-the-fastwork-web-optimize --pattern 'webkit-sim-r*' --dir <scratch>` (scratch = session scratchpad wr/).
CI runs (state):
- base 40349554405: r2, r3 ok; r1 LOST at Determinism sessions (first pass: Safari opened no tab, 19 openurl asks in 155 s, then silent; the 720 s stall watchdog killed it at 748 s; no pass-level SimHost gate fired). Host load1 667-860 in r2/r3, passes still kept.
- base retry 40360267706 (--runs 2): success, r1 and r2 good. Base for the reader = retry r1 + first-run r2 + r3 (3 distinct VMs, 6 passes); retry r2 is a sensitivity extra
- platform.entries:fill-release 40349566685: r2, r3 ok; r1 LOST at Determinism sessions, same signature as base r1 (no tab after 150 s, 22 openurl asks, silent, stall watchdog at 723 s)
- fill-release retry 40364461242 (--runs 2): r1 LOST again (stalled 731 s mid pass at census y=3000, event loop blocked in a host `lsof` call; no SimHost pass gate fired), r2 ok (same id as r2 of the first run, counts once). fill-release arm = r2, r3 only: n=3+2, undecided after the one allowed retry (reader: pass rule noGain in all 4 zones)
- layer-sweep 3 VMs: 40366658003 (queued behind other tasks' macOS jobs 17:18Z-19:47Z; r1 ok, r2 LOST at Determinism sessions (reason pending), r3 running at 22:00Z). The `fw run` wrapper gave up after its 4 h cap: download artifacts by hand with gh run download --repo kitimark/lean-loop-engineer-the-fastwork-web-optimize
- hero.exit:contain 3 VMs: 40372868559 success 3 of 3. Reader zones and hero windows (3+3 VMs, 6+6 passes): noGain everywhere, decided. results/webkit-recount/contain-zones.json, hero-exit-contain.json
- layer-sweep first run lost r2 (inspector dead, simctl shutdown ETIMEDOUT) and r3 (warm-up Runtime.evaluate timeouts x2); only r1 good. Retry (3 VMs, needs r2 and r3) 40408733016 queued
- entries:probe-off 3 VMs dispatched at 00:10Z (id: gh run list); marquee:probe-off not yet
Next waves in order: layer-sweep (platform.sweep:layer-sweep), hero.exit:contain, platform.entries:probe-off, platform.marquee:probe-off.
Lane takes one site config per VM job (no several arms per VM).
Reader: packages/measure-webkit/src/offscreen-webkit-cli.mjs (zones z4500 z5000 finish whole); hero.exit:contain also results/hero-relayout-boundary/read-webkit.mjs windows.
Verified: nothing yet. Open: everything after the runs (notes, ledger, recount note, check.sh, dry land, review).
