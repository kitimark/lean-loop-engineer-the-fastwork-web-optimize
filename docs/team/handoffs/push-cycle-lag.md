branch: worktree-wf_d4bb5016-cf9-1 (CI branch ci/push-cycle-lag)
worktree: .claude/worktrees/wf_d4bb5016-cf9-1 (under the main checkout)
last commit: 2bb2a897b (push 1 of at most 3; request commit, empty)
CI runs: toolbar-throttle 40206864819 running (sim 3 success and reduced: the glue works, 3 passes, rewrite needed one restart; sim 2 in progress, sim 1 queued on macOS); chromium-counts 40206864910 success; lean 40206864857 success
verified: Lean check.sh green; WebKit, Chromium and runner (land-inputs, ci-triggers) package tests pass; ci-paths test passes; plan lint has no push-cycle-lag writesClosure line
chromium (dwell 300, 3 runs per arm, downloaded to the scratchpad): window k=0 carries the first-time cost (raster invalidation 14.1M px against 2.1-3.1M later); layers stay constant (107 rewrite, 35 user composition), only 4 layers churn at k=2 and k=5; Layout/Paint do not fall in cycles 2 and 4 (Paint 452 and 468 against 408 at k=0); the user composition equals rewrite on Layout/Paint/Raster and differs only in UpdateLayer (about 1900 against 7960) and layer count.
open: WebKit sim results of push 1 (dwell 0.3 s); push 2 (dwell 1 s: marker throttle:push-cycle:1000 and profile=push-cycle-d1000); per-hypothesis verdicts; research note; full check.sh, dry land, review ready

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
