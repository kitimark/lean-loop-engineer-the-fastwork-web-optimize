# Handoff: sweep-offscreen-pause
Branch: worktree-wf_72c42085-d84-1 (ci branch ci/sweep-offscreen-pause, pushed at 6b4b9c69f). Worktree: .claude/worktrees/wf_72c42085-d84-1.
CI runs: breakpoint-gate 40091740060 (fw=platform.sweep:offscreen-pause, both engines) success;
trajectory-probe 40091732984 (diagnostic 390,1280, both engines, same flag) success. 1 of 3 dispatches used.
Verified: Lean PlatformSweepPause.lean (shown_same, visible_same, visible_phase, reported_no_tick, reported_run,
offscreen_ticks_le_one under the named premise Lag); golden platform-sweep-pause.jsonl --check ok, replayed by pause.test.ts;
site vitest 6575 pass, tsc clean; footprint chain regenerated; Bridge.lean retabled (platform.sweep no longer isolated: 11 not 12).
Open: rendering updates / main-thread time while offscreen are NOT measured: no CI lane counts them for the rewrite (wktr runs
the original only, count lanes count class names). Lead: Fw.lean imports Fw.Parts.PlatformSweepPause and
Fw.Parts.PlatformSweepPauseGolden; check.sh job: lake env lean --run scripts/PlatformSweepPauseGolden.lean --check
../packages/contracts/golden/parts/platform-sweep-pause.jsonl (script file lean/scripts/PlatformSweepPauseGolden.lean is in the branch).
Writes outside the task graph: apps/site/src/parts/platform/index.tsx (wiring), lean/Fw/Parts/{FootprintData,FootprintRows,Bridge}.lean,
packages/contracts/golden/parts/{footprint.gen,footprint-diff.gen}.json, golden/preset/v2-proved.decisions.jsonl,
research/findings/ledger.json (row platform.sweep.offscreen-pause), lean/scripts/PlatformSweepPauseGolden.lean.
Read first: lean/Fw/Parts/PlatformSweepPause.lean, then apps/site/src/parts/platform.sweep/pause.ts.

Round r426: main merged; wiring done in 844f1df7b (Fw.lean imports, check.sh job
'platform-sweep-pause golden check', lean.yml trigger row after stillruns, triggers.jsonl regenerated, ci-paths ok).
Verified: lean check.sh green, @fw/site tests 6576 pass, part-footprint --check ok, ci-paths test 56 pass.
Offscreen counts item: followUp, task offscreen-count-lane (graph r426). No new CI dispatch.
