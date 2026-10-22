Branch: worktree-wf_a1c5829a-60b-1
Worktree: .claude/worktrees/wf_a1c5829a-60b-1 (under the repo root)
Last commit: see `git log -1` (work commit 52920d209, then the merge of main). No CI run pushed (no ci/* push in this task).

Verified (local, through fw slot): lean/scripts/check.sh green (axiom check, diskgc golden 50 cases); apps/runner test 91 files / 2639 tests
(incl. typecheck); scripts/ci-paths.test.mjs and scripts/lint-tmpdirs.test.mjs pass.

Delivered, the six follow-ups:
1. fw-main.ts postLandGc runs classes lake, landed, console, usertmp.
2. Fw.Ops.DiskGc.tmpPrefixes extended from git grep of mkdtemp prefixes (dryl-, jev, cm-, slots-, rr-, replay-, wkrep-, wkraw-,
   vd-, compose-, graph- and the rest); usertmp_named has a docstring; deletes_subset_allowlist unchanged and still proved.
3. lean.yml node --test line runs scripts/lint-tmpdirs.test.mjs.
4. Cand.sym is Option Bool (none from a missing JSON key); ruleConsole/ruleUsertmp need sym = some false; rule_console/rule_usertmp
   say so; goldens regenerated (new case: no sym fact is kept).
5. Lean event liveness in DiskGc.lean (Ev, stopped by seq, resume by later spawn, runOfEnd/runOfLabel, liveAgents, finishedRuns,
   landedTasks) with theorems stop_ends, resume_not_stopped, liveAgents_spec, finishedRuns_spec, landedTasks_spec; wire op
   ops.diskGcFacts; TS gatherEventFacts(repo, call) only parses lines and asks fwcore (null, so class 4 keeps all, on a line without seq).
6. scripts/lint-tmpdirs.mjs pairs each mkdtemp binding with an rm of that name inside a cleanup window; unbound factories fall back to the file rule.

Open: the 78 GB X folder under var/folders (out of scope); fixing the tests the lint flags (separate follow-up).
Read first: lean/Fw/Ops/DiskGc.lean (end of namespace Fw.Ops.DiskGc), docs/team/tools/disk-gc.md.
Decision to know: only agent.spawn resumes a stopped agent (an agent.label after a stop does not), so a late-drained label cannot revive an ended agent.
