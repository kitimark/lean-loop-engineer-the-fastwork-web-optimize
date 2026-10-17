# ghb-lean: GitHub request budget in Lean (`Fw.Ci.Budget`, ops `ci.budget.*`)

**State:** done on branch `worktree-agent-ac9dc1dd62990a024` (commit: see `git log -1 -- lean/Fw/Ci`). Spec + proofs
`lean/Fw/Ci/Budget.lean`; wire `lean/Fw/Ci/Wire.lean` (ns `Fw.Wire.Ci`); goldens and fixtures `lean/Fw/Ci/Golden.lean` →
`packages/contracts/golden/ci-budget/{limits.json,wire.jsonl,fixtures/*.jsonl}`; replay `lean/FwTest/CiBudget.lean`.
Regenerate: `cd lean && lake test -- --write-ci-budget-golden`. Design: `research/notes/2026/10-18-gh-rate-budget.md`.

**Theorems:** (a) `window_bound`, `window_total`, `overrun_absorbed`, `register_free`, `tick_cost_indep_N`;
(b) `no_issue_when_exhausted`, `next_no_issue_when_exhausted`, `guard_persists`, `backoff_ge/mono`, `stop_after_fails`;
(c) `poll_live`, `next_wait_interval`, `wait_future`; (d) `interval_sound`, `oldRate_linear`, `per_agent_interval`;
`clock_monotone`. Changes vs the note: two shares per window (ticks 1800/h and 20/min, one-offs R = 1200/h and
R1 = 40/min); P uses `ceilDiv W (max 1 (share/c))` (the note's ⌈Wc/(B−R)⌉ is unsound: W=10, c=3, B−R=4).

**Wire (for ghb-glue).** Every request has `now` (epoch seconds) and an optional `state` (absent or null: fresh). Store
the returned `state` (one file, one writer) and pass it back. Limits are never restated in TS: read `limits.json` or
`ci.budget.limits`.
- `ci.budget.reserve {now,state?,cost}` / `ci.budget.next {now,state?}` → `{decision:"issue",kind,cost,state}` (next
  also gets `createdSince`: list runs `created>=` it) | `{decision:"wait",until,reason,state}` | `{decision:"stop",reason,state}`;
  reasons `failures idle tooBig retryAfter floor hour minute interval`.
- `ci.budget.observe {now,state,lines:[header lines of gh api --include],actual?}` → `{state,headers,actual}`. Call it
  after every issued call, 403/429 included; never retry a 403 yourself, ask `reserve`/`next` again.
- `ci.budget.step {now,state?,event}` with event `{register:{runId,createdAt}}|{unregister:runId}|{pages:n}|{resume:true}` → `{state}`.
- `ci.budget.status {now,state?}` → `{limits,used:{tick,oneoff:{hour,minute,hourCorrections,minuteCorrections}},
  interval,headroom,retryUntil,fails,watched,createdSince,state}`; `ci.budget.limits {}` → `{limits}`.
- State: `{now,ledger:[{time,cost,kind,charged}],remaining,reset,retryUntil,fails,etag,watched:[{runId,createdAt,
  lastCovered}],lastTick,pending:{kind,cost}|null,pages}`.

**Open:** a recorded trace `fixtures/recorded-1.jsonl` (format in `FwTest/CiBudget.lean`: `{"at","lines"}`
overrides after a scenario line) is replayed automatically once added. This is a proof model only. The glue
(`ghCharged`, the shared poller) is ghb-glue's task.
