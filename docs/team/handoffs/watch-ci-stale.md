# watch-ci-stale handoff
- branch: worktree-wf_7e08ee00-224-1; worktree: .claude/worktrees/wf_7e08ee00-224-1; CI runs: none (no CI push; local Lean + runner tests)
- cause: failed gh run list -> collectSystem carries the old list up to 1 h with status in_progress (note: research/notes/2026/10-2x-watch-ci-stale.md)
- done: Lean GhStatus.ciAgeNote/ciFreshMs + Gh.ciAgeMs, Health.ciSlowAlert note + theorems, Wire/Obs.lean field + roundtrip, goldens regenerated; TS SystemSnap.ciAt, gh.ciAgeMs; tests in watch.test.ts, watch-gh.test.ts
- open: null reason of the failed list is not recorded; a finished run only closes once the list can be read
- read first: the research note
