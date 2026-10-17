# Timings: every automation step as a span

`.fw-console/timings.jsonl` (main checkout, gitignored) holds one JSON line per timed step. Append-only; the writers
never fail or slow the step. The view `pnpm fw timings` is display only: whether a step is "slow" is decided later by
Lean (task timing-lean), not by this file or the TS quantiles.

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

No paths, no user names. The `fw land` total is the `fw` span with `step=land`.

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
