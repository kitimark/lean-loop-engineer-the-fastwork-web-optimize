branch: worktree-wf_d4bb5016-cf9-1 (CI branch ci/push-cycle-lag)
worktree: .claude/worktrees/wf_d4bb5016-cf9-1 (under the main checkout)
last commit: see git log (final commit "push-cycle-lag: note, results, handoff"); ci/push-cycle-lag on origin = 33ae23d29
CI runs: push 1 toolbar-throttle 40206864819 failure (sims 1, 3 usable; sim 2 lost), chromium-counts 40206864910 success, lean 40206864857 success; push 2 toolbar-throttle 40218625611 success, chromium-counts 40218625602 success; push 3 (the re-push, 33ae23d29, dwell 1 s, flag-off arms) toolbar-throttle 40232266467 FAILURE: every sim ran its touch step to success, then actions/upload-artifact refused the file 1-driver-off-engine.scroll:unthrottle-r1.log (colon in a file name; sim (1) log of the run), so no flag-off data exists. Pushes used: 4 of the allowed (push 3 and its one re-push); no further push without the lead.
verified: Lean check.sh green (after merging main); webkit, chromium, runner package tests and ci-paths test pass; plan lint has no push-cycle-lag writesClosure line; the fix (uploadName, renamed files in push-cycle-cli.mjs run) has a unit test but has not run on CI.
state: reduced and written: research/notes/2026/10-2x-push-cycle-lag.md (answer, per-cycle table, H1-H4 verdicts), results/push-cycle-lag/*.md (run tables). Undelivered: the flag-off attribution of push 3.
open: lead decides a second push 3 (command: empty commit with message lines "[ci:toolbar-throttle] [throttle:push-cycle:1000] [throttle:push-cycle-off]", then git branch -f ci/push-cycle-lag HEAD and pnpm -s fw ci push --branch ci/push-cycle-lag --lanes toolbar-throttle; then reduce with push-cycle-cli.mjs report --in 1-throttle.json,2-throttle.json,3-throttle.json and add the result to the note); fix candidates in the note.

# State
- Lean: lean/Fw/Measure/PushCycle.lean (cost model, trend, H1-H4 premises and verdicts, cycle plan, phone profile), golden packages/contracts/golden/measure/push-cycle.jsonl, wired in lean/scripts/check.sh, Fw.lean, Fw/Ci/Trigger.lean.
- WebKit Simulator touch lane: packages/measure-webkit/src/throttle/push-cycle*.mjs (twin, page recorder, pass, report, cli, search); workflow toolbar-throttle.yml marker [throttle:push-cycle] (dwell 300) or [throttle:push-cycle:1000]; arms original, rewrite, user; 3 jobs. TS stand-ins: recordCycles, verdictInputs, indexSeries, searchOf.
- Chromium counts lane: packages/measure-chromium/src/push-cycle.mjs (profiles from the golden plan, window sums, spread compare via offscreen.mjs cmp), profiles push-cycle-d300 and push-cycle-d1000. Read a result dir: node src/push-cycle.mjs report <dir of chromium-counts-* artifacts> --dwell 300 [--half open|close|all].
- Phone replay profiles: results/push-cycle-lag/phone-profile-d300.json, -d1000.json (equal to the Lean profile; for phone-compose-counts).

# Conventions
- Sandbox refuses compound shell: plain single commands, literal absolute paths, Write/Edit tools.
- Push form: git branch -f ci/push-cycle-lag HEAD, then pnpm -s fw ci push --branch ci/push-cycle-lag --lanes toolbar-throttle,chromium-counts (the head commit message carries the markers; draft in the scratchpad pcl/ folder).
- Wait: pnpm -s fw ci wait --branch ci/push-cycle-lag in the background; fetch with pnpm fw ci <runId> or gh run download.

# Read first
lean/Fw/Measure/PushCycle.lean header, packages/measure-webkit/src/throttle/push-cycle.mjs header, this file.
