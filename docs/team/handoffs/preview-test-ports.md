# preview-test-ports handoff

State: branch worktree-wf_23953071-c84-1 @ 73e2d401 (plus lead docstring fix). Tests of PreviewManager no longer bind 47100-47139.

Done
- `lean/Fw/Console/Preview.lean`: the port base is a binder `lo`: `freePorts lo`, `admit lo`, `Reach lo`, `Inv lo`; theorems
  `reach_inv`, `live_le_K`, `ports_distinct`, `ports_in_range`, `inv_admit`, `inv_filter`, `admit_user`, `agent_*_admitted` keep their
  names and take `lo`; docstring math carries `b`. `portLo = 47100` stays the single production default.
- `lean/Fw/Wire/Console.lean`: `console.previewAdmit` takes optional `portBase` (default `portLo`) and returns `portLo`, `portN`.
  Count (`portN`) stays a constant, not a parameter (accepted limit).
- Golden: one new previewAdmit case (base 47300); regenerated `console.previewAdmit.jsonl`.
- `apps/console-api/src/preview/manager.ts`: 5th constructor arg `{ portBase? }`; omitted = Lean default. main.ts unchanged (production).
- `apps/console-api/test/preview.test.ts`: `TEST_BASE = 47300` passed everywhere; range assertion; new test that a manager without the
  option gets 47100/47101 (build hook throws, nothing binds) and that Lean reports portLo 47100, portN 40.

Verified: `lean/scripts/check.sh` green; vitest console-api 305/305 twice while 47100-47103 were held by the lead console.

Limits: 47300-47339 is a convention of the test, a foreign listener there would still fail; the tests choose it, never probe.
Read first: Preview.lean "The table, admission, ports" section.
