# 08.02 How v1's agents worked together: the coordination graph

Lens: who talked to whom, through which hubs, how agents were woken, replaced and handed off, and where
coordination failed. Sources are the v1 chat transcripts (lead sessions and subagent/teammate transcripts),
the pre-extracted digest, and the v1 console (threads, incidents, memory notes).

Conventions:
- `$DIG` is the digest folder (`.local/v1-chat-digest/out` in this repo). Every digest number has a command in
  Appendix A. Run it from `$DIG`.
- `$TX` is the v1 transcript folder (`~/.claude/projects/<v1 project>`). Numbers that need the raw transcripts
  come from the small scripts in Appendix B (`ctx.mjs`, `smres.mjs`, `i274.mjs`).
- `$V1` is the v1 repo, read only.
- Status tags: **MEASURED** means computed from data, **INFERRED** means reasoning on top of measured data,
  **QUOTED** means taken from a v1 note, incident or user message.
- "Main session" means lead session `391f6dee`: 09-30 to 10-11, 25,176 API calls and 125 compactions.
  Later sessions (`32f68516`, `7480db23`, `e978e7c9`) are small and are named where used.

---

## 0. Answer first

1. **v1 was a star with a second star bolted on, not a team.**
   - 64 % of the 12,582 SendMessage calls in the main session started or ended at the lead.
   - 31 % touched an `mgmt-ops*` instance.
   - Only 16 % went worker to worker, with no lead and no mgmt agent involved.
   - The lead exchanged messages with about 310 distinct agents: 373 distinct address strings, 311 once raw agent
     ids are mapped to agent names (A3b).
   - In a busy hour it handled up to 38 counterparts and 144 messages.
   - It compacted about once an hour (median 1.02 h between compactions). [A3, A4, A6, A12] MEASURED
2. **Messages were not lost. Attention was.**
   - Only 45 of 13,038 sends failed (0.35 %), and only 19 were duplicates (0.15 %).
   - Messages reached the lead fast: median 7 s when it was mid-turn, under 3 s when idle.
   - The failures were elsewhere:
     - 2,741 sends (21 %) had to resume an agent that had stopped.
       - The I-274 signature (a finished background job's notice reaches an idle agent only when something else wakes
       it) matched 214 times (MEASURED, heuristic); up to about 33 agent-hours of waiting (INFERRED upper bound).
     - 43 % of messages to the lead arrived in the middle of another turn.
   - [A8, A9, B1, B3] MEASURED
3. **Coordination ate about a fifth of the lead's re-read context** (INFERRED: these shares come from `ctx.mjs`, which
   Appendix B1 describes only as pseudocode, so they cannot be re-run from this note).
   - Teammate messages, subagent hand-backs, the lead's own SendMessage and spawn calls and their results were
     23.8 % of the transcript-visible content the lead took in.
   - They were 18.2 % of what it re-read on later turns, roughly 0.5 B cache-read tokens.
   - Re-injected rules, memory and skills were larger still: 30 % of re-reads.
4. **The ops hub was rebuilt ten times.**
   - `mgmt-ops` ran as 10 hub instances in 5 days (9 named transcripts plus the unnamed mgmt-ops-8), plus a
     14-turn Sonnet editor named mgmt-ops-11. Six of the handovers were for a full context.
   - One handover happened because the successor was spawned without a name, so peers could not reach it.
   - The last instance (`mgmt-ops-10`) instead ran 52.7 h through 46 compactions. It was then replaced by a Sonnet
     clerk to save cost.
   - 47 % of mgmt-* → lead messages were land requests (45 % for the mgmt-ops hubs alone). The hub relayed work to
     the lead; it did not remove it.
   - [A10, A11, §3] MEASURED and QUOTED
5. **Most friction was mechanical and fixable with config and hooks, not more agents.**
   - 62 % of all Bash errors (3,026 of 4,880) were worktree-isolation refusals.
   - 20 sends failed because teammates guessed the lead's address: 19 used `lead` and 1 `team-lead`; it was `main`.
   - Unnamed spawns after a compaction cut agents off from each other.
   - [A13, A9, A14] MEASURED

---

## 1. The graph

### 1.1 Volumes and edges

| Channel | Count | Source | Status |
|---|---|---|---|
| SendMessage calls, all sessions | 13,038 (lead sessions 4,761; agents 8,277) | A1 | MEASURED |
| Agent-to-lead messages actually enqueued in the main session | 4,619: 3,463 teammate messages + 1,173 subagent hand-backs (counts from the record types; they differ by about 0.4 %) | B1 | MEASURED |
| Spawns (Agent tool calls) | 823 (lead 544, agents 279) | A5 | MEASURED |
| User messages typed in the chat | 229 | `wc -l human.jsonl` | MEASURED |
| User messages in console threads | 989 in 278 threads | A16 | MEASURED |

**Caveat on the digest.** `peer-messages.jsonl` counts each message to the lead twice. A message is recorded once
when it is enqueued and once when it is delivered as a turn. The lead's 7,270 equals 4,619 enqueues plus 2,651
turn deliveries. Use the enqueue count (B1) for the number of messages. MEASURED

**Top edges by role class** (sender side, **all sessions**; the class rules are in A0). Restricted to the main
session, lead → toolsmith is 399, toolsmith → lead 245 and lead → unnamed 349; the other edges are unchanged:

| Edge | Msgs | | Edge | Msgs |
|---|---|---|---|---|
| lead → fix | 1,411 | | fix → mgmt-ops | 508 |
| fix → lead | 1,127 | | iphone-runner → lead | 370 |
| lead → mgmt-ops | 941 | | lead → iphone-runner | 354 |
| mgmt-ops → lead | 790 | | lead → unnamed (agent id) | 350 |
| mgmt-ops → fix | 651 | | fix → fix | 340 |
| lead → toolsmith | 519 | | toolsmith → lead | 306 |

