# Resource audit: Lean, Node and browser processes (2026-10-20)

User request: our Lean, node and related processes take a lot of memory and CPU; use less with the same or better speed. Local ps/top measurements on the dev Mac (8 cores, 16 GB); these are local debug observations, not CI results. Four agents: three investigators and an adversarial check. The check's ranking decides the build tasks (graph d8103b04).

Cleanup already done (user ran it): 8 leaked lean-lsp lake serve trees for removed worktrees, an orphan console-api from a removed worktree and a 3-day-old orphan headless Chrome stopped; swap 7.5 -> 3.9 GB.


---

## Adversarial check of the resource-fix proposals (2026-10-20 18:30-18:45)

Read-only. No process signalled, no tracked file edited. One local probe (under 10 s): `node -e 0` and wait-guard.mjs
start cost (25-30 ms, 42-49 MB peak). It is a debug measurement, not a CI result.
`LLM` = `~/.cache/uv/archive-v0/ztfN-5nOXtZi_RlyfqoOO/lib/python3.14/site-packages` (lean-lsp-mcp 0.31.0, leanclient 0.13.2).
Machine: 8 cores (6P + 2E), 16 GB RAM, swap 4.1 of 5.1 GB used at 18:34 (MEASURED, `sysctl`).

## Corrections to the three reports
- orphans.md says lean-lsp eviction is "LRU" and that `lake serve` runs in the session's pgid. Both are wrong per source.
  Eviction pops the first-inserted key (`LLM/lean_lsp_mcp/client_utils.py:142-147`), so it is FIFO; lean-servers.md is right.
  leanclient starts the server with `start_new_session=True` (`LLM/leanclient/aio/transport.py:93`) and closes it with
  `killpg` (:123-138), so each tree is its own group (CONFIRMED source; the trees are gone, so this cannot be re-measured).
  Signalling a tree's group is therefore safe, but only after checking that pgid == pid.
- The 8 trees, the orphan console-api and the orphan Chrome had all exited by 18:25. `ps` at 18:33 shows no `lake serve`
  under lean-lsp-mcp pid 92523 (MEASURED). "Saves 3.75 GB now" no longer applies: what remains is the recurrence.
- The F3 speed argument says "above load 8 the machine is CPU-bound". docs/team/parallel-plan.md:75-78 measured the
  opposite (load1 412 at 64 % idle; on macOS load1 is not a CPU-demand gauge). The load-band timings therefore show
  nothing about contention.
- N1 says "Lean: none". Wrong: `Fw.Ops.Wait.isFw` matches only `fw`, `*/fw`, `fw.mjs` and `*/fw.mjs`
  (lean/Fw/Ops/Wait.lean:365), so `node apps/runner/src/fw.ts watch` no longer has the `fwWatch` shape (:374). The wait-guard
  (PreToolUse on every Bash call, .claude/settings.json:31) would judge it as another command.
- P1's console self-exit would stop the main console in one case. `fw console start` run from a worktree spawns
  console-api from that worktree's code (apps/runner/src/console.ts:28,135) but anchors its state at main
  (apps/runner/src/lib.ts:112-114). Removing that worktree would then make the lead's console quit, and console events
  would be lost (CONFIRMED code path).
