# Parallel work plan: measured, resource-aware (proposal, 2026-10-17)

Decision document for "measure the work, see whether it can run in parallel, plan it". Nothing here is applied yet;
section 6 is the change list for the lead to approve. The lead commits.

Sources and tags: **[M§n]** = `research/notes/2026/10-17-parallel-work-measure.md` section n; **[C§n]** =
`research/notes/2026/10-17-parallel-capacity.md` section n; **[PLAN §x]** = `docs/plan/PLAN.md`; **[H:name]** =
`docs/team/handoffs/<name>.md`; **[repo]** = file read at main `a0b9053` (or in a running worktree, named). Every claim
carries CONFIRMED / MEASURED / INFERRED as in those notes. `[C header]` = the header of the capacity note.

Base state at `a0b9053`: `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS` is 10 (was 6), and five long-running roles have the
Agent tool, so nested helper roles exist (Haiku `scout`/`runner`, Sonnet `checker`/`patcher`). Helper `runner` jobs
that run heavy commands count as jobs: they go through `fw job` like any other heavy command.

## 0. Decisions in one table

| # | Decision | Main evidence |
|---|---|---|
| P1 | Track 6 numbers continuously (speedup, efficiency, contention, critical path, lead latency, user wait), defined once in Lean (`Fw.Ops.ParMetrics`) | 219-min build window: S = 4.94, serial share 17 %, x1.20 per heavy command, lead busy 46 % (MEASURED [M§2-5]) |
| P2 | Budget the machine: 6 cores, 10 GB, 1 clean Lean build, 1 Simulator, 1 phone, 2 Docker runs | 8 cores / 16 GB, already swapping 3.5 GB (MEASURED [C header, M§3]); load1 is not used as a gauge (section 2) |
| P3 | One admission op in Lean (`Fw.Ops.Admit`), composed after `Fw.Ops.SpawnGuard`, used at spawn time and at heavy-command time | the guard counts agents only, not files, deps or resources ([repo] lean-ops worktree `lean/Fw/Ops/SpawnGuard.lean`) |
| P4 | Seven quick wins now (section 4): cloned `.lake`, thread caps, Simulator lane lock, staggered clean builds, fast check, no sleep-polling, land-on-notification | the top 5 measured causes [M§6] |
| P5 | Validate with a scripted A/B bench, decided by the existing `Fw.Verdict.verdict` (4 v 4) | the false-better chance of 4 v 4 is 1/C(8,4) = 1/70 under no effect, only if the A/B labeling is drawn uniformly at random ([repo] `Fw/Spec/Null`) |

## 1. Metrics we track continuously

Window = a span of lead wall time with the user's AskUserQuestion wait and away periods removed [M§2]. Busy = an
agent is in a model request or a tool call (merged per agent) [M§1]. Polling = a tool call that is a sleep or wait loop
[M§1]. Heavy command = the command list of [M§3] (lake build/exe/test, check.sh, pnpm test/determinism/census,
host.mjs, cli.mjs, vitest, build-math-view (retired), simctl, measure.mjs).

| Metric | Definition | Baseline (MEASURED) | Target (INFERRED) | Data source |
|---|---|---|---|---|
| Speedup S | $S = \sum_a \mathrm{busy}_a / W$; $S_{np}$ drops polling | S 4.94, $S_{np}$ 4.44 [M§2] | $S_{np} \ge 5.5$ | `agent-profile.py` (model/tool/idle per agent, `calls.jsonl`) |
| Efficiency E | $E = S_{np} / \bar R$, $\bar R$ = mean number of declared workstreams that are ready (deps landed, not landed itself); plus serial share = share of $W$ with $\le 1$ agent busy | serial share 17 %, all before 07:50 [M§5]; $\bar R$ not measured (no declarations yet) | serial share $\le 8$ %; $E \ge 0.8$ | profile + `docs/team/workstreams.json` + `card.landed` events |
| Contention slowdown | Decision metrics: (b) per-job stretch $d / d_{solo}$ from `fw job` logs; (c) probe stretch: a fixed 1 s CPU loop every 60 s, time / quiet time. Descriptive only: (a) fit $\ln d = c_{cmd} + \beta k$, factor $e^\beta$, $k$ = other heavy commands overlapping ($R^2$ 0.03, CI 1.07-1.35 under 7 named confounders, so a refit cannot tell x1.20 from x1.10) | x1.20 (CI 1.07-1.35, $R^2$ 0.03), Lean x1.25 [M§3]; tax 63 of 247 heavy agent-min is model-derived (INFERRED) | p90 job stretch $\le 1.3$; probe stretch $\le 1.1$ | `calls.jsonl`; `fw job` log; load sampler |
| Critical path CP | longest path through the declared workstream DAG, node weight = lane wall time (first agent start to `card.landed`); report the lane that sets it and its model/tool/polling split | measurement lanes 118 and 111 min vs Lean chain 68 min; lane time 30-40 % model [M§5] | CP lane polling $\le 5$ % | `workstreams.json` + obs `SubagentStart/Stop` + `card.landed` |
| Lead latency | pickup = enqueue to next lead request; action = enqueue to next spawn/SendMessage/TaskStop/land; disposition = agent's last line to the lead's first action on it; follow-up gap = lane agent end to next lane agent start; lead busy share | pickup median 5 s; disposition median 18 s, p90 350 s, 49 agent-min; follow-up gaps 0.6-15.9 min; lead busy 46 % (65 % in 08:00) [M§4] | disposition p90 $\le 60$ s; follow-up median $\le 2$ min; lead busy $\le 35$ % | lead transcript via `agent-profile.py` (`res["lead"]`); obs events |
| User wait | min with 0 agents busy while the lead waits on you; AskUserQuestion block min; console needs-you age (`step.post` to `step.answer`) | 6.6 min idle-on-user, 3.6 min AskUserQuestion in window [M§4] | $\le 3$ min per 4 h | lead transcript; console `events.jsonl` |

