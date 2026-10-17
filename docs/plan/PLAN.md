---
id: 2026-10-17-v2-plan
kind: decision
title: "v2 loop-engineering experiment: design and plan (for user review)"
status: review
created: 2026-10-17
updated: 2026-10-17
revision: 4 (your decisions of 2026-10-17: MUI everywhere, Lean, private repo, looser budget; see Appendix D)
authors: [agent:plan-architect]
topics: [plan, architecture, measurement, lean, parts, agent-teams, styling]
links:
  notes:
    - research/kickoff/01-prior-loop-lessons.md
    - research/kickoff/02-site-anatomy-and-rewrite.md
    - research/kickoff/03-chromium-rendering-math.md
    - research/kickoff/04-webkit-rendering-math.md
    - research/kickoff/05-lean-proofs-and-backend.md
    - research/kickoff/06-architecture-and-tooling.md
    - research/kickoff/07-claude-code-agent-teams.md
    - research/kickoff/08-chat-forensics/README.md
    - research/kickoff/09-mui-zero-runtime/README.md
    - research/notes/2026/10-17-v2-plan-feasibility-review.md
  v1_repo: ../fastwork-com-web-optimize (read-only)
---

# v2 plan: a measurable, provable loop for the fastwork.com scroll experiment

This is the design for you to review. It merges the kickoff notes, cited as `[01]` to `[09]` with section numbers.
`[08]` is the forensics of v1's raw chat history (§2.3). `[09]` is the MUI zero-runtime study,
`research/kickoff/09-mui-zero-runtime/README.md`, and its sub-notes are cited as `[09.01]` to `[09.04]`. It also
merges the feasibility review, cited as `[FR]` (`research/notes/2026/10-17-v2-plan-feasibility-review.md`). Where the
notes disagree, Appendix A says which way this plan goes and why. Appendix D logs every change. **Revision 4 applies
your four decisions of 2026-10-17 (§12.0).** Only Q1 remains to answer before Monday. Nothing is built yet, and
nothing is committed.

**Status words.** CONFIRMED = a note cites a source, doc or v1 record for it, or it was checked on this Mac today.
INFERRED = a design choice or expectation that a spike or measurement must still check. Targets and thresholds are
proposals until you accept them.

## Glossary of labels (each prefix is used for one thing only)

| Label | Means | Where |
|---|---|---|
| **Q1 … Q21** | questions and defaults for you (Q2, Q3, Q4 and Q16 are answered; see §12.0) | §12 |
| **Day 1 … Day 45** | working days from Monday 2026-10-19 (Day 1-10 in detail) | §10.1, §10.2 |
| **M0 … M6** | milestones | §10.1 |
| **G1 … G4** | outcome goals | §1.1 |
| **V-a … V-q** | method (validation) criteria | §1.2 |
| **TL0 … TL5** | test layers | §5.4 |
| **PL0 … PL6** | parity levels (rewrite vs original) | §6.6 |
| **N0 … N5** | styling-neutrality checks | §6.7 |
| **S1 … S13** | styling rules inside parts | §6.5 |
| **class W / SM / X / P** | landing classes: less **W**ork, **SM**oothness or mixed, device-only (**X**), **P**roposal | §9.2 |
| **SPK-a … SPK-s** | spikes (short experiments that answer one question) | Appendix B |
| **tier T0 … T3** | v1's pixel-difference tiers | §6.6 |
| **K1 … K10** | calibration fixture pages: K1-K9 WebKit [04 §9]; K10 sheet mutation, both engines [09.03 §5.2] | §4.4 |
| **R1 … R22** | risks | §11 |
| stages | question → build → screen → review → (device) → land, always written as words | §9 |

## 0. The plan in one page

