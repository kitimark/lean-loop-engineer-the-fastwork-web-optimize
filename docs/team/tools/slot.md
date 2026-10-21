# fw slot: one queue for heavy local work

`pnpm -s fw slot` admits Lean checks, package tests, dry lands and Simulator work one queue at a time. The number of
jobs it admits rises and falls with the machine's load and memory.
- Spec and proofs: `lean/Fw/Sup/Adapt.lean`.
- TS stand-in: `apps/runner/src/slot-core.ts` (each function mirrors the Lean definition of the same name).
- Glue: `apps/runner/src/slot.ts`, which holds the probe, the state file, the child process group and the result cache.
- Golden vectors: `packages/contracts/golden/sup/adapt.jsonl` (`lean/Fw/Sup/AdaptGolden.lean`, checked by
  `lean/scripts/check.sh`), replayed by `apps/runner/test/slot.test.ts`.
- Inputs: the local load report (sup-baseline sampler, one busy window). MEASURED there: the Simulator holds about
  2.7 GB, one Lean compile 650-770 MB, a runner test run up to 2.1 GB, and memory runs out before CPU.

## Use

| Command | Does | Exit |
|---|---|---|
| `fw slot run --kind <k> [--cache] -- <cmd...>` | waits for a slot, runs `<cmd>` in its own process group, releases | the command's; 75 when refused |
| `fw slot acquire --kind <k> [--lease s] [--wait s] [--json]` | holds a slot across tool calls; prints the token | 0 admitted, 75 refused or `--wait` passed |
| `fw slot renew --token t [--lease s]` | extends your own live slot by its granted length, or by `s` (which becomes its length) | 1 when it expired or is not yours |
| `fw slot release --token t` | frees your slot | 0 |
| `fw slot status [--json]` | current limit, sample, holders, queue | 0 |
| `fw slot sim [--apply]` | the Simulator check now; `--apply` shuts down every booted device when it says shutdown | 0 |
| `fw slot held --kind <k>` | whether a live slot of kind `k` exists (used by `scripts/sim-lock.sh`) | 0 held, 3 free, other: check failed |
| `fw slot admit --kind build [--agents n]` | may the lead start one more builder or reviewer; prints `VERDICT admit build` or `VERDICT wait build`, the reason on stderr | 0 admit, 75 wait |

Kinds: `check`, `test`, `land`, `sim`, `other`. `--owner o` (default `FW_SLOT_OWNER`, else the worktree's
directory name) names the holder. Typical lines:

```sh
pnpm -s fw slot run --kind check --cache -- sh lean/scripts/check.sh
pnpm -s fw slot run --kind test --cache -- pnpm --filter @fw/runner test
pnpm -s fw slot run --kind land --cache -- pnpm -s fw land <branch> --task <id> --dry
t=$(pnpm -s fw slot acquire --kind sim --lease 1800)   # then: fw slot renew --token "$t" (1800 s again); fw slot release --token "$t"
pnpm -s fw slot admit --kind build                       # lead, before spawning a builder
```

## Decisions (Lean)

- **Limit.** Each poll takes one sample and steps the limit `n`. It halves on overload: 1-min load at least 16, free
  memory under 1 GB, compressor at least 40 % of RAM, or swap growing at least 512 MB a minute. It adds 1 when the
  load is under 8 with 3 GB free, and otherwise holds. A change waits 30 s after the last one, and `n` stays in 1..4.
  The swap ratio is never read: macOS swap stays high after a peak (`swap_static_never_trips`).
- **Admission.** A ticket waits while one of its kind is ahead (FIFO per kind). It also waits while a ticket of
  another kind has waited 300 s ahead of it and can run itself, while `n` slots are held, or while a Simulator slot is
  held and it asks for one. A Simulator ticket stuck behind a held Simulator slot never holds back other kinds
  (`verdict_not_older_of_sim_blocked`). Otherwise it waits until the job's footprint fits above the 1 GB floor.
  Footprints: check is 700 MB per Lean worker, test 1600, land 1500, sim 2800, other 1000. Holders admitted in the
  last 60 s are charged, since free memory does not show them yet. After 1800 s the verdict is timeout, and the job never runs (exit 75).
- **Simulator first.** A Simulator ticket never waits as `older` (`verdict_sim_never_older`). It waits as `drain`
  while more than one holder of another kind runs. A ticket of another kind waits as `simFirst` while a Simulator slot
  is held and another kind still runs, and while a Simulator ticket is pending unless a slot and the Simulator's
  2800 MB above the floor stay free after it starts. So every admission keeps "Simulator held implies at most one other
  holder" (`admit_keeps_simInv`). When another kind is admitted while a Simulator ticket is pending, the first
  Simulator ticket is still admitted on the same sample (`sim_not_starved`).
