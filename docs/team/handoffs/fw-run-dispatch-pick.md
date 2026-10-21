# fw-run-dispatch-pick (with ci-push-probe-inputs): handoff

State: same branch and commit as docs/team/handoffs/ci-push-probe-inputs.md.

What changed
- `lean/Fw/Ci/Dispatch.lean`: `title nonce`, `validNonce` (8..32 of a-z0-9), `pick nonce rows` (found / absent / ambiguous / badNonce), theorems per branch plus `found_sound`, `found_unique`, `other_nonce_not_mine`, `push_not_mine`, `title_inj`. Golden `packages/contracts/golden/ci/dispatch.jsonl` (18 cases, same write flag as triggers).
- `apps/runner/src/run-pick.ts` is the TS stand-in for `pick` (replayed by `test/run-pick.test.ts`; not skipped by env). `run.ts` `runGate` for `--trajectory` sends `-f nonce=<n>`, lists `--event workflow_dispatch` runs, takes the exact title `trajectory-probe dispatch nonce=<n>`, then waits on that run id. Looks again every 120 s, 5 looks; ambiguous stops.
- Workflow input `nonce` and `run-name` in trajectory-probe.yml.

Not done (follow-up): `--gate` and the count lanes still use `latestRun` (their workflows have no `nonce` input); `fw run` without `--trajectory` keeps the old path. A fwcore op for `pick` would replace the TS stand-in.

Read first: `lean/Fw/Ci/Dispatch.lean` header, then `findDispatched` in `apps/runner/src/run.ts`.