[A2] MEASURED. Fix owners talked to each other (340) about as often as they talked to the phone runner (119 + 137).

### 1.2 Hubs

Main session, sent + received SendMessage, with the number of distinct partners:

| Agent | Out | In | Partners | Share of all msgs |
|---|---|---|---|---|
| lead (`main`) | 4,552 | 3,480 | 373 address strings (311 agents) | 63.8 % |
| mgmt-ops-10 | 896 | 831 | 47 | 13.7 % |
| iphone-runner | 726 | 725 | 60 | 11.5 % |
| fix-nav-morph | 413 | 508 | 55 | 7.3 % |
| int-v8 (integrator) | 328 | 408 | 29 | 5.8 % |

[A3] MEASURED. `iphone-runner` was a hub because it owned the only phone: 60 partners queued work through it.
That is a resource hub, and v2 replaces it with the device lock and a script (PLAN §3.3).

**Peer-to-peer share by day** (messages with neither the lead nor an mgmt agent at either end):

25 % on 09-30, 22 % on 10-01, then 8-17 % for the rest of the run.

The user asked several times for agents to talk directly, for example asking the design agents to talk together
(09-30 22:23), and complaining on 10-01 that teammates were spawned unnamed and could not reach each other
(paraphrased). The share still never rose. [A3] MEASURED.

### 1.3 Relay chains

- **Verbatim forwarding was rare.**
  - Only 0-7 % of each hub's outbound messages shared six or more word 6-grams with a message the hub received in
    the previous 15 minutes.
  - The exception is `mgmt-clerk-1` at 15 %, which was a clerk by design. [A7] MEASURED
- **Paraphrased relaying was common.**
  - 4 % of the lead's messages and 8 % of mgmt messages use relay words (relay, forward, "on behalf of").
  - **467 of 990 (47 %) mgmt-* → lead messages are land requests; for the mgmt-ops hubs alone it is 354 of 789
    (45 %).** Workers sent "ready" to mgmt-ops, and mgmt-ops sent the land request to the lead, because only the
    lead could land.
  - The two-hop chain worker → mgmt-ops → lead → worker was the normal landing path. [A7] MEASURED
- QUOTED (`$V1/memory/proactive-by-default.md`, 10-04): "the lead made 89 of 92 queue moves by hand … and the lead
  relayed results between agents. One user message got two different answers."

### 1.4 Spawn fan-out, depth and lifetimes

**Spawns per day** (A5, MEASURED):

| Day | 09-30 | 10-01 | 10-02 | 10-03 | 10-04 | 10-05 | 10-06 | 10-07…11 | 10-12/13 |
|---|---|---|---|---|---|---|---|---|---|
| by lead | 72 | 88 | 35 | 48 | 59 | 63 | 31 | 17-23/day | 25 / 23 |
| by agents | 201 | 18 | 2 | 2 | 7 | 14 | 9 | 0-13/day | 0 |

- On 09-30, 133 of the 201 agent-made spawns came from **one** benchmark agent ("grep vs Serena navigation").
  At 21:00 that hour, 190 agents were alive in the session. [A5, A6]
- **Depth:**
  - 509 agents ran at depth 1 (spawned by the lead).
  - 278 ran at depth 2 (spawned by an agent).
  - 48 ran at depth 0. These are teammates in the 10-12/13 sessions, which ran on a newer client that records
    teammates differently.
  - No depth 3. [A5] MEASURED
- **Lifetimes, first to last record** (A6, MEASURED):

| Class | n | p50 | p90 | max |
|---|---|---|---|---|
| unnamed id | 297 | 0.01 h | 0.2 h | 5 h |
| mapper | 53 | 0.06 h | 0.1 h | 2.5 h |
| reviewer | 67 | 0.2 h | 2.2 h | 9.4 h |
| toolsmith | 133 | 0.9 h | 4.9 h | 13.5 h |
| fix owner | 50 | 4.9 h | 42.5 h | 119.5 h |
| integrator | 7 | 4.8 h | 51 h | 51 h |
| mgmt-ops (per instance) | 10 | 8.4 h | 52.7 h | 52.7 h |
| iphone-runner | 3 | 0.9 h | 102 h | 102 h |

Long lives map to long contexts. fix-nav-morph made 4,604 calls with 44 compactions, iphone-runner 4,014 calls
with 32, and mgmt-ops-10 4,780 calls with 46. [B1 on those files] MEASURED

### 1.5 Span of control

In the main session's 224 active hours:
- The lead exchanged SendMessages with a median of 5 distinct agents per hour, p90 13, max 38 (09-30 22h).
- It handled a median of 29 messages per hour, p90 80, max 144. [A4]
- Per day it was up to 85 distinct agents (10-01) and 81 (10-04). [A4]
- It compacted 125 times (119 auto). The median pre-compaction context was 268k tokens and the max was 523k. [A12]

All MEASURED. INFERRED: with an hourly reset, the lead could not have held more than about one hour of a
13-agent conversation in working memory. The rest lived in compact summaries (3.5 % of re-reads) and files.

**What started the lead's 8,948 turns** (B1, MEASURED):

| Trigger | Count | Share |
|---|---|---|
| Meta prompts (`isMeta`): 3,761 scheduled cron fires (42 %) plus 96 goal check-ins, 27 local-command caveats, 5 Stop-hook feedbacks and a few others | 3,921 | 44 % |
| A teammate message or subagent hand-back | 2,651 | 30 % |
| A task notification (console-thread waits, background jobs, Monitor) | 2,107 | 24 % |
| The user typing in chat | 200 | 2 % |