Machine gauges logged next to them: CPU idle %, memory free %, swap used, process counts (lean, node, docker,
simulator, claude) every 10 s (load1 is logged but never used as a gauge, section 2). The current sampler is a scratchpad script started 09:48Z with an interval of 9-30 s, so only 12 heavy calls
overlap a sample and no load fit was possible (MEASURED [M§3]); it is promoted in section 6.

Lean first: interval merge, busy counts, $S$, serial share, CP over a DAG, stretch, and the bench verdict are pure, so
they are specified in `Fw.Ops.ParMetrics` and the Python extractor is checked against its golden vectors. Until then
`parallel-measure.py` is a **Python stand-in** (listed in section 6).

## 2. Resource model and budget

Units for the Lean op: cores in tenths (`dc`, 10 = one busy core), RAM in MB, tokens and devices as counts.
"Hold" = kept for the workstream's life; "job" = held only while one heavy command runs.

| Kind | Cores (dc) | RAM MB | Tokens / devices | Basis |
|---|---|---|---|---|
| model-only agent (any role) | 0 | 250 (hold) | - | node RSS 250-280 MB, MEASURED [C§6] |
| lake clean build (capped `LEAN_NUM_THREADS=2`) | 40 | 2500 | `cleanBuild` 1 | one lean peaked 2.5 GB RSS, MEASURED; cores INFERRED: lake jobs run at the default task priority on the pool (lean4@eb6cafb `src/lake/Lake/Build/Job/Monad.lean:170-172`), so 2 concurrent `lean` children x 2 threads; E1 measures it |
| lake incremental / cloned `.lake` | 20 | 300 | - | no-op 0.37 s, MEASURED [C§2] |
| `check.sh` (full) | 20 | 2500 | - | INFERRED (build + test + lint in one process chain) |
| vitest / `pnpm test` (capped 2 workers) | 20 | 1500 | - | default 7 workers, CONFIRMED [C§5]; RAM INFERRED |
| Docker Chromium run (`--cpus 2 -m 1500m`) | 20 | 1500 | `docker` 1 | INFERRED [C§4] |
| Simulator boot | 60 (burst) | 2500 | device `simulator` | job; CPU idle collapses to 0 % at boots, ~170 extra processes per boot MEASURED [C§3]; cores INFERRED |
| Simulator booted (hold, WebKit run on top) | 5 | 2500 (hold while booted) | device `simulator` | a booted, idle device left 50-67 % idle (10:01-10:03) [scratchpad load.jsonl, MEASURED]; RAM INFERRED |
| phone lane | 5 | 300 | device `phone` | INFERRED; job order inside is `Fw.DeviceQueue` |
| lean-lsp / Serena server | 10 | 1000 (hold) | - | INFERRED [C§6] |

Budget (INFERRED from [C§6]): cores 60 dc (8 minus 1.5 for OS, Docker VM, WindowServer, rounded down), RAM 10,000
MB (16 GB minus ~4 GB OS/apps, and swap already at 3.5 GB), `cleanBuild` 1, `docker` 2 (2 runs x `--cpus 2` fit a
4-CPU VM; RAM fits the 7.75 GiB VM at 1.5 GB each), devices `simulator` 1 and `phone` 1.