**v1's result, and why v2 is different.** v1 reached its goal: slow frames in your swipe fell from 20.1 % to 1.7 %,
and the end-of-page longest frame fell from 584 ms to 42 ms. It cost 10 days, 442 started agents (848 transcripts)
and about $11.4k at list price, recomputed per request (v1's own readout scaled to about $13.5k) [01 §0, 08 §3]. 231
of its 276 incidents were filed against its own tools, 45 of them feature requests rather than failures [01 §1,
08 §4]. Your three pain points all show in v1's data. v2 answers each one structurally:

| Pain point | v1 evidence | v2 answer |
|---|---|---|
| 1. The phone was needed for every measurement | ~111 of 276 incidents involve the iPhone or Simulator driver; phone blocks took 12-35 min plus cooling [01 §B.1] | **Two-speed loop.** The inner loop is deterministic engine **work counts** (Chromium headless-shell in a Linux container, and WebKit on the iOS Simulator) feeding a **cost model** that is calibrated on the phone. The phone becomes a scheduled outer loop (§4) |
| 2. Patching the minified Svelte build was slow | Retrospective cause C6; ~349 commits on the end-of-page line [01 §B.1] | **React rewrite as pluggable parts.** Each part has a `faithful` variant that copies the original's look and, for the parts we experiment on, its per-frame engine work, plus ablation, optimized and proposal variants picked by flags (§6) |
| 3. A coupled, bug-prone loop; every tool change re-ran everything | Full suite 250-280 s on every tooling commit; `lock.mjs` grew to 1,685 lines [01 §B.1, 06 §1] | **A small pure core with a thin IO shell.** The few decisions that matter (verdict, flags, screening, frame ticks) live in one Lean 4 project (`fwcore`) with theorems. Tools are plugins. Results are content-addressed, so changing a tool re-runs only that tool's tests and artifacts. An explicit MVP tier keeps the tooling small (§3, §5) |

**What the chat history adds** (§2.3, [08]): v1's agents did their work well; the loop around them did not. One
overloaded lead was woken mostly by recurring check prompts, long-lived contexts idled and woke up cold, home-made
coordination tools broke more often than agents did, and you acted as device technician and status bus. v2 fixes
that with scripts, events and hooks, not with more agents or more rules (§8.5).

**What to expect, plainly** (so you can judge pain points 1 and 2 with the right expectations):
- **The phone does not go away.** Before the model may stand in for the phone for one kind of change, it needs a
  calibration session and 5 of 5 blind swipe verdicts that agree with it. Expect **about 5-10 phone sessions before
  the first kind of change is licensed** (INFERRED [FR §1.8]). Changes that only the phone can see (backdrop/filter,
  toolbar, first-touch layer builds: class X) and look changes (class P) always need the phone. After that, phone use
  drops to calibration every 14 days or on a version change, plus one blind spot-check per 5 landings. That is far
  below v1, but it is not zero.
- **MUI is used everywhere, with styles compiled ahead of time (decided 2026-10-17).** Every part with markup is
  built from Material UI 9.5 components (the `engine.*` parts have none). Their Emotion styles are rendered at build time into one static, linked CSS file, and
  the client is told those styles are already present, so no style is inserted after first paint ("Emotion AOT",
  §6.5). The looks come from CSS Modules that restate the original's values, and all motion stays in our drivers.
  Pigment CSS, the compiler you remembered, is a paused alpha that no longer builds with current Material UI. It is
  kept only as a fallback and an optional measured arm (CONFIRMED [09.01, 09.04]). A styling-neutrality gate (§6.7)
  checks that MUI adds no style-sheet mutations, no extra DOM writes or React commits, and no extra engine work
  counts compared with a plain twin; it is needed because the planned counts cannot see style-sheet insertions
  (CONFIRMED [09.04]). What counts cannot see (JS time, per-element style cost of a bigger style sheet) is left to
  timing parity (PL6). The gain for pain point 2 still comes mostly from readable source plus flags.
- **Chromium is a development aid; the iPhone is the target.** The Chromium counts lane is fast and deterministic,
  but Chromium cannot predict iPhone Safari, so the cost model is calibrated for WebKit first (§4.4, Q8).

**Headline goal.** Rebuild the page, reproduce v1's outcome on the phone as a set of flag arms, and do it with a
fraction of v1's device time, tool bugs and calendar time. Cost is reported, not capped (decided 2026-10-17). Every
speed-up the model claims must hold up against your finger (§1).

**Order of work.** M0 bootstrap as a thin vertical slice (Day 1-5: one counts script on the original, one Lean
verdict round trip, one WebKit Simulator spike) → M1 measure the **original** snapshot in both engines, before any
rewrite → M2 pilot three parts → M3 calibrate the WebKit model → M4 port the parts we will experiment on → M5
experiments → M6 write-up (§10).

## 1. Goals and success criteria

Each criterion has a measurement and an owner. "Proposal" thresholds become binding once you accept them (Q9).

### 1.1 Outcome goals

| # | Goal | Metric | Target | Checked by |
|---|---|---|---|---|
| G1 | v2 reproduces v1's effect | On the iPhone in your swipe, the `original` preset is within v1's A/A band of the original site, and the `v2-best` preset is at or below v1's g0.0m | slow frames (> 34 ms) ≤ 1.7 %; end-of-page longest frame ≤ 42 ms; frames > 50 ms per 100 moving frames in the finger's zone no worse than g0.0m | phone block + blind A/B (§4.6) |
| G2 | Fewer device blocks, less device chore work for you | phone sessions, device incidents, chore steps per session | ≤ 10 phone sessions up to the first licensed class (INFERRED estimate 5-10); afterwards ≤ 1 block per landed class SM change and calibration ≤ 1 session per 14 days; device-driver incidents ≤ 10 % of incidents (v1: ~40 %); **≤ 1 get-ready step and 0 reactive chore steps per phone session** (v1: 82-105 of 166 steps were chores [08]) | console step log, bug ledger |
| G3 | Speed first, cost reported (decided 2026-10-17) | calendar days per milestone; list-price dollars per milestone, role and day; Opus share; cold-wake share | **no hard caps or stop rules**. The milestones finish on or before the §10.1 days. Cost is reported daily against the §8.4 forecast. Soft alerts at 1.5× a milestone's forecast and at 60 % / 80 % of the weekly usage limit raise a one-line note, not a stop. Report the total against v1's $11.4k at M6 | `pnpm fw usage` [07 §8] |
| G4 | Write-up material | every landed experiment card has a plain one-paragraph summary and a reproducible clip or chart reference; cleanup never deletes listed evidence | all landed cards (v1: 74 of your messages were about evidence and the article [08]) | `kb lint`; M6 review |

The lead's share and dollars per day are reported, not capped (§8.4). The anti-waste rules that also save time stay
in force (§8.5).

### 1.2 Method goals

| # | Goal | Metric | Target (proposal) | Source |
|---|---|---|---|---|
| V-a | **Count transfer: Chromium** | container (Linux headless-shell) counts vs counts from a traced, non-timed headed Mac Chrome run, per count family | equal per family, or the family is marked "container-only" and never feeds a fitted coefficient | [FR §1.6] |
| V-b | **Count transfer: WebKit** | Simulator count equals phone count at the same held state | ≥ 95 % of states, per count type; failing types are marked "not transferable" | [04 §9] |
| V-c | **Ranking** | Spearman ρ, predicted vs measured cost per variant (holdout) | ρ ≥ 0.8 on the iPhone. Chromium: only if an Android phone is added (Q1, Q8), then also stage MAPE ≤ 20 % at p50 | [03 §9.3, 04 §9] |
| V-d | **Decision agreement** | sign of predicted Δ vs measured Δ, where the prediction exceeds the noise band | ≥ 90 %, and 0 sign errors among "large" predictions | [03 §9.3, 04 §9] |
| V-e | **Magnitude** | median abs(log(pred/meas)) | ≤ 0.3. If missed, the model is "ranks only" and may not size a change | [04 §9] |
| V-f | **Feel agreement** | blind verdicts with predictions frozen first | 5 of 5, no sign disagreement, before the model can stand in for the device for a change class | v1 `stats-vs-finger.md` via [03 §9.3] |
| V-g | **Visual parity** of each `faithful` part | v1 tiers against a same-run original-vs-original (A/A) baseline | tier **T1** at PL0-PL3 (all parts) and PL4 (experiment parts) in Chromium and Playwright WebKit on the core viewport matrix; element boxes ≤ 0.5 CSS px; one Simulator check at 430×775 DPR 3 | [02 §4] |
| V-h | **Work parity** of each experiment part | PL5 bands per count family (§6.6) | within the band for every family; layers ±0; same compositor/main-thread split | [02 §4.6, FR §2] |
| V-i | **Determinism, per count type** | two identical counts-lane runs | each count type classified *deterministic* (byte-identical), *stable* (within a stated tolerance) or *quarantined* (never used). Chromium: all used types deterministic. WebKit: the deterministic set covers what the K1-K9 fixtures need | [03 §7.1, 04 §8.5] |
| V-j | **Time to adopt a tool** | new measurement plugin → first cached artifact | ≤ 1 agent-day; tests run = that plugin + `contracts` only; 0 other artifacts invalidated (shown by `fw run --dry`) | [06 §3] |
| V-k | **Test speed** | pre-commit gate; TL1 whole repo | pre-commit ≤ 30 s (affected packages); TL1 < 20 s cold | [06 §3.4] |
| V-l | **Bug ledger** (replaces "share of logic proved") | every entry has `kind: request \| incident`; every incident tagged *proof would have caught it* / *property test caught it* / *adapter (IO, device, container)* | complete ledger; at M4 it decides whether Lean pays (Q12), counting incidents only (v1 filed 45 requests as incidents [08]) | [FR §3.1] |
| V-m | **Bugs in proved areas** | incidents in verdict / flag resolution / screening / frame ticks | 0 logic incidents (adapter bugs are counted separately) | bug ledger |
| V-n | **Harness neutrality** | on fixtures, frame-stepped counts vs free-running counts, per family | equal per family; a family that fails is not used for screening in that engine | [FR §1.2] |
| V-o | **Timing parity** (PL6) | Mac Chrome per-stage time, rewrite vs original | rewrite within the original's A/A band (ABBA, n ≥ 4) per stage; plus one Simulator and one phone whole-page check at M4 | [FR §2] |
| V-p | **Transfer to the original** | the same change as an overlay on the original, in the counts lane | same sign of Δ per stage as on the rewrite, for every landing whose change can be overlaid | [FR §2] |
| V-q | **Styling neutrality** of MUI | N0-N5 (§6.7): N0/N1 in every counts run (all parts); N2/N3 on experiment parts (they need the `impl: plain` twin); N4 once per build; N5 per build at hydration | sheet mutations 0 after hydration; DOM-write and commit census and work counts equal to `impl: plain`; style shape within ±10 % of arm A (or a K-fixture parameter); 0 hydration diffs | [09.03 §2] |

## 2. What we keep and what we drop from v1

### 2.1 Keep (each with its v2 form)

| Keep | Why (v1 evidence) | v2 form |
|---|---|---|
| Frozen, hash-pinned baseline | The pin changed only twice, both on purpose [01 §B.2] | `snapshot.lock.json` pins the original; each rewrite build is pinned by commit + flag vector + `servedHash` |
| One change per arm | Overlays gave clean A/B arms | Overlays become **flag arms**; never bundle fixes in one arm (bundled builds hid causes) |
| A/A noise floor; "better" only with disjoint ranges; ±4 ms twins | g0.0l vs g0.0m was correctly called level [01 §B.2] | The landing verdict is **4 vs 4** runs with disjoint ranges (or v1's sequential ABBA rule). Its false-win rate under the null is proved to be exactly 1/70, and comparisons are counted per experiment (§5.1) |
| Prediction cards before data | 17 or more flagged prediction misses in 153 rows | The question card carries a pre-registered predicted Δ per stage and zone (§9) |
| Claim status words, engine-build applicability, "read source first" | Claim C1 (`layerPainted`) reached you as fact on two probes [01 §B.2] | Rule cards in `refs/rules/` with file:line@commit, status (incl. WEAKENED), builds [04 §11] |
| Pixel tiers T0-T3, screencast capture, frozen frames | False 0 % passes after a scroll (P14) | Parity levels PL0-PL6 (§6.6) |
| Element ablation with a fairness check | Showed end-of-page backgrounds cost a median 16 → 3 slow frames [02 §2.6] | Generated ablation variants per part (§6.2) |
| The validated feel metric: frames > 50 ms per 100 moving frames in the finger's zone | The only metric that agreed with you 7 of 7 [01 §A.4] | Primary device metric (§4.6) |
| Less-work landing rule | Gates sized to risk | Landing class W, now per-frame and over a declared-complete vector (§9.2) |
| Proposals with Try-it pages; blind swipe A/B; comment on anything | Look changes are your call; your thumb caught what Chrome missed. 41 proposals, median 10 min to your decision; 94 of 198 of your threads came from comment buttons [08] | The console Proposals view (shadcn); Try-it, comment-on-any-row and a preset gallery on Wi-Fi are M1 features; a second iPhone for free play (Q1) |
| Your coaching, as rules with enforcers | You re-taught the same management behaviour on 11 days; the lead said its role file never told it [08] | Day 1, in the lead file and `CLAUDE.md`: the issue loop (cause from data, workaround, long-term fix with an owner), proactive by default, trace before asking, the answer format; each names its enforcer and is re-injected after compaction (§8.5) |
| Named spawns `<role>-<topic>`; one worktree per editor; one lander; ff-only | 0 merge commits in 2,483 [01 §B.2] | Same, enforced by git config, deny rules and a land-time gate [06 §6] |
| Quiet-host gate and contamination flag for timing runs | One overloaded evening voided all 9 A/Bs | Kept, for the **timing lane only**; the counts lane needs no lock |

### 2.2 Drop (each with what replaces it)

| Drop | Evidence | Replacement |
|---|---|---|
| A device run for every measurement | ~111 device incidents; 19 end-of-page phone blocks for 5 passes [01 §B.1] | Counts lane + WebKit cost model + validity table (§4) |
| Patching a minified bundle | Cause C6; a replace-all broke six SVG circles unseen [01 §B.1] | React parts with flags (§6) |
| The 6x CPU throttle as the model | One scalar, super-linear (6x costs 7.8x), GPU untouched, fitted on the unfixed page [03 §11] | Per-stage, per-count coefficients per device, with a page factor `ρ_page` [03 §9, FR §1.7] |
| A full test suite on every tooling commit | 250-280 s; ~22 h of serial suite time [01 §B.1] | `vitest --changed` per affected package; TL0-TL5 layers [06 §3.4] |
| Real time and the real host in tests | 75 of 143 s were sleeps [06 §1]; 44 flaky-test incidents and 14 port, process and temp-dir collisions on the shared host [08] | Clock port; a lint bans timers in the pure zone and real load, fixed ports, process-name matching and shared temp folders in tests; engine e2e tests run outside pre-commit; scratch paths per agent |
| Side effects at import; 8-24 copies of one parser; two different medians | [01 §B.1, 06 §1] | Pure zone enforced by a lint; one `model` package for stats |
| Many writers to many JSON stores; agents writing board state | 575 board writes a day; 8 stale-board incidents [01 §B.3] | One writer (console-api), one append-only event log, status as a projection |
| A 9.7k-word rulebook loaded by every agent | ~8 % of all cache reads [01 §B.3] | Root `CLAUDE.md` under 300 words at Day 1, never above 1,500; each rule names its enforcer |
| Opus everywhere; the lead as router; 160 agents in 29 h; recurring check prompts | Opus ~97 %; 3,761 cron fires were 42 % of the lead's turns and 35 % of its dollars; the lead was first responder on 773 of 985 of your console messages [01 §C, 08] | Small roster, a model ladder with Opus where it speeds the work, a lead that decides and does not route, no LLM polling, scripts for checks and gates (§8.5) |
| Routing agents (mgmt-ops ×10, desks, clerk, devices, ops-readers) | 47 agents, $847; 47 % of their messages to the lead were land requests; 22 % of workers' consecutive instructions switched between two bosses [08] | `pnpm fw` scripts over `events.jsonl`: queue order, land queue, device dispatch, digests, card pre-data reads (§8.5) |
| Agents holding device leases; hand-moved queues | 40 scheduler incidents (median fix 2.2 h); ≈ 230 lead hand moves; 264 order-request messages [08] | A device job queue in console-api; priority is a tested function of your list (§3.3, §4.1) |
| Shared ledger files that many agents edit | `ops-handover.md` 569 commits, `PREDICTIONS.md` 378; 94 `rebase --continue` [08] | Predictions in each `card.md`, handovers in per-agent notes, the board as a projection (§7.1) |
| Multi-step inline shell in worktree agents | 3,046 isolation refusals, 57 % of all v1 errors [08] | Committed `pnpm fw` verbs; one plain command per Bash call (§8.2) |
| Hand-built lock code (1,685 lines) | ~39-89 lock incidents depending on the count [01 §B.5, 05 §3] | No lock in the counts lane; one in-process queue in console-api for the timing lane. Many lock incidents were cross-process races that a single writer removes (INFERRED [FR §3.1]) |
| An 842-line git-guard hook | The guard drew its own incidents | git config + deny rules + a land-time path check in `fw gate`; one small spawn-guard hook (§8.3) |

**Rule for every new tool, hook or package:** it must name the v1 incident class it prevents (or the failure it
fixed in v2). If it cannot, it waits until something fails without it. An **enforcer** (alarm, lint, router, status
board) also reads only events, never agent self-reports; ships with false-positive and false-negative golden tests;
and reaches ≥ 90 % precision on an event-log replay before any alarm reaches you (v1: 46 enforcement incidents, 61 of
80 lead-made threads were alarms [08]). A new *agent* rule must cite an incident caused by an agent mistake;
otherwise fix the tool (v1: 4 agent-mistake incidents against 139 tooling ones, hand labels [08]).

### 2.3 What the chat history showed

[08] ([`research/kickoff/08-chat-forensics/README.md`](../../research/kickoff/08-chat-forensics/README.md)) read v1's raw transcripts (848, 135k model requests), the console
and the incident store. Its numbers are reproducible from the commands it lists; readings are marked INFERRED there.
- **A star, not a team.** 64 % of the main session's 12,582 messages started or ended at the lead; only 16 % went
  worker to worker. The lead talked to about 310 agents, up to 38 in one hour, and compacted 125 times.
- **The lead was woken by polls, not decisions.** 42 % of its 8,948 turns started from 3,761 cron fires: 2,897 from
  your `/loop` prompts (1,889 "check iphone connection"), 864 from crons the lead created itself. They cost 35 % of
  the lead's dollars. It also landed, signed, spawned, scheduled the phone queue (≈ 230 hand moves) and answered
  78 % of your console messages first.
- **Idle contexts cost the most** (§8.4). **Home-made coordination broke more than the agents did:** coupled tooling
  and enforcers made 139 of 276 incidents, agent mistakes 4 (hand labels); 57 % of all 5,393 errors were
  worktree-isolation refusals of inline shell.
- **You were the device technician and the status bus.** 82-105 of 166 console steps were device chores; one re-plug
  waited 11 h 41 min and stalled a landing. 132 of your messages match a catch-up regex, and you asked the lead to
  delegate or called it the bottleneck on 11 days.
- **What worked:** the console's steps, Try-it proposals and comment buttons; fast replies (median 40 s); message
  delivery (0.35 % failed); short, fresh agents (645 agents under an hour cost 11 %); one lander, ff-only.

The resulting changes are in §8.5 (coordination rules) and in the sections each one names; Appendix D lists them.

## 3. Architecture

### 3.1 Overview

```mermaid
flowchart TB
  subgraph SITE["apps/site: React 19 + Material UI 9.5 (Emotion AOT) + Vite 8, prerendered"]
    ENG["engine: ScrollEngine, Signals, MotionClock"]
    PARTS["parts/*: faithful | ablation | optimized | proposal (impl: mui; plain control)"]
    AOT["mui-aot: census route → static mui.css + emotion-ids.json"]
    RES["registry + resolve() (the only TS mirror of fwcore)"]
  end
  SNAP[("snapshot/ (gitignored): Fastwork original, arm A")]
  subgraph RUN["apps/runner: fw CLI"]
    LANES["lanes: counts (parallel) | timing (one queue) | device (console step)"]
  end
  subgraph MEAS["packages/measure"]
    CR["chromium: counts in a Linux container (headless-shell + BeginFrameControl); traced headed Mac Chrome for transfer and timing"]
    WK["webkit: Simulator counts (Inspector via iwdp), held-state LayerTree census, timeline, device"]
  end
  AS[("artifact store: git-common-dir/fw/artifacts")]
  CM["packages/model: stats + cost model (WebKit W/F/U/RS; Chromium counts)"]
  FW["lean/ fwcore: verdict, ticks, flags, screen (later: stage, step)"]
  subgraph CON["console"]
    WEB["console-web: shadcn/ui (run builder, steps, results)"]
    API["console-api: Node 24 + Hono, single writer, events.jsonl, run + device queues, watchers"]
  end
  KB[("research/ refs/ results/ + pnpm kb")]
  PHONE(["iPhone Safari: calibration, licences, spot-checks, class X and P"])

  SITE -- "URL ?fw= / ?preset=, window.__fw" --> LANES
  SNAP -- "same harness" --> LANES
  LANES --> CR
  LANES --> WK
  CR -- "count vectors (zod)" --> AS
  WK -- "count vectors (zod)" --> AS
  AS --> CM
  CM -- "predictions + model status" --> API
  LANES <-- "screen, verdict ops" --> FW
  API <-- "JSON-lines ops with ids" --> FW
  WEB <-- "HTTP + SSE (zod)" --> API
  API -- "device jobs + steps (booked sessions)" --> PHONE
  PHONE -- "timeline segments, verdicts" --> API
  API --> KB
  RES -. "oracle test (TL2)" .- FW
```

### 3.2 Modules and their narrow contracts

Rule: a module talks to another only through the contract in this table. Each contract is a zod schema in
`packages/contracts`, exported to JSON Schema and, where Lean reasons about it, mirrored in Lean with golden
fixtures [06 §2.5, 05 §6].

| From → to | Contract | Notes |
|---|---|---|
| runner → site | URL `?fw=part:variant,…`, `?impl=part:plain,…`, `?preset=<id>`, `seed`, `t0`, `rm`; page exposes `window.__fw = {config, configHash, scroll, clock, hydrated, styleMisses, markMeasureStart}` and `<meta name="fw-config">` | The same harness drives arm A (original) by injecting an equivalent `__fw.scroll`; `markMeasureStart()` is refused before `hydrated` [02 §3.5, 09.03 §2] |
| site build → runner | Vite `manifest.json` → `servedHash` per route | Edits to part X change the keys only of routes that serve X [06 §3.1] |
| runner → plugin | `MeasurePlugin {id, semantics, lane, input, output, run, reduce}` | `reduce()` is pure and golden-tested; an output that fails its schema is an incident, never a result [06 §2.4] |
| plugin → artifact store | key = `sha256(canonical JSON of {subject, tool{plugin,semantics}, engine{build,flags}, profile, protocol})` (sorted keys; full JCS later if needed) | Counts artifacts are reused; timing artifacts append samples [06 §3.1] |
| artifact store → model | count vector per (frame, part, zone) + coefficient set `(device, engine build, thermal class, ρ_page)` → `{stage p50/p90, missed vsyncs, status: uncalibrated | ranks-only | sizes}` | Pure; applied at report time, so a refit re-runs no measurement [06 §3.3] |
| TS → fwcore | one JSON-lines request per decision, MVP ops: `verdict`, `ticks`, `twins`, `flags.resolve`, `screen`, `samples` (later: `stage.step`, `step.step`) | Long-lived child process; ~140 µs per round trip (MEASURED [05 §1]). **Hardening below** |
| console-web → console-api | typed HTTP + SSE; zod schemas shared from `contracts` | The UI never decides. **Previews always call console-api (and so `fwcore`)**, so the site resolver stays the only mirror |
| agent → device lane | job card `{kind, card, priority class}`; agents never hold the phone; long runs live in console-api, never in an agent's shell | v1: 40 scheduler incidents; runners died with their agent (I-221, I-240, I-256) [08] |
| console-api → status and steps | each status row: stage, owner, next step, ETA, age of its last event, and `needs-you: yes/no + the exact action` (set only by an open step or proposal event); a step is shown only after a script checks it is ready, and has a retry | v1: 25 "what does this mean" asks, rows saying "waiting on you" with nothing to do [08] |
| any client → console-api | every request carries `contractsVersion`; a mismatch is refused with "rebase" | v1: worktrees on old tool code misread shared state (I-010, I-011, I-041, I-102) |
| everything → knowledge store | one frontmatter schema; `pnpm kb index | find | lint` | §7.2 |

**Hardening the TS ↔ `fwcore` glue** (each item is CONFIRMED as a real failure path in [FR §3.2]):
1. **Request ids.** Every request carries `id`; `fwcore` echoes it; the client rejects a reply whose id does not
   match the oldest outstanding request, kills the child and fails the call. `fwcore` replies to **every** line,
   including a blank one (with an error), so replies can never shift onto the wrong request (today's sketch skips
   blank lines without a reply: `05-lean-sketch/Main.lean` l.7-10).
2. **Timeout and restart.** A per-call timeout (default 2 s); on timeout or exit the client restarts `fwcore` and
   fails the outstanding calls. It never retries silently.
3. **Panics abort.** `fwcore` is always spawned with `LEAN_ABORT_ON_PANIC=1`, because a Lean panic otherwise prints
   and returns a default value (lean4 v4.35.0 `src/runtime/object.cpp` l.76-82, l.198-202). Any stderr output is
   logged as an incident.
4. **No partial operations in the glue.** A grep gate fails the build on `!`-suffixed partial ops (`get!`, `head!`,
   `[i]!`, `panic!`) in `Fw/Wire.lean` and `Main.lean`.
5. **Numbers.** Counts cross as `Nat`; times as integer **ns**; fitted coefficients as `Rat` with an explicit wire
   form `{"num":"<int>","den":"<positive int>"}` (decimal strings, reduced), with golden round-trip tests. Never
   `Float`. (The sketch's `UnitCost` in `Nat` µs would truncate a sub-µs per-element cost to 0: `Cost.lean` l.21-25.)

### 3.3 Where each decision runs (one place only)

- **Default: in `fwcore`.** The Node side sends inputs and gets the decision back. TS never re-implements it [05 §0].
- **Exception: code that must run in the browser.** Today that is only the site's flag resolver. It is a TS mirror,
  and a TL2 oracle test (fast-check, 2,000 cases) must agree with `fwcore flags.resolve` on every change [05 §5.3].
- **Plain bookkeeping stays in TS** with unit tests, for example "which artifact keys are missing" (a set
  difference). Lean is kept for decisions whose wrong answer would mislead an experiment.
- **Priority is data you own.** One ordered list (`presets/priority.json`, or a list you drag in the console). The
  experiment queue and the device queue read it through one pure, table-tested TS function of the list and the job
  class (user step > calibration > class X/P > spot-check). Agents never set priority; a manual move is an event with
  a reason (v1: 39 priority overrides by you, ≈ 230 hand moves [08]).
- **Numbers that are fitted, not decided** (coefficients, regressions) live in TS (`packages/model`). Lean proves the
  **screening rule** for the model that is actually deployed (§4.3, §5).

### 3.4 MVP tier and later tier

| | MVP (built in M0-M2) | Later (only when a named failure needs it) |
|---|---|---|
| apps | `site`, `runner` (`fw`), `console-web`, `console-api` | — |
| packages | `contracts`, `measure` (chromium + webkit), `model` (stats + cost model), `kb`, `fwcore-client` | split `measure-sdk`; separate `artifact-store`, `usage` packages; `core` |
| console storage | `events.jsonl` + in-memory projection; one in-process run queue and one device job queue; three watchers (device, stall, notice coalescer, §8.5) | SQLite read model (if queries get slow); a proved lease (only if a second timing host appears) |
| Lean | `Frames`, `Verdict`, `Flags` (+ generated registry), `Cost`/`screen` | `Stage`, `Step` (lifecycle). `Thread`, `Log`, `Lease` only after an incident class appears. No engine-rule data in Lean |
| hooks | `SessionStart` brief (also after compaction), `SubagentStop` usage, one `PreToolUse(Agent)` spawn-guard | `SubagentStart` role brief, `TeammateIdle` (only if the stall watcher is not enough), `TaskCompleted` |
| repo tooling | pnpm workspaces, Biome, lefthook (one pre-commit), Vitest | Turborepo, knip, dependency-cruiser, ast-grep rule sets, REUSE.toml, JCS keys |
| knowledge store | 4 kinds (`note`, `decision`, `ref`, `rule`), 5 claim statuses | more kinds if the index needs them |

## 4. Measurement methodology

### 4.1 Three lanes

| Lane | Runs | Determinism | Gives | Never gives |
|---|---|---|---|---|
| **counts** | parallel, no lock. **Chromium:** Playwright's linux-arm64 `chromium-headless-shell` inside a Linux container (Docker Desktop is installed on this Mac, CONFIRMED locally), with BeginFrameControl. **WebKit:** Simulator Mobile Safari through `ios_webkit_debug_proxy` | per count type (V-i): deterministic, stable or quarantined | work per virtual frame, per 100 px, per part and per scroll zone | milliseconds |
| **timing** | one at a time from the console-api queue: headed Mac Chrome with `PipelineReporter` tracing; Simulator Timeline with `Page.enable` first | statistical (ABBA, n ≥ 4) | per-stage ms on this host, for timing parity (PL6) and A/A bands | iPhone ms |
| **device** | iPhone Safari blocks as **jobs in a console-api queue**, run only inside a session window you book. Each session starts with `fw device check` (v1's named trap codes: link, unlock and UI Automation, tabs, proxy), which repairs what it can and then posts **one** get-ready step (usual USB port, unlocked, Auto-Lock Never, UI Automation on, same Wi-Fi, Do Not Disturb, one thermal profile); then the queued blocks run back to back | statistical | the truth for feel; iPhone coefficients; render-server time (Instruments) | anything at scale |

**Why a container.** Chromium refuses BeginFrameControl on macOS: `chromium@317846d579b2`
`headless/lib/browser/protocol/target_handler.cc` l.62-65 returns "BeginFrameControl is not supported on MacOS
yet", and the protocol doc for `Target.createTarget.enableBeginFrameControl` says the same (CONFIRMED [FR §1.1]).
The container must serve **every font from `snapshot/`** with no system fallback fonts, because Linux text shaping
and fallback fonts change line breaks and so change layout and paint counts (INFERRED). SPK-i checks this on Day 1.
If SPK-i fails, the Chromium counts lane loses compositor stepping, and V-i is re-scoped to the count types that stay
deterministic without it.

Heavy trace categories (invalidation tracking, layers) are used in the counts lane only and never feed timing data;
v1 saw −17 fps from one such probe (CONFIRMED [03 §12]).

### 4.2 Step 1: deterministic work counts

**The harness must not change the mechanism it measures.** The first draft advanced a Playwright fake clock and
seeked every animation each frame. Both perturb the engine (CONFIRMED [FR §1.2]):
- Playwright's `page.clock` fakes `requestAnimationFrame` (https://playwright.dev/docs/clock). The app's rAF then
  runs as a timer task outside the rendering steps, scroll-linked writes lag one frame, and the rAF count is lost.
- In Chromium, seeking (`setCurrentTime`) marks the animation compositor-pending; `PreCommit` cancels a non-playing
  animation on the compositor and restarts a playing one (`animation.cc` l.576-618, l.741-800 @317846d5). Seeking
  would charge main-thread work to animations that really run on the compositor.
- In WebKit, `setCurrentTime` ends in `invalidateEffect()`, a style invalidation per animation per step
  (`WebAnimation.cpp` l.587-620, l.1057-1063 @fba976461fc0).

**One virtual frame in Chromium** (both arms):
1. **Driver:** `puppeteer-core` (or raw CDP) creates the page target with
   `Target.createTarget({enableBeginFrameControl: true})` in headless-shell started with
   `--enable-begin-frame-control --deterministic-mode --run-all-compositor-stages-before-draw`. Playwright's own page
   creation does not set that flag (INFERRED from [03 §7.1]), so it is not the driver. This is the first check on
   Day 1.
2. **Clock shim** injected before any page script: fakes `Date`, timers and `performance.now` from the virtual time,
   with the date pinned to `2026-10-01T00:00:00+07:00` (before the countdown target `2026-11-02T12:00+07:00`, which
   passes during this experiment). It **keeps native `requestAnimationFrame`**.
3. Apply the scroll step from a committed profile (the v1 scripted swipe, a fling, slow drags, or v1 finger replays).
4. `HeadlessExperimental.beginFrame({frameTimeTicks})`. The document timeline advances by `frameTimeTicks`, so CSS
   and Web Animations advance **without seeking**, and rAF callbacks fire inside the rendering steps as in real life.
5. Read the counter deltas.

**One held state in WebKit.** The Simulator has no BeginFrameControl, so WebKit stepping needs seeking plus "two
rAFs" (with the native rAF kept). WebKit counts are therefore classified per count type (V-i):
- **Seek overhead is measured, not assumed.** A fixture with N accelerated animations is run seeked and
  free-running; the extra style counts per seeked animation are recorded, and the affected counts are tagged
  `harness-induced` and subtracted or excluded.
- **Compositor status is read only from free-running runs:** a held-state `LayerTree` census (layer reasons) while
  the page plays normally, never from a stepped run.
- **Time box and fallback.** WebKit stepped counts get two days (Day 7-8). If the deterministic set is still too
  small, the fallback is held-state `LayerTree` censuses plus timeline record counts from a real gesture run, with a
  stated tolerance (count types become *stable*, not *deterministic*).

`Math.random` is seeded (mulberry32); `t0` and the seed are part of the artifact key.

**What gets counted** (full catalogues in [03 §7.2] and [04 §4.1]):

| Family | Chromium (Blink/cc) | WebKit (Simulator, Inspector protocol) |
|---|---|---|
| **Sheet mutations** (new, rev 4) | page-side census N0 (CSSOM write wrappers + `MutationObserver` on `<style>`/`<link>`); engine side N1: `StyleEngine::updateActiveStyleSheets`, `scheduleInvalidationsForRuleSets`, font-update slices (`blink,blink_style`) | page-side census N0 (always); `CSS.styleSheetAdded/Removed/Changed` events (attribution runs only) |
| Script | rAF callbacks (`FireAnimationFrame`); script ms measured, not modelled | rAF count; script ms through page-side wrappers |
| Style | `UpdateLayoutTree` passes, `elementCount` | `RecalculateStyles` records (**no element count without WKTR**, see below) |
| Layout | passes, forced layouts (with JS stack), `dirtyObjects` | `Layout` records with root (Safari 27 adds the root node) |
| Paint and raster | `Paint` count (**not** area: the clip is the cull rect), raster-invalidation rects × dpr², tiles, paint ops | `Paint` clip area, ΔpaintCount per layer |
| Image decode | `decodedPx` per frame (new component) | `decodedPx` per frame (new component) |
| Layers | layer count, reasons, `drawsContent` | `LayerTree` count, `memory` (backing bytes), 29 reason flags |
| Compositor | `Animation` trace `compositeFailed` bitmask per animation (free-running only) | active accelerated animations × requested rate (80-120 Hz each, [04 §2.3]) as a component; layer reason `animation` from the free-running census |
| Frame outcome | `PipelineReporter` states (timing lane only) | `RenderingFrame` segments (timing lane only) |

Tile and raster counts in the container use software raster; headed Mac Chrome uses GPU raster with different tile
geometry (INFERRED [FR §1.6]). V-a compares them per family before any of them is used.

**Why sheet mutations are a family of their own.** In the [09.04] spike, a build that inserted 100 CSS rules during
the scroll had exactly the same `UpdateLayoutTree`, `elementCount`, `Layout`, `dirtyObjects` and `Paint` counts as one
that inserted none; only style-recalc time differed (20-24 ms vs 8-10 ms, CONFIRMED, Chrome 155). From source, one
insertion costs a resolver reset and a full-document style rebuild in WebKit (`StyleScope.cpp` l.585-619
@77db40e2fa70), and with `@layer` rules a rebuild of the whole document's rule data in Blink (`style_engine.cc`
l.3171-3325 @fcacb60bd396) (path CONFIRMED, cost INFERRED [09.03 §1]). The original reads 0 after load (CONFIRMED by
grep [09.03 §4]; SPK-q runs it). The family is part of every declared-complete vector (§4.3); K10 prices it.

**WebKit element counts (decided now, Q10).** WebKit's largest model term is the restyled-element count, and Phase A
does not have it; v1's WebKit costs were dominated by restyle (custom-property restyle 2.2×, presence-flip layouts;
v1 `research/cpu-throttle-calibration/README.md` l.39). So, from M1:
- until a WKTR count exists, the WebKit model is at most `ranks-only` for style-affecting changes, and **class W is
  barred for any diff that touches selectors, classes or custom properties**;
- the 1-day WKTR spike runs on a rented cloud Mac at the start of M3 (this Mac has 16 GB RAM and 69 GB free,
  CONFIRMED [04 §5] and locally), unless you object. v1's cleanest less-work landings were CSS-only diffs [08], so if
  M1 ends early the spike moves into M1.

### 4.3 Step 2: the cost models

Both models are **monotone in counts with non-negative coefficients**, so removing work can never raise a
prediction. Lean proves that for the model as deployed (§5).

- **WebKit (the target)** [04 §7]: `W = J + Σ c·counts` (WebContent main thread);
  `F = max(s²·Ap/R_cg, Bn/R_alloc)` (GPU-process raster wait; the draft's `− overlap` term broke monotonicity and is
  replaced by `max`, [FR §1.4]); `U = c_ui·Nc` (UI-process apply); `dt ≈ max(T_req, W + F + U + δ)` with
  `T_req` = 16.67 ms (60 Hz page rendering, CONFIRMED in source); a separate render-server term `RS`, priced only by
  Instruments on the phone, with "active accelerated animations × requested rate" as its count. Seeds from v1, such
  as about 0.14 ms per repainted layer, are priors only.
- **Chromium (development aid)** [03 §9]: `T_s(f) = κ_s + Σ_j c_{s,j} · x_{s,j}(f)` per stage, checked against the
  scheduler's budget inequalities B1-B4, `k = max(1, ⌈T/I⌉)` vsyncs per frame. Used for mechanism and screening.
  Coefficients are fitted only if an Android phone is added (Q8). Near the B1 boundary the scheduler can switch mode,
  so a screen result there is reported as "mixed" (INFERRED [FR §1.3]).
- **Page factor.** Per-unit cost depends on the page: v1 measured custom-property restyle at 2.2× the blank-page cost
  on fastwork (CONFIRMED, v1 `research/cpu-throttle-calibration/README.md` l.39), and stylesheet size, selector
  shape, DOM depth and layout-object types all matter (INFERRED). The fit is `T = θ_run · ρ_page · (κ + c·x)`, with
  `ρ_page` estimated on arm A (the original) in M3. Predictions from fixtures alone are labelled `uncalibrated` until
  `ρ_page` exists.
- **Fits are constrained to `c ≥ 0`**, including the τ = 0.9 quantile fit (unconstrained quantile regression would
  void the monotonicity theorem).
- **Model status per output:** `uncalibrated` → `ranks-only` (passes V-c and V-d) → `sizes` (also passes V-e).
  Stored per (engine, device, browser build, output).

**Screening without coefficients (class W).** If a variant's count vector is ≤ the baseline's **in every component
and in every frame**, and strictly lower somewhere, then the predicted cost of every frame is no higher under **any**
non-negative coefficients. This is a theorem, restated for the deployed model (with `κ`, indicator terms, `⌈T/I⌉`,
`max` and the p90 predictor), so a "dominates" result needs no calibration. Three conditions make it meaningful:
1. **Per frame, not per zone.** Batching can lower a zone's total while raising one frame's peak.
2. **Frames aligned by content anchor** (crossing coordinates), not by scroll y, so a variant that changes layout
   height compares the same content.
3. **The vector is declared complete for the mechanism class**, and a lint confirms the diff touches no family the
   vector does not count: images and assets, `filter`/`backdrop-filter`, new WAAPI or CSS animations, fonts. A diff
   that fails the lint is class SM. A diff that changes the styling-engine configuration (theme, layers, cache
   options, MUI version) is class SM until K10 has priced it (S11).

**Golden fixtures from v1.** `fwcore screen` is tested on two v1 rulings the lead made by hand: case A (layout passes
per frame dominate → class W) and case B (paint moved 1-3 frames earlier, total equal, more memory → not W) [08].

**Canonical rate.** Steps run at 60 Hz (the iPhone's page-rendering rate). Chromium budgets are also reported at
120 Hz (Q11).

### 4.4 Step 3: calibration

| | iPhone Safari (the target, first) | Mac Chrome (development aid) |
|---|---|---|
| Fixtures | the 9-page suite K1 restyle … K9 presence flip [04 §9], plus **K10 sheet mutation** (none / custom-property write / plain `insertRule` / `@layer` rule / `@keyframes` / appended tag / moved tag / growing sheet; ~2 min of phone time; decides whether MUI rules stay in `@layer mui` [09.03 §5.2]); style and layout fixtures take the original's rule count and custom-property count as **parameters** (restated numbers, never copied CSS) | ~8 synthetic micro-pages, each sweeping one count [03 §9.2], plus K10 |
| Page term | `ρ_page` fitted on arm A in M3 | not fitted |
| Timing truth | Timeline segments joined by `performance.mark`; Instruments for K7 (backdrop) and K8 (CA animations) | `PipelineReporter` + BlinkBreakdown per frame, used for timing parity (PL6) |
| Fit | NNLS on segments; thermal class recorded per run; a block whose thermal class changes mid-block is refused; ABBA order | none, unless an Android phone is added (then NNLS + constrained τ = 0.9 on the Android phone) |
| Re-calibrate when | the Safari/iOS version changes, 14 days pass, or 2 spot-checks fall outside the band | — |
| Device time | ~10 min of fixtures per session, plus holdout scenarios | none |

All fixtures are our own pages in `fixtures/calibration/`. No Fastwork code goes in them.

### 4.5 Step 4: validation and the validity table

- **Pre-registration.** Every candidate carries its predicted Δ by stage and zone before any device data.
- **Holdout scenarios** (3-5 real page scenarios with flags) produce V-c to V-e.
- **Feel check.** v1's blind pairs are rebuilt as flag configurations, and you swipe blind. We need 5 of 5 with no
  sign disagreement (V-f) before the model may stand in for the device for that change class.
- **Validity table** (`results/validity/*.jsonl`). One row per (model output, mechanism class, engine build):
  predictions, device verdicts, transfer check, status. An output that disagrees with the device twice is retired,
  as v1 did in `stats-vs-finger.md` [01 §A.4].
- **Spot-check.** One blind device A/B per 5 landings. Any sign disagreement demotes the output.

### 4.6 What only the phone can tell us (honest limits)

| Limit | Why | Handling |
|---|---|---|
| **Work is not feel** | v1's cost card was right about the work and wrong about what you felt (CONFIRMED [03 §0]) | Decision agreement + blind feel (V-d, V-f); landing classes (§9.2) |
| **Render server / GPU** (backdrop-filter, filter passes, CA animation rate) | Off the rAF path; visible only to Instruments on the device (CONFIRMED [04 §2.2, §4.6]) | Class X: always on the device; `RS` is calibration-only |
| **Finger-only effects** | iOS toolbar resizes (775↔815), velocity-based tile coverage (`scrollTo` sets no velocity [04 §8.3]), 80 Hz runs, layout only while the scroll view is dragging | Replay toolbar steps in the counts lane; a Simulator WDA finger-drag counts profile (count types *stable*, with a stated tolerance) for drag-state mechanisms, as v1's case A used [08]; feel and timing on the device |
| **First-interaction layer builds, hydration** | Count-based predictions missed in the same direction five times in v1 [01 §A.4]; Svelte 5 and React 19 hydrate differently [02 §7]; Emotion still hashes styles on every styled render at hydration (JS only under AOT; ≈ +16 ms script, +27 kB gz in the [09.04] spike, directional) | Class X; `markMeasureStart()` only after `__fw.hydrated`; N5; the M4 whole-page PL6 check includes rest 6 s + first scroll; the `style-engine` A/B (SPK-s) prices the load cost |
| **Emergent dynamics** | Back-pressure, catch-up frames, coalesced layouts: a stepped harness removes them [04 §12] | The device outer loop must still see them |
| **Heat and Low Power Mode** | Coefficients drift; LPM halves rAF to 30 Hz (CONFIRMED [04 §2.3]) | Thermal class per run; θ factor; LPM recorded and refused for calibration |
| **Blink cannot see WebKit-only costs** | presence-flip layouts, `steps()`/`linear()` off the CA path, store discard on resize [01 §A.3] | A separate WebKit count vector and coefficients; never predict iPhone feel from Blink counts |
| **Version skew** | Simulator iOS 26.5 (installed, CONFIRMED locally), phone 26.6.x or 27, host Safari 27.0.1 [04 §12] | Every count and coefficient stored with (engine, family, platform); matching Simulator runtime (Q1) |
| **Experimental interfaces** | `HeadlessExperimental`, BeginFrameControl (Linux only), the Playwright webview backend [03 §12, 04 §4.3] | Pin versions and the container image digest; keep a thin raw Inspector client |

**Primary device metric:** frames > 50 ms per 100 moving frames in the finger's zone, from the swiped run (7 of 7 in
v1). Also reported: slow-frame % (> 34 ms) and the longest frame per zone, binned by **vsync ticks** (proved tick
math) and placed by **crossing coordinates** (the nearest code threshold, not raw y).

## 5. Lean strategy

### 5.1 What is proved

`lean/README.md` lists the inventory. **P** = already proved in the kickoff sketch (`research/kickoff/05-lean-sketch/`,
630 lines, no `sorry`, standard axioms only, MEASURED [05 §0]).

| Tier | Module | Theorems (examples) | v1 bug class it removes |
|---|---|---|---|
| MVP | `Fw/Spec/Frames` | `tick_ge5_iff`, `tick_ge7_iff`, `tick_mono`, `countAbove_antitone`, `tick5_eq_countAbove` (P); near bands disjoint; twin rule | 60 vs 120 Hz tick confusion; the 50.0 ms coin toss |
| MVP | `Fw/Spec/Verdict` | `better_sound`, `better_needs_runs`, duality (P); **`land_null_prob`: under the null (8 exchangeable runs, no ties) the 4v4 rule says "better" with probability exactly 1/70** (enumerate the C(8,4) orderings in `Rat`); the sequential ABBA decision implies the non-overlap verdict | an untested n ≥ 3 branch; two medians; a 1-in-20 false-win rule |
| MVP | `Fw/Spec/Flags` + `Fw/Gen/Registry` | `resolve_sound`, `override_diff` (A/B arms differ in exactly one part) (P); `registry_ok := by decide` on the generated registry | arms that changed more than the named thing |
| MVP | `Fw/Spec/Cost` (`screen`) | `screen_sound` for the deployed model: per-frame componentwise dominance on aligned steps ⇒ every frame's predicted cost (with `κ`, indicators, `⌈T/I⌉`, `max`, p90) is no higher for all coefficients `c ≥ 0` in `Rat` | over-trusting proxies (it formalizes when no calibration is needed) |
| later | `Fw/Spec/Stage`, `Fw/Spec/Step` | `land_requires` (land ⇒ screen passed ∧ reviewer signed ∧ (device verdict ∨ valid licence for the class)); one stage per step; a step is answered at most once | landing without the required evidence; double-answered steps |
| only on an incident | `Thread`, `Log`, `Lease` | ownership, replay invariants, bounded wait | — (the single-writer design removes most of v1's lock and board incidents first) |

**Dropped:** the former "wave 3" (engine decision rules as Lean data, metric reducers, part geometry claims) and the
"≥ 90 % proved" target. A proof about our transcription of an engine rule cannot catch a transcription error. Engine
rule data is checked instead by **table tests** against `compositeFailed` (Chromium) or WKTR (WebKit). At M4 the bug
ledger (V-l) decides whether Lean pays for itself, the way Cedar counted bugs found by proof vs by testing [05 §2]
(Q12).

**Not proved:** engine behaviour, coefficients, pixels, IO adapters, performance numbers. These are measured and
calibrated [05 §4.5].

**Multiplicity.** Each experiment records how many comparisons it made (k). A landing needs `k · p_null ≤ 0.05`:
4v4 (1/70) allows k ≤ 3; above that use 5v5 (1/252, also proved by enumeration) or v1's sequential rule.

### 5.2 How TypeScript and Lean connect

- **Lean decides, TypeScript does** (architecture (i) of [05 §5]). `lean/` is one Mathlib-free Lake project that
  builds the native executable `fwcore` (JSON-lines over stdin/stdout, hardened as in §3.2).
- Types: zod is the source of truth (`packages/contracts`). Lean types derive `ToJson`/`FromJson`. `fwcore samples`
  emits golden JSON that zod must parse byte-for-byte, so the Lean JSON shape cannot drift [05 §2, 06 §2.5].
- Mirrors: only the site's resolver (browser). It is oracle-tested against `fwcore` in TL2 on every change.

### 5.3 A worked example: how to read, prove and test one decision

**How to read a theorem:** the statement (the line after `theorem … :`) **is the spec**. You and the reviewer check
that the statement says what we mean; Lean checks that the proof is right. `#guard` lines are examples that run at
build time.

```lean
-- lean/Fw/Spec/Verdict.lean (MVP)
/-- Landing verdict: 4 control and 4 variant runs; lower is better. -/
def land (ctl var : List Int) : Verdict := verdictN 4 .lower ctl var

/-- Spec 1: "better" means every variant run beat every control run. -/
theorem land_sound (h : land ctl var = .better) : ∀ y ∈ var, ∀ x ∈ ctl, y < x := …

/-- Spec 2: with no real difference, a false "better" happens with probability exactly 1/70. -/
theorem land_null_prob : falseBetterProb 4 4 = (1 : Rat) / 70 := by decide   -- 70 orderings enumerated

-- Examples run at build time (illustrative numbers; real rows are taken from v1's results index):
#guard land [21, 19, 23, 20] [4, 3, 5, 2] = .better
#guard land [21, 19, 23, 20] [4, 3, 5, 22] = .noise
```

The JSON-lines op it backs (one line each way, the id echoed):
`{"id":"r-17","op":"verdict","n":4,"dir":"lower","ctl":[21,19,23,20],"var":[4,3,5,2]}` →
`{"id":"r-17","verdict":"better","pNull":{"num":"1","den":"70"}}`

The oracle test that keeps the browser's TS resolver equal to Lean's (TL2, `@fast-check/vitest`):

```ts
test.prop([arbFlagRequest(registry)], { numRuns: 2000 })('site resolver = fwcore flags.resolve', async (req) => {
  const ts = resolve(registry, req);                              // apps/site/src/registry/resolve.ts
  const lean = await fwcore.call({ op: 'flags.resolve', req });   // id-checked, times out, aborts on panic
  expect(ts).toEqual(lean);
});
```

### 5.4 Test strategy per layer

| Layer | What | Tool | Runs when | Budget |
|---|---|---|---|---|
| TL0 | proofs, `#guard` examples, axiom/`sorry` gate, partial-op grep on `Wire`/`Main` | `lake build`, `lake test`, `scripts/Axioms.lean`, grep for `sorry`, `native_decide`, `implemented_by`, `unsafe`, `!`-ops | `lean/` affected | 0.5 s per changed module (MEASURED) |
| TL1 | pure unit + property tests; no real time, host load, ports, process lists or shared temp folders (lint; 2 s per-test cap); engine rule table tests | Vitest + fast-check | pre-commit, affected packages | < 20 s whole repo |
| TL2 | contracts: zod ⇄ JSON Schema ⇄ Lean golden round trips (incl. the `Rat` wire form); the resolver oracle test | Vitest + `fwcore` | pre-commit, affected | < 30 s |
| TL3 | visual parity per part (PL0-PL4) | Playwright (Chromium + WebKit) | pre-land, affected parts | < 10 s per part per config |
| TL4 | measurement plugins on real engines, incl. harness-neutrality fixtures (V-n) | `fw run` (cached by artifact key) | on demand; pre-land for touched parts | 0 on a cache hit |
| TL5 | device + your finger | console steps | milestone gates and scheduled blocks | scheduled |

**"Gate" means the local gate in M0-M1:** lefthook pre-commit + `pnpm fw gate` (which also re-runs the checks at
land, so a commit made with hooks skipped still cannot land). GitHub Actions on the private repo is optional, only if
the local gate becomes a bottleneck.

## 6. Pluggable parts and flags

### 6.1 Parts

The parts follow the page anatomy in [02 §2]: `nav`, `nav.hitTest`, `nav.langMenu`; `hero.{orbit, deck, exit,
accent, countdown, cue}`; `people.{card, o, deck, carousel}`; `pain`, `pain.notes`; `commission`,
`commission.typing`; `platform.{sweep, glint, entries, stageBg, marquee}`; `morph.{mount, tween, panel, countdown,
columns}`; `overlays.{signup, drawer}`; and the cross-cutting parts `engine.scroll`, `engine.scene` and `images`
(about 32 in all).

**Every part is built from Material UI components** (decided 2026-10-17). These include `Box`, `Stack`, `Container`,
`Typography`, `Button`/`ButtonBase`, `Link`, `AppBar`/`Toolbar`, `Card`, `Avatar`, `Dialog`, `Drawer`, `Menu` and
`Tabs`. The DOM shape and look come from CSS Modules that restate the original's values. Motion comes from our
drivers (§6.5). The engine parts (`engine.*`) contain no markup and need no MUI. MUI's wrapper elements (Paper,
Backdrop, Portal roots) are listed in each part's `parity.json` wrapper map. PL0/PL1 and N3 use that map.

**Experiment parts** (the M5 backlog): `morph.*`, `people.*` (reveal and deck), avatars, `engine.scroll` and
`nav.hitTest` (scroll-engine reads), `hero.countdown`. Only these need full work parity (PL5-PL6). All other parts
need look parity only (PL0-PL3).

Dead CSS (about half of the Platform section's animation CSS never runs [02 §2.6]) is not ported as live rules. The
`faithful` preset can add it back as an **inert stylesheet** with the same rule count (restated, never copied), so
per-element style cost matches the original (INFERRED; decided after the M2 pilot measures the difference).

### 6.2 Registry and variants

Each part has a static `part.json`, which is the single source of truth. TS imports it, and codegen turns it into
`lean/Fw/Gen/Registry.lean`:

```jsonc
{ "id": "hero.countdown", "slot": "hero", "anchors": ["hero-countdown"], "experiment": true,
  "impls": ["mui", "plain"],              // mui = default everywhere; plain = control twin (experiment parts only)
  "muiStates": ["countdown-running"],     // ownerState values the AOT census must render (S2)
  "variants": {
    "faithful": { "kind": "faithful",  "tier": "T1", "layerBudget": 80 },
    "strip":    { "kind": "optimized", "tier": "T0", "provenance": {"v1Fix": "cd-strip"}, "layerBudget": 16 },
    "frozen":   { "kind": "ablation" }, "static": { "kind": "ablation" },
    "nopaint":  { "kind": "ablation" }, "box": { "kind": "ablation" } },
  "requires":  { "morph.countdown:strip": ["hero.countdown:strip"] },
  "conflicts": [] }
```

| Kind | Meaning | Gate |
|---|---|---|
| `faithful` | same DOM shape, the original's CSS values restated; for experiment parts, also the **same per-frame reads and writes**, including the bad ones (rect reads in rAF, a var written on a subtree, 10 layered faces per digit, the `elementFromPoint` hit test, the scroll-jack) | look parity PL0-PL3 (all); PL4-PL6 for experiment parts. **Time box:** 1 agent-day per part, 2 for `engine.*` and `morph.*`. After the time box the part may be promoted as **`faithful-with-delta`**, with the measured difference recorded in the validity table. Exempt from the compositor gate |
| `ablation` | generated per part: `frozen`, `static`, `nopaint`, `box`; `off` only when the preset says `"layoutChanging": true` | v1 fairness check: boxes equal, script and layout counts equal, only paint/raster lower |
| `optimized` | v1 fixes re-implemented from their READMEs (never copied from patches), and new ideas | declared tier verified; **compositor gate** (free-running): `compositeFailed = 0`, layer count = `layerBudget`, no pixel-moving filter animation, no scroll-linked JS style writes, unless the part declares a waiver (Q11) |
| `proposal` | look changes, such as finger-following end or instant People card | your decision via Try-it + blind A/B |
| `impl: plain` (an axis, not a kind) | the same variant with plain elements in place of MUI components, sharing the same CSS Module and drivers; experiment parts only; time box 0.25 agent-day | a measurement control for N3 (§6.7), never shipped in a preset |

**Presets** (`presets/*.json`, with `extends`): `original` (all `faithful`; the parity reference), `v1-best` (g0.0m
rebuilt as flags, including its two proposals), `ablation-<part>`, `v2-best`.

### 6.3 Resolution

- **Order:** URL `?fw=` → `?preset=` → registry default `faithful`. Unknown ids and violated `requires`/`conflicts`
  are an error page, never a fallback.
- The resolved config (variants and `impl`) is sorted and hashed. The hash goes into `window.__fw.configHash`, every
  artifact key and every capture. **A build ID is the commit + the flag vector + the style-engine build variant + the
  MUI/Emotion versions** (+ `servedHash` per route). The style engine is chosen at build time, never by URL.
- **Flags resolve at load, never per frame.** Flipping a flag in a running page re-creates v1's lesson 10 (subtree
  invalidation, `will-change` flips). If ever needed, that is a separate, named experiment.

### 6.4 Choosing what a run measures (the workflow)

From the command line (the same options exist in the console):

```sh
# One part swapped to its optimized variant, both engines, the v1 scripted swipe:
pnpm fw run --preset original --fw hero.countdown:strip --engines chromium,webkit --profile swipe-v1

# Ablate every People part, one arm per part (variant `static` vs faithful), WebKit only:
pnpm fw run --preset original --ablate 'people.*' --engines webkit --profile swipe-v1

# Styling neutrality N3: the MUI part vs its plain control twin, both engines:
pnpm fw run --preset original --impl hero.countdown:plain --engines chromium,webkit --profile swipe-v1

# Timing lane, ABBA n=4, for timing parity or an A/B:
pnpm fw run --preset original --fw nav.hitTest:hit-skip --lane timing --abba 4

# Dry run: show the resolved config, its hash, and which artifacts are cache hits, then exit:
pnpm fw run --preset original --fw hero.countdown:strip --engines chromium --dry
```

Output: raw artifacts go to the local store `<git-common-dir>/fw/artifacts/<key>/`; the run summary goes to
`results/runs/<date>-<configHash7>.json` (committed) with a line in `results/index/runs.jsonl`. `fw report <run>`
prints per-zone counts, the screen result (dominates / mixed / worse) and the model prediction with its status.

**Console "Run builder" view** (console-web): tick parts → pick a variant per part from the registry → pick engines,
profile and lane → see the resolved config, its hash and the cache hits (from `fw run --dry` through console-api) →
queue the run. The queue lives in console-api; results appear in the Results view.

### 6.5 Runtime rules inside parts

1. **No per-frame value goes through React state, context, MUI `sx` or Emotion.** Drivers write refs, inline styles
   or CSS variables on the consuming element, or use WAAPI or scroll timelines.
2. All JS motion goes through the injectable `MotionClock` and the scroll source. Components have no free-running
   `requestAnimationFrame` or `setInterval`.
3. `engine/Signals` gives each scroll threshold **one owner**. The faithful engine reproduces the triple flip at hero
   progress 0.72 in one frame; an optimized engine may split it.
4. The faithful `engine.scroll` is literal: one passive listener, one rAF, callbacks in the original's order, with
   the original's forced-layout order.
5. The site is prerendered (the original's first paint is server-rendered). Only production builds are measured.
6. **Styling: MUI everywhere, Emotion AOT** (decided 2026-10-17; [09] README §1). Material UI 9.5.0 and Emotion
   11.14.x, pinned exactly. A build-only **census route** renders every MUI component in every state the parts
   declare (`muiStates`). `extractCriticalToChunks` (`@emotion/server` 11.11.0) writes those styles to a static,
   linked `mui.[hash].css` in `@layer mui`, plus `emotion-ids.json`. The prerendered HTML has no `<style
   data-emotion>` tags. Before `hydrateRoot`, the client marks every census id in `cache.inserted`, so Emotion
   inserts nothing (mechanism CONFIRMED in Emotion's source, `@emotion/utils` l.54, `@emotion/cache` l.100-113; the
   whole pipeline INFERRED until SPK-r). Measurement builds wrap `cache.insert`, and one miss fails the build. The
   static CSS declares `@layer reset, mui, parts, flags;` first. **Cache wiring** (CONFIRMED in source, review of
   rev 4): the AOT build does **not** use `StyledEngineProvider` (`injectFirst`/`enableCssLayer`). In MUI 9.5.0 that
   provider builds its own client-only cache and wraps the tree in its own `CacheProvider` (`@mui/styled-engine`
   `StyledEngineProvider.js` l.71-130, "This is for client-side apps only"), so a pre-marked cache would be bypassed,
   and on the server it would emit inline `<style data-emotion>` tags. Instead one `createCache({ key: 'mui' })` per
   side goes through `CacheProvider`; the server cache goes through `createEmotionServer`, which sets `cache.compat`
   so no inline tags are rendered (`@emotion/server@11.11.0` `create-instance/index.js` l.9-12;
   `@emotion/react@11.14.0` `emotion-element.tsx` l.92); the `@layer mui {…}` wrap is applied to the extracted file
   at build, and the client cache copies MUI's insert wrapper so that a miss still lands in the layer. Class names
   do not depend on the wrapper (it edits `styles` after the name is hashed). **Portals:** MUI `Portal` renders
   nothing on the server (`Portal/Portal.js` l.41-66), so the census renders every overlay with `disablePortal`, in
   both its closed (`keepMounted`, exited) and open states; otherwise `extractCriticalToChunks`, which keeps only
   ids found in the HTML, drops the overlay styles. **Build variants:** `style-engine: aot` (default);
   `runtime` (plain Emotion SSR, the negative control that N0/N5 must catch); `pigment` (Pigment 0.0.30 with Material
   UI pinned to 9.0.1 in its own workspace package; optional, SPK-s). **Fallbacks:** per part, Base UI 1.9.0 + CSS
   Modules where a part's census cannot be completed, where N0/N1/N5 incidents cannot be fixed inside the part's
   time box, or where its N3 delta comes from styling (§6.7); whole site, the `pigment` variant if SPK-r
   fails at the mechanism level. The rules below extend rules 1-5 (lint = an ESLint or ast-grep rule in `apps/site`;
   N = the gate in §6.7).

   | # | Rule | Prevents | Enforced by |
   |---|---|---|---|
   | S1 | No `sx`, no `styled()`, no Emotion `css`/`keyframes` under `src/parts/**`; style MUI through `className` and `slotProps.*.className` from CSS Modules in `@layer parts` | runtime insertion; class churn | lint; N0 |
   | S2 | Theme `styleOverrides`/`variants` branch only on props whose values are listed in `part.json` `muiStates` | a census miss = an insertion mid-run | census test; N5 |
   | S3 | Per-frame values only through `MotionClock` writers: a custom property on the *consuming* element, inline `transform`/`opacity`, WAAPI or scroll timelines; never React state, props, context or className | React commits, churn | rules 1-2; N2 |
   | S4 | Discrete flips (tab change, menu open, avatar swap) may re-render but must map to classes already in the static CSS | an insertion at a flip | N0 in W-trigger; N2 |
   | S5 | No MUI `Fade`/`Grow`/`Slide`/`Collapse`/`Zoom` on scroll-linked or always-mounted paths; overlays replace `slots.transition` with class-toggled keyframes restated from the original | forced reflow (`node.scrollTop`), rect reads, inline writes from JS | lint; PL4 in the overlay's own scenario |
   | S6 | Ripples off theme-wide (`disableRipple`, `disableTouchRipple` on `MuiButtonBase`); focus styles restated in CSS | a re-render, rect read and `@keyframes` insertion at the first touch of a swipe | theme unit test; N0 in the finger-replay profile |
   | S7 | Tabs: hide the built-in indicator (`slotProps.indicator`) and draw the original's in CSS; no scrollable Tabs; no `Popper`/`Tooltip`/`Autocomplete` on scroll paths. Hiding the indicator does **not** stop MUI `Tabs` from measuring: it reads `getBoundingClientRect` after **every** render (an effect with no deps) and on every window `resize` and tab `ResizeObserver` callback (`Tabs/Tabs.js` l.338-381, l.561-611, l.644-646 @9.5.0), so an iOS toolbar step (775↔815) triggers it mid-swipe. On parts present during scroll scenarios, use `Tab` buttons in a plain `role="tablist"` (or Base UI Tabs) instead of `Tabs`. **Avatar:** pass the `<img>` as a child, never `src`/`srcSet`: with `src`, `useLoaded` creates an off-DOM `new Image()` and commits twice per mount (`Avatar/Avatar.js` l.115-145 @9.5.0), which N0-N3 cannot see | rect reads + `left`/`width` animation; resize-driven forced layouts; hidden commits and image loads | lint; PL5 forced layouts (exact); N2 commit count |
   | S8 | One theme, created at module scope; `cssVariables: true` with `disableStyleSheetGeneration` (variables emitted into the static CSS, trimmed), one colour scheme, nothing written on `<html>` at hydration; `cssVariables: false` if N4 finds too many root custom properties | `<Global>` insertion, root invalidation, consumer re-renders | N0/N1 in W-load/W-rest; N4; N5 |
   | S9 | No Emotion `<Global>` at runtime (`CssBaseline`, `GlobalStyles`, `enableColorScheme`); the reset is static CSS in `@layer reset` | `<Global>` bypasses `cache.inserted` and moves or flushes tags | lint; N0 |
   | S10 | No `useMediaQuery` or `useScrollTrigger` for looks; breakpoints live in CSS | commits on scroll and on toolbar resizes (775↔815) | lint with an allow-list |
   | S11 | Emotion configuration is fixed: production `speedy`, one own cache with key `mui` on server and client (no `StyledEngineProvider`, see cache wiring above), MUI rules in `@layer mui` (static wrap at build; kept unless K10 says otherwise), no `injectFirst`/`prepend`/`insertionPoint`; the configuration and MUI version are in the build ID; every MUI bump re-runs N0-N5 on all parts | an unpriced change to the styling engine | build-ID hash; K10 |
   | S12 | Overlays (`Dialog`, `Drawer`, `Menu`) are closed during scroll scenarios and mounted at load or `keepMounted`; `disableScrollLock` set to match the original at PL4. FocusTrap's 50 ms interval is an allowed exception to rule 2 while a modal is open, measured in the modal's own scenario | insertion and body writes at the trigger; an unmeasured timer | N0 in W-trigger; PL5 in the modal scenario |
   | S13 | The theme uses the original's font families and metrics (no Roboto default) | layout and paint differences that look like styling cost | PL1/PL3; N4 lists `@font-face` |

   **Build gates** (every build): census test with 0 misses; no `<style data-emotion>` in prerendered HTML; no
   `null`, `undefined` or `NaN` values in emitted CSS (the [09.04] spike saw Pigment emit `width:null%` with exit
   code 0); for `pigment` builds, no `data-emotion`, `insertRule` or `stylis` in the built JS.

### 6.6 Parity gate (rewrite vs original)

Arms: **A** = the snapshot served from `snapshot/`; **A2** = A loaded again (A/A, captured in every run); **R** = the
rewrite at preset `original`. Both arms load the same image and font bytes from the same paths.

| Level | Check | Gate | Applies to |
|---|---|---|---|
| PL0 | structure: the anchor set exists and counts match (`parity.json` maps `data-fw` ids to original selectors and lists MUI wrapper elements) | exact, wrappers excluded | all parts |
| PL1 | element boxes at each stop | ≤ 0.5 CSS px | all parts |
| PL2 | computed styles (a property list per anchor); plus N4, the static style-shape census, once per build | exact after normalisation; numeric ≤ 1e-3; N4 as in §6.7 | all parts |
| PL2b | accessibility tree and tab order at each stop | equal to the original's, also when a part hides content by opacity (v1's g0.0m needed a third revision for this [08]) | all parts |
| PL3 | still pixels at fixed stops, animations frozen | v1 tiers against A/A | all parts |
| PL4 | frame-by-frame pixels at 16.667 ms steps, plus motion paths | per frame as PL3; paths within 1 device px | experiment parts |
| PL5 | work counts per scenario (rest 6 s, scripted scroll, the part's trigger), per family; plus N0/N1 sheet mutations and the N2 DOM-write census; N3 against the part's `impl: plain` twin | rAF callbacks and forced layouts **exact**; style and layout passes and elements `|R−A| ≤ max(2, 5 %)`; paint/raster `|R−A| ≤ max(2, 10 %)`; layers ±0; compositor/main split exact; **sheet mutations 0 and N2 equal to the plain twin (exact)**. Bands are proposals, re-set once from the M2 pilot and then frozen (INFERRED) | experiment parts (N0 on all parts) |
| PL6 | timing parity: Mac Chrome timing lane, per stage, R within A's A/A band (ABBA, n ≥ 4); at M4 one Simulator Timeline and one phone whole-page check, including rest 6 s + first scroll, with N5 (hydration neutrality) | within band; N5 green | experiment parts; whole page at M4 |

**Transfer check (V-p), at every landing.** If the change can be expressed as a CSS or script overlay on the
original, the runner applies the same change to arm A in the counts lane and requires the **same sign of Δ per
stage** as on the rewrite. A change that cannot be overlaid is recorded as "transfer unchecked" and cannot land as
class W.

The core viewport matrix runs on every PR: 430×932 and 430×775/815 (toolbar) at DPR 3 with touch; 375×667 and
1440×900 at DPR 2; reduced motion at 430 and 1440. The full 14-config matrix runs before an experiment part is
promoted. The last step is one Simulator check, because Playwright WebKit is not iOS Safari: it has no toolbar and no
Conservative compositing policy [02 §7].

### 6.7 Styling-neutrality gate (N0-N5)

This gate shows that MUI adds no style-sheet mutations, DOM writes, React commits or engine work counts compared with
arm A and with the part's `impl: plain` twin. If it passes, PL5 compares mechanisms, not styling engines [09.03 §2].
It cannot see JS time (Emotion still serialises and hashes on every styled render) or the per-element cost of a
differently shaped style sheet; those are left to N4 as a proxy and to PL6 timing parity. It replaces the rev 3 `STYLE-INJECTION` guard, which
wrapped only `insertRule`/`replace` and watched only `<head>`.

Windows: **W-load** = navigation → `__fw.hydrated`; **W-rest** = `__fw.hydrated` → `markMeasureStart()` (incl. the
6 s rest); **W-measure** = the scenario; **W-trigger** = an interaction scenario's own window.

| Check | What and how | Gate |
|---|---|---|
| **N0** sheet mutations, page side (every counts run, both engines, both arms) | an init script runs before any page script (Chromium: `Page.addScriptToEvaluateOnNewDocument`; WebKit over iwdp: `Page.setBootstrapScript`, present in WebKit main's `Page.json`; or the test server injects it as the first `<head>` script for both arms). It wraps the CSSOM write APIs: `insertRule`/`deleteRule`/`replace*` on sheets, grouping and keyframes rules, the `selectorText` setter, `adoptedStyleSheets`, the `StyleSheet.disabled` setter, `MediaList` mutators, and rule-level `setProperty`/`cssText` (only when `parentRule != null`, so MotionClock's inline writes stay allowed). One `MutationObserver` sees `<style>`/`<link>` adds, removes, **moves** and text edits anywhere in the tree. A hash of `[sheet count, rules per sheet]` is taken at every window edge | W-rest, W-measure, W-trigger: **0**. W-load: equal to arm A's (0) or recorded as a class X delta |
| **N1** sheet mutations, engine side | Chromium: `blink,blink_style` slices `StyleEngine::updateActiveStyleSheets`, `scheduleInvalidationsForRuleSets`, `InvalidateStyleAndLayoutForFontUpdates`. WebKit: `CSS.styleSheet*` events over iwdp, attribution runs only | W-rest and W-measure: **0**. Non-zero on arm A is a harness finding |
| **N2** DOM-write and commit census | per frame and per `data-fw` anchor: `class` and `style` attribute changes, childList mutations; plus React commits per frame per part (a `<Profiler>` counter in measurement builds, as [09.01 §7] proposed). Commits catch MUI work that writes nothing to the DOM (Avatar's `useLoaded`, Tabs' indicator state) | `impl: mui` = `impl: plain`, **exact per frame** for both; equal to arm A where `parity.json` maps the write |
| **N3** work counts, MUI vs plain | the PL5 families on the `impl` pair, same flags otherwise | passes, forced layouts and layers **exact**; `elementCount`/`dirtyObjects` within `max(2, w)`, where w = MUI wrappers in the invalidated subtree (wrapper map); paint/raster: the PL5 band. Until WKTR exists, a style-affecting diff cannot pass N3 on WebKit by counts alone (Q10) |
| **N4** static style shape (once per build, A and R) | at the end of W-rest, walk `document.styleSheets`. Count style rules, selectors by their rightmost compound, `:root` custom properties, `@property`, `@layer`, `@keyframes`, `@font-face`, and `@media` rules (how many match) | rule count and `:root` custom-property count within ±10 % of arm A, or the difference becomes a K-fixture parameter and is flagged for PL6 |
| **N5** hydration | the SSR `class`/`style` per anchor vs the DOM after `__fw.hydrated`; `cache.insert` misses | **0** attribute diffs, 0 misses, 0 style-tag moves |

A failed N0, N1 or N5 is an **incident against the part, never a result**; it is fixed inside the part's time box, or
the part moves to the Base UI fallback. A failed N2 or N3 makes the part `faithful-with-delta`, with the delta in the
validity table, or moves it to the Base UI fallback if the delta comes from MUI. N0 runs in the counts lane. In the timing lane and on the phone, only the end-of-run hash runs, so it
adds no timing cost.

## 7. Repo layout and the knowledge store

### 7.1 Tree (MVP; "later" items are added only when needed, §3.4)

```
fastwork-com-web-optimize-lean/
├─ CLAUDE.md                  < 300 words at Day 1 (≤ 1,500 ever): rules with "Enforced by", trust boundary, lanes
├─ .claude/                   settings.json, agents/*.md, hooks/*.mjs (3 in MVP), skills/*/SKILL.md
├─ .mcp.json                  serena, lean-lsp (local tools only), chrome-devtools (exploration only)
├─ .serena/project.yml        language_servers: [typescript, lean4]  (lean4 checked by SPK-k)
├─ lefthook.yml  pnpm-workspace.yaml  package.json  biome.json
├─ snapshot.lock.json         id + content hash of the Fastwork snapshot (no content)
├─ apps/
│  ├─ site/                   React 19 + Material UI 9.5 + Vite 8, prerendered; /__harness/:part; /__census (build only)
│  │  └─ src/{engine/, registry/, theme/, mui-aot/, parts/<id>/{part.json, parity.json, faithful/, variants/<v>/}}
│  ├─ console-web/            shadcn/ui + Tailwind 4: run builder, steps, results (later: validity, proposals, usage)
│  ├─ console-api/            Node 24 + Hono; single writer; events.jsonl; run queue; fwcore child
│  └─ runner/                 `fw`: run | gate | screen | report | usage | src:fetch | snapshot | sim
├─ packages/
│  ├─ contracts/              zod + generated JSON Schema + golden fixtures (leaf)
│  ├─ measure/                chromium/ (container driver, counts), webkit/ (iwdp, census, timeline), fixtures
│  ├─ model/                  stats + cost model (PURE: no fs, clock, random, browser)
│  ├─ fwcore-client/          id-checked JSON-lines client + oracle tests
│  └─ kb/                     frontmatter schema, index, find, lint
├─ docker/counts-chromium/    Dockerfile pinned by digest; fonts mounted from snapshot/ at run time (no font in git)
├─ lean/                      Lake project fwcore (seeded from research/kickoff/05-lean-sketch)
├─ fixtures/calibration/      our own micro-pages (WebKit K1-K9 first, K10 both engines, Chromium set)
├─ presets/  profiles/        flag presets, priority.json (yours); scroll scripts, viewport and toolbar replays
├─ research/
│  ├─ kickoff/                the kickoff notes and folders (01-09), unchanged
│  ├─ notes/YYYY/MM-DD-<slug>.md          (also per-agent handoff notes; no shared ledger files)
│  ├─ decisions/YYYY-MM-DD-<slug>.md   (ADR: context, options, decision, enforcer)
│  └─ INDEX.md                GENERATED
├─ refs/
│  ├─ external/<slug>.md      papers, docs, articles: link + notes
│  ├─ upstream/               sources.lock.yaml, PINS.md (engine ↔ browser version map),
│  │                          excerpts/<repo>/<path>@<sha7>#L<a>-L<b>.md (≤ 40 lines), protocol/<engine>/*.json
│  ├─ rules/<engine>/<family>/*.yaml   engine decision rules (with table tests)
│  └─ v1/<slug>.md            pointers into v1 (path + commit + summary), never copies
├─ results/
│  ├─ experiments/<date>-<slug>/{card.md, result.json}   (predictions live only in card.md)
│  ├─ runs/  index/*.jsonl  validity/*.jsonl  calibration/<device>/<date>.json  bugs/ledger.jsonl
├─ docs/plan/PLAN.md          this file
├─ snapshot/                  GITIGNORED: the Fastwork original, local only, files read-only
└─ .cache/                    GITIGNORED: sparse upstream clones, raw traces, kb.json
```

### 7.2 Frontmatter (one zod schema in `packages/kb`, checked by `pnpm kb lint`)

```yaml
id: 2026-10-17-webkit-presence-flip       # date-slug: no collisions across worktrees
kind: note | decision | ref | rule
title: "..."
status: draft | review | accepted | superseded
created: 2026-10-17
updated: 2026-10-17
authors: [agent:<role>-<topic>, user]
topics: [measurement, webkit]
engines: [webkit]                          # optional
builds: ["webkit:7624/ios", "chromium:155.0.8059.80"]   # where the claims apply
parts: [people.carousel]                   # must exist in the registry
links: { refs: [], sources: [], experiments: [], v1: [] }
claims: [{ text: "...", status: CONFIRMED | OBSERVED | INFERRED | WEAKENED | REFUTED, cite: "<id|url>" }]
```

A **rule card** (`kind: rule`) adds `statement` (a predicate over a style diff, count or setting), `source {repo,
commit, path, lines}`, `counts` (which count-vector entries it predicts), and `test` (the table test that checks it
against `compositeFailed` or WKTR), and `mechanism: <engine>/<family>/<id>`: `kb lint` fails when two live cards
share a mechanism with opposite statuses (v1's cross-agent contradictions surfaced only through managers [08]).
`fw refs:drift` re-reads each card's cited lines at a new engine tag and flags
changed hunks; that is how the 7624 → 7625 drift would have been caught [04 §11].

### 7.3 What never enters git

- No Fastwork HTML/JS/CSS, images or fonts. Assets are served from `snapshot/`, pinned by hash, and the server
  refuses to start on a mismatch. `fw snapshot` makes the snapshot files read-only.
- No screenshots, diff images or raw traces. They stay in the local artifact store; git gets index lines and
  summaries only (Q15). Simulator frames may be captured; phone-screen frames only for named recording sets made with
  Do Not Disturb on (Q19; v1 changed this rule three times mid-investigation [08]).
- No personal data: no emails, LAN IPs or device ids.

The ported copy and design values in `apps/site/src/parts/**` count as Fastwork-derived. **The repo stays private**
(decided 2026-10-17, Q3). These rules still apply, so that a later partial publication stays possible. Enforced by `.gitignore`, a lefthook pre-commit path and scrub check, deny rules on `git add -f`, Serena
`ignored_paths` and a `kb lint` rule.

## 8. Agent teams

### 8.1 Verified mechanics this design relies on

Checked against Claude Code 2.1.301 docs on 2026-10-17 [07 §2, FR §5]; the settings keys were also found in the
installed binary. Re-verify on upgrade.

- **In-process teammates honour the definition's `model`, `effort`, `tools`, `disallowedTools` and
  `autoCompactWindow`** (CONFIRMED). Split-pane teammates do not. In-process is the documented default, so committing
  `teammateMode: "in-process"` only makes it explicit.
- A teammate brought back re-applies its `.claude/agents/` definition **only if that folder is trusted**
  (CONFIRMED); `session-brief` checks this.
- One team per session; no nested teams; teammates start with the lead's permission mode; `/resume` does not restore
  in-process teammates.
- Teammates never call `EnterWorktree` (v1 I-272). Code-editing roles run as **named worktree subagents**: `name`
  plus `isolation: "worktree"` **on the call** keeps a named spawn a subagent (CONFIRMED by docs, "Subagent names").
  A named spawn **without** `isolation` on the call becomes a teammate in the main checkout, even if the role file
  sets isolation (CONFIRMED); the spawn-guard hook denies that.
- `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS` does not count teammates (CONFIRMED), so the teammate cap is enforced by the
  spawn-guard hook, which has unit tests.
- Task tools are off by default on the 5.5 models (`CLAUDE_CODE_ENABLE_TODO_TOOLS=1`). Settings-file `env` values are
  reapplied to running sessions and this variable is not startup-only (CONFIRMED by docs; SPK-a is a confirmation run).
- Agent permission rules match literal call parameters only (CONFIRMED): a role file with `model: claude-fable-5-1`
  is not caught by an `Agent(model:…)` rule. So Fable is controlled by an `Agent(model:*fable*)` ask rule **and** a
  lint that forbids `fable` in `.claude/agents/*.md`.
- **Observed in v1, re-checked on the v2 version by SPK-p** (INFERRED until then) [08]: a finished background task did
  not wake an idle teammate (I-274; 214 signature matches); a long foreground command left an agent deaf to messages;
  the lead's SendMessage address was `main`, and 20 sends failed on guessed names (19 `lead`, 1 `team-lead`); after a
  compaction the naming rule was lost and 9 unnamed spawns followed. `session-brief` prints the verified address; the
  stall watcher (§8.5) covers the wake gap.

**Bootstrap order.** Day 1-3 run in a **plain session**: the lead works alone or with generic subagents, and no role
file is used before it exists. On Day 3, after elan is confirmed and `settings.json` plus the first agent files are
committed, the session is restarted so `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` takes effect from the committed env,
and the team starts. Writing `.claude/**` prompts you (an `ask` rule); the lead batches those writes into one
sitting on Day 1 and one on Day 3. No second Claude Code session for side tasks: approvals stay in this one (v1's side
session was nothing but approvals [08]).

### 8.2 Roster

Models are pinned to full IDs: `opus` = `claude-opus-5-5`, `sonnet` = `claude-sonnet-5-5`,
`haiku` = `claude-haiku-5-5`, `fable` = `claude-fable-5-1`. `cW` is the context cap (`autoCompactWindow`). The table
is checked against `.claude/agents/*.md` by `pnpm fw roster:check`, so the files are the truth.

| Role | Runs as | Model / effort | cW | Cache TTL | Spawned when | Writes |
|---|---|---|---|---|---|---|
| lead (main session) | session | opus / medium; `high` whenever it speeds a decision | **200k** | 1h (v1's lead ran on 1h and lost $3 to idle rewrites) | always; requests per day reported, not capped; no `CronCreate`; delegates all multi-file reading | lands to `main`; `research/decisions/` |
| engine-researcher (`eng-chromium`, `eng-webkit`) | teammate | opus / high | **200k**, with a written handoff note in `research/notes/` before compaction | 1h | M0-M3 research questions; parked between | `research/notes/`, `refs/**`, fixtures |
| source-locator | subagent (from eng-*) | sonnet / low | 150k | 5m | "where is X computed, file:line@sha" | nothing |
| ref-librarian (`lib-<topic>`) | subagent | haiku / low | 100k, low `maxTurns` (Haiku's price step is at 100k) | 5m | pin sources, write ref and rule cards, `kb lint` | `refs/**` |
| Explore (override) | subagent | haiku / low | 100k | 5m | any search | nothing |
| part-builder (`part-<slug>`) | named worktree subagent | sonnet / medium; per call opus/high for `engine.*`, hero exit, morph, the MUI theme and AOT census, and any part that failed its gate once | 200k | 1h | one part or variant each; time box 1 agent-day (2 for engine/morph) | `apps/site/src/parts/<slug>/**` (theme/AOT: `apps/site/src/{theme,mui-aot}/**`) |
| console-builder (`console-<feature>`) | named worktree subagent | sonnet / medium | 200k | 1h | M0+ console features (the step queue first, §10.2) | `apps/console-*/**` |
| measure-engineer (`meas-<plugin>`) | named worktree subagent | **sonnet / high**; per call opus/high for the cost-model fit, harness neutrality and the N0-N5 gate | 200k | 1h | one plugin or fit each | `packages/measure`, `packages/model` |
| lean-prover (`lean-<module>`) | named worktree subagent (from Day 3) | opus / high; fable per call (ask) for a stuck theorem | 200k | 1h | one Lean module each | `lean/**`, golden fixtures |
| experiment-owner (`exp-<hypothesis>`) | teammate | **sonnet / medium** | 200k | 1h | M5: ≤ 5 alive; 1 agent-day or 3 build iterations per question, then the card and a review | `results/experiments/**`, presets |
| reviewer (`review-<topic>`) | subagent, fresh context, read-only | **opus / medium**; `high`/`xhigh` per call for theorem statements and neutrality-gate rulings | 200k | 5m | the review stage of every change; every new theorem statement | nothing (its verdict is its reply) |
| *(no agent)* | scripts + hooks | — | — | — | gates (tests, parity, `lake build`, `kb lint`), usage meter, device runs and preflight, watchers, queue order, land queue, status digests (§8.5) | `results/index`, console log |

Concurrency, raised in rev 4 for speed: at most **5 teammates** (spawn-guard) and **8 worktree subagents** alive at
once; `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS=10` as a backstop for subagents. The real limit for parallel builders is
this Mac (16 GB RAM, one counts container, one timing queue). `session-brief` shows host memory, and the lead lowers
parallelism when builds start to queue. The caps live in `settings.json` and the spawn-guard reads them from there,
so raising a cap is a one-line change. Kept, because they protect quality and not only cost: at most 10 spawns per
10 minutes per spawner, and depth-2 spawns are read-only helpers (v1: one agent made 133 spawns in an hour, and
unnamed spawns followed [08]). **Cache TTL is chosen by
expected wait:** 1h for roles that wait under an hour on gates, builds or peers; 5m for fresh, short roles; a wait of
an hour or more, or of unknown length (a device session, you), ends the agent with a handoff note (§8.5). Every role
file has `maxTurns`, and each spawn prompt names whom the agent **reports to** (its spawner). "Teams" are lanes inside the one session team
(research, build, measure, proof, experiment, review). Escalate per call (`model`/`effort` parameters), never with a
second role file.

**One committed agent file, in full** (`.claude/agents/part-builder.md`):

```markdown
---
name: part-builder
description: Ports or varies ONE site part behind its flag (apps/site/src/parts/<slug>). Use for part work only.
model: claude-sonnet-5-5
effort: medium
tools: Read, Grep, Glob, Edit, Write, Bash
disallowedTools: WebFetch, WebSearch, Agent
autoCompactWindow: 200000
maxTurns: 150
experimental: { cacheTtl: 1h }
---
You own exactly one part: apps/site/src/parts/<slug>/. Never edit outside it.
Contract: part.json is the truth; restate the original's CSS values, never copy code or assets; build with MUI
components styled only through className/slotProps from CSS Modules (no sx, styled, css; rules S1-S13 in PLAN §6.5);
no per-frame value through React state; motion only through MotionClock. Time box: 1 agent-day (2 for engine/morph);
if parity is not met by then, stop and report the measured delta (faithful-with-delta).
Done = `pnpm fw gate --part <slug>` green. Commit with `git add -- <paths>` and `git commit -m`.
Bash: one plain command per call; multi-step work is a `pnpm fw` verb. Never `node -e`, `sed` on variables,
`python -c`, `cd` or `git -C`. Send your result to the agent you report to; the lead gets at most 300 characters plus a
file path, and `waiting-for: lead|device|user`. To wait an hour or more, write a handoff note and stop.
```

The engine-researcher file differs in `model: claude-opus-5-5` and `effort: high`. `experimental: {cacheTtl: 1h}` is
the per-agent TTL field (CONFIRMED in the sub-agents doc from v2.1.248); the Day 6 meter checks it against the measured
gap distribution per role (§8.4).

### 8.3 `.claude/settings.json` (committed; sketch, strip comments)

```jsonc
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1",
    "CLAUDE_CODE_SUBAGENT_MODEL": "claude-sonnet-5-5",     // default for spawns without a role file
    "CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH": "2",
    "CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS": "10",          // subagents only; teammates are capped by spawn-guard
    "CLAUDE_CODE_ENABLE_TODO_TOOLS": "1"
    // never set CLAUDE_CODE_EFFORT_LEVEL (it overrides every role's effort)
  },
  "teammateMode": "in-process",                            // the documented default, made explicit
  "autoCompactWindow": 200000,                             // the lead
  // no global subagentPromptCacheTtl: TTL is set per role by expected wait (§8.2, §8.4 lever 1)
  "worktree": { "baseRef": "head", "symlinkDirectories": [".cache"] },
  "permissions": {
    "allow": [
      "Edit(/apps/**)", "Write(/apps/**)", "Edit(/packages/**)", "Write(/packages/**)", "Edit(/lean/**)",
      "Write(/lean/**)", "Edit(/research/**)", "Write(/research/**)", "Edit(/refs/**)", "Write(/refs/**)",
      "Edit(/results/**)", "Write(/results/**)", "Edit(/presets/**)", "Edit(/profiles/**)", "Edit(/fixtures/**)",
      "Write(/fixtures/**)", "Edit(/docs/**)",
      "Bash(pnpm fw *)", "Bash(pnpm kb *)", "Bash(pnpm install)", "Bash(pnpm exec *)", "Bash(pnpm test*)",
      "Bash(lake build*)", "Bash(lake test*)", "Bash(lake exe *)",
      "Bash(git status*)", "Bash(git diff*)", "Bash(git log*)", "Bash(git add -- *)", "Bash(git commit -m *)",
      "Bash(git checkout -b *)", "Bash(git worktree add .claude/worktrees/*)", "Bash(git rebase main)",
      "Bash(git merge --ff-only *)", "Bash(gh search code *)", "Bash(xcrun simctl list*)",
      "mcp__lean-lsp__lean_goal", "mcp__lean-lsp__lean_term_goal", "mcp__lean-lsp__lean_diagnostic_messages",
      "mcp__lean-lsp__lean_hover_info", "mcp__lean-lsp__lean_completions",          // local tools only (SPK-l)
      "mcp__serena__find_symbol", "mcp__serena__find_referencing_symbols", "mcp__serena__get_symbols_overview",
      "mcp__serena__find_declaration", "mcp__serena__get_diagnostics_for_file"],
    "ask":   ["Agent(model:*fable*)", "CronCreate", "Edit(/.claude/**)", "Write(/.claude/**)", "Edit(/CLAUDE.md)",
              "Write(/CLAUDE.md)", "mcp__serena__rename_symbol"],
    "deny":  ["Bash(gh api*)",                       // upstream reads go through `pnpm fw src:fetch` (GET only)
              "Bash(git push*)", "Bash(git -C * push*)", "Bash(git commit*--no-verify*)",
              "Bash(git commit -n*)", "Bash(git commit * -n *)", "Bash(git add -f *)", "Bash(git add --force*)",
              "Bash(gh pr *)", "Bash(gh repo create *)",
              "Edit(/snapshot/**)", "Write(/snapshot/**)", "Bash(rm *snapshot/*)", "Bash(mv *snapshot/*)",
              "Bash(cp * snapshot/*)", "Edit(/.cache/upstream/**)",
              "mcp__chrome-devtools__performance_start_trace",
              "mcp__serena__replace_symbol_body", "mcp__serena__insert_after_symbol",
              "mcp__serena__insert_before_symbol", "mcp__serena__replace_content", "mcp__serena__replace_in_files",
              "mcp__serena__safe_delete_symbol", "mcp__serena__write_memory"]
  },
  "hooks": {
    "SessionStart": [/* session-brief.mjs, also on source "compact": roster with live agents' idle minutes and context
                        size, the verified lead address, the naming rule, spend by role today, open steps, device
                        state, disk, agents-folder trust (≤ 15 lines) */],
    "SubagentStop": [/* usage-record.mjs (async): tokens and list-price $ per agent; dedupes by message.id keeping the
                        final stream record; splits 5m from 1h cache writes (two-record unit test: 8, then 210) */],
    "PreToolUse":   [/* spawn-guard.mjs, matcher "Agent": deny an unnamed call, a name that resolves to a live or
                        resumable agent, name + editing subagent_type without isolation, a 6th teammate, > 10 spawns
                        per 10 min per spawner, and model fable without the ask path */]
  }
}
```

Notes:
- Bash patterns are a convenience, not the guard: the real guards are the snapshot hash refusal at serve time,
  read-only snapshot files, `fw gate` re-running checks at land (so a commit made with `-n` cannot land), and the
  land-time path check (a pure, unit-tested function: the diff's paths ⊆ the role's write globs). That path check
  replaces v1's per-role write hook.
- `lean-lsp-mcp` tool names and the flag that disables its remote search tools are checked at install (SPK-l). The
  remote tools are also switched off in `.mcp.json` launch args, if the server supports it.
- After Day 1, the lead runs one dry run, counts permission prompts per hour, and uses the `fewer-permission-prompts`
  skill to add any read-only command that still prompts.
- The allow list holds verb patterns, because worktree agents run one plain command per call (v1: 3,046 isolation
  refusals, 57 % of all errors [08]). SPK-o checks that a named worktree subagent can gate and commit with zero
  refusals.
- The uncommitted `settings.local.json` gives read-only access to the v1 repo, plus deny rules on writing there.

### 8.4 Cost reporting (speed first, no hard caps)

**Decision of 2026-10-17: speed over token savings.** Removed: the ≤ $6.0k project cap, the per-milestone caps and
their +15 % stop rule, the lead's $50/day and 600 requests/day caps, and the Opus ≤ 85 % share. Kept: reporting, a
forecast to report against, and soft alerts.

- **v1's bill was context and idling, not thinking** (MEASURED [08 §3], list price, $11.4k): cache reads 44 % of
  dollars (96 % of tokens), cache writes 41 %, output 14 %. 2,924 cold rewrites after 5-60 min idle cost 24 %; 19
  agents alive over 24 h cost 36 %.
- **Rules kept because they make the work faster or better, not only cheaper:**
  1. **Do not idle:** 1h TTL for waits under an hour; handoff note and exit for longer ones (§8.2, §8.5). A warm
     cache answers faster than a cold rebuild, and a fresh agent with a short note starts from the current state, not
     a stale one (v1: an owner idled 11 h 26 min, then rebuilt its cache).
  2. **No recurring LLM polling;** scripts and watchers check (§8.5). v1's polls were 42 % of the lead's turns, and
     real decisions queued behind them.
  3. **Fresh, short agents with `maxTurns`; 200k context caps with handoff notes.** v1's 645 agents under an hour
     did its cleanest work; long contexts compacted 125 times and lost the naming rule.
  4. **Scripts, not agents, for routing and the device; results peer to peer,** so the lead stays free for decisions
     (v1: the lead answered 78 % of your console messages first).
  5. **Search on Haiku:** faster as well as cheaper.
- **Loosened for speed:** Opus or `high` effort wherever it shortens the path (the lead's decisions, hard parts, the
  MUI theme and AOT census, the neutrality gate, gate failures, reviewer rulings; §8.2); 5 teammates, 8 worktree
  subagents, 10 subagents; up to 5 experiment owners in M5.
- **Forecast, not caps** (rev 3 bottom-up, list-price USD; the meter replaces it; role split in git history at
  931aa35): M0 370 · M1 1,165 · M2 775 · M3 785 · M4 1,450 · M5 1,070 · M6 115 · **total ≈ 5,730**. Revision 4's Opus
  use and concurrency should run about 20-40 % above it (INFERRED), with calendar time below the §10.1 days.
- **Soft alerts, no stops.** A milestone above 1.5× its forecast, a day above 2× the running daily average, or a
  cold-wake share above 10 % adds one line to the daily summary: what drove it, and whether a model, effort, window or
  scope change would help. **The weekly usage limit is the one real stop**, and it is the provider's limit, not a rule of this plan (v1 hit it three times, each time halting
  the lead plus up to 5 agents [08]), so the console header alerts at 60 % and 80 % of it, and the lead slows
  spawning before it.
- **Reporting.** Every experiment card and daily summary carries, from `pnpm fw usage` (a port of v1's transcript
  meter, with the dedupe fix in §8.3): `tokens_by_role`, the cache-read and cold-wake shares, compactions,
  list-price dollars per milestone, role and day, isolation refusals per 100 turns per role, resumes per role, and the
  lead's distinct counterparts and inbound messages per hour (alarms at 10 and 60; v1's p90 was 13 and 80). The
  console header shows usage.

### 8.5 Coordination rules (from the v1 chat history)

Each rule cites the v1 evidence in [08] and is enforced by a script, hook or lint, not by a memory note. **All of them
stay under the looser budget of revision 4.** They exist for speed and quality: a lead free of polls and relays
decides faster, and fresh agents with notes make fewer mistakes than stale ones. Their savings are a side effect
(§8.4).

| Area | Rule | Enforced by | v1 evidence [08] |
|---|---|---|---|
| **Topology** | The lead decides and lands; it does not route. A worker sends its result to its consumer (reviewer, exp-* owner) and gives the lead ≤ 300 characters plus a file path. Reports live in notes and cards, never in messages. Each worker has one manager (its spawner); others send FYIs | role files; spawn prompts name "reports to"; the meter's span alarms | 64 % of messages touched the lead, 16 % went peer to peer; hand-backs ≈ 4k characters; 22 % two-boss switches |
| **No routing agents** | Queue order, land queue, device dispatch, check-in digests, card pre-data reads and console first response to status questions are `pnpm fw` scripts over `events.jsonl`. Only judgement questions wake the lead | §2.2 Drop; console-api | 10 mgmt-ops hub instances; the lead first on 78 % of your console messages |
| **Owner state from events** | `fw` stage commands emit events; the lead reads the projection instead of asking. A hand-back carries `waiting-for: lead\|device\|user`; the lead sends one message per hand-back | console-api; `session-brief` | 39 "crossed" messages, 55 status nags, 1,334 back-to-back lead sends |
| **No LLM polling** | No recurring prompt checks the device, agent liveness or queues. `CronCreate` is `ask`, and `CLAUDE.md` forbids `/loop` status checks. console-api runs three watchers: device (usbmux, WDA, proxy, lock state, Wi-Fi; one status and at most one open re-plug step), stall (a finished background task plus a silent agent gets one wake message), and a coalescer for repeated "finished" and Monitor notices. `pnpm fw status --watch` posts deltas only | §8.3 `ask`; console-api | 3,761 cron fires (42 % of lead turns, 35 % of its $), 864 of them lead-created; 214 wake-gap matches; one "finished" notice repeated 83 times |
| **Waiting** | Wait under an hour: stay alive on the 1h cache, waiting in the foreground with a bounded timeout, never a silent background wait. An hour or more, or unknown: write a handoff note to `research/notes/` and exit; the script that ends the wait (gate, device job, build) spawns a fresh agent with the note | role files; `session-brief` lists live agents with idle minutes and context size | $2,763 of cold rewrites; a device owner idled 11 h 26 min, then rebuilt its cache |
| **Lifetime and compaction** | `maxTurns` on every role; time boxes as request counts the meter checks; no agent lives across two milestone days without a handoff note; after every compaction `session-brief` re-injects the roster, the lead address and the naming rule (≤ 15 lines) | role files; `SessionStart` on `compact` | 19 agents over 24 h = 36 % of $; the naming rule lost at a compaction, 9 unnamed spawns |
| **Names and addresses** | Spawn-guard denies unnamed spawns and names in use; restarts are `<role>-<topic>-<n>`; peer directories are generated from the live roster; one verified lead address | spawn-guard (unit tests); SPK-p | 45 failed sends (20 to guessed lead addresses); 6 same-name reuses |
| **Your attention** | The console is your channel from the first phone or Simulator step (§10.2). Every status row shows "needs you" plus the exact action and the age of its last event (§3.2). One digest per experiment-card stage change, on the card page, not in a thread. Alarms go to an ops log; you see one counter. One question per thread, auto-closed; long topics become pages. Priority is your list (§3.3). Device chores are batched into sessions you book (§4.1) | console-api; console-web | 132 catch-up regex matches; 61 of 80 lead-made threads were alarms; 82-105 of 166 steps were chores; a 500-message thread |
| **Coaching** | Your rules go into role files and `CLAUDE.md` on Day 1 with their enforcers (§2.1), not into memory notes | `kb lint` on role files | the same asks on 11 days; 4 rules broken after they were written |

## 9. Loop protocol v2

### 9.1 Tracks

| Track | Purpose | Stages |
|---|---|---|
| **fidelity** | make a part `faithful` | port → PL0-PL3 (all) → PL4-PL6 (experiment parts) → Simulator check → promoted, or `faithful-with-delta` after the time box |
| **calibration** | keep the model honest | fixtures on device → fit (with `ρ_page`) → holdout → validity table update |
| **experiment** | change a part and land it | **question → build → screen → review → (device) → land**, below |

Time boxes are request counts the meter checks. The part time box (1-2 agent-days) also applies to a **page region**
as a whole (all parts of the end-of-page morph together); going past it needs a decision record (v1: the end-of-page
line took 37 agents and 10.8 % of all cache reads in 78 h [08]).

### 9.2 Experiment stages, gates and signatures

| Stage | What happens | Artifact | Gate | Signed by |
|---|---|---|---|---|
| **question** | hypothesis, part, variants, mechanism (rule cards cited), **pre-registered predicted Δ** per stage and zone, landing class, number of planned comparisons k; order from your priority list (§3.3); for a part whose behaviour is contested, first a class P decision on the behaviour | `results/experiments/<date>-<slug>/card.md` | card schema valid; prediction present before any data | experiment-owner writes, **lead** approves |
| **build** | the variant behind its flag | commit on `<role>/<topic>`; config hash; parity report | `fw gate --part`: typecheck, TL1/TL2, styling lint (S1-S13) and build gates (AOT census, CSS values), declared parity level, compositor gate (optimized, free-running), N0 (+ N2/N3 for experiment parts), path check | script |
| **screen** | counts lane, both engines, original preset vs variant; ablations where needed for attribution; transfer overlay on arm A | artifact keys + `screen.json` (dominates / mixed / worse, per frame on aligned steps; model prediction + status; transfer sign) | determinism per count type; uncounted-family lint; `fwcore screen` | script |
| **review** | fresh-context check: does the result match the card; attribution (positive and negative ablation); no cherry-picking; the `kb lint` mechanism check | `review.md` | reviewer verdict `accept` | **reviewer** |
| **device** (only when the class requires it) | a job card queued for the next session you book; preflight first; phone block C V V C, warm-up, sentinel; blind A/B for feel; the owner hands off and exits while it waits | device record + `fwcore verdict` (4v4, k recorded) | verdict `better` or `level` as declared; validity row written | **you** (the swipe) + script |
| **land** | preset updated; validity table updated with prediction vs outcome | `result.json`; `results/index` line | `land_requires` holds (checked in TS in MVP, by `fwcore stage.step` later) | **lead** (ff-only) |

**Landing classes** decide whether the device stage is needed:

| Class | When | Device needed? |
|---|---|---|
| **W** less work | per-frame componentwise dominance on anchor-aligned steps in both engines, over a vector declared complete for the mechanism class (sheet mutations included, and 0); the uncounted-family lint passes; the diff touches no selector, class or custom property (until WKTR, §4.2) and no styling-engine configuration (S11); the transfer check has the same sign; parity level met; layers within budget | No. Lands on counts; part of the 1-in-5 spot-check sample |
| **SM** smoothness claim or mixed counts | trades one cost for another, claims a feel improvement, or fails any W condition | No, if the model output for this mechanism class has status `sizes` and a valid licence (V-f passed); otherwise yes |
| **X** device-only mechanism | the lint finds `filter`, `backdrop-filter`, `mix-blend-mode` or group opacity changes; toolbar or first-interaction effects; heat | Always |
| **P** proposal | changes the look | Your decision on a Try-it page + blind A/B |

Rules carried over from v1: one change per arm; stalls belong in the slow landing of an eased motion, not the fast
start; a single probe never becomes a rule (claims need the status vocabulary). Every stage change is an event, so the
console shows each card's stage, owner, next step and ETA without anyone asking (§8.5).

## 10. Roadmap

### 10.1 Milestones

| Milestone | Content | Exit criteria |
|---|---|---|
| **M0 Bootstrap as a vertical slice** (Day 1-5) | your Q1 answer (§12.1); the 2026-10-17 decisions (§12.0) written as decision records; minimal settings + CLAUDE.md; the Chromium counts script in a container on the **original**; `fwcore verdict` round trip; WebKit Simulator spike; spikes SPK-a…e, i, j, k, l, o, p, q; the console step queue | two byte-identical Chromium count vectors for the original (or SPK-i failure recorded and V-i re-scoped); `lake build` + axiom gate green; spike answers recorded as decision records |
| **M1 Measure the original** (Day 6-13) | artifact store; per-zone Chromium counts and V-a transfer check; WebKit counts per type (time-boxed Day 7-8, then fallback); harness neutrality fixtures (V-n); `fwcore` MVP modules; console skeleton (run builder, results, Try-it, comment on any row, a preset gallery on Wi-Fi); **in parallel, SPK-r (Emotion AOT)** in a minimal `apps/site` with the MUI theme and census route | Chromium: all used count types deterministic; N0/N1 read 0 on arm A after load (SPK-q); SPK-r passed, or the per-part or whole-site fallback chosen in a decision record; WebKit: the deterministic + stable set covers what K1-K9 need; baseline count vectors per zone for the original; one plugin refactor shows 0 re-runs (V-j) |
| **M2 Pilot parts** (Day 14-18) | `engine.scroll` faithful, `hero.countdown`, `nav.hitTest`, `hero.exit`; registry + resolver + oracle test; harness route; MUI theme + AOT build in the site; pilot parts built with MUI plus `impl: plain` twins; N0-N5 on the pilots; PL0-PL6; optional SPK-s (`style-engine` A/B) | 3 parts `faithful` (V-g, V-h, V-o, V-q); PL5 and N3 bands re-set from pilot data and frozen; `cssVariables` decision from N4; inert-dead-CSS decision made |
| **M3 Calibrate** (Day 19-23) | WKTR spike on a cloud Mac (Q10), with K10 in both engines; SPK-n link soak; iPhone K1-K10 session in a booked window; `ρ_page` on arm A; holdout; validity table v0 | V-b and V-c on the phone; model status per output recorded; `@layer mui` kept or dropped from K10; first V-f attempt scheduled |
| **M4 Port the experiment parts** (Day 24-33) | remaining experiment parts at PL0-PL6 with N0-N3; all other parts at PL0-PL3 with N0; whole-page PL6 check with N5 (Mac Chrome, one Simulator, one phone); console: validity, proposals, usage; **Lean go/no-go from the bug ledger** | every part promoted (`faithful` or `faithful-with-delta`); Simulator check passed |
| **M5 Experiments** (Day 34-43) | first, the end-of-page behaviour decision (class P, Try-it: the `faithful` tween vs the finger-following `proposal`, both against `original`; only the chosen variant is optimized; reversing it later is a preset change); then the 22-row backlog from [01 §A.1] as flag arms, by v1's measured impact: end-of-page morph, People reveal, deck sizing under the toolbar, avatar presence flips, scroll-engine reads, countdown layers, idle loops. Each known v1 outcome is also a **postdiction test** of the model | G1 reached; V-d/V-e/V-f measured on ≥ 10 changes; G2 and G3 reported |
| **M6 Distill** (Day 44-45) | write-up from the G4 material; transfer results; cost report | G4 met; report published (your call) |

### 10.2 The first two weeks, day by day

This starts Monday 2026-10-19, after your review. The countdown target date (2026-11-02) falls right after week 2,
so date pinning is in from Day 1. Already on this Mac (CONFIRMED locally): Xcode with the iOS 26.5 Simulator runtime,
`ios_webkit_debug_proxy`, Docker Desktop, and 69 GB free disk.

| Day | Deliverable | Who |
|---|---|---|
| Day 1 | Your Q1 answer and the 2026-10-17 decisions (§12.0) recorded. Minimal `.claude/settings.json` (env, permissions, no hooks yet) and `CLAUDE.md` under 300 words. **SPK-i:** one standalone script `packages/measure/chromium/counts.mjs` that starts headless-shell (linux-arm64) in a container with BeginFrameControl via `puppeteer-core` + `Target.createTarget({enableBeginFrameControl:true})`, serves the snapshot with its own fonts only, steps the scripted swipe, and writes one count-vector JSON. SPK-k: Serena `find_symbol` on a Lean file. Your coaching rules (§2.1) in `CLAUDE.md` | lead (plain session, generic subagents) |
| Day 2 | Run it twice: byte-identical? **SPK-j** (Chromium side): the clock shim with native rAF vs a free-running run on a small fixture (V-n). **SPK-q** (Chromium side): N0/N1 on arm A. Per-zone counts for the original at 430×775 saved. First V-a comparison against one traced headed Mac Chrome run | lead + generic subagent |
| Day 3 | Lean already installed (elan 4.2.4, Lean 4.35.0, CONFIRMED locally 2026-10-17); `lean-toolchain` pinned to `leanprover/lean4:v4.35.0`; `lean/` seeded from the sketch with request ids, `LEAN_ABORT_ON_PANIC=1`, the partial-op grep and the blank-line reply; `fwcore verdict` round trip from a 30-line TS client. Commit `settings.json` + the first agent files (lead, eng-*, measure-engineer, lean-prover, reviewer, part-builder, console-builder) + the 3 hooks; restart the session; the team starts; SPK-o and SPK-p | lead; lean-prover from the afternoon |
| Day 4-5 | **Console step queue first** (post, Start, answer, Done, on the §3.2 contract), before any Simulator or phone step asks you anything. **WebKit Simulator spike:** Simulator + iwdp; `Page.enable` before `Timeline.start`; `LayerTree` census at held states while free-running; two-rAF stepping trial with native rAF; seek-overhead fixture (N accelerated animations, seeked vs free-running); first per-count-type determinism table; SPK-q on the WebKit side | console-builder, measure-engineer, eng-webkit |
| Day 6 | `contracts` (count-vector schema), the simple artifact store, `fw run` with `--fw`, `--preset`, `--engines`, `--dry`; meter check: idle-gap histogram and cacheCreation vs cacheRead per role (confirms the TTL by expected wait) | measure-engineer, lead |
| Day 7-8 | WebKit stepped counts on the original (**time box**; fallback at the end of Day 8 is held-state censuses + gesture-run timeline counts with tolerance). Simulator runtime matched to the phone (Q1) | measure-engineer, eng-webkit |
| Day 9 | `fwcore` MVP: frames, verdict (4v4 + `land_null_prob`), flags, cost/`screen`; console skeleton: run builder and results from the event log (steps exist since Day 4). **SPK-r** (Emotion AOT, Day 8-10, in parallel) | lean-prover, console-builder, part-builder (opus) |
| Day 10 | M1 review: baseline count report for the original (both engines, per zone, with determinism class per count type); the M2 part plan; SPK-r verdict and the styling decision record; first `pnpm fw usage` cost report against the §8.4 forecast | lead, reviewer |

Added only when their absence causes a failure (week 2 or later): Turborepo, knip, dependency-cruiser, ast-grep rule
sets, REUSE.toml, JCS artifact keys, `kb lint` beyond the frontmatter schema, and the three later hooks. Parallel
during week 2: eng-chromium and eng-webkit turn the rule cards into `refs/rules/**` (seeded with v1's 16 WebKit rules
and the Chromium `compositeFailed` reasons) with table tests, and draft the K1-K9 fixtures.

## 11. Risks and mitigations

| # | Risk | Likelihood / impact | Mitigation |
|---|---|---|---|
| R1 | The React port looks right but does different engine work (reconciliation, effect order, DOM depth, hydration), so findings do not transfer | medium / high | PL5 bands + PL6 timing parity for experiment parts; the transfer check on arm A at every landing; prerender; DOM shape kept close |
| R2 | The model looks precise and steers wrong (v1: right about work, wrong about feel; one 4-5x over-prediction) | medium / high | Decision and feel agreement before any stand-in; "ranks-only" status; class X always on device; spot-checks; retire outputs after 2 misses |
| R3 | WebKit-only and render-server costs are invisible off the device | certain / high | Separate WebKit counts; CA-rate component; `RS` priced by Instruments; class X |
| R4 | Experimental interfaces break (`HeadlessExperimental`, Playwright webview backend, agent-team fields) | medium / medium | Pin versions and the container digest; re-verify fields on each Claude Code upgrade |
| R5 | Coefficients are unidentifiable (collinear flag designs) or drift (heat, LPM, versions) | medium / medium | Micro-fixtures; fractional factorial designs; θ per run; `ρ_page`; re-calibration triggers |
| R6 | Wrong spec, correct proof | medium / high | Reviewer reads statements against the protocol; `#guard` examples from v1 data; no proofs about transcribed engine rules |
| R7 | Over-engineering before the first measurement (v1 day 1 was 38 % process) | high / medium | Week 1 is a vertical slice; MVP tier (§3.4); every new tool names the incident class it prevents; a new agent rule must cite an agent-mistake incident, otherwise fix the tool |
| R8 | Port size: ~11.8k lines of CSS, half dead; Platform visual mapping only inferred | high / medium | Full work parity only for experiment parts; time box per part; `faithful-with-delta` |
| R9 | MUI everywhere pollutes measurements: Emotion inserts or moves style sheets (a WebKit full style rebuild per frame; invisible to the planned counts, CONFIRMED [09.04]), class churn, theme re-renders | high if unconstrained | Emotion AOT (§6.5); rules S1-S13 with lint; N0-N5 (§6.7) with `impl: plain` twins; K10 prices one insertion; SPK-r first; `runtime` build as a negative control |
| R10 | Legal scope of a public port of copy and design values | low now / high | The repo stays private (decided 2026-10-17); assets never in git; the §7.3 rules keep a later partial publication possible |
| R11 | Toolchain churn (Lean monthly, TS 7 native port vs tools, MUI minors) | medium / low | Pin `lean-toolchain` to `leanprover/lean4:v4.35.0`, `typescript@6.0.3` and exact MUI/Emotion versions; bump in one deliberate PR; an MUI bump re-runs N0-N5 on all parts (S11) |
| R12 | `servedHash` under-invalidates (runtime-fetched assets) | low / medium | Assets only through Vite imports; the runner refuses a result whose requests leave the manifest closure |
| R13 | Shared caches in the git common dir fill the disk (v1 I-095); `.lake` is ~214 MB per worktree | medium / medium | `fw cache prune` + size caps; disk in `session-brief` |
| R14 | Spend surprises or hitting the weekly usage limit (more likely now that caps are gone) | medium / medium | Daily cost reporting against the forecast; soft alerts; 60 % / 80 % weekly-limit alerts; 200k context caps, TTL by expected wait, handoff-and-exit, `maxTurns` (§8.4) |
| R15 | The harness changes the mechanism it measures | CONFIRMED / high | No seeking in Chromium; native rAF; seek overhead measured in WebKit; V-n per family |
| R16 | Container counts differ from Mac Chrome (fonts, software raster) | medium / medium | Fonts from `snapshot/` only; V-a per family; Chromium as a development aid |
| R17 | Device link instability: v1 had 36 USB, WDA and Wi-Fi incidents, never root-caused, and a toolchain update broke its compiled link shim [08] | high / high | Device watcher logs every attach and detach from Day 1; preflight before each session; SPK-n link soak with a cable and port swap; no compiled native shims, or a pinned toolchain |
| R18 | Agents stall or go deaf: a background notice does not wake an idle teammate; long foreground commands block messages [08] | medium / medium | Stall watcher in console-api; bounded foreground waits; re-checked by SPK-p on each Claude Code upgrade |
| R19 | The lead becomes the hub again (polls, relays, first responder) [08] | medium / high | §8.5: no LLM polling, no routing agents, results peer-first, span alarms at 10 counterparts and 60 messages an hour |
| R20 | You become the device technician and status bus again [08] | medium / high | G2 chore target; booked sessions with one get-ready step; "needs you" set only by events; status questions answered by script |
| R21 | Emotion AOT fails as a whole: server and client class hashes differ, states the census cannot reach, Popper styles, hydration mismatches that production React does not patch [09.02, 09.03] | medium / high | SPK-r in M1 before any part is built; `cache.insert` miss counter fails the build; per-part Base UI fallback; whole-site Pigment fallback on MUI 9.0.1 (paused alpha, Vite 6 peer range, a build about 25× slower, silent miscompile caught by the CSS-value gate) |
| R22 | MUI behaviour, not styling, breaks parity: Tabs indicator layout animation, transitions with forced reflow, FocusTrap's 50 ms interval, Modal scroll lock, wrapper elements in PL0/PL1/PL5 [09.01 §6] | high / medium | S5-S7, S12; `parity.json` wrapper map; N3 wrapper allowance; per-part Base UI fallback; `faithful-with-delta` |

## 12. Decisions

### 12.0 Decisions made 2026-10-17

| # | Question | Your decision | Applied in |
|---|---|---|---|
| Q2 | Install the Lean toolchain? | **Yes.** elan 4.2.4 and Lean 4.35.0 are installed (CONFIRMED locally). `lean-toolchain` pins `leanprover/lean4:v4.35.0` | §3.2, §10.2 Day 3, R11 |
| Q3 | Repo visibility | **Private.** The §7.3 rules still apply, so that a later partial publication stays possible | §5.4, §7.3, R10 |
| Q4 | MUI scope | **MUI everywhere.** You remembered that CSS-in-JS can be compiled to static CSS. MUI's tool for that is Pigment CSS, which is paused and does not build with MUI 9.1 or later. So the site uses **Emotion AOT** on MUI 9.5, which reaches the same end state: static CSS and no style inserted at runtime. SPK-r and the N0-N5 gate check it. The fallbacks are Base UI per part and Pigment on MUI 9.0.1 for the whole site ([09] README) | §0, §3.1, §4.2, §4.4, §6.1-§6.7, §9.2, R9, R21, R22 |
| Q16 | Budget | **Looser: speed over token savings.** Hard caps and stop rules are removed. Cost reporting, the forecast and soft alerts stay. Opus or `high` effort is used where it speeds the work, and concurrency is higher. The anti-waste rules that also save time stay | §1.1 G3, §8.2-§8.5, R14 |

### 12.1 Answer before Monday (1 question)

**Q1. Devices.**
- What iOS/Safari version is on the iPhone 15 Pro Max? (We download the matching Simulator runtime, several GB; iOS
  26.5 is already installed.)
- May we use Developer Mode + Instruments on the phone during calibration blocks?
- Do you have an Android phone with Chrome? Android is about 74 % of mobile OS share in Thailand in September 2026
  (CONFIRMED, StatCounter, country-wide; fastwork.com's own split is unknown). With one, the Chromium model could be
  calibrated and validated on a real target; without one, Chromium stays a development aid (Q8).
- Phone work runs only in **session windows you book** in the console, each starting with one get-ready step. Which
  times of day suit you, and how long can a session be?
- May the second iPhone stay a free-play device for Try-it and best builds, kept out of measurement?

**Recommend:** yes to Developer Mode + Instruments; add Android only if you already have a device (it adds calibration
sessions); a few fixed windows a week; yes to the free-play phone.

### 12.2 Defaults we will use unless you object (one line each)

- **Q5 Fidelity:** look + work parity (PL0-PL6) for experiment parts; look parity (PL0-PL3) for the rest; time box per part, then `faithful-with-delta`.
- **Q6 Parity reference:** the snapshot `b1789284481295-a455e793`; the faithful morph is the original 680 ms scroll-jacked tween; g0.0m is the preset `v1-best`, and its look changes are proposals.
- **Q7 Device budget:** iPhone 15 Pro Max Safari is the target; expect 5-10 phone sessions before the first licensed class; classes X and P always use the phone; calibration every Safari/iOS change, every 14 days, or after 2 out-of-band spot-checks.
- **Q8 Chromium's role:** a development aid (counts, mechanism, screening, timing parity), with no fitted coefficients, unless Q1 adds an Android phone.
- **Q9 Acceptance bands:** V-a to V-p as in §1.2; a licence is per change class, never for all changes at once.
- **Q10 WebKit element counts:** from now, no class W for style-affecting diffs and ranks-only for style changes; a 1-day WKTR spike on a rented cloud Mac at the start of M3 (one day's rental; cloud Macs often have a 24-hour minimum, INFERRED).
- **Q11 Optimized variants:** compositor gate (free-running), layer budget, no pixel-moving filter animation, no scroll-linked JS style writes unless waived; 60 Hz canonical, 120 Hz also reported for Chromium.
- **Q12 Lean scope:** MVP modules only (Frames, Verdict, Flags, Cost/screen), Stage/Step later, no engine rules in Lean; the bug ledger decides at M4 whether Lean continues.
- **Q13 Landing verdict:** 4 vs 4 runs with a proved 1/70 null rate; comparisons counted per experiment; 5v5 or sequential when k > 3.
- **Q14 Loop protocol:** question → build → screen → review → (device) → land, with classes W/SM/X/P (§9).
- **Q15 Raw traces:** local artifact store only; git gets index lines and summaries.
- **Q17 Agent-team operation and helper tools:** the lead writes one decision record after the M0 spikes, starting from the draft in Appendix C.
- **Q18 Waiting:** 1h cache for roles that wait under an hour (the lead included); for longer waits the agent writes a handoff note and exits (§8.5).
- **Q19 Screen capture:** Simulator frames allowed; phone-screen frames only for named recording sets made with Do Not Disturb on, kept in the local artifact store.
- **Q20 Supervision:** no recurring LLM check prompts; `CronCreate` asks you first; console-api watchers wake agents only on a change (§8.5).
- **Q21 MUI fallbacks and the style-engine A/B:** SPK-r decides. A part falls back to Base UI 1.9.0 + CSS Modules, one at a time, when its census cannot be completed, an N0/N1/N5 incident cannot be fixed in its time box, or its N2/N3 delta comes from MUI (§6.7). The whole site moves to Pigment on MUI 9.0.1 only if SPK-r fails at the mechanism level. The optional Pigment arm (SPK-s, 1 agent-day, M2) runs once unless you say skip.

## Appendix A. Conflicts between the kickoff notes, and how this plan resolves them

| # | Conflict | Resolution | Why |
|---|---|---|---|
| A1 | **Where decisions run.** [05]: Lean decides at runtime via `fwcore`. [06]: TS `core` with differential tests | [05]'s rule for decisions that matter; a TS mirror + oracle test only in the browser (the flag resolver); plain bookkeeping in TS (§3.3) | One implementation; no Lean round trip for a set difference |
| A2 | **Console storage.** [05]: `events.jsonl` + snapshots. [06]: Hono + SQLite | The event log is the truth; SQLite only later, as a disposable read model | MVP tier |
| A3 | **MUI.** [06] and [07] write "React + MUI" for parts; [02] limits MUI after reading its source; [09.04] puts Pigment first, [09.01]-[09.03] put Emotion first | MUI everywhere (your decision, rev 4) with Emotion AOT; Base UI per part and Pigment on MUI 9.0.1 as fallbacks | The engines then see static CSS as with Pigment, on a supported MUI; the remaining confounds are MUI behaviours (S5-S7, S12) and are gated by N0-N5 |
| A4 | **Copying the original.** [07]'s part-builder says never copy class names or CSS. [02] maps anchors to original selectors and restates CSS values | Parts use their own class names; `parity.json` may name original selectors as locators; design values are restated; code and assets are never copied | Parity needs locators and values; the legal line is code and assets |
| A5 | **Serena `rename_symbol`.** [06] enables it; [07]'s draft denies it | `ask` until the Q17 decision record | Your call |
| A6 | **Teammate effort.** [01] (v1, 2.1.286): teammates ignore `effort`. [07] (2.1.301 docs): in-process teammates honour it | [07]; CONFIRMED again by [FR §5] | Newer docs |
| A7 | **Acceptance thresholds.** [03] and [04] propose different sets | Merged into V-a to V-p (§1.2), with the Chromium fit made optional | They measure different things |
| A8 | **The compositor gate vs faithful variants.** | The gate applies to `optimized` variants only | Faithful variants exist to reproduce costs |
| A9 | **Lifecycle.** [05]'s sketch proves v1's R→I→D→F→V→L | v2's question → … → land (§9); proved later (Stage/Step), checked in TS in MVP | Engine-stat measurement changes the gates, as [05 §7 Q4] anticipated |
| A10 | **Reference store paths.** [01] `references/`; [04] `refs/webkit/…`; [06] `refs/upstream/…` | `refs/upstream/` for pins, excerpts and protocol; `refs/rules/<engine>/<family>/` for rule cards | One store for both engines |
| A11 | **Spec-reviewer model.** [05]: mid-tier is enough. [07]: Opus high/xhigh | Opus medium; `high`/`xhigh` per call for theorem statements and neutrality-gate rulings (§8.2) | Wrong spec is the main Lean risk (R6); effort where it speeds a correct ruling (§8.4) |
| A12 | **An `ask` rule on every measurement-code edit** ([07] draft) | Dropped; the golden-semantics gate and the review stage guard it | It would interrupt you without adding a check |
| A13 | **Snapshot location.** [02]: `FW_SNAPSHOT_DIR`. [06]: gitignored `snapshot/` | `snapshot/` (gitignored, read-only), filled by `fw snapshot` from `FW_SNAPSHOT_DIR` and verified against `snapshot.lock.json` | One path for tools, one variable for the machine |
| A14 | **Where the cost model lives.** [05]: `Cost.lean`. [06]/[03]: TS `cost-model` | Fitting and evaluation in TS (`packages/model`); the screening theorem in Lean (`fwcore screen`) | Fitting is numeric; the landing decision is not |
| A15 | **Bootstrap order.** [06]: site skeleton first. [03], [04]: counts first | Counts on the **original snapshot** first, as a Day 1 vertical slice | Baseline first; de-risks the method (R7) |
| A16 | **Cache TTL.** [08]'s lenses: "1h for waiting roles" vs "keep 5m for device-blocked owners" | By expected wait: 1h under an hour; handoff and exit for longer | A 1h cache cannot span an overnight device wait, and an agent should not be alive during one |

## Appendix B. Spikes (each answer becomes a decision record)

| Spike | Question | Status before running |
|---|---|---|
| SPK-a | Does `CLAUDE_CODE_ENABLE_TODO_TOOLS` take effect from the project `env`? | CONFIRMED by docs; one confirmation run |
| SPK-b | Does `name` + `isolation: "worktree"` on one Agent call give a named, messageable worktree subagent? | CONFIRMED by docs; one confirmation run |
| SPK-c | Do hooks inside in-process teammates carry `agent_type`, or only `agent_id`? | open |
| SPK-d | Does `Agent(model:*fable*)` match (wildcards in parameter values)? | open (INFERRED yes) |
| SPK-e | Where do teammate transcripts live, for the usage meter? | open |
| SPK-f | Do per-package `CLAUDE.md` files load when an agent works in that package? (Turborepo `cacheDir` moves to the later tier) | open |
| SPK-g | Can `xctrace` System Trace attached to macOS Safari decode WebKit kdebug trace points by name [04 §4.6]? | open |
| SPK-h | Do the Chromium trace argument paths (`elementCount`) and the invalidation-rect categories hold on the pinned build [03 §7.4]? Do the N1 slices (`StyleEngine::updateActiveStyleSheets`, `scheduleInvalidationsForRuleSets`, font-update) exist there, and what does the `blink_style` category cost [09.03 §6.4]? | open; before SPK-q relies on N1 |
| SPK-i | Does linux-arm64 headless-shell in a container accept BeginFrameControl with the three flags, with fonts only from `snapshot/`, and give byte-identical count vectors? | open; Day 1 |
| SPK-j | Harness neutrality: clock shim with native rAF vs free-running (Chromium); seek overhead per accelerated animation (WebKit) | open; Day 2 and Day 4-5 |
| SPK-k | Does Serena's `lean4` language server answer `find_symbol` on a Lean file? (`lean4` is in Serena's language list, CONFIRMED in `.serena/project.yml`.) If not: Serena for TypeScript only, lean-lsp-mcp for Lean | open; Day 1 |
| SPK-l | lean-lsp-mcp: exact local tool names, and a launch flag that disables its remote search tools | open; Day 3 |
| SPK-m | WebKit determinism per count type (stepped vs held-state) | open; Day 4-5, 7-8 |
| SPK-n | Device link soak: one hour idle with an attach/detach logger, then a cable and port swap; do WDA, the proxy and UI Automation survive a re-plug? | open; first booked phone session (M3 at the latest) |
| SPK-o | Can a named `isolation: "worktree"` subagent run `pnpm fw gate --part x`, `git add -- p` and `git commit -m` with zero isolation refusals? | open; Day 3 |
| SPK-p | On the v2 Claude Code version: the lead's SendMessage address; does a finished background task wake an idle teammate; does `SessionStart` fire with source `compact` so `session-brief` can re-inject the roster? | open; Day 3 |
| SPK-q | Styling-neutrality baseline: do N0/N1 read 0 on arm A in W-rest and W-measure, in both engines? | expected 0 from a grep of the original's JS (CONFIRMED [09.03 §4]); Day 2 and Day 4-5 |
| SPK-r | Emotion AOT: with Button, Dialog, Menu, Tabs and Drawer in the harness, are there 0 insertions and 0 tag moves after hydration in Chromium and WebKit, nothing inserted when an overlay opens, equal closed-overlay scroll counts and commit counts for `impl: plain` and `impl: mui`, and a green N5? Also checks the §6.5 cache wiring (own `mui` cache, no `StyledEngineProvider`, `createEmotionServer` compat), the census with `disablePortal` overlays, and the `runtime` variant as the negative control (N0/N5 must flag it). Also records trace `UpdateLayoutTree` ms for `aot` vs `runtime` (ABBA, n ≥ 4): in the [09.04] spike a build with 0 scroll insertions (`emotion-v7cv`) still showed 13-15 ms against Pigment's 8-10 ms per scroll phase, while CDP `RecalcStyleDuration` showed no gap (2 runs, unexplained) | mechanism CONFIRMED in Emotion's source, pipeline INFERRED [09.02 §8]; Day 8-10, 1 agent-day (Opus) |
| SPK-s | `style-engine` A/B: Pigment 0.0.30 with MUI 9.0.1 vs AOT on the pilot parts. What are the load and hydration script ms, the heap, the bytes, and N0-N3? | MUI 9.0.1 builds unpatched with Pigment 0.0.30 (Vite 6.4.4) and 0.0.31 (Vite 8.3.4, outside peer ranges); 0 insertions observed for 9.0.1 + 0.0.31 in Chrome only [09.01 §2.2]; WebKit 0 insertions observed for Pigment on 7.3.11 and patched 9.5.0, not on 9.0.1 [09.04] (so 9.0.1 + 0.0.30 at runtime is INFERRED); M2, 1 agent-day, optional (Q21) |

## Appendix C. Draft for the Q17 decision record (agent-team operation and helper tools)

The lead finalises these after the spikes; they are listed here so nothing is hidden.

- Permission mode: `default` with the lane-scoped allow-list (§8.3), not `acceptEdits` or `auto` (v1's auto mode
  refused 211 calls when its classifier was unavailable [08]); prompts per hour counted on the Day 1 dry run.
- `.claude/**` and guard changes batched into planned sittings; no side Claude Code sessions; `CronCreate` behind `ask`.
- Lead: Opus `medium`, `high` whenever it speeds a decision; context cap 200k (not 400k or 1M), for quality and speed.
- In-process teammates (tmux panes lose per-role effort); task tools on; Fable per call only, behind `ask`.
- Telemetry: the local transcript meter only (no OpenTelemetry at first); `includeGitInstructions: false` for agents,
  after the `land` skill exists.
- pnpm workspaces (Turborepo later); bun only as an optional local runner; pin `typescript@6.0.3`.
- Serena with `typescript` (+ `lean4` if SPK-k passes): navigation, plus `rename_symbol` behind `ask`; other edit tools denied.
- lean-lsp-mcp with its remote search tools off (queries leave the machine and help little without Mathlib).
- chrome-devtools-mcp for exploration only, with `--isolated --no-usage-statistics`.

## Appendix D. Review log

### Revision 4 (your decisions of 2026-10-17)

Source: your four decisions, and [09] (`research/kickoff/09-mui-zero-runtime/README.md`, which synthesises
09.01-09.04). Where the 09 notes disagreed, [09] §3 says which way it went: the spike note [09.04] put Pigment first,
and the other three notes put Emotion first.

| # | Change | Where |
|---|---|---|
| 1 | **MUI everywhere with Emotion AOT.** A census route, extraction into static CSS in `@layer mui`, pre-marked `cache.inserted`, and a miss counter. Every part is built from MUI components and styled with CSS Modules. The rev 3 "about 3 parts use MUI" scope and the `impl` pair on "one or two simple parts" are removed | §0, §3.1, §3.2, §6.1, §6.2, §6.3, §6.5, §7.1, §8.2 part-builder file |
| 2 | Styling rules S1-S13 replace rule 6. Build gates: census, no `<style data-emotion>`, no `null`/`undefined`/`NaN` CSS values, no Emotion runtime in `pigment` builds | §6.5 |
| 3 | Styling-neutrality gate N0-N5, a new "sheet mutations" count family, and V-q. The `STYLE-INJECTION` guard is widened into N0/N1. The gate is wired into PL0/PL2/PL5/PL6 | §1.2, §4.2, §4.3, §6.6, §6.7, §9.2 |
| 4 | `impl: plain` is kept as a thin control twin on experiment parts only (N3). `style-engine: aot \| runtime \| pigment` is a build variant: `runtime` is the negative control, `pigment` is optional (SPK-s). Both are kept because they are measured experiments, not dependencies | §6.2, §6.3, §6.4, Q21 |
| 5 | K10 sheet-mutation fixture; SPK-q (N0/N1 on arm A), SPK-r (Emotion AOT, M1), SPK-s (Pigment arm, M2) | §4.4, Appendix B, §10.1, §10.2 |
| 6 | MUI risks: R9 rewritten; R21 (AOT fails as a whole) and R22 (MUI behaviour breaks parity) added; A3 resolved | §11, Appendix A |
| 7 | Lean installed and pinned to v4.35.0; Q2 answered | §10.2 Day 3, R11, §12.0 |
| 8 | Repo private; Q3 answered; GitHub Actions only if the local gate becomes a bottleneck | §5.4, §7.3, R10, §12.0 |
| 9 | Looser budget. Caps and stop rules removed; cost reporting, the forecast and soft alerts kept. Opus or `high` effort where it speeds the work. Concurrency raised to 5 teammates, 8 worktree subagents and 10 subagents. Spawn rate 10 per 10 min. Up to 5 exp-* agents. The anti-waste rules are kept and stated as speed and quality rules | §1.1 G3, §2.2, §8.2, §8.3, §8.4, §8.5, R14, Appendix C |
| 10 | Answered questions moved to §12.0; only Q1 remains before Monday; new default Q21 | §12 |

**Adversarial review of revision 4 (2026-10-17, `review-rev4`).** Small fixes applied in place; larger issues were
returned to you separately.

| # | Fix | Where |
|---|---|---|
| R4-1 | AOT cache wiring: no `StyledEngineProvider` (its `enableCssLayer` cache is client-only and installs its own `CacheProvider`, which would bypass the pre-marked cache and emit inline SSR tags); one own `mui` cache per side, `createEmotionServer` for `compat`, `@layer mui` applied to the extracted file (CONFIRMED in `@mui/styled-engine@9.5.0`, `@emotion/server@11.11.0`, `@emotion/react@11.14.0` source) | §6.5 rule 6, S11; [09] §1 |
| R4-2 | Census renders overlays with `disablePortal` in closed and open states: `Portal` renders nothing on the server, and `extractCriticalToChunks` keeps only ids found in the HTML (CONFIRMED in source) | §6.5 rule 6; SPK-r; [09] §1 |
| R4-3 | S7: MUI `Tabs` measures after every render and on every resize even with the indicator hidden, so scroll-path parts use `Tab`s in a plain tablist; Avatar takes its `<img>` as a child, because `src` triggers `useLoaded` (off-DOM `Image`, two commits per mount) (CONFIRMED, MUI 9.5.0 source) | §6.5 S7; [09] §4 |
| R4-4 | N2 also counts React commits per frame (proposed in [09.01 §7], dropped in rev 4); N0 also wraps `StyleSheet.disabled` and `MediaList`, and names how the init script is injected in each engine (`Page.setBootstrapScript` for WebKit) | §6.7; [09] §4 |
| R4-5 | Neutrality claims narrowed: the gate does not see JS time or style-sheet shape cost (§0, §6.7 intro); V-q says which checks run where (N2/N3 need the plain twin, so experiment parts only); fallback wording in §6.5 and Q21 aligned with §6.7's failure handling | §0, §1.2, §6.5, §6.7, Q21 |
| R4-6 | Pigment evidence corrected: 9.0.1 runtime (0 insertions) was observed with Pigment 0.0.31 in Chrome only; no WebKit or 0.0.30 runtime run on 9.0.1 | Appendix B SPK-s; [09] §0, §2 |
| R4-7 | SPK-r also records `UpdateLayoutTree` ms `aot` vs `runtime`, because the spike's 0-insertion Emotion build still had longer style recalcs in traces; SPK-h also checks the N1 slices | Appendix B |
| R4-8 | Budget text: the weekly usage limit is labelled as the provider's limit, not a plan stop rule; A11 no longer cites cost as the reason for the reviewer's effort | §8.4, Appendix A |
| R4-9 | "Every part is built from MUI" now says "every part with markup", matching §6.1 (`engine.*` has no markup) | §0 |

Not changed: the measurement method, Lean scope, landing classes, and the device lane. The revision 2 and revision 3
tables were compressed to short summaries, to keep the plan near 1,300 lines. Their full text is in git history
(commit 931aa35).

### Revision 3 (chat forensics)

Source: [08] Section 5, 18 ranked improvements, all applied: (1) wait policy, 1h TTL by expected wait and handoff and
exit for waits ≥ 1 h; (2) no LLM polling, watchers in console-api; (3) the device lane as a job queue with booked
sessions and one get-ready step; (4) lifetime and iteration bounds; (5) no routing agents, owner state from events;
(6) `pnpm fw` verbs, one plain command per Bash call; (7) the console as your channel from the first step;
(8) priority is your list; (9) your coaching rules on Day 1; (10) spawn and address hygiene; (11) a message budget;
(12) a re-derived budget (superseded by revision 4); (13) decoupled tooling; (14) enforcer discipline; (15) decide
the end-of-page behaviour first, plus accessibility parity; (16) Simulator finger-drag counts and v1 rulings as golden
tests; (17) harness settings; (18) keep what worked. Q1 gained booked session windows and the free-play phone, and
Q18-Q20 were added. The item-by-item table with section pointers is in git history (`docs/plan/PLAN.md` at commit
931aa35).

### Revision 2 (feasibility review)

All 34 critique items of `[FR]` were applied (3 blockers, 19 major, 12 minor). Among them: the Linux container for
BeginFrameControl, harness neutrality, per-frame class W, the WebKit element-count decision (Q10), the 4v4 verdict
with its proved 1/70 null rate, the hardened Lean glue, the MVP tier and the label glossary. The item-by-item table
is in git history (`docs/plan/PLAN.md` at commit 931aa35, Appendix D).
