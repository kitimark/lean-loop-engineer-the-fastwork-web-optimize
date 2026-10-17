---
kind: kickoff-note
id: 10-01-v1-console-manual-work
title: "v1 console forensics: how much hand-kept state, and what v2 derives from events"
date: 2026-10-17
status: draft for user review
inputs: v1 repo at eae1bb99 (read-only); v1 live stores `v1:.git/fastwork-mirror/` (read-only); v1 raw transcripts
  (848 jsonl); `.local/v1-chat-digest/out`; kickoff notes 01, 05, 06, 08; docs/plan/PLAN.md rev 3 (not edited)
---

# v1 console forensics: hand-kept state, and what v2 derives from events

**Question.** How much work did v1 agents spend keeping the console up to date by hand? Which of that state could
have been computed from events instead? What must stay a human or agent judgement, and how can that judgement be
one structured command instead of free editing?

**Status words.**
- **MEASURED**: computed by a command given in Appendix A.
- **CONFIRMED**: read in a v1 file (cited as `v1:<path>:<line>`).
- **INFERRED**: a reading or a recommendation.

**Privacy.** No personal data. The user's messages are referred to by thread number and paraphrased, never quoted at
length. Agent names are role names (e.g. `fix-accent-ca`), not people.

**Where things are.**
- `v1:` = `../fastwork-com-web-optimize` (read-only).
- The v1 live stores are in `v1:.git/fastwork-mirror/`. They were never committed. The only committed copy is the
  export `v1:console/` (one commit, 79fc236f, "release: console record export"). So `git log -- console` shows one
  write per file and **cannot** measure manual updates. This note counts the `history` arrays inside the live stores
  instead, plus the tool calls in the transcripts.

> **Verification fixes (2026-10-17).** (1) The "waiting on lead" class was split: only 307 of its writes were land
> requests; about 290 were waits on a lead *ruling*, which is judgement. (2) The ±30 min hold cross-check did not
> separate classes (a judgement-class control matched 75 %), so the 643 "measuring/testing" writes move from
> "already derivable from v1 events" to "derivable with a v2 event" (every v2 measurement is a console-api job).
> The split is now **19 / 37 / 44 %** (was 33 / 29 / 38), so **56 %** of status writes are derivable (was 62 %).
> (3) The scripts are now in `scripts/` (not the session scratchpad), and polls are reported without blocking waits.
> (4) Items that need judgement are no longer called derivable (best build, status auto-reply, thread close,
> hand-back result). (5) Stages follow note 02's evidence-derived model; R/I/D/F/V/L cards become card content.
> (6) Staleness uses the one definition shared with note 02 (λ frozen at stage entry, live waits exempt).

---

## 1. The answer on one page

### 1.1 How much manual work (MEASURED)

**Console upkeep took one tool turn in nine.** Over the v1 run there were 121,286 assistant turns that called a tool.
**13,279 of them (10.9 %) did nothing but console upkeep.** "Console upkeep" here means writing derivable state or
polling a board. Those turns used:
- **2.69 B of 23.3 B context tokens (11.5 %)**;
- 4.96 M of 80.1 M output tokens (6.2 %).

Without the blocking `wait` calls (thread and step waits, which are v1's push mechanism and which v2 keeps as one
inbox wait per agent), the figure is **12,779 turns and 2.59 B context tokens** (MEASURED, `scripts/agg3.py`). An
independent re-implementation from Appendix B during verification got 14,661 of 121,724 turns (12.0 %), the same
order.

**The lead spent the most on it.** For the lead, 5,769 of 18,568 tool turns (31 %) were pure upkeep, and so was 31 %
of its context tokens. The next highest roles:
- mgmt-other: 16 %;
- phone runner: 13 %;
- mgmt-ops: 13 %.

**Status board.** Agents made 4,982 `status.mjs set|priority|seed|sync` calls (Appendix B regex; 4,992 on a re-run
during verification; note 03 counts 4,914 for `set` alone, which is the canonical "set" figure). The store kept 4,412 history entries
on 299 rows:
- 3,437 were written by the row's owner;
- 672 by the lead, for rows other agents owned;
- 303 by other agents and mgmt-ops.

The busiest day was 10-04, with 1,085 writes.

**Of those 4,412 status writes:**

| Group | Writes | Share | What they recorded |
|---|---|---|---|
| Already derivable from events v1 stored | 821 | **19 %** | waiting for Chrome or the phone (lock queue), landed/done (git), waiting on the user, an incident or a review (stores) |
| Derivable once v2 adds one event type | 1,635 | **37 %** | measuring/testing (643; every v2 measurement is a console-api job, `run.started`), waiting on the lead to *land* (307, a `land.requested` record), waiting on an agent (a wait record), row created (spawn), phone-next marks |
| Real judgement | 1,956 | **44 %** | note/next text only (825), waiting on a lead *ruling* (about 290), priority (138), "implementing vs researching vs designing" (385), parked + resume condition (218), dropped/closed (28), misc. |

(The 129 "done (other)" writes stay in the v2-event row: the *fact* of a hand-back is derivable from
`SubagentStop`. Its *result* is still the agent's judgement, captured as one enum, `agent.handback{result}`; see
§3.3. Moving them to judgement would give 19 / 34 / 47 %.)

**Check on the derivable claims (corrected).**
- The first version said 82 % of the "measuring/testing" writes fall within 30 min of a hold that the owner itself
  logged (575 of 701), and concluded that "the event existed and the agent copied it by hand". **That test does not
  separate classes.** The same ±30 min test matches 402 of 537 (75 %) *judgement-class* writes (state researching,
  implementing or designing), and shifting every write by ±2 h still matches 38-44 %. With a strict test (the write
  falls inside the hold, `[acquiredAt, at]`), "measuring" matches **131 of 701 (19 %)**, against 20 of 537 (4 %) for
  the judgement control (MEASURED, `scripts/holds_strict.py`, `scripts/holds_control.py`). So about 80 % of v1
  "measuring" writes were **not** made during a logged hold.
- The 643 measuring writes are derivable **in v2 because of v2's design** (every measurement runs as a console-api
  job and emits `run.started`), not because v1 already had the event. They are counted in the v2-event row above.
- 82 % of the "waiting for Chrome/phone" writes are followed by a hold by that owner within 6 h (344 of 422). This
  check has no control class either, so treat it as weak support only (INFERRED).

**Other hand-kept stores, from their history arrays:**

| Store | Hand-written entries | Notes |
|---|---|---|
| Findings | 1,006 acks, 375 posts, 24 claim changes | the acks were read receipts |
| Incidents | 279 opened, 632 updates, 237 resolved | 460 of the updates were note-only; 203 of the resolutions name a fix commit |
| User steps | 246 runner acks (loading/ready/recording/done), 24 cancels, 7 redo/reopen | |

**Hand-kept ledgers in git, by commit count:**

| File | Commits |
|---|---|
| `ops-handover.md` | 569 |
| `PREDICTIONS.md` | 378 |
| `PROGRESS.json` | 148 (132 of them by mgmt-ops) |
| `BEST_BUILDS.md` | 21 |
| `fixes/<topic>/README.md` | 892 file-commits over 166 topics; 1,841 Edit/Write calls in the transcripts |

