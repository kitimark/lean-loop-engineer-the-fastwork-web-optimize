branch: worktree-wf_1cff5c71-27c-1  worktree: .claude/worktrees/wf_1cff5c71-27c-1 (under the repo root)
last commit: see git log; CI runs: none (accepted limit: no CI dispatch)

State: built and checked locally; dry land is the last step.
Verified: lake build Fw.Obs.Timing (judgeQ_rebuild_noBaseline, incident_not_slow, #guards); TimingGolden --check; check.sh green
via fw slot (its own span line carried lake.built 0); @fw/runner test 3501 passed incl. typecheck; ci-paths + lake-slot node tests.
Read first: research/notes/2026/10-2x-lake-span-mods.md.
Conventions: the lake member rule is Fw.Obs.Timing.lakeBuilt?; three twins (Lean, timing.ts lakeMember, awk lake_built_member
in scripts/lake-slot-lib.sh) are tied by golden/obs/timing-lake.jsonl. check.sh exports FW_LAKE_BUILT_FILE and sets span_more_file;
fwcore-build.sh writes the member, span.sh appends it to the next span line. land.ts ends check spans with lakeMember(output).
Open: apps/runner/test/timing-work.test.ts is not in the graph writes list.
