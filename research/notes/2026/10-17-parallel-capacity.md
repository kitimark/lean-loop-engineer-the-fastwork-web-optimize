---
id: 2026-10-17-parallel-capacity
kind: note
title: "Machine capacity for parallel agent work (M1 Pro 8 cores, 16 GB)"
date: 2026-10-17
---

Status tags: CONFIRMED (source or probe), MEASURED, INFERRED. Machine: 8 cores (6P+2E), 16 GB, Docker VM 8 CPUs / 7.75 GiB / 1 GiB swap
(Docker settings-store: Cpus 8, MemoryMiB 8192, SwapMiB 1024). Probe taken at load1 ~330-440, swap 3.5 of 5 GB used, ~75 MB free pages: the machine is oversubscribed.

## 1. Lake / Lean parallelism
- CONFIRMED: Lake has **no `-j`/`--jobs` flag**. `grep jobs|threads src/lake/Lake/CLI/{Main,Help}.lean` finds only `--fail-fast` ("stop scheduling new build jobs", Help.lean:62). Lake runs build jobs as Lean `Task`s on the process-wide task manager.
- CONFIRMED: the pool size is `LEAN_NUM_THREADS` if set, else `hardware_concurrency()` = 8 here (lean4@eb6cafb src/runtime/object.cpp:1106-1113; thread.h:53 = std::thread::hardware_concurrency). So one `lake build` may run up to 8 `lean` jobs' worth of tasks.
- CONFIRMED: each child `lean` has its own flag `-j/--threads=num` (src/util/shell.cpp:182, `{"threads", required_argument, 0, 'j'}`; manager built at shell.cpp:353). Lake does not forward a cap, so the env var is the lever; children inherit it.
- Cap per agent: `LEAN_NUM_THREADS=2 lake build` (MEASURED: accepted, 67-job no-op in 0.37 s). INFERRED: a clean 25-module build is mostly a dependency chain, so 2 threads cost little wall time.
- The module dependency graph limits real parallelism more than the pool does (INFERRED).

## 2. Build sharing across worktrees
- MEASURED: scratch `git worktree add --detach` of HEAD, `cp -c -R <main>/lean/.lake .lake` took **0.22 s** (APFS clone, 603 MB logical, ~0 extra disk until written). `LEAN_NUM_THREADS=2 lake build` then took **0.37 s**, "Build completed successfully (67 jobs)", nothing rebuilt (trace hashes depend on file content and toolchain, not on the checkout path). Worktree removed afterwards.
- Existing worktrees: 26 under .claude/worktrees; 14 have a lean/.lake of 38 MB to 603 MB (sum ~5.3 GB logical); each was built from scratch. Each also has its own node_modules (~310 MB).
- Recommendation: spawn step for a lean worktree = `cp -c -R <main>/lean/.lake <wt>/lean/.lake` (0.2 s) before any `lake build`. Only works when the worktree base commit equals main's lean sources (else Lake rebuilds just the changed modules and their dependents, still much cheaper than clean).
- Lake artifact cache (src/lake/Lake/Config/Env.lean:43-56,135,177): `LAKE_ARTIFACT_CACHE=true` plus `LAKE_CACHE_DIR=<shared dir>` puts artifacts in a content-addressed cache shared across workspaces (PackageConfig.lean:280-289: default is read-only use). INFERRED: also works, but not probed; the APFS clone is simpler and proven.

