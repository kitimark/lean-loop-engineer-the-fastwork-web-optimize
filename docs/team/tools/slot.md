# fw slot: one queue for heavy local work

`pnpm -s fw slot` admits Lean checks, package tests, dry lands and Simulator work one queue at a time. The number of
jobs it admits follows the machine's load and memory.
- Spec and proofs: `lean/Fw/Sup/Adapt.lean`.
- TS stand-in: `apps/runner/src/slot-core.ts` (each function mirrors the Lean definition of the same name).
- Glue: `apps/runner/src/slot.ts`, which holds the probe, the state file, the child process group and the result cache.
- Golden vectors: `packages/contracts/golden/sup/adapt.jsonl` (`lean/Fw/Sup/AdaptGolden.lean`, checked by
  `lean/scripts/check.sh`), replayed by `apps/runner/test/slot.test.ts`.
- Inputs: the sup-baseline sampler, one busy window. MEASURED: the Simulator holds about 2.7 GB, one Lean compile
  650-770 MB, a runner test run up to 2.1 GB; memory runs out before CPU.

## Use

| Command | Does | Exit |
|---|---|---|
| `fw slot run --kind <k> [--cache] -- <cmd...>` | waits for a slot, runs `<cmd>` in its own process group, releases | the command's; 75 when refused |
| `fw slot acquire --kind <k> [--lease s] [--wait s] [--next s] [--json]` | holds a slot across tool calls; prints the token. For `measure`, also opens the measure window with its first pass due in `--next` s (default 0) | 0 admitted, 75 refused or `--wait` passed |
| `fw slot pass start --token t [--for s] [--wait s]` | the measure holder asks for an exclusive pass of `--for` s (default 1200); waits up to `--wait` s (default 300) for other holders to finish; prints `VERDICT start pass <till>`, `VERDICT wait pass` or `VERDICT gone pass` | 0 start, 75 wait, 1 gone |
| `fw slot pass stop --token t [--next s]` | ends the pass and opens a gap; the next pass is due in `--next` s | 1 when the lease is not yours or ended |
| `fw slot renew --token t [--lease s]` | extends your own live slot by its granted length, or by `s` (which becomes its length) | 1 when it expired or is not yours |
| `fw slot release --token t` | frees your slot | 0 |
| `fw slot status [--json]` | current limit, sample, measure window, holders, queue with each ticket's wait reason | 0 |
| `fw slot sim [--apply]` | the Simulator check now; `--apply` shuts down every booted device when it says shutdown | 0 |
| `fw slot held --kind <k>` | whether a live slot of kind `k` exists (used by `scripts/sim-lock.sh`) | 0 held, 3 free, other: check failed |
| `fw slot admit --kind build [--agents n]` | may the lead start one more builder or reviewer; prints `VERDICT admit build` or `VERDICT wait build`, the reason on stderr | 0 admit, 75 wait |

Kinds: `check`, `test`, `land`, `sim`, `measure`, `other`. `--owner o` (default `FW_SLOT_OWNER`, else the worktree's
directory name) names the holder. Examples:

```sh
pnpm -s fw slot run --kind check --cache -- sh lean/scripts/check.sh
pnpm -s fw slot run --kind test --cache -- pnpm --filter @fw/runner test
pnpm -s fw slot run --kind land --cache -- pnpm -s fw land <branch> --task <id> --dry
t=$(pnpm -s fw slot acquire --kind sim --lease 1800)   # then: fw slot renew --token "$t" (1800 s again); fw slot release --token "$t"
pnpm -s fw slot admit --kind build                       # lead, before spawning a builder
t=$(pnpm -s fw slot acquire --kind measure --lease 3600 --next 600)
pnpm -s fw slot pass start --token "$t" --for 900         # VERDICT start pass <till>; measure, then:
pnpm -s fw slot pass stop --token "$t" --next 600         # gap of 600 s; release at the end
```

## Decisions (Lean)

