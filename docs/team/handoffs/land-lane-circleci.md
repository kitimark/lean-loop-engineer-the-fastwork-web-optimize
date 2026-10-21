# land-lane-circleci handoff

State: branch worktree-wf_27cbc28d-204-2, round 2 code commit bd1fec07 (round 1 c79f8223). `sh lean/scripts/check.sh` exit 0 (axiom check 0 failing, overflow golden 48 lines);
apps/runner `pnpm test` 1863 pass (typecheck included); `node --test scripts/ci-paths.test.mjs scripts/circleci.test.mjs` 118 pass.
Read first: `docs/team/tools/land.md` ("The land overflows to CircleCI"), `research/notes/2026/10-21-land-lane-circleci.md`, `lean/Fw/Ci/Overflow.lean`.

Built
- Lean `Fw.Ci.Overflow`: rule, `widths`, `settle`; theorems `github_first`, `overflow_only_when_full`, `never_both`, `verdict_same`, `pickKind_*`, `failed_start_covered_once`.
  Wire ops `ci.overflow`, `ci.overflowCombine`, `ci.overflowSettle`; golden `packages/contracts/golden/ci/overflow.jsonl`, replayed in `apps/runner/test/land-overflow.test.ts`.
- `.circleci/config.yml` + `job.sh` land job per leg; `scripts/circleci.mjs` `trigger --lane land --legs`. `land-remote.ts`: `circleciAdapter`, `makePusher`, `awaitGroups`, `legsCovered`.
  `land-overflow.ts`: slot count and CircleCI facts. `land.yml` guard reads `[legs:..]`. `land-probe.ts` lands HEAD through the real path on a probe branch.
- Round 2: the `widths` rows are derived from the workflow files by `apps/runner/test/land-overflow-widths.test.ts` (+ `workflow-widths.ts`); a matrix, job or workflow that grows fails it
  until the Lean row is raised. A CircleCI start that fails (adapter missing, key check, push, trigger) re-runs its legs on GitHub on branch `...-again` (`awaitGroups`), never locally.

Live (MEASURED; public ids): paired GitHub run 39586853718 + CircleCI pipeline 54ecd7d1-a61a-4bf7-9319-4df18982ed7f; forced overflow pipeline 7733541c-8613-42c1-8412-0fae5bef0eb5
(`VERDICT accept remote-pass`); partial split GitHub run 39590436245. Round-2 forced-overflow re-run: see the report (id recorded there).

TS stand-ins (not Lean): status-to-active filter in `readSlots`; `markerMessage`; `legsCovered`; sha and digest uniformity in `normalizeCircle`; the width derivation in the test
(`workflow-widths.ts`) and the choice of `-again` branch / group wiring in `awaitGroups` (the leg split itself is Lean `settle`).
Extra writes beyond the declared list: `lean/Fw/Ci/Wire.lean`, `lean/scripts/OverflowGolden.lean`, `.github/workflows/land.yml`, `apps/runner/src/land.ts`, `land-overflow.ts`,
`land-probe.ts`, `test/land-overflow.test.ts`, `test/land-overflow-widths.test.ts`, `test/workflow-widths.ts`.

Limits (named): the slot count reads THIS REPOSITORY only and the NEWEST 100 RUNS, so other repositories of the account and older runs are invisible (it can under-count); it is up to
120 s old; width rows over-count finished jobs; Linux legs only; no hedge; busy-window CircleCI concurrency unmeasured; credits count only fetched pipelines (30 days);
an aborted CircleCI pipeline is not cancelled; a GitHub group that cannot start runs the remote tier here; `ghPrev` false.

Open
- Busy-window measurement of CircleCI concurrency; hedging; macOS lanes (tasks ci-route, pool-fallback).
- CircleCI Lean cache (follow-up task): the CircleCI land job has NO Lean cache today (config.yml: "No cache of any kind", storage stop rule); its legs took 450-579 s (second run about 466-471 s)
  against 63-127 s on GitHub, INFERRED to be the cold Lean build; weigh a cache against the storage stop rule.
