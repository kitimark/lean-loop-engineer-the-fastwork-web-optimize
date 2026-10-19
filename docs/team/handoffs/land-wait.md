# land-wait handoff

State: branch worktree-wf_8d5d5644-4a5-1 (commits from a5ce619e on). `fw land` runs the Lean local tier here and waits for the
remote tier on the GitHub land lane; Lean `Fw.Console.LandRemote` decides. Not landed; the lead does the first real land.

Verified (runner `pnpm test` 1193 pass, `land-inputs`, `ci-paths` 40 pass, contracts, `lean/scripts/check.sh` green):
- Lean: sha + laneDigest binding, any provider's fail wins, explicit fallback (unavailable -> next provider -> run here); 22 theorems,
  golden `packages/contracts/golden/console/land-remote.jsonl` (32 lines) replayed through fwcore in `land-remote.test.ts`.
- Live (MEASURED): `ci/land-probe-30a307f` (run 39317802669) failed on a missing fixture and its step name bound it to the sha;
  `ci/land-probe-e5b7f17` (run 39319745028) passed with `lane: sha=e5b7f177.. digest=remote:..`. Both recorded in
  `apps/runner/test/fixtures/land-remote/{fail,pass}.json`. Nothing was landed.
- Local work before vs after (MEASURED wall medians of the last land spans, `.fw-console/timings.jsonl`, CPU not measured): the
  remote-tier checks cost about 548 s of Mac time per land (runner 204, gate-breakpoints 115, console-api 86, measure-chromium 72,
  gh-budget 70, engine-check 1); they now run on the lane. Left here: about 66 s (check.sh 21, webkit 19, wktr 16, difftest 5,
  contracts 3, console-web 2) plus the evidence/fwcore build. While waiting the land process is one sleeping `fw ci wait` child.

How it works: `land.ts` `tieredChecks` -> `land-remote.ts` `runTiered` (split by `console.landTier`, push `ci/land-<task>-<sha7>`
= marker commit on the merge commit C, `awaitRemote` loop asks `console.landRemote`). `land.yml` suites step has `id: suites`,
keeps the exit code, writes `sha` (`land-base.sh rev`) and `digest` (`LANE digest=` line of `fw checks --tier remote`) and a final
step named `lane: sha=.. digest=..`; the adapter reads that name from `gh run view --json jobs`.

TS stand-ins (glue around the Lean verdict, no decision): `normalizeGithub`, `awaitRemote`, `runTiered`, `tieredChecks`.

Open / follow-ups: (1) CircleCI adapter is a stub (`circleciAdapter`, always unavailable) until circleci-pilot lands
`scripts/circleci.mjs`; it must emit the same `lane: sha=.. digest=..` binding and map to `LaneRun`. (2) The routing feed for
`allow` (default `["github"]`). (3) `land-remote.test.ts` takes ~2-4 min (one fwcore spawn per case); batch them if it hurts.
(4) The fallback (locked) protocol and the card fast-forward stay all-local. Queue stays serial.
Read first: `lean/Fw/Console/LandRemote.lean`, `apps/runner/src/land-remote.ts`, `docs/team/tools/land.md`.