## 3. Simulator
- MEASURED (loadsample/load.jsonl, 10 samples): `sim` process count 165 -> 192 while booted, then 21 at the last sample after shutdown. A boot adds ~170 processes (launchd_sim children, SpringBoard, backboardd, etc.). Baseline with nothing booted is ~21 (CoreSimulatorService etc.).
- During the booted window `idle` was 0.0% for 3 samples (boot storm, with lake builds on top), then 40-64% idle.
- RSS by ps: CoreSimulatorBridge 69 MB, simulator runtime processes ~1 GB summed (excluding a shared-mapping artifact of 16 GB). INFERRED: ~1.5-2.5 GB RAM per booted iPhone device.
- simctl: `boot <device>` (or `bootstatus <device> -b` to boot-and-wait), `shutdown`, `create`/`clone`, `--disabledJob=<launchd job>` on boot to skip services (simctl help boot). Booting an already booted device errors with "current state: Booted" (INFERRED, harmless).
- Keeping one device booted and reusing it is the cheap path: the lane owner boots once, others `simctl launch/openurl` on it. INFERRED: runs can share one device only if serialized (one Safari viewport/state); parallel runs need one device each (~2 GB each). Recommend a single simulator lane with a lock.

## 4. Docker lane
- MEASURED: `docker info`: 8 CPUs, 7.751 GiB, server 28.5.1; Docker settings: 8 CPUs, 8192 MiB, 1024 MiB swap. The VM can use every core, so containers compete with everything else on the host.
- `docker run --cpus <decimal>` and `-m/--memory` exist (docker run --help). INFERRED recommendation: `--cpus 2 -m 1500m` per chromium measure run; 3 concurrent runs then fit the 7.75 GiB VM. Lower Docker Desktop CPUs to 4 to protect the host (settings, needs restart).
- MEASURED: one fw-measure-chromium run was up at probe time.

## 5. Node / vitest
- CONFIRMED (vitest 5.0.5, dist/chunks/index.1TqnEahn.js:1622-1625): default `maxWorkers` = `availableParallelism() - 1` = 7 in run mode, `floor(count/2)` = 4 in watch mode. Overrides: env `VITEST_MAX_WORKERS=<n>` (index:9008-9009), CLI `--maxWorkers <n|%>` (cac:942), config `maxWorkers` (accepts "25%", index:1626-1631), `--no-file-parallelism` forces 1 (index:7531). Old `VITEST_MAX_THREADS` is gone in v5.
- 4 packages run `vitest run`; with pnpm -r in parallel each spawns up to 7 workers (INFERRED: up to ~28 busy processes).
- Cap: `VITEST_MAX_WORKERS=2` per agent.

## 6. Resource model (cores = sustained busy cores while the job runs)

| job | cores | RAM | basis |
|---|---|---|---|
| lake clean build (11k lines) | 4-8 (cap LEAN_NUM_THREADS=2-3) | 1.5-2.5 GB (one lean peaked 2.5 GB RSS) | MEASURED RSS, cores INFERRED |
| lake incremental / cloned .lake | 0.1-2, seconds | 0.3 GB | MEASURED no-op 0.37 s |
| lean-lsp / Serena server | 0.2 idle, 1-2 on edit | 0.5-1 GB | INFERRED |
| vitest run | min(files, 7) | 0.3-1.5 GB | source, RAM INFERRED |
| docker chromium run | 1-2 (with --cpus 2) | 1-1.5 GB | INFERRED |
| simulator (booted + WebKit run) | 1-3 | 1.5-2.5 GB | MEASURED process count, RAM INFERRED |
| model-only agent | ~0 | 0.2-0.3 GB (node 250-280 MB) | MEASURED RSS |

Budget (INFERRED): 8 cores minus 1.5 for OS/Docker VM/WindowServer = ~6.5 usable; 16 GB minus ~4 GB OS and apps = ~12 GB, already swapping (3.5 GB). Admission rule: sum of cores <= 6, RAM <= 10 GB. Example mix that fits: 1 lake incremental (2) + 1 vitest capped (2) + 1 docker run (2) + 8 model-only agents, with at most one clean lake build or one booted simulator at a time. A load1 of 400 means runaway thread counts (many agents each at 8 workers/threads), not 400 busy cores: cap every job.

Caps to export by default in agent worktrees: `LEAN_NUM_THREADS=2`, `VITEST_MAX_WORKERS=2`, `docker run --cpus 2 -m 1500m`, one simulator lock.