**Polling.** Reading the board and its sources took:
- 6,419 `lock.mjs status` calls (3,274 by the lead);
- 2,179 status reads;
- 2,187 thread reads;
- 1,647 incident reads;
- 1,580 `idle.mjs` runs;
- 995 step reads;
- 454 `usage.mjs` runs.

### 1.2 Was it stale? (MEASURED, CONFIRMED)

**Incidents.**
- 8 incidents in v1's own count were "the board shows a stale or wrong state (it needs an agent to write it)"
  [`v1:research/architecture/team-ops-plan.md:23`].
- At least 22 incidents in all were about the board, Progress, the idle alarm or the Agents page (§3.5).

**The user complained repeatedly.** At least 7 user comments said the status was out of date or unclear: T-060 #3,
T-070 #6, T-122 #5, T-124 #3, T-125 #1 and #6, and T-233 #1. Ten incidents name the user thread that triggered them.
The user also opened 31 comment threads on status or Progress rows, with 79 user messages in them.
- In T-122 #5 (10-04) the user asked, in v1, for **exactly the requirement in this note**: the board should be
  updated by tools, not agents, because agent updates cost tokens and go wrong.
- v1's answer was PR-020 and a read-time "an event overrides an older self-report" fix (I-145, I-152). The rows
  themselves were still written by agents.

**Lag behind a user decision.**
- From a proposal decision to the author's next board write: median 3.3 min, p90 18.5 min (56 decisions).
- On 10-04, measured on the owner's next write for proposals and steps together: median 9 min, and 7 of 19 over
  10 min [`v1:research/architecture/team-ops-plan.md:44-55`].

### 1.3 What v2 should do (INFERRED)

- **One rule: agents never write status.** The console-api is the only writer. Every console field is either
  (a) a projection of events that scripts, hooks, git and the user's clicks emit, or (b) one typed judgement
  command whose arguments are enums, ids and at most one short note.
- **Shrink the judgement.** About 56 % of v1's status writes need no agent at all in v2. What is left is the
  judgement part of the other 44 %, shrunk:
  - priority moves to the user's list (PLAN §3.3);
  - "implementing vs researching" disappears as a status: the stage is derived from evidence (note 02 §4.4), and
    research/implementation notes are card content;
  - "parked until X" becomes a typed event predicate.
  - a wait on a lead ruling becomes a typed `decision.requested{card, on: lead, kind}`.
  So only the free `note` remains free text, and the reducer never reads it.
- **Prove the projection in Lean.** Three of its properties are already proved in a scratch file, with no `sorry`,
  using only the axioms `propext` and `Quot.sound` (§6.1):
  - a closed wait stays closed (the I-145 class);
  - self-reports cannot change derived fields;
  - "landed" is sticky.

  §6.2 lists 8 more, each written as a math equation first.

---

## 2. How the v1 console was kept (CONFIRMED)

**Stores.** Each store kept one JSON file per record in `.git/fastwork-mirror/<store>/`, written under a file guard:

| Store | Tool | Who was told to write it |
|---|---|---|
| `status/<id>.json` (299 rows) | `tools/status.mjs set` | every owner, "at every transition, when a wait starts or ends, and on resume" [`v1:CLAUDE.md:383-390`]; before every wait [`v1:CLAUDE.md:455`]; the lead for priority and `sync` after each landing [`v1:tools/status.mjs:66`] |
| `fixes/PROGRESS.json` (committed) | hand edits, later `console.mjs progress set|best` [`v1:tools/console.mjs:89-95`] | mgmt-ops ("keeps fixes/PROGRESS.json current") and the lead |
| `console/C-*.json` (steps) | `console.mjs post|ack|redo|cancel` | the agent that runs the step acks every part: loading, ready, recording, done [`v1:tools/console.mjs:21-57`] |
| `console/threads/T-*.json` | `console.mjs thread reply|assign|merge|close…` | the lead, assignees, the desk |
| `console/proposals/PR-*.json` | `console.mjs proposal post|revise|revising --eta|hold…` | the author; "revising" plus an ETA by hand [`v1:memory/proposal-revision-visible.md`] |
| `findings/F-*.json` | `finding.mjs post|ack|claim|resolve` | any agent; the lead pastes `digest` into `fixes/FINDINGS.md` by hand [`v1:tools/finding.mjs:29-30`] |
| `incidents/I-*.json` | `incident.mjs open|update|resolve` | any agent opens; the lead triages and resolves with `--commit` [`v1:tools/incident.mjs:16-18`] |
| `locks/*` | `lock.mjs` (and `repair --move` by hand) | the agents holding devices; the lead moved the queue by hand |
| `usage/usage.jsonl` | `usage.mjs` on a 30-min cron the lead re-created each session | the lead [`v1:memory/usage-meter-every-30-min.md`] |
| `fixes/BEST_BUILDS.md`, thread T-228 | hand edits | the lead "at every build change" [`v1:memory/best-builds-list.md`] |
| `research/management/ops-handover.md` | hand edits | each mgmt-ops before its handover (about every 2 h) |

**What v1 already derived, at read time only.** The board computed some fields without writing them:
- queue places;
- the lock holder;
- open steps;
- blocking incidents;
- live waits;
- "what it waited on is over: update?" flags [`v1:research/architecture/status-board.md:97-108`];
- later, "landed (from git)" and "owner ended" (I-152).

**The flaw (CONFIRMED in `v1:research/architecture/team-ops-plan.md:94`).** A derived event never *overrode* the
stored self-report. It only added a "may be out of date" flag, so the row kept saying "waiting on you". A design
choice made this worse: "no transition rules are enforced (any state to any state)"
[`v1:research/architecture/status-board.md:74`]. Any write could move a row anywhere, and no checker could tell a
right write from a wrong one.

v1 named the right long-term fix but never built it (CONFIRMED, `team-ops-plan.md:173-174`):
- L1, one append-only event log, with every board as a projection of it;
- L2, one inbox wait per agent.

---

## 3. Measured manual work in detail

### 3.1 Tool calls by category (transcripts, all 848 files; MEASURED)

A Bash call is put in a category by the regexes in Appendix B. One call can fall into more than one. Edit and Write
calls count when their path is a hand-kept ledger.

| Category | Calls | Top roles |
|---|---|---|
| `lock.mjs status` (poll device queues) | 6,419 | lead 3,274 · fix owners 1,079 · toolsmiths 779 · mgmt-ops 374 |
| `status.mjs set/priority/seed/sync` (**write board**) | 4,982 | fix owners 1,712 · toolsmiths 887 · lead 645 · integrators etc. 470 · mgmt-ops 387 |
| thread reply/new/close/merge/assign/escalate | 2,374 | lead 1,885 |
| thread list/show/lint | 2,187 | lead 1,807 |
| status list/show/mine/stale/check/agent(s) | 2,179 | lead 1,555 |
| Edit/Write `fixes/<topic>/README.md` | 1,841 | fix owners 1,547 |
| incident list/show/wait/announce | 1,647 | lead 816 |
| `idle.mjs` | 1,580 | lead 1,252 |
| incident open/update/resolve | 1,026 | lead 535 · toolsmiths 376 |
| step list/show | 995 | lead 780 |
| thread wait | 741 | lead 370 |
| finding list/show/wait/digest | 530 | fix owners 204 |
| finding post/ack/claim/resolve | 506 | fix owners 253 |
| proposal list/show/wait/overdue/talk | 505 | lead 218 · fix owners 161 |
| `usage.mjs` | 454 | lead 433 |
| `console.mjs progress` (read) | 430 | mgmt-ops 275 |
| step wait | 377 | lead 115 · fix owners 104 · phone runner 101 |
| proposal post/revise/revising/hold/… | 355 | fix owners 234 |
| step post/ack/redo/reopen/cancel/answer | 312 | lead 119 · fix owners 76 · phone runner 67 |
| `lock.mjs repair` (hand queue moves etc.) | 271 | lead 248 |
| Edit/Write `ops-handover.md` | 130 | mgmt-ops 124 |
| Edit/Write `CLAUDE.md` / `memory/` | 105 / 52 | lead, toolsmiths |
| Edit/Write `fixes/PROGRESS.json` + `progress set/best` | 57 + 43 | mgmt-ops, toolsmiths, lead |
| Edit/Write `PREDICTIONS.md` | 33 | mgmt-ops, fix owners |