Worked fit (INFERRED): up to 10 subagents plus the lead and nested helpers, about 14 model agents (3500 MB) + 1
incremental lake (20 dc, 300) + 1 vitest (20, 1500) + 1 Docker run (20, 1500) + booted Simulator (5, 2500) = 65 dc,
9300 MB: RAM fits, cores do not, so one heavy job queues. Gauge note: CPU-idle collapses coincide with Simulator boots
(0 % idle at reboots at 09:49:50, 09:52:07, 09:54:10, a reboot about every 2 min), while a booted, idle device left
50-67 % idle (10:01-10:03); load1 fell from 431 (09:53) to 14 (10:03) while the Simulator process count rose from
190 to 264, and load1 412 occurred with 64 % idle (09:49:02), so on macOS load1 is not a CPU-demand gauge
[scratchpad load.jsonl, 88 samples, MEASURED]. Mean concurrent tool calls were only 0.24 x 8 cores over the window
(MEASURED [M§2, M§3]).

Caps exported by default in every agent environment (CONFIRMED levers [C§1, C§5]): `LEAN_NUM_THREADS=2`,
`VITEST_MAX_WORKERS=2`; Docker runs with `--cpus 2 -m 1500m` [C§4]; one Simulator lock; at most one clean Lean build
at a time (the `cleanBuild` token). Lake has no `-j` flag, so the env var is the only lever (CONFIRMED
lean4@eb6cafb src/runtime/object.cpp:1106-1113 [C§1]).

## 3. Admission rule (Lean first): `Fw.Ops.Admit`

### 3.1 Definitions

Resource kinds $\mathcal R$ = {cores, ram, cleanBuild, docker}; devices $\mathcal V$ = {simulator, phone}; budget
$B : \mathcal R \to \mathbb N$. An **item** (a workstream at spawn time, or a heavy job at command time) is

$$x = (\mathit{id},\ \mathit{parent},\ W(x),\ D(x),\ d(x),\ V(x),\ \mathit{seq},\ \mathit{enq},\ \mathit{base})$$

with $\mathit{parent} : \mathrm{Option}\ \mathit{Id}$ (a job's parent workstream), $W(x)$ write prefixes (path segments; a
directory prefix covers its subtree), $D(x)$ ids it depends on, $d(x) : \mathcal R \to \mathbb N$ its demand,
$V(x) \subseteq \mathcal V$ the devices it needs, and the `DeviceQueue` fields (arrival number, enqueue time, base
priority). Workstreams and jobs share one $\mathit{Run}$, so $x \sim y$ (related) holds when one is the other's parent;
related pairs are exempt from the $\bowtie$ and $V$ checks (a heavy job always overlaps the writes and devices its parent
workstream holds, e.g. the `simulator` lane). A state is $\sigma = (\mathit{Run}, \mathit{Done}, Q, t)$.

$\mathit{base}$ for a workstream is its rank of CP slack from `fw plan` (0 on the critical path); for a job it is the
`DeviceQueue` base. A dependency in $D(x)$ is satisfied by `card.landed`, or by `card.build` (committed on its branch)
when $x$ only reads it, so lead latency does not sit on every edge.

| Name | Math |
|---|---|
| path conflict | $p \bowtie q \iff p \sqsubseteq q \lor q \sqsubseteq p$ (segment prefix) |
| write conflict | $x \bowtie y \iff \exists p \in W(x),\ q \in W(y):\ p \bowtie q$ |
| ready | $\mathrm{ready}(\sigma, x) \iff D(x) \subseteq \mathit{Done}$ |
| free | $\mathrm{free}(\sigma, x) \iff \forall y \in \mathit{Run},\ \lnot(x \sim y):\ \lnot(x \bowtie y) \land V(x) \cap V(y) = \emptyset$ |
| fits | $\mathrm{fits}(\sigma, x) \iff \forall r \in \mathcal R:\ d(x)(r) + \sum_{y \in \mathit{Run}} d(y)(r) \le B(r)$ |
| never fits | $\mathrm{unfit}(x) \iff \exists r:\ d(x)(r) > B(r)$ |
| competes | $\mathrm{comp}(z, x) \iff z \bowtie x \lor V(z)\cap V(x)\neq\emptyset \lor \exists r:\ d(x)(r)+d(z)(r)+\sum_{y\in Run} d(y)(r) > B(r)$ (decidable over finite lists; a bare "both demand $r$" test would serialize nearly all work, since every item demands RAM) |
| held by an aged item | $\mathrm{held}(\sigma, x) \iff \exists z \in Q,\ z \ne x:\ \mathrm{before}_t(z, x) \land \mathit{enq}(z) + A \cdot \mathit{base}(z) \le t \land \mathrm{ready}(\sigma, z) \land \lnot\mathrm{unfit}(z) \land \mathrm{comp}(z, x)$ |

