---
id: 2026-10-21-mem-gate-bypass
kind: note
title: "Lean entry points against the heavy lock and the lake slot: the 4.2-5.4 GiB bursts are one admitted check.sh at width 8 beside ungated Lean work"
status: review
created: 2026-10-21
topics: [lean, memory, heavy-lock, lake-slot, fw-sup, daemon, leases, scheduling]
---

# Lean entry points against the heavy lock and the lake slot

## Answer

- Only `lean/scripts/check.sh` passes the heavy lock (CONFIRMED check.sh:21, the sole caller of
  `scripts/heavy-lock.mjs`). `fw land` builds pass the lake slot only. Agents' direct `lake build`, `lake env lean`,
  `lake test`, `lake exe`, the lean-lsp-mcp `lake serve` tree, its `lean_build` tool and the Serena Lean server pass
  neither gate.
- The four bursts of 4.2-5.4 GiB were each a single check.sh, the only heavy-lock holder, admitted at n=0 with no
  memory or swap check (CONFIRMED `lean/Fw/Sched/Heavy.lean:80`, `verdict_idle`). Its parallel group then ran up to 8
  Lean jobs (CONFIRMED check.sh:134-136, `LakeSlot.lean:43,59`; no memory input) beside an agent's direct `lake build`
  and two idle Lean servers that the lock never saw (MEASURED, samples i=27, 34, 38).
- The 4.2-5.4 GiB figure is summed ps RSS. Shared mmapped `.olean` files count once per process, so RSS overstates
  each job's footprint 2.4-6.9x (MEASURED, `/usr/bin/time -l`). The real burst demand is about 1.6-1.8 GiB anonymous
  plus about 1.5 GiB shared olean cache (INFERRED). The 58 MB free at the bursts is this Mac's normal level: free
  memory was 60-330 MB across the whole window (MEASURED), so it marks no burst.
- The swap gate would have held check.sh back had any other Lean job been a holder: swap stayed at 72-73% against
  the 60% limit all window (MEASURED; CONFIRMED `Heavy.lean:82`, `verdict_swap_blocks` at line 139). The memory gate
  would not have: `heavy-lock.mjs:80-84` reads `memory_pressure` free percentage (available memory, about 7.7 GB at
  48%), not `vm_stat` Pages free (about 136 MB) (MEASURED now).
- Daemon fix (stage 1b): a `lean` lease kind charged by footprint, with the grant carrying a width; every Lean entry
  point takes it. Interim fix: one heavy-lock holder registry for all Lean entry points plus a Lean-decided width.
  Both are below.

## Entry points

Gate columns are CONFIRMED at bea13736. Peaks are MEASURED: "RSS" is the max summed ps RSS for that entry's process
tree over 46 sampler samples at 20 s spacing; "footprint" is `/usr/bin/time -l` peak memory footprint from one run,
or `top` MEM for idle servers. Runs today are MEASURED from `.fw-console/timings.jsonl` spans since 00:00 local, or
from Bash tool calls in today's transcripts (regex over the command; heredocs missed, so a lower bound).

| Entry point | Heavy lock | Lake slot | Peak RSS | Footprint | Runs today |
|---|---|---|---|---|---|
| `sh lean/scripts/check.sh` (local) | yes, check.sh:21 | parallel group, check.sh:134 | 5245 MiB, 15 procs (i=34) | about 0.23 GiB per job | 234 parallel groups, p50 27.6 s, max 110 s |
| check.sh serial `lake build` stage | inside check.sh | fwcore-build.sh:39-40 | (in the row above) | 0.24 GiB per `lean -o` | 241 |
| check.sh axiom check | inside check.sh | no | 779 MiB (`--stdin` 724) | not run | per check.sh |
| `fw land` phase 1 `sh scripts/fwcore-build.sh` | no | fwcore-build.sh:39-40 | 1699 MiB (i=23) | 0.24 GiB per `lean -o` | 68, p50 20.5 s, max 332 s |
| `fw land --queue` rebuild (fw.ts:147) and remote build (land-remote.ts:299) | no | fwcore-build.sh | as above | as above | 51 |
| land axiom lint (land-verdict.ts:70) | no | `lake build` part only; `axiom-check.sh` (`lake env lean --stdin`, axiom-check.sh:10,17) runs outside both | not sampled | not run | 7 |
| agent `lake build ...` (settings.json:162-165 allow it; lean-prover.md:12 asks for it) | no | no | 921 MiB (i=24) | 0.24 GiB per `lean -o` | 98 calls |
| agent `lake env lean ...` | no | no | 1259-1479 MiB per golden or lint | 0.21-0.23 GiB | 173 calls |
| agent `lake test` / `lake exe` (site: apps/site/package.json:10 `lake exe breakgen`) | no | no | not sampled | not run | 19 / 1 calls |
| lean-lsp-mcp `lake serve` tree (.mcp.json:17-27; leanclient base_client.py:66) | no | no | 915 MiB (i=6) | about 465 MiB idle (top) | 71 MCP calls |
| lean-lsp-mcp `lean_build` tool (build_utils.py:173, not in the disabled list) | no | no | not sampled | as `lake build` | 0 seen |
| Serena Lean `lean --server` (serena-lean, uvx) | no | no | under 10 MiB RSS | 320 MiB (319 MiB compressed) | one server, 2.2 days old |
| console-api `fwcore` child (lean.ts:113) | no | no | 248 MiB | 19-23 MiB | resident |