### 3.2 Upkeep turns and their token cost, by role (MEASURED)

**Definitions.**
- "Upkeep turn": an assistant message whose tool calls are all class A or class B. A turn that also did real work is
  not counted, so this is a lower bound.
  - **Class A** = writes of derivable state: status writes, `progress set|best`, Edit of PROGRESS.json or
    ops-handover, step runner acks, `lock.mjs repair`, and the lead's incident updates.
  - **Class B** = polls: board, lock, step, thread, incident, finding, proposal, progress, usage and idle reads,
    plus the `wait` calls.
- "Context tokens" = cache-read plus cache-write input tokens of those turns. This is the dominant cost of a turn on
  a long context.

| Role | Tool turns | Upkeep turns | % of turns | …with a write (A) | Context tokens, upkeep | % of role's context |
|---|---|---|---|---|---|---|
| lead | 18,568 | 5,769 | **31.1 %** | 1,065 | 1,316 M | **30.9 %** |
| fix owners | 37,268 | 2,442 | 6.6 % | 1,015 | 467 M | 6.2 % |
| toolsmiths | 19,156 | 1,719 | 9.0 % | 520 | 304 M | 8.7 % |
| mgmt-ops | 8,112 | 1,042 | 12.8 % | 308 | 175 M | 12.9 % |
| phone runner | 3,761 | 488 | 13.0 % | 181 | 88 M | 12.3 % |
| design engineers | 7,882 | 457 | 5.8 % | 200 | 76 M | 5.7 % |
| integrators | 4,961 | 330 | 6.7 % | 160 | 68 M | 6.4 % |
| architects | 5,326 | 284 | 5.3 % | 108 | 57 M | 4.9 % |
| mgmt-other (desk, devices, clerk) | 1,553 | 253 | 16.3 % | 56 | 43 M | 13.7 % |
| capture/artifact | 3,507 | 236 | 6.7 % | 118 | 49 M | 6.9 % |
| reviewers | 2,855 | 118 | 4.1 % | 76 | 19 M | 4.7 % |
| others | 8,337 | 141 | 1.7 % | 29 | 24 M | 1.8 % |
| **All** | **121,286** | **13,279** | **10.9 %** | **3,836** | **2,687 M** | **11.5 %** |

**Polls without blocking waits** (MEASURED, `scripts/agg3.py`; class W = `console.mjs wait` and `thread wait`):

| Turn kind (all calls upkeep) | Turns | Context tokens |
|---|---|---|
| with a write (A) | 3,836 | 0.74 B |
| polls only (B, no waits) | 9,042 | 1.87 B |
| waits only (W) | 283 | 0.06 B |
| polls and waits (B + W) | 118 | 0.02 B |
| **upkeep without any W turn** | **12,779** | **2.59 B** |

The proposal, finding and incident `wait` subcommands share a category with their reads, so about 180 such waits
are still inside B; this makes B a slight over-count.

**Reading (INFERRED).**
- Writes (class A) are the smaller share: 3,836 turns and 0.74 B context tokens.
- The bigger cost is **polling to find out whether state changed**: 9,042 poll-only turns and 1.87 B context tokens,
  not counting the blocking waits.
- v2 keeps one inbox wait per agent, so the push saving is **polls minus the inbox-wait turns v2 adds**. Using v1's
  own wait turns as the estimate (401 turns, 0.08 B), the saving is about **1.8 B** context tokens, not the 1.94 B the
  first version gave (which counted waits as polls). Both savings come from the same change: one event log with
  projections.
- This fits [08 §1.1]: 42 % of the lead's turns were started by cron fires. v2's "no LLM polling" (PLAN §8.5,
  line 996) is the matching fix.

### 3.3 Status board: who wrote what, and could it be derived (MEASURED)

**What the store holds.** 299 rows and 4,412 history entries:
- actions: `set` 3,908, `created` 292, `priority` 138, `sync` 74;
- 8 rows hit the 100-entry history cap, so the true total is a little higher. The 4,982 Bash calls also include
  refused writes.

**Which fields changed, by key set:**

| Key set | Writes |
|---|---|
| note + state + waitingOn | 870 |
| next + note + state + waitingOn | 729 |
| note + state | 614 |
| next + note | 453 |
| note | 368 |
| next + note + waitingOn | 305 |

**`waitingOn` values written:**

| Value | Writes |
|---|---|
| cleared (`none`) | 779 |
| `lead` | 599 |
| `chrome` | 328 |
| `agent` | 255 |
| `user` | 112 |
| `phone` | 94 |
| `incident` | 26 |
| `other` | 23 |
| `review` | 10 |
| `item` | 2 |

**Classification.** Each write was assigned to the first matching rule (script in Appendix A, step 3):

| Class | Writes | Share | Event that makes it derivable |
|---|---|---|---|
| note/next only | 825 | 18.7 % | none: judgement text |
| state → measuring/testing | 643 | 14.6 % | v2's `run.started` / `run.finished` (every measurement is a console-api job). v1's `locks/holds.log` (4,005 holds) does **not** cover them: only 131 of 701 writes fall inside a logged hold (§1.1) |
| waiting on lead: land request | ≈ 307 | ≈ 7.0 % | a `land.requested` record (v1 sent land requests as messages; 47 % of mgmt→lead messages were land requests [08 §1.1]) |
| waiting on lead: ruling | ≈ 290 | ≈ 6.6 % | **judgement**: a typed `decision.requested{card, on: lead, kind}` command. MEASURED split of the 599 `waitingOn.kind == lead` values: land 307, decision 38, review 28, other 226 (rulings, go-aheads, sign-offs, "after p-153", "npm test" …). Command: `jq -rs '[.[].history[]\|.changes.waitingOn?\|select(type=="object" and .kind=="lead")\|(.text//""\|ascii_downcase\|if test("land") then "land" elif test("review") then "review" elif test("decision\|decide\|approv\|go-ahead\|pick\|choose\|direction\|which") then "decision" else "other" end)]\|group_by(.)\|map("\(.[0]) \(length)")\|.[]' $M/status/*.json` (599 values; the first-match classifier assigns 596 of them to this class) |
| waiting on Chrome/phone | 415 | 9.4 % | `queue.entered` / `queue.granted` |
| row created | 292 | 6.6 % | `agent.spawned` with its card id (kind and owner); the title once |
| waiting on an agent | 243 | 5.5 % | a `wait.started{on: agent}` record (v1 had one for `wait.mjs --reason`) |
| landed/done (sync or lead) | 236 | 5.3 % | `git.landed` (commit on main touching the card) |
| parked | 218 | 4.9 % | judgement; the resume condition can be typed (§5) |
| state implementing/researching/designing/reviewing/… | 385 | 8.7 % | judgement in v1; the card stage in v2 |
| waiting on user/incident/item/review | 146 | 3.3 % | `step.posted` / `proposal.posted` / `incident.opened{blocking}` |
| priority (lead) | 138 | 3.1 % | v2: the user's priority list, not an agent |
| done (other) | 129 | 2.9 % | the *fact* comes from `agent.handback`; the *result* is the agent's judgement: `agent.handback{result: landed\|no-gain\|refuted\|blocked}` (typed) |
| misc (phoneNext, unlink, owner/title edits, terminal states) | about 100 | 2.3 % | mostly derivable (phone-next = the head of the device job queue) |

