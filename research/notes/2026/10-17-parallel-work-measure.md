# Parallel work measure, 2026-10-17

Status: MEASURED (all numbers from transcripts, git log and load samples; scripts in the session scratchpad, not committed).
Data: 107 sub-agent transcripts, the lead transcript, `docs/team/tools/agent-profile.py` profile, git log (75 commits), machine load samples (09:48-09:55Z only). Machine: 8 cores (6P+2E), 16 GB. Times are UTC. Analysis window for the build: 06:11-09:50Z (219 min); 21:39-06:11 is the user away (excluded).

## Answer

- Peak 12 sub-agents busy at once (08:09Z); mean busy 4.9 over the build window, 10.9 in the busiest 5 minutes.
- Speedup S = 4.9 agent-seconds per wall second over the window; 6.8-7.5 in 08:00-09:50, 2.4-3.6 before.
- Contention: about x1.20 per added concurrent heavy command (CI 1.07-1.35), weak fit.
- The lead answers fast (pickup median 5 s) but is busy 46% of the window.
- Wall time was set by the measurement lanes, which are shell-bound.

## 1. Concurrency timeline

Definitions (MEASURED from transcripts). *alive* = between an agent's first and last transcript line. *model* = open API request (incl. unanswered ones). *tool* = tool call open and no model request open. *idle* = alive but neither. *polling* = tool calls that are sleep or wait loops (a subset of tool). Sub-agents only; the lead is listed separately. 5-minute bins; values are mean agents in that state.

| phase | span (UTC) | mean alive | mean in model turn | mean in tool call (of which polling) | mean idle/waiting | mean busy | peak alive (1 s) | peak busy (1 s) |
|---|---|---|---|---|---|---|---|---|
| P1 research workflows | 19:04-21:39 | 2.56 | 2.09 | 0.19 (0.03) | 0.28 | 2.28 | 6 at 19:08 | 6 at 19:08 |
| P2 user away (overnight) | 21:39-06:11 | 0.02 | 0.01 | 0.01 (0.00) | 0.00 | 0.02 | 1 at 21:39 | 1 at 21:39 |
| P3 build window | 06:11-09:50 | 5.26 | 3.05 | 1.95 (0.50) | 0.26 | 5.00 | 13 at 08:09 | 12 at 08:09 |

Whole session peak: 13 agents alive and 12 busy at once (both at 08:09Z). 107 sub-agent transcripts, of which 41 are named lead-spawned agents and the rest workflow agents.

Per 5 minutes, build window (UTC). Lead: m = in model turn, t = in tool call, - = idle (fraction of the 5 min).

