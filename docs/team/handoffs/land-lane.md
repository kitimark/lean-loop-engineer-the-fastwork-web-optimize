# land-lane handoff (round 1)

State: branch worktree-wf_e5423bd4-ebd-1; the land lane (`.github/workflows/land.yml`, push `ci/land-*` with `[ci:land]`).

What it is
- `lean/Fw/Console/LandTier.lean`: `tier` (allowlist `remoteIds`), `laneVerdict`, `filterList`/`filterText`; golden land-tier.jsonl and generated `lean/land-filter.txt` (both checked by check.sh).
- `apps/runner/src/checks.ts`: `fw checks --affected --base <rev> [--tier]`; `skippedCount` reads vitest, TAP and node:test spec (`ℹ skipped N`); fixtures in apps/runner/test/fixtures are real captured outputs.
- `.github/scripts/land-base.sh main|base`: main = HEAD^1 (lane sets refs/heads/main there, independent of origin/main); base = first parent, skipping empty tip commits.
- land.yml prints `PHASE queue|setup|fwcore_build|suites` lines; `[warm]` in the head commit message (or dispatch input) rebuilds fwcore from the Lake artifact cache to measure the warm time.
- `origin/ci/preview-pin`: octopus commit (tree of main) over 6 pinned commits only local branches held; preview-facts-gen.test fails instead of skipping on CI if they are missing. Never delete that branch.
- console-api `stopForTest` now waits for process state T (ordering, no wall clock).

TS stand-ins: skippedCount, land-base.sh (shell), the `fw checks` glue.

Open items
- fwcore build is warm only when main's Lake cache entry has this lean/ tree (the lean lane writes it on main pushes; ci/* entries are branch-scoped). Land probes before landing use the old main entry (partial).
- fw land waiting on the lane: task land-wait.

Read first: lean/Fw/Console/LandTier.lean, apps/runner/src/checks.ts, .github/workflows/land.yml.