**Totals (corrected).**
- 18.6 % derivable from v1 events (was 33.2 %: the 643 measuring writes moved, see §1.1);
- 37.1 % derivable with one new v2 event type (was 29.1 %: + 643 measuring, − about 290 lead rulings);
- 44.3 % judgement (was 37.8 %: + about 290 lead rulings).

Before the hold correction (only the lead split applied) the split was about 33 / 22 / 45 %.

### 3.4 Other stores and ledgers (MEASURED)

**Steps.** 172 steps, 920 history entries:
- user: 215 starts, 182 dones, 47 answers;
- agents: 172 posts and **246 runner acks**: loading 74, ready 90, recording 74, done 8.

The acks were a protocol that the agent running the recorder kept up by hand. Its failures were I-059, I-122,
I-123, I-140 and I-143 (class 3, "user step stuck on its runner",
[`v1:research/architecture/team-ops-plan.md:25`]). In v2 the recorder process emits `ready` and `recording` itself.

**Findings.** 375 posted, **1,006 acks**, 24 claim changes, and the lead folded the findings into `FINDINGS.md` by
hand (12 commits). The acks are read receipts. v2 can drop them, or derive "read by X" from a knowledge-base read
event.

**Incidents.** 279 incidents:
- 632 `update` entries, 460 of them note-only ("repro started" and the like);
- the rest set priority, status, assignee or workaround;
- 237 resolved, 203 of them as `fixed` with a commit.

`resolve --commit` was a hand copy of something git already knew. A `Fixes: I-NNN` commit trailer derives it.

**Proposals.** 218 history entries:
- decided 64, revised 52, proposed 30, **revising 29** (a hand "revision in progress" plus ETA), drafted 11,
  published 8, live 7, held/unheld 10, other 7.

**Threads.**
- 1,009 user messages, 1,775 lead messages, 372 other-agent messages.
- 104 user messages (10 %) match a status/catch-up regex. [08] gets 132 with a wider regex; use 132 as the upper
  figure.
- Those questions are answerable from a projection without an LLM, which is PLAN §8.5's "console first response to
  status questions".

**Ledgers in git (commits).** Every one of these duplicated state that events or stores already held:
- `ops-handover.md`: 569, the "who waits on what" table written by hand;
- `PREDICTIONS.md`: 378;
- `PROGRESS.json`: 148;
- `CLAUDE.md`: 99;
- `fixes/DIRECTION.md`: 51;
- `memory/`: 50;
- `AGENT_ROLES.md`: 36;
- `LEAD.md`: 35;
- `BEST_BUILDS.md`: 21.

The exceptions are the judgement parts: predictions and the direction text.

### 3.5 Staleness and user complaints (MEASURED, CONFIRMED)

**Incidents about the board or the views derived from it** (titles paraphrased):
- **Stale or wrong row**:
  - I-044: an owner could not clear a derived "blocked by" line;
  - I-108: a listener shown as "waiting for a user reply";
  - I-145: "waiting on you" 16 min after the decision;
  - I-162: a "researching" row whose fix had landed;
  - I-183: a lead-only incident shown as blocking every lead row;
  - I-248: "owner ended" on a live detached runner.
- **Missing information**:
  - I-048: shared-lane readers invisible;
  - I-058: waits invisible (user T-016);
  - I-060: no job shown for the device holder (T-020);
  - I-104: no link between Status and Progress (T-057);
  - I-118: no per-agent view (T-074);
  - I-156: only the latest comment could be reached (T-137);
  - I-177: a revision in progress was invisible;
  - I-187 and I-188: the Mac lane shown as "free" while stalled (T-165);
  - I-265: team agents missing from the Agents page.
- **Wrong Progress or best-build data**: I-116, an empty table cell read as a result.
- **The idle alarm reading stale self-reports**: I-105, I-111, I-125, I-144, I-155 and I-196.

**v1's view of the cause.** The team-ops plan itself concluded that rows 1-3 of its slip table "have the same cause:
a fact the tools already store … reaches the board … only when an agent rereads it and writes it down"
[`v1:research/architecture/team-ops-plan.md:36-37`].

**User comments about stale or unclear status** (paraphrased):

| Thread | What the user said |
|---|---|
| T-060 #3 | many statuses are out of date |
| T-070 #6 | remove the outdated "waiting for user" statuses, they confuse |
| T-122 #5 | the tools should update this, not agents |
| T-124 #3 | cannot tell in-progress from done |
| T-125 #1, #6 | asked twice whether a "parked" item was done |
| T-233 #1 | "I did my part, why does the status not change?" |

The user also opened 31 comment threads on status or Progress rows (79 user messages), and the best-build thread
T-228 had 24 user messages. The best-build list was kept by hand after the user asked on 10-07 whether it was up to
date [`v1:memory/best-builds-list.md`].

**Lag behind the user** (MEASURED, Appendix A, step 5):
- from a proposal decision to the author's next board write: median 3.3 min, p90 18.5 min (56 decisions);
- for step answers: a median of 362 min (42 answers). This number mostly measures runners that never kept a row,
  so it is not a clean lag.

---

## 4. Catalog: every console item → v1 writer → real source → v2 derivation → remaining judgement

**Event names.** These are proposals for `events.jsonl` in console-api (PLAN §3, line 229). "Judgement command" is
the one typed command that captures what an event cannot know.

**Rules for every row of this catalog (INFERRED):**
1. The console-api is the only writer.
2. Agents never edit a store or ledger file.
3. A judgement command takes enums and ids, plus at most one note of 200 characters or less.
4. A later event always beats an earlier judgement on a derived field. This is proved as `close_wins` and
   `says_inert` in §6.1.

### 4.1 Status rows ("the board")