`before`, `eff` and $A = 300$ s are reused from `Fw.DeviceQueue` (aging: one priority level per 300 s of waiting).
The rule is EASY-style backfill: an item may pass an aged item only if it does not compete with it.

$$\operatorname{admit}(\sigma, x) = \begin{cases} \mathrm{queue}(\mathrm{neverFits}(r)) & d(x)(r) > B(r) \\ \mathrm{queue}(\mathrm{depPending}(e)) & e \in D(x) \setminus \mathit{Done} \\ \mathrm{queue}(\mathrm{writeConflict}(p, y)) & y \in \mathit{Run},\ p \in W(x),\ \exists q \in W(y): p \bowtie q \\ \mathrm{queue}(\mathrm{deviceBusy}(v, y)) & v \in V(x) \cap V(y),\ y \in \mathit{Run} \\ \mathrm{queue}(\mathrm{overBudget}(r, \mathit{need}, \mathit{free})) & \lnot \mathrm{fits} \text{ at } r \\ \mathrm{queue}(\mathrm{behindAged}(z)) & \mathrm{held}(\sigma, x) \text{ by } z \\ \mathrm{admit} & \text{otherwise} \end{cases}$$

First match wins, so the reason is always the first failing check (the lead sees "queued: writeConflict
`lean/Fw/Ops/` held by lean-ops"). The step functions are `admitStep` (admit the `before`-least admissible item of
$Q$), `finish` (remove from $\mathit{Run}$, add to $\mathit{Done}$ when the item is a workstream that landed) and
`enqueue`.

### 3.2 Theorems to prove

| Theorem | Statement |
|---|---|
| `admit_iff` | $\operatorname{admit}(\sigma, x) = \mathrm{admit} \iff \mathrm{ready} \land \mathrm{free} \land \mathrm{fits} \land \lnot \mathrm{held}$ (as `SpawnGuard.accepted_iff`) |
| `inv_step` | $\mathrm{Inv}(\sigma) \Rightarrow \mathrm{Inv}(\mathrm{step}(\sigma, c))$ for `admitStep`, `finish`, `enqueue`, where $\mathrm{Inv}$ is the four rows below plus unique ids |
| `writes_disjoint` | $\forall x \ne y \in \mathit{Run},\ \lnot(x \sim y):\ \lnot(x \bowtie y)$: no two unrelated admitted items write the same file |
| `deps_respected` | $\forall x \in \mathit{Run}:\ D(x) \subseteq \mathit{Done}$, and $\mathit{Done}$ only grows |
| `within_budget` | $\forall r \in \mathcal R:\ \sum_{x \in \mathit{Run}} d(x)(r) \le B(r)$ |
| `devices_exclusive` | $\forall x \ne y \in \mathit{Run},\ \lnot(x \sim y):\ V(x) \cap V(y) = \emptyset$ |
| `unfit_reported` | $\mathrm{unfit}(x) \Rightarrow \operatorname{admit}(\sigma, x) = \mathrm{queue}(\mathrm{neverFits}(\cdot))$: the one real starvation case is named at enqueue, never silent (as `DeviceQueue.unfit_never_starts`) |
| `aged_not_overtaken` | $z$ aged, ready, $\lnot\mathrm{unfit}(z)$, $z \in Q$, $\mathrm{before}_t(z, x)$, and `admitStep` admits $x \ne z$ $\Rightarrow \lnot\mathrm{comp}(z, x)$ (without $\mathrm{before}_t(z,x)$ it is false: an aged $x$ ahead of $z$ is not held) |
| `admit_conserving` | some $x \in Q$ with $\operatorname{admit}(\sigma, x) = \mathrm{admit}$ $\Rightarrow$ `admitStep` admits some item (no idle capacity while admissible work waits; as `dispatch_conserving`) |
| `aged_admitted_by` (stretch) | for job-level items $z$ (workstreams hold writes and devices for hours, so $\mathit{dur}_{max}$ does not bound them), over a trace where `admitStep` runs after every finish and enqueue, every job ends within $\mathit{dur}_{max}$, and $D(z)$ is landed: $z$ is admitted by $t_{aged} + (1 + |\{y \in Q \cup \mathit{Run} : \mathrm{comp}(y,z),\ \mathit{seq}(y) < \mathit{seq}(z),\ y \text{ aged}\}|) \cdot \mathit{dur}_{max}$, with $t_{aged} = \max(t_{ready}, \mathit{enq}(z) + A\cdot\mathit{base}(z))$. This is the liveness statement that DeviceQueue still lacks [H:lean-null-fix]; prove it here first and port it back. **Restated in Lean (`4bd850f`):** this k-term bound is false (the `Cex` guards: an older competitor that is not ready lets a newer one slip ahead, so $z$ is still queued at $t = 25 > 20$). Proved instead: $\sigma_j.t < \sigma_i.t + (1 + \Psi)\cdot \mathit{dur}_{max}$, where $\Psi$ counts the queued older items that can ever fit plus those not yet aged but ready, given $\mathit{dur}_{max} > 0$ and a quiescent $\sigma_i$ (nothing chosen); see `docs/team/handoffs/lean-sched.md` |
| `gate_spec` | $\mathrm{accepted}(\operatorname{gate}(i, \sigma, x)) \iff \mathrm{accepted}(\operatorname{SpawnGuard.decide}(i)) \land \operatorname{admit}(\sigma, x) = \mathrm{admit}$, and a guard denial is returned unchanged as `guard (deny r)` |

