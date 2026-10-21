---
id: 2026-10-21-mem-gate-bypass
kind: note
title: "Lean entry points against the heavy lock and the lake slot: the three 4.2-5.4 GiB bursts are each one check.sh admitted at n=0 and run at width 8 beside ungated Lean work"
status: review
created: 2026-10-21
topics: [lean, memory, heavy-lock, lake-slot, fw-sup, daemon, leases, scheduling]
---

# Lean entry points against the heavy lock and the lake slot

Round 2. Source citations are file:line at main 2edd65b1 (this branch merges it; none of the cited files changed here).
Sample numbers come from the node-resources sampler log `samples.jsonl` (scratch, uncommitted): 46 samples `i=0..45`,
20 s apart, 17:01:32-17:16:33 local on 2026-10-21. Each sample holds `vm_stat` counters, `sysctl vm.swapusage`, the
pressure level (1 normal, 2 warn) and `ps` rows (pid, ppid, RSS, cwd, args). "Tree RSS" sums ps RSS over a process and
all its descendants in one sample.

## Answer

- Only `lean/scripts/check.sh` takes the heavy lock (CONFIRMED check.sh:21; no other caller of `scripts/heavy-lock.mjs`).
  `fw land` builds and check-fast take the lake slot only. The git pre-commit hook, repo `scripts/check.sh`,
  `pnpm test`, the site and gate-breakpoints generators, agents' direct `lake` calls, the lean-lsp-mcp `lake serve` tree,
  its `lean_build` tool and the Serena Lean server take neither gate (table below, CONFIRMED per row).
- Only three samples reach 4.2-5.4 GiB of Lean RSS: i=27 (5565 MiB), i=34 (5560 MiB) and i=38 (4503 MiB). Each was one
  check.sh, the only heavy-lock holder in its sample (MEASURED). The lock admits a lone holder without reading swap or
  memory (CONFIRMED `lean/Fw/Sched/Heavy.lean:80`, `verdict_idle` at :87). Its parallel group then runs up to 8 jobs,
  a width from cores alone (CONFIRMED check.sh:134-136, `LakeSlot.lean:43,59`). Beside each burst ran an agent's
  direct `lake build`, the lean-lsp-mcp `lake serve` tree, the Serena Lean server and the console `fwcore` child, none
  of which the lock counts (MEASURED). The node-resources report's "fourth peak" is i=23 (1782 MiB: a `fw land`
  fwcore-build in land worktree `land-wt/0`, tree 1701 MiB) or i=28 (3277 MiB, the tail of the i=27 run).
- Summed ps RSS overstates the burst. Shared mmapped `.olean` pages count once per process, so per-job RSS is 2.4-6.4x
  the job's peak footprint (MEASURED, three runs below). The VM counters move 1.1-1.6 GB per burst, not 4-5 GiB
  (MEASURED); that fits RSS double counting (INFERRED).
- `vm_stat` free memory was 58-1809 MB over the window, median 118 MB, 39 of 46 samples at or under 330 MB (MEASURED).
  The 58 MB at i=34 is the window minimum but not unusual: it marks no burst on its own.
- Had a second job been a holder, the swap gate would have held it back: swap use was 71.8-73.5% in all 46 samples
  against the 60% limit (MEASURED; CONFIRMED `Heavy.lean:82`, `verdict_swap_blocks` at :139). Whether the memory gate
  would also have bitten is unknown (INFERRED, see "Memory gate at the bursts"): it waits at a `memory_pressure` free
  percentage of 43% or less, three readings gave 48%, 40% and 43%, and the samples hold no free percentage.
- Fix: a `lean` lease kind in fw-sup stage 1b, charged by footprint, whose grant carries a width, taken by every batch
  Lean entry point. Interim: I1, the batch entry points register as heavy-lock holders, with a `land` kind admitted
  at once so lands never queue behind agents (I1-L); I2, a width decided in Lean. I1 without I1-L stalls lands: at swap
  above 60% the cap is 1 all day.

## Entry points

Sweep for `lake` call sites (run at 1186e05e, 281 hits; the rows below are every executing site, the rest are comments,
usage strings, tests of parsers and goldens):

