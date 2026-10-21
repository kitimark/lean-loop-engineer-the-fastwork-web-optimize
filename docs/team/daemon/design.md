<!-- Moved from the lead scratch daemon-design/design.md on 2026-10-21 (sup-model and sup-fairness cite it). Correction: top MEM is phys_footprint, which already includes compressed memory (incident inc-footprint-correction); never add CMPRS to it. -->

# fw-sup: one Lean supervisor for every tool we start (design, 2026-10-21)

Inputs: inventory A (17 process kinds, 14 rules), feasibility B (Lean 4.35.0 @ eb6cafb probe), the
partial node-resources samples (`scratchpad/node-resources/startup.txt`, `analysis.txt`; its
`report.md` did not exist when this was written). Repo commit 617d55fd. Tags: MEASURED, CONFIRMED
(file:line), INFERRED.

## 1. Goal and non-goals

The user asked for one process that owns all resource use, manages it, tears down what is unused,
and is proved in Lean. What can be built:

- **One supervisor, not one OS process.** lean/lake, `lake serve` workers, vitest, Chromium, `gh`,
  `simctl` are separate executables (CONFIRMED, B Table 2). The daemon `fwsup` is a Lean binary that
  owns every child it starts, keeps one memory and CPU budget, and makes every lifecycle decision
  in one pure Lean step function. Only the Node-side tools (fw CLI commands, watch, ci waiters,
  gh-budget poller, land queue, hook logic) can truly collapse, into one supervised Node host
  plus thin clients (A, constraints).
- **Things it cannot own.** MCP servers (lean-lsp-mcp, Serena x2, chrome-devtools) are spawned by
  Claude Code over stdio; CoreSimulator is a launchd service (CONFIRMED, B Table 2). For these the
  daemon counts their footprint against the budget and, for an allowlist of kinds, stops idle
  ones by pid+start identity (as `fw reap` does today) or runs `simctl shutdown`.

What the user gets, per stage (numbers are targets to measure, INFERRED):

| Gain | Today | With fw-sup |
|---|---|---|
| Fewer process starts | ~62k hook Node starts/day + ~47 MB fwcore per guard ask; 1,097 `fw` calls/day each pnpm (0.46 s, 106 MB footprint) (MEASURED: A row 1-2, startup.txt) | hooks and `fw` become bare clients (0.03 s, 12 MB footprint MEASURED for `node -e 0`); fwcore ops run in the daemon, 0 extra starts |
| Shared warm servers | each one-shot fwcore boot re-reads an 82 MB binary; watch re-arm is cold every 30 min; 12 ci waiters = 12 pnpm+node pairs (A row 3-4) | one warm fwcore core, one watch collector, one poller; waiters are sockets, not processes |
| Idle teardown | no rule stops an idle live process; ~4.8 GB idle now (sim 3 GB, Serena 1.25 GB, lake serve 450 MB) (A, MEASURED parts) | idle grace per kind, priced by its cold-start cost; shed under memory pressure |
| One budget | heavy-lock, lake slots, poolFair, sim-lock each see one slice; poolFair ignores memory (A Table 2) | one ledger: declared cost of every lease + observed footprint of unowned processes |
| No orphans | reap covers removed worktrees only; a SIGKILLed console leaves previews running (A row 9-10) | every child has one owner record; restart re-adopts or reaps by pid+start identity |

Non-goals: putting MCP servers or CoreSimulator inside the daemon; a daemon on CI runners (CI
jobs keep their current shape); replacing Lake's own build parallelism; Unix-domain sockets in
stage 1 (Lean has none, B Table 1); any OS-level guarantee macOS cannot give (no subreaper, no
parent-death signal, no cgroups, B Table 4).

## 2. Architecture

