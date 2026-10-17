---
kind: kickoff-note
id: 08-chat-forensics-04-failures-conflicts
title: "v1 chat forensics 4: failures and conflicts between agents"
date: 2026-10-17
status: draft for user review
sources: v1 transcripts (digest in .local/v1-chat-digest/out), v1 console/incidents.json, findings.json, threads/, steps/, v1 git log
---

# v1 chat forensics 4: failures and conflicts

Status words: **MEASURED** = computed from the data with the command shown. **INFERRED** = my reading or an
estimate built on measured numbers. **QUOTED** = the user's or an agent's words (short, or paraphrased).

## 0. Answer first

1. **Most of v1's 5,393 recorded errors were not failures of the work.** 57 % (3,046) were Claude Code refusing a
   Bash command inside a worktree agent because it could not prove the command stayed in that worktree. 233 of
   those were identifiable attempts to touch the shared checkout. The other 2,813 were commands the checker could not
   verify (868 "too complex to verify", 616 "names git in a form too complex", inline `node -e`, `sed` with a variable,
   `python`) (MEASURED, §2.1). That those 2,813 were harmless is likely but INFERRED.
2. **Error turns were cheap; the failure system around them was not.** All 5,393 errors together cost about 1.0 B
   context tokens, 3.8 % of v1's 26.7 B (INFERRED from measured per-agent averages, §2). The bigger costs were the
   tools built to handle failures:
   - 132 toolsmith agents used 3.42 B cache-read tokens (13 %) (MEASURED, §3).
   - 1,889 "check iphone connection" cron prompts and 988 "check all agents" cron prompts made up 11 % of the lead's
     API calls (MEASURED, §4.5).
   - 82 of the 166 steps the user was asked to do were device chores, not judgments (MEASURED, §6).
3. **By root cause, a third of the 276 incidents came from coupled tooling:**
   - 44 tests that broke when the shared Mac was busy;
   - 40 bugs in the home-made lock, queue and lease scheduler;
   - 9 races between processes, or version skew between worktrees.
   That is 93 incidents (34 %). The environment and the phone caused 57 (21 %), the enforcement and coordination
   tools themselves 46 (17 %), and plain logic bugs a test would catch 24 (9 %). Agent mistakes caused only 4
   (counts MEASURED with `inctax.mjs`; the labels are my hand classification, so the split is INFERRED; §3).
4. **The phone was often only where a failure showed up, not its cause.** Of the 132 incident titles that mention
   the phone, Simulator, WDA, Safari or Xcode, only 51 (39 %) have an environment root cause. 42 are scheduling or
   test coupling, 13 are alarms or board bugs, and 17 are feature requests (MEASURED, §3.2). v2's "fewer phone
   blocks" goal will not remove that 61 %. Removing the scheduler and the alarms will.
5. **Conflicts between agents were mostly about the shared phone and shared files, not about the code.**
   - The lead reordered the measurement queue by hand about 230 times (229 `repair --move` calls).
   - Agents sent 264 distinct messages asking for a queue or phone order (MEASURED, §5.4).
   - Four shared ledgers took 1,194 commits (`ops-handover.md` 569, `PREDICTIONS.md` 378, `PROGRESS.json` 148,
     `CLAUDE.md` 99), and rebases needed `git rebase --continue` 94 times (MEASURED, §5.1).
   - Contradictory findings were rare and mostly caught by their own authors: 9 corrections (7 by the same agent
     within the hour) and 4 claims marked refuted out of 375 findings (MEASURED, §5.2).
   - Duplicated work was low at the spawn level. One page region, though, drew 23 agents and 3.06 B cache-read
     tokens (12 %, by name over all time; [05 C] counts the line by spawn window as 37 agents and 2.78 B) (MEASURED,
     §5.3).

## 1. Data and how to reproduce

All commands run **from the digest directory** unless noted:

```sh
cd .local/v1-chat-digest/out           # in the v2 repo; the digest of the v1 transcripts
V1=../../../../fastwork-com-web-optimize  # the v1 repo, read-only (adjust to your checkout)
T=~/.claude/projects/<v1-project-dir>    # the v1 raw transcripts, read-only (3 GB; never cat whole)
```

- `errors.jsonl`: 5,393 records = 5,251 tool errors (4,880 of them Bash), 98 hook errors and 44 API errors.
  `jq -r .kind errors.jsonl | sort | uniq -c` (MEASURED).
- `agents.json`: 848 rows, 135,493 model turns, 25.73 B cache-read tokens.
  `jq '[.[].asst]|add, ([.[].usage.cacheRead]|add/1e9)' agents.json` (MEASURED).
- `$V1/console/incidents.json` (276), `findings.json` (375), `threads/*.json` (278), `steps/C-*.json` (166).
- Two scripts do the classification. They are in Appendix A: `errtax.mjs` for the error classes and `inctax.mjs`
  for the incident root-cause labels. Save them anywhere and run `node errtax.mjs .` and
  `node inctax.mjs "$V1" .`.
- **Command counts.** Counts taken from `/tmp/cmds.txt` below use the regex window `"command":"[^"]{0,600}`, which
  stops at the first escaped quote in a command. Commands with a quote before the matched text are lost, so these
  counts undercount; they also include commands echoed inside results. Treat them as rough. The `lock.mjs` counts in
  §4.2 were redone by a full JSON parse (README B14).
- **The token cost of an error** is estimated as "one extra turn at that agent's mean context per turn". The mean is
  `(cacheRead + cacheWrite + input) / asst` from `agents.json`. That is a lower bound on turns, because a refused
  call usually costs one retry. It is only a rough size of tokens (INFERRED).

## 2. Error taxonomy (5,393 records)

`node errtax.mjs .` (MEASURED; the classes are regexes, first match wins, Appendix A):

