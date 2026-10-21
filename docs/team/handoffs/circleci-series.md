# Handoff: circleci-series

State: branch worktree-wf_22f9acfd-29a-2 (pushed as ci/circleci-series, code at the first commit). The CircleCI series did NOT run:
pipelines 261 and 262 (arm.medium.gen2) failed in `Checkout code` ("checkout key has zero length", git clone permission denied).
Read first: `research/notes/2026/10-20-circleci-series.md`.

Verified: `node --test scripts/circleci-series.test.mjs scripts/circleci.test.mjs scripts/ci-paths.test.mjs` (106 pass). The GitHub
baseline (20 runs, ubuntu-24.04-arm) is in `results/circleci-series/github-runs.json` and `summary.json` (MEASURED).

Blocker (user step): the CircleCI project is a GitHub OAuth project with no usable checkout key since the push trigger was deleted
(it worked at 17:35 to 17:43 UTC on 2026-10-20, pipelines 254 to 256). Add a deploy key or user key in Project Settings, SSH Keys.
I did not create one (it adds a deploy key to the GitHub repository). `GET /project/{slug}/checkout-key` answers 403.

Resume: delete `results/circleci-series/rows/p00261.json` and `p00262.json` (or run 9 per class), then
`node scripts/circleci-series.mjs run --branch ci/circleci-series --runs 10 --out results/circleci-series --scratch <dir> --config-root <main checkout>`,
then `insights`, `github`, `summary` (same script), then replace the "NOT delivered" section of the note with the tables. The driver:
sequential, medium then large per index, 120 s polls, refuses past 30 rows, stops after 3 failed pipelines in a row, `--adopt N`
takes an already started pipeline as run 1.

Conventions: p50/p95 are nearest rank (ceil(pct n / 100)-th smallest), p95 at n = 10 is the max; TS stand-in for p95 (Lean has p50
only, `Fw.Obs.Timing.p50`), pinned by tests to the Lean `#guard` values. Rows hold the pipeline number only; ids live in
`.local/circleci-series-ids.json`. Pitfalls: `pnpm fw` needs `pnpm install` in a fresh worktree (I ran `node scripts/...` directly);
an error message of the API holds the project slug, so never paste it into a file.

Writes outside the graph writes: none. Budget used: 2 of 30 runs, about 4 credits (INFERRED).
