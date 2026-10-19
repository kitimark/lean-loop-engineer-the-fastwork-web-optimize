# Handoff: circleci-pilot

State: branch worktree-wf_24a09928-7f2-1 (commits "circleci-pilot: ..."); the pilot is ready to run once the user finished `docs/team/tools/circleci.md` steps 1-5. No CircleCI call was ever made.

Read first: `docs/team/tools/circleci.md`, then `lean/Fw/Ci/Provider.lean` (module doc, `compare`, `stops`, `route`, `jobMap`).

Verified (local, no CI run):
- `sh lean/scripts/check.sh` green (new stage `provider golden check`); `node --test scripts/circleci.test.mjs scripts/ci-paths.test.mjs scripts/ci-push.test.mjs` pass; `pnpm test` in apps/runner passes (tsc + vitest, incl. land-inputs and ci-triggers, which now runs the circleci test).
- `circleci config validate .circleci/config.yml` valid, and it evaluates the `when` expressions (a misspelled operator fails).
- `pnpm fw ci circleci dry-run` renders the requests (token `<redacted>`) and replays wait, fetch and compare on the fixtures.

Not verified (INFERRED, listed in the tool doc): Xcode 27 image name, `pipeline/run` body, `queued_at` field, Gen 2 Arm availability, `.circleci/job.sh` and `node-install.sh` on a real image (syntax only, `sh -n`). Fixtures in `scripts/circleci-fixtures/` are synthetic; replace with a recorded run.

TS stand-ins (decisions replayed from the Lean golden, each row tested): `credits`, `storageMilli`, `compare`, `stops`, `route` in `scripts/circleci.mjs`. The price list, limits and job map are read from the golden, not copied. Glue without a Lean spec: status-to-conclusion maps (`circleConclusion`, `githubConclusion`), `premiseDigest`, artifact path check, the queue/upload span arithmetic.

Conventions: token only from the Keychain (`fw-circleci-token`) inside each request; slug and definition id in `.local/circleci.json` or `FW_CIRCLECI_*`, never committed; polls >= 120 s; Lean golden is generated (`cd lean && lake env lean --run scripts/ProviderGolden.lean`), never hand-edited.

Wiring: `apps/runner/src/fw.ts` spawns `scripts/circleci.mjs` for `fw ci circleci ...` and `fw ci wait --provider circleci`; reads declared in `apps/runner/src/land.ts` (PACKAGE_EXTRA_READS, apps/runner) and the test list in `apps/runner/test/ci-triggers.test.ts`.

Open items:
- After setup: `fw ci push`, `trigger` both lanes, 10 runs per class, `compare`; write the MEASURED note and the go/no-go (plan in `research/notes/2026/10-20-circleci-free-tier.md`).
- `fw ci wait` of one command for both providers (today two commands) and feeding the CircleCI spans into `.fw-console/timings.jsonl` (run.json carries them in the span format).
- Wire `route` into a lane only after the pilot; the allowlist is empty by default.
- Writes outside the graph: none (docs/team/work-graph.json untouched).