| Item | v1: who updated it | Real source of truth | v2: derived from (event) | What stays judgement → command |
|---|---|---|---|---|
| Row exists, id, kind, owner | owner `status.mjs set` (first call: `--kind --title`), 292 creates | the spawn (the lead names agent + card) | `agent.spawned{name, card, role}`; the row id = card id | none |
| Title | owner, once (plus 4 retitles) | the card's title | `card.created{title}` | the title, once, in `fw card new` |
| Stage (v1 "state": researching/designing/implementing/…) | owner at every transition (385 judgement writes) plus PROGRESS `stage` R-L by mgmt-ops | evidence keyed by commit (note 02 §4.4: question → build → screen → review → device → landReady → land) | **derived, no command**: `stage(c)` from `approved`, `built`, `screened`, `reviewed`, `swiped`, `landed` events (Lean `stage`, note 02). The R/I/D/F/V/L sections of the sketch's `Stage.lean` become **card content** (sections of `card.md`, e.g. the named cause for D), not stage transitions | none for the stage itself. The judgements inside it are typed commands that already exist: the lead's `approve`, the reviewer's verdict, the lead's land request |
| measuring / testing (activity) | owner (643) | lock holds (`holds.log`), test runs | `run.started/finished{card, lane}`, `test.run{card}` | none |
| Waiting: Chrome / phone / Mac lane | owner (415) | the lock queue | `queue.entered/granted{job, card}`; shown as "#2 in line", ETA = Σ median duration of the jobs ahead | none |
| Waiting: user | owner (112) plus I-145 lag | open step or proposal | `step.posted{card}` → needs-you; `step.answered/skipped` / `proposal.decided` closes it | none (`needs-you` is set only by these events, PLAN line 267) |
| Waiting: lead (land request) | owner (≈ 307) | a message to the lead | derived: the card's stage is `landReady`, which is the lead's move; the lead's `land.request` (refused unless ready) and then the git `landed` fact close it | none for the owner; the lead's land request is catalogue row 11 |
| Waiting: lead (ruling) | owner (≈ 290) | a message to the lead | `decision.requested{card, on: lead, kind}` → `decision.answered` closes it | **yes**: asking for a ruling is the judgement; `kind` is an enum (`go-ahead\|pick\|sign-off\|other`) |
| Waiting: agent X | owner (243) | a message or a `wait.mjs --reason` | `wait.started{by, on: agent, card}` / `wait.ended` from `fw wait` | why: an enum `answer|review|artifact` plus an id |
| Waiting: incident | derived, plus a self-report | incident store | `incident.opened{blocking, affects: card}` / `incident.resolved` | none |
| Waiting: review | owner | the reviewer's verdict | derived: the card's stage is `review` | the verdict: `fw review <card> --sha --accept\|--reject` (reviewer; refused if the reviewer owns or built the card) |
| Note / next | owner (825 note-only, plus most other writes) | the agent's head | — | **yes**: `fw note <card> "<≤200 chars>"` (optional; age shown; never changes a derived field) |
| Priority | lead (138) | the user's wishes | `priority.set` from the user's list (PLAN §3.3) | the user's drag in the console; agents cannot set it |
| Parked + resume-on | owner (218 + resumeOn) | the agent's choice | `card.parked{until: <event predicate>}`; "ready to resume" = the predicate holds on the log | **yes**: `fw park <card> --until incident:I-7|land:<card>|decision:PR-3|after:<time>|never` (typed only) |
| Landed / done / dropped / closed-no-fix | lead `sync` (74), owners, lead (236) | git main; the agent's hand-back | `git.landed` (L) · the hand-back *fact* from `SubagentStop` | the hand-back *result* is a typed judgement: `agent.handback{result: landed\|no-gain\|refuted\|blocked}`; dropping: `fw drop <card> --reason superseded\|no-gain\|refuted\|user` |
| Owner alive / ended | read time from transcripts (I-152, I-248, I-265) | Claude Code session state | `agent.handback` / `agent.stopped` from a `SubagentStop` hook; `agent.stalled` from the stall watcher | none |
| Phone-next / startable (I-182) | owner `--phone-next --phone-needs --arm-neutral` | the device job queue | the head of the device job queue (agents never hold the phone, PLAN line 266) | none |
| "Stale" flag | `status.mjs stale` (45 min, 2 h rules) | the age of the last event | stale(c,t) ⟺ t − last(c) ≥ λ_c ∧ liveWaits(c) = ∅, with λ_c frozen at stage entry (T6; the same definition as note 02 §4.4) | none |
| ETA | proposals only (`revising --eta`); PROGRESS `upcoming.when` by hand | the queue and the run history | queue ETA = Σ medians of the jobs ahead; stage ETA = median stage duration for this card class (shown as "typical") | an optional `--eta` on `fw note`, shown with its age and never used by the scheduler |
| Steps on the row ("needs you") | derived in v1 too | step store | `step.*` | none |

### 4.2 Fix progress, versions, best builds