| Class | n | % | ≈ ctx tokens | Legit or wrong? | Architectural root cause |
|---|---:|---:|---:|---|---|
| Worktree isolation: **cannot verify** the command | 2,813 | 52.2 | 524 M | Likely **wrong** in effect (INFERRED): the check was conservative and the command was probably harmless, but it needed a rewrite | Agents wrote multi-step inline shell or `node -e`/`sed`/`python` instead of calling committed scripts |
| Other non-zero exit (normal output; mostly read pipelines whose last `grep`/`diff`/`test` found nothing) | 780 | 14.5 | 129 M | Not a failure (INFERRED from a 60-record sample) | n/a |
| Agent's own script or tool-call error (Traceback, SyntaxError, missing file, Edit string not found, unknown agent type) | 447 | 8.3 | 85 M | Agent mistakes at the call level | Inline throwaway scripts |
| Worktree isolation: **identifiable** attempt on the shared checkout (`cd` main, `git -C`) | 233 | 4.3 | 43 M | **Legit** | Agents tried to land or read from main themselves |
| Auto-mode classifier **unavailable** (its model timed out) | 211 | 3.9 | 43 M | **Wrong**: an outage, not a judgment; it also blocked 36 `SendMessage` calls | Permission mode `auto` makes every call depend on a second model |
| Wait/poll timed out (`wait.mjs`, `TIMEOUT file`) | 211 | 3.9 | 38 M | Expected | Agents waiting on peers, the lock or the phone |
| Self-built lints and CLI checks (answer format, `--note too long`, `bad --waiting-on`) | 135 | 2.5 | 28 M | Mostly legit, but they are friction | Rules enforced at post time with no draft helper |
| Stop hook (sound player failed) | 98 | 1.8 | 25 M | Harmless | A cosmetic hook |
| Device (WDA, usbmux, Simulator) | 96 | 1.8 | 18 M | Real | §4.3 |
| Auto-mode **denied** (Irreversible Local Destruction 6, Interfere With Workloads 5, …) | 71 | 1.3 | 15 M | Mixed | Same as above |
| `fg-guard` hook (long command in the foreground) | 47 | 0.9 | 10 M | **Legit** by rule (user rule T-152), but always a retry | Agents went "deaf" during long foreground commands |
| Test failures | 47 | 0.9 | 10 M | Real | §4.2 |
| Git conflicts (`CONFLICT`, `could not apply`, `cannot rebase`) | 42 | 0.8 | 8 M | Real | §5.1 |
| Lock held (`[lock wait] … held by`) | 41 | 0.8 | 8 M | Expected | §4.2 |
| Harness blocked `sleep N` | 28 | 0.5 | 5 M | Legit | Agents polled with `sleep` |
| `git-guard` hook | 18 | 0.3 | 4 M | **Legit**: privacy (no viewing of screen recordings), no push, no hook bypass. 1 was a parse failure | |
| API: weekly usage limit | 18 | 0.3 | 4 M | External | §2.3 |
| User rejected the call | 16 | 0.3 | 3 M | Legit | |
| Pre-commit hook | 15 | 0.3 | 3 M | Legit | |
| API: Mac slept mid-response 10, 529 overloaded 7, other 9 | 26 | 0.5 | 6 M | External/host | §4.3 |
| **Total** | 5,393 | | **1.01 B = 3.8 % of 26.67 B** | | |

### 2.1 The worktree-isolation refusals (3,046)

- **Reasons** (MEASURED):
  - "too complex to verify": 868;
  - "names git in a form too complex": 616;
  - "runs sed with a value computed at runtime": 369;
  - "runs node with a value computed at runtime": 163;
  - `cd` to the shared checkout: 75 + 70;
  - `git -C` to the shared checkout: 64.

  ```sh
  jq -r 'select(.msg|test("is isolated in the worktree"))|.msg|capture("but (?<r>[^.—]*)").r' errors.jsonl \
    | sed -E 's/\(the variable [^)]*\)/(var)/; s#/[^ ]+#PATH#g' | cut -c1-90 | sort | uniq -c | sort -rn | head
  ```
- **Spread.** 358 agents hit the check, in 2,299 episodes (refusals by one agent less than 2 minutes apart). The
  median episode had 1 refusal and 146 episodes had 3 or more (MEASURED; the one-liner is in Appendix B). Agents
  recovered on the first rewrite, so each refusal cost about one turn (INFERRED).
- **Timing.** 2,386 of the 3,046 (78 %) fell in the first six days (Sep 30 to Oct 5), when most fix agents ran
  (MEASURED: `jq -r 'select(.msg|test("is isolated in the worktree"))|.ts[0:10]' errors.jsonl | awk '$1<="2026-10-05"' | wc -l`).
- **Who.** The worst were long-lived workers (mgmt-ops-10 178, fix-nav-morph 117, fix-hero-exit-threaded 111,
  int-v8 110, iphone-runner 100). These agents scripted their work inline in Bash (MEASURED: the same jq, keyed on
  `.who`).
- **Root cause (INFERRED).** v1's own tools were good, but agents glued them together with ad hoc shell. Every
  editing role in v2 is a worktree subagent (PLAN §8.2), so **v2 will hit the same check unless multi-step work is a
  committed `pnpm fw` verb**.

### 2.2 Guards: legit or wrong

- **Project guards were legit almost every time.**
  - `git-guard` blocked 18 calls: ffmpeg frame exports of screen recordings (a privacy rule, 9), `core.hooksPath`
    overrides (2), a push (1), and other rules.
  - `fg-guard` blocked 47 long foreground commands, 24 of them `iphone.mjs gesture`.
  - What they cost is the retry, plus the guards' own incidents (§4.4).
- **The harness checks were half legit.**
  - Worktree isolation: 233 legit and 2,813 unverifiable.
  - Auto mode: 211 outage refusals and 71 judgments.
  - So about 3,000 of the 3,300 harness refusals (≈ 91 %) did not stop anything harmful (INFERRED).

### 2.3 API errors and limits (44)

- **Weekly usage limit: 18 errors in 3 episodes.** On 4 Oct 07:23, 5 Oct 12:31 and 8 Oct 18:18Z the limit stopped
  the lead plus 5, 1 and 4 agents (6, 2 and 5 transcripts; 11 distinct transcripts in total) (MEASURED:
  `jq -r 'select(.kind=="api" and (.msg|test("weekly limit")))|"\(.ts[0:13]) \(.who)"' errors.jsonl | sort -u | cut -c1-13 | uniq -c`).
- The lead resumed within about 2 to 8 minutes each time (MEASURED from the lead's per-minute assistant timestamps
  in `$T`; QUOTED, paraphrased: the user said to continue once usage was restored).
- **The real cost was what died with the agents.** A phone-block runner launched from an agent's background shell
  died when its agent ended on an API error (I-221). The same class of failure came from Claude Code's 30-minute
  background limit (I-240, I-256) (MEASURED, `incidents.json`).
- 529 overloaded: 7. Mac slept mid-response: 10. Response cut off or connection lost: 7. Login expired: 2.

## 3. Incident root causes (276 incidents)

- **Method.** I read every title and resolution note and gave each incident one root-cause label (`inctax.mjs`,
  Appendix A; the full label map is in the script).
- **The question the label answers** is "what would have had to be different for this not to happen?". It does not
  answer "what did it touch?" [01 §B.1] counted by area, so its "device/driver ~111" is a different cut.

`node inctax.mjs "$V1" .` (MEASURED):