```
git grep -n -I -E '(^|[^a-zA-Z_-])lake[" ,]+(build|env|exe|test|serve|update|clean|run|lean|script|check)' -- scripts apps packages .claude lean/scripts package.json '*.json' ':!**/node_modules/**' ':!**/*.md' ':!**/*.jsonl' ':!**/golden/**'
git grep -n -E "(spawn|spawnSync|execFileSync|execSync|execFile|exec)\(['\"]lake|\[['\"]lake['\"]" -- apps packages scripts lean .claude ':!**/node_modules/**'
```

Columns. Gates: CONFIRMED at 2edd65b1. "Peak (samples)": max tree RSS with its sample index, MEASURED. "Footprint":
`/usr/bin/time -l` peak memory footprint (runs below) or `top` MEM at round 1, MEASURED. "Today": spans in
`.fw-console/timings.jsonl` since local midnight (count, p50, max), or Bash tool calls in today's transcripts matched
by command regex (heredocs skipped, so a lower bound), or `git log`; read at 18:15.

| # | Entry point | Heavy lock | Lake slot | Peak (samples) | Footprint | Today |
|---|---|---|---|---|---|---|
| 1 | `sh lean/scripts/check.sh` (agent, any worktree) | yes, check.sh:21 | parallel group check.sh:134-136 | 5260 MiB, 24 procs (i=34) | 0.21-0.24 GiB per job | 240 parallel groups, p50 27.7 s, max 110.0 s; 137 Bash calls |
| 2 | check.sh serial build stage (check.sh:35 `fwcore-build.sh`) | inside row 1 | scripts/fwcore-build.sh:39-40 | in row 1 | 0.24 GiB per `lean -o` | 247 spans, p50 0.7 s, max 303.3 s |
| 3 | check.sh axiom check (lean/scripts/axiom-check.sh:10,17) | inside row 1 | no | 781 MiB (i=38) | not run | 240 spans, p50 7.1 s, max 21.4 s |
| 4 | `fw land` check.sh in the land worktree (apps/runner/src/land.ts:293) | yes, check.sh:21 | as row 1 | as row 1 | as row 1 | 5 spans, p50 34.3 s, max 41.5 s |
| 5 | `fw land` phase 1 `sh scripts/fwcore-build.sh` (land.ts:665) | no | fwcore-build.sh:40 | 1701 MiB, 7 procs (i=23, `land-wt/0`) | as row 2 | 70 spans, p50 20.2 s, max 332.1 s |
| 6 | `fw land --queue` rebuild in the main checkout (apps/runner/src/fw.ts:147); remote build `BUILD_ARGV` (apps/runner/src/land-remote.ts:299) | no | fwcore-build.sh:40 | 61 MiB (i=22) | as row 2 | 52 rebuild spans, p50 0.8 s, max 28.4 s |
| 7 | land axiom lint (apps/runner/src/land-verdict.ts:70) | no | the `lake build` part; `axiom-check.sh` outside | not sampled | not run | 12 spans, p50 10.3 s, max 54.6 s |
| 8 | git pre-commit hook: scripts/hooks/pre-commit:13 `node scripts/checkmap.mjs --staged`; checkmap.mjs:70 spawns the argv of lean/Fw/Ops/CheckMap.lean:225 (`lake build`, staged module or lakefile) and :226 (`lake env lean <script>`, staged lean/scripts file); checkmap.mjs:132 `lake env lean --stdin` (preset check) | no | no | not sampled | as rows 10-11 | 162 commits touched `lean/` (`git log --all --no-merges --since 2026-10-21 -- lean`); 185 `git commit` Bash calls. Skipped when `FW_LAND_TOKEN` is set (pre-commit:12) |
| 9 | repo `sh scripts/check.sh` (scripts/check.sh:12 `exec node checkmap.mjs`) | no | no | not sampled | as row 8 | 7 Bash calls |
| 10 | agent `lake build ...` (.claude/settings.json:162 allows it; .claude/agents/lean-prover.md:12 asks for it) | no | no | 719 MiB (i=2, `lake build Fw.Wire.Obs`) | 0.24 GiB per `lean -o` | 106 Bash calls |
| 11 | agent `lake env lean ...` (settings.json:163) | no | no | see runs below | 0.21-0.23 GiB | 196 Bash calls |
| 12 | agent `lake test` / `lake exe` (settings.json:164-165) | no | no | not sampled | not run | 20 / 1 Bash calls |
| 13 | lean/scripts/check-fast.sh:33-34 (`fwcore-build.sh`, then `lake test`) | no | build only | not sampled | as row 2 | 6 Bash calls |
| 14 | root `pnpm test` (package.json:10 runs `pnpm lean:build`, package.json:9 `cd lean && lake build`) | no | no | not sampled | as row 2 | at most 68 `pnpm test` Bash calls (the regex also counts package-level runs, which do not build Lean) |
| 15 | site: apps/site/package.json:10 `gen:breakpoints` (`lake exe breakgen`); apps/site/scripts/check-breakpoints.mjs:9 (`lake exe breakgen --check`, run by the site `build` scripts, package.json:7-9) | no | no | not sampled | not run | 0 Bash calls matched |
| 16 | gate-breakpoints generators: scopegen.mjs:21 (`lake build fwcore`) and :36, settlegen.mjs:23, freezegen.mjs:23, src/images/armgen.mjs:18 (`lake env lean --run`); test/freeze.test.mjs:160 (in that package's `test`) | no | no | not sampled | not run | 6 Bash calls |
| 17 | scripts/math-pending.mjs:129 `lake exe mathview` | no | no | not sampled | not run | 2 Bash calls |
| 18 | lean/scripts/mutants.sh:119,168-181 (`lake build`, `lake test`; full pass on CI) | no | no | not sampled | not run | 1 Bash call |
| 19 | lean-lsp-mcp `lake serve` tree: .mcp.json:17-27 starts `lean-lsp-mcp==0.31.0`; leanclient 0.13.2 `leanclient/base_client.py:66` spawns `lake serve` | no | no | 915 MiB (i=6) | about 465 MiB idle (`top`, round 1) | 40 MCP calls |
| 20 | lean-lsp-mcp `lean_build` tool: lean-lsp-mcp 0.31.0 `lean_lsp_mcp/build_utils.py:173` runs `lake build`; not in `--disable-tools` (.mcp.json:25-26) | no | no | not sampled | as row 2 | 0 calls |
| 21 | Serena Lean `lean --server` (serena-lean MCP server, uvx) | no | no | 0 MiB RSS (pid 92565 at i=27, 34, 38: paged out) | 320 MiB, 319 MiB of it compressed (`top`, round 1) | one server |
| 22 | console-api `fwcore` child (apps/console-api/src/core/lean.ts:113) | no | no | 19-22 MiB (pid 13443, i=27, 34, 38) | | resident |

Not an entry point: apps/runner/src/lake-gc.ts:48 runs `lake env printenv LAKE_CACHE_DIR`, which starts no `lean`.

Per-job footprint, one run each against the main checkout's built `.lake`, read-only. Command form: `LEAN_PATH` from
`lake env printenv LEAN_PATH`, then `/usr/bin/time -l <toolchain>/bin/lean <args>`; that equals
`lake env /usr/bin/time -l lean <args>`. The form `/usr/bin/time -l lake env lean <args>` measures `lake` itself
(about 12 MB) and misses `lean`.

| Job | Max RSS | Peak footprint | RSS / footprint | Wall |
|---|---|---|---|---|
| `lean --run scripts/HeavyGolden.lean --check` | 1259 MiB | 213 MiB | 5.9 | 9.8 s |
| InitCostLint import of `Main` (stopped early: import cost only) | 1479 MiB | 231 MiB | 6.4 | 2.7 s |
| `lean Fw/Ops/Obs.lean -o <scratch>` | 583 MiB | 241 MiB | 2.4 | 5.8 s |

propslint's footprint is 0.2 GB (MEASURED earlier, recorded at lean/lakefile.toml:42-45).

## The bursts

The three samples at 4.2-5.4 GiB, from `samples.jsonl` (MEASURED). "Lean RSS" sums every `lean`, `lake`, `propslint`
and `fwcore` process in the sample. The check.sh tree is rooted at its outermost `sh scripts/check.sh` in worktree
`wf_27cbc28d-204-1`; its jobs column counts `lean` plus `propslint` processes.

| Sample | Time | Lean RSS (all) | check.sh tree | Its lean + propslint jobs | Their RSS | Heavy-lock pid |
|---|---|---|---|---|---|---|
| i=27 | 17:10:33 | 5565 MiB, 22 procs | 5020 MiB, 25 procs | 6 + 1 | 4663 MiB | 55269, the only one |
| i=34 | 17:12:53 | 5560 MiB, 21 procs | 5260 MiB, 24 procs | 5 + 1 | 4901 MiB | 2951, the only one |
| i=38 | 17:14:13 | 4503 MiB, 22 procs | 4204 MiB, 28 procs | 6 + 1 | 3746 MiB | 13550, the only one |

Their tails: i=28 3277 MiB Lean RSS, i=35 1582 MiB, i=39 1605 MiB. The other Lean peak in the window is i=23: 1782 MiB
Lean RSS, of which 1701 MiB (7 procs, 4 `lean`) is pid 38650 `sh scripts/fwcore-build.sh` with cwd
`.claude/land-wt/0`, child of `fw.ts land --queue worktree-wf_b4f30eab-54a-1`: the phase-1 build in a land worktree
(land.ts:665), which takes the lake slot only. The main-checkout fwcore-build at i=22 was 61 MiB.

Beside every burst, outside the heavy lock (MEASURED, same samples):

- pid 39611, an agent's direct `lake build Fw.Obs.Golden Fw.Ops.Golden` `lean` in worktree `wf_21068a14-405-1`: 413,
  240 and 250 MiB RSS at i=27, 34, 38; alive from i=24 to i=45 (etime 423 s at the last sample);
- the lean-lsp-mcp tree pids 99718/99720/99725 (`lake serve`, `lean --server`, one `lean --worker`): 80, 49 and 49 MiB
  RSS;
- the Serena `lean --server` pid 92565: 0 MiB RSS (paged out or compressed);
- the console `fwcore` child pid 13443: 19-22 MiB.

VM counters per burst, the sample before against the burst sample (MEASURED):

| Counter | i=26 → i=27 | i=33 → i=34 | i=37 → i=38 |
|---|---|---|---|
| Compressor (MB) | 5551 → 6224 (+673) | 5259 → 5888 (+629) | 5190 → 5288 (+98) |
| Wired (MB) | 3575 → 4026 (+451) | 3685 → 4045 (+360) | 3467 → 4076 (+609) |
| Active + inactive (MB) | 6520 → 5319 (−1201) | 6345 → 5634 (−711) | 6844 → 6140 (−704) |
| Free (MB) | 84 → 60 | 235 → 58 | 185 → 69 |
| Swap-outs (cumulative) | 12491230 → 12491230 | same | same |
| Swap used (MB of 5120) | 3708.94 (72.4%) | 3676.88 (71.8%) | 3676.88 (71.8%) |
| Pressure level | 2 → 2 | 2 → 2 | 2 → 2 |
| Load, 1 min | 16.04 → 20.84 | 27.29 → 28.90 | 21.33 → 18.33 |

Window context: pressure was 2 at i=8-15 and from i=25 to the end, 1 otherwise; swap-outs rose by 148 between i=8
and i=9 and not after; swap use stayed between 71.8% and 73.5%.

Each burst moved 0.1-0.7 GB into the compressor and 0.4-0.6 GB into wired memory while active plus inactive pages fell
0.7-1.2 GB, with no swap-out. That is 1.1-1.6 GB of change per burst, not the 4-5 GiB that RSS sums show. It fits
several `lean` jobs of about 0.2 GiB footprint each plus file pages they share (INFERRED: the counters do not split
anonymous from file-backed memory).

The mechanism, in order:

1. check.sh asks the heavy lock with no other holder. `verdict` admits at n=0 before it reads swap or memory
   (CONFIRMED Heavy.lean:79-80). The swap check at :82 is never reached.
2. `lake_slot_hold` sets the group width to `stage2Width = min (width i) (max cores 1)`, 8 on this Mac (CONFIRMED
   LakeSlot.lean:59, scripts/lake-slot-lib.sh:65-77). The budget is cores plus a clean-build flag (LakeSlot.lean:43);
   memory and swap are not inputs.
3. The agent's build, the two Lean servers and land builds run outside the holder count, so the lock sees n=0 while
   other Lean work is live.

## Memory gate at the bursts

`heavy-lock.mjs` takes `freeMB` as the `memory_pressure` "free percentage" times total memory (CONFIRMED
scripts/heavy-lock.mjs:78-90), not `vm_stat` free pages. The gate waits when `freeMB < jobMB + reserveMB` = 5000 + 2048
= 7048 MB (CONFIRMED heavy-lock.mjs:22, Heavy.lean:83). On 16384 MB that is a free percentage of 43% or less
(43% gives 7045 MB).

| Reading | Free percentage | freeMB | Memory gate |
|---|---|---|---|
| round 1 (about 17:20) | 48% | 7864 | admits |
| round-1 review | 40% | 6553 | waits |
| round 2, 18:15:03 (`memory_pressure -Q`) | 43% | 7045 | waits |

The readings fall on both sides of the threshold, and the sampler did not log the free percentage, so its value at
i=27, 34 and 38 is unknown. Whether the memory gate would have held back a second holder at the bursts is therefore
not known (INFERRED either way). The swap gate would have (MEASURED swap 71.8-73.5%; at 18:15:03 swap was 4606.62 of
5120 MB, 90.0%).

## Fix as a daemon lease kind (stage 1b)

The fw-sup stage 1b design (scratch) turns the lake slot, heavy lock and sim lock into daemon leases and charges
`max(cost, observed footprint)` in `Fw.Sup.step`. The lease kind for Lean:

- Kind `lean`, a job lease (the client spawns the job under a ticket; the job holds the flock). Cost
  `{cores = width, footMB = width × 256}` plus one shared charge of 1536 MB per (toolchain, `.lake` tree) key, charged
  once however many jobs read that tree (INFERRED sizes: 213-241 MiB per job measured above; the shared charge is not
  measured).
- The grant carries `width`. The daemon computes it from its own observation (pressure level, swap, room left after
  other charges) with the I2 rule below, floor 1 for liveness.
- check.sh takes the lease once and passes the nested token in its environment (`nested_no_wait`), so its
  fwcore-build.sh and `lake build` children do not queue behind their parent.
- Batch entry points that take it: rows 1-18 of the table, among them the pre-commit hook and repo `scripts/check.sh`
  (wrap the `lakeBuild`, `leanElab` and preset argv in checkmap.mjs), root `pnpm test`, the site and gate-breakpoints
  generators, math-pending and mutants.
- `lake serve` trees and the Serena Lean server are service leases, or external charges at their `top` footprint when
  the daemon did not start them. The `lspServe` idle teardown (lean/Fw/Ops/Reap.lean:46 `isTool`) frees them.
- Agents' direct `lake build`, `lake env`, `lake test` and `lake exe` run through `fw run --lease lean`, routed by the
  cap.mjs Lean classifier (task sup-enforce); cap.mjs routes no `lake` command today (CONFIRMED).
- The lean-lsp-mcp `lean_build` tool is disabled in `.mcp.json` or wrapped, because it runs `lake build` directly.
- Stage 0 baseline logging (task sup-baseline) records footprint from `top` or `proc_pid_rusage`, not ps RSS; logs the
  `memory_pressure` free percentage and the swap-out count with each sample; and logs heavy-lock acquire, wait and
  release spans. timings.jsonl has no heavy-lock span today (MEASURED: its only "heavy" steps are the golden check
  and a test suite).

## Interim fix without the daemon

I1, one holder registry for the batch entry points. Each registers as a heavy-lock holder in
`<git common dir>/fw-heavy/holders`:

- `scripts/fwcore-build.sh` wraps its `lake_slot ... lake build` in `heavy-lock.mjs --kind build`; check.sh already
  sets `FW_HEAVY_HELD`, so the nested call skips the queue (heavy-lock.mjs:192).
- `scripts/checkmap.mjs` wraps the argv of `lakeBuild`, `leanElab` and the preset check (checkmap.mjs:70,132), which
  covers the pre-commit hook and repo `scripts/check.sh`.
- The land axiom lint (land-verdict.ts:70) runs `axiom-check.sh` inside the same wrapper.
- `scripts/lake-slot.sh` gains the wrapper; agent instructions and the settings allowlist move from bare `lake ...`
  to `sh scripts/lake-slot.sh ...`. The allowlist is `.claude/settings.json`, a user edit.
- Root `pnpm test` (package.json:9) and the generators of rows 15-17 call `sh scripts/lake-slot.sh` instead of bare
  `lake`.
- Servers stay outside I1 on purpose: `lake serve`, Serena's `lean --server` and the console `fwcore` child are
  long-lived, and one long-lived holder at cap 1 would block every batch job for its whole life. They wait for stage
  1b service leases.
- Fix the header comment of heavy-lock.mjs (line 2), which names fwcore-build.sh as a caller; it is not one
  (CONFIRMED by the sweep).

Cost of I1 as written (INFERRED from the code paths, with today's counts as MEASURED inputs). Swap use was above the
60% limit in every sample, so the swap gate makes the effective cap 1 (Heavy.lean:81-82; the docstring at
Heavy.lean:24-25 says the same). I1 would then serialize, machine-wide: agents' check.sh (240 parallel groups today,
p50 27.7 s), land phase-1 builds (70, p50 20.2 s, max 332.1 s), queue rebuilds (52, max 28.4 s), land axiom lints
(12, max 54.6 s) and every wrapped agent build (106 `lake build` and 196 `lake env` calls). For lands:

- A land build waiting past `maxWaitS` 1800 s exits 75 with "waited N s" (heavy-lock.mjs:167, 193). That text does
  not match `LOAD_FAILURE_RE` (land.ts:386), so the land does not rerun it alone (land.ts:724): it is refused.
- On the pre-lock path the phase-1 build runs in a land worktree with no land lock (land.ts:793-796): the wait
  delays this land and, through the queue's synchronous rebuild (fw.ts:147), every land behind it.
- On the locked fallback the merge is open in the main checkout while the checks run (land.ts:885-887): for the
  whole wait the pre-commit land guard (scripts/hooks/pre-commit:9-10) refuses every commit in the main checkout.
- The land's own check.sh (land.ts:293) already queues behind agents' check.sh today, since check.sh:21 takes the
  lock in the land worktree too (CONFIRMED). I1 adds the phase-1 build and the lint to that exposure.

I1-L, the variant that does not stall lands. Add a holder kind `land`:

- A `land` job is admitted at once: no cap, swap or memory check. It still counts as a holder for every other kind,
  so with swap high nothing else is admitted beside it.
- At most one `land` holder exists, because `fw land` runs one land at a time (land lock land.ts:885-899, queue); the
  Lean statement takes that as a hypothesis.
- `fw land` sets the kind for everything it starts (phase-1 build, queue rebuild, axiom lint, its check.sh), for
  example `FW_HEAVY_KIND=land`.
- Lean: `verdict` gains the kind; theorems `verdict_land_admits` (a land job never waits) and `verdict_land_counts`
  (a land holder raises n for the other kinds), next to the existing ones per OR-branch.
- Cost: an agent's check.sh or build waits for a land build (p50 20.2 s, max 332.1 s today), not the reverse. At most
  two heavy jobs run at once: one land plus one admitted before it, the current `capMax` 2.

I2, width from Lean. Add `Fw.Sched.Heavy.width` and have `lake_slot_hold` read it (or export `LEAN_NUM_THREADS` from
it):

| Condition | Width |
|---|---|
| pressure normal and swap at or under `swapPct` | `stage2Width` |
| pressure warn, or swap over `swapPct` | ⌈`stage2Width` / 2⌉ |
| pressure critical | 1 |

Each row gets its own theorem, plus `width_pos` and `width_le` against `stage2Width`. Replace `jobMB 5000`
(Heavy.lean:34, sized from summed RSS) with 256 MB per job plus 1536 MB shared, and log acquire and release spans.

Accepted limits of the interim fix:

- Swap stayed at 71.8-73.5%, so I2 halves the width all day (8 to 4). check.sh's parallel group would take longer,
  up to about 2x its 27.7 s p50 (INFERRED).
- The swap gate reads swap in use, which stayed above 60% while swap-outs were flat from i=9 to i=45 (MEASURED). As
  a signal it says "swapping" all day. A gate on the swap-out rate is a follow-up, not part of I1.
- Agents can still call bare `lake` until the allowlist changes; I1 covers the scripted paths without that edit.

## Round-1 findings

| # | Finding | Answer |
|---|---|---|
| 1 | entry points missing (pre-commit, repo check.sh, `pnpm test`, site) | fixed, lines 45-84: rows 8, 9, 14, 15, plus 4, 13, 16-18 from the sweep (commands at lines 50-53); I1 (line 201) and the lease list (line 175) cover them |
| 2 | memory-gate claim tagged MEASURED | fixed, lines 36-39 and 157-173: INFERRED, threshold 43%, readings 48/40/43%; sup-baseline logs the free percentage (plan table) |
| 3 | free memory range | fixed, line 34: 58-1809 MB, median 118 MB, 39 of 46 at or under 330 MB |
| 4 | VM table ranges, i=38 | fixed, lines 126-145: per-burst table from i=26/27, 33/34, 37/38; inference softened |
| 5 | four bursts vs three | fixed, lines 24-32 and 100-117: three samples, i=23 and i=28 named as the report's fourth peak; same in the plan table (node-resources fix 6) |
| 6 | i=23 location | fixed, lines 112-116: land worktree `land-wt/0`, land.ts:665; main checkout at i=22 was 61 MiB |
| 7 | ratio 2.4-6.9x | fixed, lines 31-33 and 87-96: 2.4-6.4x from the table, command form stated |
| 8 | I1 cost understated | fixed, lines 201-267: I1 covers batch entry points only, servers excluded on purpose (line 215), land cost (line 221), I1-L (line 236) |
| 9 | citation hygiene | fixed, rows 19-22 (lines 80-83): versions and package paths for lean-lsp-mcp 0.31.0 and leanclient 0.13.2, full lean.ts path; handoff names the commit |

Corrections against round 1 found while re-deriving: the direct agent build peak is 719 MiB (i=2), not 921 MiB (that
summed two builds at i=24); the console `fwcore` child is 19-22 MiB RSS, not 248 MiB; lean-lsp MCP calls today are 40, counted by the tool-name prefix `mcp__lean-lsp__`.

## What this changes in the plan

| Section | Change |
|---|---|
| daemon-design design.md §3 cost table | add the `lean` kind with footprint cost (256 MB per job plus 1536 MB per tree key) and a granted width |
| daemon-design design.md §5 stage 1b row | the lease covers rows 1-18 (check.sh, fwcore-build.sh, land lint, pre-commit/checkmap, repo check.sh, `pnpm test`, site and gate-breakpoints generators, math-pending, mutants, agent `lake *`, `lean_build`); `lake serve` and Serena Lean are service leases |
| work-graph task sup-baseline | sample footprint via `top` or `proc_pid_rusage`; log the `memory_pressure` free percentage and swap-outs per sample; log heavy-lock acquire, wait and release spans |
| work-graph task sup-enforce | the cap.mjs Lean classifier routes `lake build`, `lake env`, `lake test` and `lake exe` |
| node-resources report, fix 6 | three bursts (i=27, 34, 38), each one check.sh, not four; the fourth peak is i=23 (land-wt/0 fwcore-build, 1.7 GiB) or i=28 (tail); saving about 0.9 GiB of footprint (jobs above width 4 at about 0.23 GiB), not 2.5 GiB |
| PLAN §8.3, settings allowlist (user edit) | replace `lake build*`, `lake env lean *`, `lake test*`, `lake exe *` with the `scripts/lake-slot.sh` form; disable `lean_build` in `.mcp.json` |
| new task (Lean first) | `Fw.Sched.Heavy` kind `land` (I1-L) and `width` (I2) with footprint cost, proved, then wired into heavy-lock.mjs, checkmap.mjs, fwcore-build.sh, lake-slot-lib.sh and land.ts |