The cron fires (MEASURED, README B12):
- From the user's five `/loop` prompts (2,897 fires):
  - "check iphone connection" 1,889;
  - the user's own coordination poll, asking the lead to check that all agents work together (paraphrased), 988;
  - three smaller loops (team improvement, each agent's state, session usage) 20.
- From crons the lead created itself (864 fires):
  - delegated-mode check-ins with mgmt-ops 365;
  - usage checks 334 (asked for by the user in T-010);
  - hourly team measures 164 (asked for in T-163);
  - one usage-window reset.

So about 1,350 lead turns were spent asking the team how it was doing (the 988 coordination polls plus the 365
check-ins).

### 1.6 The console channel

- The user talked mostly through the console: 989 thread messages against 229 in the chat.
- The first non-user reply came in a median 0.7 min (p90 2.7 min); 13 of 985 took over 10 min.
- **The lead was still first responder on 773 of 985 (78 %),** even after "desk" agents were created to take
  this load off it: `mgmt-desk-1` (10-04 10:15) right after the user asked whether mgmt-ops-10 was the bottleneck
  (T-104), and `mgmt-desk-2` (13:40) after the user called the lead the bottleneck (T-105 #18).
- The desks answered first 68 times, other mgmt agents 86, workers 58. [A16] MEASURED
- Every console wake reached the lead as a task notification, which is part of the 24 % above.

---

## 2. How much of the lead's context went to reading teammates

**Status of this section: INFERRED.** The shares below come from `ctx.mjs`, which Appendix B1 describes only as
pseudocode. Until the script is published in full, nobody can re-run them.

Method (B1, `ctx.mjs`):
- Every block that entered the lead's transcript is classified.
- Its weight is its characters times the number of later API calls that re-read it before the next compaction.
- This covers transcript-visible content only. The system prompt and tool schemas are not in the transcript.
  The visible re-reads come to about 2.71 B tokens at 4 characters per token, against 5.86 B actual cache-read
  tokens for the session.

| Category (main session) | Items | Share of chars taken in | Share of re-reads |
|---|---|---|---|
| Rules, memory and skills re-injected (`instructions`, `nested_memory`, `invoked_skills`) | 378 | 22.1 % | **30.0 %** |
| **Coordination traffic, total** | 14,730 | **23.8 %** | **18.2 %** |
|   teammate messages in | 3,463 | 7.9 % | 6.0 % |
|   subagent hand-backs in | 1,173 | 7.0 % | 5.5 % |
|   lead's SendMessage calls out | 4,552 | 4.9 % | 3.7 % |
|   spawn prompts out | 495 | 2.3 % | 1.7 % |
|   SendMessage and Agent results | 5,047 | 1.7 % | 1.3 % |
| Bash output | 13,774 | 16.2 % | 14.6 % |
| Lead's tool inputs, other than SendMessage and Agent | 15,120 | 10.3 % | 8.9 % |
| Lead's prose | 20,271 | 8.3 % | 7.3 % |
| Task notifications | 5,249 | 5.6 % | 5.1 % |
| Compact summaries | 125 | 2.6 % | 3.5 % |
| Cron prompts | 7,682 | 1.4 % | 1.3 % |
| User typing | 259 | 0.03 % | 0.0 % |

- Shares of transcript-visible content (from `ctx.mjs`; see the status note above).
- INFERRED: 18.2 % × 2.71 B ≈ **0.49 B cache-read tokens** went to coordination traffic in the lead. Messages
  and hand-backs alone were about 0.31 B. That is a lower bound of about 8 % of the session's 5.86 B cache reads.
- **Hub teammates spent less of their context on messages.**
  - mgmt-ops-10: 8.1 % of re-reads.
  - iphone-runner: 8.9 %.
  - fix-nav-morph: 4.9 %.
  - The exception is `mgmt-clerk-1` at 21 %, whose whole job was messages. [B1 per file; same caveat]

### 2.1 Message length

| Stream | n | p50 chars | p90 chars |
|---|---|---|---|
| All SendMessage | 13,038 | 691 | 1,967 |
| lead → anyone | 4,761 | 517 | 1,120 |
| fix → lead | 1,127 | 1,112 | 2,548 |
| toolsmith → lead | 306 | 1,319 | 3,073 |
| integrator → lead | 232 | 1,342 | 2,582 |
| distill → lead | 221 | 1,429 | 3,318 |
| fix → other agents | 1,425 | 868 | 2,249 |
| Subagent hand-backs into the lead | 1,173 | **4,140** | **7,138** (max 24,271) |

SendMessage rows: [A15] MEASURED. The hand-back row comes from `ctx.mjs` [B1] and is INFERRED until that script is
published. Messages to the lead ran about 1.3-1.5x longer than the same senders' messages to peers.
Hand-backs, which are a subagent's final report, ran about 4x longer than teammate messages. 2,236 sends were
over 1,500 characters.

---

## 3. mgmt-ops 1…10: why the hub kept being replaced

| Instance | Alive (UTC) | Life | Calls | Compactions | Why it ended or was replaced (from the successor's spawn prompt) |
|---|---|---|---|---|---|
| mgmt-ops | 09-30 23:06 → 10-01 02:34 | 3.5 h | 448 | 1 | "context filled up" |
| mgmt-ops (2nd, same name) | 10-01 01:18 → 09:42 | 8.4 h | 159 | 1 | Ran 1.3 h alongside the first under the same name. The lead's next send failed: "'mgmt-ops' now resolves to a different agent … Nothing was sent." |
| mgmt-ops-3 | 10-01 05:03 → 08:51 | 3.8 h | 183 | 0 | Handed over "at ~55 % context" |
| mgmt-ops-4 | 08:52 → 14:10 | 5.3 h | 165 | 1 | Ended 11:25 |
| mgmt-ops-5 | 11:25 → 18:01 | 6.6 h | 350 | 3 | "near its context limit" |
| mgmt-ops-6 | 10-01 17:19 → 10-02 09:11 | 15.9 h | 544 | 3 | "stopped at ~60 % context" |
| mgmt-ops-7 | 10-02 09:12 → 23:54 | 14.7 h | 462 | 3 | Replaced by mgmt-ops-8 |
| mgmt-ops-8 | spawned 10-02 23:55 **without a name** | minutes | — | — | "peers could not reach [it] by name"; replaced 7 min later |
| mgmt-ops-9 | 10-03 00:02 → 08:37 | 8.6 h | 372 | 3 | Overlapped 19 min with -10 |
| mgmt-ops-10 | 10-03 08:18 → 10-05 12:59 | **52.7 h** | **4,780** | **46** | User asked to move routine work to cheaper models (T-196). Replaced by `mgmt-clerk-1` on Sonnet. |
| mgmt-ops-11 | 10-04 18:49, Sonnet | minutes | 14 | 0 | Not a hub: a one-job ops editor that reused the family name |

Sources: A10 and A11 (lifetimes, spawn prompts) are MEASURED. The reasons are QUOTED from the spawn prompts.

Split-offs taken out of the hub's job:
- `mgmt-desk-1` (10-04 10:15), for user threads, right after the user asked whether mgmt-ops-10 was the bottleneck
  (T-104 #1; its spawn prompt says so); `mgmt-desk-2` (13:40) after the user told the lead it was the bottleneck
  because catch-ups across many threads slowed it down (T-105 #18, paraphrased).
- `mgmt-devices` (10-04), after the phone sat idle for 10 minutes unnoticed (T-149).
- 27 short `ops-reader-*` agents (10-05/06), one per proposal read.

INFERRED reading:
- Two policies were tried, and both cost a lot:
  - Hand over at 55-60 % context: 7 instances in 2.5 days, each re-reading `ops-handover.md`, LEAD.md, DIRECTION.md
    and the incident and lock state.
  - Ride compactions: mgmt-ops-10 compacted 46 times, used 773 M cache-read tokens, and still needed 285 resumes by
    message (B2).
- Neither made the lead's load go away, because the lead stayed the only one who could land, spawn, rule and talk
  to the user.

Other role families with re-spawns:
- 27 named-role families had more than one instance (72 instances in total). Examples: review-scene-scope ×5, and
  the I-268…I-274 release toolsmiths ×2 each across the 10-12 and 10-13 sessions.
- In 6 cases the exact same name was reused within one session (arch-webkit, arch-render, review-stats, mgmt-ops,
  review-scene-scope, ops-reader-P152). [A11] MEASURED

---

## 4. Coordination failures, quantified

| # | Failure | Evidence | Status |
|---|---|---|---|
| F1 | **Stopped agents had to be resumed by message.** 2,741 of 13,038 sends (21 %) returned "Resuming agent X", across 279 distinct agents. Top targets: mgmt-ops-10 285, fix-nav-morph 189, int-v8 155, mgmt-clerk-1 154, iphone-runner 132. The lead's own sends: 1,348 of 4,552 (30 %) were resumes. | B2 | MEASURED |
| F2 | **Wake-up gap (I-274).** A background job finishes while the agent is idle, and the notification does not wake it. The agent sleeps until someone sends it a message. The signature (silence of 5 min or more, then the notification written at wake time with an earlier timestamp) matches **214 times in 65 agents, up to 1,996 min (an upper bound on wasted wait), median 6.3 min, max 103 min.** It occurred every day from 09-30 (busiest 10-04: 75), long before it was diagnosed on 10-13. The four cases named in the incident (ts-i268 103 min, ts-i269 92, ts-i270 86, ts-i273 80) are the top hits. | B3; incident I-274 | MEASURED (heuristic); the bug's existence is QUOTED |
| F3 | **Deaf in the foreground.** Many notification-to-wake gaps cluster at 9.6-9.7 min, the 10-minute Bash foreground cap. Agents running a long foreground command did not see messages (I-169, I-170, fixed by the `fg-guard` hook on 10-04). | B3 variant; incidents | MEASURED cluster; cause QUOTED |
| F4 | **The lead was interrupted mid-turn.** 1,982 of 4,619 messages to the lead (43 %) were absorbed mid-turn as reminders, inside unrelated work. The user noticed that the lead was being interrupted a lot (09-30 23:05, paraphrased). | B1 | INFERRED until `ctx.mjs` is published; user remark paraphrased |
| F5 | **Wrong or stale addresses.** Of the 45 failed sends: 20 used a guessed lead address (19 `lead`, 1 `team-lead`; the lead was `main`), 13 named ended or unknown agents, 8 tried to resume an agent whose worktree was deleted, and 4 hit a name now held by a newer agent. | B2 | MEASURED |
| F6 | **Context dropped after compaction.** After the lead's compaction at about 09:11 on 10-01, it spawned 9 agents unnamed between 09:13 and 10:19. Four sends to their intended names failed between 10:17 and 10:20. At 10:26 the user said the teammates could not talk to each other because they were spawned as general-purpose agents (paraphrased). It slipped again on 10-02 23:26 → 10-03 00:00 (3 unnamed, including mgmt-ops-8). Overall the lead spawned 35 of 495 unnamed, and 14 of 415 after the naming rule. | A14; `$V1/memory/agent-spawn-names.md` | MEASURED / QUOTED |
| F7 | **Worktree pinning.** 3,046 tool errors across 358 agents were worktree-isolation refusals. They were 3,026 of the 4,880 Bash errors (62 %). The main forms: "too complex to verify" (868), "names git in a form too complex" (616), "cd to the shared checkout before git" (143). mgmt-ops* alone hit 209. Separately, I-272: `EnterWorktree` in a teammate moved the whole session. | A13; I-272 | MEASURED / QUOTED |
| F8 | **Two bosses.** For 102 workers, 984 of 4,460 consecutive instructions in their inbox (22 %) switched between the lead and an mgmt agent within 30 min. Explicit "conflicting instruction" complaints are hard to separate from merge-conflict talk in the text, so contradictions are not quantified here. The "one user message got two different answers" case is QUOTED from v1. | A17 | MEASURED exposure; contradiction INFERRED |
| F9 | **Supervision by polling.** 988 fires of the user's "check that all agents work together" poll, 365 lead-created mgmt check-ins, and 47 explicit status pings by the lead. The status pings were *not* concentrated after compactions: 28 % of pings fell within 15 min of one, against 25 % of all lead messages. | B1, A12 | MEASURED |
| F10 | **Lost or duplicated messages: not a real problem.** 0.35 % failed and 0.15 % were duplicates (same sender, recipient and first 200 chars within 60 min). Messages to the lead reached it in a median 0-7 s, and only 4 took over 10 min. | A8, B1 | MEASURED |
| F11 | **Console routing holes.** Router incidents: I-137 (a dead listener counted as listening, so a user message went unanswered), I-163 (orphan wait), I-164 (busy owners woken), I-169 (deaf owner), I-181 (the lead's triage skipped its own threads), I-147 (a proposal decision missed for 16 min). Six router or listener fixes landed on 10-04. | `$V1/console/incidents.json` | QUOTED |

---

## 5. What this says about v2 (INFERRED)

- **Delivery is solved by the platform. Attention and waking are not.**
  - v2 needs no message bus.
  - It needs (a) fewer recipients per message, (b) a guaranteed wake path, and (c) state the lead can read
    without a conversation.
- **A hub agent is a context sink.** Every hub (the lead, mgmt-ops-10, iphone-runner) became a 4,000+ call,
  30-46-compaction context. Routing, queueing, device dispatch and land bookkeeping are fixed rules, so they belong
  in scripts over an event log (PLAN §2.2 and §3.3 already drop mgmt agents; this note supplies the numbers).
- **The lead's turn budget went to polling** (42 % cron fires, 44 % with other meta prompts; 30 % inbound messages). A lead capped at 600
  requests/day (PLAN §8.4) is only possible if polls become scripts that wake the lead on change, and teammates
  send one-line FYIs with a pointer instead of reports.
- **Names, addresses and worktrees caused more failures than any reasoning error in this lens.** They are cheap to
  enforce with hooks.

---

## Improvements for v2

| # | Change | Evidence | PLAN section changed |
|---|---|---|---|
| 1 | **Fix one lead address and lint it.** Do not guess it: record the address that SPK-a verifies on the v2 Claude Code version (v1's working address was `main`), and lint role files and spawn prompts for it. Spawn prompts get the peer directory *generated* from the live roster, never typed. Add a SubagentStart or SessionStart check that the address in each role file matches. | F5: 20 failed sends to a guessed address (19 `lead`, 1 `team-lead`) while the lead was `main` | §8.1 (verified mechanics: record the lead's address), §8.3 `session-brief` |
| 2 | **Extend spawn-guard to deny unnamed spawns and names in use.** Deny an `Agent` call without `name`, and deny a name that already resolves to a live or resumable agent. Restarts must use `<role>-<topic>-<n>`. | F6: 9 unnamed spawns right after a compaction cut peers off; mgmt-ops-8; 6 same-name reuses; 4 "name now resolves to a different agent" failures | §8.3 `PreToolUse` spawn-guard (add two deny rules and unit tests) |
| 3 | **Add a stall watcher, as a script, not an agent.** It flags a teammate with a finished background task and no assistant record since, and sends one wake SendMessage. Teammates wait in the foreground with a bounded timeout instead of ending their turn on a background job. Re-check the upstream bug at each Claude Code upgrade. | F2: 214 signature matches, up to ~33 agent-hours (upper bound), max 103 min, on most days of v1; F3 10-min deaf cluster | §8.1 (add "background-task notifications do not wake an idle teammate" as a verified limit), §8.3 hooks, §11 new risk row |
| 4 | **Nothing whose only job is routing.** No ops, desk, clerk or dispatcher agent. Queue order, land queue, device dispatch, check-in digests and console first-response come from `pnpm fw status` projections over the event log. | §3: 10 mgmt-ops instances, 6 context handovers, mgmt-ops-10 at 4,780 calls and 46 compactions; 47 % of mgmt-* → lead messages (45 % for mgmt-ops) were land requests; the desk answered first only 68 of 985 times | §2.2 Drop (list mgmt-ops, desk, clerk, devices explicitly with these numbers), §3.3 |
| 5 | **Peer-first results with a lead FYI capped at one line.** A worker sends its result to its consumer (reviewer, integrator, experiment owner) and gives the lead ≤ 300 characters plus a file path. Long reports go to `research/notes/` or the experiment card, never into a message. | §2.1: messages to the lead p50 1.1-1.4k chars; hand-backs p50 4.1k (max 24k) and coordination 18 % of lead re-reads (~0.5 B tokens), both INFERRED (`ctx.mjs`); peer-to-peer only 16 % | §8.2 (role contract line), §8.4 levers (add "message budget"), §9.2 artifacts |
| 6 | **Replace recurring check prompts with scripts that wake on change.** No cron prompt to the lead that asks the team for status. `pnpm fw status --watch` posts only deltas, such as a stall, an idle device or a queued land. | §1.5: 3,761 cron fires were 42 % of the lead's turn starts (988 "check all agents work together", 1,889 "check iphone connection"); 864 came from crons the lead created, so the rule must cover `CronCreate`, not only `/loop` | §8.4 lever 1 (cite these numbers), §9 (add "supervision is a projection, not a prompt") |
| 7 | **One manager per worker.** Only the lead (or the worker's experiment owner) instructs a builder; other roles send FYIs. Record the owner in the spawn prompt and the roster. | F8: 22 % of consecutive instructions to 102 workers switched between the lead and mgmt within 30 min; "one user message got two different answers" | §8.2 roster ("Spawned when" → add "reports to") |
| 8 | **Ship git and file wrappers that pass the isolation check.** `pnpm fw git <args>` runs `git -C <own worktree>`, and role prompts say "never `cd` to the main checkout". The lead creates every worktree (already in §8.1). Count isolation refusals in the usage meter, with an alarm over 20/day. | F7: 3,026 Bash refusals (62 % of Bash errors) across 358 agents; I-272 | §8.1, §8.3 permissions allow-list, §8.4 reporting |
| 9 | **Re-inject roster and naming rules after every compaction.** Use a hook (`PostCompact`, or `SessionStart` with the compact source, whichever SPK-a confirms) that prints the roster, the lead address and the naming rule in ≤ 15 lines. With the 200k cap the lead will compact often, so this has to be automatic. | F6 (naming lost at the 10-01 09:11 compaction); the lead compacted every ~1 h (p50 268k pre-tokens) | §8.1 cW, §8.3 `session-brief` trigger list |
| 10 | **Make "ended" explicit.** A teammate either finishes (hand-back, then it may be resumed by a new task) or waits in the foreground. Resumes are counted per role in `pnpm fw usage`, with a ceiling (for example 20/day per role) that triggers a decision record. | F1: 21 % of all sends were resumes, 285 for one hub | §8.4 Reporting |
| 11 | **Budget span of control from data.** The caps of 3 teammates + 4 worktree subagents put ≤ 7 live counterparts on the lead. Add "distinct counterparts per hour" and "messages in per hour" to the meter, with alarms at 10 and 60 (v1 p90: 13 and 80). | §1.5: v1 p50 5, p90 13, max 38 counterparts/h; up to 85 agents/day | §8.2 Caps, §8.4 Reporting |
| 12 | **Console first response by script or a read-only helper, not the lead.** The console answers status questions from projections. Only judgement questions wake the lead, and those are tagged in the thread. | §1.6: the lead was first responder on 78 % of 985 console questions; router incidents I-137/163/164/169/181/147 | §3.2 modules (console-api), §12.2 defaults |
| 13 | **No fan-out bursts.** Spawn-guard also limits spawns to ≤ 6 per 10 minutes per spawner, and keeps depth-2 spawns to read-only helpers. | §1.4: 133 spawns by one benchmark agent in an hour; 190 agents alive at 09-30 21h | §8.3 spawn-guard, §8.3 env (`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=2` kept) |

---

## Appendix A. Digest commands (run in `$DIG`)

**A0. Role classifier.** Save this as `$CLS` (for example `/tmp/cls.js`):

```js
module.exports=n=>{n=String(n||"");if(/^lead:/.test(n)||/^(main|team-lead|lead)$/.test(n))return"LEAD";n=n.replace(/^.*\//,"");
for(const[r,c]of[[/^mgmt-ops/,"mgmt-ops"],[/^mgmt-/,"mgmt-other"],[/^iphone-runner/,"iphone-runner"],[/^fix-/,"fix"],[/^(int|wi|wave)/,"integrator"],[/^(ts|tool)/,"toolsmith"],[/^(review|rv)/,"reviewer"],[/^arch-/,"arch"],[/^de-/,"distill"],[/^(map|bm)-/,"mapper"],[/^(art|cap)-/,"capture"],[/^ops-/,"ops-reader"],[/^(agent-)?a[0-9a-f]{16}$/,"unnamed-id"]])if(r.test(n))return c;return"other"}
```

Shorthands used below:

```sh
J='const L=f=>require("fs").readFileSync(f,"utf8").trim().split("\n").map(JSON.parse);'
q='const q=(s,f)=>{s=[...s].sort((x,y)=>x-y);return s[Math.min(s.length-1,Math.floor(f*s.length))]};'
```

**A1. SendMessage totals by side.**

```sh
jq -s 'group_by(.who|startswith("lead"))|map({lead:.[0].who|startswith("lead"),n:length})' sendmessage.jsonl
```

**A2. Role-class edge matrix.**

```sh
node -e "$J"'const C=require(process.env.CLS),m={};L("sendmessage.jsonl").forEach(r=>{const k=C(r.who)+" -> "+C(r.to);m[k]=(m[k]||0)+1});console.log(Object.entries(m).sort((a,b)=>b[1]-a[1]).slice(0,30))'
```

**A3. Hub degree, lead and mgmt shares, peer-to-peer share by day (main session).**

```sh
node -e "$J"'const S=L("sendmessage.jsonl").filter(r=>/^(lead:391|391f6dee\/)/.test(r.who)),n=r=>r.who.startsWith("lead")?"LEAD":r.who.split("/")[1],t=x=>/^(main|team-lead|lead)$/.test(x)?"LEAD":x,D={};S.forEach(r=>{for(const[a,b,k]of[[n(r),t(r.to),"out"],[t(r.to),n(r),"in"]]){D[a]??={out:0,in:0,p:new Set()};D[a][k]++;D[a].p.add(b)}});console.log(S.length,Object.entries(D).sort((a,b)=>b[1].out+b[1].in-a[1].out-a[1].in).slice(0,8).map(([k,v])=>[k,v.out,v.in,v.p.size]));const pp=r=>n(r)!="LEAD"&&t(r.to)!="LEAD"&&!/^mgmt/.test(n(r))&&!/^mgmt/.test(t(r.to));console.log("lead",S.filter(r=>n(r)=="LEAD"||t(r.to)=="LEAD").length,"ops",S.filter(r=>/^mgmt-ops/.test(n(r)+" "+t(r.to))||/^mgmt-ops/.test(t(r.to))).length,"p2p",S.filter(pp).length)'
```

**A3b. Lead partners with agent ids mapped to names** (373 address strings → 311 agents; the same command as
README B13):

```sh
node -e 'const fs=require("fs"),A=require("./agents.json"),id={};for(const a of A){const m=(a.file||"").match(/agent-(a[0-9a-f]+)\.jsonl$/);if(m&&a.name)id[m[1]]=a.name}const t=x=>/^(main|team-lead|lead)$/.test(x)?"L":x,raw=new Set(),can=new Set();for(const r of fs.readFileSync("sendmessage.jsonl","utf8").trim().split("\n").map(JSON.parse)){if(!/^(lead:391|391f6dee\/)/.test(r.who))continue;const a=r.who.startsWith("lead")?"L":r.who.split("/")[1],b=t(r.to),p=a=="L"?b:b=="L"?a:null;if(!p||p=="L")continue;raw.add(p);can.add(id[p.replace(/^agent-/,"")]||p)}console.log(raw.size,can.size)'
```

For the main-session edge matrix, add `.filter(r=>/^(lead:391|391f6dee\/)/.test(r.who))` to A2.

**A4. Lead counterparts and messages per hour and per day.**

```sh
node -e "$J$q"'const S=L("sendmessage.jsonl").filter(r=>r.who.startsWith("lead:391")||(r.who.startsWith("391f6dee/")&&/^(main|team-lead|lead)$/.test(r.to))),H={};S.forEach(r=>{const h=r.ts.slice(0,13);H[h]??={p:new Set(),n:0};H[h].n++;H[h].p.add(r.who.startsWith("lead")?r.to:r.who.split("/")[1])});const P=Object.values(H).map(x=>x.p.size),N=Object.values(H).map(x=>x.n);console.log(P.length,q(P,.5),q(P,.9),Math.max(...P),q(N,.5),q(N,.9),Math.max(...N))'
```

For the per-day figure, use `r.ts.slice(5,10)` as the key.

**A5. Spawns per day by spawner; depth.**

```sh
node -e "$J"'const E=L("events.jsonl").filter(e=>e.kind=="spawn"),d={};E.forEach(e=>{const k=e.ts.slice(5,10);d[k]??={lead:0,agent:0};d[k][e.who.startsWith("lead")?"lead":"agent"]++});console.table(d)'
jq -s 'map(select(.kind=="agent"))|group_by(.spawnDepth)|map({d:.[0].spawnDepth,n:length})' agents.json
```

**A6. Lifetimes by class; agents alive per hour.**

```sh
node -e "$q"'const C=require(process.env.CLS),a=require("./agents.json").filter(r=>r.kind=="agent"&&r.first),g={};a.forEach(r=>(g[C(r.name)]??=[]).push((Date.parse(r.last)-Date.parse(r.first))/36e5));for(const[k,v]of Object.entries(g))console.log(k,v.length,q(v,.5).toFixed(2),q(v,.9).toFixed(1),Math.max(...v).toFixed(1))'
```

For agents alive per hour: filter `session=="391f6dee"`, increment every hour bucket between `first` and `last`, and take the max (190, at 09-30T21).

**A7. Relays.**
- Verbatim relays: compare each hub output with the hub's inputs from the previous 15 min. Count a relay when it shares ≥ 3 word 6-grams and those cover ≥ 15 % of the output's 6-grams.
- Relay words and land requests:

```sh
node -e "$J"'const L2=L("sendmessage.jsonl"),re=/\b(relay(ed|ing)?|forward(ed|ing)?|passing (this|it) on|on behalf of)\b/i,land=/\b(land request|ready to land|please land)\b/i,c=(f,x)=>{const s=L2.filter(f);return s.filter(r=>x.test(r.msg)).length+"/"+s.length};console.log(c(r=>r.who.startsWith("lead:391"),re),c(r=>r.who.startsWith("391f6dee/mgmt"),re),c(r=>r.who.startsWith("391f6dee/mgmt")&&r.to=="main",land))'
```

**A8. Duplicate sends.**

```sh
node -e "$J"'const m=new Map();let d=0;L("sendmessage.jsonl").sort((a,b)=>a.ts<b.ts?-1:1).forEach(r=>{const k=r.who+"|"+r.to+"|"+r.msg.slice(0,200),t=Date.parse(r.ts),p=m.get(k);if(p!=null&&t-p<36e5)d++;m.set(k,t)});console.log(d)'
```

**A9. Failed sends by cause.** Use B2's output: `node -e 'const j=require("./smres.json");…'`, grouping `fails[].why` by `named .(lead|team-lead).`, `worktree no longer exists`, `now resolves to a different agent`, and other.

**A10. mgmt and ops lineage.**

```sh
jq -r '.[]|select(.kind=="agent" and (.name|test("^mgmt")))|[.name,.first[5:16],.last[5:16],.asst,.compactions,(.usage.cacheRead/1e6|floor)]|@tsv' agents.json
```

**A11. mgmt spawn prompts (replacement reasons); role families; same-name reuse.**

```sh
jq -c 'select(.kind=="spawn" and ((.name//"")|test("^mgmt")))|{ts,name,p:.prompt[0:300]}' events.jsonl
```

For role families: strip `-\d+`, `-r\d*`, `-p\d+` from named agents and count families with more than one instance. For same-name reuse: count `session/name` pairs that occur more than once.

**A12. Lead compactions: count, trigger, pre-tokens, spacing; pings near compactions.**

```sh
jq -s 'map(select(.kind=="compact" and .who=="lead:391f6dee"))|{n:length,auto:map(select(.meta.trigger=="auto"))|length,pre:(map(.meta.preTokens)|sort|.[length/2|floor])}' events.jsonl
```

**A13. Worktree-isolation errors.**

```sh
jq -s '[.[]|select(.msg|test("isolated in the worktree"))]|{n:length,agents:([.[].who]|unique|length),bash:([.[]|select(.tool=="Bash")]|length)}' errors.jsonl
jq -s '[.[]|select(.tool=="Bash")]|length' errors.jsonl
```

**A14. Unnamed lead spawns, and their time since the last compaction.**

```sh
jq -c 'select(.who=="lead:391f6dee" and .kind=="spawn" and .name==null)|{ts,desc}' events.jsonl
```

**A15. Message length by sender class.** True length is `1500+N` when a message ends with `…[+N]`.

```sh
node -e "$J$q"'const C=require(process.env.CLS),len=m=>{const x=m.match(/…\[\+(\d+)\]$/);return x?1500+ +x[1]:m.length},g={};L("sendmessage.jsonl").forEach(r=>{const k=C(r.who)+(C(r.to)=="LEAD"?" -> LEAD":"");(g[k]??=[]).push(len(r.msg))});for(const[k,v]of Object.entries(g))console.log(k,v.length,q(v,.5),q(v,.9))'
```

**A16. Console threads** (run in `$V1/console`): count user messages, first responder class, and reply latency.

```sh
node -e "$q"'const fs=require("fs"),T=fs.readdirSync("threads").filter(f=>f.endsWith(".json")).map(f=>JSON.parse(fs.readFileSync("threads/"+f))),cl=b=>b=="user"?"user":b=="lead"?"lead":/^mgmt-desk/.test(b)?"desk":/^mgmt/.test(b)?"mgmt":"worker",F={},lat=[];let u=0;T.forEach(t=>(t.messages||[]).forEach((m,i,a)=>{if(m.by!="user")return;u++;const r=a.slice(i+1).find(x=>x.by!="user");if(r){F[cl(r.by)]=(F[cl(r.by)]||0)+1;lat.push((Date.parse(r.at)-Date.parse(m.at))/6e4)}}));console.log(T.length,u,F,q(lat,.5),q(lat,.9),lat.filter(x=>x>10).length)'
```

**A17. Two-boss exposure.** For each non-mgmt recipient, sort the messages it received from the lead or an
`mgmt-*` sender by time, and count consecutive pairs whose source switches within 30 min (984 of 4,460, 102 workers).

## Appendix B. Raw-transcript scripts (run in `$TX`; read only)

**B1. `ctx.mjs <file.jsonl>`.** Per-category characters and re-read weight, turn starts, inbound message lengths,
and queue latency. **Only the method and the core loop are given here, not the script**, so the figures that come
only from it (§2 shares, the hand-back lengths, the 43 % mid-turn share) are INFERRED until it is published in full.
The turn-start counts in §1.5 were re-checked by a raw scan of the lead's user records (`isMeta` grouped by prompt).
- Each category's weight is its characters × the API calls (unique `requestId`) between insertion and the next
  `compact_boundary`.
- Attachments count by their `rendered` length. Bookkeeping attachments such as `prompt_snapshot` and
  `deferred_tools_record` have none, so they count as zero.
- Teammate versus hand-back is decided by the `[Subagent hand-back]` marker.
- Queue latency:
  - Mid-turn delivery: `enqueue` matched to `remove` by content.
  - Idle delivery: `enqueue` matched to the next `origin.kind=="peer"` user record by the first 300 chars.

Run it on `391f6dee-….jsonl` for the lead. Run it on `391f6dee-…/subagents/agent-<id>.jsonl` (find the id with
`grep -l '"name":"mgmt-ops-10"' */subagents/*.meta.json`) for the hubs. The script's core loop:

```js
// for each record r (file order):
// assistant: new requestId -> call++; text/tool_use(SendMessage|Agent|other) -> add(cat, chars)
// user: isCompactSummary -> 'compact summary'; tool_result -> 'in:tool_result <tool>';
//       else turnStart[r.origin?.kind ?? (r.isMeta?'meta':'none')]++, peer -> teammate|hand-back, coordinator, human
// attachment: queued_command -> classify by origin/agent-message/hand-back; others -> rendered length by type
// system: compact_boundary -> close segment (w += call*chars - sum(chars*callAtInsert)); scheduled_task_fire -> prompt
// queue-operation: enqueue -> pending; remove -> latency(mid-turn); dequeue -> drop non-agent head
```

**B2. `smres.mjs <files…>`.** Classifies the `tool_result` of every SendMessage `tool_use` across all transcripts
(`find . -name '*.jsonl'`, excluding `journal`):
- `Resuming agent` → resumed-stopped-agent (2,741)
- `queued for delivery` → queued-to-running-agent (6,291)
- `another Claude session` → cross-session (21)
- other `success:true` → ok-other (3,901)
- permission or classifier refusals → blocked (39)
- `success:false` → failed (45), each kept with its reason

**B3. `i274.mjs <subagent files…>`.** For each agent transcript, in file order:
1. When the next record's timestamp is ≥ 5 min after the latest seen, a silent gap starts.
2. Within the next 25 records, look for a `queued_command` with `<task-notification>` (or a user record with
   `origin.kind=="task-notification"`) whose timestamp lies inside the gap and ≥ 30 s before the wake. That is a hit.
3. lostMin = wake − notification time.

Results: 214 hits, 65 agents, 1,996 min in total, p50 6.3 min, max 103 min, by day {09-30: 3, 10-01: 55,
10-02: 18, 10-03: 43, 10-04: 75, 10-06: 2, 10-12: 4, 10-13: 14}.

Limitation: a hit proves that a finished job's notice was written only after a wake. It does not prove the job's
result was needed at once. Treat the minutes as an upper bound on wasted wait.
