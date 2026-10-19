# land-wait handoff

State: branch worktree-wf_8d5d5644-4a5-1 (commits from a5ce619e on). `fw land` runs the Lean local tier here and waits for the
remote tier on the GitHub land lane; Lean `Fw.Console.LandRemote` decides. Not landed; the lead does the first real land.

Verified (runner `pnpm test` 1202 pass, `land-inputs`, `ci-paths` 40 pass, contracts, `lean/scripts/check.sh` green):
- Lean: sha + laneDigest binding, any provider's fail wins, explicit fallback (unavailable -> next provider -> run here); 22 theorems,
  golden `packages/contracts/golden/console/land-remote.jsonl` (32 lines) replayed through fwcore in `land-remote.test.ts`.
- Live (MEASURED): `ci/land-probe-30a307f` (run 39317802669) failed on a missing fixture and its step name bound it to the sha;
  `ci/land-probe-e5b7f17` (run 39319745028) passed with `lane: sha=e5b7f177.. digest=remote:..`. Both recorded in
  `apps/runner/test/fixtures/land-remote/{fail,pass}.json`. Nothing was landed.
- Local work before vs after: CPU time was NOT measured (a follow-up; the check pool would need a rusage wrapper and CLAUDE.md
  keeps Mac measurements out of results). Wall-time sum only: the median per-check wall time of the remote-tier checks over the
  last 20 land spans in `.fw-console/timings.jsonl` is about 609 s (checks run in parallel, so this is neither CPU nor the wall
  time saved). Left on the Mac: the local tier plus the evidence/fwcore build; the wait is one sleeping `fw ci wait` child.
- Round 2 (final design round) fixes: exit 3 -> running only on `timed out after` and the slice is slept out (fake-adapter test);
  `BIND_STEP` needs 40-hex sha + digest, lane step skipped when suites did not run, renamed-step test refuses; waiter detached
  and its group killed on abort; land.yml passes outputs by env; `scrub.mjs --range` runs before the push (hit = provider
  unavailable); fixtures lost `url`/`databaseId`. Live pass: see the line at the end of this file.

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

Live pass, round 2 (MEASURED): `ci/land-probe-r2-bd45639` run 39326507586 passed on the changed land.yml; its step reads
`lane: sha=bd4563917db3b81287dbc13e22b24a462673bb03 digest=remote:apps/runner,packages/engine-check` (the commit under test).