| 5-min start | alive | model | tool | idle | busy | lead m / t / idle |
|---|---|---|---|---|---|---|
| 06:10 | 1.7 | 1.0 | 0.7 | 0.0 | 1.7 | 0.46 / 0.02 / 0.52 |
| 06:15 | 3.8 | 2.6 | 1.2 | 0.0 | 3.8 | 0.70 / 0.01 / 0.29 |
| 06:20 | 2.7 | 1.9 | 0.9 | 0.0 | 2.7 | 0.26 / 0.00 / 0.74 |
| 06:25 | 4.7 | 3.4 | 1.3 | 0.0 | 4.7 | 0.37 / 0.14 / 0.49 |
| 06:30 | 6.0 | 4.8 | 1.2 | 0.0 | 6.0 | 0.61 / 0.01 / 0.37 |
| 06:35 | 4.7 | 3.9 | 0.7 | 0.0 | 4.6 | 0.10 / 0.01 / 0.89 |
| 06:40 | 3.6 | 2.7 | 0.8 | 0.0 | 3.5 | 0.08 / 0.00 / 0.92 |
| 06:45 | 3.9 | 2.2 | 1.7 | 0.0 | 3.9 | 0.12 / 0.00 / 0.88 |
| 06:50 | 2.1 | 1.0 | 1.1 | 0.0 | 2.1 | 0.12 / 0.00 / 0.88 |
| 06:55 | 1.4 | 1.0 | 0.4 | 0.0 | 1.4 | 0.03 / 0.00 / 0.97 |
| 07:00 | 1.0 | 1.0 | 0.0 | 0.0 | 1.0 | 0.00 / 0.00 / 1.00 |
| 07:05 | 1.0 | 0.9 | 0.1 | 0.0 | 1.0 | 0.00 / 0.00 / 1.00 |
| 07:10 | 1.0 | 1.0 | 0.0 | 0.0 | 1.0 | 0.00 / 0.00 / 1.00 |
| 07:15 | 0.2 | 0.2 | 0.0 | 0.0 | 0.2 | 0.09 / 0.00 / 0.90 |
| 07:20 | 0.8 | 0.5 | 0.1 | 0.3 | 0.6 | 0.14 / 0.01 / 0.85 |
| 07:25 | 2.0 | 1.0 | 0.3 | 0.7 | 1.3 | 0.20 / 0.10 / 0.70 |
| 07:30 | 2.0 | 1.7 | 0.1 | 0.3 | 1.7 | 0.07 / 0.00 / 0.92 |
| 07:35 | 1.6 | 1.5 | 0.1 | 0.0 | 1.6 | 0.20 / 0.01 / 0.79 |
| 07:40 | 3.7 | 3.4 | 0.2 | 0.1 | 3.6 | 0.72 / 0.01 / 0.27 |
| 07:45 | 3.9 | 2.9 | 0.1 | 1.0 | 2.9 | 0.34 / 0.02 / 0.65 |
| 07:50 | 6.8 | 4.3 | 2.2 | 0.4 | 6.4 | 0.34 / 0.04 / 0.62 |
| 07:55 | 8.0 | 5.3 | 1.6 | 1.2 | 6.8 | 0.28 / 0.02 / 0.70 |
| 08:00 | 8.1 | 4.8 | 2.2 | 1.1 | 7.0 | 0.66 / 0.11 / 0.24 |
| 08:05 | 9.5 | 4.6 | 2.5 | 2.5 | 7.0 | 0.65 / 0.23 / 0.12 |
| 08:10 | 12.0 | 7.6 | 3.2 | 1.1 | 10.9 | 0.37 / 0.09 / 0.54 |
| 08:15 | 8.1 | 4.3 | 3.6 | 0.2 | 7.9 | 0.26 / 0.21 / 0.54 |
| 08:20 | 7.1 | 3.1 | 3.9 | 0.2 | 7.0 | 0.53 / 0.25 / 0.22 |
| 08:25 | 8.2 | 4.9 | 3.3 | 0.1 | 8.1 | 0.13 / 0.14 / 0.73 |
| 08:30 | 6.9 | 3.2 | 3.6 | 0.1 | 6.8 | 0.47 / 0.47 / 0.06 |
| 08:35 | 5.7 | 2.5 | 2.9 | 0.3 | 5.4 | 0.28 / 0.27 / 0.45 |
| 08:40 | 5.4 | 3.8 | 1.6 | 0.1 | 5.3 | 0.20 / 0.44 / 0.36 |
| 08:45 | 5.2 | 3.0 | 2.1 | 0.0 | 5.2 | 0.18 / 0.11 / 0.71 |
| 08:50 | 4.2 | 2.5 | 1.7 | 0.0 | 4.2 | 0.20 / 0.79 / 0.00 |
| 08:55 | 7.1 | 4.7 | 2.1 | 0.3 | 6.8 | 0.63 / 0.10 / 0.27 |
| 09:00 | 7.4 | 4.1 | 3.2 | 0.1 | 7.3 | 0.72 / 0.05 / 0.23 |
| 09:05 | 7.7 | 3.1 | 4.5 | 0.1 | 7.6 | 0.05 / 0.01 / 0.94 |
| 09:10 | 7.6 | 3.2 | 4.3 | 0.1 | 7.5 | 0.37 / 0.02 / 0.61 |
| 09:15 | 8.5 | 4.5 | 4.0 | 0.0 | 8.5 | 0.42 / 0.51 / 0.07 |
| 09:20 | 5.7 | 3.0 | 2.6 | 0.1 | 5.6 | 0.24 / 0.74 / 0.02 |
| 09:25 | 4.5 | 1.8 | 2.6 | 0.0 | 4.4 | 0.26 / 0.73 / 0.01 |
| 09:30 | 8.5 | 5.1 | 3.3 | 0.1 | 8.4 | 0.58 / 0.06 / 0.36 |
| 09:35 | 9.1 | 3.2 | 5.8 | 0.1 | 9.0 | 0.77 / 0.08 / 0.15 |
| 09:40 | 7.3 | 2.6 | 4.0 | 0.7 | 6.6 | 0.24 / 0.07 / 0.68 |
| 09:45 | 7.5 | 4.8 | 2.7 | 0.1 | 7.4 | 0.80 / 0.08 / 0.11 |

## 2. Parallel speedup and efficiency

