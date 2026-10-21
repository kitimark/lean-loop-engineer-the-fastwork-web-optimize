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
| `fw slot renew --token t [--lease s]` | extends the lease of your own live slot | 1 when it expired or is not yours |
| `fw slot release --token t` | frees your slot | 0 |
| `fw slot status [--json]` | current limit, sample, holders, queue | 0 |
| `fw slot sim [--apply]` | the Simulator action; `--apply` shuts down booted `fw-*` devices when it says shutdown | 0 |

Kinds: `check`, `test`, `land`, `sim`, `other`. `--owner o` (default `FW_SLOT_OWNER`, else the worktree's
directory name) names the holder. Typical lines:

```sh
pnpm -s fw slot run --kind check --cache -- sh lean/scripts/check.sh
pnpm -s fw slot run --kind test --cache -- pnpm --filter @fw/runner test
pnpm -s fw slot run --kind land --cache -- pnpm -s fw land <branch> --task <id> --dry
t=$(pnpm -s fw slot acquire --kind sim --lease 1800)   # then: fw slot renew --token "$t"; fw slot release --token "$t"
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
- **Lean workers.** A check gets as many Lean workers as fit the free room, at least 1 and at most the online cores.
  `run` exports them as `LEAN_NUM_THREADS` and `LAKE_SLOT_CORES`.
- **Holders.** A holder is an owner, a token and a lease, never a process id. A live lease is never recovered as stale
  (`live_never_recovered`). Only the same owner and token renew or release it. `run` renews every 20 s.
- **Simulator.** Only the owner of a live `sim` slot may boot it (`simBoot`). `fw slot sim` keeps a booted `fw-*`
  device while a live sim slot or the old `.local/locks/sim` lock exists. Once 600 s have passed with neither, it
  shuts the device down.
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
- Events: `acquire`, `refuse` and `release` lines with `lock: "slot"` go to `<main>/.fw-console/locks.jsonl`
  (`FW_LOCK_EVENTS=off` or CI turns them off).
- Nested runs: `run` sets `FW_SLOT_HELD=1`, and a `fw slot run` inside it runs at once.
- `lean/scripts/check.sh` still takes `scripts/heavy-lock.mjs` inside the slot, so both gates apply until
  heavy-lock is retired into the slot.

## Limits

- Footprints and thresholds come from one MEASURED busy window and are initial values.
- `scripts/sim-lock.sh` callers outside this task still use the old lock. `fw slot sim` respects it.
- `fw slot sim --apply` is not yet run by `fw watch`.
