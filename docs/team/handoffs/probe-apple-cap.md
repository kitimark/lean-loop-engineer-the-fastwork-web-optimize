branch: worktree-wf_f3187135-c59-1 (CI branch ci/probe-apple-cap, pushed once at f96cbd282)
worktree: .claude/worktrees/wf_f3187135-c59-1
last commit: see `git log -1` (code 39f48bc0b; later commits are note, handoff, merge of main)
CI runs: push 1 (f96cbd282, no [ci:...] line) started only skipped workflows (trajectory-probe run 40132944389: skipped). A ci/* push cannot reach the Mac leg without debug= (Lean Fw.Ci.Trigger.appleRuns), so the clean Mac run is a lead dispatch:
`pnpm -s fw run --trajectory --ref ci/probe-apple-cap --fw engine.scroll:batched --engines playwright-webkit`
Decision: re-derive the probe-apple cap (18 min from 6 retry-era legs, p90 13.2 min), not a per-leg budget. Reason and table:
research/notes/2026/10-2x-probe-apple-cap.md.
Verified locally (not results): check.sh green, gate-breakpoints test 778 pass, ci-paths 56, land-inputs 73, fw land --dry VERDICT dry probe-apple-cap.
Lean: Fw/Ci/Pool/Caps.lean (probeWalls, p90dmOfSec, legWorstSec, probe_worst_under_cap), Fw/Gate/Trajectory.lean (ArmRole, retries,
settleFor, pooledReps, leg_extra_le, legs_mac_len, leg_wall_under_cap); goldens written by Lean (trajectory.jsonl, pool-caps.jsonl, pool-fallback.jsonl).
TS: plan.mjs retriesRole/pooledReps, run.mjs uses them and sets out.reps = reps + extra; trajectory.test.mjs replays the golden + fake-engine morphPath test.
Open: the clean Mac run (dispatch above, judge each leg wall against 18 min); docs/team/tools/trajectory-probe.md:751 and
trajectory-frames.md:24 still say cap 15 (outside the task's writes); the thin lane re-derives at 10 successes.
Read first: research/notes/2026/10-2x-probe-apple-cap.md, then lean/Fw/Ci/Pool/Caps.lean.