| Item | v1: who updated it | Real source | v2: derived from | Judgement → command |
|---|---|---|---|---|
| PROGRESS item state / stage / owner | mgmt-ops by hand (148 commits), `progress set` (43) | cards, git | the card projection (§4.1) | none |
| Item "why" / writeup / title | mgmt-ops | the card | `card.created`, card body | the card text (in a file, reviewed by its commit) |
| Item "felt" (the user's finger verdict) | mgmt-ops copied it from step answers | step answers | `step.answered{card, value}` (blind A/B result) | none: it is the user's click |
| Item "gate" / "checks" | mgmt-ops | gate scripts, verdicts | `gate.passed/failed{card, gate}`, `verdict.computed` (Lean `Verdict`) | none |
| Version "improvement / cost / verdict" | mgmt-ops, lead | run artifacts | `verdict.computed{version, screen}` from `fwcore` | none |
| Version hashes, Try-it | mgmt-ops | build artifacts | `build.created{version, hashes}`, `tryit.served` | none |
| Best build (`progress best`, `BEST_BUILDS.md`, thread T-228) | lead by hand, "at every build change" | landed versions + verdicts + the user's felt verdicts | **derived candidate set**: the maximal elements among landed versions that were compared head to head (T7). The non-overlap verdict is pairwise and per screen, not a total order and not even transitive across run sets, so there is no argmax. v1's list also carried the user's felt verdicts (T-228, 24 user messages) | **yes, when the set has more than one member**: the user picks (`best.pick{version}`); with one member nothing is asked |
| `changes[]` (30 recent changes) | hand `changes[^]` | the event log | the last N meaningful events (stage closed, landed, decided) | none |
| `upcoming[]` | hand | queues, parked predicates | the queue head and parked cards whose predicate is close | none |
| `complaints[]`, `goal` | lead | the user | user threads / plan | the user, or a plan edit |

### 4.3 User steps

| Item | v1 | Real source | v2: derived from | Judgement → command |
|---|---|---|---|---|
| Step posted | agent `post` | the need for a device/finger action | `fw device check` and the job queue post it themselves (PLAN line 321: one get-ready step per session) | a perception A/B: `fw step ab <card> --arms A,B` (typed); free questions go to a thread |
| Part loading / ready / recording / done (246 acks) | the runner by hand, with attempt and epoch rules (I-140) | the recorder and runner processes | `recorder.ready`, `recorder.recording`, `recorder.stopped` from the job runner inside console-api | none |
| Redo / cancel / reopen | agent | the user's "start over" or a failed run | `run.failed` → automatic redo with a retry cap; the user's "start over" click | cancel: `fw step cancel <id> --reason no-longer-needed|superseded` |
| Answer | user click (or the lead's `answer` for a chat reply) | the user | `step.answered` | none |

### 4.4 Threads

| Item | v1 | Real source | v2: derived from | Judgement → command |
|---|---|---|---|---|
| Who answers (routing, desk, topic map, listening) | lead `assign`, `desk set`, `topic set`; router heuristics (I-137) | the owner of the anchored item | `thread.created{anchor}` → anchor owner; listening = a live inbox wait (`wait.started{kind: inbox}`) | `thread assign` stays a lead command, rarely needed |
| First reply to a status/catch-up question (104-132 messages) | the lead, by hand | the projection | the *reply text* is rendered from the projection (no LLM) | **recognising** a status question is a classification, so it is judgement (this note's two regexes already disagree: 104 vs 132). The classifier only *suggests* "answer from the board"; the user's "not answered" click escalates to the lead |
| Reply text | lead / assignee (`thread reply`, lint) | the agent | — | **yes**: the reply (lint kept) |
| Close / merge | lead or assignee | the conversation | a close is *suggested* after a reply plus N h without a new user message | **whether the reply answered the question is judgement**: the user clicks "answered" / "not answered", or the assignee runs `thread.close --reason answered\|duplicate\|moved`. Merge stays a command |
| Unread / badge | derived | store | derived | none |

### 4.5 Proposals

| Item | v1 | Real source | v2: derived from | Judgement → command |
|---|---|---|---|---|
| Post / revise | author | the PoC | `fw proposal post` (Try-it required, I-109 rule) | **yes**: the proposal content |
| "Revising, rev N+1 in progress, ETA" (29 + I-177) | author by hand | the author's commits on the proposal branch | `proposal.changes_requested` → "revising since t" until `proposal.revised`; activity = commits on the branch | an optional ETA through `fw note` |
| Live / phone pages (publish, live, phone) | author | Try-it server | `tryit.served{proposal, option}` started by `proposal post` | none |
| Decision, stale decision, hold | user / lead | the user's click | `proposal.decided`; a revision after a decision → `decision.stale` (projection) | hold: `fw proposal hold <id> --reason correcting` |

### 4.6 Findings / knowledge

| Item | v1 | Real source | v2: derived from | Judgement → command |
|---|---|---|---|---|
| Post | agent | the agent's discovery | — | **yes**: `fw kb add --kind note|decision|ref|rule --claim <status> --cite …` (PLAN: 4 kinds, 5 claim statuses) |
| Ack (1,006) | every agent, by hand | whether the agent read it | `kb.read{by, id}` from the kb read command, or nothing (drop acks) | none |
| Claim status change | any agent | evidence | — | **yes**: `fw kb claim <id> --status refuted --cite …` (cite required) |
| Fold into FINDINGS.md (digest pasted by hand) | lead | the kb | no ledger file; the kb index is generated | none |

### 4.7 Incidents / bug ledger

| Item | v1 | Real source | v2: derived from | Judgement → command |
|---|---|---|---|---|
| Open | agents (279) | a tool failure | adapters open it themselves on a known exit code or signature (`incident.opened{sig}`, dedup by sig, the I-128 ×4 case) | a novel bug: `fw bug open --kind request|incident --title … --sig …` |
| Note-only updates (460) | lead / fixer | branch activity | commits on the `ts-I-NNN` branch, test runs | none |
| Triage: priority, assignee, blocking | lead | impact | priority = f(blocking, affected cards, class): a tested function; assignee = the spawned fixer (`agent.spawned{incident}`) | override: `fw bug triage <id> --priority P1` (rare) |
| Resolve (237; 203 with a commit) | lead `resolve --commit` | git | `git.landed` with a `Fixes: I-NNN` trailer | non-code resolutions: `fw bug close <id> --resolution workaround|not-a-bug|duplicate:<id>` |
| "Proof would have caught it" tag (V-l) | — | review | — | **yes**, one enum at close (PLAN V-l) |

### 4.8 Devices, queues, usage, agents

| Item | v1 | Real source | v2: derived from | Judgement → command |
|---|---|---|---|---|
| Device holder / queue (6,419 status polls) | lock tool, agents | console-api queue | the queue projection; SSE push | none |
| Queue order (≈230 hand moves, 271 `repair` calls) | lead | the user's priority + class | order = a tested function of the priority list (PLAN §3.3; Lease.lean) | a manual move = `fw queue move <job> --before <job> --reason …` (logged event) |
| Device health (link, WDA, lock, thermal) | agents and the lead on cron (1,889 "check iphone connection" fires [08]) | usbmux/WDA/thermal probes | device watcher events (PLAN line 996) | none |
| Idle alarm (1,580 `idle.mjs` runs) | lead cron | queue + holds | the projection: free lane ∧ startable job queued for > τ | none |
| Usage (454 `usage.mjs`, T-010 with 223 messages) | lead cron, re-created each session | transcripts | a usage meter script or hook | none |
| Agents page / who is alive | read time from transcripts | the harness | `agent.*` hook events | none |

### 4.9 Hand-kept ledgers

| Ledger | v1 commits | v2 |
|---|---|---|
| `ops-handover.md` (who waits on what, living state) | 569 | gone: the projection answers "who waits on what"; per-agent handoff notes for judgement (PLAN line 723) |
| `PREDICTIONS.md` | 378 | predictions live in each `card.md` (PLAN line 170) and are written once, before data |
| `PROGRESS.json` | 148 | generated view (§4.2) |
| `BEST_BUILDS.md` | 21 | generated (T7) |
| `fixes/<topic>/README.md` | 892 file-commits | the card file. Its stage and status lines are generated; only the narrative is hand-written |

---

## 5. The judgement commands that remain: the merged catalogue (INFERRED)

This is **the one catalogue** for rev 5. It merges this note's list with note 02 §5 (user commands, review,
approve, jobs) and note 03's `note` events. Everything an agent or the user still decides is a typed command; each
appends exactly one event, which the Lean reducer can refuse. Free text is limited to the `note` argument, which is
**shown but never read by the reducer** (proved inert: `says_inert`, `note_preserves_needsYou`).

| # | Command (event) | Who | Arguments (typed) | Refused when | Replaces in v1 |
|---|---|---|---|---|---|
| 1 | `step.answer` | user | step id; answer per kind (yes/no, choice, swipe `A\|B\|same`, rating) | step closed; actor ≠ user | step answers |
| 2 | `step.cancel` | user (script for its own steps) | step id, reason enum | step closed | runner cancels |
| 3 | `proposal.decide` | user | proposal, option, optional comment | closed; unknown option | proposal decisions |
| 4 | `priority.set` | user | ordered card ids | not a permutation of open cards | 138 lead priority writes |
| 5 | `session.book` | user | from, to, lanes | overlap; in the past | device chores |
| 6 | `decision.answer` | user (lead for `on: lead`) | question id, choice | unknown; already answered | thread replies, lead rulings |
| 7 | `best.pick` | user | version id | not in the derived candidate set | the hand-kept best-build list |
| 8 | thread post / "answered" / "not answered" | user | text; click | — (conversation, not state) | — |
| 9 | `card.open` (`fw card new <id> --title --class --part`) | owner or lead | ids, enums | id exists; part unknown | status create, PROGRESS item |
| 10 | `card.approve` | lead (user may) | card | no registered prediction; already approved | "lead approves" in chat |
| 11 | `land.request` (`fw land <card>`) | lead (user may) | card, sha | not land-ready | `waiting-on lead: land`, `status.mjs sync` |
| 12 | `card.drop` (`fw drop <card> --reason`) | lead or owner | enum `superseded\|no-gain\|refuted\|user` | already landed | dropped, closed-no-fix |
| 13 | `card.park` (`fw park <card> --until <predicate>`) | owner | typed predicate `incident:I-7\|land:<card>\|decision:<id>\|after:<time>\|never` | malformed predicate | parked + resumeOn (218) |
| 14 | `wait.started` (`fw wait <card> --on agent:<x> --for answer\|review\|artifact`) | owner | ids, enum | unknown agent | `waiting-on agent:` (255) |
| 15 | `decision.requested` (`fw ask-lead <card> --kind go-ahead\|pick\|sign-off\|other`) | owner | card, enum | — | `waiting-on lead:` rulings (≈ 290) |
| 16 | `agent.handback` result | owner | `landed\|no-gain\|refuted\|blocked` | — | done (other) 129 |
| 17 | `review.verdict` (`fw review <card> --sha --accept\|--reject --reasons`) | reviewer | sha, bool, reason enums | sha ≠ head; reviewer owns or built the card | reviewing rows, V-cards |
| 18 | `job.request` (`fw screen\|gate\|run\|device`) | any agent | kind, card | unknown card; stage forbids it | lock queues, "waiting on chrome" |
| 19 | `note` (`fw note <card> "<≤200>"`) | owner | one short text (an ETA, if any, goes here and is shown with its age) | longer than 200 chars | `--note`, `--next`, `revising --eta` |
| 20 | `kb.add` / `kb.claim` | any agent | kind, claim status, cites | no cite on a claim change | finding post/claim |
| 21 | `bug.open` / `bug.triage` / `bug.close` | any / lead | sig, enums | — | incident open/update/resolve without a commit |
| 22 | `queue.move` | lead | job ids, reason enum | — | `lock.mjs repair --move` |
| 23 | `thread.close` | assignee | reason `answered\|duplicate\|moved` | — | lead thread closes |

Rows 1-8 are yours (console-web only), 9-12 the lead's, 13-19 owners' and reviewers', 20-23 shared tools. Note 02
§5 refers to this table.

**Agent duty is down to one command per real decision.** v1 had about 13 status writes per row on average (4,412 /
299). A v2 row should see:
- 1 card open, 1 approve, 1 review verdict, 1 land request;
- the occasional park, wait or lead question;
- a few optional notes.

So about 5-8 writes, each one a decision no event could make (INFERRED). Stage changes themselves need no command.

---

## 6. What to prove in Lean, written as math first

**Notation.**
- L = ⟨e₁, …, eₙ⟩ is the event log. It is append-only. L·e means "L with e appended".
- S(L) is the console state computed from it: S(⟨⟩) = S₀ and S(L·e) = step(S(L), e). In Lean this is
  `project r log = log.foldl step r`.
- So **the state is a function of the log alone.** Two replays of the same log give the same board. This holds by
  construction.

### 6.1 Proved now (scratch, compiled, no `sorry`)

**File.** `research/kickoff/10-automation-and-proof/lean-scratch/01-v1console/RowProjection.lean`
- Lean 4.35.0;
- checked with `~/.elan/bin/lean RowProjection.lean` (exit 0);
- `#print axioms` shows only `propext` and `Quot.sound`.

The model: a row has `waits` (a set of open wait ids), `phase ∈ {open, measuring, landed}` and `note`. The events
are `waitOpen w`, `waitClose w`, `holdStart`, `holdEnd`, `landed` and `say note`.

| # | Math | In words | Lean name | v1 incidents it rules out |
|---|---|---|---|---|
| T1 | L = A · close(w) · B ∧ open(w) ∉ B ⟹ w ∉ waits(S(L)) | once the event that ends a wait is logged, the wait is gone, whatever comes after, unless the wait is opened again | `Fw.Row.close_wins` (from `stays_closed`) | I-145, I-108, I-044, T-233, T-070 — **provided** every decision emits its close event. That is an IO-completeness premise (L3), checked by an adapter test ("every decision emits `waitClose`"), not by this theorem |
| T2 | B ∈ Say* ⟹ waits(S(A·B)) = waits(S(A)) ∧ phase(S(A·B)) = phase(S(A)) | self-reports (notes) cannot change any derived field | `Fw.Row.says_inert` | the whole "agent wrote a wrong state" class (I-162, T-124, T-125) |
| T3 | landed ∈ L ⟹ phase(S(L)) = landed | once landed, always landed; a later hold or note cannot move it back | `Fw.Row.landed_sticky` (from `landed_stays`) | I-162 (researching on a landed item), T-125 (parked vs done) |

### 6.2 Proposed for the v2 Lean scope (not yet written)

Each property is stated in math, with a suggested Lean name and module. The modules extend PLAN's
`Fw/Spec/{Stage,Lease,Verdict}.lean`.

| # | Math | In words | Suggested Lean |
|---|---|---|---|
| T4 | needsYou(r, L) ⟺ ∃ s: owner(s) = r ∧ posted(s) ∈ L ∧ closed(s) ∉ L | "needs you" is shown exactly when an open step or proposal exists, and never otherwise (PLAN line 267) | `Fw.Console.needsYou_iff` |
| T5 | stage(c) is note 02's evidence function, and built(c, sha) ⟹ stage(c′) = screen for an approved, unlanded card | the stage is derived from evidence; a rebuild sends the card back to screen (MEASURED: `built_resets` in `lean-scratch/02-events/ConsoleV2.lean`). Still to prove: no event skips forward, i.e. the stage advances only on its own evidence | `Fw.Console.built_resets` (proved), `Fw.Console.stage_own_evidence` (to do) |
| T6 | stale(c, t) ⟺ t − last(c) ≥ λ_c ∧ liveWaits(c) = ∅, with λ_c frozen when c entered its stage; so liveWaits(c) ≠ ∅ ⟹ ¬stale(c, t), and t ≤ t′ ∧ stale(c, t) ⟹ stale(c, t′) | a row in a live queue or wait is never called stale (v1's lead rule, `status-board.md` §5), and a stale row stays stale until an event touches it | `Fw.Console.stale_live`, `stale_mono` (both proved in `ConsoleV2.lean`) |
| T7 | Best(L) = { v ∈ Landed(L) : ¬∃ w ∈ Landed(L), w compared with v head to head ∧ w ≻ v } | the best-build *candidates* are the landed versions that no head-to-head comparison beats; when there is more than one, the user picks | `Fw.Verdict.best_is_maximal` |
| T8 | resolved(i, L) ⟺ ∃ c ∈ mainCommits(L): Fixes(i) ∈ trailers(c) ∨ close(i, r) ∈ L | an incident is resolved by its fixing commit, or by a typed close | `Fw.Bugs.resolved_iff` |
| T9 | ready(r, L) ⟺ parked(r, P) ∈ L ∧ ∃ e after it in L: P(e) | "ready to resume" holds exactly when the typed predicate fired after parking | `Fw.Console.resume_iff` |
| T10 | route(m) = first listening x in ⟨anchorOwner, topicOwner, cardOwner, lead⟩ | the router is a total function. The lead is the fallback, so a message is never routed to nobody | `Fw.Console.route_total` |
| T11 | ∀ e ∈ L: writer(e) = consoleApi ∧ (kind(e) ∈ Judgement ⟹ fields(e) ⊆ Enums ∪ Ids ∪ {note≤200}) | one writer; judgement events carry only typed fields | a type-level invariant (`Ev` constructors), checked by construction |

**Keeping math and Lean in sync.** Every theorem in `Fw/` gets a doc comment with its math (as in the table
above). The pipeline is note 04's: `lake exe mathview` exports each declaration with a deep statement hash (the
statement plus the bodies of every `Fw` definition it reaches), and CI fails when the hash differs from the one in
the reviewer-owned sign-off file. See `README.md` §3 in this folder.

---

## 7. Implications for the plan (for whoever writes PLAN rev 4; this note does not edit PLAN.md)

1. **One writer, one event log, projections.** This is already in PLAN rev 3 (lines 165, 229, 995). This note adds
   the evidence for it:
   - 56 % of v1 status writes are derivable (19 % from events v1 had, 37 % with one new v2 event);
   - 31 % of the lead's turns were upkeep;
   - 2.7 B context tokens went on upkeep.
2. **Add the event types v1 lacked.** v1 lacked `land.requested`, `wait.started/ended{on}`, `agent.spawned{card}`,
   `agent.handback`, `recorder.ready/recording`, `proposal.changes_requested`, and a `Fixes: I-NNN` trailer
   convention. Without them 29 % of the v1 writes stay manual.
3. **Ban hand edits by tool, not by rule.** A PreToolUse hook should deny Edit/Write on generated views (the
   PROGRESS-like JSON, board, best builds, handover) and on `events.jsonl`. v1 shows that rules kept only in memory
   slip [`v1:research/architecture/team-ops-plan.md:32`, class 10].
4. **Make polling unnecessary.** One inbox wait per agent on the event log (v1's L2). The B-class turns (polls)
   cost more than the writes did.
5. **Widen the Lean scope** to T1-T11. All of them are small and decidable, and they are the logic behind every
   staleness incident above. The adapter (reading git, transcripts, devices) stays tested, not proved; T1's
   "every decision emits its close event" is one of those adapter premises.

---

## 8. Limits

- **Roles** come from agent-name prefixes (`fix-`, `ts-`, `mgmt-ops`, …). 4,892 turns come from unnamed agents. Two
  sessions' lead turns are counted as "lead".
- **Upkeep turns** are a lower bound: a turn that mixed upkeep with real work is not counted. The **context tokens**
  are the turn's whole context, not a marginal cost.
- **The derivability classes** use the first matching rule. A write that changed a wait *and* a note counts as
  derivable, because the event triggered it. Its note is judgement text that v2 would capture with `fw note`.
- The status store keeps the last 100 history entries per row; 8 rows reached the cap.
- Regex-based user-message counts (104 here, 132 in [08]) are approximate.

---

## Appendix A: commands to reproduce

All of these are read-only. `V1=../fastwork-com-web-optimize`, `M=$V1/.git/fastwork-mirror`,
`D=.local/v1-chat-digest/out`.

The scripts are committed in `research/kickoff/10-automation-and-proof/scripts/` (see its `README.txt`). They read
local data and print counts only. Appendix B holds the scanner's regexes.

1. **Transcript scan (§3.1, §3.2).** Run
   `python3 -I scan.py <v1 transcripts dir> $D/agents.json calls.jsonl`.
   - It writes one line per assistant message that has tool calls: role, output tokens (the max over the streamed
     lines of that message id), cache-read and cache-write tokens, and the categories of each call.
   - Then `agg.py` counts the categories by role, `agg2.py` computes the class A/B upkeep turns (definitions in
     §3.2), and `agg3.py calls.jsonl` splits out the blocking waits (class W).
2. **Status history (§3.3).** For every `$M/status/*.json`, iterate over `history[]`. Count `action`, `by` (equal
   to the owner or an alias → owner; `lead`; `mgmt*`) and `sorted(changes.keys())`. Classify with the first-match
   rules in the §3.3 table.
3. **Hold cross-check.** Parse `$M/locks/holds.log` (one JSON per line: `owner`, `acquiredAt`, `at`).
   - For each status write with `state ∈ {measuring, testing}`, check for an owner/id/alias hold where
     acquiredAt − 30 min ≤ t ≤ at + 30 min. Result: 575 of 701.
   - For each wait of kind chrome or phone, check for a hold acquired in [t, t + 6 h]. Result: 344 of 422.
   - Control and strict tests: `python3 -I scripts/holds_control.py $M` (the same ±30 min test on judgement-class
     writes: 402 of 537; ±2 h shifts: 38-44 %) and `python3 -I scripts/holds_strict.py $M` (write inside the hold:
     131 of 701 measuring, 20 of 537 judgement).
4. **Other stores (§3.4).** Count `history[].action` in `$M/incidents/I-*.json`, `$M/findings/F-*.json`,
   `$M/console/C-*.json` (`who`, `action`, `state`) and `$M/console/proposals/PR-*.json`. Count thread messages by
   `by` in `$M/console/threads/T-*.json`.
5. **Lag (§1.2, §3.5).** For each `history` entry with `action == decided` in a proposal, find the first status
   write by the proposal's `by` at or after it, then take the median and p90.
6. **Ledgers.** `git -C $V1 log --oneline -- <file> | wc -l` for each file in §3.4, and
   `git -C $V1 log --format= --name-only | grep -c '^fixes/[^/]*/README.md$'` (gives 892).
7. **The console export is one commit.** `git -C $V1 log --format='%h %s' -- console` returns one line
   (79fc236f).
8. **Lean.**
   `cd research/kickoff/10-automation-and-proof/lean-scratch/01-v1console && ~/.elan/bin/lean RowProjection.lean`
   (exit 0). Then append `#print axioms Fw.Row.close_wins` (and the other two) to a copy of the file to check the
   axioms.

## Appendix B: the transcript category regexes (from `scan.py`)

```text
status_write    status\.mjs\s+(set|priority|seed|sync)\b
status_read     status\.mjs\s+(list|show|mine|stale|check|agent|agents|phone-next)\b
progress_write  console\.mjs\s+progress\s+(set|best)\b
progress_read   console\.mjs\s+progress(?!\s+(set|best))
step_runner     console\.mjs\s+(post|ack|redo|reopen|cancel|answer)\b
step_wait       console\.mjs\s+wait\b
step_read       console\.mjs\s+(list|show)\b
thread_write    console\.mjs\s+thread\s+(reply|new|close|reopen|merge|unmerge|relate|assign|escalate|desk\s+set|steward\s+set|topic\s+set)\b
thread_wait     console\.mjs\s+thread\s+wait\b
thread_read     console\.mjs\s+thread\s+(list|show|lint)\b
proposal_write  console\.mjs\s+proposal\s+(post|revise|live|phone|publish|withdraw|decide|hold|unhold|revising)\b
proposal_read   console\.mjs\s+proposal\s+(list|show|wait|overdue|talk)\b
finding_write   finding\.mjs\s+(post|ack|claim|resolve)\b
finding_read    finding\.mjs\s+(list|show|wait|digest)\b
incident_write  incident\.mjs\s+(open|update|resolve)\b
incident_read   incident\.mjs\s+(list|show|wait|announce)\b
lock_status     lock\.mjs\s+status\b
lock_repair     lock\.mjs\s+repair\b
usage           usage\.mjs\b
idle            idle\.mjs\b
ledger_edit     Edit|Write|MultiEdit file_path matching
                fixes/PROGRESS.json | ops-handover.md | PREDICTIONS.md | fixes/FINDINGS.md | fixes/INCIDENTS.md |
                fixes/LEAD.md | fixes/AGENT_ROLES.md | fixes/<topic>/README.md | memory/ | CLAUDE.md
roles (name prefix) mgmt-ops, mgmt-*, fix-, ts-, review/rev-, de-, arch, iphone/phone, int-/wi-/wave (integrator),
                art-/cap- (capture), ver-/apple-verify (verifier), agent-a* (unnamed); session files = lead
```
