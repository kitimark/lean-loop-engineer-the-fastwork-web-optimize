# Handoff: circleci-pilot

State: branch worktree-wf_24a09928-7f2-1, round 3 (final design round) done; see the last commit "circleci-pilot r3: ...". The Arm pairs ran at 9145de1d (pipelines 15, 16). The sim pair was re-run at 458c852e: CircleCI pipeline 45 against GitHub run 39332408753 (dispatch), verdicts equal, 307 s against 1700 s, 1025 credits. An earlier paired sim run at 430fecdf (pipeline 36, GitHub run 39327151744) is a FINDING: the CircleCI determinism session stalled (743 s without output), the job failed (exit 130), the GitHub twin passed. Cause not diagnosed.

Read first: `research/notes/2026/10-20-circleci-pilot.md` (table, step table, limits), `docs/team/tools/circleci.md`, then `lean/Fw/Ci/Provider.lean` (`compare`, `verdict`, `credits`, `stops`, `route`).

Verified: `sh lean/scripts/check.sh` green; `node --test scripts/circleci.test.mjs` (45) and `scripts/ci-paths.test.mjs`; `pnpm test` in apps/runner (tsc + vitest, land-inputs). Fixtures are real recordings: `webkit-sim.json` is pipeline 45, `webkit-sim-stall.json` pipeline 36 (token, UDID, account names removed).

TS stand-ins (each replayed from `packages/contracts/golden/ci/provider.jsonl`): `credits`, `storageMilli`, `compare`/`verdict`, `stops`, `route`, `waitStep`, `ofCircleStatus`, `ofGithubConclusion`, `ghMatches`, `classOfApi`. Glue with no Lean spec: the ledger `.local/circleci-ledger.json`, the artifact lookup of `timings.json`, `fixtureFetch`, the GitHub queue definition (run start to job start).

Conventions: token only from the Keychain (`fw-circleci-token`); slug and definition id in `.local/circleci.json`; polls >= 120 s; golden by `cd lean && lake env lean --run scripts/ProviderGolden.lean`. GitHub twin: `gh workflow run <lane>.yml --ref ci/<task>` (the push is skipped as unchanged; same practice as docs/team/tools/fw-ci.md). Block with `pnpm -s fw ci wait`, no sleep loops.

FINDING for the lead (stub drain): main's bootstrap `.circleci/config.yml` runs a `probe` job on every `ci/*` push. 33 webhook pipelines of other branches (3, 5, 8-13, 17, 19-34, 37-40, 42, 43, 46, 47; more since) each ran it, about 1 credit each (INFERRED), not pilot cost, and they keep coming. Landing this branch replaces the stub only for branches that merge main after the land. Deleting the "All pushes" trigger (circleci.md setup step 4) is a user-only step and is open.

FINDING for the lead (sim credits): the pilot's three sim pipelines spent 992 + 2756 + 1025 = 4773 credits (16 % of the 30,000 base pool, INFERRED); a stalled run costs 2756. A 10-run sim series is about a third of the monthly pool.

Open items (follow-up tasks already in the work graph): circleci-series (10 runs per class, spread, queue p50/p95), circleci-cache-accounting (ledger overcounts the pnpm cache: 108 milli per Arm pipeline, 222 after five pipelines, stop at 1000), circleci-sim-digest (class-table digest), circleci-insights-credits (billed values). Also: the stall of pipeline 36; other sim breakpoints (first GitHub sim job only); `route` unwired; `wait --branch` skips webhook pipelines only.
- Writes outside the graph: none. work-graph.json untouched.
