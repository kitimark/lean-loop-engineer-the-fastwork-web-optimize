branch: worktree-wf_d4bb5016-cf9-1 (CI branch ci/push-cycle-lag)
worktree: .claude/worktrees/wf_d4bb5016-cf9-1 (under the main checkout)
last commit: 2bb2a897b (push 1 of at most 3; request commit, empty)
CI runs: toolbar-throttle 40206864819 failure (sim 1 and sim 3 success with 3 passes each, rewrite needed one restart; sim 2 lost: touch step hit its 90 min limit, no artifact; report job success) ; push 2 (cb4b6a8b7, dwell 1 s): chromium-counts 40218625602 success (Paint 520->588 and RasterTask 103->113 rise from k=3, same in original; invalidation area 5.1M->7.2-7.7M, below k=0 16M; layers constant), toolbar-throttle 40218625611 of push 2: sims 1 and 2 success (downloaded), sim 3 running; at dwell 1 s slow >50 ms also rises at k=3 in original (41->101, 65->140), further to k=4 in rewrite and user; chromium-counts 40206864910 success; lean 40206864857 success
verified: Lean check.sh green; WebKit, Chromium and runner (land-inputs, ci-triggers) package tests pass; ci-paths test passes; plan lint has no push-cycle-lag writesClosure line
chromium (dwell 300, 3 runs per arm, downloaded to the scratchpad): window k=0 carries the first-time cost (raster invalidation 14.1M px against 2.1-3.1M later); layers stay constant (107 rewrite, 35 user composition), only 4 layers churn at k=2 and k=5; Layout/Paint do not fall in cycles 2 and 4 (Paint 452 and 468 against 408 at k=0); the user composition equals rewrite on Layout/Paint/Raster and differs only in UpdateLayer (about 1900 against 7960) and layer count.
webkit sim dwell 0.3 s (2 usable jobs, 1 and 3, rotations differ): slow >50 ms per cycle rises at k=3,4 for rewrite (vm1 37,145,244; vm3 64,126,210 at k=2,3,4) and user (vm1 128,150,335; vm3 52,118,261) but not for original; viewport changes (toolbar) fall to 2 per cycle in later cycles, so H1 does not drive the rise; reduce with push-cycle-cli.mjs report --in a.json,b.json.
open: push 3 (dwell 0.3 s again, third usable job); push 2 (dwell 1 s: marker throttle:push-cycle:1000 and profile=push-cycle-d1000); per-hypothesis verdicts; research note; full check.sh, dry land, review ready

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