### 3.3 Composition with lean-ops' SpawnGuard (extend, do not duplicate)

- `SpawnGuard.decide` (lean-ops, in progress, [repo] worktree `agent-ae9a708540ef53fad`) already owns names, kinds,
  the worktree trap, the agent-count caps (5 teammates, 8 worktree, 10 subagents, 3 lean-provers), the spawn rate and
  the `fable` ask path. Admit does **not** count agents again.
- New `Fw.Ops.Gate` defines `GateDecision := guard (d : SpawnGuard.Decision) | queue (why)` (`Decision` = allow |
  needsApproval | deny, and `accepted(needsApproval)` is true). `gate i σ x := match SpawnGuard.decide i with | .deny r
  => guard (deny r) | d => match admit σ x with | .admit => guard d | .queue why => queue why`. A guard denial is
  returned unchanged; every SpawnGuard theorem carries over through `gate_spec`. A `PreToolUse` hook cannot queue a
  spawn: at spawn time a `queue` result becomes a hook deny carrying the reason, and Q is persisted by `fw plan`.
- Devices: the Simulator lock is a `Fw.Lease` state (exclusivity already proved by `Inv`); Admit reads its holder as
  $V$-occupancy. Phone jobs keep `Fw.DeviceQueue` for order inside a booked window; Admit only reserves the phone lane.
  Lease's renew-forever gap (G4, [repo] `Fw/Spec/Lease.lean`) is closed by a renew cap in the lock, not here.
- Called from (a) the spawn-guard hook (`PreToolUse` matcher `Agent`): the spawn prompt's first line `work: <id>`
  names a workstream in `docs/team/workstreams.json`; read-only roles without `work:` get zero demand; (b) `fw plan`:
  prints every declared, unlanded workstream with admit or queue-and-reason, the CP and the spawn order; (c) `fw job
  <kind> -- <cmd>`: job-level admission for heavy commands, blocking server-side (no sleep-polling) until admitted;
  helper roles (`runner`) run heavy commands through `fw job` too.
  All three go through `fwcore` ops `ops.admit` / `ops.gate`; the hooks and CLI only move JSON.
- Rollout: shadow mode first (decision logged as an obs event, never denies), enforce only after section 5 passes.

## 4. Quick wins to apply now