```
 agents / lead / hooks                         one per machine (git common dir)
 ┌──────────────┐  line JSON over TCP   ┌─────────────────────────────────────────────┐
 │ fw (client)  │──127.0.0.1:port──────▶│ fwsup  (Lean binary)                        │
 │ hook client  │  bearer from 0600 file│  shell: TCP accept, SIGCHLD+tryWait, timers, │
 │ console-api  │◀─────────────────────│         ps/sysctl sample, spawn, kill FFI    │
 └──────────────┘   exactly one reply   │  core:  Fw.Sup.step (pure)                   │
                                        │  in-process: Fw.Serve.exec, all wire ops     │
                                        │  children: Node host, lake/lean, vitest,     │
                                        │            Chromium, gh, simctl, previews     │
                                        └─────────────────────────────────────────────┘
```

**The daemon.** A new exe `fwsup` in `lean/lakefile.toml` (next to the existing `[[lean_exe]]`
rows, CONFIRMED lakefile.toml:29-54), linking `Fw`. It does not extend the stdin loop of
`Fw.Serve` (single-threaded, one line per request, CONFIRMED Serve.lean:881-891); it reuses
`Fw.Serve.exec` and the wire dispatch as functions called in-process, so the console state and
every one-shot fwcore op (today spawned at run.ts:100, gh-budget core.ts:26, watch.ts:37,
spawn-guard.mjs:49, land-guard.mjs:28, CONFIRMED A) become requests to a warm process.

**Socket API.** Line-delimited JSON over 127.0.0.1 TCP (Std.Async.TCP, CONFIRMED B). Identity file
`<git-common-dir>/fw-sup/daemon.json` = {pid, start, port, token, commit, toolchain}, mode 0600,
written under an flock (`Handle.lock`, CONFIRMED B) so only one daemon per machine starts. The
client checks pid+start against `kill -0`/ps and the health reply, the pattern
`Fw.Console.Daemon.verified` already proves (Daemon.lean:64). Requests:

| Request | Reply (exactly one) | Notes |
|---|---|---|
| `request {kind, key, cost?, wait, holdMax}` | `granted {lease, endpoint?}` or `refused {why}` | blocks until ready or `wait` passes; `wait <= maxWait` |
| `release {lease}` | `released` | idempotent: an unknown lease replies `released` too |
| `renew {lease}` | `renewed {deadline}` or `refused` | renew count capped (closes Lease gap G4) |
| `op {name, json}` | the wire op's reply | fwcore ops in-process, no lease |
| `status` | resources, leases, budget, queue | read-only |
| `drain` | `draining` | stops grants; used by upgrade and shutdown |

Clients never name a pid. A signal can only target a resource id the daemon owns or an allowlisted
observed kind; this is the security boundary (section 6).

**Clients.**
- `fw` CLI: `package.json` script becomes a bin that runs node directly (pnpm wrapper costs 0.23 s
  and ~30 MB footprint per call, MEASURED startup.txt and A row 2). Stateless commands are sent as
  `op` or run by the Node host; long ones (`fw ci wait`) hold a socket instead of polling.
- Hooks: a bare client with no imports (Node bare start 0.03 s / 12 MB footprint MEASURED, vs 42-49
  MB + a 47 MB fwcore today). A Lean client binary importing only Lean.Json and TCP is the
  alternative; stage 2 measures both and keeps the smaller (INFERRED).
- console-api: stays Node + Hono (UI and HTTP). Stage 2 replaces its own fwcore child
  (console-api lean.ts:113) by `op` calls to the daemon, and the daemon supervises console-api as a
  child. The preview manager's children move under the daemon, so a console crash no longer
  orphans them.
- Agents' tools (lake build, check.sh, vitest, measure scripts): wrapped by `fw run --lease <kind>`,
  which requests a lease, runs the command as a daemon child in its own process group, and releases
  on exit.

**In-process vs children.**

| Service | Where | Why |
|---|---|---|
| fwcore wire ops, console state (`Fw.Serve.exec`), lease/slot/heavy/admit decisions, reap selection, health rules | in the daemon (Lean functions) | already Lean, pure |
| gh-budget poller loop, watch collector, land queue runner, ci waiter fan-out | one Node host child (stage 2); optional later port to Lean shell code | their I/O glue (gh JSON, git, ps parsing) is TS today; one Node process replaces up to 12 waiters + watch + runner (INFERRED) |
| lake build, `lake env lean --run`, vitest, node --test, tsc, Chromium, gh, git, simctl | owned children, `setsid` process group (CONFIRMED B Table 1) | separate executables |
| lake serve trees, Serena, other MCP, booted Simulator | observed, not owned | spawned by Claude Code or launchd |

