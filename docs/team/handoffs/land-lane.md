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

CI proofs (final code e8a6b01f + probe commit): Lean-only run 39260671932 and runner-only run 39260628508, both GREEN. Lean-only: 5 remote checks pass, skipped=0 each; phases queue 22s, setup 39s, fwcore build 18s (restored cache), rebuilt again from the artifact cache 0.2s, suites 345s. Runner-only: queue 21s, setup 72s, fwcore 18s, suites 178s. Cold fwcore (stale cache) was 217s in run 39249846030.

Open items
- fwcore build is warm only when main's Lake cache entry has this lean/ tree (the lean lane writes it on main pushes; ci/* entries are branch-scoped). Land probes before landing use the old main entry (partial).
- fw land waiting on the lane: task land-wait.

Read first: lean/Fw/Console/LandTier.lean, apps/runner/src/checks.ts, .github/workflows/land.yml.
