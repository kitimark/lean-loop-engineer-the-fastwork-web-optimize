# slot-renew-lease handoff

State: branch `worktree-wf_391e38a5-122-1`, work commit 142a741c, main merged after it.

Delivered (pinned unit: renew rule and prune rule):
- `lean/Fw/Sup/Adapt.lean`: `Entry.leaseS` (granted length, default 0), `grant`, `lenOf`, `renew` taking
  `Option Nat`, `expired`, `leaseOr`. Theorems `renew_keeps_len`, `renew_sets_len`, `grant_renew_keeps`,
  `renew_live` (now per entry: `0 < lenOf`), `expire_emits`, `expire_live_silent`, `prune_expired_split`,
  `grant_len`, `leaseOr_stored`, `leaseOr_legacy`.
- Goldens `packages/contracts/golden/sup/adapt.jsonl` (ops `adapt.expired`, `adapt.grant`, `adapt.leaseOr` added;
  every entry carries `leaseS`; B4 case "sim lease of 1800 s renewed after 1192 s with no length keeps 1800 s").
- `apps/runner/src/slot-core.ts` mirrors them; `slot.ts`: acquire builds holders with `grant`, `renew` without
  `--lease` passes null, `run` renews with null, `tick` logs one `expire` event per dropped holder (owner, token,
  leaseS, holdMs, lateMs), `readState` fills a missing `leaseS` from `leaseOr`.
- `apps/runner/test/slot.test.ts`: golden replay (22 ops) plus CLI tests for keep/set, legacy state, expire events.
- `docs/team/tools/slot.md`: Lease length, Expiry, events and limits.

Verified: `sh lean/scripts/check.sh` and `pnpm --filter @fw/runner test` through `fw slot run`; dry land.

Open (follow-ups, accepted limits):
- A holder whose process died keeps its slot until its lease ends.
- `fw watch` alerting on `expire` events; today the line only matches the shared lock-event shape (sup-report).
- The stale pid-less legacy sim lock directory (sim-first-queue follow-up).
- Queue tickets that lapse are dropped without an event (only holders log `expire`).

Read first: `docs/team/tools/slot.md`, then `Adapt.lean` section "Holders and leases".
