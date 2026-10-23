branch: worktree-wf_47f5b5af-b15-1
worktree: .claude/worktrees/wf_47f5b5af-b15-1 (under the repo root)
last commit: see `git log -1` on the branch
CI runs started by me: none (existing runs answered the unit; accepted limit of one dispatched run unused). Runs read: 40010696608, 40010826449, 40011143247, 40011600530, 40011600647, 40012913395 (restores of pruned main entries), 40009814844 (first pruned main save), 40012913395 (exe artifact).

State: all four title items done except the behind-main measure. Verdict per leg (Fw.Ops.LakeCache.verdict): 10 of 10 legs hit, 43-51 Built lines of 826/849 jobs, setup-lean 17-24 s. Prune stays; exe stays pruned (relink 0.63-0.68 s < 1 s rule); lean.yml and fwcore-build.sh unchanged.
Verified: lake build Fw.Ops.LakeCache green, golden lake-cache.jsonl equals the Lean output (gen ["--check"]), theorems legs_ok, no_gate_pays, exe_pruned, keeps_*.
Correction found: the first row of the note's item-3 table gave 12 s saved; it is 46 s (still < the 62 s wait).
Open: (1) no run restored a pruned entry onto a branch BEHIND the entry; INFERRED only, the next one extends `legs`. (2) the golden check needs a job in lean/scripts/check.sh (outside this task's writes), line:
  job "lake-cache golden check" sh -c 'printf "import Fw.Ops.LakeCache\n#eval Fw.Ops.LakeCache.gen [\"--check\"]\n" | lake env lean --stdin'  # golden/ops/lake-cache.jsonl
Conventions: legs are MEASURED rows copied from job logs (run, job, hit, files, Built lines, jobs, setup seconds); regenerate the golden with `Fw.Ops.LakeCache.gen []` from lean/.
Read first: research/notes/2026/10-2x-ci-setup-lean-slow.md, last two sections.
