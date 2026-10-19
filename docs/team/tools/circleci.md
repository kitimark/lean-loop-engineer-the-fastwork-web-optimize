# CircleCI pilot

A second runner for two GitHub lanes, run side by side with their GitHub twins so the verdicts, durations, queue times and credits can be compared. Background and capacity: `research/notes/2026/10-20-circleci-free-tier.md`. The decisions are Lean (`lean/Fw/Ci/Provider.lean`, golden `packages/contracts/golden/ci/provider.jsonl`); the glue is `scripts/circleci.mjs`. Counts and verdicts only: nothing measured on CircleCI is phone time.

## What is built

| Piece | File |
|---|---|
| Config: `premise-tests` (Linux Arm, `arm.medium.gen2` or `arm.large.gen2`) and `webkit-sim` (one job, `m4pro.medium`) | `.circleci/config.yml` |
| The steps, each timed in the `timings.jsonl` span format | `.circleci/job.sh`, `.circleci/node-install.sh` |
| Trigger, wait, fetch, compare, route, dry run | `scripts/circleci.mjs` (`pnpm fw ci circleci <sub>`, `pnpm fw ci wait --provider circleci`) |
| Lean verdicts replayed in JS | `scripts/circleci.test.mjs` (`node --test scripts/circleci.test.mjs`) |
| Recorded-shape API fixtures (synthetic until the first real run) | `scripts/circleci-fixtures/*.json` |

Both workflows run only when the pipeline parameter `lane` names them and the branch starts with `ci/`. A plain push to `ci/*` makes a pipeline with no workflow and spends no credit. Every job uploads the result files of its GitHub twin (`premises-<engine>/`, `premises-verdict.txt`; `runner.json`, `tools.txt`, `v1-session-1.*`) plus `timings.json` (spans: checkout, node, pnpm, cache restore, deps install, system libraries, browser install, test; the glue adds `queue`, `upload (after the last step)`, `job`). The only cache is the pnpm store; no Lake cache is saved.

## Your setup (once, about 15 minutes)

1. Sign in at circleci.com with GitHub and pick the Free plan. The repository is public, so the open-source pool (400,000 credits a month for Linux) applies.
2. Set up the project: Projects, Set Up Project, install the CircleCI GitHub App on this repository only. A GitHub App on a personal repository may be refused; if it is, stop and tell the lead (the pilot does not need a workaround).
3. In the project's settings, open Project Setup, create or open the pipeline (config source: this repository, `.circleci/config.yml`) and copy two values: the project slug (it reads like `circleci/<uuid>/<uuid>` for a GitHub App project) and the pipeline definition ID. For `webkit-sim`, check that macOS jobs are enabled for the organisation.
4. Make a personal API token (User Settings, Personal API Tokens) and keep it in the Keychain without putting it on a command line: `security add-generic-password -s fw-circleci-token -a "$USER" -w` (it prompts for the token). Nothing else reads or stores it.
5. Write `.local/circleci.json` (gitignored): `{"slug": "<project slug>", "definitionId": "<pipeline definition id>"}`. The environment variables `FW_CIRCLECI_SLUG` and `FW_CIRCLECI_DEFINITION_ID` override it.

## Commands

- Preview, no network and no token: `pnpm fw ci circleci dry-run` prints the exact requests (token `<redacted>`) and replays wait, fetch and compare over the fixtures. `... trigger --lane premise-tests --branch ci/x --dry` prints one trigger request.
- Run a pair: push the branch (`pnpm fw ci push --branch ci/<task> --lanes premise-tests`), then `pnpm fw ci circleci trigger --lane premise-tests --branch ci/<task> --class arm.medium.gen2` and `pnpm fw ci wait --provider circleci --branch ci/<task> --out <dir>` (polls every 120 s or more, waits Retry-After on 429, writes `<dir>/run.json` and the artifacts). The GitHub twin: `pnpm fw ci wait --branch ci/<task>`, then `gh run view <id> --json workflowName,headSha,createdAt,jobs > gh-run.json` once.
- Compare: `pnpm fw ci circleci compare --github gh-run.json --circleci <dir>/run.json`. Exit 0 no finding, 1 a verdict differs (a finding), 2 the two sides are not a pair. For the engine jobs add `"digestDirs": {"engine (chromium)": "<dir of the GitHub premises-chromium artifact>"}` to `gh-run.json`; `pnpm fw ci circleci digest <dir>` prints a digest.
- Routing rule (not wired to any lane yet): `pnpm fw ci circleci route --lane L --platform linux-arm|macos --class C --est-ms N --credits-left N [--allow a,b] [--gh-degraded]` prints `github` or `circleci`.

## Rules the code applies (Lean `Fw.Ci.Provider`)

- Pair verdict: equal conclusions and, when both sides have a digest, equal digests; otherwise a finding. A pair is the same job on the same commit, GitHub against CircleCI.
- Credits are minutes times the class rate, rounded up (`arm.medium.gen2` 6, `arm.large.gen2` 12, `m4pro.medium` 200 a minute; the rate table carries its source).
- The pilot stops when a job reaches 1 h, a job waits more than 10 min in the queue, or storage passes 1 GB-month. `wait` then cancels the workflow and exits 5.
- Routing: a lane goes to CircleCI only if it is allowlisted, on a free class of its own platform, the estimate fits the credits left, and (macOS only) GitHub Actions is degraded. The default allowlist is empty.

## Not verified yet (INFERRED until the first real run)

- The Xcode image name (`xcode` parameter, default `27.0.0`) and whether it carries iOS runtime build 24A434; `check-simulator.sh` fails the job fast when it does not, which is then the finding.
- The `pipeline/run` body, the `queued_at` and `created_at` fields of a job (queue is `queued_at` to `started_at`, so waiting for `requires` is not counted), and the `arm.*.gen2` classes being available to the organisation. The fixtures are synthetic, shaped after the API v2 reference; replace them with a recorded run.
- `.circleci/job.sh` and `node-install.sh` are checked for syntax only (`sh -n`); they have not run on a Linux or macOS CircleCI image.
- The GitHub-only guard job and the tip re-check are not ported: the API trigger names the branch, and the pilot is started by hand.
