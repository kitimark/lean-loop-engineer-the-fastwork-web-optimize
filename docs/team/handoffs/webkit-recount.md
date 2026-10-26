branch: worktree-wf_60f31c57-bb5-1 | worktree: .claude/worktrees/wf_60f31c57-bb5-1 | last commit: see git log | CI branch: ci/webkit-recount @60ee5c326 (= main; every arm measures this sha)
Dispatch form: `pnpm -s fw run --target rewrite --engines webkit --ref ci/webkit-recount --runs 3 --no-route [--fw part:variant]` (--no-route keeps all VMs on GitHub: Codemagic cells have other hardware; `--runs` must be 2..10, so a retry is --runs 2 and only the needed VM id is used). Artifacts of a failed run: `gh run download <id> --repo kitimark/lean-loop-engineer-the-fastwork-web-optimize --pattern 'webkit-sim-r*' --dir <scratch>` (scratch = session scratchpad wr/).
CI runs (state):
- base 40349554405: r2, r3 ok; r1 LOST at Determinism sessions (first pass: Safari opened no tab, 19 openurl asks in 155 s, then silent; the 720 s stall watchdog killed it at 748 s; no pass-level SimHost gate fired). Host load1 667-860 in r2/r3, passes still kept.
- base retry 40360267706 (--runs 2): success, r1 and r2 good. Base for the reader = retry r1 + first-run r2 + r3 (3 distinct VMs, 6 passes); retry r2 is a sensitivity extra
- platform.entries:fill-release 40349566685: r2, r3 ok; r1 LOST at Determinism sessions, same signature as base r1 (no tab after 150 s, 22 openurl asks, silent, stall watchdog at 723 s)
- fill-release retry 40364461242 (--runs 2; use only r1) running
- layer-sweep 3 VMs: dispatched after base retry (id in wr/sweep.log; list with gh run list)
Next waves in order: layer-sweep (platform.sweep:layer-sweep), hero.exit:contain, platform.entries:probe-off, platform.marquee:probe-off.
Lane takes one site config per VM job (no several arms per VM).
Reader: packages/measure-webkit/src/offscreen-webkit-cli.mjs (zones z4500 z5000 finish whole); hero.exit:contain also results/hero-relayout-boundary/read-webkit.mjs windows.
Verified: nothing yet. Open: everything after the runs (notes, ledger, recount note, check.sh, dry land, review).
