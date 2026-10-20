# land-sha-pin handoff

State: branch worktree-wf_73319e74-c87-2, one commit on top of main.
- apps/runner/src/land.ts: the behind check (`merge-base --is-ancestor main sha`) and the scope diff (`main...sha`) now read the pinned `sha`; the render guard and every merge already did.
- apps/runner/test/land-sha-pin.test.ts: temp repo; the branch ref moves (a commit outside the task writes) during the task read after the pin; the land succeeds and main^2 is the pinned sha, without the late file.
- docs/team/tools/land.md accepted limits: names `hero.png.` (trailing dot) and a non-ASCII trailing space as guard gaps, and states the one-sha rule.

Verified: apps/runner `pnpm test` (tsc + vitest, 56 files, 1618 tests) green; ci-paths test run.
Open: the behind read follows the pin with no hook between them, so the test cannot move the ref between them; the behind change is by code (same sha variable). Not run against the old code to see the test fail.
Read first: land.ts lines ~539-575.