- F2-drop-serena: the user asked for Serena (memory upstream-source-in-project, 2026-10-17: "setup the serena for help your
  research"), so dropping it is the user's decision. Usage is confirmed: obs.jsonl has 4 serena-lean calls, 1 serena call
  and 279 lean-lsp calls (MEASURED, grep). Serena also covers TypeScript and C++, which lean-lsp does not (docs/team/serena.md).

## Ranked verdicts (largest saving with no speed loss first)
| # | id | verdict | saving | why |
|---|---|---|---|---|
| 1 | F1-lsp-reap + orphans F4 | change | ~450 MB per removed worktree that used lean-lsp, up to 3.6 GB at cap 8 | Cause CONFIRMED (cap 8 at client_utils.py:42,183-185; dead-only close at :171-181; exit-only close at __init__.py:167-168). Changes: (a) trigger at worktree removal (land.ts:939), plus the fw watch tick for Claude Code's own removals. (b) Decide on identity, not on path: select a tree only when its cwd inode matches no live checkout's `lean/` inode, because land slots `.claude/land-wt/<n>` reuse paths (land.ts:359-372). (c) Signal the group only when pgid == pid (transport.py:93). (d) Alert only until the user amends the CLAUDE.md kill rule. Speed is unchanged: a removed tree has no caller. Lean `ops.lspReap` is real filter logic. |
| 2 | F2-drop-serena | change | 481 MB (serena-lean) now; 768 MB more if serena goes too | Remove serena-lean: lean-lsp covers it and follows the caller's worktree. For serena (TS/C++/upstream): ask the user to disable it by default and toggle it on in /mcp, not delete it. Speed: 5 calls in 3 days. Turning it on costs a few seconds of startup (INFERRED). |
| 3 | F3-build-slots | change | GBs of peak RSS and swap when builds overlap (2.5 GB per lean child peak, parallel-plan.md:57) | Cause CONFIRMED (object.cpp:1106-1112; Job/Monad.lean:168-172; Fw.Sched.Admit has no caller). A fixed T=4 slows a solo clean build: half the pool on an idle machine. Changes: the first slot holder keeps T=8 and a waiter that gets slot 1 uses T=4, so threads stay at or below 12 instead of 8N. Add a re-entrancy env guard (check.sh calls fwcore-build.sh). Do not put LEAN_NUM_THREADS in the global settings env, which would also cap fwcore and every Lean tool. Take S, T and the bound from Fw.Sched.Admit (cores, cleanBuild), not from new constants. Confirm with timings.jsonl spans per overlap count, not per load band. |
| 4 | F1-drain-event-driven | change | ~9 % of a core when idle (175 ms per 2 s, MEASURED bench) | Step 1, no latency risk: cache each journal by (size, mtime). That removes 129 of the 175 ms with the 2 s poll kept. Step 2: fs.watch triggers a full stat sweep, not "only files named by the event", because FSEvents coalesces and can drop names. Use a safety tick of 10 s or less, not 60 s, so a dropped event lags 10 s at most. Also watch the projects dir so new session `workflows/` dirs are picked up (workflow.ts / drain.ts:123). Event times come from mtimes (workflow.ts:126-131), so a later read does not change them. Lean: the foldl_append incremental fold and the sweep-after-append lemma are real. |
| 5 | F2-reconciler-event-driven | keep | 2 git spawns, plus 1-2 fwcore ops every 2 s, go to 0 when idle; fwcore ~1.5 % of a core | The pass reads only refs, the board and `done` (reconciler.ts:73-128), so refs/heads plus packed-refs plus store.subscribe cover its inputs. The sync execFileSync is real (git.ts:8,16,31). Keep a safety tick of 10-60 s. Plan sync after a land gets faster. |
| 6 | W2-watch-transcripts-incremental | keep | Removes the cold pass every 30 min (10.7 s CPU, ~400 MB peak) and the warm 23 MB re-reads | Cause CONFIRMED (trCache is in memory only, watch-collect.ts:480-490; ghostMs 24 h at :88). Key the on-disk cache by schema version and fw code hash. Fall back to a full read when size < offset or the inode changed. The Lean fold proof is real once signalsOf/summarizeTranscript are written as folds. |
| 7 | W1-watch-spool-cache | keep | 0.47 s CPU and 1.3 s wall per pass, part of the 300-400 MB peak | The (size, mtime) cache alone needs no proof: it is a memo of a pure function, the same convention as trCache. The mtime prefilter needs the Fw.Obs lemma and the precondition lastAt <= mtime (true when writers stamp Date.now() at append time on one host, INFERRED). Keep the stoppedAt-with-worktree exception (watch-collect.ts:551). |
| 8 | P1-no-orphans (and orphans F2 recipe) | change | 25-270 MB plus fwcore for each orphan console | Keep the e2e-land.sh trap on INT/TERM/HUP, the stdin-EOF opt-in and the recipe change in task-preview.md:14 to `fw console start`, which records under main. Change self-exit to fire only when the console's own FW_CONSOLE_DIR is inside the removed codeRoot (see correction). The land report stays report-only. Lean `selfExit` is small but a real decision. |
| 9 | F1-browser-pipe | keep | ~500 MB and ~30 % CPU for each orphan Chrome | Source CONFIRMED (devtools_pipe_handler.cc:186-191, remote_debugging_server.cc:325-328, headless_devtools.cc:128-131 @f842f52). Three call sites (census.mjs:146, shell-measure.mjs:124, gaps/engines.mjs:36) use neither wsEndpoint nor connect, so pipe:true changes nothing else. Speed is the same. |
| 10 | F4-upstream-lru-cap | keep | Bounds trees at cap x ~450 MB | Upstream patch: LRU on reuse, evict clients whose root is gone, env cap. Speed is better because the main client stops being evicted first. With it, item 1 becomes a backstop. |
| 11 | F6-test-tempdirs | keep | Disk only: 144k dirs, at least 8.5 GB | Not CPU or memory. Deleting the existing dirs needs the user's approval (memory: disk-cleanup). |
| 12 | F5-chrome-devtools-mcp | keep (user option) | ~116 MB per session | `--isolated` drops the persistent profile and its logins, and headless hides the window; both are user preferences. |
| 13 | N1-skip-pnpm-wrapper | change | ~230 CPU-s/day (~0.3 % of a core) and 14-92 MB per long-lived call | Small. Better as a `./fw` shim that isFw already matches (Wait.lean:365), or extend isFw/Identity and their goldens first. Also needs a user settings allow rule and memory text updates. |
| 14 | F3-fw-reap (+ pids.jsonl registry) | change: defer | Unquantified once 1, 8 and 9 land | 9 theorems for an unknown saving. Ship `fw reap --list` as a `reapable` line in fw watch first, and build stop mode only if leftovers recur. The design is sound (pid+start identity, reap_not_live) apart from the main-console-from-worktree case above. |
| 15 | F4-sse-heartbeat | change: defer | 254 KB per 15 s, and only while a tab is open | The board carries `now` (board.json keys: seq, now, ...), and the web reads it for the clock offset (console-web/src/lib/api.ts:22), so a hash that includes it never matches. Excluding it needs proof that no board field depends on now. |
| 16 | F3-preview-deadline-timer | drop | One fwcore op per 30 s | Negligible. The idle end moves on every access, so the timer must be re-armed on each touch, which is more logic for no measurable gain. |
| 17 | F5-max-open-files | drop | 0 MEASURED (1 worker per tree today) | Worst-case only. A third open file forces re-elaboration, seconds to minutes on large Lean files, which is a speed loss. |

## Hooks summary
- Worktree removal (land.ts:939): lspReap list or stop (1), land "live in tree" report (8).
- fw watch tick: lspReap alert (1), reapable line (14); W1/W2 ship with the next Monitor re-arm.
- Post-land console restart: 4, 5 (console-api code).
- User steps: the kill-rule amendment (1), /mcp disable for serena (2), the lean-lsp-mcp pin bump (10),
  ~/.claude.json (12), the settings allow rule (13), approval to delete leftover tmp dirs (11).

## Not in the reports
- Hooks start node for every tool call (PostToolUse emit.mjs, PreToolUse wait-guard and cap). Each costs ~25-30 ms and
  ~42-49 MB peak (MEASURED probe). emit.mjs caches `ps` per session (emit.mjs:45-60). Cheap: no action.
- The user's Zed `lake serve` on main (~680 MB, 7 workers) is outside our scope.

---

## Lean servers and Lean builds: resource audit (2026-10-20)

Read-only. No process was signalled, no local debug run. Paths: `LLM` = `~/.cache/uv/archive-v0/ztfN-5nOXtZi_RlyfqoOO/lib/python3.14/site-packages`
(the env of the live lean-lsp-mcp pid 92523), `SER` = `~/.cache/uv/archive-v0/nxURZhmEE1vzzkCJ9S2pC/lib/python3.14/site-packages`
(serena-agent 2.0.0, pid 92531), `L4` = `.cache/upstream/lean4@eb6cafb` (v4.35.0). Footprints: `top -l1 -stats mem,cmprs` at ~18:20.

## 1. Why lean-lsp-mcp keeps one `lake serve` per worktree forever

- CONFIRMED: one Python process serves the whole Claude Code session (lead + every in-process subagent). A tool call on a
  file walks up to the innermost Lean root and rebinds the session to it (`LLM/lean_lsp_mcp/client_utils.py:402-487`;
  worktrees nested in the repo are their own root, :402-428). Each root gets its own `AsyncLeanLSPClient` = one
  `lake serve` tree (`client_utils.py:126-139`, `LLM/leanclient/aio/client.py:154`).
- CONFIRMED: a client is closed only (a) when the cap is hit: `_MAX_SHARED_CLIENTS = 8`, hard-coded, no env var
  (`client_utils.py:42,183-185`); (b) when its process is already dead (:171-181); (c) at MCP process exit
  (`LLM/lean_lsp_mcp/__init__.py:167-168` -> `close_shared_client`, killpg SIGKILL, `LLM/leanclient/aio/transport.py:93,122-138`).
  The per-session lifespan teardown deliberately does not close it (`LLM/lean_lsp_mcp/server.py:358-364`).
  No idle timeout, no "project dir still exists" check, no close tool.
- CONFIRMED: eviction is FIFO, not LRU: it pops the first-inserted dict key (`client_utils.py:142-147`); reusing a client
  (`:170-171`) does not reorder. MEASURED consequence: the 8 live trees are 8 worktree paths; the main `lean/` client is
  not among them, so the hottest project was evicted first and pays a cold start on its next call.
- MEASURED now: 8 trees, all for removed worktrees (only wf_4b8d04ef-923-1, wf_b2d9cca1-299-1, wf_df082d5f-ac9-3 exist;
  `lsof -d cwd` of each `lake serve`). Footprint: servers 289-309 MB each (2.43 GB), one worker each 102-245 MB (1.23 GB),
  lake 11 MB each: **~3.75 GB**, almost all compressed (cmprs = mem), 0% CPU. Swap used 7.8 of 9.2 GB.
- Knobs that exist: `LEAN_LSP_MAX_OPEN_FILES` (workers per tree, default 4, `LLM/lean_lsp_mcp/config.py:63-73`; open
  files are LRU-closed, `LLM/leanclient/aio/client.py:575-589`), `LEAN_BUILD_CONCURRENCY` allow|cancel|share (per
  project only, `config.py:101-108`). Nothing bounds or ages the number of trees.

## 2. serena-lean and serena

- CONFIRMED: serena-lean starts one `lean --server` for `--project lean` relative to the session cwd (`.mcp.json`),
  i.e. the main checkout only (`SER/solidlsp/language_servers/lean4_language_server.py:43-44`); it lives for the session,
  restarted only if dead (`SER/serena/ls_manager.py:167-169`). INFERRED: a worktree agent asking serena-lean sees main's
  files, not its own tree.
- MEASURED: serena-lean chain = uvx 50 + Python 111 + lean 320 MB = **481 MB**; serena (`.`) = uvx 61 + Python 268 +
  ts-ls 29 + tsserver 109 + 301 MB = **768 MB**.
- MEASURED usage (`.fw-console/obs.jsonl`, PostToolUse events, 3.0 days, 77,112 tool calls): lean-lsp 279,
  serena-lean 4, serena 1. ~1.25 GB held for 5 calls.

## 3. Lean builds

- Who builds: `scripts/fwcore-build.sh:38` (`lake build` in the caller's checkout); `lean/scripts/check.sh` runs it
  serially, then parallel stages call built binaries without Lake's lock (check.sh header); `fw land` phase 1
  (`apps/runner/src/land.ts:598`), lint `cd lean && lake build && axiom-check` (`apps/runner/src/land-verdict.ts:70`),
  queue rebuild in main (`apps/runner/src/fw.ts:136`), in land slots `.claude/land-wt/<n>`, one per concurrent land
  (`land.ts:359-372`); agents call `lake build` directly (`.claude/agents/lean-prover.md:12`); lean-lsp `lean_build`;
  and every LSP worker builds stale imports itself (INFERRED: `lake setup-file`). No machine-wide limit exists.
- CONFIRMED: Lake has no `-j`; jobs are `BaseIO.asTask` at default priority (`L4/src/lake/Lake/Build/Job/Monad.lean:168-172`)
  and block in `IO.Process.output` (`L4/src/lake/Lake/Util/Proc.lean:34`), so one `lake build` runs up to pool-size `lean`
  children; pool = `LEAN_NUM_THREADS` else `hardware_concurrency()` = 8 (`L4/src/runtime/object.cpp:1106-1112,1121`).
  Each child inherits the env var and has its own `-j/--threads` (`L4/src/util/shell.cpp:182,353`).
- CONFIRMED gap: `docs/team/parallel-plan.md:80` says `LEAN_NUM_THREADS=2` is "exported by default in every agent
  environment", but `.claude/settings.json:3-11` env has no such key and `git grep LEAN_NUM_THREADS` finds no code.
  `Fw.Sched.Admit` (cleanBuild token, proved `within_budget`, `lean/Fw/Sched/Admit.lean:1-18,30-51`) is not called by
  any app code (git grep). So N concurrent builds can run 8N `lean` processes on 8 cores.
- MEASURED (`.fw-console/timings.jsonl`, host=local): `lean/check` "lake build" n=820, median 0.9 s (mostly no-op),
  p90 22 s, max 245 s; land phase 1 n=60, median 4.9 s; land lint n=15, median 11 s. Real builds (>5 s) by 1-min
  load at start: load<8 median 12.4 s (p90 22), 8-16 13.2 (37), 16-40 15.0 (49), >=40 21.7 s (p90 79). Confounded by
  work size; INFERRED that contention explains much of the 1.75x median / 3.6x p90 gap. Spanned builds overlap at most 2
  (44 events); agent and LSP builds are not spanned, so true concurrency is higher (load hit 185 earlier).
- Sharing: CONFIRMED already shared through Lake's artifact cache with hard-link restore (`lean/lakefile.toml`
  `enableArtifactCache`, `restoreAllArtifacts`) and `scripts/wt-prep.sh:2-3` (APFS clone of main's `.lake`). MEASURED:
  6 `.lake` trees are 5.7 GB summed separately, 4.1 GB counted once. No further sharing is needed for build time.
  INFERRED, unmeasured: APFS clones are separate inodes, so mmapped `.olean` pages of main and a cloned worktree are
  not shared in the page cache, while Lake's hard-link restores are.

## Fixes (ranked by memory freed per effort)

F1 Reap lean-lsp trees of removed worktrees. Saves ~3.75 GB now (and ~450 MB per finished worktree that used lean-lsp);
  CPU 0 (they idle). Speed: better (less swap); no live tree is touched.
  - Now, no rule change: user runs `/mcp` -> lean-lsp -> Reconnect. The stdio close runs `close_shared_client`
    (`__init__.py:167-168`, CONFIRMED in source; that reconnect closes stdin is INFERRED). Cost: one cold `lake serve`
    start on the next lean-lsp call (seconds, INFERRED; main was evicted anyway).
  - Durable: `fw watch` tick (already runs every 300 s) lists `lake serve` processes whose parent is the lean-lsp-mcp
    Python and whose cwd is not a live checkout (`git worktree list`, path missing on disk). Lean first: op
    `ops.lspReap` (facts: pid, ppid, start, exe, args, cwd; checkouts) -> pids, proving: selected => exe is lake, args
    `serve`, parent = the MCP pid, cwd under no live checkout; a live checkout's server is never selected; goldens like
    `golden/ops/lakegc.jsonl`. Glue reuses `gatherProcs` of `apps/runner/src/lake-gc.ts:118-144` (+ ppid). Killing
    (killpg of that pgid, identity = pid+start) conflicts with CLAUDE.md "kill only PIDs your own run started": the user
    must amend that rule; until then the op only raises an alert and the lead relays the `/mcp` step.
F2 Remove serena and serena-lean from `.mcp.json` (+ their entries in `.claude/settings.json:70-78` and agent tool
  lists). Saves ~1.25 GB held for the session. Speed: same (5 calls in 3 days); lean-lsp covers search, references,
  outline and follows the caller's worktree. Lean first: none (config, no decision). Hook: lead edits tracked files;
  user restarts the session.
F3 Machine-wide Lean build slots + thread cap. Wrapper `scripts/lake-slot.sh`: `LEAN_NUM_THREADS=T lockf -t 0` on slot
  file 0..S-1 (kernel lock, released on exit, no stale pids), else wait on slot 0; fwcore-build.sh:38, land.ts lint
  argv and lean-prover.md call it. Proposed S=2, T=4 (S*T = 8 cores). Saves: peak `lean` children from 8N to <= 8,
  each 200-600 MB (2.5 GB on clean builds, parallel-plan.md:57), i.e. GBs of peak and the swap that comes with it.
  Speed: total throughput same or better: the machine is CPU-bound above load 8 (handoffs/land-test-speed.md: load is
  state-R work), so >8 runnable `lean` adds no throughput and adds swap; one build may wait for a slot (no-op builds
  hold it ~0.9 s). Must be measured before/after with the existing spans (median and p90 per load band above).
  Lean first: S, T and `S*T <= cores` as Lean constants with a `decide` proof, generated into the wrapper; the slot
  choice itself is the OS lock (no decision logic). LSP workers' own `setup-file` builds stay outside the gate.
  Hook: wrapper in scripts + `LEAN_NUM_THREADS` in `.claude/settings.json` env (user edits settings).
F4 Upstream lean-lsp-mcp patch (proposal): env cap for `_MAX_SHARED_CLIENTS`, LRU move-to-end on reuse, evict clients
  whose root no longer exists. Bounds trees to the cap; speed better (main client no longer evicted first). Pin bump in
  `.mcp.json` once released. Lean: none of ours (third-party code); the cap/LRU rule could be specified as a model.
F5 Optional: `LEAN_LSP_MAX_OPEN_FILES=2` in the lean-lsp `.mcp.json` env: worst case 4 -> 2 workers per tree (~100-250 MB
  each). Speed: same if agents work on <= 2 files per tree (MEASURED today: 1 worker per tree); else a re-elaboration.

Out of scope, noted: Zed (user's editor, pid 18078) runs its own `lake serve` on main with 7 workers (~680 MB).

---

## Resource audit: our Node processes (console-api, fw watch, previews, pnpm)

Read-only. Measured 2026-10-20 18:20-18:35 with `ps`. One local debug run (bench.mjs here, under 1 min) is not a CI result.

## Measured now
| process | RSS | CPU |
|---|---|---|
| console-api (main, pid 14847) | 205-220 MB | 1.75-1.83 s CPU per 20 s, so about 9 % of a core when idle (MEASURED) |
| its fwcore child | 24-26 MB | 2:15 over 2:28 h, about 1.5 % (MEASURED) |
| `fw watch --stream` (fresh) | 410 MB at 48 s, 52 MB idle, 309 MB again at the 2nd pass | 1st pass 10.7 s CPU, 2nd pass 2.2 s (MEASURED) |
| pnpm wrapper per fw call | 147 MB peak, then 14-92 MB resident while the child runs | 0.23-0.25 s CPU per call (MEASURED, `pnpm -s run __nope__`) |
| `watch pass` spans, 24 h | p50 10.5 s, max 198 s, 283 passes | timings.jsonl (MEASURED) |
| fw calls, 24 h | 1205 spans: ci wait 440, watch pass 283, land 156 | timings.jsonl (MEASURED) |
The orphan console-api of wf_8e08bb9a-7b4-1 (pid 6392) and the orphan Chrome were gone by 18:25. Someone else ended them.

## (1) console-api idle CPU: what runs on timers
| timer | file:line | work per tick | measured cost |
|---|---|---|---|
| spool drain, every 2 s | main.ts:92 -> drain.ts:151-157 | workflowSweep: `scanWorkflows` reads every journal.jsonl of every workflow run (321 runs, 7.4 MB) and stats them (workflow.ts:137-148). spoolSweep: readdir + stat of 7741 spool files (drain.ts:170-174) and one `store.board()` | scanWorkflows 129 ms CPU, stat loop 46 ms CPU per run. 175 ms per 2 s is about 8.75 %, which is almost all of the idle CPU (MEASURED, bench) |
| reconciler, every 2 s | reconciler.ts:132-134 | `git for-each-ref` (247 refs), up to 3 `store.board()` calls (254 KB JSON from fwcore, 1 s share cache: store.ts:111-119), `git log -n300` with full bodies (86 KB) and `plan.trailers` in fwcore (git.ts:48-68), merge-base per open card (git.ts:26). Uses sync execFileSync, so it blocks the event loop | 2 git spawns + 1-2 fwcore queries per 2 s (CONFIRMED by code). 0 card/* branches now |
| preview sweep, every 30 s | main.ts:65 -> manager.ts:260 | one fwcore `console.previewSweep`, even with an empty table (table.json is `[]` now) | small (INFERRED) |
| SSE board, every 15 s per client | app.ts:109-111 | a full 254 KB board per client, also when nothing changed | only while a console tab is open (CONFIRMED by code) |

Memory (INFERRED): the drain loads all of obs.jsonl (40 MB, 138k lines, zod-parsed) at start into `seen` (drain.ts:128-139).
`/api/obs/summary` parses the whole file again on each call (drain.ts:141). The 2 s re-parse of 7.4 MB adds heap churn.

## (2) Why `fw watch` reaches 300-400 MB
- Every pass reads and parses every spool file, 7741 files and 31.5 MB, before any filter (watch-collect.ts:534-538).
  That costs 474 ms CPU and 1.3 s wall per pass (MEASURED, bench). Only 12 files changed in the last hour.
- The ghost window is 24 h (watch-collect.ts:88). 399 transcripts (1.07 GB, up to 23 MB each) were written in the
  last 24 h. A cold pass reads all of them whole (watch-collect.ts:488). `trCache` is in memory only (watch-collect.ts:480),
  so every re-armed stream (the Monitor re-arms every 30 min) pays a cold pass: about 10.7 s CPU and about 400 MB peak (MEASURED).
- A warm pass still re-reads each changed transcript whole (up to 23 MB) and the whole timings.jsonl (11 MB, 37 ms;
  watch-collect.ts:917).
- It is a peak, not a leak: RSS falls to 44-52 MB between passes (MEASURED).

## (3) Lifetime of previews and worktree processes
- Previews: serve-children are detached process groups (manager.ts:64, :90-91). They are stopped by the 60 min
  deadline or 15 min idle sweep (manager.ts:259-268; Lean `Fw.Console.Preview.tick`, Preview.lean:506), by
  console-api SIGTERM/SIGINT (main.ts:131-141 -> manager.ts:293), and at the next console start (`reapRecorded`,
  manager.ts:277). A SIGKILLed console leaves its children running until the next start (CONFIRMED by code).
- Worktree removal: `fw land` cleanup (land.ts:924-946) checks only lock, dirty tree and cwd. It never checks for live
  processes whose code is in that worktree (CONFIRMED). Claude Code's own worktree removal does not check either (INFERRED).
- Probable source of the orphan console-api: apps/runner/test/e2e-land.sh:13 runs `node $HERE/apps/console-api/src/main.ts &`,
  which is exactly the orphan's argv, with `trap ... EXIT` only (:9). When the shell dies by SIGKILL or a tool timeout,
  the trap does not run, and node plus its fwcore are reparented to pid 1 (INFERRED).
- Probable source of the orphan Chrome: puppeteer without `pipe: true` (apps/site/scripts/census.mjs:146). Chrome then
  outlives a killed Node parent. Playwright launches (gate-breakpoints/src/engines.mjs:96, visual-diff/src/engines.mjs:27)
  use a pipe by default (INFERRED; check puppeteer LaunchOptions.pipe docs and Chromium devtools_pipe_handler.cc).

## (4) pnpm wrapper
- `"fw": "node apps/runner/src/fw.ts"` (package.json:14). pnpm adds 0.23 s wall, 0.25 s CPU and 147 MB peak per call,
  and 14-92 MB resident while the child runs (MEASURED). That is about 920 non-watch calls per day, roughly 230 CPU-s/day.
- The capability hook already mints nothing for `pnpm -s fw` (Lean golden Fw/Ops/Golden.lean:146 "notFwPrefix";
  cap.mjs:96). So `watch`, `ci wait` and `run` started as `pnpm -s fw` get no identity from pnpm today. They do not
  read `npm_*`/INIT_CWD and spawn only git/env (CONFIRMED by grep). Run from the repo root, they behave the same under bare node.

## Fixes (each: saving, speed, Lean first, hook)
F1. Event-driven, incremental drain (largest CPU win)
- Drain on `fs.watch(spool)` and `fs.watch(<session>/workflows|subagents/workflows, {recursive:true})`, coalesced
  through coalesce.ts / Lean `Fw.Console.ReconcileSched`, plus a 60 s safety drain for missed FSEvents.
- Cache each journal by (size, mtime) and skip runs that are finished and fully sent. Read only files named by the
  event, and do a full stat sweep only on the safety tick.
- Saving: about 8-9 % of a core down to under 1 % when idle. Less heap churn, maybe 50-100 MB RSS (INFERRED).
- Speed: better: FSEvents latency 0.05 s (libuv v1.51.0 src/unix/fsevents.c:340, node 24.14 = uv 1.51.0) vs up to 2 s.
- Lean first: in ReconcileSched-style, prove every append is drained by a pass that starts after it, and that a missed
  event is drained within one safety period. Model the journal as append-only and prove the incremental fold equals the
  full fold (List.foldl_append). Golden vectors for the TS cache.
- Hook: console-api code. The post-land routine restarts the console.

F2. Event-driven reconciler
- Run a pass on `fs.watch(<common-dir>/refs/heads, recursive)` and on packed-refs (git-scm.com/docs/gitrepository-layout),
  on `store.subscribe` (a newly opened card needs a pass), and on a 60 s safety tick.
- Memoize `trailerFacts` by (main sha, undone ids). It is a pure function of those, so a hit skips git log and plan.trailers.
- Saving: 2 git spawns and 1-2 fwcore queries per 2 s down to 0 when idle; no event-loop blocking. Speed: better (ref write wakes it in ~50 ms).
- Lean first: the trigger set is complete, meaning every input of `pass` (refs, board seq, main sha) is covered by a
  wake source. Prove the memo is sound from `plan.trailers` being a function. Hook: console-api, post-land restart.

F3. Preview timer from deadlines
- Arm `setTimeout` at Lean `nextWake(table)`, the minimum of the deadline and idle end. Do not arm it while the table is empty.
- Saving: 2880 fwcore ops/day. Speed: better, because previews stop at the deadline and not up to 30 s late.
- Lean first: `nextWake` with ∀ now < nextWake, `expired s now = []` (Preview.lean:509), and the idle analogue. Hook: console-api.

F4. SSE heartbeat
- Send `:hb` instead of the full board when seq and board hash are unchanged (app.ts:109-111).
- Saving: 254 KB per 15 s per tab. Speed: same. Lean first: none (equality of fwcore output). Hook: console-api.

W1. Spool cache in fw watch
- Stat before reading. Skip an id whose spool mtime and transcript mtime are older than ghostMs and that has no worktree.
  Cache summaries by (size, mtime) as trCache does.
- Saving: about 31 MB of parse per pass down to the changed files, with peak RSS likely 300-400 down to about 100 MB
  (INFERRED). Per pass: -0.47 s CPU and -1.3 s wall (MEASURED parts).
- Lean first: in `Fw.Obs`, prove that with lastAt ≤ mtime the stat prefilter drops only agents the current filter drops
  (watch-collect.ts:551). Hook: the `fw watch` code. The next Monitor re-arm picks it up.

W2. Incremental transcripts with an on-disk cache
- Restate `summarizeTranscript`/`signalsOf` as fold state plus step and read only appended bytes. Persist {path, size, mtime, offset, state} to .fw-console/watch-cache.json so a re-armed stream starts warm.
- Saving: the cold pass every 30 min, about 10.7 s CPU and about 400 MB peak, drops to warm-pass cost. Speed: better (pass p50 is 10.5 s now).
- Lean first: the summary as a List.foldl and incremental = full (foldl_append). The TS step is checked against Lean
  golden vectors. Hook: `fw watch`.

P1. No orphans
- In e2e-land.sh, trap `EXIT INT TERM HUP`.
- console-api gets an opt-in `FW_EXIT_ON_STDIN_EOF=1`: tests give it a pipe, and it exits when the parent dies, even by SIGKILL.
  console-api also exits by itself when its codeRoot's main.ts disappears (worktree removed). It only stops itself; it
  never kills another process.
- census.mjs gets `puppeteer.launch({pipe:true})`.
- `fw land` cleanup lists processes whose argv path is under wt.dir (ps -axo pid,lstart,command) and reports them.
  It never kills them, per CLAUDE.md.
- Saving: each orphan console-api 25-250 MB plus fwcore; the orphan Chrome was ~500 MB and 30 % CPU. Speed: unchanged.
- Lean first: `console.selfExit(codeRootExists, stdinEof, optIn)` and the land "live in worktree" report decision.
  Hook: worktree removal (land.ts:924), the test harness, console-api.

N1. Skip pnpm for long-lived commands that need no identity
- Monitor and wait commands become `node apps/runner/src/fw.ts watch|ci wait|run ...` from the repo root.
- Saving: 0.25 s CPU, 147 MB peak and 14-92 MB resident per call. Speed: 0.23 s faster start.
- Lean first: if `./fw` or bare node should also mint capabilities, extend the `Fw.Ops.Identity` prefix rule and its
  goldens (Golden.lean:145-147) first. Otherwise none.
- Hook: a settings change the user must make, an allow rule `Bash(node apps/runner/src/fw.ts watch:*)` (and `ci wait`,
  `run`), plus the memory/skill text that names `pnpm -s fw watch`.

---

## Orphan processes: sources, record design, `fw reap` (audit 2026-10-20 18:14-18:40)

Read-only. No process signalled, no tracked file edited, no local debug run. Upstream sources fetched into
`scratchpad/resource-audit/up/` (Chromium @f842f52, the pin in refs/upstream/sources.lock.yaml:6-10).

## 1. Who started each orphan

| Orphan | Started by | Why it outlived its driver |
|---|---|---|
| Headless Chrome, `puppeteer_dev_chrome_profile-DRbNR3`, ppid 1, pgid = own pid 77003, born 2026-10-17 17:22 | The breakpoint gate as committed in 9e999e6b (17:18): `packages/gate-breakpoints/src/engines.mjs` used `puppeteer.launch` with no `userDataDir` and exactly the flags seen on the orphan (`MAP * ~NOTFOUND, EXCLUDE 127.0.0.1`, `--blink-settings=...primaryPointerType=2`, `--font-render-hinting=none`, `--force-color-profile=srgb`). INFERRED (flags and time match; no run log) | Puppeteer spawns Chrome `detached` (own process group) over a WebSocket port (`--remote-debugging-port=0` on the orphan): @puppeteer/browsers 3.2.5 src/launch.ts:326-333, puppeteer-core 25.14.0 src/node/LaunchOptions.ts:105-111 (`pipe` default false). Its exit handlers cannot run on SIGKILL, so a killed driver leaves Chrome running. CONFIRMED (source) |
| Same pattern, still possible today | Puppeteer without `pipe`: apps/site/scripts/census.mjs:146, apps/site/scripts/shell-measure.mjs:124, packages/gate-breakpoints/src/gaps/engines.mjs:36. Playwright: gate engines.mjs:96, visual-diff engines.mjs:27, premise-tests run.mjs:29, e2e-preview run.mjs:34, console-api scripts/preview-bench.mjs:59 | Playwright already launches with `--remote-debugging-pipe` / `--inspector-pipe` (playwright-core 1.64.1 lib/coreBundle.js, chromium `_innerDefaultArgs` and webkit args). CONFIRMED (source) |
| console-api + fwcore from removed worktree wf_8e08bb9a-7b4-1 | The recipe in docs/team/handoffs/task-preview.md:14 (`FW_CONSOLE_DIR=$PWD/.fw-console PORT=<free> node apps/console-api/src/main.ts`). INFERRED (process already gone at 18:25, could not read its env) | The pid record (`api.json`) lived in the worktree's `.fw-console`, so `git worktree remove` (apps/runner/src/land.ts:939) deleted the only record. `fw console` itself records under the main checkout (apps/runner/src/lib.ts:112-114) and stops only the verified pid (lean/Fw/Console/Daemon.lean:49,106). CONFIRMED (code) |
| 8 `lake serve -- -Dserver.reportDelayMs=0` trees under lean-lsp-mcp | lean-lsp-mcp 0.31.0: an agent's tool call on a worktree file switches project (allowed on stdio, client_utils.py:74-80, 87-112) and starts one `lake serve` per project root with cwd = that root (leanclient 0.13.2 base_client.py:65-67). Clients are kept until an LRU eviction at `_MAX_SHARED_CLIENTS = 8` (client_utils.py:42, 181-185), hard-coded, no env knob. CONFIRMED (source) | Nothing closes a client when its worktree is removed; the cap of 8 explains the 8 trees (~3.5 GB). `lake serve` runs in the Claude session's process group (pgid 92347 = the session), so a group signal would hit the whole session. MEASURED (ps) |
| chrome-devtools-mcp Chrome (headed, `~/.cache/chrome-devtools-mcp/chrome-profile`) | User-level `~/.claude.json`: `npx chrome-devtools-mcp@latest`, no args | Not an orphan: child of its MCP server (ppid 92485). One MCP server per Claude session (two now, 1 d and 7 h old). Chrome tree 6 procs, 116 MB RSS, 0 % CPU. MEASURED |

State at 18:25: the 8 lake trees, the orphan console-api and the orphan Chrome were already gone (stopped by someone
else); the Chrome profile dir is left (8 MB). The remaining `lake serve` (pid 18816) belongs to the user's Zed editor.

## 2. Temp dir (`$TMPDIR` = <tmpdir> `find -maxdepth 1` under a 60 s alarm, no deletion)

| Prefix | Count | Size |
|---|---|---|
| puppeteer_dev_chrome_profile- | 1 | 8 MB |
| playwright_chromiumdev_profile- / playwright_webkitdev_profile- / playwright-artifacts- | 8 / 1 / 9 | ~0 MB |
| fw-gaps-chrome- / chrome-devtools-mcp- | 0 / 1 | 0 / 2 MB |
| fw-* (test temp dirs) | 144,487 | ≥ 8.5 GB (du stopped at 150 s after 75,746 entries) |

Browser profiles are small (MEASURED). The real leak is our tests: `mkdtempSync` without removal, e.g.
apps/console-api/test/serve.test.ts:82 (`fw-serve-`, 11 MB each, 409 dirs), apps/console-api/test/reconcile-fixture.ts:19
(`fw-land-`, 47,257 dirs), apps/runner/test/hooks.test.ts:15 (`fw-hooks-`, 22,130), run-budget.test.ts:18, spawn-guard.test.ts:32.
Disk only, no CPU or memory cost. Fix: one `tmpdir()` helper per test file that removes its dir in `afterEach`.

## 3. Fixes

**F1 Browsers die with their driver (pipe transport).** Pass `pipe: true` to the three `puppeteer.launch` calls. With
`--remote-debugging-pipe`, Chrome reads the pipe; EOF posts `OnDisconnect` (content/browser/devtools/devtools_pipe_handler.cc:186-191@f842f52),
bound to `ChromeDevToolsManagerDelegate::CloseBrowserSoon` (chrome/browser/devtools/remote_debugging_server.cc:325-328@f842f52;
headless: headless/lib/browser/headless_devtools.cc:130-131). The kernel closes the driver's pipe end on any death, SIGKILL
too. CONFIRMED (source). Saving: the observed orphan, ~500 MB and ~30 % CPU for days. Speed: same or better; pipe skips
the TCP socket and the port discovery on stderr; Playwright already uses it in every lane. INFERRED. Lean: none (no
decision, a launch option). A premise test in premise-tests could check "driver SIGKILL -> browser gone within 5 s" on CI.

**F2 Records outside the worktree.** Every detached spawn of ours (console-api, preview servers already in
`preview/table.json` with `pstart`, browsers, `fw` daemons) appends `{pid, start, leader, run, tree, kind}` to
`<git-common-dir>/../.fw-runs/<run-id>/pids.jsonl`, the same anchor `consoleDirOf` uses (lib.ts:112-114), so removing a
worktree cannot delete the record. `start` is `ps -o lstart=` as in apps/runner/src/console.ts:79-81; `leader` is true
only when we spawned with `detached: true` (pgid = pid). Change task-preview.md:14 to `pnpm fw console start --port <free>`
with `FW_CONSOLE_DIR` under `.fw-runs/`. Saving: the orphan console-api (~270 MB, ~6.7 % CPU idle if like main's). Speed:
one append per spawn, < 1 ms. Lean: the record schema is wire, fine to golden-check.

**F3 `fw reap` (decision in Lean, glue signals).** Spec below. Hooks: `fw reap --list` (prints `pid reason tree`, like
`fw lake-gc --list`); `fw reap --stop` sends SIGTERM to the selected pids (to `-pgid` only for `leader` records), waits
30 s, reports survivors, never SIGKILL (as console.ts:174-177); land.ts:939 calls it for the removed tree; the post-land
routine and `fw watch` show "reapable: N procs, X MB". Saving: everything F1/F2 miss. Speed: one `ps` + one
`git worktree list` (~50 ms), off the land critical path if run after the merge. INFERRED.

**F4 lean-lsp-mcp trees of removed worktrees (needs a lead/user decision).** These pids are started by lean-lsp-mcp,
not by our runs, so CLAUDE.md forbids us to stop them. Options: (a) user reconnects `lean-lsp` with `/mcp` after a wave
of worktree removals (closes all its clients; the next call restarts the main project, ~seconds of warm-up); (b) at
`git worktree remove`, land.ts records the pids whose cwd is inside the tree being removed as `kind = resident` and
`fw reap` stops them by pid, never by group (pgid is the session's). (b) widens "PIDs your run started" to "PIDs living
in a tree your run removes": the user must accept it. Saving: up to 8 x ~450 MB = ~3.5 GB (MEASURED in the brief). Speed:
same; a removed worktree's LSP has no further caller.

**F5 chrome-devtools-mcp (user edits `~/.claude.json`).** Pin the version and add `--headless --isolated` as in
research/notes/2026/10-18-chrome-agent-tools-install.md:44-49. Saving: the headed window and the persistent profile
(~116 MB tree now; temp profile removed on close). Speed: pinned `npx` skips the `@latest` registry lookup at session start.
INFERRED. Lean: none.

## 4. `Fw.Ops.Reap` (specify and prove before coding; reuse `Fw.Ops.LakeGc.Proc`, lean/Fw/Ops/LakeGc.lean:30-36)

```
structure Proc where pid ppid pgid start : Nat; cwd : Option String
structure Rec  where pid start : Nat; leader : Bool; run tree : String; kind : Kind   -- kind: browser|server|daemon|resident
structure Input where procs : List Proc; live : List String; recs : List Rec; self : Nat
inductive Reason | treeRemoved | driverGone          -- driverGone is reported, never selected inside a live tree
def under (c : Option String) (w : String) : Bool := c == some w || (c.map (·.startsWith (w ++ "/"))).getD false
def owned (i : Input) (p : Proc) : Option Rec := i.recs.find? (fun r => r.pid == p.pid && r.start == p.start)
def reap (i : Input) : List (Nat × Bool × Reason)   -- (pid, signal the group?, reason)
  := i.procs.filterMap fun p => match owned i p with
     | none => none
     | some r => if p.pid ≤ 1 || p.pid == i.self || i.live.contains r.tree || i.live.any (under p.cwd) then none
                 else some (p.pid, r.leader && p.pgid == p.pid, .treeRemoved)
```
Theorems (unit of decision: one process-table row):
1. `reap_recorded`: (pid,_,_) ∈ reap i -> ∃ p ∈ i.procs, ∃ r ∈ i.recs, p.pid = pid ∧ r.pid = pid ∧ r.start = p.start.
2. `reap_not_live`: (pid,_,_) ∈ reap i -> ∀ p ∈ i.procs, p.pid = pid -> ∀ w ∈ i.live, ¬ under p.cwd w ∧ (owned i p).tree ≠ w.
3. `reap_pid_reuse`: a row whose start differs from every record with its pid is never selected (from 1).
4. `reap_not_self_init`: selected pid > 1 and ≠ i.self.
5. `reap_group_leader`: (pid,true,_) ∈ reap i -> the row has pgid = pid and its record says leader (never the session group).
6. `reap_antitone_live` / `reap_antitone_recs`: adding a live tree or dropping a record never adds a selection.
7. `reap_nodup` when `procs` has unique pids; `reap_empty_recs`: no records -> [].
Golden vectors: the 2026-10-20 table (orphan Chrome with and without a record, lake trees, a pid reused with a new start).
Accepted limits: paths are realpath'd by the glue; an orphan in a live tree (main included) is listed as driverGone but
waits for F1 or for its tree's removal; processes started by tools we do not wrap (lean-lsp-mcp, Serena) need F4.
