# land-lane-circleci handoff

State: branch worktree-wf_27cbc28d-204-2. `sh lean/scripts/check.sh` green (axiom check 0 failing); apps/runner `pnpm test` 1836 pass; `node --test scripts/circleci.test.mjs
scripts/ci-paths.test.mjs` 118 pass. Read first: `docs/team/tools/land.md` ("The land overflows to CircleCI"), `research/notes/2026/10-21-land-lane-circleci.md`.

Built
- Lean `Fw.Ci.Overflow` (rule, widths table, theorems `github_first`, `overflow_only_when_full`, `never_both`, `verdict_same`, `pickKind_*`), wire ops `ci.overflow`,
  `ci.overflowCombine`, golden `packages/contracts/golden/ci/overflow.jsonl` (40 lines), replayed in `apps/runner/test/land-overflow.test.ts`.
- `.circleci/config.yml` + `job.sh`: land job per leg (same `fw checks --tier remote --leg` entry, writes `lane.json`); `scripts/circleci.mjs` `trigger --lane land --legs`,
  `landLegs`, `landLane`, lanes in run.json, `creditsSoFar`, 404-on-new-workflow tolerance in `pollOnce`.
- `land-remote.ts`: `circleciAdapter`, `normalizeCircle`, `makePusher` (one marker for both providers), `markerMessage` (`[legs:a,b]`), `awaitGroups`, `legsCovered`.
  `land-overflow.ts`: slot count (`gh run list`, 120 s cache, newest 100 runs), CircleCI facts, `planOverflow`. `land.ts` wires it (any setup failure: GitHub only).
- `land.yml` guard reads `[legs:..]` into a matrix `exclude`. `land-probe.ts` lands HEAD through the real path on a probe branch.

Live (MEASURED, one run each; ids are public run ids)
- Paired: GitHub run 39586853718 and CircleCI pipeline 54ecd7d1-a61a-4bf7-9319-4df18982ed7f (#304): 5 legs each, same sha and `digest=remote:apps/runner,packages/engine-check`.
- Forced overflow: `FW_LAND_FORCE_FULL=1 node apps/runner/src/land-probe.ts --task llc-forced2` -> pipeline 7733541c-8613-42c1-8412-0fae5bef0eb5, `VERDICT accept remote-pass`.
  First try (pipeline 5cece824-a357-4ea0-bfb7-f0418cc37450) found the 404 race, fixed.
- Partial split: GitHub run 39590436245 ran only `land (check-sh)` and `land (suites-a)`.

TS stand-ins (not Lean): status-to-active filter in `readSlots`; `markerMessage`; `legsCovered`; sha and digest uniformity in `normalizeCircle`.
Extra writes beyond the declared list: `lean/Fw/Ci/Wire.lean`, `lean/scripts/OverflowGolden.lean`, `.github/workflows/land.yml`, `apps/runner/src/land.ts`,
`land-overflow.ts`, `land-probe.ts`, `test/land-overflow.test.ts`.

Limits: slot count up to 120 s old and sees only the newest 100 runs (under-count); width table over-counts finished jobs; Linux legs only; no hedge; CircleCI under load
not measured; credits count only fetched pipelines (rolling 30 days); an aborted CircleCI pipeline is not cancelled; one group "local" runs the whole remote tier here; `ghPrev` false.

Open
- Busy-window measurement of CircleCI concurrency; hedging; macOS lanes (tasks ci-route, pool-fallback).
- CircleCI legs ran 450 to 579 s vs GitHub 63 to 127 s: a CircleCI Lean build cache (config.yml has `save_cache`) may close part of it; not measured.