- **Available memory.** The probe reads `vm_stat` and `sysctl vm.vm_page_filecache_min
  kern.memorystatus_vm_pressure_level vm.swapusage` (macOS; elsewhere Node's free memory, pressure normal).
  `availMB` is free + speculative + purgeable pages plus the file cache above its minimum. Active and inactive pages
  are left out: they hold running processes' memory. The kernel's "free percentage" counts them
  (xnu osfmk/vm/vm_page.h:1528@f6217f8, osfmk/vm/vm_pageout.c:4732-4738@f6217f8), so in the lead's busy window
  (MEASURED) the old probe read 9994-11141 MB free while 217-2005 MB were available. The pageout daemon reclaims
  file pages only down to `vm_page_filecache_min` and then compresses process memory (vm_pageout.c:2211-2230,
  2620-2623@f6217f8), so file cache below the minimum adds nothing.
- **Memory low.** `memLow` holds when available memory is under the 1 GB floor, the kernel pressure level is not
  normal (1), pages leave for swap at 64 MB a minute or more (`swapActive`), or the compressor takes in at least
  1500 MB a minute (`thrash`). Both rates come from the `Compressions` and `Swapouts` counters and a mark in
  `<dir>/vm-mark.json`: new rates after 5 s or more, 0 after 600 s or a counter reset (`vmNext`); a mark without the
  swap fields counts as a first reading. Swap occupancy is not read: macOS keeps stale swapped pages, so on 2026-10-22 swap sat at 3,276 of 4,096 MB with 0 swap-outs in 30 s (MEASURED,
  incident `inc-slot-stall`). The 64 MB/min and 1500 MB/min thresholds are INFERRED until replayed on sampler data. A
  ticket admitted on a sample is still admitted when only its memory reading is better (`memLow_antitone`,
  `verdict_antitone`).
- **Idle head.** With no live holder, pressure level 1, no `thrash` and no `swapActive` (`idleHead`), the head of
  its kind is admitted even under `memLow` or a footprint that does not fit, unless an older ticket of another kind
  is starved or a sim ticket goes first (`idle_head_admitted`); waiting frees
  nothing then, since other programs hold the memory. Such an admit means no holder was live
  (`idle_head_only_when_empty`), and once it holds a slot no other ticket is admitted on the same reading
  (`idle_head_at_most_one`). With a live holder the verdict is the strict one (`verdict_unchanged_with_holder`).
  The 2026-10-22 stall (281 MB available, file cache 4,443 MB under its 4,608 MB minimum) admits one Lean worker
  with no holder and waits `memLow` with one (goldens).
- **Limit.** Each poll takes one sample and steps the limit `n`. It halves on overload: 1-min load at least 16,
  `memLow`, compressor at least 40 % of RAM, or swap growing at least 512 MB a minute. It adds 1 when the load is under
  8 with 3 GB available, and otherwise holds. A change waits 30 s after the last one, and `n` stays in 1..4. The
  growth signal never reads the swap ratio, since macOS swap stays high after a peak (`swap_static_never_trips`).
- **Admission.** A ticket waits while one of its kind is ahead (FIFO per kind). It also waits while a ticket of
  another kind has waited 300 s ahead of it and can run itself, while `n` slots are held, or while a Simulator slot is
  held and it asks for one. A Simulator ticket stuck behind a held Simulator slot never holds back other kinds
  (`verdict_not_older_of_sim_blocked`). It waits as `memLow` while memory is low, and an admitted ticket saw normal
  pressure, no `swapActive` and no `thrash`, and either the floor or no live holder (`admit_calm`). Otherwise it waits
  until the job's footprint fits above the 1 GB floor, unless it is the idle head (`admit_fits`).
  Footprints: check is 700 MB per Lean worker, test 1600, land 1500, sim 2800, measure 2800, other 1000. Holders admitted in the
  last 60 s are charged, since available memory does not show them yet. After 1800 s the verdict is timeout, and the job never runs (exit 75).
- **Simulator first.** A Simulator ticket never waits as `older` (`verdict_sim_never_older`). It waits as `drain`
  while more than one holder of another kind runs. A ticket of another kind waits as `simFirst` while a Simulator slot
  is held and another kind still runs, and while a Simulator ticket is pending unless a slot and the Simulator's
  2800 MB above the floor stay free after it starts. So every admission keeps "Simulator held implies at most one other
  holder" (`admit_keeps_simInv`). When another kind is admitted while a Simulator ticket is pending, the first
  Simulator ticket is still admitted on the same sample (`sim_not_starved`).
- **Old lock.** A live `.local/locks/sim` directory (no pid yet, or a live pid) counts as one Simulator holder
  (`withLegacy`): a sim ticket waits `simBusy` (`verdict_legacy_blocks_sim`). `sim-lock.sh acquire` takes its
  directory, asks `fw slot held --kind sim` under the slot's state lock, and gives the directory back while a slot sim
  holder is live. A failing check refuses the old lock; CI skips it (no slot there).
- **Lean workers.** A check gets as many Lean workers as fit the available room, at least 1 and at most the online
  cores; an admitted check's workers fit above the floor and the warming holders (`threads_fit`).
  `run` exports them as `LEAN_NUM_THREADS` and `LAKE_SLOT_CORES`.
- **Measure window** (`Fw.Sup.MeasureWindow`). A `measure` ticket is admitted like any other kind and opens one
  window: its owner, token, a pass end, the next pass's due time and a deadline 5400 s after the grant
  (`openAt_deadline`), fixed for the window's life (`deadline_fixed`). While a pass is live every other request waits
  as `pass` (`pass_live_waits`, `pass_live_no_admit`). A pass starts only when no other holder is live
  (`pass_start_quiet`), lasts at most 1200 s (`pass_start_bounded`), and `pass start` first sets the next due time to
  now, so no new gap job is admitted while it waits (`want_closes_gap`). In a gap a job is admitted only when the p90
  of its kind's last 20 local passing uncached `slot run` spans (at least 3) plus 30 s settle ends before the next
  pass, memory fits and the base verdict admits (`gap_admit`); then it ends before the pass when it runs no longer
  than that p90 (`gap_job_ends_before_pass`). Otherwise it waits as `gap` or, with too few spans, `unknown`. A second
  measure ticket waits as `measureBusy` (`gap_measure_waits`). After the deadline the window gives way to the base
  verdict (`after_deadline`), and the measure lease never runs past it (`capLease_within`). In a gap an older ticket
  of another kind still blocks as before (`window_keeps_older`).
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
  and below 8, and available memory covers the floor plus 2100 MB (`admitBuild_iff`). The count is `--agents n`, else the last line of `<main>/.fw-console/health.jsonl` (agents neither done nor gone), unknown when older than 900 s
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
- Events: `acquire`, `refuse`, `release`, `expire`, `pass-start`, `pass-refuse` and `pass-stop` lines with `lock: "slot"` go to `<main>/.fw-console/locks.jsonl`
  (`FW_LOCK_EVENTS=off` or CI turns them off). An `expire` line also carries `owner`, `token`, `leaseS`, `holdMs` (the
  span it held) and `lateMs` (how long after its lease end the poll dropped it).
- Nested runs: `run` sets `FW_SLOT_HELD=1`, `FW_SLOT_TOKEN=<its token>` and `FW_SLOT_OWNER` for its child. A `fw slot run`
  inside it skips the queue only when the state holds an entry that is live, of the same kind, and carries that owner and
  token (`nestedSkips` in `lean/Fw/Sup/Nested.lean`; `nestedSkips_iff`, `nestedSkips_none`, `nestedSkips_kind`,
  `nestedSkips_live`, `nestedSkips_of_live`, `nestedSkips_empty`; TS twin `nestedSkips` in `slot-core.ts`, facts read by
  `nestedHeld` in `slot.ts`, goldens `adapt.nested` in `adapt.jsonl`). Identity, not env presence: `FW_SLOT_HELD=1` with
  no token (a script started with the flag by hand), an expired or released token, another owner's token, and a held
  slot of another kind (a held `test` slot with a nested `land` request) all take their own slot.
  - Cause (incident `inc-slot-held-env`): the old rule skipped on any `FW_SLOT_HELD`. Of the 760 local `slot run land
    pnpm fw land dry` spans to cutoff 1792808775650 (timings.jsonl), 133 have no `slot` land `acquire` in locks.jsonl
    within 3 s of their start. COUNT (MEASURED, by time match: spans carry no caller): 114 of the 133 started within 60 s
    of a lead Bash call `FW_SLOT_HELD=1 sh .../land-rNNN.sh` in the lead session transcript, 122 within 10 min, so 11 to 19 came from other callers (agents' own `fw slot run` inside a held `acquire` shell
    or an env that inherited `FW_SLOT_HELD`). Not covered: callers outside `fw slot`, `scripts/slot-self.mjs` (it still
    runs directly on any `FW_SLOT_HELD`). 
- `lean/scripts/check.sh` still takes `scripts/heavy-lock.mjs` inside the slot; both gates apply until
  heavy-lock is retired.

## Limits

- Footprints and thresholds are initial values from one MEASURED busy window.
- A holder whose process died keeps its slot until its lease ends.
- `fw watch` does not alert on `expire` events yet.
- `scripts/sim-lock.sh` callers still use the old lock; it and the slot exclude each other.
- The Simulator check runs only while someone polls or releases a slot; `fw watch` does not run it yet.
- The idle shutdown covers every booted device, also one booted by hand without a slot or the old lock.
- `admit --kind build` is run by the lead by hand; `build-review.js` does not call it yet. Its thresholds (8 agents,
  2100 MB) are from the same window.
- The Simulator's own footprint is not reduced; sim priority only orders the other work around it.
- Gap admission trusts the p90 of past spans (INFERRED); a job that runs longer than its prediction can still overlap
  the pass, and the pass's own quiet check stays the guard. `acquire` holders that run no `slot run` have no spans,
  so their kind waits as `unknown` in a gap.
- `packages/measure-webkit/src/safari-local-lease.mjs` does not take a `measure` slot yet.

## Self-routing

- `lean/scripts/check.sh`, `lean:build` (root) and every package `test` script run `node scripts/slot-self.mjs <check|test> -- <cmd>`.
  The package scripts keep their old body as `test:run`.
- Not held: the helper itself runs `slot run --kind <kind> -- <cmd>` (apps/runner/src/slot-main.ts, in its own process) and waits in the queue.
- Held (`FW_SLOT_HELD` set, the nested rule above), on CI (`CI` set) or with `FW_SLOT_SELF=off`: the command runs
  directly, so a nested call starts at once and CI behaves as before. The helper decides nothing else (no Lean).
- Tests: `node --test scripts/slot-self.test.mjs`.
- Not covered: one-off `lake build <target>`,
  `lake env lean --run/--stdin`, `npx vitest`.
- A `fw slot acquire --kind sim` holder does not get `FW_SLOT_HELD` in its shell: export `FW_SLOT_HELD=1` before running a self-routing script (check.sh, a package `test`), or it queues behind its own slot.

## Light waiter

A queued run waits in one node process, not a tree (slot-waiter-light, MEASURED on this Mac, `ps -o rss` of the waiter's process group, node 24.22.0, one run each):

| waiter | processes | tree RSS |
|---|---|---|
| before, `slot-self.mjs` + `fw.ts slot run` | 2 | 168 MB |
| after, `slot-self.mjs` (waits itself) | 1 | 99 MB |
| before, `node fw.ts slot run` under `pnpm -s fw` | pnpm + 1 | 129 + 118 = 247 MB |
| after, `node fw.ts slot run` under `pnpm -s fw` | pnpm + 1 | 129 + 102 = 231 MB |

- One process only via `slot-self.mjs` (check.sh, package `test`), 99 MB. The typed form `pnpm -s fw slot run` stays pnpm + node (2 processes; 3 where the pnpm shim switches to the pinned pnpm, which the lead measured as 95 + 105 + 102 MB). It gains 16 MB of node RSS (118 to 102, MEASURED).
- `fw.ts` is a small entry: for `fw slot ...` it loads only `slot-main.ts`, for every other group it loads `fw-main.ts` (the old fw.ts body: contracts, land, ci, plan; the 120 MB part). `package.json` `fw` still starts `apps/runner/src/fw.ts`, so the Monitor command line `node apps/runner/src/fw.ts watch --interval 300 --stream` is unchanged.
- A bare node with TypeScript stripping is about 46 MB idle; the waiter is 99-102 MB. Not cut further (follow-up: a precompiled JS waiter). `manage-package-manager-versions=false` would remove the shim's nested pnpm and is not set here.
- Tests: `scripts/slot-self.test.mjs` (the waiter has no child and starts the command only after the holder releases; usage exits 64).

## Main's slot code

`fw slot ...` (apps/runner/src/fw.ts) and `scripts/slot-self.mjs` load `slot-main.ts` from the main checkout (the parent of the shared repo dir, see `apps/runner/src/slot.ts`), so a worktree on an older branch decides with main's slot code. They fall back to their own file when main's is missing or fails to import (for example a conflicted main checkout during a land merge). The Node pin guard and the Monitor line `node apps/runner/src/fw.ts watch --interval 300 --stream` are unchanged.
- Limits: a run already waiting keeps the code it loaded; main's code must stay compatible with older callers' `state.json` writes; a worktree cut before slot-main-code still runs its own slot code until it merges main; a branch that changes slot code tests it through the unit tests, since `fw slot` runs main's code.
- Test: `apps/runner/test/slot.test.ts` (fixture repo with a worktree). Incident: `inc-slot-branch-code`.

## Queue waits in timings

An acquire that waited writes `queue: {kind, waitMs, waits: [{why, ms}]}` on its span (`fw slot acquire`, `slot wait <kind>`); `waits` sums, per reason name, the ms between consecutive polls, using the `why` of the poll loop's own verdict (`apps/runner/src/slot-queue.ts` `addWait`; no owner, lease or tenure is read). The reason names are `Fw.Sup.Adapt.WhyTag`; `parseSamples` parses `waits` against that list and drops an unknown name (its ms stay in the judged remainder). Lean (`Fw.Obs.Timing.judgeQ`) decides: a sample with time under a holder reason (`holderWait`: every reason but `memory` and `memLow`) is judged on the remainder after that time only: `slow` when the remainder is slow, else `queued`; it never enters a window; wait time under `memory` or `memLow` stays judged. Whether a holder overstayed its lease is not judged on the waiter's span: it belongs to the expire events (task `timing-lease-overrun`). A refused acquire (`maxWaitS`, or `--wait`) carries no queue and is judged as any span, so a holder that never leaves still ends in a possible slow alert. Spans without `queue` keep their verdicts. Test: `apps/runner/test/slot-queue.test.ts`.