The per-job footprint runs (one each, against the main checkout's built `.lake`, read-only):

| Job | Max RSS | Peak footprint | Wall |
|---|---|---|---|
| `lean --run scripts/HeavyGolden.lean --check` | 1259 MiB | 213 MiB | 9.8 s |
| InitCostLint import of `Main` (stopped early, import cost only) | 1479 MiB | 231 MiB | |
| `lean Fw/Ops/Obs.lean -o <scratch>` | 583 MiB | 241 MiB | |

propslint's footprint is 0.2 GB (MEASURED, recorded at lakefile.toml:41-44).

## The bursts

Three distinct check.sh runs in one worktree made the three largest bursts. Each was the only `heavy-lock.mjs`
process in its sample (MEASURED):

| Sample | Heavy-lock start | Lean procs in check.sh | Their RSS |
|---|---|---|---|
| i=27 | 17:10:10 | 7 | 4664 MiB |
| i=34 | 17:12:21 | 6 | 4901 MiB |
| i=38 | 17:14:06 | 7 | 3746 MiB |

Beside every burst, outside the heavy lock (MEASURED):

- an agent's direct `lake build Fw.Obs.Golden Fw.Ops.Golden` in another worktree, alive at least 423 s, 240-413 MiB
  RSS, `top` 176 MB MEM plus 115 MB compressed;
- the lean-lsp-mcp `lake serve` tree and the Serena Lean server, about 785 MiB footprint between them, mostly
  compressed;
- the console `fwcore` child.

The fourth peak (i=23, 1.9 GiB) was `fw land --queue` running fwcore-build.sh in the main checkout, which passes the
lake slot only.

VM counters at the bursts against the samples just before (MEASURED):

| Counter | Before | Burst |
|---|---|---|
| Compressor | 5259-5551 MB | 5888-6224 MB |
| Wired | 3550-3650 MB | 4026-4076 MB |
| Active plus inactive | | 1.0-1.2 GB lower |
| Swap-outs (cumulative) | 12491230 | 12491230 |
| Swap used | 3677-3762 of 5120 MB | same |
| Pressure level | 2 (warn) from i=25 | 2 |
| Load (8 cores) | 13-18 | 20-29 |

The bursts compressed about 0.4-0.7 GB and swapped nothing. That shift fits about 1.7 GiB of new anonymous memory
plus the olean pages, not 5 GiB (INFERRED).

The mechanism, in order:

1. check.sh asks the heavy lock with no other holder. `verdict` admits at n=0 before it reads swap or free memory
   (CONFIRMED Heavy.lean:78-80). The swap check at line 82 never runs.
2. `lake_slot_hold` sets the group width to `stage2Width = min (width i) (max cores 1)`, 8 here (CONFIRMED
   LakeSlot.lean:59, lake-slot-lib.sh:65-77). The budget is cores plus a clean-build flag (LakeSlot.lean:43). Memory
   and swap are not inputs.
3. The agent's build, the two Lean servers and land builds run outside the holder count, so the lock sees n=0 while
   other Lean work is live.

Fix 6 of the node-resources report estimated about 2.5 GiB saved by gating these bursts. That estimate counts RSS.
In footprint, the reachable saving is roughly the jobs above width 4: about 4 × 0.23 GiB, near 0.9 GiB (INFERRED).

## Fix as a daemon lease kind (stage 1b)

The design scratch for fw-sup stage 1b turns the lake slot, heavy lock and sim lock into daemon leases and charges
`max(cost, observed footprint)` in `Fw.Sup.step`. The lease kind for Lean:

- Kind `lean`, a job lease (the client spawns the job under a ticket; the job holds the flock). Cost
  `{cores = width, footMB = width × 256}` plus one shared charge of 1536 MB per (toolchain, `.lake` tree) key, charged
  once however many jobs read that tree.
- The grant carries `width`. The daemon computes it from its own observation (pressure level, swap percent, room
  left after other charges) with the rule written for the interim fix below, floor 1 for liveness.
- check.sh takes the lease once and passes the nested token in its environment (`nested_no_wait`), so its
  fwcore-build.sh and `lake build` children do not queue behind their parent.
- `lake serve` trees and the Serena Lean server are service leases, or external charges at their `top` footprint when
  the daemon did not start them. The `lspServe` idle teardown (Reap.lean:46 `isTool`) frees them.
- Agents' direct `lake build`, `lake env`, `lake test` and `lake exe` run through `fw run --lease lean`. The cap.mjs
  Lean classifier (task sup-enforce) routes them; cap.mjs routes no `lake` command today (CONFIRMED).
- The lean-lsp-mcp `lean_build` tool is disabled in `.mcp.json` or wrapped, because it calls `lake build` directly
  (build_utils.py:173).
- Stage 0 baseline logging (task sup-baseline) records footprint from `top` or `proc_pid_rusage`, not ps RSS, and logs
  heavy acquire and release. No heavy-lock span exists in timings.jsonl today (MEASURED).

## Interim fix without the daemon

I1, one holder registry. Every Lean entry point registers as a heavy-lock holder in `<git common dir>/fw-heavy/holders`
with a per-kind cost:

- `scripts/fwcore-build.sh` wraps its `lake_slot ... lake build` in `heavy-lock.mjs --kind build`; check.sh already
  sets `FW_HEAVY_HELD`, so its nested call skips the queue (heavy-lock.mjs:192).
- The land axiom lint (land-verdict.ts:70) runs `axiom-check.sh` inside the same wrapper.
- `scripts/lake-slot.sh` gains the wrapper, and agent instructions and the settings allowlist move from bare `lake ...`
  to `sh scripts/lake-slot.sh ...`. The allowlist is `.claude/settings.json`, a user edit.
- Fix the header comment of heavy-lock.mjs, which names fwcore-build.sh as a caller; it is not one (CONFIRMED).

I2, width from Lean. Add `Fw.Sched.Heavy.width` and have `lake_slot_hold` read it (or export `LEAN_NUM_THREADS` from
it):

| Condition | Width |
|---|---|
| pressure normal and swap at or under `swapPct` | `stage2Width` |
| pressure warn, or swap over `swapPct` | ⌈`stage2Width` / 2⌉ |
| pressure critical | 1 |

Each row gets its own theorem, plus `width_pos` and `width_le` against `stage2Width`. Replace `jobMB 5000`
(Heavy.lean:31-37, sized from summed RSS) with 256 MB per job plus 1536 MB shared, and log acquire and release spans.

Limits of the interim fix (INFERRED):

- Swap sat at 72% all day, so with I1 the swap gate makes the cap 1 and I2 makes the width 4. check.sh's parallel
  group would take longer, up to about 2x its 27.6 s p50.
- A rule on free MB alone would not have narrowed these bursts: available memory was about 7.7 GB at 48%.
- Agents can still call bare `lake` until the allowlist changes. I1 covers the scripted paths without it.

## What this changes in the plan

| Section | Change |
|---|---|
| daemon-design design.md §3 cost table | add the `lean` kind with footprint cost (256 MB per job plus 1536 MB per tree key) and a granted width |
| daemon-design design.md §5 stage 1b row | the lease covers fwcore-build.sh, land axiom lint, agent `lake *`, `lake serve`, Serena Lean and `lean_build`, not only check.sh |
| work-graph task sup-baseline | sample footprint via `top` or `proc_pid_rusage`; log heavy-lock acquire and release spans |
| work-graph task sup-enforce | the cap.mjs Lean classifier routes `lake build`, `lake env`, `lake test` and `lake exe` |
| node-resources report, fix 6 | saving is about 0.9 GiB of footprint, not 2.5 GiB; the cause is gate coverage and width, not one oversized job |
| PLAN §8.3, settings allowlist (user edit) | replace `lake build*`, `lake env lean *`, `lake test*`, `lake exe *` with the `scripts/lake-slot.sh` form; disable `lean_build` in `.mcp.json` |
| new task (Lean first) | `Fw.Sched.Heavy.width` and the footprint cost, proved, then wired into lake-slot-lib.sh and fwcore-build.sh |