| # | Change | Expected effect (INFERRED unless tagged) | How we measure it |
|---|---|---|---|
| Q1 | Shared Lean build: `scripts/wt-prep.sh` runs `rm -rf <wt>/lean/.lake` (or requires it absent; `cp -c -R` into an existing directory makes `.lake/.lake`), then `cp -c -R <main>/lean/.lake <wt>/lean/.lake` before any `lake build`; skipped while a main `lake build` holds the `cleanBuild` lock (torn copy) | 0.22 s clone + 0.37 s no-op build instead of a clean build per worktree (MEASURED [C§2]); 14 worktrees built from scratch so far, 5.3 GB logical (MEASURED [C§2]); a cold build is up to ~300 s ([M§3] confounder 1) | count of clean `lake build` runs per new worktree (target 0 when the base equals main); first-build duration per worktree in `calls.jsonl` |
| Q2 | Thread caps in the agent environment: `LEAN_NUM_THREADS=2`, `VITEST_MAX_WORKERS=2` | fewer runaway threads (one lake build may run 8 lean jobs' worth of tasks, CONFIRMED [C§1]; 4 vitest packages x 7 workers ~28 processes [C§5]); contention factor from x1.20 towards x1.10 | per-job stretch and probe stretch (section 1); idle % from the sampler; lake build median at $k \ge 2$ |
| Q3 | Simulator lane: one owner holds a lock (`.local/locks/sim`, stand-in for `Fw.Lease`), boots once per lane session (`--keep` between runs), shuts down at release | a boot adds ~170 processes and gave 0 % idle for 3 samples (MEASURED [C§3]); 192 -> 21 simulator processes after shutdown (MEASURED [C§3]); 227 simulator processes were up at 09:58Z [scratchpad load.jsonl, MEASURED] | boots per hour (the metric); CPU idle % while no WebKit job runs |
| Q4 | Stagger heavy builds: at most one clean Lean build at a time (`cleanBuild` token; until `fw job` exists, a `mkdir` lock in `wt-prep.sh`) | removes the worst overlaps; with Q1 most clean builds disappear anyway | share of heavy calls at $k \ge 3$ (was 73 of 351, MEASURED [M§3]) |
| Q5 | `lean/scripts/check-fast.sh` for the inner loop (build + `lake test` + golden diff; lint and breakgen only on land), reusing the existing `lean/scripts/check-partial.sh` instead of duplicating gates; full `check.sh` stays the land gate; both print per-step seconds | `check.sh` calls ranged 3-136 s (MEASURED, n = 15, scratchpad `par-prof/calls.jsonl`; [M§3] bin medians were 33.8-68.9 s); the split per step is not measured yet | per-step timings from the new output; inner-loop check median |
| Q6 | No sleep-polling: wait in the foreground with a bounded timeout, or run in the background and end the turn; the measure harnesses run all passes of a determinism check in one command | polling held 110 agent-min, 78 of them in 4 agents ([M§6] rank 1); a re-extraction with the `poll` flag gave 77.5 agent-min (meas-webkit-2 31.7, gate-breakpoints 11.0, meas-chromium-2 9.5, meas-chromium 5.1), so the figure is pending E2 re-extraction with a committed classifier | polling agent-min per window from `agent-profile.py` (repeated identical commands, sleep calls); target $\le 20$ |
| Q7 | Lead latency: land on the finish notification in the same turn (`fw land`, landed 840f7d6); land finished branches in one batch; every handoff note ends with a ready "next agent" prompt so the follow-up spawn is one call; the lead delegates multi-file reading to reviewers | disposition p90 350 s, 49 agent-min; follow-up gaps up to 15.9 min; 31 of 60 events queued behind a busy lead (MEASURED [M§4]) | disposition p90, follow-up gap median, lead busy share (section 1) |

Docker: `--cpus 2 -m 1500m` per Chromium run, and Docker Desktop at 4 CPUs (your setting, needs a restart) [C§4]. At 4
VM CPUs, 3 concurrent runs x `--cpus 2` is 6 CPUs, so the `docker` token is 2 (or keep the VM at 6 CPUs). This waits
for the running Chromium agent (section 6). Budget line in section 2 follows: `docker` 2 at a 4-CPU VM.

## 5. Validation experiment: same workload, old way vs new rules

- **Workload** (scripted, no model calls, same commit, so the job set is identical in both arms): per block, 3 fresh
  worktrees each with a Lean build, 3 full `check.sh`, 2 `pnpm test`, 1 Chromium count run (Docker), 1 WebKit
  determinism pass (Simulator), 1 `build-math-view`. Jobs arrive on a fixed schedule that reproduces the measured
  overlap (mean $k$ = 1.63, from the $k$ histogram of 351 heavy calls, MEASURED [M§3]).
- **Arm A (old):** no caps, clean build per worktree, every job starts on arrival, Simulator booted per command.
  **Arm B (new):** admission only. To isolate the admission rule, Q1 (cloned `.lake`) and Q2 (thread caps) apply in
  both arms: A = no admission, Simulator booted per command; B = `fw job` admission under the section 2 budget plus
  the Simulator lock. (Alternatively run a separate admission-only pair; E15 is gated only on that pair.)
- **Design:** 8 blocks; draw the A/B assignment uniformly from the C(8,4) = 70 labelings with a recorded seed before
  the first block; the 1/70 bound holds only under that randomisation (`Fw.Null` assumes equally likely labelings).
  Before each block remove the bench worktrees, shut the Simulator down and remove the containers. Nothing enforces
  exclusivity while admission is in shadow mode, so run the bench only when no agents are alive (for example the
  user-away window; 21:39-06:11 had about 0.02 agents alive) and log zero `claude`/`lean` processes outside the bench
  at each block start; otherwise it stalls the critical path for about 2 h. About 8 x 12 min of machine time plus the
  solo-baseline runs (3 per job kind, including ~4-min determinism passes), about 96 min plus baselines (INFERRED).
- **Measured per block:** makespan; each job's stretch $d / d_{solo}$ ($d_{solo}$ = median of 3 solo runs per kind on
  a quiet machine); peak swap used, minimum memory free and idle %; number of clean builds; the count vectors of the
  Chromium and WebKit runs.