- **Old lock.** A live `.local/locks/sim` directory (no pid yet, or a live pid) counts as one Simulator holder
  (`withLegacy`): a sim ticket waits `simBusy` (`verdict_legacy_blocks_sim`). `sim-lock.sh acquire` takes its
  directory, asks `fw slot held --kind sim` under the slot's state lock, and gives the directory back while a slot sim
  holder is live. Either order of the two locks leaves one Simulator user. A failing check refuses the old lock; CI
  skips the check (no slot there).
- **Lean workers.** A check gets as many Lean workers as fit the free room, at least 1 and at most the online cores.
  `run` exports them as `LEAN_NUM_THREADS` and `LAKE_SLOT_CORES`.
- **Holders.** A holder is an owner, a token and a lease, never a process id. A live lease is never recovered as stale
  (`live_never_recovered`). Only the same owner and token renew or release it. `run` renews every 20 s.
- **Lease length.** A holder stores its granted length, `--lease` capped at 3600 s (`grant`). `renew` without
  `--lease` runs that length again from now and changes no holder's length (`renew_keeps_len`); `renew --lease s`
  sets the length to `s`, capped (`renew_sets_len`). A state entry written before the length was stored gets its whole
  span `till - since` (`leaseOr_legacy`).
- **Expiry.** Each acquire poll and `status` drop the holders whose lease ended. Each dropped holder yields exactly
  one `expire` event, and a live holder none (`expire_emits`, `expire_live_silent`).
- **Simulator.** Only the owner of a live `sim` slot may boot it (`simBoot`). The slot itself checks the booted
  devices (every device, not only `fw-*`) on each acquire poll and on each release, at most every 30 s machine-wide
  (`simDue`). The idle clock starts at the first check that sees a device booted with neither a live sim slot nor the
  old lock, and clears while either holds (`simIdleNext`). Once it has run 600 s, the check shuts every booted device
  down (`sim_shutdown_idle`); it never does so under a holder (`sim_shutdown_only_unheld`) or at a first sighting
  (`sim_first_sighting_keeps`). The decision and the shutdown run under the state lock.
- **Builder admission.** `admit --kind build` admits when no Simulator ticket is queued, the live-agent count is known
  and below 8, and free memory covers the floor plus 2100 MB (`admitBuild_iff`). The count is `--agents n`, else the
  last line of `<main>/.fw-console/health.jsonl` (agents neither done nor gone), unknown when older than 900 s
  (`agentsSeen`).
- **Stop.** On TERM or INT, `run` sends TERM to the child's group, then KILL after 5 s, and only while the leader's
  pid and start time are unchanged.
- **Result cache.** With `--cache` on a clean tree, the key is the kind, the exact argv, the HEAD tree hash and, for
  `land`, the `main` commit. A passing run is recorded when the tree is still clean and unchanged afterwards. The next
  run with the same key replays its stdout, stderr and exit code. Failures, dirty trees and a moved `main` (for land)
  run afresh (`cacheHit_same`, `cacheHit_dirty`). Records live in `<main>/.fw-console/review-cache/slot/`.

## Files and switches

- State: `<main>/.fw-console/slot/state.json`, written under a short `state.lock` directory. A lock whose writer died
  (pid and start time) is renamed to `state.lock.stale-<pid>` and then removed, so only one waiter recovers it; a lock
  that turns out live after the rename is moved back. `FW_SLOT_DIR` moves it.
- Events: `acquire`, `refuse`, `release` and `expire` lines with `lock: "slot"` go to `<main>/.fw-console/locks.jsonl`
  (`FW_LOCK_EVENTS=off` or CI turns them off). An `expire` line also carries `owner`, `token`, `leaseS`, `holdMs` (the
  span it held) and `lateMs` (how long after its lease end the poll dropped it).
- Nested runs: `run` sets `FW_SLOT_HELD=1`, and a `fw slot run` inside it runs at once.
- `lean/scripts/check.sh` still takes `scripts/heavy-lock.mjs` inside the slot, so both gates apply until
  heavy-lock is retired into the slot.

## Limits

- Footprints and thresholds come from one MEASURED busy window and are initial values.
- A holder whose process died keeps its slot until its lease ends.
- `fw watch` does not alert on `expire` events yet.
- `scripts/sim-lock.sh` callers outside this task still use the old lock; it and the slot exclude each other.
- The Simulator check runs only while someone polls or releases a slot; `fw watch` does not run it yet.
- The idle shutdown covers every booted device, also one booted by hand without a slot or the old lock.
- `admit --kind build` is run by the lead by hand; `build-review.js` does not call it yet. Its thresholds (8 agents,
  2100 MB) come from the same busy window.
- The Simulator's own footprint is not reduced; sim priority only orders the other work around it.
