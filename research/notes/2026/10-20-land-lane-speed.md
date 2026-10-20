# Land lane speed (task land-lane-speed, 2026-10-20)

Question: where does the wall time of a land go, and what can be cut on CI without moving a check back to this Mac? Status words: MEASURED
= read from a record (obs spans in `.fw-console/timings.jsonl`, `gh run view --json jobs`), INFERRED = reasoning over those records.

## 1. Per-phase table of today's lands (MEASURED, seconds)

`fw land total`, `local tier` and `remote push` are the spans of `.fw-console/timings.jsonl`; the other columns are the steps of the `land` job
of the run (`gh run view <id> --json jobs`). `lane` = run created to updated. `other` = fw land total - push - lane (work before the push and
after the lane ends). The local tier starts in the same second as the push, so it was never on the critical path (it is shorter than the lane).

| land (task) | run id | fw land total | local tier | push | lane | job queue | setup-lean | pnpm | fwcore build | suites | browser (install + suites) | other |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| preview-e2e r2 (failed lane) | 39338755874 | 529 | 36 | 5 | 422 | 115 | 39 | 8 | 23 | 89 | 139 | 102 |
| scrub-session-paths | 39340181287 | 164 | 12 | 4 | 127 | 20 | 39 | 5 | 23 | 32 | 0 | 33 |
| runner-bin-mode | 39340490277 | 180 | 17 | 4 | 143 | 21 | 51 | 8 | 21 | 31 | 0 | 33 |
| land-queue-why | 39340855802 | 406 | 46 | 5 | 314 | 20 | 38 | 5 | 22 | 84 | 129 | 87 |
| scrub-session-paths-r2 | 39341563550 | 171 | 12 | 5 | 126 | 16 | 38 | 5 | 23 | 36 | 0 | 40 |
| land-remote-fail-wins | 39342064962 | 423 | 31 | 5 | 340 | 16 | 39 | 4 | 24 | 91 | 151 | 78 |

preview-e2e r1 (39337463978, 244 s lane): queue 20, setup-lean 40, pnpm 4, fwcore 22, suites 5, browser 141 (no fw land spans recorded for it).

## 2. Top costs