**Worktrees share one daemon.** The key is `git rev-parse --git-common-dir`, the same for main and
every `.claude/worktrees/*` (INFERRED from git semantics). The daemon binary is built from `main`
only. A resource key includes the worktree root when its inputs differ per worktree (lake build,
lake serve root, test run) and the toolchain otherwise (fwcore ops, the Simulator device). So a
`lake build` in two worktrees is two leases under one budget, not one shared process; the honest
sharing win is the warm fwcore core, one poller, one watch, and one Node host, not shared Lean
elaboration across different sources.

## 3. The Lean model (`Fw.Sup.Core`)

Pattern: `Fw.Serve.exec : Srv → Cmd → Srv × Resp` with `run_eq_fold` (CONFIRMED Serve.lean:1-33)
and `Fw.Lease.step` (Lease.lean:57). New:

```
Fw.Sup.step : Cfg → State → Event → State × List Cmd
```

**State.**
- `res : List Res`, `Res = {id, kind, key, cost : Vec, phase, proc : Option Ident, lastUse,
  spawns : List Nat}` with `phase ∈ absent | starting (since) | ready | stopping (since, signal) |
  failed (until)`; `Ident = (pid, startSec)` as in `Fw.Ops.Reap`.
- `leases : List Lease`, `Lease = {id, owner : Ident (client process), res, deadline, renews}`.
- `pending : List Req` (FIFO with aging, `Fw.DeviceQueue` aging reused via `Fw.Sched.Admit`),
  `Req = {reqId, owner, kind, key, cost, deadline}`. A re-request after any refusal for cause, deadline included,
  keeps the original age (`ticket_age`, `deadline_keeps_ticket`).
- `obs : Sample` from the last tick: pressure level (1/2/4, sysctl
  `kern.memorystatus_vm_pressure_level`, CONFIRMED watch-collect.ts:529,725), footprint per owned
  ident, footprint of observed unowned processes, live client idents, load.
- `budget : Vec` (cores in tenths, RAM MB, as `Fw.Sched.Admit.Res`), `draining : Bool`, `now`.

**Events.** `request`, `release`, `renew`, `op` (pure, answered by the wire dispatch),
`spawned (rid, ident | error)`, `ready rid` (health probe passed), `childExit (ident, code)`
(crash = exit not preceded by our stop), `tick (now, sample)` (memory pressure and client death
arrive here), `clientGone owner` (socket closed), `restart (snapshot, psRows)` (daemon start with
the persisted state and a fresh ps sample), `drain`.

**Commands** the shell executes and nothing else: `spawn rid spec`, `signal ident sig` (TERM or
KILL; the shell re-reads start time before sending), `probe rid`, `reply reqId r`,
`revoke owner lease`, `simctl rid verb`, `persist snapshot`, `exit`.

**Charged cost.** `charge r = max r.cost (observed footprint r)`; `external = sum of observed
unowned footprints`; `room s = budget − external − Σ charge over live resources`. Footprint, not
ps RSS, because ps shows 0 MB for a compressed 320 MB lean server (MEASURED A).

**Theorems** (all over `Reachable cfg s`, the closure of `init`/`restart` under `step`):