| Bucket / label | n | % | blocking | dup | unresolved | median h | ts-iNNN fixers | fixer cache-read |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| **Coupled tooling**: flaky tests on a shared host | 44 | 16 | 3 | 3 | 10 | 1.3 | 5 | 0.12 B |
| **Coupled tooling**: lock, queue and lease scheduler | 40 | 14 | 2 | 1 | 6 | 2.2 | 11 | 0.34 B |
| **Coupled tooling**: process races, worktree version skew | 9 | 3 | 1 | 2 | 0 | 0.1 | 1 | 0.00 B |
| **Enforcement and coordination tools** (router, idle alarm, board, scrubber, answer lint, guards) | 46 | 17 | 3 | 0 | 7 | 1.2 | 9 | 0.12 B |
| **Not a failure**: feature request filed as an incident | 45 | 16 | 2 | 0 | 5 | 1.4 | 22 | 0.60 B |
| **Missing test**: plain logic bug | 24 | 9 | 3 | 0 | 2 | 1.1 | 6 | 0.11 B |
| **Environment / phone**: device driver code (our iPhone/Sim tools) | 24 | 9 | 7 | 1 | 6 | 0.9 | 3 | 0.04 B |
| **Environment / phone**: the device itself (USB, lock screen, WDA, heat, Wi-Fi) | 21 | 8 | 10 | 1 | 3 | 0.5 | 4 | 0.07 B |
| **Environment / phone**: the Mac (sleep, disk, Xcode licence, gh login) | 12 | 4 | 2 | 1 | 0 | 1.1 | 3 | 0.06 B |
| **Harness limit** (30-min background cap, `EnterWorktree`, teammate not woken) | 5 | 2 | 1 | 1 | 3 | 0.4 | 2 | 0.01 B |
| **Agent mistake** | 4 | 1 | 0 | 1 | 0 | 0.1 | 0 | 0 |
| Product bug in the site | 2 | 1 | 0 | 0 | 1 | 3.6 | 0 | 0 |

Rolled up into the five buckets of this note's brief (MEASURED, sums of the rows above):

| Bucket | Incidents | Blocking (of 34) |
|---|---:|---:|
| Coupled tooling | 93 (34 %) | 6 |
| Environment / phone | 57 (21 %) | **19 (56 %)** |
| Enforcement friction | 46 (17 %) | 3 |
| Missing test | 24 (9 %) | 3 |
| Agent mistake | 4 (1 %) | 0 |
| (not failures: feature asks 45, harness 5, product 2) | 52 (19 %) | 3 |

Plus the toolsmiths that the `ts-iNNN` naming does not tie to one incident (MEASURED, name regex over
`agents.json`; the regexes are mine, so group membership is a judgement):

| Group | Agents | Cache-read |
|---|---:|---:|
| Lock, queue and lane (`ts-lock-*`, `ts-lease-renew`, `ts-head-aging`, `ts-gate*`, `ts-phone-hold`, `ts-prio`) | 10 | 0.38 B |
| Board, console, guards and lints (`ts-board`, `ts-threads`, `ts-answer-lint`, `ts-fg-guard`, `ts-proposal*`, …) | 18 | 0.49 B |
| **All `ts-*` toolsmiths** (`/ts-`) | 132 | **3.42 B (13.3 % of v1)** |
| `mgmt-*` managers | 16 | 1.58 B (6.2 %) |

So lock and queue work used 0.34 B (`ts-iNNN`) + 0.38 B (named) = 0.72 B, and enforcement 0.12 B + 0.49 B = 0.61 B.
Feature requests' 0.60 B is `ts-iNNN` fixers only. Compare labels on one basis: by `ts-iNNN` fixers alone, feature
requests are largest (0.60 vs 0.34 vs 0.12 B); with named toolsmiths, lock and queue work is.

```sh
jq -r '.[]|select(.who|test("/ts-"))|.usage.cacheRead' agents.json | paste -sd+ - | bc       # all ts-* (3.42 B)
jq -r '[.[]|select((.name//"")|test("^ts-(lock|lease|prio|gate|head-aging|phone-hold|queue|lane|fair|sched)"))]|"\(length) \(map(.usage.cacheRead)|add/1e9)"' agents.json
jq -r '[.[]|select((.name//"")|test("^ts-") and test("board|thread|answer|lint|guard|proposal|console|alarm|idle|router|scrub"))]|"\(length) \(map(.usage.cacheRead)|add/1e9)"' agents.json
```

The README uses the 133-agent `^(ts|tool)` family (3.44 B, 13.4 %) so that it matches note 03's dollar table.

### 3.1 Port, process and shared-directory conflicts

14 incidents. Each one is two processes, or a test and a live service, sharing one name on one host (MEASURED,
by label):

- two servers writing the same certificate path: I-001, I-004;
- all subagents sharing one scratchpad folder: I-006. One agent overwrote another's `results-mobile.json` (QUOTED,
  paraphrased from both agents' messages);
- a test killing "chrome" by process name, which matched other agents' real measurement Chrome: I-008, I-236;
- an old Chrome for Testing opened on a profile that a newer Chrome had written: I-036;
- unit tests hitting the phone's live WDA port 8100: I-094, I-102;
- tests colliding with the live Try-it host on port 6400: I-157, I-158, I-161;
- port arithmetic past 65535: I-166;
- a free-port probe racing between two parallel `npm test` runs: I-193.

### 3.2 The phone was often only where the failure showed up

132 titles match a phone regex. By root cause:

| Root cause | Titles |
|---|---:|
| Environment | 51 (39 %) |
| Coupled tooling | 42 |
| Feature requests | 17 |
| Enforcement and alarms | 13 |
| Agent mistake, missing test, harness | 3 each |

(MEASURED: the last lines of `inctax.mjs`.) Typical non-device "phone" incidents:

- I-123: a user step outlived its runner's lease, so the next agent took the phone while the user waited.
- I-165: a wait option kept an agent asleep 9.5 minutes after it got the phone.
- I-144: the idle alarm told the user their own hand-test was idle.

## 4. The top categories: frequency, cost, root cause

### 4.1 Inline scripting in isolated worktrees

- **How often and what it cost.** See §2.1: 3,046 refusals and about 0.57 B context tokens (INFERRED).
- **Root cause (INFERRED).**
  - Agents built multi-step pipelines in Bash: variables, `sed` on computed paths, `node -e` programs, and
    `cd main && git …` to land their own work.
  - v1 had no "verb" layer that turned a common sequence into one plain command an allow rule could match.

### 4.2 Coupled tooling: one host, one scheduler, many copies of the tools

**Flaky tests (44 incidents, 10 still open at the end).**

- **Why they failed.**
  - The tests read the real host: its load, its clock, its free ports and its process list.
  - The full suite ran in every tooling pre-commit while other agents measured on the same Mac. Many titles say
    "under load".
  - Examples: I-024 (a test ran 940 s because it read real host load) and I-258 (five timing tests at load1 30-97).
- **Commands.** 1,791 `npm run test:unit` and 245 `npm test` (MEASURED:
  `rg -o --no-filename '"command":"[^"]{0,600}' -g '*.jsonl' "$T" > /tmp/cmds.txt; grep -cE 'npm run test:unit' /tmp/cmds.txt`;
  the count includes any command echoed inside a result, so it is an upper bound).

