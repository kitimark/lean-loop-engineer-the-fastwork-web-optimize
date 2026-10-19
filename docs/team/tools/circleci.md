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

## Your setup (once, about 15 minutes; a fresh setup follows the same steps)

Status for this repository: steps 1 to 5 are done (project set up, definition id and slug in `.local/circleci.json`, token in the Keychain). Steps 6 and 7 are the checks to repeat on a fresh setup.

1. Sign in at circleci.com with GitHub and pick the Free plan. The repository is public: in Organization Settings, Plan, turn on "Free and Open Source" so the open-source pool (400,000 credits a month for Linux) applies.
2. Set up the project: Projects, Set Up Project, install the CircleCI GitHub App on this repository only. A GitHub App on a personal repository may be refused; if it is, stop and tell the lead.
3. In Project Setup, create the pipeline (config source: this repository, `.circleci/config.yml`) and copy two values: the project slug (`circleci/<uuid>/<uuid>` for a GitHub App project) and the pipeline definition ID. For `webkit-sim`, check that macOS jobs are enabled for the organisation.
4. Delete the default "All pushes" trigger of the pipeline. A push then makes no CircleCI pipeline; every pipeline comes from `pipeline/run` with `lane`. (If it stays, a push makes a `webhook` pipeline with no workflow; `wait --branch` skips those, but they still show in the dashboard.)
5. Make a personal API token (User Settings, Personal API Tokens) with a short expiry (a week covers a pilot) and keep it in the Keychain without putting it on a command line: `security add-generic-password -s fw-circleci-token -a fw -w` (it prompts for the token). Nothing else reads or stores it; it is sent to circleci.com and circle-artifacts.com only.
6. Write `.local/circleci.json` (gitignored): `{"slug": "<project slug>", "definitionId": "<pipeline definition id>"}`. The environment variables `FW_CIRCLECI_SLUG` and `FW_CIRCLECI_DEFINITION_ID` override it.
7. Check with `pnpm fw ci circleci dry-run` (no network) and one `trigger` of `premise-tests`.

## Commands

- Preview, no network and no token: `pnpm fw ci circleci dry-run` prints the exact requests (token `<redacted>`) and replays wait, fetch and compare over the fixtures. `... trigger --lane premise-tests --branch ci/x --dry` prints one trigger request.
- Run a pair: push the branch with a head commit message containing `[ci:premise-tests]` (`git branch -f ci/<task> HEAD`, then `git push origin ci/<task>`), then `pnpm fw ci circleci trigger --lane premise-tests --branch ci/<task> --class arm.medium.gen2` and `pnpm fw ci wait --provider circleci --pipeline <id> --out <dir>` (polls every 120 s or more, waits Retry-After on 429, writes `<dir>/run.json` and the artifacts). `wait --branch` skips pipelines with no `lane` parameter or no workflow (a push-made `webhook` pipeline). The GitHub twin: `pnpm fw ci wait --branch ci/<task>`, then `gh run view <id> --json databaseId,workflowName,headSha,createdAt,jobs > gh-run.json` once.
- Compare: `pnpm fw ci circleci compare --github gh-run.json --circleci <dir>/run.json`. Exit 0 no finding, 1 a verdict differs (a finding), 2 the two sides are not a pair. `compare` downloads the GitHub `premises-<engine>` artifacts itself (`gh run download`) and digests them. `pnpm fw ci circleci digest <dir>` prints a digest.
- Routing rule (not wired to any lane yet): `pnpm fw ci circleci route --lane L --platform linux-arm|macos --class C --est-ms N --credits-left N [--allow a,b] [--gh-degraded]` prints `github` or `circleci`.

## Rules the code applies (Lean `Fw.Ci.Provider`, replayed from the golden)

- Commit: the sha of a CircleCI run is `vcs.revision` of `GET /pipeline/{id}` (a job has none).
- Job names: the premise jobs match by exact GitHub name (`engine (chromium)`, `engine (playwright-webkit)`, `verdict`); `webkit-sim` matches a GitHub matrix name with the prefix `sim (original,` and the suffix `, v1)` (the real name is `sim (original, 430, 1, <sha>, v1)`). Only the first matching GitHub sim job is compared; the other breakpoints are not (accepted limit).
- Pair verdict: for `engine-chromium` and `engine-playwright-webkit` the verdict is the premise digest, not the step conclusion (the test step exits 0 even when a premise fails, so both conclusions are `pass`). A missing digest on either side is not a pair (exit 2). Other jobs: equal conclusions, and equal digests when both sides have one.
- Status maps: CircleCI status to conclusion (`success` pass, `failed` and the like fail, `canceled` cancelled) and GitHub conclusion to the same set, in Lean with goldens.
- Wait exit codes (Lean `waitStep`): 0 pass, 1 a job failed, 3 timeout, 4 no workflow or cancelled, 5 stop rule.
- Credits are minutes times the class rate, rounded up (`arm.medium.gen2` 6, `arm.large.gen2` 12, `m4pro.medium` 200 a minute). INFERRED: the `arm.*.gen2` names; `arm.medium` and `arm.large` are the documented fallback and are accepted by the config enums. Free classes only.
- Stop rule: a job reaches 1 h, a job waits more than 10 min in the queue, or storage passes 1 GB-month. Storage is counted from a ledger (`.local/circleci-ledger.json`, gitignored) of the cache, workspace and artifact bytes of every run fetched, each held 30 days (an upper bound). `fetch` and `wait` exit 5 and `wait` cancels the workflow.
- Routing: a lane goes to CircleCI only if it is allowlisted, on a free class of its own platform, the estimate fits the credits left, and (macOS only) GitHub Actions is degraded. The default allowlist is empty.
- Artifact downloads and list calls use the same path as every other call (429 and Retry-After handled) and follow `next_page_token`; a list that does not end fails loudly.

