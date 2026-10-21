# Codemagic pilot

One cell of the `webkit-sim` lane (`sim (original, 430, 1, <sha>, v1)`: Simulator boot, Safari, `ios_webkit_debug_proxy`, one determinism session of two passes) on a Codemagic Mac mini M2 with the Xcode 27 image, side by side with its GitHub twin. Task `codemagic-pilot`; results and the recommendation: `research/notes/2026/10-2x-codemagic-pilot.md`. Counts and verdicts only: nothing measured on Codemagic is phone time.

## What is built

| Piece | File |
|---|---|
| The workflow: one `webkit-sim` workflow, `mac_mini_m2`, Xcode 27.0, `max_build_duration: 40`, no `triggering` block (a push starts nothing) | `codemagic.yaml` (repo root) |
| Trigger, wait, fetch, compare, ledger, check, dry run | `scripts/codemagic.mjs` (`node scripts/codemagic.mjs <sub>`) |
| The minutes rule, the billed-minutes rounding, the month key, the wait exit codes | `lean/Fw/Ci/Codemagic.lean`, golden `packages/contracts/golden/ci/codemagic.jsonl` (regenerate: `cd lean && lake env lean --run scripts/CodemagicGolden.lean`) |
| Tests, fake fetch, no network, no Keychain | `scripts/codemagic.test.mjs` (`node --test scripts/codemagic.test.mjs`) |

## Your setup (once, about 10 minutes)

1. Sign in at codemagic.io with GitHub (Personal plan: 500 Mac mini M2 minutes a month, 1 concurrent build, no card; the pricing page was checked 2026-10-21) and add this repository as an application. It needs no Workflow Editor config: the build reads `codemagic.yaml` from the branch.
2. Copy the application id (the part after `app_id=` in the builds URL).
3. Make a personal API token (Account settings, API token) and keep it in the Keychain without putting it on a command line: `security add-generic-password -s fw-codemagic-token -a fw -w` (it prompts for the token). Nothing else reads or stores it; it is sent only to `api.codemagic.io`.
4. Give the app id to the adapter: the environment variable `FW_CODEMAGIC_APP_ID`, or the gitignored file `.local/codemagic.json` `{"appId": "<id>"}`. The id is not secret, but it stays out of committed files.
5. Check with `node scripts/codemagic.mjs check` (one read-only call, `GET /apps`: the token works and the id is one of your apps; no minutes are spent).

## Commands

- Preview, no network and no token: `node scripts/codemagic.mjs dry-run` (or `trigger --dry`) prints the request with the token `<redacted>`, the app id masked, and the Lean decision for the ledger as it stands.
- Run: push the branch (`git branch -f ci/<task> HEAD`, then `git push origin ci/<task>`; the build reads the branch tip), then `node scripts/codemagic.mjs trigger --branch ci/<task>`. It prints the build id.
- Wait: `node scripts/codemagic.mjs wait --build ID --out DIR` polls every 120 s at most (never faster), exits 0 finished, 1 failed or timeout, 3 the wait ran out, 4 canceled or skipped, and fetches `build.json` (status, per-step seconds, minutes billed), `artifacts/` and the step logs the API names.
- Compare: `node scripts/codemagic.mjs compare --github DIR --codemagic DIR` reads `v1-session-1.md` (the class table) from both directories (the GitHub one from `gh run download <run> -n webkit-sim-v1`); exit 0 same classes in every row, 1 some rows differ, 2 not comparable.
- `node scripts/codemagic.mjs ledger` prints the minutes used this month.

## Rules the code applies (Lean `Fw.Ci.Codemagic`, replayed from the golden)

- Minutes: a build bills its start-to-finish time rounded up to a whole minute, at least one (`billedMin`; INFERRED, Codemagic's own rounding is not documented on the pages read). The ledger `.local/codemagic-ledger.json` holds one row per build with its UTC month; a build not yet fetched is a pending row at its cap and counts in full.
- Trigger: allowed only when `used(month) + cap <= 400` (of the 500 free), fewer than 3 pilot builds ever ran, and `cap <= 40`. Each refusal has its own theorem (`no_trigger_over`, `no_trigger_builds`, `no_trigger_cap`), `trigger_iff` says allowed means all three hold, `trigger_within_plan` says an allowed trigger never reaches 500, and `ledger_invariant` says that after a build that stays within its cap the month is still within 400. The adapter checks this before every trigger and exits 5 without a request when it refuses.
- The ledger lives in the checkout where the trigger ran (`.local/` is gitignored). Another checkout does not see it; copy the file or set the rule's inputs by hand before triggering from there.
- Status: `finished` exits 0; `failed` and `timeout` 1; `canceled` and `skipped` 4; every other status is "keep waiting".

## Limits

- The month boundary is UTC; Codemagic's billing month is not documented on the pages read (INFERRED). The 100-minute margin under the 400 line absorbs a day's difference.
- `GET /builds/:id` is not on docs.codemagic.io (it lists `POST /builds` and cancel only). The API answers HTTP 200 with the legacy camelCase shape `{application, build}` (`build.buildActions[]` with `startedAt`/`finishedAt` ISO strings, `build.artefacts[]`); the adapter also reads the v3 snake_case shape. The raw response carries the commit author and the repository's branch list, so it is never committed; `build.json` keeps only status, times, per-step seconds, billed minutes and artifact names (CONFIRMED by builds 1 to 3, research note).
- Image facts the builds showed: macOS 27.0 (26A428), Xcode 27.0, iOS 27.0 runtime 24A434 preinstalled (equal to the GitHub cell's pin), Node v26.8.2 as default (the yaml does not pin it), `ios_webkit_debug_proxy` installed by brew each build (41 to 76 s). `simctl openurl` timed out in 1 of 3 builds; the harness does not retry that call.
- Pilot result: 3 builds, 46 of 500 minutes (two finished at 22 and 19 billed minutes, one failed at 5).
- No wiring into `pool-fallback`: a follow-up the user approves.
