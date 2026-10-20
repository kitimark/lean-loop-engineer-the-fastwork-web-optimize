# Handoff: land-check-remote

State: branch worktree-wf_7c5d2ef0-583-1; code commit fbd7a9ee (+ empty `[ci:land]` probe commit 955bac38, + this handoff).
`sh lean/scripts/check.sh` green at fbd7a9ee. Runner (1573), contracts (7) tests and `node --test scripts/ci-paths.test.mjs` pass.

What changed
- Lean `LandTier`: `checkShId`, `remoteIds` gains it (8 ids); `gates_local` is install + reads-scan only; `check_sh_remote`;
  `filterList` uses `suiteIds` (the script has no pnpm package; still 7 selectors).
- Lean `LandLegs`: leg `checkSh` ("check-sh", first in the matrix), `shardC`; theorems `shards_perm`, `shards_nodup`, `shardC_disjoint`,
  `shard_one`, `legs_cover`, `legs_nodup`, `checkSh_sound`, `checkSh_runs_of_selected`, `checkSh_no_engine`. `laneVerdict` untouched.
- Regenerated: land-tier.jsonl, land-legs.jsonl, lean/land-legs.txt (never hand-edit).
- land.yml: matrix gains check-sh (same setup-lean + fwcore build as every leg; the leg runs `fw checks --leg check-sh`).
- TS stand-in: `SUMMARYLESS` in `apps/runner/src/checks.ts` (check.sh prints no test summary, so exit code is its verdict; skipped=0).
  Replace by a Lean list in LandTier plus an op field. Everything else (tier, leg) comes from fwcore.
- land.ts unchanged: the local fallback (`remote:false`, CI unavailable) runs the remote tier here incl. check.sh; `checkDeps` still orders it.

Evidence (one before/after pair; free runners vary)
- Before: run 39458419744 (main-based land, 8m26 total; webkit 8m02, chromium 6m44, suites-a 6m33, suites-b 6m24).
- After: run 39461106516 success, 4m14 total; check-sh 2m09 (check.sh itself 31 s), suites-a 2m41, suites-b 2m49, chromium 2m55, webkit 3m53.
- Mac local tier (spans `.fw-console/timings.jsonl`, tool "fw land"): before "local tier" 43.7-54.9 s of which `sh lean/scripts/check.sh`
  26.3-37.0 s (commits bbb99c3, 76b7c5b, 2ff42b6, eea0134). After: INFERRED 16.7-17.9 s (tier minus check.sh); not yet measured on a real land.

Open: re-read the Mac "local tier" span on the first real land after this one; Mac CPU per land is not in spans.
Read first: lean/Fw/Console/LandLegs.lean, docs/team/tools/land.md (legs section).