- **Success, all of:**
  1. `Fw.Verdict.verdict .lower makespan_A makespan_B = .better` (every B block faster than every A block; chance
     1/70 under no effect, given the randomised labeling).
  2. p90 stretch in B $\le 1.3$.
  3. Measurement classes unchanged: every count type keeps its deterministic / stable / quarantined class
     (`measure.classify`, [H:lean-measure]).
  4. Swap growth in B $\le$ A.

  Fail on 1 or 3: Admit stays in shadow mode, and we re-plan from the per-job numbers.
- **Then, observational** (not a decision; models vary): the next real build window against this session. Targets
  are the section 1 table. Done when 4 of the 6 metrics meet their targets.

## 6. Execution list

Running now (do not touch their files):
- lean-serve (`agent-aa3e2a69b982250f3`): `lean/Fw/Serve.lean`, `Fw.lean`, `Wire.lean`, `Main.lean`, `FwTestMain.lean`, board goldens.
- lean-ops (`agent-ae9a708540ef53fad`): `lean/Fw/Ops/**`, `lean/Fw/Wire.lean`, then the spawn-guard hook. The overlap
  with lean-serve on `lean/Fw/Wire.lean` is a registration-line overlap that the lead merges.
- gate-breakpoints: `packages/gate-breakpoints/**`, `pnpm-lock.yaml`.
- A Chromium agent (`agent-afebbc5875983d2f8`): `packages/measure-chromium/src/{host,run,server,clock-shim}.*`, plus `Dockerfile`, `.dockerignore` and `docker/`.
- A WebKit agent (worktree `agent-a350351627a0b4359`): `packages/measure-webkit/src/{cli,determinism,page,reduce,scrollrun,serve,session,sim}.mjs`.

The working trees were read at the time of writing. con-hooks and con-land have landed (3fe1876, 840f7d6).

