---
kind: kickoff-note
id: 08-chat-forensics/01-user-timeline
title: "v1 from the user's side: timeline, corrections, waits, attention and interfaces"
date: 2026-10-17
status: draft for user review
inputs: v1 chat digest (.local/v1-chat-digest/out), v1 console (threads, steps, proposals), v1 memory notes, raw lead transcript (timestamps only)
---

# v1 from the user's side (chat forensics 01)

**Lens.** What the user asked for, when, through which channel; where the user had to repeat, re-ask or override;
which moments became standing rules; how long the user waited on the loop and the loop on the user; how much
attention the loop took; what the user valued; which interfaces worked.

**Scope and privacy.** Read-only use of the v1 repo (`v1:` below), its console stores and the transcripts. No Fastwork
code, no personal data. The user's words are paraphrased; the few direct quotes are a handful of words, with
spelling normalised. Times and days are UTC.

**Status words.** **MEASURED**: computed from the data with the command named in brackets, e.g. [R5]; every command is
in the appendix and runs from the digest directory. **QUOTED**: the user's or the lead's own words, with thread and
message number (`T-154 #12`) or chat timestamp. **INFERRED**: my reading; not checked.

**Regex caveat.** The intent counts in §3 come from keyword regexes over message text [R12]. They are regex counts,
not a hand-labelled classification, and they can over-count as well as under-count. Example: the catch-up regex
matches a bare "progress", which also hits requests such as sorting or linking rows by progress. It gives 132 matches;
114 without the bare word; 68 messages actually say "catch up" [R12b].

---

## 0. Summary

1. **The user spent a lot of attention: 1,652 recorded actions in 13 days**: 218 chat messages, 989 console thread
   messages and 445 clicks on console steps. The peak was 4 Oct with 448 actions (MEASURED [R14]).
2. **Chat lasted 1.5 days.** 185 of the 218 chat messages came on the first two days. The user then moved to the
   console, because the main session had so many messages that it was hard to catch up on them (paraphrased, chat
   2026-10-01 14:19). After that, chat was used mostly for things the harness only accepts there: permission OKs,
   guard changes, rule approvals and "start the console" (MEASURED [R2]).
3. **Replies were fast, but the user had to pull the state.** Median first reply to a console message was 40 s (p90
   2.7 min), with a median of 129 words (MEASURED [R5]). Yet 132 user messages match the catch-up regex (68 say
   "catch up"), 32 of them bare one-liners. 39 overrode priorities and 25 asked what a status meant or
   what the user had to do (MEASURED [R12, R13]). The slow part was the **state the user could see**, not reply time.