**The lock, queue and lease scheduler (40 incidents, the slowest to fix at a median of 2.2 h).**

- **What it was.** `lock.mjs` grew to 1,685 lines [01 §B.1]. It handled:
  - a short lane, a shared lane and an exclusive lane;
  - host-load gates, reader-ageing rules and writer preference;
  - lease TTLs, and phone-block priority.
- **How each fix went (INFERRED).** Each fairness rule starved some other class of job, so the next incident
  followed:
  - I-049: readers starve, so a 10-minute reader rule was added;
  - I-097: that rule starves a phone hold;
  - I-207: phone priority starves readers;
  - I-210: exclusive heads starve.
- **Agent calls (MEASURED, over agent commands in `$T`).**
  - By full JSON parse (README B14): `lock.mjs status` in 6,424 unique tool calls; `repair --move` in 244 (229 in
    the lead's transcripts, 15 in subagents').
  - By the truncated regex window (§1; undercounts): `run` 2,735, `acquire` 657, `wait` 436, `doctor` 241. An
    earlier draft gave `status` 4,756 and `repair --move` 194 from this window; both are retired.
  - Window command: `grep -oE 'lock\.mjs (repair[^&|;]{0,80}--move|[a-z-]+)' /tmp/cmds.txt | sort | uniq -c | sort -rn`.

**Version skew and races (9 incidents).**

- **What happened.** Each worktree ran its own copy of `tools/`, and every copy coordinated through one shared lock
  state in the git common dir:
  - I-010 and I-011: a waiter on pre-fix lock code misread the new state;
  - I-102: a branch based before a fix;
  - I-041: unlanded lock code granted co-holds on the **live** lock, breaking exclusivity for 17 minutes.
- **Root cause (INFERRED).** Shared state with no protocol version, read and written by clients of different ages.

### 4.3 The environment and the phone

- **How often.** 57 incidents, 19 of the 34 blocking ones (MEASURED):
  - USB link lost: I-040, I-127, I-173, I-235, I-239, I-222;
  - the phone auto-locked during a cooling wait: I-215, I-217;
  - WDA not authorized after a re-plug: I-227, I-244;
  - Critical heat readings under Xcode's Serious condition: I-225, I-231;
  - Mac sleep: I-026, I-068, I-071, I-098, I-101;
  - disk full: I-095, I-124.
- **The user did the device chores.** 82 of the 166 user steps were chores (MEASURED):

  | Chore | Steps |
  |---|---:|
  | Re-plug or cable | 35 |
  | Xcode thermal toggles | 33 |
  | Unlock or UI Automation | 15 |

  Command: `jq -r .title "$V1"/console/steps/C-*.json | grep -ciE 're-?plug|unplug|cable|usb|unlock|auto-lock|ui automation|xcode|thermal|serious|wi-?fi|licen|login|trust|connect'`.
  The groups overlap.