Speedup S = sum of sub-agent busy seconds (model or tool, merged per agent) / lead wall seconds in that hour (the lead's AskUserQuestion wait is removed from the wall). S_np excludes polling sleeps. Utilisation U = busy / alive agent-seconds. Core load = mean concurrent tool calls / 8 cores (model time uses no local CPU). Commits = landings on main (git commit time).

| hour (UTC) | lead wall min | lead busy min | agent busy min | S | S_np | U | peak alive (bin) | core load | commits |
|---|---|---|---|---|---|---|---|---|---|
| 19:00 | 56 | 5 | 138 | 2.48 | 2.41 | 1.00 | 6.0 | 0.05 | 0 |
| 20:00 | 60 | 3 | 175 | 2.92 | 2.90 | 0.82 | 5.0 | 0.01 | 0 |
| 21:00 | 40 | 1 | 41 | 1.04 | 1.03 | 0.93 | 1.9 | 0.01 | 0 |
| 06:00 | 48 | 15 | 172 | 3.59 | 3.27 | 1.00 | 6.0 | 0.13 | 7 |
| 07:00 | 58 | 13 | 141 | 2.44 | 2.42 | 0.88 | 8.0 | 0.05 | 10 |
| 08:00 | 60 | 39 | 408 | 6.80 | 6.65 | 0.93 | 12.0 | 0.34 | 40 |
| 09:00 | 50 | 34 | 370 | 7.45 | 5.76 | 0.98 | 9.1 | 0.47 | 18 |

Build window 06:11-09:50 (219 min): S = 4.94, S_np = 4.44, U = 0.95, core load = 0.24. S rises from 2.4-3.6 (06:00-08:00) to 6.8-7.5 (08:00-09:50): the second half ran 6-7 agents' worth of work at once. U is near 1.0 because agents are not kept alive while they wait; idleness shows up as agents not existing, not as idle agents. Efficiency against the ideal of one agent per workstream is therefore measured below (section 5: share of time with at most one agent busy), not by U.

## 3. Contention

Heavy command = Bash call matching lake build/exe/env lean/test, pnpm test/determinism/census/add/build, check.sh, node host.mjs, cli.mjs, vitest, build-math-view, simctl, stress.sh, measure.mjs and similar, foreground only. k = time-weighted mean number of OTHER agents' heavy calls overlapping the call (k_any: any non-polling Bash call of at least 2 s). Calls with errors or under 2 s are dropped. Model: ln(duration) = c(command) + beta * k, one fixed effect per command.

| command | n | median s at k=0 | k=1 | k=2 | k>=3 | beta per +1 heavy | factor |
|---|---|---|---|---|---|---|---|
| lake build | 106 | 6.8 (n=27) | 12.4 (n=22) | 9.6 (n=34) | 14.7 (n=23) | +0.26 | x1.30 |
| lake exe | 20 | 46.1 (n=3) | 6.5 (n=6) | 50.7 (n=5) | 64.0 (n=6) | +0.31 | x1.37 |
| lake env lean | 34 | 5.8 (n=4) | 4.5 (n=10) | 2.5 (n=9) | 6.1 (n=11) | +0.08 | x1.08 |
| pnpm test | 33 | 6.6 (n=1) | 7.2 (n=10) | 8.6 (n=14) | 13.2 (n=8) | +0.08 | x1.08 |
| check.sh | 7 | - | 50.5 (n=4) | 33.8 (n=2) | 68.9 (n=1) | +0.12 | x1.12 |
| node host.mjs | 26 | 60.8 (n=4) | 50.8 (n=10) | 71.7 (n=10) | 91.2 (n=2) | +0.17 | x1.19 |
| pnpm determinism | 9 | - | 247.6 (n=3) | 207.3 (n=5) | 145.0 (n=1) | -0.24 | x0.79 |
| pnpm census | 12 | 29.9 (n=1) | 14.8 (n=4) | 22.6 (n=6) | 22.0 (n=1) | -0.19 | x0.82 |
| node cli.mjs | 7 | - | 50.7 (n=3) | 52.3 (n=4) | - | +0.50 | x1.64 |
| node build-math-view.mjs | 7 | - | 2.3 (n=1) | 179.2 (n=3) | 21.0 (n=3) | +0.12 | x1.13 |
| npx vitest | 7 | - | 2.8 (n=1) | 28.3 (n=3) | 3.7 (n=3) | -0.85 | x0.43 |

Pooled slowdown factor per added concurrent heavy command:

| subset | calls | beta | factor | 95% CI | R2 |
|---|---|---|---|---|---|
| all commands with n>=5, k (heavy only) | 273 | +0.182 | x1.20 | 1.07-1.35 | 0.03 |
| all commands with n>=5, k_any | 273 | +0.150 | x1.16 | 1.06-1.28 | 0.03 |
| Lean only (lake build/exe/env lean, check.sh) | 172 | +0.226 | x1.25 | 1.10-1.43 | 0.06 |
| measure only (host.mjs, determinism, census, cli.mjs) | 54 | +0.081 | x1.08 | 0.81-1.45 | 0.01 |

Headline: about x1.20 per added concurrent heavy command (CI 1.07-1.35), R2 only 0.03. Applied to the observed k, the contention tax is 63 agent-minutes of 247 in these 351 heavy calls (25%). Distribution of k (rounded) over those calls: k=0: 65, k=1: 96, k=2: 117, k=3: 53, k=4: 16, k=5: 4.

Load samples: 46 samples, 09:48-09:57Z only (the sampler started at the end of the window), so only 12 heavy calls overlap a sample and no load1 fit is possible. What the samples show: load1 209-449, idle CPU 0-64%, with 18-205 simulator processes and 3-15 lean, 13-22 node processes. Load1 is high even when only 3-4 lean processes run, so it is dominated by the iOS Simulator runtime, not by agent commands.

Confounders (all present): (1) work size varies, so the same command key spans incremental vs cold builds (lake build 5 s vs 300 s), which is why R2 is 0.03; (2) cache state: a lake build after another agent's warm shared toolchain is faster; (3) the iOS Simulator (about 190 processes) and Docker run in the same hours as the measure lanes and are not counted in k; (4) later agents learn to batch commands, so duration falls over time while concurrency rises; (5) Edit/model time is not counted in k, only shell commands; (6) transcripts log the start of the last tool_use block of a message, not the process start; (7) 351 calls, many in few agents, so errors are clustered. Treat x1.2 as an order of magnitude, not a constant.

## 4. Lead latency

Events are queue-operation enqueue lines in the lead transcript (task-notification of a finished agent/workflow/background command, or a teammate message), user-asleep periods excluded. Pickup = enqueue until the lead's next model request starts. Action = enqueue until the lead's next spawn, SendMessage, TaskStop, workflow start or git commit/merge/rebase.

| event kind | n | queued while lead busy | pickup median s | p90 s | sum s | to action median s | p90 s |
|---|---|---|---|---|---|---|---|
| agent finished | 30 | 21 | 10 | 54 | 622 | 13 | 52 |
| teammate message | 30 | 10 | 1 | 54 | 393 | 13 | 52 |
| workflow finished | 10 | 6 | 2 | 150 | 175 | 71 | 30829 |
| background command done | 31 | 11 | 39 | 153 | 1689 | 77 | 283 |

Disposition of finished named agents: for the 31 of 39 named agents that the lead later touched by id or name (TaskStop, a landing command, a message), the gap from the agent's last transcript line to that first lead action is median 18 s, p75 170 s, p90 350 s, total 49 min (agent-minutes, summed over agents that were no longer running). The other 8 were never referenced after their end (reports taken from the notification text only, or still running at the cutoff).

Gap from a lane's agent ending to its follow-up agent starting (what a workstream waited on the lead to continue):

| predecessor | follow-up | gap |
|---|---|---|
| meas-chromium (08:37) | meas-chromium-2 (08:38) | 0.8 min |
| meas-webkit (08:49) | meas-webkit-2 (08:49) | 0.6 min |
| part-hero (08:17) | part-hero-2 (08:22) | 5.1 min |
| lean-doc-fix-r3 (09:22) | lean-doc-fix-r4 (09:36) | 14.7 min |
| page-rev5 (08:17) | page-mathview-2 (08:23) | 5.8 min |
| lean-parts (08:40) | part-fix (08:43) | 3.0 min |
| lean-core (08:22) | lean-measure (08:38) | 15.9 min |
| mathrev-fwcore (08:32) | lean-null-fix (08:32) | -0.8 min |

The lead is quick per event but busy: 101 of 219 min of the window (46%) in a model turn or tool call, 71 min of it in model turns; 08:00-09:00 was 65% busy. 31 of 60 agent/teammate events arrived while the lead was already working and waited in the queue.

Waiting on the user: 27 human prompts in the window. The lead sat idle before each prompt for a median 50 s (sum 38 min) , during which agents kept running whenever any were alive. Time with zero agents busy and the lead waiting on the user: 6.6 min (of which the 07:16-07:22 pause is 5.8 min). AskUserQuestion blocked the lead 3.6 min inside the window and 515 min overall (512 min of it the overnight wait before 06:11, excluded from every number above). Permission waits recorded by the profiler across all sub-agents: 0.1 min.

## 5. Critical path

Window 06:11-09:50 = 219 min. Time by number of sub-agents busy:

| agents busy | min | share |
|---|---|---|
| 0 | 9 | 4% |
| 1 | 28 | 13% |
| 2-3 | 31 | 14% |
| 4-7 | 105 | 48% |
| 8+ | 45 | 21% |

Serial share (0 or 1 busy): 37 min = 17% of the window.

Landing chain (git log + agent windows, UTC). Agents were launched in waves; the data dependency between waves is the plan and the handoff files, not a name in a prompt, so the chain below is the sequence of long lanes, not a mechanical DAG (an automatic prompt-mention DAG found only one edge and is not used).

| lane | agents | span | wall min | model | tool | polling | what bounded it |
|---|---|---|---|---|---|---|---|
| Chromium counts | meas-chromium -> meas-chromium-2 | 07:51-09:49 | 118 | 34 | 83 | 35 | host.mjs 50 s p50, 4 loops of ~200 s, sleep waits |
| WebKit counts | meas-webkit -> meas-webkit-2 | 07:51-09:42 | 111 | 29 | 81 | 34 | pnpm determinism 235 s x9, simctl, sleep waits |
| Lean core to site | lean-core -> lean-site -> site-breakpoints | 07:50-08:58 | 68 | 51 | 32 | 0 | model turns (24+25 min), then breakgen byte check |
| Lean docs | lean-null-fix -> lean-doc-fix-r3 -> lean-doc-fix-r4 | 08:32-09:50 | 79 | 30 | 16 | 0 | serial docstring batches, lake build/check.sh |
| Plan and page | plan-rev5 -> page-rev5 -> page-mathview-2 | 07:22-08:33 | 71 | 53 | 11 | 1 | model turns, math-view build |

Wall-time setter: the two measurement lanes. meas-chromium-2 was still running at the cutoff (09:49), 118 min after the chromium lane started at 07:51, while every other Lean/site/page lane had finished by 09:22 (only lean-doc-fix-r4, started 09:36, ran later) and the last landing on main was 09:41Z. Their lanes are 118 and 111 min versus 68 min for the longest Lean chain. Inside those lanes model time is only 30-40%; the rest is shell time waiting on a browser or simulator run, and a quarter of it is polling sleeps.

Serial waiting inside the window: 9 min with nobody busy (the only gap over 30 s is 07:16-07:22, 347 s, lead idle waiting for the user) and 28 min with a single agent busy; all of the single-agent time is before 07:50: wf:delta:rev5 ran alone from about 07:00 to 07:15 (plan revision workflow), then 07:15-07:22 nothing ran while the lead waited for the user, and 07:22-07:50 only 1-4 plan/env/page agents ran.

Time with at most one agent busy: 37 min before 07:50 and 0 min after.

## 6. Top measured causes of lost parallelism

| rank | cause | measured | unit / note |
|---|---|---|---|
| 1 | Polling instead of blocking: sleep and wait loops hold an agent while a background job runs | 110 | agent-min inside the window, 78 of it in meas-webkit-2 (32), meas-chromium-2 (29), gate-breakpoints (11), meas-chromium (5.5) |
| 2 | Lead serialisation: one lead, one model turn at a time; 46% busy, 65% busy in the 08:00 hour; every landing, spawn and review passes through it | 101 | lead-busy min of 219; 31 of 60 agent events queued behind a busy lead; per-event pickup median 5 s |
| 3 | Tool-bound lane tails: the two measurement lanes are the critical path and spend their time in host.mjs, determinism and simctl runs (polling excluded, counted in the polling row) | 96 | agent-min of non-polling shell time in 4 agents; lanes 118 and 111 min vs 68 min Lean chain |
| 4 | Resource contention: lake, pnpm and browser runs slow each other | 63 | agent-min extra at ~x1.20 per concurrent heavy command (25% of heavy-call time) |
| 5 | Ramp and single-agent time: serial plan/env work before the build wave, follow-up agents started after a gap | 37 | wall min with at most 1 agent busy (17% of window), 37 before 07:50; r3->r4 doc fix follow-up gap 15 min |

Next, not in the top 5: unanswered API requests 15 agent-min in the window; user prompts and AskUserQuestion 3.6 min in the window; permission waits 0.1 min. Note the units differ (agent-minutes of lost work versus wall minutes), so the ranking is by size of the number, not by wall-time gain; the wall-time effect of each is smaller because the other lanes ran meanwhile.

