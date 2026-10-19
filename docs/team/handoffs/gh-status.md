# gh-status handoff

State: branch worktree-wf_237ada1b-128-1, GitHub platform status in `fw watch` and the console Health tab.

## Design
- Collect (I/O only): `apps/runner/src/watch-gh.ts` reads the githubstatus summary once per pass (10 s timeout, no
  auth, no retry, never throws). Keeps Actions, Pages, Webhooks and the open incidents touching them.
  `apps/runner/src/watch-collect.ts` puts it in `system.gh`; `watch.ts` feeds `prevDegraded` from the last logged
  output (`ghFlagged`).
- Decide (Lean): `lean/Fw/Obs/GhStatus.lean` (`ghOpenB`: opens on degraded, closes on operational, unknown keeps
  prev; theorems). `lean/Fw/Obs/Health.lean`: alert `sys.ghDegraded` (rank 18, later ranks +1), `ci.slow` detail gets
  the incident suffix during an open Actions incident (`ciSlowAlert_names`, `ciSlowAlert_plain`).
- Wire: `lean/Fw/Wire/Obs.lean` round trips for `gh` (`systemOf_systemJson` needs maxHeartbeats 4000000).
- Goldens: `packages/contracts/golden/obs/health.jsonl` (94 cases, 6 typed "gh-status:" cases).
- Serve and show: `apps/console-api/src/health.ts` (`gh` view; flag taken from fwcore's alert),
  `apps/console-web/src/Health.tsx` (`GhCard`, testid `gh-status`, link to https://www.githubstatus.com).

## Verified
- Runner (1135), console-api (420), console-web (11) full test scripts; `scripts/ci-paths.test.mjs` (40).
- Headless Chrome on a scratch console (port 47311, stopped): GitHub card shows three badges, the incident with
  ages, the link. Screenshot in the session scratchpad (health-gh.png).
- Fixtures: `apps/runner/test/fixtures/gh-status/` (operational; degraded = githubstatus.com/incidents/8tzbpcnl75jp captured 2026-10-19 ~16:30 UTC, trimmed to 4 components); fetch failure is in tests.
- Follow-ups (review): theorem states the "since" text exactly (ciSlowAlert_incident); since-time carries the date; `fw next` also fetches githubstatus (accepted, ≤ 10 s); runCore cases fail instead of skip on CI without fwcore; split systemOf_systemJson (maxHeartbeats 4000000).

## Open
- There is no `ci.queued` code in Lean; queued runs are `ci.slow` ("queued for N min"), which carries the incident.
- Polled per pass (300 s); only Actions, Pages, Webhooks; githubstatus outage reads as unknown.
- No component test for `GhCard` yet (console-api test covers the view).
