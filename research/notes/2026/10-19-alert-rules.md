---
id: 2026-10-19-alert-rules
kind: note
title: "fw watch alerts of 2026-10-19: agent.stalled 0/3 true (Stop/StructuredOutput race), ci.failed early on twin runs, timing.slow mixes run kinds"
status: review
created: 2026-10-19
topics: [tooling, alerts, watch, lean-first]
---

# Fable: fw watch alerts of 2026-10-19 (read-only; times +0700)

## 1. The two agent.stalled: both false positives, same bug
- a02c9f12689384a3a = workflow subagent `indep-bridge` (wf_11ac09ad-a60), ran 09:08:21–09:32:36; a90427cb7632237ab = the next
  `indep-bridge` of the same workflow, ran 09:32:39–09:34:05 (86 s). Both ended normally: events.jsonl holds
  `agent.stop stop:<id>|SubagentStop` and `wfid-end:` for each (seq 10414/10416, 10431/10433). CONFIRMED.
- The "silent window" was after exit. Spool tails (`.fw-console/spool/<id>.jsonl`), both agents and a08d1f989fb9338b5 (00:07 alert):
  `SubagentStop ts=T` then `PostToolUse tool=StructuredOutput ts=T+2..6 ms`. CONFIRMED.
- `apps/runner/src/watch-collect.ts:134`: "a Start or a tool call after the last Stop means it was resumed" ->
  `stoppedAt = null`. The StructuredOutput PostToolUse lands 2–6 ms after SubagentStop, so every workflow subagent that
  returns structured output is reported alive forever with `inflight:null`. Health input rows show `stoppedAt:null,
  lastTool:"StructuredOutput"` from 09:35 to 10:04 (health.jsonl lines 437–442). CONFIRMED.
- Lean then does its job: `stallB` (lean/Fw/Obs/Health.lean:334) = no event for stallMin=20 min and no tool in flight ->
  stalled at 09:54 (21 min) and 09:59 (25 min). Closed at 10:04:52 only because `workflowDone:true` arrived
  (health.jsonl line 443) and the state became `done`. CONFIRMED.
- Lead action needed: none. Not a stall; no transcript to read (workflow subagents leave no file under subagents/).

## 2. The rule and today's rate
- Rule: `Stall` lean/Fw/Obs/Health.lean:341–344: `stallMin*60s <= now - lastAt` and (no inflight, or inflight hung:
  `toolHangMin`=30 min and not an `Agent`/`SendMessage` wait with a live child, Health.lean:321–328). Liveness = any
  spool hook record (`lastAt` = max ts of all hook events, watch-collect.ts:118) or a transcript line. CONFIRMED.
- `fw ci wait` / a long foreground Bash: `inflight` is set from the transcript while the call runs
  (watch-collect.ts:572), so the agent is not stalled before 30 min, and after 30 min it is `agent.toolHang`, not
  `agent.stalled`. A real 20-min silence with no call in flight is the only true positive shape. CONFIRMED.
- Rate today (health.jsonl, 41 snapshots since 00:00): agent.stalled opened for 3 agents (a08d1f9 00:07, a02c9f1 09:54,
  a90427c 09:59), 4 snapshot rows; real stalls 0/3. All three are the Stop/StructuredOutput race. MEASURED.

## 3. timing.slow and ci.failed
- timing.slow: verdict = `codeOf` lean/Fw/Obs/Timing.lean:262–266: slow when d > budget and 2d > 3*p50(last 20 of
  the same key); key = (tool, step, host) only (Timing.lean:77–87). An alert stays until the next sample of that key
  (Next.lean `slowLatest`), hence 212 rows for 17 subjects. CONFIRMED.
- One series mixes run kinds: `counts (original, r1)` samples for commit 4283c5a are 116 s, 120 s, 203 s from three
  chromium-counts runs dispatched 10 s apart (runs 39186469962/…77379/…85136, 08:42:18–08:42:38); the 203-s run has
  all six counts jobs at ~3 min, the 116-s one at 1–2 min. Same commit, same step name, different workflow inputs
  (profile/runs/target/preset, chromium-counts.yml:13–36) -> bimodal 115/200 history, the slow mode is the other kind.
  MEASURED (durations), INFERRED (inputs differ; `gh run view` does not return inputs and `gh api` is denied).
- `chromium-counts/fwcore/lake build fwcore` samples: 0,1,1,0,44,138,…,195 s = cache hit vs miss in one series. MEASURED.
- ci.failed: `sCiFailed` Health.lean:1155–1157 fires when the latest run (by startedAt, `ciLatest` :988) of
  (workflow, branch) has conclusion failure. `fw ci` dispatches breakpoint-gate once per engine (run.ts:232–239), so each
  push yields a `push` run (skipped) plus two `workflow_dispatch` runs 3–7 s apart. At 08:45:09 the row for
  ci/morph-tween-inherit was [failure st 08:20:15, in_progress st 08:20:12, skipped]: the later-started sibling
  failed first, so ci.failed opened while the gate was still running. Both siblings later failed (jobs all green, `merge`
  job failure 02:12–02:13Z on run 39187623386), so the alert was early, not wrong. CONFIRMED.
