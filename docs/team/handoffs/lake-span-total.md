branch: worktree-wf_25fb70f6-c00-1  worktree: .claude/worktrees/wf_25fb70f6-c00-1 (under the repo root)
last commit: see git log; CI runs: none (accepted limit: no CI dispatch)

State: built and checked locally; dry land passed with --allow apps/runner/src/slot.ts (VERDICT dry lake-span-total).
Verified: lake build Fw.Obs.Timing (outer_rebuild_noBaseline, incident_outer_not_slow, #guards); TimingGolden written and
--check via check.sh; check.sh green via fw slot; @fw/runner test 3526 passed; ci-paths 56 pass; land-inputs 73 pass.
Read first: research/notes/2026/10-2x-lake-span-total.md.
Conventions: outer lake work = outerBuilt (sum of per-check built); land.ts keeps a builds list, land() ends the total span with
the lake member (dryLake), landRun's finally also notes the inner span and calls writeLakeHandoff (env FW_SLOT_LAKE_FILE);
slot.ts run() sets that env for kind land and puts readLakeHandoff on the slot span. Golden: golden/obs/timing-outer.jsonl.
Open: apps/runner/src/slot.ts is outside the graph writes (needs --allow on the dry land); fw slot runs slot-main from main,
so the slot span member shows only after the land.
