branch: worktree-wf_6513a020-ac2-1
worktree: .claude/worktrees/wf_6513a020-ac2-1
state: no CI run pushed (no CI lane in this task)

Done: Lean kind workflow + check workflowParse in lean/Fw/Ops/CheckMap.lean (row 9a, workflow_routed, workflowParse_cmd, precommit_covers extended, #guards); golden regenerated (20 cases); scripts/checkmap.mjs 'file workflow' mode (AsyncFunction parse after stripping 'export const meta = '); scripts/checkmap.test.mjs (4 tests: build-review.js ok and broken body refused, on current node 24.14 and node 24.22).
Verified: lake build green; golden --check up to date; node --test scripts/checkmap.test.mjs 4/4; checkmap --paths on both workflows ok under 24.14 and 24.22.
Open: scripts/test-checkmap.mjs fails 'preset: all 23 modules of Gen import closure are inputs' (cause not in this task; not touched). test-checkmap.mjs preset closure failure reproduces on main 399d4823b (pre-existing).
Outside writes: lean/scripts/CheckMapGolden.lean (one golden case: workflow bodies get workflowParse); scripts/checkmap.mjs source() uses resolve so absolute paths work.