| # | File(s) | Owner role | Wave | Conflict check |
|---|---|---|---|---|
| E1 | `docs/team/tools/load-sample.sh` (promote the scratchpad sampler: add swap, per-kind CPU %, the 1 s probe; output to `.local/load/`) | env-ops | 1 (now) | new file |
| E2 | `docs/team/tools/parallel-measure.py` (the [M] analysis as a tool: S, $S_{np}$, serial share, $\beta$ fit, lead latency, user wait; reads profile, sampler, obs). **Python stand-in** until E9 | researcher (Sonnet) | 1 | new file; reads `agent-profile.py`, does not edit it |
| E3 | `scripts/wt-prep.sh` (Q1 clone, Q4 lock), `scripts/sim-lock.sh` (Q3; **shell stand-in** for `Fw.Lease`) | env-ops | 1 | new files |
| E4 | `lean/scripts/check-fast.sh` (Q5) | lean-prover (Sonnet tier) | 1 | new file; `check.sh` untouched |
| E5 | `.claude/settings.json` env (Q2 caps; already changed at `a0b9053`: concurrency 6 to 10); `.claude/agents/{lean-prover,console-builder,part-builder,measure-engineer}.md` (first command `sh scripts/wt-prep.sh`; Q6 rule; helper roles such as `runner` run heavy commands through `fw job`); `CLAUDE.md` (Q6, Q7 handoff "next agent" line) | lead (each is an `ask` write; one sitting, batched with con-hooks' proposed hooks block) | 1 | lead-only files |
| E6 | `docs/team/workstreams.json` (id, writes, deps, demand, devices per workstream) + zod schema `packages/contracts/src/work.ts` | lead fills; console-builder for the schema | 1 | new files |
| E7 | `lean/Fw/Sched/Admit.lean` (section 3 definitions and theorems; `lean/lakefile` uses `globs = ["Fw.*"]`, so no `Fw.lean` edit) in wave 1; `lean/Fw/Ops/Gate.lean` (needs SpawnGuard) in wave 2 | lean-prover (opus/high) | 1 for Admit; 2 for Gate: after lean-ops lands (it owns `lean/Fw/Ops/`) | new files |
| E8 | `lean/Fw/Wire.lean`, `lean/Fw.lean`: registration of ops `ops.admit`, `ops.gate`, `metrics.*`; goldens `packages/contracts/golden/ops/{admit,metrics}.jsonl` | the E7 lean-prover (one writer for Wire) | 2: after lean-serve and lean-ops land | - |
| E9 | `lean/Fw/Sched/ParMetrics.lean` (interval merge, S, serial share, CP, stretch; bench verdict via `Fw.Verdict`). Theorems: `merge_disjoint_sorted`, `busy_le_alive`, `serial_share_le_one`, `cp_ge_path` (CP $\ge$ weight of every path), `cp_attained`, `cp_acyclic_or_error` (CP by a fuel $= \lvert V\rvert$ topological pass, returning `cycle` if the graph is not acyclic) | a second lean-prover (per-role cap 3) | 1 | new file; E8 registers its ops |
| E10 | `apps/runner/hooks/spawn-guard.mjs`: call `ops.gate` in shadow mode | console-builder | 2: after lean-ops lands the hook | lean-ops' file |
| E11 | `apps/runner/src/{plan,job}.ts` + verbs in `fw.ts`; `apps/console-api/src/jobs/` (Run state, blocking admit endpoint) | console-builder | 2 | `fw.ts` free since con-land landed |
| E12 | `packages/measure-chromium/src/host.mjs` Docker caps; `packages/measure-webkit` harness: `--keep` within a session, `sim-lock.sh` | measure-engineer | 2: after the running Chromium agent lands (`host.mjs`, Docker files) and, for the `measure-webkit` part, after the WebKit agent lands | their files |
| E13 | `scripts/par-bench/` (section 5 workload, arms, block order, result JSON); run it | measure-engineer (opus/high for the bench design) | 3: after E3, E5, E11, E12 | new files |
| E14 | `docs/plan/PLAN.md` §8.2-8.3 caps and budget, §10.1 row, Appendix D row | plan-editor | 3: after the bench verdict | the only PLAN writer |
| E15 | Flip `spawn-guard.mjs` from shadow to enforce | lead decides; console-builder edits | 3: after a pass in section 5 | - |

Stand-ins introduced: `parallel-measure.py` (until E9, now wave 1) and `sim-lock.sh` (until the console holds a `Fw.Lease`
state). The `wt-prep.sh` lock is replaced by the `cleanBuild` token of E11.

## 7. How to continue

Read this file, then [M§3-6] and [C§6]. Start wave 1 (E1-E7 Admit, E9) now; they touch no running agent's files. Wave 2
starts per row as soon as lean-ops, lean-serve, the Chromium agent or the WebKit agent lands; `git -C <worktree> status` shows their
live files. Record outcomes in `docs/team/improvements/2026-10-17.md`.

## Critique log

| # | Finding | Severity | Resolution |
|---|---|---|---|
| 1 | Bench arms confounded (Q1 bundled with admission) | High | Q1 and Q2 in both arms; B = admission only (section 5) |
| 2 | 1/70 needs random labeling, fixed order is not | High | Uniform draw from 70 labelings with recorded seed (sections 0, 5) |
| 3 | Nothing enforces "bench holds every resource" | High | Run only when no agents alive; log zero outside processes per block (section 5) |
| 4 | `aged_not_overtaken` false without `before_t(z,x)` | High | Hypothesis added (3.2) |
| 5 | `aged_admitted_by` bound wrong | High | Job-level only, k-term bound, admitStep after every event (3.2) |
| 6 | `comp` serializes everything via RAM | High | Budget-overflow form of `comp` (3.1) |
| 7 | Job conflicts with its parent workstream | High | `parent` field, related pairs exempt (3.1, 3.2) |
| 8 | Simulator/load1 claims refuted by raw data | High | Claims replaced, Simulator split boot/booted, boots per hour, load1 dropped as gauge (1, 2, 4) |
| 9 | Running-now list incomplete | High | WebKit agent, Chromium Docker files, Wire.lean overlap added; E12 gated (6) |
| 10 | Stale base commit | Medium | Re-based on a0b9053, concurrency 10, helper roles, `runner` jobs count (header, 2, 3.3, E5) |
| 11 | E7/E9 wave 2 without need | Medium | Admit and ParMetrics under `lean/Fw/Sched/`, wave 1; Gate and E8 wait (6) |
| 12 | ParMetrics has no theorems | Medium | Six theorems listed in E9 |
| 13 | Gate typing and hook semantics mismatch | Medium | `GateDecision`, queue becomes hook deny, Q persisted by `fw plan` (3.3) |
| 14 | No critical-path priority | Medium | base = CP slack rank; `card.build` satisfies read-only deps (3.1) |
| 15 | Lake core demand underestimated | Medium | 40 dc, cited, measured by E1 (2) |
| 16 | Contention target untestable with (a) | Medium | (b), (c) decision metrics; (a) descriptive; tax INFERRED (1) |
| 17 | Polling number not reproduced | Medium | 77.5 cited, pending E2 re-extraction (Q6) |
| 18 | Q5 misreads data | Medium | Range 3-136 s (n=15); reuse `check-partial.sh` (Q5) |
| 19 | Docker settings inconsistent | Medium | `docker` token 2 at 4 VM CPUs (4, 2) |
| 20 | Citation errors | Low | `[C header]`, sampler tagged scratchpad, 9-30 s interval |
| 21 | `cp -c -R` nests `.lake/.lake` | Low | `rm -rf` first; skip during main build (Q1) |
| 22 | Privacy check | Low | No personal data found; no change |