- **Detection by polling.** The lead ran "check iphone connection" every 5 minutes, 1,889 times (§4.5).
- **Root cause (INFERRED).** A cabled phone, Xcode-induced heat states and WDA sessions each fail on their own, and
  v1 detected each failure inside a long measurement block rather than before it. The preflight with named trap codes
  (I-227's fix) arrived only on 6 Oct, day 7 of 10 (MEASURED: `resolvedAt` in `incidents.json`).

### 4.4 Enforcement and coordination tools that failed in turn

- **How often.** 46 incidents (17 %) and about 0.61 B cache-read in fixers (0.12 B `ts-iNNN` + 0.49 B in 18 named
  toolsmiths; MEASURED with the commands in §3). By kind:
  - Router or listener misses: I-137, I-163, I-169, I-181. User questions went unanswered for minutes.
  - Idle-alarm false alarms: I-125, I-144, I-189, I-196, I-252.
  - Board staleness: I-044, I-108, I-145, I-183, I-187, I-188, I-248.
  - Scrubbers mangling text: I-119, I-139, I-191, I-194, I-228.
  - A lint passing bad output (I-178) or failing good input (I-232).
  - A guard gap: I-267.
  - The disk auto-clean deleting article images: I-275.
- **Root cause (INFERRED).** Each user complaint produced a new enforcer ([01 §B.3] lists "rules added per incident,
  never removed" as anti-pattern 2). Each enforcer read shared state that agents wrote by hand, so it inherited the staleness of that state.
  The status board, for example, depended on agent self-reports, not on the events the tools already had (I-145).

### 4.5 Monitoring by recurring prompts

The lead session's scheduled fires, by prompt (MEASURED):

```sh
rg '"subtype":"scheduled_task_fire"' "$T"/<lead-session>.jsonl | grep -oE '"cron":"[^"]*","prompt":"[^"]{0,40}' | sort | uniq -c | sort -rn
```

| Prompt | Every | Fires |
|---|---|---:|
| "check iphone connection" | 5 min | 1,889 |
| "check all agents can work together properly" | 10 min | 988 |
| lead check-in with the manager | 30 min | 365 |
| usage check | 30 min | 334 |
| hourly team report | 1 h | 164 |

- **Share of the lead's turns.** The two checks alone are 2,877 fires, 11.4 % of the lead's 25,176 turns (MEASURED).
- **Rough token cost.** At the lead's mean of 234k context tokens per turn
  (`jq '.[]|select(.who=="lead:391f6dee")|(.usage.cacheRead+.usage.cacheWrite+.usage.input)/.asst' agents.json`),
  that is about 0.67 B tokens (INFERRED, ≥ 1 turn per fire). [01] put the cost of recurring checks at about 200 M up
  to 5 Oct. This note's figure covers the whole run and both prompts.
- **Origin.** Both checks came from the user's own `/loop` prompts; the second asked the lead to check that all agents
  work together, or it would become the bottleneck (paraphrased). The check-in, usage and hourly-report crons were
  created by the lead (864 fires; README B12).

## 5. Conflicts between agents

### 5.1 Same files and landing

- **Code edits rarely collided**, because every editor had its own worktree and the lead landed fast-forward only.
- **Git commands (MEASURED, over agent commands in `$T`, upper bounds):**

  | Command | Count |
  |---|---:|
  | `git rebase main` | 1,187 |
  | `git rebase --continue` | 94 |
  | `git merge --ff-only` | 562 |
  | `git stash` | 340 |
  | `git checkout --theirs` or `--ours` | 13 |

  Command: `grep -cE 'git rebase --continue' /tmp/cmds.txt`, and the same for the others.
- **Where conflicts came from** (from the conflict errors): `tools/lib/lock.mjs`, `fixes/PREDICTIONS.md`,
  `tools/sim.mjs`, `tools/iphone.mjs`, `tools/console.mjs`, `tests/helpers.mjs` (MEASURED:
  `jq -r 'select(.tool=="Bash")|.msg' errors.jsonl | grep -oE 'Merge conflict in [^ \\]+' | sort | uniq -c | sort -rn`).
- **Hot shared files** (MEASURED: `git -C "$V1" log --format= --name-only | grep -v '^$' | sort | uniq -c | sort -rn | head`):

  | File | Commits (of 2,521) |
  |---|---:|
  | `research/management/ops-handover.md` | 569 |
  | `fixes/PREDICTIONS.md` | 378 |
  | `fixes/PROGRESS.json` | 148 |
  | `CLAUDE.md` | 99 |

  Every manager rewrote the one handover file, and every fix appended to the one predictions ledger.
- **Shared board state was overwritten too** (QUOTED, paraphrased):
  - one desk agent's status update overwrote another desk agent's note on the board;
  - a fix agent's "parked" status overwrote the "landed" state the lead had set.
- **Root cause (INFERRED).** Coordination state lived in shared, hand-edited files and rows, not in one append-only
  log with a single writer.

### 5.2 Contradictory findings

- **Counts (MEASURED).** Of 375 findings, 4 carry `claim: refuted` (F-051, F-055, F-072, F-299). 9 more are
  explicit corrections. 7 of the 9 were corrected by the **same** agent within two hours (F-027, F-044, F-065, F-208,
  F-300, F-352, F-359). Command:

  ```sh
  jq -r '.[]|select(.claim=="refuted")|.id' "$V1"/console/findings.json
  jq -r '.[]|select(.title|test("^Corrections? to F-|refutes F-"))|"\(.id) \(.by) \(.title[0:60])"' "$V1"/console/findings.json
  ```
- **Two cross-agent corrections, both found by auditor roles:**
  - res-layerpainted corrected ts-render-signals' claim about why a Chrome trace signal died (F-064 on F-059);
  - arch-claims corrected two reader claims against the iOS 26.6 WebKit source (F-070 on F-051 and F-055).
- **Contradictions between peers surfaced through the managers, not directly** (QUOTED, paraphrased):
  - mgmt-ops-10 noticed that fix-scroll-cb said `scrollY`/`innerHeight` reads force layout (CONFIRMED in source),
    which contradicted int-v8's "cached box, no layout read".
  - art-worst-cases had told the user one thing about the Xcode thermal setting, and a later lead step (C-061) said
    the opposite. The agent paused and asked the lead rather than correct the user itself.
- **Root cause (INFERRED).** The claim-status discipline worked. What was missing was a place where two live claims
  about the same mechanism met automatically. The `findings.json` board had 375 entries and no "same mechanism"
  key.

### 5.3 Duplicated work

- **Low at the spawn level.** Repeated names are mostly deliberate respawns: mgmt-ops ×10 and review-scene-scope ×5
  (MEASURED: `jq -r 'select(.kind=="spawn")|.name//"-"' events.jsonl | sed -E 's/-[0-9]+$//' | sort | uniq -c | sort -rn | head`).
- **Duplicate incidents: 11.** The worst case was one flaky test filed four times (I-128, I-133, I-135, I-138), which
  led to dedup by signature (I-151).
- **Peer messages flagging overlap: only 7** (QUOTED example: fix-nav-morph asked before drafting, because its #4
  "is the same change as fix-morph-gpu's N2"). MEASURED:

  ```sh
  jq -c 'select(.msg|test("(already (fixed|landed|done|did|built|implemented|covered) (by|in|on main by)|same (change|fix|work) as|duplicates? (my|the work|work)|someone else (already|is)|both (of us|agents) (changed|edited|fixed))";"i"))|[.from,(.msg|.[0:300])]' peer-messages.jsonl | sort -u | wc -l
  ```
- **Where duplication really happened: one region.** The end-of-page morph region drew 23 agents (fix-nav-morph,
  fix-morph-gpu, arch-compositor-morph, fix-end-morph, fix-end-morph-p1, fix-menu-layers, arch-end-fresh, reviewers
  and mappers). They used 14,337 turns and 3.06 B cache-read, 11.9 % of v1, by name over all time (MEASURED:
  `jq -r '[.[]|select(.who|test("morph|-end-|end-morph|menu"))]|"\(length) \(map(.asst)|add) \(map(.usage.cacheRead)|add/1e9)"' agents.json`).
  [01] counts 19 end-of-page phone blocks with 5 passes.
- **Root cause (INFERRED).** A shared engine (scroll engine, morph, scene manager) inside a minified bundle had no
  part boundary, so successive owners re-derived the same context.

### 5.4 Priority fights over the phone and the Mac lane

- **Who argued for an order.** 264 distinct agent messages asked for a queue order, a phone order or a move (MEASURED):

  ```sh
  jq -c 'select(.msg|test("please move|move (it|me|us|my [a-z]+|[a-z-]+) (up|first|ahead|to #)|jump the queue|reorder the queue|ahead of [a-z-]+ in the (queue|lane)|queue order|phone order|lease order";"i"))|[.from,(.msg|.[0:300])]' peer-messages.jsonl | sort -u | wc -l
  ```

  Top senders: mgmt-ops-10 41, iphone-runner 33, mgmt-ops-6 31, mgmt-ops-5 23, mgmt-ops-7 21. The managers acted
  as arbiters.
- **The lead moved queue entries by hand about 230 times** (229 `repair --move` calls, README B14). On 4 Oct alone
  it made 89 moves (I-185).
- **Priority rules became code, one incident at a time:**
  - phone holder before other Mac waiters (I-172);
  - lead-moved holds beat the reader rule (I-097);
  - user steps keep the phone (I-123);
  - a phone reservation for a promised user step (I-149, never landed).
- **The user saw the result (QUOTED, paraphrased):**
  - "the iPhone is free for a long time while many tasks wait for it" (T-058);
  - "why didn't you find this incident before I asked?" (T-149, on a 9.5-minute idle hold, I-165).
- **Root cause (INFERRED).** Agents held leases on the scarce device, rather than handing jobs to one runner that
  owned it. So the time it sat idle between holds belonged to whichever agent held the lease, and priority was
  settled by messages.

## 6. What the user saw (console channel)

- **Volume (MEASURED, node over `$V1/console/threads/*.json`; Appendix B).** The user posted 989 messages in 278
  console threads, plus 229 typed chat messages.
- **Agents answered fast:** median 0.7 minutes, p90 2.7, p99 13.1. Only 4 user messages got no reply.
- **Friction.** 101 user thread messages (10 %) contain friction words ("again", "still", "why did", "forgot",
  "idle", …). Repeated themes (QUOTED, paraphrased):
  - the phone sat idle while work waited (T-058, T-149);
  - the lead was the bottleneck again (T-105);
  - the lead should find and fix tool problems itself, because the user had said so many times (T-154);
  - a status board showing "waiting on you" when nothing was waiting (T-070).
- **What the console data says about the cause (INFERRED).** Fast replies did not prevent these complaints. The
  user's pain was **detection**: failures the user noticed before the system did.
- **The user found many of the enforcement bugs.** 15 of the 46 enforcement and coordination incidents cite a user
  thread or step in their title. So do 20 of the 45 feature requests (MEASURED: the last line of `inctax.mjs`).

## 7. Improvements for v2

Each item cites its evidence and the PLAN.md section it changes.

1. **Make every multi-step operation a committed verb, and keep worktree agents to one plain command per call.**
   - Evidence: 3,046 worktree-isolation refusals, 57 % of all errors; 2,813 were inline scripts the checker could
     not read; 358 agents hit it (§2.1).
   - Changes:
     - §8.2 `part-builder.md` body: add "Bash: one plain command per call; use `pnpm fw <verb>`; never `node -e`,
       `sed` on variables, `python -c`, `cd`, or `git -C`".
     - §8.3 allow list: keep only verb patterns.
     - Appendix B: add a spike SPK-n. Run `pnpm fw gate --part x` and `git add -- p && git commit -m` in a
       `name` + `isolation: "worktree"` subagent, and confirm zero refusals.
     - §8.4 Reporting: add "isolation refusals per 100 turns per role".
2. **Keep permission mode `default` (Appendix C), and measure prompts instead of classifier refusals.**
   - Evidence: auto mode refused 211 calls because its classifier was unavailable (36 of them `SendMessage`), and
     denied 71 more (§2).
   - Changes: Appendix C keeps `default`. §10.2 Day 1 adds a "prompts per hour" count from the first dry run, so the
     `fewer-permission-prompts` pass is judged by a number.
3. **Ban LLM polling for state a script can watch.**
   - Evidence: 1,889 "check iphone connection" fires and 988 "check all agents" fires, 11.4 % of lead turns and
     about 0.67 B tokens (§4.5).
   - Changes:
     - §8.4 lever 1 becomes a rule. No recurring `CronCreate` prompt may check device link, agent liveness or queue
       state. `console-api` watches usbmux/WDA and agent idleness and emits one event on a state change.
     - §8.3: add `CronCreate` to `ask`.
     - §3.4: the `TeammateIdle` hook moves from "later" to MVP only if M0 shows stalls (v1 I-274).
4. **Give the device lane one owner process and job submission, not leases held by agents.**
   - Evidence: 40 scheduler incidents, the slowest to fix (median 2.2 h); 0.34 B in their `ts-iNNN` fixers plus
     0.38 B in 10 named lock toolsmiths (§3); about 230 manual moves by the lead; 264 order-request messages; idle-while-held incidents I-111, I-155, I-165 and I-182
     (§4.2, §5.4).
   - Changes:
     - §4.1: the device lane is a job queue in `console-api`. Agents submit a job card; the runner holds the phone.
     - §3.2: add a contract row `agent → device lane: job {kind, card, priority class}`.
     - §5.1: add the device-lane priority order (user step > calibration > class X/P > spot-check) as a pure,
       table-tested function with no hand moves. A hand move is an event with a reason.
5. **Move device chores into a preflight, and count them as a validation metric.**
   - Evidence:
     - 82 of 166 user steps were chores (re-plug 35, Xcode thermal 33, unlock 15);
     - environment and phone caused 19 of the 34 blocking incidents;
     - WDA restarts failed after re-plugs and auto-lock (§4.3).
   - Changes:
     - §4.6 and §9.2 device stage: a `fw device check` preflight with v1's named trap codes (USB 4, unlock and UI
       Automation 10, extra tabs 11, proxy 12) runs **before** a session is offered to the user.
     - Session setup: Auto-Lock Never, one known USB port, and one thermal profile for the whole session.
     - §1.1 G2: add "user chore steps per phone session ≤ 1".
     - §11: add risk R17 (device link and heat state), with this mitigation.
6. **Tests never read the real host.**
   - Evidence: 44 flaky-test incidents (16 %), 10 still open at the end, mostly "under load". There were also 14
     port, process-name and shared-directory collisions (§3.1, §4.2).
   - Changes:
     - §5.4 and §2.2 ("Real time in tests"): extend to "no real host load, no real ports (port 0 with an injected
       listener), no global process-list matching, no shared temp folders". Add a lint for `os.loadavg`, `ps`,
       `pkill` and fixed ports in test files.
     - Engine-driving e2e tests run in their own TL layer, outside pre-commit (V-k).
     - Scratch paths are always per agent (`.cache/<agent>/`).