4. **The user kept re-teaching the same management behaviour.** "Delegate" or "you are the bottleneck" came up 36
   times on 11 different days [R17]. "Investigate, workaround, long-term fix" came up 31 times [R12]. The lead itself
   wrote: "you asked me for this loop at least 15 times today, and my role instructions never said it" (QUOTED,
   T-154 #12, 4 Oct).
5. **40 standing rules (memory notes) were born from user moments.** 11 of them came on 4 Oct alone, the day of peak
   load (MEASURED [R11]; one note per user correction, INFERRED from each note's "Rule (user, T-…)" line).
   About a third concern **how the loop talks to the user** (§4).
6. **Most of what the console asked of the user was babysitting hardware.** Of 166 console steps, 105 (63 %) were
   device chores: re-plug the cable (28 steps, 13 of them later cancelled), unlock, Xcode thermal toggles (26),
   Do Not Disturb, Trust. Only 41 (25 %) asked for what only the user could give: a blind swipe or a visual judgement.
   From 6 to 8 Oct there were 53 chore steps and 4 perception steps (MEASURED [R6]).
7. **The loop also waited on the user.** Most steps were picked up within a minute (median 1 min, p90 20 min). But
   9 steps waited more than an hour, 2,573 min in total (MEASURED [R7], §6).
8. **What worked for the user (INFERRED from behaviour):**
   - the console's step buttons;
   - proposals with live Try-it pages: 41 proposals, 64 decisions, median 10 min from a revision to the decision [R9];
   - "comment on anything": 94 of the 198 user-created threads were opened from a comment button [R4];
   - the best-build page that the user could play on a **second iPhone**. Every enthusiastic "ultra smooth" came
     from the user's own hands on a build, not from a metric (§7).
9. **What did not work:**
   - stale or ambiguous status rows;
   - alarm threads in the user's inbox: 61 of the 80 lead-created threads were automated alarms [R4];
   - mega-threads;
   - the console dying with a background job;
   - permission prompts that needed the user present;
   - recurring check prompts the user had to type themselves: 1,889 "check iphone connection" fires [R10].

---

## 1. Channels and attention per day

| day (UTC) | chat | console msgs | step clicks | what dominated (INFERRED from the timeline) |
|---|---:|---:|---:|---|
| 30 Sep | 61 | 0 | 0 | setting up the team in chat |
| 1 Oct | 124 | 47 | 43 | the user as the phone test instrument; the console starts |
| 2 Oct | 1 | 62 | 37 | console era; camera privacy incident; recording the phone screen |
| 3 Oct | 1 | 72 | 18 | measurement protocol, thermal "Serious" profile, GPU research |
| 4 Oct | 2 | **330** | **116** | peak: status confusion, idle-phone alarms, "bottleneck", 11 new rules |
| 5 Oct | 6 | 122 | 41 | end-of-page push; article thread starts; article side session |
| 6 Oct | 0 | 56 | 36 | "we did it" on the end of the page; heavy device chores |
| 7 Oct | 0 | 46 | 57 | re-plug cascades; best-build thread |
| 8 Oct | 1 | 48 | 34 | real-heat tests; compositing-border hunt |
| 9 Oct | 2 | 41 | 19 | user declares the optimization done; recordings for the article |
| 10 Oct | 6 | 35 | 15 | article media; guard changes typed in chat |
| 11 Oct | 0 | 83 | 7 | demo deploy and wrap-up; the user stops the team |
| 12 Oct | 4 | 21 | 0 | distillation threads |
| 13 Oct | 8 | 26 | 22 | public release, history sync, teardown |

Source: MEASURED [R14]. Totals 218 / 989 / 445. Two more chat lines fall on 16 Oct (shutting the console down).

**Messages per day.** The user sent a median of about 52 console messages a day from 2 to 13 Oct, plus about 28 step
clicks (MEASURED, medians of the table rows).

---

## 2. Timeline by phase

Phase boundaries are my cut (INFERRED). The counts in the table use those boundaries [R18].

| phase (UTC) | chat | console msgs | steps posted | step clicks | proposals | decisions |
|---|---:|---:|---:|---:|---:|---:|
| P0 bootstrap: 30 Sep 17:00 to 1 Oct 00:00 | 61 | 0 | 0 | 0 | 0 | 0 |
| P1 chat phone loop: 1 Oct 00:00 to 20:20 | 124 | 0 | 14 | 33 | 0 | 0 |
| P2 console and proposals: 1 Oct 20:20 to 3 Oct | 2 | 181 | 21 | 65 | 13 | 20 |
| P3 peak load: 4 to 5 Oct | 8 | 452 | 35 | 157 | 13 | 23 |
| P4 convergence: 6 Oct to 9 Oct 11:00 | 2 | 173 | 68 | 144 | 15 | 21 |
| P5 publication: 9 Oct 11:00 to 11 Oct 17:30 | 7 | 136 | 16 | 24 | 0 | 0 |
| P6 distill and teardown: 11 Oct 17:30 to 17 Oct | 14 | 47 | 12 | 22 | 0 | 0 |

### P0 Bootstrap (30 Sep, chat only)

- 17:05: the user asks how to connect Safari on the iPhone and measure render performance. At 17:30 the user
  **re-frames** the session as an exploratory, educational probe of a laggy scroll on the phone.
- 17:56 to 19:21: the 4x desktop throttle is laggy too. The user asks for a local mirror, then for a calibration at
  4x/6x/20x. That request was typed three times in 70 s (18:30 to 18:31), an early resend (MEASURED, human.jsonl).
- 19:33 to 20:17: the user designs the team shape: subagents per topic in worktrees, Agent Teams "so agents can talk"
  and share one iPhone, Serena, tests for the tools, and a hard rule on rebase merges.
- 20:49: the user asks why the harness keeps asking for approval. This was the first permission friction.
- 21:35 to 23:26: a burst of process questions (paraphrased):
  - why some incidents were handled without spawning subagents;
  - why nobody used Chrome for testing;
  - why agents had to queue to commit;
  - and, at 23:05, that the lead should delegate as much as possible, because it was being interrupted a lot.
  - Then, at 23:26: why the lead had not seen an issue itself, so that the user had to gather the evidence.
- The user set up two recurring `/loop` prompts: "think about the improvement for team" and "check each agents…".

### P1 The user as the instrument (1 Oct, chat)

- 06:48 to 15:06: phone sessions run through chat. Of 146 chat messages that day, 68 have six words or fewer:
  "A done, still laggy", "B done", "same", "next", "go" (MEASURED [R16], spelling normalised). The lead asked settings questions
  (Reduce Motion, Low Power Mode, extensions) and the user answered them inline.
- 08:27: the user apologises for not following an instruction and asks to redo test E1 (paraphrased). There was no
  retry affordance.
- 12:05 to 12:08: the user challenges a platform claim and asks whether the team checked it against reference
  documents (paraphrased). This became `verify-platform-claims`.
- 13:50: the user teaches the perception method: lag is felt when the page does not follow the finger, so test with
  swipe A/B (paraphrased). This became `perception-tests-touch-ab`.
- 14:19: the user asks for a web tool that lists the questions, so they can click Start and answer when ready,
  because the chat is too busy to follow. The console was opened at 15:43, and the first step (C-001) was posted
  at 15:32.
- 15:27 to 15:38: the user reads the plan usage meter aloud (session usage in the high 80s, then 91 %). That led to
  a usage `/loop` and later T-010.
- 17:29: the user had already clicked Done on step C-009 and asks why the lead did not notice (paraphrased). This
  became `console-step-wait-yourself`.
- 17:34: the user creates `/loop 5m check iphone connection`. It fired **1,889 times** (MEASURED [R10]).
- 19:00: the user asks the lead directly to investigate itself: about a day had passed and the goal was still far
  away (paraphrased).

### P2 Console and proposals (1 Oct 20:20 to 3 Oct)

- The first threads are user DIRECTION threads (T-001 style recalculation, T-005 "pick 2 fixes") and the first
  proposal (PR-001).
- PR-001: the user changed a decision from reject to changes-requested, and the change was not picked up (T-005 #6,
  T-007). This became `proposal-decision-is-the-spec`.
- 2 Oct: the console died; it had been run as a 2-hour background job (T-012). A "Finish Recording" popup and an
  automation that **turned on the Mac camera** led the user to ask agents never to access the camera, as a privacy
  issue (T-018 #1, paraphrased). The user also asked to keep the log as evidence of the mistake (T-018 #5). This
  became `no-camera-access`.
- The user proposed ideas that became research or rules:
  - countdown re-rendering while hidden (T-024);
  - GPU-accelerated properties (T-030);
  - heat as a goal (T-029);
  - the Serious thermal profile (T-039). This became `phone-checks-start-warm` and `milestone-2-heat-profiles`.
- UI requests: show who a reply goes to (T-038); comments anywhere, "likes claude artifacts" (T-043); talk inside a
  proposal (T-048).

### P3 Peak load and the management crisis (4 to 5 Oct)

- 452 console messages and 157 step clicks in two days (MEASURED [R18]).
- **Status confusion.** At 03:46 the user asks what a row means and what they have to do, on three status rows within
  one minute (T-059, T-060, T-061), and again on T-064, T-065, T-068 and T-069. Rows said "parked" or "done" when they
  were not (T-124, T-125). "Waiting for a user reply" showed with nothing to answer (T-070).
- **Readability.** The user found the answers hard to read and asked for a rule (T-080 #1, paraphrased). This
  became `answer-format`. On 7 Oct the user still saw raw tables (T-230).
- **Phone idling.** 23 idle-phone alarm threads on 4 Oct alone (MEASURED [R4b]). The user asked why the team had not
  found this incident first, and said they expected the team to find such things before the user had to ask (T-149
  #3, paraphrased). This became `idle-alarms-are-a-pattern` and `lead-delegates-areas-measures`.
- **Bottleneck.** The user told the lead it was the bottleneck: when the user asked for catch-ups in many threads,
  the lead got slower (T-105 #18, paraphrased), and repeated it a few messages later (T-105 #23).
- **Being the user's step queue.** Steps were blocking each other (T-078 #8, sent twice). "Start over" sat for
  588 s (C-037) [R8]. The user asked the lead to trace a lag itself instead of asking (T-087 #7, paraphrased). These
  became `one-phone-step-at-a-time` and `trace-before-asking`.
- **Proactivity.** The user said the team should not have reactive agents that wait for orders (T-160 #7,
  paraphrased). This became `proactive-by-default`, with an hourly team report (T-163, 171 agent messages, 4 from
  the user).
- **Breakthroughs the user felt.** The user called the best build very smooth, played on a second iPhone (T-111 #6,
  12:01), and PR-021 "ultra smooth" (T-154 #2).
- **Article.** The article thread starts on 4 Oct at 23:33 (T-170, which grew to 500 messages, 210 from the user).
  The user opened a **second Claude Code session** for article editing. Its whole chat is "approved permission" and
  "go", nine times (MEASURED [R1]: lead:e978e7c9 rows).

### P4 Convergence on the end of the page (6 Oct to 9 Oct 11:00)

- DIRECTION T-204: focus only on this optimization (5 Oct 22:40). On 6 Oct at 03:25 the user called it ultra smooth
  and wrote "we did it" (T-204 #8).
- The user pushed method rules:
  - read engine source instead of searching for bug reports (T-221, which became `read-source-first`);
  - turn breakthroughs into practices (T-224, which became `breakthroughs-become-practices`);
  - allow any end-of-page test on a free phone (T-204 #35).
- **Device chores peak.** 53 chore steps and 4 perception steps from 6 to 8 Oct [R6]. On 6 Oct alone there were six
  re-plug steps in two hours (C-082 to C-087). The user diagnosed a USB-port change (T-222 #5). Then the user asked
  that an unrequested phone disconnect be investigated and fixed first, before asking the user (T-256 #1,
  paraphrased). This became `phone-problems-fix-first`.
- T-228 "Did you update the best build ?" grew to 168 messages and became the best-build channel (`best-builds-list`).
- 9 Oct 10:56: the user declared the iPhone rendering optimization done and congratulated the team (T-264 #1,
  paraphrased).

### P5 Publication (9 Oct 11:00 to 11 Oct)

- Article media, where the user drove the choices: GIF size, video hosting, 60 fps, alt-text limits. Chat was used
  only for **guard changes** that the hook accepts only from the user. The user typed three of these in chat on 9 and
  10 Oct, after the lead posted console steps to "paste this line" (C-155, C-156; that rule is `chat-lines-as-steps`).
- A protected demo deploy and wrap-up. 17:26 on 11 Oct: the user asked to stop the team gracefully (T-274,
  paraphrased).

### P6 Distillation and teardown (12 to 17 Oct)

- T-275 asks for a knowledge distillation and "delegate agent team instead of to dynamic workflow" (which became
  `agent-teams-not-workflows`). T-277 asks how the lead built the loop. Public release approvals were typed in chat
  on 13 Oct. Console start and teardown requests came on 12, 13 and 16 Oct. On 12 Oct the user had to ask again
  whether the observer had been started, as already requested in a thread (paraphrased), which became the "start the
  console fully" note.

---

## 3. Corrections and frustrations

| pattern | count | example (QUOTED or MEASURED) | did it stop? |
|---|---:|---|---|
| Pull for status ("catch up", "progress", "any update") | 132 regex matches (114 console, 18 chat) [R12]; 114 without the bare word "progress", 68 say "catch up" [R12b]; 32 bare one-liners [R13] | four catch-up one-liners in 90 s on 4 Oct 13:33 to 13:37 | No. It continued until the end, on T-159 and T-228 (INFERRED from the timeline) |
| "What it means / what do I need to do" | 25 [R12] | the same question on 3 status rows in 1 min (T-059 to T-061) | Partly: `console-steps-only-for-actions`, answer format |
| Priority overrides ("mark X as highest priority") | 39 [R12] | the user asked why the status page still showed only one fix as top priority (T-159 #18, paraphrased) | No. It ran to 8 Oct (T-253 #24/#25, sent twice) |
| Re-teaching the issue loop (workaround / long-term) | 31 [R12] | the user said they had asked for this many times and the lead had forgotten (T-154 #11, paraphrased) | Became a rule on 4 Oct (`lead-owns-issue-loop`) |
| Lead critique (bottleneck, proactive, responsibility) | 36 [R12] | the user told the lead it was the bottleneck and to delegate (T-216 #4, 6 Oct, paraphrased) | Recurred on 11 days [R17] |
| Same message resent in the same thread within 10 min | 4 in the console (T-078, T-104, T-134, T-253) + 1 triple in chat | (MEASURED; [R13] variant) | INFERRED cause: no visible "received/working" state |
| Privacy | 1 incident | camera turned on by automation (T-018) | Yes: `no-camera-access`, no repeat found |
| Permission and harness prompts | ≥ 25 chat lines were approvals, "go" or guard text [R19] | a side session where the user only clicked approvals | No |
| Console infrastructure failures the user noticed | T-012 (console died), T-078/T-087 (start over), T-089 (unseen counter), T-116 (step stuck "getting ready") | — | Mostly fixed one by one |

**Repeated after the rule existed** (so a memory note was not enough):
- Tables rendering raw on 7 Oct, after `answer-format` on 4 Oct (T-230).
- Unnamed spawns on 3 Oct, after `agent-spawn-names` on 1 Oct (T-032; the note records the slip).
- An incomplete console start on 12 Oct, after `console-server-detached` on 2 Oct (chat 12 Oct 09:34).
- Delegation, again on 6, 11 and 12 Oct (`lead-delegates-research` on 11 Oct, `agent-teams-not-workflows` on 13 Oct).

---

## 4. Moments that created standing rules

There are 40 memory notes. By creation day: 1 Oct 9, 2 Oct 6, 3 Oct 4, 4 Oct 11, 6 Oct 2, 7 Oct 1, 8 Oct 2,
9 Oct 1, 10 Oct 1, 11 Oct 1, 13 Oct 2 (MEASURED [R11]; four notes have no `since:` line and are dated from their
text). Grouped by what they fix (INFERRED):

| group | notes | the user moment behind them (channel) |
|---|---|---|
| **How the loop talks to the user (14)** | `user-tasks-via-console`, `console-step-wait-yourself`, `console-server-detached`, `user-steps-first`, `no-phone-steps-during-blocks`, `console-steps-only-for-actions`, `one-phone-step-at-a-time`, `answer-format`, `trace-before-asking`, `proposal-try-it-required`, `proposal-revision-visible`, `proposal-decision-is-the-spec`, `best-builds-list`, `chat-lines-as-steps` | chat 1 Oct 14:19 and 17:29; T-012; T-017; C-027; C-031 note; T-078; T-080; T-087; T-063; T-154; T-005/T-007; T-228; T-170 #149 |
| **How the lead manages (9)** | `lead-owns-issue-loop`, `lead-delegates-areas-measures`, `lead-delegates-research`, `proactive-by-default`, `busy-workers-answer-later`, `idle-alarms-are-a-pattern`, `agent-spawn-names`, `agent-teams-not-workflows`, `usage-meter-every-30-min` | T-154; T-149; T-170 #343; T-160 #7; T-147; T-149 #3; chat 1 Oct 10:26 and T-032; T-275 #3; T-010 |
| **Method (12)** | `verify-platform-claims`, `read-source-first`, `perception-tests-touch-ab`, `defer-timing-focus-call-tree`, `simulator-for-non-perf-phone-jobs`, `illusion-must-be-pixel-identical`, `less-work-landing-rule`, `phone-checks-start-warm`, `milestone-2-heat-profiles`, `heat-probe-for-blog`, `breakthroughs-become-practices`, `phone-problems-fix-first` | chat 1 Oct 12:05, 13:50, 17:45, 19:00; T-221; PR-001; T-029 #30; T-039; T-162 #3; T-247 #10; T-224; T-256 |
| **Safety, privacy, publishing (5)** | `no-camera-access`, `keep-awake-only-during-measurements`, `deck-recording-pictures`, `github-via-gh`, `public-release` | T-018; C-024; chat 9 and 10 Oct; T-071; chat 13 Oct |

**Reading (INFERRED).**
- About 35 % of the rule book is "how to talk to the user" and was learned by friction, not designed in advance.
- The lead-management rules were learned last and broken most often (§3).
- Almost every rule has a user complaint as its "Why" line. The loop had no way to find these failure classes before
  the user hit them.

---

## 5. Requests the loop handled well and badly

**Well** (each with evidence):
- **Fast, substantive replies.** Console: median 40 s to a first reply of about 129 words [R5]. Chat on day 1-2:
  median 24 s, p90 69 s to the first lead text [R15].
- **Building the requested tool quickly.** The console went from the user's ask (1 Oct 14:19) to first use
  (C-001, 15:32) in about 70 min. The comment buttons the user asked for on 3 Oct (T-043) carried 94 later threads [R4].
- **The decision loop for look changes.** 41 proposals with 93 revisions in total. 64 user decisions: 39 accepted,
  22 changes requested, 3 rejected. Median 10 min from the latest revision to the decision, p90 340 min [R9].
- **Capturing rules.** 40 notes in 13 days, each with the triggering thread (MEASURED [R11]).
- **Reaching the outcome the user cared about.** The user, judging by their own swipes, said "we did it" on 6 Oct
  and "all done" on 9 Oct (QUOTED, T-204 #8, T-264 #1).

**Badly:**
- **Status and progress visibility.** 132 catch-up regex matches (§3); stale or ambiguous rows (T-060 #3: the user
  saw a lot of outdated status, paraphrased).
- **Using the phone as a shared resource.** 55 idle-phone alarm threads with 1,217 stated idle minutes, posted into
  the user's inbox (MEASURED [R4b]). The user found the cause class before the lead did (T-149 #3).
- **Device reliability.** 28 re-plug steps, 26 Xcode thermal steps [R6]. On the user's side, the most common step was
  physical, not perceptual.
- **Keeping its own process.** Rules that were broken again after they were written (§3). The user acted as process
  coach; the lead's role file did not carry the coaching (T-154 #12).
- **Harness friction.** Approvals in a side session; guard text typed by hand; a console that died with a background
  job (T-012).

---

## 6. Wait times

**The user waiting on the loop:**

| wait | value | source |
|---|---|---|
| console message to first reply | median 40 s, p90 2.7 min; 3 of 985 over 30 min | MEASURED [R5] |
| chat message to first lead text (30 Sep to 1 Oct) | median 24 s, p90 69 s | MEASURED [R15] |
| user pressed Start on a step, to the agent's "ready/recording" | median 5 s, max 81 s (C-052) | MEASURED [R8] |
| user pressed Start over, to "ready" | median 19 s, max 588 s (C-037; T-078 "it stuck on Getting page 1 ready") | MEASURED [R8] |
| asked for a change, to a visible proposal revision | hours in some cases ("after your change request the page showed nothing for hours", lead, T-154 #10) | QUOTED |
| the user said they would not wait long and asked for faster (paraphrased) | 1 Oct 11:57, 12:40; T-017 #3; T-116 #5 | QUOTED (paraphrased) |

**The loop waiting on the user (steps):**
- 145 steps with a user action: median 1 min from posting to the first user action, p90 20 min (MEASURED [R7]).
- 9 steps waited more than 60 min, 2,573 min in total. C-140 waited 700 min, C-035 565 min, and C-090 and C-091
  about 6 h each. In these cases the team was **blocked for hours on a phone chore or a swipe while the user was
  away** (MEASURED [R7]).
- The user did 355 minutes of hands-on work inside perception steps (first to last click per step), against 27 minutes
  for chores. Chores were short but frequent and interrupting (MEASURED [R20]).

---

## 7. What the user valued (INFERRED from behaviour, with evidence)

1. **Feel under the finger, judged personally.** Every superlative ("so smooth", "ultra smooth"; 8 matching lines
   [R19b], plus the T-264 title) came right after the user played a build on the phone (T-111 #6, T-154 #2, T-170 #1,
   T-204 #8, T-253 #15, T-228 #167). The user asked for Try-it on every proposal (T-062, T-063) and for every best
   build as a link (T-076, T-079).
2. **Understanding, not just results.** There were 73 messages asking to explain, the technique behind, the math,
   or how (regex count, [R19b]). Examples: asking for the technique behind a change (T-193 #3), and for an
   explanation with visuals and the math (T-275 #6) (paraphrased).
3. **Evidence for a write-up.** There were 74 messages about evidence, the article or a blog [R19b]. Examples: keeping
   evidence for the article (T-216 #3) and keeping a log as evidence of a mistake (T-018 #5) (paraphrased).
4. **Look fidelity.** PR-001 rev 1 was rejected for changing the visual. This became `illusion-must-be-pixel-identical`.
5. **Autonomy of the team.** The user wanted proactive agents, owners per area, and the lead as decider, not router
   (T-160 #7, T-134 #11, T-149 #12).
6. **Privacy and control.** No camera (T-018). Only the user publishes (`public-release`). Approval for release rules
   typed by the user (chat, 13 Oct).
7. **Cost awareness.** The user read out plan usage by hand 12 times (regex count [R19]) and asked for cheaper models
   (T-196 #1, 5 Oct).

---

## 8. Which user-facing interfaces worked

| interface | evidence | verdict (INFERRED) |
|---|---|---|
| **Chat with the lead** | 185 of 218 messages on days 1-2; the user left it because it was too busy to follow (chat 1 Oct 14:19); later only for harness-only lines | Worked for set-up and steering; failed as a status surface and as a step queue |
| **Console threads** | 989 user messages, 278 threads (198 user, 80 lead); fast replies [R5]; but T-170 has 500 messages, T-010 has 220 agent messages to 3 user messages, T-163 has 171 to 4; 61 of 80 lead threads were alarms [R4] | Good for one question in one thread; bad as a log of reports and alarms |
| **Console steps ("Your steps")** | 166 steps; 63 % chores; one-at-a-time and wait-yourself rules needed; start-over stalls | The right shape (Start, answer, next). It was overloaded with hardware care |
| **Proposals with Try-it** | 41 proposals, 64 decisions, median 10 min [R9]; the user demanded Try-it as required | Worked best of all |
| **Comment-anywhere** | 94 user threads opened from comment buttons on proposals (18), threads (17), status rows (16), the best-build page (12), steps (10), progress (14), other pages (7) [R4c] | Worked; it is how the user asked "what does this row mean" |
| **Best-build page + second phone** | very smooth on another device (T-111 #6); no need to queue, because the user had another device (T-144 #5) (paraphrased) | Worked; it took the user off the measurement phone queue |
| **claude.ai artifacts** | 47 user messages mention artifacts [R19b]; used for article drafts, visual explainers and distillations; the user commented on artifacts and asked the lead to read the comments (T-170 #213, #410, #421) | Worked for long-form review and visual explanation |
| **A side Claude Code session** | its chat is 9 lines of "approved permission" or "go" [R1] | Did not work: the user acted as a permission clicker |

---

## Improvements for v2

Each item names the change, the evidence, and the PLAN.md (rev 2) section it changes.

1. **Make the console the user's only channel from the first phone touch, not Day 9.**
   - *Evidence:* the user left chat on day 2 (185 of 218 chat lines on days 1-2; too hard to catch up, chat 1 Oct
     14:19). On 1 Oct, 68 of 146 chat lines were one-line test answers [R16].
   - *Change:* a minimal step queue (post, Start, answer, Done; the API from §3.2) ships before the first device or
     Simulator step. The console skeleton in §10.2 moves from Day 9 to Day 3-4, with steps only. Chat stays for lines
     the harness accepts only from the user.
   - *PLAN:* §10.2 (Day 3-4 and Day 9), §10.1 M0 content.
2. **Every status row carries "needs you: yes/no + the exact action" and the age of its last event.**
   - *Evidence:* 25 "what does it mean / what do I need to do" [R12]; the fan-out of T-059 to T-069; "parked" vs
     "done" (T-124, T-125); "waiting for you" with nothing to answer (T-070).
   - *Change:* add both fields to the status projection contract. "needs you" may only be set by an open step or
     proposal event, never by an agent's self-report.
   - *PLAN:* §3.2 (console-api contract), §2.2 "One writer … status as a projection".
3. **Push a digest; don't make the user pull.**
   - *Evidence:* 132 catch-up regex matches (68 say "catch up"), 32 bare one-liners [R12, R13]; the user called the
     lead the bottleneck because catch-ups across many threads slowed it down (T-105 #18, paraphrased).
   - *Change:* `pnpm fw status` writes one digest per experiment-card stage change: stage, owner, next step,
     expected time. It goes to the experiment card page, not to a thread. The lead answers "catch up" by linking the
     card.
   - *PLAN:* §9.2 (add a "visible stage + next ETA" column per stage), §8.4 "Reporting".
4. **Machine alarms never go to the user's inbox.**
   - *Evidence:* 61 of 80 lead-created threads were automated alarms, 55 of them idle-phone alarms (23 on 4 Oct)
     [R4]. Report threads T-010 and T-163 were 220 and 171 agent messages against 3 and 4 user messages.
   - *Change:* alarms go to an ops log in console-api, owned by a script. The user sees one counter. A thread is
     opened only when a human decision is needed.
   - *PLAN:* §3.2 (console-api), §8.2 ("(no agent) scripts and hooks" row).
5. **Budget and automate device chores; count them as a metric.**
   - *Evidence:* 105 of 166 steps (63 %) were chores; 28 re-plug steps (13 cancelled); 26 Xcode thermal steps; 53
     chores vs 4 perception steps on 6 to 8 Oct [R6]; "investigate to fix first" (T-256 #1); 1,889 "check iphone
     connection" fires [R10].
   - *Change:* add a G2 sub-metric, **"user chore steps per phone session ≤ 2"**. A device-health script (link, lock
     state, thermal state, Do Not Disturb) runs before any step is posted, and it repairs before it asks. Settle the
     thermal-state control (CLI or a fixed profile) in Q1 before M3.
   - *PLAN:* §1.1 G2, §4.1 device lane, §12.1 Q1, §11 (new risk: device babysitting load).
6. **Phone time in sessions the user books; nothing posted outside them.**
   - *Evidence:* 9 steps waited over 60 min (2,573 min), the longest 700 min, while the user was away [R7].
   - *Change:* the user declares windows; the loop batches device steps into a session plan with a stated length;
     outside a window, device work queues and the team works on the counts lane.
   - *PLAN:* §12.2 Q7 (device budget gets "sessions in user-declared windows"), §4.1, §10.1 M3.
7. **A perception step is posted only when both arms are pre-loaded and verified.**
   - *Evidence:* Start-over up to 588 s (C-037) [R8]; the user asked for faster starts (T-116 #5); a redo of test E1
     had no retry button (chat 1 Oct 08:27).
   - *Change:* a step has a "ready" gate checked by script (both URLs answer, the inspector is attached, phone
     unlocked) before it shows; built-in retry per part.
   - *PLAN:* §9.2 device stage, §3.2 (step contract).
8. **Put the user's coaching in the role files on Day 1.**
   - *Evidence:* 31 issue-loop re-asks; 36 delegation and bottleneck asks on 11 days [R12, R17]; the lead: "you asked
     me for this loop at least 15 times today, and my role instructions never said it" (T-154 #12).
   - *Change:* the lead file and the root CLAUDE.md carry four lines from v1 memory:
     - issue loop (cause from data, workaround, long-term fix with owner);
     - proactive by default;
     - trace before asking;
     - answer format.
   - Each line names its enforcer (answer-lint, step gate).
   - *PLAN:* §8.2 (lead row and role files), §2.1 Keep table (add these four), §2.2 rulebook row (still under 300
     words).
9. **The user owns one ordered priority list.**
   - *Evidence:* 39 priority overrides [R12]; the user asked why only one fix showed as top priority (T-159 #18) and
     asked to rank every fix related to one build as top priority (T-133 #6) (paraphrased).
   - *Change:* `presets/priority.json` (or a console list) that the user drags; the experiment queue reads it; agents
     never set priority.
   - *PLAN:* §9.1/§9.2 (the question stage reads the user priority list), §3.3 (where the decision runs).
10. **Keep the interfaces that worked as first-class features.** Keep Try-it, comment-anywhere, a preset gallery
    served on Wi-Fi, and a second "free-play" phone.
    - *Evidence:* Try-it proposals had a median 10-min decision [R9]; 94 of 198 user threads came from comment
      buttons [R4c]; the best felt results came from the user playing builds on a second phone (T-111 #6, T-144 #5).
    - *Change:* M1's console skeleton includes comments on any row and a preset gallery with Wi-Fi links. Q1 asks
      whether the second iPhone can be a free-play device kept out of measurement.
    - *PLAN:* §2.1 Keep table ("Proposals with Try-it" row), §10.1 M1, §12.1 Q1.
11. **No chat-only approvals in the middle of work.**
    - *Evidence:* at least 25 chat lines were approvals, "go" or guard text [R19]; a side session where the user only
      clicked approvals; guard changes typed by hand three times on 9 and 10 Oct.
    - *Change:* batch every `.claude/**` and guard change into planned sittings (as §8.1 already does for Day 1 and
      Day 3). Run `fewer-permission-prompts` after each new tool. No second Claude Code session for side tasks; use a
      named teammate.
    - *PLAN:* §8.1 Bootstrap order, §8.3 Notes.
12. **Show plan usage in the console header.**
    - *Evidence:* the user reported usage percentages by hand 12 times [R19]; a 30-minute usage cron fired 334 times
      [R10].
    - *Change:* `pnpm fw usage` feeds a header badge; the lead never asks the user for a percentage.
    - *PLAN:* §8.4 Reporting, §3.1 console-web.
13. **One question, one thread, closed on answer; reports never in threads.**
    - *Evidence:* T-170 had 500 messages; T-228 had 168; replies landed in closed threads, so the unseen counter
      stuck (T-089 #5); the user asked to merge duplicates (T-024 #13).
    - *Change:* threads auto-close with "related" links; long-running topics become pages (article, best builds),
      not threads.
    - *PLAN:* §3.2 console contract, §3.4 (Thread stays "later", but the hygiene rules go in the MVP).
14. **Plan for the write-up as an outcome.**
    - *Evidence:* 74 evidence/article/blog messages [R19b]; the user kept recordings and logs for the article (T-216
      #3, T-049 #27).
    - *Change:* add an outcome goal "write-up material": every landed experiment card has a 1-paragraph plain summary
      and a reproducible clip or chart reference; nothing on the evidence list is deleted by cleanup.
    - *PLAN:* §1.1 (new G4), §7.3, §10.1 M6.

---

## Appendix: reproduce every number

Run from the digest directory, `fastwork-com-web-optimize-lean/.local/v1-chat-digest/out`. Needs `jq` and Node.

```bash
V1C=../../../../fastwork-com-web-optimize/console          # v1 console (read-only)
V1M=../../../../fastwork-com-web-optimize/memory           # v1 memory notes
RAW=~/.claude/projects/<v1-project-dir>                    # raw v1 transcripts
CM=$(mktemp)                                               # flattened console thread messages
# R0: flatten console threads to one JSON line per message
node -e 'const fs=require("fs"),d=process.argv[1]+"/threads";for(const f of fs.readdirSync(d).filter(f=>f.endsWith(".json"))){const t=JSON.parse(fs.readFileSync(d+"/"+f));for(const m of t.messages)console.log(JSON.stringify({tid:t.id,title:t.title,n:m.n,at:m.at,by:m.by,text:m.text}))}' $V1C > $CM
```

```bash
# R1: chat messages by source (typed 180, queued 23, suggestion_accepted 15, none 11); per session: change .src to .who
jq -r '.src//"none"' human.jsonl | sort | uniq -c
# R2: chat messages (with a source) per UTC day
jq -r 'select(.src)|.ts[0:10]' human.jsonl | sort | uniq -c
# R3: console user messages per UTC day (total 989)
jq -r 'select(.by=="user")|.at[0:10]' $CM | sort | uniq -c
# R4: thread creators (user 198, lead 80) / R4c: user threads from comment buttons (94) / R4: lead alarm threads (61)
cat $V1C/threads/T-*.json | jq -r .createdBy | sort | uniq -c
cat $V1C/threads/T-*.json | jq -r 'select(.createdBy=="user")|.title' | grep -c '^Comment on'
cat $V1C/threads/T-*.json | jq -r 'select(.createdBy=="lead")|.title' | grep -cE '^(iPhone (held|free)|Chrome slot free|Disk nearly full|PR-[0-9]+: revision)'
# R4b: idle-phone alarm threads (55), per day, and the sum of stated idle minutes (1,217)
cat $V1C/threads/T-*.json | jq -r 'select(.createdBy=="lead" and (.title|test("^iPhone (held|free)")))|"\(.createdAt[0:10]) \(.title|capture("(?:(?<h>[0-9]+) h )?(?<m>[0-9]+) min")|((.h//"0"|tonumber)*60+(.m|tonumber)))"' | awk '{d[$1]++; s+=$2} END{for(k in d) print k, d[k]; print "minutes", s}'
# R4c: what the comment threads were attached to
cat $V1C/threads/T-*.json | jq -r 'select(.createdBy=="user")|.title' | grep '^Comment on' | sed -E 's/^Comment on (the )?(T-[0-9]+|PR-[0-9]+|C-[0-9]+|status|progress|[A-Za-z ]+ page).*/\2/; s/T-[0-9]+/thread/; s/PR-[0-9]+/proposal/; s/C-[0-9]+/step/' | sort | uniq -c
# R5: first reply latency to a user console message, and reply length
node -e 'const L=require("fs").readFileSync(process.argv[1],"utf8").trim().split("\n").map(JSON.parse),T={};for(const m of L)(T[m.tid]=T[m.tid]||[]).push(m);const d=[],w=[];for(const k in T){const a=T[k].sort((x,y)=>x.n-y.n);a.forEach((m,i)=>{if(m.by!="user")return;const r=a.slice(i+1).find(x=>x.by!="user");if(r){d.push((new Date(r.at)-new Date(m.at))/6e4);w.push(r.text.split(/\s+/).length)}})}const q=(a,p)=>[...a].sort((x,y)=>x-y)[Math.floor(p*(a.length-1))];console.log("n",d.length,"med_min",q(d,.5).toFixed(2),"p90",q(d,.9).toFixed(1),"over30",d.filter(x=>x>30).length,"reply_words_med",q(w,.5))' $CM
```

```bash
# R6: console steps by kind of ask (perception 41, device 105, other 20), cancelled, per day; re-plug and thermal subsets
cat $V1C/steps/C-*.json | jq -s -r 'map(. as $s|(if ($s.kind=="swipe-pair" or ($s.title|test("which page|smoother|look the same|felt|Fast flicks|Follow-the-finger|render test|Try the|blinking|own finger|Where did|clips|look check|Safari check";"i"))) then "perception" elif ($s.title|test("re-?plug|unlock|cable|USB|thermal|heat|Serious|Do Not Disturb|Auto-Lock|UI Automation|Trust|Wi-Fi|Safari|QuickTime|tab|record the iPhone|connection|off the Mac|Reconnect|Xcode|iPhone ready|iPhone is yours|test runs about|camera";"i")) then "device" else "other" end) as $c|{c:$c,d:$s.createdAt[5:10],x:($s.status=="cancelled")})|group_by(.c)[]|"\(.[0].c) \(length) cancelled=\(map(select(.x))|length) "+(group_by(.d)|map("\(.[0].d):\(length)")|join(" "))'
cat $V1C/steps/C-*.json | jq -r 'select(.title|test("re-?plug|USB link";"i"))|.status' | sort | uniq -c
cat $V1C/steps/C-*.json | jq -r 'select(.kind=="action" and (.title|test("thermal|heat setting|heat condition|Serious";"i")))|.id' | wc -l
# R7: minutes from posting a step to the user's first action (median, p90, count and sum over 60 min)
cat $V1C/steps/C-*.json | jq -r '(.history|map(select(.who=="user"))|.[0].at) as $u|select($u!=null)|((($u|sub("\\.[0-9]+Z$";"Z")|fromdate)-(.queuedAt|sub("\\.[0-9]+Z$";"Z")|fromdate))/60|floor)' | sort -n | awk '{a[NR]=$1; if($1>60){n++; s+=$1}} END{print "n",NR,"median",a[int((NR+1)/2)],"p90",a[int(NR*0.9)],"over60",n,"sum_over60_min",s}'
#     the same steps listed by id and wait:
cat $V1C/steps/C-*.json | jq -r '(.history|map(select(.who=="user"))|.[0].at) as $u|select($u!=null)|((($u|sub("\\.[0-9]+Z$";"Z")|fromdate)-(.queuedAt|sub("\\.[0-9]+Z$";"Z")|fromdate))/60|floor) as $w|select($w>60)|"\(.id) \($w)m"'
# R8: seconds from the user's Start / Start over to the agent's ready/recording ack
cat $V1C/steps/C-*.json | jq -r '.id as $id|.history as $h|range(0;$h|length) as $i|select($h[$i].who=="user" and ($h[$i].action=="start" or $h[$i].action=="restart"))|([$h[$i+1:][]|select(.who!="user" and .action=="ack" and (.state=="ready" or .state=="recording"))][0]) as $n|select($n!=null)|"\($h[$i].action) \((($n.at|sub("\\.[0-9]+Z$";"Z")|fromdate)-($h[$i].at|sub("\\.[0-9]+Z$";"Z")|fromdate))) \($id)"' | sort -k2 -n | awk '{c[$1]++; v[$1,c[$1]]=$2; last[$1]=$2" "$3} END{for(k in c) print k,"n",c[k],"median_s",v[k,int((c[k]+1)/2)],"max",last[k]}'
# R9: proposals, revisions, decisions, minutes from the latest revision to the decision
node -e 'const fs=require("fs"),d=process.argv[1];let n=0,r=0,v={},l=[];for(const f of fs.readdirSync(d).filter(f=>f.endsWith(".json"))){const p=JSON.parse(fs.readFileSync(d+"/"+f));n++;r+=p.rev||1;for(const x of p.decisions||[]){v[x.value]=(v[x.value]||0)+1;const rv=(p.revisions||[]).filter(y=>y.at<=x.at).pop();if(rv)l.push((new Date(x.at)-new Date(rv.at))/6e4)}}l.sort((a,b)=>a-b);console.log("proposals",n,"revisions",r,v,"decide_med_min",l[l.length>>1].toFixed(0),"p90",l[Math.floor(.9*(l.length-1))].toFixed(0))' $V1C/proposals
# R10: scheduled (cron / /loop) fires by prompt
grep -h '"scheduled_task_fire"' $RAW/*.jsonl | jq -r '"\(.cron) \(.prompt[0:45])"' | sort | uniq -c | sort -rn
# R11: memory notes per creation day (36 dated + 4 undated = 40)
grep -h '^since:' $V1M/*.md | sort | uniq -c; ls $V1M/*.md | grep -vc README
```

```bash
# R12: intent regex counts over typed/queued chat + console user messages
(jq -c 'select(.src=="typed" or .src=="queued")|{ch:"chat",t:.text}' human.jsonl; jq -c 'select(.by=="user")|{ch:"console",t:.text}' $CM) | node -e 'const C={catchup:/catch ?up|progress|any update|^status|how it going|finish(ed)? yet|is it done|what.?s about|what.?re (you|they) doing/i,confused:/what (it|this|does it) mean|what (do )?i (need|have) to do|ambiguous|hard to (read|understand|catch)|confus|didn.?t understand/i,priority:/highest priority|higher priority|prioriti/i,issueLoop:/workaround|long[- ]term/i,leadCritique:/bottleneck|before me|proactive|responsib|authority|you forgo|told you|why you don.?t|why it need me/i,delegate:/delegat/i};const o={};require("fs").readFileSync(0,"utf8").trim().split("\n").map(JSON.parse).forEach(m=>{for(const k in C)if(C[k].test(m.t)){o[k]=o[k]||{chat:0,console:0};o[k][m.ch]++}});console.log(JSON.stringify(o))'
# R12b: catch-up regex with and without the bare word "progress", and messages that say "catch up" (132 / 114 / 68)
(jq -c 'select(.src=="typed" or .src=="queued")|{t:.text}' human.jsonl; jq -c 'select(.by=="user")|{t:.text}' $CM) | node -e 'const W=/catch ?up|progress|any update|^status|how it going|finish(ed)? yet|is it done|what.?s about|what.?re (you|they) doing/i,N=new RegExp(W.source.replace("|progress",""),"i");let w=0,n=0,c=0;require("fs").readFileSync(0,"utf8").trim().split("\n").map(JSON.parse).forEach(m=>{w+=W.test(m.t);n+=N.test(m.t);c+=/catch ?up/i.test(m.t)});console.log(w,n,c)'
# R13: bare catch-up one-liners (32); same-thread resends within 10 min: compare consecutive user texts per tid
jq -r 'select(.by=="user")|.text' $CM | grep -ciE '^(catch up this( progress)?\.?|catch up the progress\.?|what.?s about this progress ?\??|any update ?\??)$'
# R14: user actions per UTC day: chat, console messages, step clicks (totals 218 / 989 / 445)
node -e 'const fs=require("fs"),[h,c]=process.argv.slice(1),D={},add=(t,k)=>{const d=t.slice(0,10);D[d]=D[d]||{chat:0,console:0,steps:0};D[d][k]++};fs.readFileSync(h,"utf8").trim().split("\n").map(JSON.parse).filter(m=>m.src).forEach(m=>add(m.ts,"chat"));for(const f of fs.readdirSync(c+"/threads").filter(f=>f.endsWith(".json")))JSON.parse(fs.readFileSync(c+"/threads/"+f)).messages.filter(m=>m.by=="user").forEach(m=>add(m.at,"console"));for(const f of fs.readdirSync(c+"/steps").filter(f=>f.endsWith(".json")))JSON.parse(fs.readFileSync(c+"/steps/"+f)).history.filter(x=>x.who=="user").forEach(x=>add(x.at,"steps"));for(const d of Object.keys(D).sort())console.log(d,D[d].chat,D[d].console,D[d].steps)' human.jsonl $V1C
# R15: chat (30 Sep to 1 Oct 20:20) to the first lead text reply, seconds
grep -E '"timestamp":"2026-(09-30|10-01)' $RAW/391f6dee-*.jsonl | grep '"type":"assistant"' | grep '"type":"text"' | jq -r .timestamp | sort > $CM.t
node -e 'const fs=require("fs"),T=fs.readFileSync(process.argv[2],"utf8").trim().split("\n"),H=fs.readFileSync(process.argv[1],"utf8").trim().split("\n").map(JSON.parse).filter(m=>m.who=="lead:391f6dee"&&m.src&&m.ts<"2026-10-01T20:20"),d=[];for(const m of H){const n=T.find(t=>t>m.ts);if(n)d.push((Date.parse(n)-Date.parse(m.ts))/1e3)}d.sort((a,b)=>a-b);console.log("n",d.length,"median_s",d[d.length>>1].toFixed(0),"p90_s",d[Math.floor(.9*(d.length-1))].toFixed(0))' human.jsonl $CM.t
# R16: 1 Oct (UTC 00:00-20:20) chat lines, and how many have <= 6 words (146 / 68)
jq -r 'select(.src and .ts>="2026-10-01T00" and .ts<"2026-10-01T20:20")|.text' human.jsonl | awk '{n++; if(NF<=6) s++} END{print n, s}'
# R17: "delegate" / "bottleneck" asks per UTC day (36 over 11 days)
(jq -r 'select(.src)|select(.text|test("delegat|bottleneck";"i"))|.ts[0:10]' human.jsonl; jq -r 'select(.by=="user")|select(.text|test("delegat|bottleneck";"i"))|.at[0:10]' $CM) | sort | uniq -c
```

```bash
# R18: per-phase counts (phase starts in UTC)
node -e 'const fs=require("fs"),[h,c]=process.argv.slice(1),P=[["P0","2026-09-30T17:00"],["P1","2026-10-01T00:00"],["P2","2026-10-01T20:20"],["P3","2026-10-04T00:00"],["P4","2026-10-06T00:00"],["P5","2026-10-09T11:00"],["P6","2026-10-11T17:30"]],ph=t=>{for(let i=P.length-1;i>=0;i--)if(t>=P[i][1])return P[i][0]},R={},inc=(t,k)=>{const p=ph(t);if(!p)return;R[p]=R[p]||{chat:0,msgs:0,steps:0,clicks:0,props:0,decs:0};R[p][k]++};fs.readFileSync(h,"utf8").trim().split("\n").map(JSON.parse).filter(m=>m.src).forEach(m=>inc(m.ts,"chat"));for(const f of fs.readdirSync(c+"/threads").filter(f=>f.endsWith(".json")))JSON.parse(fs.readFileSync(c+"/threads/"+f)).messages.filter(m=>m.by=="user").forEach(m=>inc(m.at,"msgs"));for(const f of fs.readdirSync(c+"/steps").filter(f=>f.endsWith(".json"))){const s=JSON.parse(fs.readFileSync(c+"/steps/"+f));inc(s.createdAt,"steps");s.history.filter(x=>x.who=="user").forEach(x=>inc(x.at,"clicks"))}for(const f of fs.readdirSync(c+"/proposals").filter(f=>f.endsWith(".json"))){const p=JSON.parse(fs.readFileSync(c+"/proposals/"+f));inc(p.createdAt,"props");(p.decisions||[]).forEach(d=>inc(d.at,"decs"))}console.table(R)' human.jsonl $V1C
# R19: approval / "go" / guard lines in chat (>= 25), and usage percentages reported by hand (12)
jq -r 'select(.src)|select(.text|test("approv|^go$|guard|allow|permission";"i"))|.ts' human.jsonl | wc -l
(jq -r 'select(.src)|.text' human.jsonl; jq -r 'select(.by=="user")|.text' $CM) | grep -ciE 'session usage|current session|% (current|lefts)|resets on|reset usage|[0-9]+ ?%( current)?$|it.s [0-9]+%'
# R19b: value signals: artifacts (47), evidence/article (74), explain/learn (73), superlatives
(jq -r 'select(.src)|.text' human.jsonl; jq -r 'select(.by=="user")|.text' $CM) | grep -ciE 'artifact'
(jq -r 'select(.src)|.text' human.jsonl; jq -r 'select(.by=="user")|.text' $CM) | grep -ciE 'evidence|article|blog|medium'
(jq -r 'select(.src)|.text' human.jsonl; jq -r 'select(.by=="user")|.text' $CM) | grep -ciE 'explain|technical|how (it|we|they) |math|understand|why it'
(jq -r 'select(.src)|.text' human.jsonl; jq -r 'select(.by=="user")|.text' $CM) | grep -cE 'SOO+'
```

The perception-vs-chore minutes in §6 (355 vs 27) are the summed span from the first to the last user click per
step, grouped with the R6 classes. That is an approximation of hands-on time, not a stopwatch.

```bash
# R20: summed first-to-last user click span per step, by R6 class (perception 355, device 27, other 54 minutes)
cat $V1C/steps/C-*.json | jq -s -r 'map(. as $s|(if ($s.kind=="swipe-pair" or ($s.title|test("which page|smoother|look the same|felt|Fast flicks|Follow-the-finger|render test|Try the|blinking|own finger|Where did|clips|look check|Safari check";"i"))) then "perception" elif ($s.title|test("re-?plug|unlock|cable|USB|thermal|heat|Serious|Do Not Disturb|Auto-Lock|UI Automation|Trust|Wi-Fi|Safari|QuickTime|tab|record the iPhone|connection|off the Mac|Reconnect|Xcode|iPhone ready|iPhone is yours|test runs about|camera";"i")) then "device" else "other" end) as $c|($s.history|map(select(.who=="user")|.at|sub("\\.[0-9]+Z$";"Z")|fromdate)) as $u|{c:$c,m:(if ($u|length)>1 then (($u|max)-($u|min))/60 else 0 end)})|group_by(.c)[]|"\(.[0].c) \(map(.m)|add|floor)"'
```
