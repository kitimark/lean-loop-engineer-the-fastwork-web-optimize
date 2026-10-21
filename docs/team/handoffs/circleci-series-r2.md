# Handoff: circleci-series-r2

State: branch worktree-wf_22f9acfd-29a-2 (pushed as ci/circleci-series). Delivered: the read-only key check and the 40-pipeline series.
Read first: `research/notes/2026/10-21-circleci-series.md` (tables, meaning for ci-route and land-lane-circleci).

Verified: `sh lean/scripts/check.sh` green; `node --test scripts/circleci.test.mjs scripts/circleci-series.test.mjs scripts/ci-paths.test.mjs`.
MEASURED: pipelines 264 to 303 (20 per class, `arm.medium.gen2` even, `arm.large.gen2` odd), all success, billed credits 237 and 406.
Rows `results/circleci-series/rows/`, `summary.json`, GitHub baseline `github-runs.json` (unchanged, n=20).

Key check: Lean `Fw.Ci.Provider.keyVerdict`/`keyProceed` (theorems per branch), golden ops keyCheck/keyKind/checkoutStatus (regenerate:
`cd lean && lake env lean --run scripts/ProviderGolden.lean`), glue `keyCheck`/`readKeyList`/`readCloneResult` in `scripts/circleci.mjs`,
CLI `key-check` (exit 0/6/7) and the check inside `trigger` and `circleci-series.mjs run`. The key list answers 403 for our token, so the
check falls back to the newest finished `Checkout code` step. TS stand-ins: none for the key rule (golden-pinned); p95 is a TS
stand-in (Lean has p50 only).

Open: concurrency (30 per Arm class) and overflow under a busy GitHub pool are untested (the series ran one pipeline at a time);
that is land-lane-circleci's measure. One outlier (pipeline 300, chromium 178.8 s) unexplained.

Conventions: a fresh worktree needs `pnpm install --offline --frozen-lockfile` before `git push` (pre-push hook). The CircleCI slug is in an
API error message: never paste errors into files. `.local/circleci.json` was copied into this worktree (gitignored).
Writes outside the graph writes (needed by the task): lean/Fw/Ci/Provider.lean, lean/scripts/ProviderGolden.lean, packages/contracts/golden/ci/provider.jsonl, scripts/circleci-series.mjs, results/circleci-series/**, docs/team/handoffs/circleci-series.md. Follow-up: export runSeries and test that a missing/unknown key makes zero POSTs. Rerun: `node scripts/circleci-series.mjs run --branch ci/circleci-series --runs 20 --out <dir> --scratch <dir>`
(refuses past 40 rows, so use a fresh `--out`), then `insights`, `github`, `summary`.