7. **Version the coordination protocol.**
   - Evidence: worktrees on old tool code misread the new lock state; unlanded lock code granted co-holds on the live
     lock (I-010, I-011, I-041, I-102; §4.2).
   - Changes: §3.2. Every client → `console-api` request carries `contractsVersion`. The server refuses a mismatch
     with "rebase". Only `console-api` (run from `main`) writes shared state, as §2.2's single-writer row already
     says. Add this failure mode to that row's evidence.
8. **No shared ledger files that many agents edit.**
   - Evidence: `ops-handover.md` 569 commits, `PREDICTIONS.md` 378, `PROGRESS.json` 148, `CLAUDE.md` 99; 94
     `rebase --continue`; board overwrites (§5.1).
   - Changes:
     - §7.1: predictions live only in each experiment's `card.md`, and handovers in per-agent `research/notes/`.
     - The board is a projection of `events.jsonl`, never a file.
     - §8.2: `CLAUDE.md` edits stay behind `ask`. Add a `kb lint` check that the file stays under the 1,500-word cap.
9. **Every enforcer gets a false-alarm test and a budget before it ships.**
   - Evidence: 46 incidents (17 %) were bugs in the router, alarms, board, scrubbers, lints and guards; about 0.61 B
     in their fixers; 135 lint refusals of agents' own drafts (§4.4, §2).
   - Changes: §2.2's "Rule for every new tool, hook or package" gains three clauses:
     - it reads only events, not agent self-reports;
     - it ships with golden tests for both false positives and false negatives;
     - an alarm that reaches the user must show ≥ 90 % precision on a replay of the event log before it is enabled.
10. **Separate requests from incidents in the bug ledger.**
    - Evidence: 45 of 276 incidents (16 %) were feature requests, with the largest `ts-iNNN` fixer spend of any label
      (22 agents, 0.60 B; named toolsmiths are not attributed by label) (§3).
    - Changes: §1.2 V-l gets a `kind: request | incident` field, so the "tool bug" rate that decides Lean's future at
      M4 (Q12) counts failures only. §7.2: add `request` to the frontmatter kinds, or keep it as a console-only
      record.
