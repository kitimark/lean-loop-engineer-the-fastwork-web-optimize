branch: worktree-wf_efedb182-ce1-1
worktree: .claude/worktrees/wf_efedb182-ce1-1
last commit: see `git log -1` on the branch
CI runs started by me: none (existing land runs answered the unit). Runs read: 40024272661, 40031018930, 40026269429, 40028997665, 40037942688.

State: finding and fix delivered; note research/notes/2026/10-2x-ci-gate-engine-webkit-slow.md.
Verified: lake build Fw.Ops.GateEngineTiming green; golden gate-engine-timing.jsonl equals Lean output (gen ["--check"]); six ref rows replayed against the action's shell `case` (0 mismatches); action.yml parses.
Verdict: slow steps = apt sub-step variance (class aptVariance); Post 43 s = cache save (fixableSave). Both gate caches miss on every land leg because ci/land-* saves are invisible to other branches (24 entries, 2144 MB, none on main). Fix: no save on ci/land-* (Lean shouldSave).
Open: (1) next land legs show Cache restored once main holds the entry (premise-tests engine runs on main when this lands); (2) lean/scripts/check.sh job for the golden (outside writes, line in the note); (3) lean/Fw.lean import line added (outside writes).
Read first: the note.
