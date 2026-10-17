# fw ci

`fw ci [<run id>] [--workflow chromium-counts] [--branch main] [--store <dir>]` pulls a finished CI run into the artifact store.
No run id: the latest run of the workflow on the branch. The store is `$FW_CONSOLE_DIR/store` (default `.fw-console/store`) unless `--store`.

- Every gh call (list, view, download; also `fw run` and `fw watch`) goes through `ghCharged` (`@fw/gh-budget`): fwcore's `ci.budget.*` decides
  whether gh runs, and a wait or stop means gh is not started. `fw ci` and `fw run` sleep through a wait; a stop throws (exit 1).
- Downloads only `chromium-counts-*` and `chromium-classes` (not the image or fwcore artifacts) with `gh run download`.
- One store key per target in the run (a `both` run files two keys). fwcore `store.manifest` validates and keys it: target, preset, profile,
  git sha, image. Profile and image come from the shards (`counts.json`, `image-id.txt`); preset and flags from the rewrite query.
- Entries per key: `r<n>/*` (the shards of that target), `classes/*` (chromium-classes/<target>), `ci.json` (run id, head sha, conclusion).
- Refuses (exit 2, nothing stored): other workflow, run not completed or not success, a shard job that failed, a missing shard artifact
  or classes dir, shards that disagree on profile, query, target or image.
- Idempotent: the same run again prints `unchanged` and writes nothing. A different run with an already-stored key is refused, not overwritten.
- TS stand-in (Lean op `store.ciRun` wanted): `selectCiRun`, `searchConfig` in `apps/runner/src/ci.ts`; table tests in `apps/runner/test/ci.test.ts`.
- Chromium only; WebKit waits for webkit-green.

## Waiting for CI: `fw ci wait`, `fw ci budget`

- `pnpm fw ci wait <runId>` or `pnpm fw ci wait --branch ci/<task> [--workflow <name>] [--sha S] [--since EPOCH] [--timeout S]`.
  Blocks on the shared poller's local file (0 GitHub calls of its own, however many waiters), follows the NEWEST run per workflow on the
  branch, prints `run <id> <workflow> <conclusion>`. Exit 0 every decisive run succeeded, 1 a run failed, 3 timeout (default 540 s) or the
  poller stopped (call it again), 2 gh could not find the run, 64 usage. Run it in the background; do not loop.
- `pnpm fw ci budget [--json|--resume|--probe]` shows the request budget (0 requests; `--probe` is one charged call).
- Never `gh run watch`, never a gh loop, never `gh api`. `fw run` waits the same way: after a dispatch it waits for the newest run of the
  workflow created after the previous newest one (a branch wait), and for `--from-run` a run wait; it throws when the run fails.
- Tests: `apps/runner/test/run-budget.test.ts` (fake gh of `packages/gh-budget`): 1 vs 10 waiters make the same gh calls; no gh call is made
  while the budget says wait or stop.