11. **Put a "same mechanism" key on claims, and let `kb lint` flag opposing live claims.**
    - Evidence:
      - 9 corrections and 4 refuted claims, mostly self-caught within the hour;
      - the cross-agent ones were found only by auditor roles or relayed by managers, such as the `scrollY`
        layout-read contradiction (§5.2).
    - Changes: §7.2 rule cards get `mechanism: <engine>/<family>/<id>`. `kb lint` fails when two cards share a
      mechanism with opposite statuses, and the review stage (§9.2) must cite the lint result.
12. **Device runs never live in an agent's shell.**
    - Evidence:
      - phone-block runners died with their agent's API error (I-221) or at the 30-minute background cap (I-240,
        I-256);
      - the weekly limit stopped the lead plus 5, 1 and 4 agents in three episodes (§2.3).
    - Changes: §3.1 and §8.1. Long runs are owned by `console-api`; agents submit them and wait on events. §8.4 adds
      an alert when weekly usage passes 80 %, before the hard stop.
13. **Cap agent-days per page region, not only per part.**
    - Evidence: one region drew 23 agents, 3.06 B and 11.9 % of v1 by name over all time (§5.3); [05 C] counts the
      end-of-page line by spawn window as 37 agents and 2.78 B.
    - Changes: §9.1 and §8.2. Each part's time box (1-2 agent-days) also applies to the **region** (all parts of the
      end-of-page morph together). Going past it requires a decision record (as §8.4's stop rule does for money).
14. **Spend on architecture, not on more agent rules.**
    - Evidence: agent mistakes caused 4 of 276 incidents, while coupled tooling plus enforcement caused 139 (§3; hand
      labels, so INFERRED).
    - Changes: §11 R7's mitigation also says "a new agent rule must cite an incident whose root cause is
      agent-mistake; otherwise fix the tool". This works together with the §2.2 rule.

## Appendix A. Classification scripts

`errtax.mjs` (run `node errtax.mjs .` in the digest dir):

```js
import fs from 'node:fs';
const D = process.argv[2];
const R = [ // first match wins; order matters
 ['iso-legit',     /isolated in the worktree[\s\S]*(changes directory to (the shared checkout|a location computed)|redirects git to the shared checkout|points git at a directory computed)/],
 ['iso-unverifiable', /is isolated in the worktree/],
 ['auto-unavailable', /temporarily unavailable .*auto mode|could not evaluate this action|gave no verdict/i],
 ['auto-denied',   /denied by the Claude Code auto mode|Permission for this (action|command) was denied|Permission to use \w+ with command/],
 ['user-rejected', /doesn't want to proceed/],
 ['fg-guard',      /fg-guard/],
 ['git-guard',     /git-guard/],
 ['sleep-block',   /Blocked: sleep/],
 ['self-lint',     /FORMAT FAIL|answer-format|bad --|is too long|is not valid|needs the id|bad status id|PROGRESS INVALID/],
 ['lock-held',     /\[lock wait|held by "|waits for a timing hold/],
 ['wait-timeout',  /\[wait [0-9:Z]+ \+\d+s\]|TIMEOUT file|NO NEW FINDINGS|STILL OPEN/],
 ['git-conflict',  /CONFLICT|could not apply|cannot rebase|Please commit or stash|Needed a single revision|rebase --continue/i],
 ['pre-commit',    /pre-commit|scope guard/i],
 ['test-fail',     /^not ok|\nnot ok|# fail [1-9]|tests? failed|npm (ERR|error)|✖ |\bFAIL\b|AssertionError/],
 ['device',        /WDA|iphone|iPhone|usbmux|simctl|Simulator|webkit proxy|:9222|xctrace/],
 ['own-script',    /Traceback|SyntaxError|ReferenceError|TypeError|\[eval\]|<anonymous_script>|node:internal|node:fs|\(eval\):\d|command not found|No such file|no matches found|ugrep: error|unknown shorthand|sed: |jq: error|parse error|Cannot find module|ERR_|String to replace not found|File has been modified|File does not exist|exceeds maximum|not found\. Available agents|No background command/],
];
const A = JSON.parse(fs.readFileSync(`${D}/agents.json`));
const per = {}; for (const a of A) { const p = per[a.who] ??= { t: 0, ctx: 0 }; p.t += a.asst; p.ctx += a.usage.cacheRead + a.usage.cacheWrite + a.usage.input; }
const E = fs.readFileSync(`${D}/errors.jsonl`, 'utf8').trim().split('\n').map(JSON.parse);
const g = {};
for (const e of E) {
  let c = e.kind === 'tool' ? 'other-exit' : e.kind; // hook | api
  if (e.kind === 'tool') for (const [k, re] of R) if (re.test(e.msg)) { c = k; break; }
  if (e.kind === 'api') c = /weekly limit/.test(e.msg) ? 'api-weekly-limit' : /sleep/.test(e.msg) ? 'api-mac-slept' : /529/.test(e.msg) ? 'api-529' : 'api-other';
  const x = g[c] ??= { n: 0, ctx: 0 }; x.n++; const p = per[e.who]; if (p && p.t) x.ctx += p.ctx / p.t;
}
const tot = E.length, allCtx = Object.values(per).reduce((s, p) => s + p.ctx, 0);
let sum = 0;
for (const [k, x] of Object.entries(g).sort((a, b) => b[1].n - a[1].n)) { sum += x.ctx; console.log(k.padEnd(18), String(x.n).padStart(5), (100 * x.n / tot).toFixed(1).padStart(5) + '%', (x.ctx / 1e6).toFixed(0).padStart(5) + 'M ctx'); }
console.log('total', tot, 'ctx', (sum / 1e9).toFixed(2) + 'B of', (allCtx / 1e9).toFixed(2) + 'B =', (100 * sum / allCtx).toFixed(1) + '%');
```

`inctax.mjs` (run `node inctax.mjs "$V1" .`). The label map is the hand classification. Challenge any label by
editing its line and re-running; the script refuses a map that does not cover all 276 incidents exactly once.

```js
import fs from 'node:fs';
const [V1, D] = process.argv.slice(2);
const L = { // bucket/sub-label: incident numbers (hand-assigned from title + resolution note)
 'coupled/flaky-shared-host': '008 021 022 024 025 027 055 057 065 072 076 094 099 114 120 121 128 132 133 135 138 153 157 158 159 161 166 174 190 192 193 195 197 213 229 230 234 236 237 238 243 258 264 276',
 'coupled/lock-queue': '005 007 012 016 017 019 020 023 030 035 049 051 056 063 080 081 086 091 097 113 122 123 136 148 149 155 160 165 168 171 172 176 182 184 185 202 207 210 224 255',
 'coupled/race-skew': '001 004 006 010 011 014 015 066 102',
 'env/device': '003 040 042 098 127 173 208 212 215 216 217 220 222 225 227 231 235 239 244 251 260',
 'env/device-driver': '037 038 039 050 052 069 077 078 088 112 141 154 201 211 214 223 233 242 249 250 254 259 262 263',
 'env/host': '026 031 068 071 082 095 101 124 241 261 266 271',
 'enforcement/coordination-tools': '044 045 048 058 059 064 108 111 115 119 125 137 139 140 144 145 146 147 151 152 162 163 164 169 170 175 177 178 181 183 187 188 189 191 194 196 200 206 228 232 245 248 252 257 267 275',
 'not-a-failure/feature-ask': '002 013 018 032 033 047 053 060 061 062 070 074 075 079 083 084 087 089 090 093 096 100 104 105 109 118 129 134 142 143 150 167 180 186 198 199 203 218 246 247 265 268 269 270 273',
 'missing-test/logic-bug': '009 028 029 034 043 046 054 067 073 085 092 103 106 110 116 117 126 130 131 156 204 205 209 226',
 'harness/claude-code-limit': '221 240 256 272 274',
 'agent-mistake': '036 041 107 253',
 'product/site-bug': '179 219',
};
const lab = {}; for (const [k, v] of Object.entries(L)) for (const n of v.split(' ')) lab['I-' + n] = k;
const I = JSON.parse(fs.readFileSync(`${V1}/console/incidents.json`));
if (I.some(i => !lab[i.id]) || Object.keys(lab).length !== I.length) throw new Error('label set != incident set');
const A = JSON.parse(fs.readFileSync(`${D}/agents.json`));
const g = {}, row = k => g[k] ??= { n: 0, blocking: 0, dup: 0, open: 0, hrs: [], fixers: 0, fixTurns: 0, fixCR: 0 };
for (const i of I) { const x = row(lab[i.id]); x.n++; x.blocking += !!i.blocking; x.dup += i.resolution === 'duplicate'; x.open += !i.resolvedAt; if (i.resolvedAt) x.hrs.push((Date.parse(i.resolvedAt) - Date.parse(i.openedAt)) / 36e5); }
for (const a of A) { const m = a.who.match(/\/ts-[iI]-?(\d{3})/); const k = m && lab['I-' + m[1]]; if (!k) continue; const x = row(k); x.fixers++; x.fixTurns += a.asst; x.fixCR += a.usage.cacheRead; }
const med = h => h.length ? h.sort((a, b) => a - b)[h.length >> 1].toFixed(1) : '-';
console.log('label | n | % | blocking | duplicate | unresolved | median h to resolve | ts-iNNN fixers | fixer turns | fixer cacheRead');
for (const [k, x] of Object.entries(g).sort((a, b) => b[1].n - a[1].n)) console.log([k, x.n, (100 * x.n / I.length).toFixed(0) + '%', x.blocking, x.dup, x.open, med(x.hrs), x.fixers, x.fixTurns, (x.fixCR / 1e9).toFixed(2) + 'B'].join(' | '));
// phone-touching titles by root-cause bucket (is the phone the cause or only the stage?)
const P = /iphone|phone|wda|usb|simulator|\bsim\b|sim\.mjs|xcode|thermal|ioscap|gesture|inspector|safari/i, ph = {};
for (const i of I) if (P.test(i.title)) { const b = lab[i.id].split('/')[0]; ph[b] = (ph[b] || 0) + 1; }
console.log('phone-touching titles by bucket', ph);
// incidents whose title cites a user thread/step (the user found it), by label
const U = /user [TC]-|\(user|T-\d+ #/, ua = {};
for (const i of I) if (U.test(i.title)) ua[lab[i.id]] = (ua[lab[i.id]] || 0) + 1;
console.log('user-cited titles by label', ua);
```

**Labelling rules I used** (so a reader can contest a label):

- **coupled**: the failure needs two of our own processes, or a test plus the live host, sharing state. This
  includes lock policy bugs, because the policy existed only to share one host.
- **env**: the device or OS misbehaved (env/device or env/host), or our adapter to it mishandled a known device state
  (env/device-driver).
- **enforcement**: a tool whose job is to route, alarm, scrub, lint, guard or show status got it wrong.
- **feature-ask**: the title asks for something that did not exist yet, often citing a user thread.
- **missing-test**: a plain logic bug in measurement or console code that a unit or golden test would have caught.
- **agent-mistake**: an agent did something the rules already forbade (I-036, I-041, I-107, I-253).
- Close calls: I-016 (host overload from parallel suites) went to lock-queue, not env. I-275 (auto-clean deleted
  images) went to enforcement. I-226 (a morph driver that does not exercise the composited morph) went to
  missing-test, though it is also a measurement-validity bug.

## Appendix B. Other one-liners

```sh
# worktree-isolation episodes: refusals, agents, episodes (gap < 2 min), median length, episodes >= 3
node -e 'const E=require("fs").readFileSync("errors.jsonl","utf8").trim().split("\n").map(JSON.parse).filter(e=>/is isolated in the worktree/.test(e.msg));const b={};for(const e of E)(b[e.who]??=[]).push(Date.parse(e.ts));let s=[];for(const v of Object.values(b)){v.sort((x,y)=>x-y);let n=1;for(let i=1;i<=v.length;i++){if(i<v.length&&v[i]-v[i-1]<12e4)n++;else{s.push(n);n=1}}}s.sort((x,y)=>x-y);console.log(E.length,Object.keys(b).length,s.length,s[s.length>>1],s.filter(x=>x>=3).length)'
# -> 3046 358 2299 1 146

# console threads: user messages, reply latency (minutes), unanswered
(cd "$V1"/console/threads && node -e 'const fs=require("fs");let u=0,l=[],na=0;for(const f of fs.readdirSync(".").filter(f=>f.endsWith(".json"))){const m=JSON.parse(fs.readFileSync(f)).messages||[];m.forEach((x,i)=>{if(x.by!=="user")return;u++;const r=m.slice(i+1).find(y=>y.by!=="user");if(!r){na++;return}l.push((Date.parse(r.at)-Date.parse(x.at))/6e4)})}l.sort((a,b)=>a-b);const q=p=>l[Math.floor(p*l.length)].toFixed(1);console.log(u,na,q(.5),q(.9),q(.99))')
# -> 989 4 0.7 2.7 13.1

# toolsmith and manager spend by name prefix
jq -r '.[]|[(.who|sub("^[^/]*/";"")|sub("^lead:.*";"lead")|capture("^(?<p>[a-z]+)").p//"other"),.asst,.usage.cacheRead]|@tsv' agents.json \
  | awk -F'\t' '{n[$1]++;t[$1]+=$2;c[$1]+=$3;C+=$3} END{for(k in n) printf "%-8s n=%d turns=%d cacheRead=%.2fB (%.1f%%)\n",k,n[k],t[k],c[k]/1e9,100*c[k]/C}' | sort -t= -k4 -rn | head
```