| Name | Statement |
|---|---|
| `step_inv` | `Inv s → Inv (step c s e).1`; `Inv` bundles the facts below that are state properties |
| `spawn_fits` (budget) | `spawn rid _ ∈ (step c s e).2 → declared cost of all live resources in s' ≤ s.budget − s.obs.external` per dimension. The decision never admits beyond the budget. |
| `overrun_sheds` | if a tick sees `room < 0` or pressure ≥ warn, the step emits no `spawn` and no `granted`, and emits `signal TERM` for unleased resources in rank order (`charge / coldStart` ascending) until the projected room ≥ 0 or none are left. The OS footprint itself can grow between ticks; that is the accepted limit, not a theorem. |
| `owner_unique` (no orphans) | `∀ id ∈ liveIdents s, ∃! r ∈ s.res, r.proc = some id`, and `spawned_recorded`: every `spawn rid` in the output has `rid` in phase `starting` in s'; every `spawned (rid, id)` event sets `proc` on exactly that record. Relative to axiom S1 (only the shell spawns). |
| `recover_adopt_or_reap` | on `restart snap rows`: each record with `proc = some id` stays live iff `(id.pid, id.start) ∈ rows`, else becomes `absent` and its leases are revoked; each row picked by `Fw.Ops.Reap.reap` with no record gets the reap stop plan. |
| `signal_identity` | every `signal id _` in any output has `id` equal to the `proc` of a record in s or to a row of the same `restart`/`tick` event; never a bare pid. (Restates Reap's guard for the daemon.) |
| `stop_never_leased` | `signal _ _` or `simctl _ shutdown` for r → `leasesOn s r = []` |
| `stop_only_idle` | the same command → `now − r.lastUse ≥ grace r.kind ∨ shedding s ∨ s.draining`; with `grace` a `Cfg` table priced by cold-start cost (Simulator long, lake serve medium, vitest server short) |
| `grant_ready` | `reply q (granted l) ∈ out → (find s' l.res).phase = ready ∧ l ∈ s'.leases` |
| `reply_once` | over any trace: each `reqId` gets at most one `reply` across all outputs |
| `reply_by_deadline` | over any trace: if a `tick now` with `now ≥ q.deadline` follows request q, q has a reply by that tick; `q.deadline ≤ q.at + maxWait`. So every request is answered exactly once, within `maxWait` plus one tick period (tick period is a shell fact, axiom S4). A deadline refusal leaves the owner a ticket with q's age (`deadline_keeps_ticket`). |
| `fifo_no_overtake` | when a job q stays queued after a step, every grant of that step answers a request ahead of q, or has cost zero and is a nested job join or a share of a pinned-kind resource; `svc_respects_blocked` is its head-of-queue case, so a blocked head job holds back every svc grant on an unpinned resource |
| `head_job_granted_by` (fairness) | same proof scheme as `Fw.Sched.Admit.aged_admitted_by` (Admit.lean:1277), which cannot be instantiated (Admit has a fixed B, no eviction and no leases): a job at the head of the queue, with no older ticket and no older request behind it, q.age ≤ s.now, s not draining, and every stopping resource at s unpinned and stopped no later than s.now, is granted by `s.now + span + tickMax + K·(killAfter + 2·tickMax)`, K the unpinned resources, along traces with no drain, restart or owner loss, ticks at most `tickMax` apart that find no KILL outstanding, no shedding, and room for the job once leases, stopping and stoppable resources are gone. Phase 1: every lease ends by `s.now + span` and no new costly one lands (`svc_respects_blocked`); phase 2: each eviction round (TERM, KILL, exit) takes at most `killAfter + 2·tickMax` and stops a fresh resource. Accepted limits: head job only; a request at position k and svc progress are follow-ups. The single-step `aged_granted_by` grants the head job when it fits. |
| `expired_revoked` | a tick with `now ≥ l.deadline` removes l and emits exactly one `revoke l.owner l` |
| `exit_releases` (crash) | `childExit id` for r → `leasesOn s' r = []`, one `revoke` per prior lease, r ∈ `failed` or `absent` |
| `restart_bounded` | for every r and window `W = cfg.restartWindow`, spawns of r within W ≤ `cfg.maxRestarts` (OTP intensity, default 1 per 5 s per B Table 3); after that r is `failed until` and requests for it are refused |
| `client_gone_releases` | `clientGone o` (or a tick sample without o's ident) → no lease of o in s', its pending requests removed with no reply sent (no socket left) |
| `drain_quiet` | after `drain`, no `spawn` and no `granted`; leased resources get no signal; `exit` only when no lease is left or every lease expired |
| `run_eq_fold` | the shell's state after events e₁..eₙ is `foldl step`; the command log is the concatenation of step outputs. This is what the golden replay checks. |

Lean placement: `Fw.Sup.Core` (state, step), `Fw.Sup.Props` (theorems), `Fw.Wire.Sup`
(codecs, round-trip), goldens under `packages/contracts/golden/sup/`. Budget and fairness reuse
`Fw.Sched.Admit` (`admit_iff`, `within_budget` at Admit.lean:286,661), leases generalize
`Fw.Lease` (exclusive device = capacity-1 pool), reap reuses `Fw.Ops.Reap` (CONFIRMED). The
heavy-lock verdict (`Fw.Sched.Heavy`) becomes the cost table and pressure rule, removing the TS
stand-in `scripts/heavy-lock.mjs`.

## 4. What stays unproved, and how the shell stays thin

Unproved: TCP, the identity file and flock, `IO.Process.spawn`, the `kill(2)` FFI (5 lines of C;
`Child.kill` only sends SIGKILL, CONFIRMED+MEASURED B), SIGCHLD waiter + `tryWait` sweep, ps/sysctl
sampling, JSON persistence, the clock.

OS assumptions, written in prose in `docs/team/tools/fw-sup.md` and named in theorem docstrings,
never as Lean `axiom`:

- **S1** Only the shell spawns, and only on a `spawn` command (a child that forks its own children
  is covered by its process group, except S3).
- **S2** (pid, startSec) names one process: macOS does not reuse a pid within the same second for a
  new process (the same assumption `fw reap` makes, INFERRED).
- **S3** `killpg` reaches every group member that did not call `setsid`. lake serve file workers do
  (Watchdog.lean:846-847 @eb6cafb, CONFIRMED B); they are stopped by the tick's ps descent through
  recorded ppid chains, the reap backstop.
- **S4** A tick happens at least every `tickMax` seconds and the clock is monotone; the model clamps
  a backwards `now` to the last value.
- **S5** A child's exit is seen within one tick (SIGCHLD or the `tryWait` sweep).
- **S6** The ps/top sample is a snapshot good enough for identity (start time re-read before every
  signal).

Keeping the shell thin (closed design, allowlist):
- The shell is one function `exec : Cmd → IO (List Event)` with one match arm per `Cmd`
  constructor, plus the accept loop that turns bytes into `Event`. It holds no `if` on state; a
  lint in `lean/scripts/check.sh` fails if `Fw/Sup/Shell.lean` imports `Fw.Sup.Core` internals
  other than `step`, `Cmd`, `Event` (allowlist of names).
- Every event and every command is appended to `<git-common-dir>/fw-sup/events.jsonl`. `fwcore
  sup.replay` folds the events through `step` and compares the command stream byte for byte;
  `check.sh` replays the committed golden traces, and the daemon replays its own last log on start
  (a mismatch is a `sup.divergence` alert in watch).
- Golden traces come from three sources: synthetic (each theorem's boundary case), recorded from
  stage 0's extractor (heavy queue, lake-slot, sim-lock, reap.jsonl, timings.jsonl, health.jsonl),
  and recorded daemon logs once it runs (scrubbed of paths).

## 5. Staged migration

Every stage is landable alone, routed by `Fw.Sup.routeOf : Stage → Service → Route` (Lean, golden
vectors): when the daemon is absent or the stage is off, the client takes today's path. Resource
metrics are local by nature; they come from the existing watch health samples and the daemon's
own counters (a lane CI cannot run: this Mac's resources; to be named in work-graph.json). Each
stage compares 3 days before against 3 days after.

| Stage | Moves | Metric (target, INFERRED) | Rollback |
|---|---|---|---|
| 0 Model | `Fw.Sup.Core/Props/Wire`, trace extractor, `fwcore sup.sim` over recorded traces | no process change. Report: replayed decisions on 3.5 days of logs: predicted peak charge, idle MB-hours reclaimable, requests that would be refused | none needed |
| 1a Daemon + ops | `fwsup` exe, identity, TCP, kill FFI, events log; fwcore ops from `fw` CLI, gh-budget core, watch, guards as `op` | fwcore starts/day (counter; today 5 spawn sites, uncounted); `op` p50 latency must beat the 40 ms spawn (Turborepo lesson: measure the client first) | stage flag off; clients spawn fwcore as today |
| 1b Lake + leases | lake-slot, heavy-lock and sim-lock become daemon leases (flock files kept as fallback); `fw run --lease lake` for agents' direct `lake build` and check.sh; idle teardown of observed lake serve trees (allowlisted kind `lspServe`, idle from lean-lsp call times) | peak summed footprint of lean children; lake builds outside a lease (today: all direct agent builds); lake serve MB-hours idle | flag off; shell scripts fall back to flock |
| 2 Node host | one Node host child runs poller, watch collector, land queue runner; ci waiters become socket waits; console-api uses daemon `op` and is supervised; hooks use the bare client; `fw` bin without pnpm | long-lived Node processes (today up to 12 waiters + watch + runner + console); hook start footprint (12 vs 42-49 + 47 MB); watch re-arm cold passes → 0 | flag off per service; old entry points stay until stage 2 has run 7 days clean |
| 3 Test budget | vitest / node --test / tsc under `fw run --lease test`; land `poolFair` reads daemon room (memory too) | peak RSS during lands, load p90 (today 104, MEASURED A), inc-land-load-flake recurrences | flag off; poolFair as today |
| 4 Pools | Simulator lease with keep-warm while queued, `simctl shutdown` after grace; Chromium/Playwright pool per (hover, pointer) profile; previews under the daemon; Serena/MCP counted, idle alert | idle Simulator GB-hours (today ~3 GB for 19 h, MEASURED); boots/day × boot time (local boot cost not measured yet; measure first) | flag off; sim-lock.sh path |

The grace per kind needs warm-up costs that are not recorded today (lake serve cold start, local
Simulator boot, fwcore start in tests; A finding). Stage 0's report and a measurement task fill
them before stage 1b and 4 set defaults.

## 6. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Single point of failure | Every client keeps today's path behind `routeOf`; leases fall back to flock files; hooks fail the way they fail today when the daemon does not answer within their timeout |
| Daemon crash | Children run in their own process groups and survive; the next client starts the daemon (flock on the identity file); `restart` event re-adopts by pid+start or reaps (`recover_adopt_or_reap`); `restart_bounded` stops crash loops; a launchd agent is optional later (needs `ProcessType` set or CPU is throttled, CONFIRMED B Table 3) |
| Stale daemon after a toolchain bump or main commit | identity carries `commit` and `toolchain`; a client from a newer main sends `drain`; the old daemon persists its snapshot and exits without signalling leased children (`drain_quiet`); the new one adopts them through the same `restart` path, so every upgrade exercises crash recovery |
| Worktree isolation | daemon built from main only; per-worktree resources keyed by root; an agent developing `Fw.Sup` runs a sandbox instance (`--sandbox`: own identity dir, own children only, no adopt, no reap, no observed kinds) |
| Socket security | loopback only; bearer token in a 0600 file under the git common dir; the API takes resource ids, never pids; signals only to owned records or allowlisted observed kinds with identity re-check; same login rule as `Fw.Console.Daemon.login_loopback` (Daemon.lean:137) |
| Daemon overload at load 40+ | one event loop thread for the socket, the step runs in O(resources) per event (tens of records); Backoff (`Fw.Obs.Backoff`) stretches deadlines; ticks never block on ps (the sample runs as a child) |
| Model cost wrong | charge = max(declared, observed); `overrun_sheds` corrects within a tick; stage reports compare predicted vs measured peaks |
| Killing work an agent still needs | `stop_never_leased`; grace priced by cold-start cost; look-change of user-visible things (Simulator) goes through the user-visible "Your steps" path before stage 4 shutdowns are enabled |
| Scope creep into a Node rewrite | stage 2 keeps the TS glue in one host process; porting it to Lean is a later, separate decision |

## 7. Work-graph tasks

Style as `docs/team/work-graph.json` (`id, owner, stream, deps, writes`); `unit` = the unit the
reviewer decides on.

| id | owner | deps | writes | unit |
|---|---|---|---|---|
| sup-plan | plan-editor | - | docs/plan/PLAN.md, docs/team/work-graph.json | the PLAN §3.2 row and the task rows, each on its own |
| sup-baseline | measure-engineer | - | apps/runner/src/watch-collect.ts (per-kind process count + footprint), research/notes/2026/10-2x-sup-baseline.md, docs/team/handoffs/sup-baseline.md | each metric of section 5 with its 3-day baseline |
| sup-warmup | measure-engineer | - | research/notes/2026/10-2x-warmup-costs.md | each cold-start number (lake serve, local sim boot, fwcore in tests) on its own |
| sup-model | lean-prover | - | lean/Fw/Sup/Core.lean, lean/Fw/Sup/Props.lean, lean/Fw.lean, docs/team/handoffs/sup-model.md | each theorem of section 3 on its own |
| sup-wire | lean-prover | sup-model | lean/Fw/Wire/Sup.lean, packages/contracts/golden/sup/*.jsonl | round-trip per message type |
| sup-trace-extract | console-builder | sup-wire | apps/runner/src/sup-trace.ts, apps/runner/test/sup-trace.test.ts | each source log mapped to events |
| sup-sim | lean-prover | sup-wire, sup-trace-extract, sup-baseline | lean/Fw/Sup/Sim.lean, research/notes/2026/10-2x-sup-sim.md | the stage-0 report numbers |
| sup-kill-ffi | lean-prover | - | lean/ffi/sup_signal.c, lean/lakefile.toml, lean/Fw/Sup/Signal.lean | TERM/KILL/kill-0 on an identity-checked pid |
| sup-shell | lean-prover | sup-wire, sup-kill-ffi | lean/Fw/Sup/Shell.lean, lean/SupMain.lean, lean/lakefile.toml, lean/scripts/check.sh (shell lint + replay), docs/team/tools/fw-sup.md | the shell allowlist lint and the golden replay |
| sup-route | lean-prover | sup-model | lean/Fw/Sup/Route.lean, packages/contracts/golden/sup/route.jsonl | `routeOf` per (stage, service) |
| sup-client | console-builder | sup-shell, sup-route | apps/runner/src/sup-client.ts, apps/runner/src/run.ts, packages/gh-budget/src/core.ts, apps/runner/src/watch.ts | stage 1a: each fwcore call site routed with fallback |
| sup-leases | console-builder | sup-client | scripts/lake-slot-lib.sh, scripts/heavy-lock.mjs (removed), scripts/sim-lock.sh, apps/runner/src/fw-run-lease.ts | stage 1b: each lease kind with flock fallback |
| sup-lsp-idle | lean-prover | sup-model, sup-warmup | lean/Fw/Ops/Reap.lean (idle branch), apps/runner/src/reap.ts | stage 1b: idle lake serve stop, identity theorem |
| sup-host | console-builder | sup-client | apps/runner/src/sup-host.ts, packages/gh-budget/src/wait.ts, apps/runner/src/land.ts, apps/console-api/src/core/lean.ts | stage 2: each moved service on its own |
| sup-hooks | console-builder | sup-host | apps/runner/hooks/*.mjs, package.json (fw bin) | stage 2: hook client footprint vs baseline |
| sup-tests | console-builder | sup-leases | apps/runner/src/land.ts, lean/Fw/Console/LandPool.lean | stage 3: poolFair reads room |
| sup-pools | measure-engineer | sup-leases, sup-warmup | packages/measure-webkit/src/sim.mjs, packages/gate-breakpoints/src/engines.mjs, apps/console-api/src/preview/manager.ts | stage 4: each pool on its own |
| sup-math | lean-prover | sup-model | the math artifact for section 3's theorems (math-reviewer checks) | each stated theorem vs its Lean statement |