| rank | cost | seconds (MEASURED) | on the critical path |
|---|---|---|---|
| 1 | the two browser engines, one after the other (gate-engine install + suite) | 129 to 151 when selected (chromium 44 to 52, webkit 90 to 136) | yes, serial after the suites |
| 2 | the remote suites, serial in one job | 84 to 91 when broad (runner 35, gh-budget 22, console-api 18, gate-breakpoints 11), 31 to 36 when narrow | yes |
| 3 | setup-lean: Lake cache restore (1350 MB) 24, toolchain install 14 | 38 to 51 | yes, every land |
| 4 | fwcore build | 21 to 24 | yes, every land |
| 5 | `other` (before the push, and from lane end to land done; includes the waiter's poll granularity) | 33 to 102 | yes, not touched here |
| 6 | job queue (free runner pool) | 16 to 21 usually; 115 and 395 s seen | exogenous |

Not costs (MEASURED): pnpm install 4 to 9 s (store cache); the gate-engine and Playwright install are already skipped when the browser suite is
not selected (0 s in the three runs without it); the local tier starts with the push (same second in `timings.jsonl`) and ends first.

## 3. The cut

One change: the lane job became a matrix of legs (Lean `Fw.Console.LandLegs`, golden `land-legs.jsonl`, matrix file `lean/land-legs.txt`).
INFERRED from the table: a leg pays the same setup (about 80 s) in parallel, so splitting a serial phase wins when the phase is longer than
the setup it does not repeat. The browser engines (129 to 151 s) clear that bar; the suites (84 to 91 s broad) clear it only as two halves of
about 45 s; a plan job in front (selection, then fan-out) would add one queue plus one setup hop to every land, so every leg selects for itself.

- `suites-a` (runner, gate-breakpoints, measure-chromium, engine-check, e2e-preview; about 51 s) and `suites-b` (console-api, gh-budget; about 40 s).
- `chromium` and `playwright-webkit` run the preview browser suite on their engine, only when the selection holds the e2e-preview check.
- Proved in Lean: the shards partition `remoteIds` (`shards_perm`, `shards_disjoint`, `suites_cover`); each engine leg runs iff the browser check is
  selected (`chromium_runs_of_selected`, `webkit_runs_of_selected`, `engines_idle_of_unselected`, `engineRuns_remote_pick`); the verdict over all
  legs is fail-wins (`legsOk_fail_wins`, `legsOk_all_pass`, `legsOk_empty`, `legsOk_iff`). TS only replays the goldens (`land-legs.test.ts`); the
  adapter vetoes a `success` run when a leg did not pass (`legsPass`, `console.landLegs`).
- Accepted limits: free runners only (four per land, the engine legs idle after setup when no browser suite is selected); the verdict stays
  fail-wins across jobs; no check moved to this Mac.

## 4. Before and after (MEASURED, same selection: the 7 remote checks and `browser=true`)

Probes pushed per `docs/team/tools/land.md` (`ci/land-lane-speed-*`, a merge commit on main with a `[ci:land]` marker). Same tree; "before" uses
main's `land.yml` (its suites step failed only because the new `land-legs.test.ts` checks the new workflow text: the timings are valid).

| run | id | lane wall | queue (first job) | longest job, queue excluded | note |
|---|---|---|---|---|---|
| before, old workflow (probe) | 39345070296 | 734 | 395 | 338 | runner pool congested at that moment |
| before, recorded earlier | 39342064962 | 340 | 16 | 324 | land-remote-fail-wins, same 7 checks |
| after 1 | 39343920706 | 238 | 15 | 222 (webkit leg) | webkit `compare/page-errors` check failed (see below) |
| after 2 | 39344448520 | 292 | 51 | 177 (webkit leg) | queues 51, 63, 115, 178 s: four runners requested at once |

Per leg, after (setup-lean + fwcore build + suites / install + browser, seconds):

| leg | run 39343920706 job run | run 39344448520 job run |
|---|---|---|
| suites-a | 121 (38 + 17 + 52) | 124 (38 + 19 + 54) |
| suites-b | 103 (37 + 17 + 38) | 101 (39 + 0 + 45) |
| chromium | 117 (40 + 20 + 44) | 123 (40 + 21 + 48) |
| playwright-webkit | 222 (51 + 19 + 136) | 177 (44 + 18 + 99) |

Result: the longest job fell from 324 and 338 s (serial) to 222 and 177 s (a cut of 34 to 48 percent, compute only). The lane wall fell from 340 to
238 s when the runner queue was short (15 s) and was 292 s when four runners queued for 51 to 178 s: the runner queue is exogenous and now a
bigger share, because the lane asks for four runners instead of one. One sample per variant; the webkit install time varied 78 s (cache miss)
to 27 s (hit), which moves the critical leg by 40 to 60 s.

## 5. Findings and follow-ups (below the pinned unit)

- Critical leg now: `playwright-webkit` = setup-lean 44 to 51 + fwcore 18 to 19 + gate-engine 27 to 78 + suite 58 to 72. A webkit apt/browser cache that
  main seeds (a ci/* branch only restores its own and the default branch's caches) would cut 40 to 50 s.
- WebKit Linux `compare/page-errors` (preview-e2e) flaked once: "2 cancels reported by Playwright (expect 0 or 13)", run 39343920706. The next run of
  the same tree passed. The check's tolerance (0 or 13) does not hold for 2: follow-up for the preview-e2e owner.
- `other` is 33 to 102 s per land and now the largest untouched phase: it holds `fw ci wait`'s poll granularity (>= 120 s polls by the gh rule) and
  the landing steps. Follow-up: read the lane's end from the poller's cached facts as soon as it appears.
- setup-lean 38 to 51 s on every leg: the Lake cache is 1350 MB and the exact key hits; caching the toolchain directory and restoring only the
  fwcore products (instead of the whole cache) would cut about 25 s, but changes the one-writer cache rules (`Fw.Ops.LakeCache`): own task.