- Rate today: 40 ci.failed rows for 9 (workflow@branch) subjects, every one breakpoint-gate or chromium-counts@ci/*;
  the 9 count each push's twin runs as one subject. MEASURED.

## 4. Recommendations (ranked by noise removed; Lean-specifiable predicates)
1. timing.slow (212 rows, most noise): change the key, not the threshold. `key(s) = (tool, step, host, kind)` where
   kind = the dispatch inputs digest (`PlanJob.digest`, run.ts:204) or cache state for lake steps; prove
   `windowOf` only mixes samples of equal kind. Until then silence `chromium-counts/*` and `lake build fwcore`. Lead
   action on a true slow: `NEXT investigate step=…` once per new sample, not per snapshot (alert on the transition
   `ok -> slow`, i.e. `code(v_i)=slow ∧ code(v_{i-1})≠slow`).
2. ci.failed (40 rows): keep the rule, change the unit. Decide per (workflow, branch, headSha) set:
   `failed(S) ⟺ ∀ r ∈ S. completed(r) ∧ ∃ r ∈ S. failing(r)`; a set with any running run is `ci.slow`/pending, not
   failed. Repeats: emit once per set. Lead action: read the merge job log, re-plan the gate; never while a sibling runs.
3. agent.stalled (3 opens, 0 true): keep the Lean rule; fix the glue at watch-collect.ts:134 with a closed predicate:
   `resumed ⟺ ∃ e. ts(e) > stoppedAt + ε ∧ hook(e) ∈ {SubagentStart, PostToolUse(tool ≠ StructuredOutput)}` with
   ε = 1 s, or better identity over inference: a Stop ends the agent unless a later `SubagentStart` exists. Golden
   vector: today's three spools. Lead action for a true stall (20 min, no inflight, not stopped): read the last 20
   transcript lines, then TaskStop + respawn from handoff (`respawnFromHandoff`, Wire/Obs.lean:1021).
4. svc.stale (12 rows, 2 subjects, after lands): keep; it is correct and the post-land routine answers it. Lead action:
   `fwcore build + console-web build + restart` once per land, then it closes itself.
5. agent.held (2, both real orphan until-grep loops, pids 27999 and 69983): keep, critical. Lead action: kill the
   named pid, record the agent in the ledger. True positives 2/2. MEASURED.
6. ci.slow (3 rows, 2 subjects): keep; gate runs of 20–25 min are the observed p50 for breakpoint-gate today, so
   raise `ciSlowMin` for that workflow via a per-workflow ceiling (`ceilings`, Timing.lean) rather than globally.

## Review corrections (adversarial check, accepted by the lead; these win over the text above)
- Rec 3: drop the epsilon variant. 56 Stops are followed by PostToolUse tool=SubagentHandback (1 ms to 11.2 s) with no
  SubagentStart; 120 Stop-then-SubagentStart resumes; 0 real tool calls after a Stop without a Start. Rule: resumed iff a
  SubagentStart exists with ts > stoppedAt. Golden vectors: today's three StructuredOutput spools plus one SubagentHandback spool.
- The revive rule has a Lean twin (lean/Fw/Ops/Obs.lean:880-884, `event_revives`, `Fw.Plan.revive_on_event`); specify the
  resume predicate once in Lean and use it for both; watch-collect.ts follows it (golden-checked), no decision logic in glue.
- Rec 6: ci.slow uses the global `ciSlowMin` (Health.lean:99, rule :999), not Timing `ceilings`; add a per-workflow map
  in Health.Params with a theorem that the global value is the default.
- ci.failed siblings: 39184893562 (failure) and 39184888361 (merge job failure at 01:46:10Z); 39187623386 is a later run.
- `lake build fwcore` samples (MEASURED): 44,42,44,1,78,138,1,1,0,151,163,184,177,195,190,0,1,1,0,193 - three groups
  (0-1, 42-78, 138-195); 'cache hit vs miss' is INFERRED.
- Interim silence only for the counts (*, rN) and fwcore steps; chromium-counts/image, fw land check.sh and fw/watch pass
  are classified separately.
- Citations: lastAt max at watch-collect.ts:119; respawnFromHandoff is defined in lean/Fw/Obs/Next.lean:219 (rule :32);
  at 09:59 a02c9f1 was at 26 min and a90427c at 25 min; counts at ~10:25 cut: 42 snapshots, 221 timing.slow, 42 ci.failed,
  14 svc.stale.
- agent.held (killOrphan, Next.lean) is unaffected by recs 2 and 3: it reads transcript children, not spool stoppedAt.
