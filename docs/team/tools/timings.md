# Timings: every automation step as a span

`.fw-console/timings.jsonl` (main checkout, gitignored) holds one JSON line per timed step. Append-only; the writers
never fail or slow the step. `pnpm fw timings` only displays; Lean decides whether a step is slow, not the TS quantiles.

## Line schema

| field | meaning |
|---|---|
| `tool` | `fw`, `fw land`, `lean/check`, or (CI) the workflow name |
| `step` | `fw`: group plus sub (`plan sync`, `ci wait`, `land`, `watch pass`); `fw land`: `merge`, `merge commit`, the argv of each derived check, `reconcile`, `verify`, `plan sync`, `worktree cleanup`; `lean/check`: stage name; CI: `<job>` or `<job>/<step>` |
| `startMs`, `durMs` | epoch ms of the start, duration in ms |
| `exit` | exit code (CI: 0 success/skipped, 1 other, null unknown) |
| `commit` | short sha of HEAD when the span ended (CI: the run's head sha) |
| `load` | 1-minute loadavg (0 for CI spans) |
| `host` | `local` or `ci` |
| `runId` | CI spans only: the GitHub run id (the dedupe key) |
| `skipped` | CI spans only: `true` when the job or step conclusion was `skipped` (written from 2026-10-22 on); absent otherwise |

No paths, no user names. The `fw land` total is the `fw` span with `step=land`.

### Step names of the `fw` tool (task run-span-split)
One name per cost, so no history pools unlike work:
- Every group with subcommands is `group sub` (`ci wait`, `polish plan`, `polish staged`, ...). The groups and subcommands are
  the table `SUBCOMMANDS` in `apps/runner/src/fw-groups.ts`, built only from the lists each module exports (`POLISH_VERBS`,
  `ORACLE_SUBS`, `CONSOLE_SUBS`, `SLOT_SUBS`, ...; the module's own dispatch uses the same list). `apps/runner/test/span-names.test.ts`
  parses the `usage: fw ...` text of `fw-main.ts` and fails when a group or an alternative it names is missing, or a key has no list.
- `fw run` writes `run plan` (arguments, the fwcore plan, the checks before the dispatch), then the three parts of the
  `gh workflow run` call: `run dispatch lock` (the wait for the shared gh-budget lock plus the fwcore decision),
  `run dispatch backoff` (the sleep after a budget wait; written only when it happened) and `run dispatch call` (the gh
  process); then `run wait` (the CI wait; carries `runId`) and `run file` (download and ingest), or `run dry` for `--dry`; there
  is no `run` span (`apps/runner/src/run-phases.ts`, names listed in Lean `Fw.Obs.Timing.runSteps`). The first span opens before the
  arguments are parsed, so a usage error still writes `run plan` (exit 1).
- `fw watch` writes `watch pass` and, when the pass made a gh call, `watch pass gh lock`, `watch pass gh call`,
  `watch pass gh backoff` (only when non-zero) and `watch pass other` (the rest), all starting with the pass
  (`passParts`, Lean `passSteps`). Each part is its own key, so a slow lock wait is judged against lock waits only.
- `fw ci state` writes `ci state` and, when it made a gh call, `ci state gh lock` (the wait for the lock), `ci state gh load` (the
  state-file read inside the lock), `ci state gh reserve` (the fwcore decision), `ci state gh call` (the gh process),
  `ci state gh backoff` (only when non-zero) and `ci state reduce` (the rest: parse and id search); every span carries the
  command's real exit (0 found, 2 not found) (`ciStateParts`, `recordStateParts`, Lean `ciStateSteps`). Without `--branch` or
  `--workflow` it reads one list of 100 runs and stops (Lean `Fw.Ci.StateList.step`).
- `fw slot` is `slot run <kind>`, `slot acquire <kind>`, `slot held <kind>`, `slot admit`, `slot status`, ... from both entries
  (`fw.ts` and `scripts/slot-self.mjs`, through `apps/runner/src/slot-span.ts`). A wrapped argv with `--dry` adds ` dry`
  (`slot run land dry`); a `--cache` replay ends as `... cached` (`slot run test cached`), apart from the real run.
- A dry land is `land dry` (tool `fw`), and its `fw land` spans carry a `dry ` prefix (`dry total`, `dry merge`, ...), so the 30 s
  ceiling of `fw land`/`total` judges real lands only.
Older lines keep the old names (`run`, `slot`, `land`, `total`); a new step starts its own history.

## Writers

- `apps/runner/src/timing.ts`: `span(tool, step, fn, exitOf?)`, `begin(tool, step)(exit)`. One O_APPEND write per line;
  HEAD and the main checkout are read from `.git` files (no spawn). Overhead 0.05 ms per span (MEASURED, 500 spans).
  Off under vitest unless `FW_TIMINGS_FILE` is set.
- `scripts/span.sh` (sourced by `lean/scripts/check.sh`): `span <tool> <step> <cmd...>`. Shell, not node, because a node
  wrapper adds ~40 ms start per stage and a perl clock 9 ms; two `date` spawns cost ~8 ms per step (MEASURED, loadavg ~10,
  a bit above the 5 ms goal; commit and load are read once per script). The command's exit status passes through.
- CI: `pnpm fw ci wait` reads the `run <id> ...` lines it printed, then fetches each finished run's jobs once through the
  gh-budget charged call (`gh run view <id> --json workflowName,headSha,jobs`) and writes one span per job and per step.
  A run id already in the file is skipped without a gh call. Not covered: the standalone poller seeing a run finish with
  no waiter (open item for timing-alert).
- Backfill: `pnpm fw timings --backfill [<runId>...] [--per 3]` (one charged `gh run list`, then one view per run).

## Reading it

`pnpm fw timings [--tool t] [--since hours]` prints per (tool, step): n, p50, p90 (nearest rank), last, max, sorted by
p90. Job spans contain their step spans, so compare within a level. Raw lines: `jq -c 'select(.step|test("sweeps"))'
.fw-console/timings.jsonl`.

## Slow-step alert
`fw watch` turns the latest slow sample per `<tool>/<step>` (Lean `Fw.Obs.Next.slowSteps`, from `Fw.Obs.Timing`) into
`timing.slow` and `NEXT investigate step=<tool/step>`; replay test: apps/runner/test/timing-alert.test.ts against
packages/contracts/golden/obs/timing.jsonl.

## Full runs only
A sample is judged only when it is a full run (Lean `Fw.Obs.Timing.fullRun`): not `skipped`, and `exit` 0 or unknown
(absent or null). Any other sample gets no verdict, never enters a window and never names a CI job of the auto stages;
`timingVerdicts_indep` proves the output equals the output on the full samples alone (up to input index), and
`judge_insert_other` that inserting such samples anywhere changes no verdict. `ciSpans` writes
`skipped`, `parseSamples` passes `exit` and `skipped` through.

MEASURED (`.fw-console/timings.jsonl`, 2026-10-22):
- land run 39722879593: the gate-engine and browser-suite steps of legs check-sh, suites-a and suites-b were skipped
  (0 s, an `if:` in `.github/workflows/land.yml`); they were written as exit-0 samples of 0 s. Keys are
  per leg, so they never shared a window with the chromium leg; its 33 s step is slow under both rules (median 21 s over
  the full steps), a real outlier, not this bug.
- local `fw land --dry`: early refusals (exit 1, 2, 12, 16; 12-256 ms) shared the window of full dry lands (19-32 s); the
  32.1 s dry land was slow against a median of 256 ms. Now it has 4 full runs before it and is `noBaseline`.
- replay of all CI step histories with the 0 s samples removed (INFERRED skipped: old lines have no conclusion): 39 slow
  verdicts over 15 keys turn ok (e.g. `gate-gaps/judge`, `webkit-sim/site`, `land/land (chromium)/fwcore build`).

Accepted limits: old lines keep their fields (no rewrite), so their skipped 0 s samples still count until they leave the
20-sample window; a step that runs and exits early with success counts as full (the collector sees only GitHub's
conclusion); a failed or cancelled run over a ceiling (the 30 s `fw land`) no longer alerts; thresholds unchanged.

## Contended samples and the heavy-job lock
A span recorded while the 1-min load average is above `Fw.Obs.Timing.contendedLoad` (8) has code `contended`: it is not
compared with the baseline, and it does not become the baseline (measured: the same step takes 1.5-2x longer at load 16-40
than below 4; props lint 16.8 s vs 22.7 s). `sys.contended` reports the load once. `lean/scripts/check.sh` runs inside
`scripts/heavy-lock.mjs` (Lean `Fw.Sched.Heavy`: a FIFO queue, at most `cap` holders, free memory for the job plus a reserve,
swap below 60 percent; an idle machine always admits). `FW_HEAVY_LOCK=off` skips it. The lock files are in `<git dir>/fw-heavy/`.

## Startup cost of the verb-list imports (MEASURED, Node 24.22.0, median of 5, `/usr/bin/time -l`)

| command | main wall | branch wall | main RSS | branch RSS |
|---|---|---|---|---|
| `fw plan show` | 0.16 s | 0.17 s | 123.9 MB | 123.7 MB |
| `fw slot status` | 0.16 s | 0.17 s | 123.6 MB | 122.4 MB |

The slot path (fw.ts -> node-guard.ts, timing.ts, slot-span.ts, slot.ts -> slot-core.ts, slot-main.ts) has a static import closure that does not contain fw-groups.ts or any of the modules it imports; its only verb list is SLOT_SUBS in slot-span.ts, which imports nothing.
