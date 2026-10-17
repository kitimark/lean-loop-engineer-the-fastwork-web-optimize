---
id: 2026-10-17-v2-plan
kind: decision
title: "v2 loop-engineering experiment: design and plan (for user review)"
status: review
created: 2026-10-17
updated: 2026-10-17
revision: 7 (catch-up to d41aef0: measure on CI, SPK-i decided with pixel tolerance, WKTR from WebKit's prebuilt products, Q1/Q31/Q33 answered, team changes from the Fable review, dense tables split; rev 6 was a48aa54; see Appendix D)
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
    - research/kickoff/10-automation-and-proof/README.md
    - research/kickoff/11-breakpoints/README.md
    - research/notes/2026/10-17-v2-plan-feasibility-review.md
    - research/notes/env-setup.md
    - research/notes/2026/10-17-spk-drafts/
    - research/notes/2026/10-17-ci-trigger-scope.md
    - research/notes/2026/10-17-wktr-on-github-actions.md
    - research/notes/2026/10-17-gate-gaps-fractional.md
    - research/notes/2026/10-17-gate-gaps-hover-pointer.md
    - research/notes/2026/10-17-team-review-fable.md
    - research/notes/2026/10-17-css-decisions.md
  team:
    - docs/team/improvements/2026-10-17.md
    - docs/team/token-policy.md
    - docs/team/parallel-plan.md
    - docs/team/work-graph.json
    - docs/team/public-ci-brief.md
  v1_repo: ../fastwork-com-web-optimize (read-only)
---

# v2 plan: a measurable, provable loop for the fastwork.com scroll experiment

This is the design for you to review. It merges the kickoff notes, cited as `[01]` to `[09]` with section numbers.
`[08]` is the forensics of v1's raw chat history (§2.3). `[09]` is the MUI zero-runtime study,
`research/kickoff/09-mui-zero-runtime/README.md`, and its sub-notes are cited as `[09.01]` to `[09.04]`. `[10]` is the
automation-and-proof study, `research/kickoff/10-automation-and-proof/README.md`, with sub-notes `[10.01]` to
`[10.04]`. `[11]` is the breakpoint inventory, `research/kickoff/11-breakpoints/README.md`. It also merges the
feasibility review, cited as `[FR]` (`research/notes/2026/10-17-v2-plan-feasibility-review.md`), and the device setup
note `[ENV]` (`research/notes/env-setup.md`). Where the notes disagree, Appendix A says which way this plan goes and
why. Appendix D logs every change. **Revisions 4-5 apply your decisions and requirements of 2026-10-17 (§12.0).
Revision 6 caught up with the public repo, CI and the console core. Revision 7 catches up with 65 more commits (the
catch-up log `[CU]`, `docs/team/improvements/2026-10-17.md`): measuring moves to CI, SPK-i is decided, WKTR needs no
cloud Mac, and you answered Q1, Q31 and Q33.** Open for you: Q32 and the two M2 CSS questions (§12.1). Work runs as
a dependency graph, not a calendar (§10).

**Status words.** CONFIRMED = a note cites a source, doc or v1 record for it, or it was checked on this Mac today.
INFERRED = a design choice or expectation that a spike or measurement must still check. MEASURED = a number from a
run in this repo, with its commit. Targets and thresholds are proposals until you accept them.

## Glossary of labels (each prefix is used for one thing only)

| Label | Means | Where |
|---|---|---|
| **Q1 … Q35** | questions and defaults for you (answered ones in §12.0); Q22-Q30 added in rev 5, Q31-Q33 in rev 6, Q34-Q35 in rev 7 | §12 |
| **M0 … M6** | milestone gates (exit states, not dates) | §10.2 |
| **G1 … G4** | outcome goals | §1.1 |
| **V-a … V-t** | method (validation) criteria | §1.2 |
| **TL0 … TL5** | test layers | §5.4 |
| **PL0 … PL6** | parity levels (rewrite vs original) | §6.6 |
| **N0 … N5** | styling-neutrality checks | §6.7 |
| **S1 … S13** | styling rules inside parts | §6.5 |
| **class W / SM / X / P** | landing classes: less **W**ork, **SM**oothness or mixed, device-only (**X**), **P**roposal | §9.2 |
| **SPK-a … SPK-u** | spikes (short experiments that answer one question) | Appendix B |
| **L1 / L1-cond / L2 / L3** | proof levels: proved in Lean; proved but with a named unprovable premise; Lean spec with Lean-generated code or golden vectors for TS; not provable | §5.1 |
| **tier T0 … T3** | v1's pixel-difference tiers | §6.6 |
| **K1 … K10** | calibration fixture pages: K1-K9 WebKit [04 §9]; K10 sheet mutation, both engines [09.03 §5.2] | §4.4 |
| **R1 … R33** | risks | §11 |
| task ids (`class-freeze`, `gap-device` …) | tasks in `docs/team/work-graph.json`; a task id is also the agent name and the console card id | §10.1 |
| stages | question → build → screen → review → (device) → land, always written as words; derived from evidence events, never set by hand (§9.2) | §9 |

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
| 3. A coupled, bug-prone loop; every tool change re-ran everything | Full suite 250-280 s on every tooling commit; `lock.mjs` grew to 1,685 lines [01 §B.1, 06 §1] | **A proved core with a thin IO shell.** Every provable decision, queue and status view runs in one long-lived Lean 4 process, `fwcore` (§5.1); TypeScript moves data. Results are content-addressed, so a tool change re-runs only that tool's tests (§3) |

**What the chat history adds** (§2.3, [08]): v1's agents did their work well; the loop around them did not. v2 fixes
that with scripts, events and hooks, not with more agents or rules (§8.5). **Nobody writes status** (rev 5): in v1,
10.9 % of tool turns were console upkeep [10.01]; now every console view is a formula over one event log that only
console-api writes. **Lean first, and you read math, not Lean** (rev 5): everything reproducible is proved before it
is coded (§3.3), and every theorem carries its math on a generated page (§5.3).

**What to expect, plainly** (so you can judge pain points 1 and 2 with the right expectations):
- **The phone does not go away.** Before the model may stand in for the phone for one kind of change, it needs a
  calibration session and 5 of 5 blind swipe verdicts that agree with it. Expect **about 5-10 phone sessions before
  the first kind of change is licensed** (INFERRED [FR §1.8]). Changes that only the phone can see (backdrop/filter,
  toolbar, first-touch layer builds: class X) and look changes (class P) always need the phone. After that, phone use
  drops to calibration every 14 days or on a version change, plus one blind spot-check per 5 landings. That is far
  below v1, but it is not zero.
- **MUI everywhere, styles compiled ahead of time (decided 2026-10-17).** Material UI 9.5's Emotion styles are
  rendered at build time into one static CSS file, so no style is inserted after first paint ("Emotion AOT", §6.5).
  Pigment CSS is a paused alpha and only a fallback (CONFIRMED [09.01, 09.04]). A neutrality gate (§6.7) checks that
  MUI adds no sheet mutations, DOM writes, React commits or work counts against a plain twin.
- **Chromium is a development aid; the iPhone is the target.** The Chromium counts lane is fast and deterministic,
  but Chromium cannot predict iPhone Safari, so the cost model is calibrated for WebKit first (§4.4, Q8). There is
  no Android phone (decided 2026-10-17): the Android emulator gives Chrome-for-Android counts only, never timing.
- **Lean costs more up front:** the estimate was about 20 modules and $700-1,100 of Lean work (INFERRED [10.03 §7.1]);
  by 28b18ee `lean/Fw` holds 37 modules and 490 declarations went through math review round 5 (MEASURED). A module
  that costs much and catches nothing moves back to TypeScript (§5.1).

**Since revision 6 (rev 7, [CU]).**
- **Measure on CI, not on this Mac** (your direction, 417d90d): Chromium counts, WebKit Simulator counts, the
  breakpoint gate and WKTR run on GitHub Actions; this Mac keeps only phone sessions and short debug runs (§4.1, §5.4).
- **SPK-i decided** (6b4237e): screening uses deterministic types, plus stable types as totals only; a signed class is
  the worst over at least 3 CI runs; pixel-area types get a relative bound (§1.2 V-i, §4.2).
- **WKTR without a cloud Mac:** WebKit's own prebuilt iOS-simulator products run on GitHub `macos-26` (§4.2, Q10).
- **Your answers:** phone sessions on demand (Q1), spawn-guard blocking after three conditions (Q31), and a
  Simulator or device check for the unreachable gate cells (Q33), which led to a new `unreachable` cell state (§6.6).
- **Lean took over the last console TS stand-ins**, the gate verdict, the work graph and a team health watch (§5.1).

**Headline goal.** Rebuild the page and reproduce v1's outcome on the phone as flag arms, with a fraction of v1's
device time, tool bugs and elapsed time; cost reported, not capped; every claimed speed-up checked by your finger (§1).

**Order of work: a dependency graph, no calendar (decided 2026-10-17).** Workstreams start as soon as their inputs
exist (live status in the console). Milestones M0-M6 are gates: M1 the **original** measured in both engines, M2
three pilot parts, M3 the WebKit model calibrated, M4 all parts promoted, M5 experiments, M6 write-up (§10).

## 1. Goals and success criteria

Each criterion has a measurement and an owner. "Proposal" thresholds become binding once you accept them (Q9).

### 1.1 Outcome goals

| # | Goal | Metric | Target | Checked by |
|---|---|---|---|---|
| G1 | v2 reproduces v1's effect | On the iPhone in your swipe, the `original` preset is within v1's A/A band of the original site, and the `v2-best` preset is at or below v1's g0.0m | slow frames (> 34 ms) ≤ 1.7 %; end-of-page longest frame ≤ 42 ms; the feel metric (§4.6) ≤ g0.0m | phone block + blind A/B (§4.6) |
| G2 | Fewer device blocks, less device chore work for you | phone sessions, device incidents, chore steps per session | ≤ 10 phone sessions to the first licensed class; then ≤ 1 block per class SM landing; device incidents ≤ 10 % (v1 ~40 %); **≤ 1 get-ready step, 0 chore steps per session** (v1: 82-105 of 166 [08]) | console step log, bug ledger |
| G3 | Speed first, cost reported (decided 2026-10-17) | time to each gate (from git history); list-price dollars per milestone, role and day; Opus share; cold-wake share | **no hard caps or stop rules**, no dates (§10). Cost reported daily against the §8.4 forecast; soft alerts at 1.5× a milestone's forecast and at 60 % / 80 % of the weekly limit; total against v1's $11.4k at M6 | `pnpm fw usage` [07 §8] |
| G4 | Write-up material | every landed experiment card has a plain one-paragraph summary and a reproducible clip or chart reference; cleanup never deletes listed evidence | all landed cards (v1: 74 of your messages were about evidence and the article [08]) | `kb lint`; M6 review |

### 1.2 Method goals

| # | Goal | Metric | Target (proposal) | Source |
|---|---|---|---|---|
| V-a | **Count transfer: Chromium** | container (Linux headless-shell) counts vs counts from a traced, non-timed headed Mac Chrome run, per count family | equal per family, or the family is marked "container-only" and never feeds a fitted coefficient | [FR §1.6] |
| V-b | **Count transfer: WebKit** | Simulator count equals phone count at the same held state | ≥ 95 % of states, per count type; failing types are marked "not transferable" | [04 §9] |
| V-c | **Ranking** | Spearman ρ, predicted vs measured cost per variant (holdout) | ρ ≥ 0.8 on the iPhone. Chromium: not scored, since there is no Android phone (Q1, Q8) | [03 §9.3, 04 §9] |
| V-d | **Decision agreement** | sign of predicted Δ vs measured Δ, where the prediction exceeds the noise band | ≥ 90 %, and 0 sign errors among "large" predictions | [03 §9.3, 04 §9] |
| V-e | **Magnitude** | median abs(log(pred/meas)) | ≤ 0.3. If missed, the model is "ranks only" and may not size a change | [04 §9] |
| V-f | **Feel agreement** | blind verdicts with predictions frozen first | 5 of 5, no sign disagreement, before the model can stand in for the device for a change class | v1 `stats-vs-finger.md` via [03 §9.3] |
| V-g | **Visual parity** of each `faithful` part | v1 tiers against a same-run original-vs-original (A/A) baseline | tier **T1** at PL0-PL3 (all parts) and PL4 (experiment parts) in Chromium and Playwright WebKit **at every breakpoint edge** (§6.6); boxes ≤ 0.5 CSS px; one Simulator check at 430×775 DPR 3 | [02 §4]; your requirement of 2026-10-17 |
| V-h | **Work parity** of each experiment part | PL5 bands per count family (§6.6) | within the band for every family; layers ±0; same compositor/main-thread split | [02 §4.6, FR §2] |
| V-i | **Determinism, per count type** (decided in rev 7, below) | repeated CI runs classified by Lean `measure.classify` (`Fw/Measure/Classes`) | every count type *deterministic*, *stable* or *quarantined*; screening uses only the first two, as the rules below say | `spk-i.md`, [03 §7.1, 04 §8.5] |
| V-j | **Time to adopt a tool** | new measurement plugin → first cached artifact | ≤ 1 agent-day; tests run = that plugin + `contracts` only; 0 other artifacts invalidated (shown by `fw run --dry`) | [06 §3] |
| V-k | **Test speed** | pre-commit gate; TL1 whole repo | pre-commit ≤ 30 s (affected packages); TL1 < 20 s cold | [06 §3.4] |
| V-l | **Bug ledger, per module** (replaces "share of logic proved") | every entry has `kind: request \| incident`, `module`, `level: L1 \| L1-cond \| L2 \| L3` and `caughtBy: proof \| build-mutant \| property-test \| adapter-test \| replay-monitor \| user \| escaped` | complete ledger; it drives the per-module demotion rule (§5.1), counting incidents only (v1 filed 45 requests as incidents [08]) | [FR §3.1], [10.03 §7.2] |
| V-m | **Bugs in proved areas** | logic incidents in any L1 module (the console reducer and views, queues, gates, verdict, flags, screening, ticks …) | 0 escaped logic incidents (adapter and L3-premise bugs are counted separately) | bug ledger |
| V-n | **Harness neutrality** | on fixtures, frame-stepped counts vs free-running counts, per family | equal per family, else the family is not screened in that engine. Compositor-only animations still cost 1 `UpdateLayoutTree` per frame in Chromium (MEASURED 70c3370), so "0 style work" is never expected | [FR §1.2], [CU] |
| V-o | **Timing parity** (PL6) | Mac Chrome per-stage time, rewrite vs original | rewrite within the original's A/A band (ABBA, n ≥ 4) per stage; plus one Simulator and one phone whole-page check at M4 | [FR §2] |
| V-p | **Transfer to the original** | the same change as an overlay on the original, in the counts lane | same sign of Δ per stage as on the rewrite, for every landing whose change can be overlaid | [FR §2] |
| V-q | **Styling neutrality** of MUI | N0-N5 (§6.7): N0/N1 in every counts run (all parts); N2/N3 on experiment parts (they need the `impl: plain` twin); N4 once per build; N5 per build at hydration | sheet mutations 0 after hydration; DOM-write and commit census and work counts equal to `impl: plain`; style shape within ±10 % of arm A (or a K-fixture parameter); 0 hydration diffs | [09.03 §2] |
| V-r | **Mutant kill rate** | each L1 module ships v1 bugs put back on purpose (`FwTest/Mutants/<module>/*.patch`: I-091, I-113, I-145, I-059, I-185, I-011 incl. head-of-line blocking, I-041, plus design mutants) | 100 % make `lake build` fail; a surviving mutant means the theorem has no teeth and blocks the module's next land | [10.03 §7.2] |
| V-s | **Math sign-off** | every `Fw` theorem and every definition marked user-facing has docstring math whose deep statement hash equals the signed hash | 0 missing, 0 stale, 0 unsigned at land; disagreements between the reviewer's own math and the docstring are counted and reported | [10.04 §2.3] |
| V-t | **No hand-written status** | console fields an agent can set directly; a replay of v1's status history through the v2 reducer | 0 directly settable fields (every agent input is a typed, refusable event in the §8.5 catalogue); the replay reports the share of v1 hand states that contradicted git or the steps at the time | [10.02 §6.5] |

**V-i rules** (SPK-i decided by the lead, 6b4237e; `research/notes/2026/10-17-spk-drafts/spk-i.md`):
- **No byte identity.** Whole count files never match (thread ids, GC, async work; MEASURED 70c3370 and CI run
  39029423874), so classes are per count type.
- **Chromium policy** p = (kMax 4 frames, tMax 24 count units), 3 runs: *deterministic* = no frame differs;
  *stable(k, t)* = k ≤ 4 frames differ and run totals differ by t ≤ 24; else *quarantined* (CONFIRMED `Classes.lean`).
- **Pixel-area types** (names ending `AreaPx`) use the total bound max(tMax, ⌊min |total| / 1000⌋); count types are
  unchanged (proved: `classifyU_count`, `classifyU_sound`; 5879861).
- **Use.** Deterministic types frame by frame; stable types only as totals with margin 2t (`margin_exact`);
  quarantined types never (`quarantined_unsound`). "Deterministic only" was rejected: it would drop trace.Layout,
  trace.Paint, trace.RasterTask and LayoutCount, the main scroll-cost signals.
- **Signed class** = the worst class over at least 3 CI workflow runs with the image pinned (task `class-freeze`).
  One run's classes are never signed: they drift between runs of the same code (§4.2, MEASURED).
- **WebKit:** per-cell `absTol`/`relTol`, 2 passes in each of 2 boots; per-step Layout/Paint quarantined, totals
  within 3-5 % (MEASURED 367fec2). The deterministic + stable set must cover what K1-K9 need.

## 2. What we keep and what we drop from v1

### 2.1 Keep (each with its v2 form)

| Keep | Why (v1 evidence) | v2 form |
|---|---|---|
| Frozen, hash-pinned baseline | The pin changed only twice, both on purpose [01 §B.2] | `snapshot.lock.json` pins the original; each rewrite build is pinned by commit + flag vector + `servedHash` |
| One change per arm | Overlays gave clean A/B arms | Overlays become **flag arms**; never bundle fixes in one arm (bundled builds hid causes) |
| A/A noise floor; "better" only with disjoint ranges; ±4 ms twins | g0.0l vs g0.0m was correctly called level [01 §B.2] | The landing verdict is **4 vs 4** runs with disjoint ranges (or v1's sequential ABBA rule); false-win rate under the null ≤ 1/C(8,4) = 1/70 (§5.1); comparisons counted per experiment |
| Prediction cards before data | 17 or more flagged prediction misses in 153 rows | The question card carries a pre-registered predicted Δ per stage and zone (§9) |
| Claim status words, engine-build applicability, "read source first" | Claim C1 (`layerPainted`) reached you as fact on two probes [01 §B.2] | Rule cards in `refs/rules/` with file:line@commit, status (incl. WEAKENED), builds [04 §11] |
| Pixel tiers T0-T3, screencast capture, frozen frames | False 0 % passes after a scroll (P14) | Parity levels PL0-PL6 (§6.6) |
| Element ablation with a fairness check | Showed end-of-page backgrounds cost a median 16 → 3 slow frames [02 §2.6] | Generated ablation variants per part (§6.2) |
| The validated feel metric: frames > 50 ms per 100 moving frames in the finger's zone | The only metric that agreed with you 7 of 7 [01 §A.4] | Primary device metric (§4.6) |
| Less-work landing rule | Gates sized to risk | Landing class W, now per-frame and over a declared-complete vector (§9.2) |
| Proposals with Try-it pages; blind swipe A/B; comment on anything | Look changes are your call; your thumb caught what Chrome missed. 41 proposals, median 10 min to your decision; 94 of 198 of your threads came from comment buttons [08] | The console Proposals view (shadcn); Try-it, comment-on-any-row and a preset gallery on Wi-Fi are M1 features; a second iPhone for free play (Q1) |
| Your coaching, as rules with enforcers | You re-taught the same management behaviour on 11 days; the lead said its role file never told it [08] | From the start, in the lead file and `CLAUDE.md`: the issue loop (cause from data, workaround, long-term fix with an owner), proactive by default, trace before asking, the answer format; each names its enforcer and is re-injected after compaction (§8.5) |
| Named spawns `<role>-<topic>`; one worktree per editor; one lander; ff-only | 0 merge commits in 2,483 [01 §B.2] | Same; the one lander is the lead, through `fw land` (ff-only, after the reducer accepts; §8.2), with a land-time gate [06 §6] |
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
| Many writers to many JSON stores; agents writing board state | 575 board writes a day; 8 stale-board incidents [01 §B.3] | One writer (console-api), one append-only event log, status as a Lean projection. Agents cannot write it (deny rules on `.fw-console/`, §8.3); their only inputs are typed, refusable requests (§8.5). v1: 10.9 % of tool turns were console upkeep [10.01] |
| A 9.7k-word rulebook loaded by every agent | ~8 % of all cache reads [01 §B.3] | Root `CLAUDE.md` under 300 words at the start, never above 1,500; each rule names its enforcer |
| Opus everywhere; the lead as router; 160 agents in 29 h; recurring check prompts | Opus ~97 %; 3,761 cron fires were 42 % of the lead's turns and 35 % of its dollars; the lead was first responder on 773 of 985 of your console messages [01 §C, 08] | Small roster, a model ladder with Opus where it speeds the work, a lead that decides and does not route, no LLM polling, scripts for checks and gates (§8.5) |
| Routing agents (mgmt-ops ×10, desks, clerk, devices, ops-readers) | 47 agents, $847; 47 % of their messages to the lead were land requests; 22 % of workers' consecutive instructions switched between two bosses [08] | `fwcore` decisions over `events.jsonl`: queue order, land queue, device dispatch, digests, card pre-data reads (§8.5) |
| Agents holding device leases; hand-moved queues | 40 scheduler incidents (median fix 2.2 h); ≈ 230 lead hand moves; 264 order-request messages [08] | A device job queue in console-api; priority is a proved Lean function of your list (§3.3, §4.1) |
| Shared ledger files that many agents edit | `ops-handover.md` 569 commits, `PREDICTIONS.md` 378; 94 `rebase --continue` [08] | Predictions in each `card.md`, handovers in per-agent notes, the board as a projection (§7.1) |
| Multi-step inline shell in worktree agents | 3,046 isolation refusals, 57 % of all v1 errors [08] | Committed `pnpm fw` verbs; one plain command per Bash call (§8.2) |
| Hand-built lock code (1,685 lines) | ~39-89 lock incidents depending on the count [01 §B.5, 05 §3] | No lock in the counts lane; one in-process queue in console-api for the timing lane. Many lock incidents were cross-process races that a single writer removes (INFERRED [FR §3.1]) |
| An 842-line git-guard hook | The guard drew its own incidents | git config + deny rules + a land-time path check in `fw gate`; one small spawn-guard hook (§8.3) |

**Rule for every new tool, hook or package:** it names the v1 incident class it prevents, or it waits until
something fails without it. An **enforcer** (alarm, lint, status board) reads only events, never agent self-reports,
ships with false-positive and false-negative golden tests, and reaches ≥ 90 % precision on a log replay before any
alarm reaches you (v1: 61 of 80 lead-made threads were alarms [08]). A new *agent* rule must cite an agent-mistake
incident; otherwise fix the tool (v1: 4 agent-mistake incidents against 139 tooling ones [08]).

### 2.3 What the chat history showed

[08] read v1's 848 raw transcripts (135k model requests): **a star, not a team** (64 % of 12,582 messages touched
the lead, which compacted 125 times); **woken by polls** (42 % of the lead's turns were cron fires); **home-made
coordination broke more than agents did** (139 tooling incidents against 4 agent mistakes; 57 % of errors were
worktree refusals of inline shell); **you were device technician and status bus** (82-105 of 166 steps were chores).
What worked: steps, Try-it proposals, comment buttons, fast replies, short fresh agents, one lander, ff-only.

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
  SNAP[("snapshot/site (tracked unmodified): Fastwork original, arm A")]
  subgraph RUN["apps/runner: fw CLI"]
    LANES["lanes: counts (parallel) | timing (one queue) | device (console step)"]
  end
  subgraph MEAS["packages/measure-chromium, measure-webkit"]
    CR["chromium: counts in a Linux container (headless-shell + BeginFrameControl); traced headed Mac Chrome for transfer and timing"]
    WK["webkit: Simulator counts (Inspector via iwdp), held-state LayerTree census, timeline, device"]
  end
  AS[("artifact store: git-common-dir/fw/artifacts")]
  CM["packages/model: stats + cost model (WebKit W/F/U/RS; Chromium counts)"]
  FW["lean/ fwcore serve: console reducer + views, queues, gates, verdict, ticks, flags, screen"]
  subgraph CON["console"]
    WEB["console-web: shadcn/ui (run builder, steps, results)"]
    API["console-api: Node 24 + Hono, single writer (append + fsync), CLI socket, reconcilers, watchers, jobs"]
  end
  OBS(["observed facts: git refs (reconciler), Claude Code hooks (spool), watchers, transcripts"])
  MV[("docs/plan/loop-plan.html: generated math view")]
  KB[("research/ refs/ results/ + pnpm kb")]
  PHONE(["iPhone Safari: calibration, licences, spot-checks, class X and P"])

  SITE -- "URL ?fw= / ?preset=, window.__fw" --> LANES
  SNAP -- "same harness" --> LANES
  LANES --> CR & WK
  CR & WK -- "count vectors (zod)" --> AS
  AS --> CM
  CM -- "predictions + model status" --> API
  LANES <-- "screen, verdict ops" --> FW
  API <-- "events in, accepted/refused + changed rows out; queries" --> FW
  OBS -- "facts with idempotency keys" --> API
  FW -- "lake exe mathview, build-math-view.mjs" --> MV
  WEB <-- "HTTP + SSE (zod)" --> API
  API -- "device jobs + steps (booked sessions)" --> PHONE
  PHONE -- "timeline segments, verdicts" --> API
  API --> KB
  RES -. "whole-domain test (TL2)" .- FW
  FW -- "generates: breakpoints.gen.json, media strings, constants, golden vectors" --> SITE
```

### 3.2 Modules and their narrow contracts

Rule: a module talks to another only through the contract in this table. Each contract is a zod schema in
`packages/contracts`, exported to JSON Schema and, where Lean reasons about it, mirrored in Lean with golden
fixtures [06 §2.5, 05 §6].

| From → to | Contract | Notes |
|---|---|---|
| runner → site | URL `?fw=part:variant,…`, `?impl=part:plain,…`, `?preset=<id>`, `seed`, `t0`, `rm`; page exposes `window.__fw = {config, configHash, scroll, clock, hydrated, styleMisses, markMeasureStart}` and `<meta name="fw-config">` | The same harness drives arm A (original) by injecting an equivalent `__fw.scroll`; `markMeasureStart()` is refused before `hydrated` [02 §3.5, 09.03 §2] |
| site build → runner | Vite `manifest.json` → `servedHash` per route | Edits to part X change the keys only of routes that serve X [06 §3.1] |
| runner → plugin | `MeasurePlugin {id, semantics, lane, input, output, run, reduce}` | count reduction runs in `fwcore` (§3.3); the plugin's TS keeps only I/O, or passes Lean golden vectors; an output that fails its schema is an incident, never a result [06 §2.4] |
| plugin → artifact store | key = `sha256(canonical JSON of {subject, tool{plugin,semantics}, engine{build,flags}, profile, protocol})` (sorted keys; full JCS later if needed) | Counts artifacts are reused; timing artifacts append samples [06 §3.1] |
| artifact store → model | count vector per (frame, part, zone) + coefficient set `(device, engine build, thermal class, ρ_page)` → `{stage p50/p90, missed vsyncs, status: uncalibrated | ranks-only | sizes}` | Pure; applied at report time, so a refit re-runs no measurement [06 §3.3] |
| TS → fwcore | `fwcore serve` is long-lived and **stateful** (reducer state, queues, gates, work graph). Ops are listed after this table | `Fw/Serve` (14152f1). Apply round trip p50 40 µs; a 100,008-event replay 0.4 s against 36 s for the old list reducer (MEASURED [CU]). **Hardening below** |
| console-web → console-api | typed HTTP + SSE; zod schemas shared from `contracts` | The UI never decides. **Previews always call console-api (and so `fwcore`)**, so the site resolver stays the only mirror |
| agent → device lane | job card `{kind, card, priority class}`; agents never hold the phone; long runs live in console-api, never in an agent's shell | v1: 40 scheduler incidents; runners died with their agent (I-221, I-240, I-256) [08] |
| console-api → status and steps | each status row is **computed, never written** (stage, owner, next action, ETA, staleness, `needs-you` + the exact action); every cell has a "why" popover listing its events; a step shows only after a script checks it is ready | v1: rows saying "waiting on you" with nothing to do [08]; 4,412 hand-written status entries [10.01] |
| agent → console-api | `pnpm fw <verb>` sends one typed request to `.fw-console/run/cli.sock`; the PreToolUse hook `cap.mjs` adds a single-use capability (HMAC over agent type, agent id, tool-use id and the command hash); console-api stamps `actor`; the reducer accepts or refuses | The socket never produces `user`, `script` or `git`; lead iff no agent id (`Fw/Ops/Identity`, dec2d82); `cap.mjs` fails closed [10.02 §6.4] |
| observers → console-api | facts with an idempotency key both the hook and the reconciler can build; hooks write a spool file (< 100 ms, no stdout); git facts come only from the ref reconciler; transcript usage is an upsert per `message.id` | A key is marked seen only when its event is accepted, so a fact that arrived early is applied on re-send [10.02 §6.2] |
| any client → console-api | every request carries `contractsVersion`; a mismatch is refused with "rebase" | v1: worktrees on old tool code misread shared state (I-010, I-011, I-041, I-102) |
| everything → knowledge store | one frontmatter schema; `pnpm kb index | find | lint` | §7.2 |

**`fwcore` ops** (each a Lean function; TS only sends and prints):
- console: `console.apply` (one event → accepted or refused(reason) + changed rows), `.replay`, `.query`, `.reset`,
  `.landReadiness`, `.actor` (acc5d83);
- work graph: `task.*`, `milestone.define`, `plan.trailers` (a `Task:` commit trailer → `task.done`; 0de2fec, acc5d83);
- gates and decisions: `gate.*` (0d02aff), `verdict`, `ticks`, `twins`, `flags.resolve/enumerate`, `screen`, `samples`;
- measurement: `measure.*`, incl. `.classify`, `.selfCheck`, `.snapshotCounts` (baa3291);
- operations: `ops.spawn/pathCheck/usage/meter/hook/obs`, `ops.admit`, `metrics.*` (49b7ff4), `obs.health` (0877f7a).
`ops.gate` (the land-time gate on `Fw.Gate`) is next (task `ops-gate`).

**Hardening the TS ↔ `fwcore` glue** (each item is CONFIRMED as a real failure path in [FR §3.2]):
1. **Request ids.** `fwcore` echoes each request's `id` and replies to **every** line, a blank one included (the
   sketch skips it: `05-lean-sketch/Main.lean` l.7-10); a reply whose id does not match the oldest outstanding
   request kills the child and fails the call.
2. **Timeout and restart.** 10 s per call, 120 s per replay chunk (eacb660); on timeout or exit the client restarts
   `fwcore`, fails the outstanding calls (never a silent retry), and `fwcore serve` rebuilds its state from the log.
3. **Panics abort.** Always spawned with `LEAN_ABORT_ON_PANIC=1`, because a Lean panic otherwise returns a default
   value (lean4 v4.35.0 `src/runtime/object.cpp` l.76-82). Any stderr output is logged as an incident.
4. **No partial operations in the glue.** A grep gate fails the build on `get!`, `head!`, `[i]!`, `panic!` in
   `Fw/Wire.lean` and `Main.lean`.
5. **Numbers.** Counts cross as `Nat`, times as integer **ns**, fitted coefficients as `Rat` with the wire form
   `{"num":"<int>","den":"<positive int>"}` and golden round-trip tests. Never `Float`.

### 3.3 Where each decision runs (one place only)

- **Lean first for everything reproducible (your direction, 2026-10-17; `CLAUDE.md`).** Every pure piece of the
  console, the site, measurement and tooling (decisions, reducers, gates, breakpoint conditions, flag rules, motion
  curves, count reduction, verdicts, test matrices) is specified and proved in Lean **before** it is coded. Then
  (a) it runs in `fwcore`; or (b) Lean generates it (constants, CSS media strings, JSON such as
  `breakpoints.gen.json`, test matrices); or (c) the TS/React code must pass Lean-generated golden vectors. Only I/O,
  rendering and glue stay unproved, and they hold no decision. A TS stand-in is temporary and listed in the report.
- **Code that must run in the browser or stay in TS** (L2): media strings, motion curves, part logic and the flag
  resolver are generated by Lean or checked against Lean golden vectors. The console has **no TS stand-in left**
  (the last ones moved to Lean in acc5d83). The flag resolver's TL2 test covers **every** single-part override of
  every preset (`fwcore flags.enumerate`; a finite domain, so as strong as a proof for that registry version), plus
  2,000 fast-check multi-part cases [10.03 §2.10].
- **Bookkeeping too:** the console reducer and views, the queues, `fw plan`, cache prune, the path check, spawn-guard
  and usage dedupe are L1 modules (§5.1); v1 failed exactly there (hand-kept board, scheduler) [10.03 §1].
- **Priority is data you own.** One ordered list (`presets/priority.json`, or dragged in the console). Both queues read
  it through one proved Lean function of the list, the job class (user step > calibration > class X/P > spot-check)
  and the waiting time (aging, Q27); it starts the most urgent job **that fits** the booked window (no head-of-line
  blocking [10.03 §5]). Agents never set priority; a manual move is an event with a reason (v1: ≈ 230 hand moves [08]).
- **Numbers that are fitted, not decided** (coefficients) live in TS (`packages/model`). Lean proves the **screening
  rule** for the deployed model (§4.3), and an L1 checker accepts the coefficients (non-negative, exact fractions)
  before use [10.03, item cm.5].

### 3.4 MVP tier and later tier

| | MVP (built in M0-M2) | Later (only when a named failure needs it) |
|---|---|---|
| apps | `site`, `runner` (`fw`), `console-web`, `console-api` | — |
| packages | `contracts`, `measure-chromium`, `measure-webkit`, `model` (stats + cost model), `kb`, `fwcore-client` | split `measure-sdk`; separate `artifact-store`, `usage` packages; `core` |
| console storage | `.fw-console/` in the main checkout (gitignored; console-api its only writer): `events.jsonl` (append + fsync, then apply), snapshots, spool, CLI socket, secrets; projection in `fwcore serve`; reconcilers and watchers (§8.5) | SQLite read model (if queries get slow) |
| Lean | Lean-first, by milestone (§5.1): site and parts from the start; M0 console core, queues, spawn-guard, gates, verdict, work graph; M1-M3 the rest of the L1 inventory | only what an incident or a new decision calls for; the optional Mathlib package `FwMath` (§5.2) |
| hooks | Built in `apps/runner/hooks/` (3e67d48, 6756bb9): observer `emit.mjs` (spool-only, ~47 ms median, MEASURED 3fe1876) on session, subagent, compaction and tool events; `cap.mjs` on `PreToolUse(Bash)`; spawn-guard on `PreToolUse(Agent)` in shadow mode, plus `SubagentStart` so workflow spawns are logged too (2a43e6e) | `TaskCreated`/`TaskCompleted` observers, `SubagentStart` role brief |
| repo tooling | pnpm workspaces, Biome, Vitest; one pre-commit hook via `core.hooksPath` running `scripts/scrub.mjs` (0.17 s, d2574b0; not lefthook) | Turborepo, knip, dependency-cruiser, ast-grep rule sets, REUSE.toml, JCS keys |
| knowledge store | 4 kinds (`note`, `decision`, `ref`, `rule`), 5 claim statuses | more kinds if the index needs them |

## 4. Measurement methodology

### 4.1 Three lanes

| Lane | Runs | Determinism | Gives | Never gives |
|---|---|---|---|---|
| **counts** | parallel, no lock, **on GitHub Actions** (below). Chromium headless-shell in a Linux container with BeginFrameControl; WebKit Simulator Mobile Safari through `ios_webkit_debug_proxy`; WKTR (§4.2); optional Chrome on the Android emulator, counts only | per count type (V-i) | work per virtual frame, per 100 px, per part and per scroll zone | milliseconds |
| **timing** | one at a time from the console-api queue: headed Mac Chrome with `PipelineReporter` tracing; Simulator Timeline with `Page.enable` first | statistical (ABBA, n ≥ 4) | per-stage ms on this host, for timing parity (PL6) and A/A bands | iPhone ms |
| **device** | iPhone Safari blocks as **jobs in a console-api queue**, run only in a session you book. Each session starts with `fw device check` (repairs what it can, then posts **one** get-ready step); the queued blocks then run back to back | statistical | the truth for feel; iPhone coefficients; render-server time | anything at scale |

**Measure on CI, not on this Mac** (your direction, 417d90d; `CLAUDE.md`). Chromium counts, WebKit Simulator counts,
the breakpoint gate and WKTR run on GitHub Actions: an agent pushes its `ci/<task>` branch and reads the result with
`gh run view` / `gh run download`. Chromium runs in the container on `ubuntu-24.04-arm`; WebKit on the `macos-26`
image. This Mac measures only (a) the phone in a session you booked, (b) one short debug run (≤ 5 min) while
harness code changes, (c) a lane CI cannot run yet, named in the work graph with the reason. A local run is never
a result. Each workflow has a `paths:` filter and cancels stale runs on `ci/**` only, because 21 of 28 runs touched
no input and 248 of 414 job-minutes were wasted (MEASURED, 6723de2; `10-17-ci-trigger-scope.md`). The free plan
gives 20 concurrent jobs, 5 of them macOS (CONFIRMED, same note).

**Why a container.** Chromium refuses BeginFrameControl on macOS (`headless/lib/browser/protocol/target_handler.cc`
l.62-65 @317846d579b2, CONFIRMED [FR §1.1]). The container serves **every font from `snapshot/`** with no system
fallback, because fallback fonts change line breaks and so layout and paint counts (INFERRED). SPK-i ran
(70c3370): BeginFrameControl works in the container, but whole count files were never byte-identical, so V-i uses
per-type classes (§1.2). Heavy trace categories are used in the counts lane only (v1 saw −17 fps, CONFIRMED [03 §12]).

### 4.2 Step 1: deterministic work counts

**The harness must not change the mechanism it measures** (CONFIRMED [FR §1.2]). Playwright's `page.clock` fakes
`requestAnimationFrame`, so the app's rAF runs outside the rendering steps and loses a frame. Seeking an animation
(`setCurrentTime`) restarts compositor animations in Chromium (`animation.cc` l.576-618 @317846d5) and invalidates
style per animation per step in WebKit (`WebAnimation.cpp` l.587-620 @fba976461fc0). So neither is used in Chromium.

**One virtual frame in Chromium** (both arms):
1. **Driver:** `puppeteer-core` (or raw CDP) creates the target with `Target.createTarget({enableBeginFrameControl:
   true})` in headless-shell started with `--enable-begin-frame-control --run-all-compositor-stages-before-draw
   --disable-new-content-rendering-timeout --disable-checker-imaging --disable-image-animation-resync
   --num-raster-threads=2 --disable-features=WaitForLateScrollEvents` (as built, 70c3370 and 25bd9f4;
   `--deterministic-mode` and `--disable-threaded-animation` were dropped).
2. **Clock shim** before any page script: `Date`, timers and `performance.now` from virtual time, the date pinned to
   `2026-10-01T00:00:00+07:00` (before the countdown target 2026-11-02). It **keeps native `requestAnimationFrame`**.
3. Apply the scroll step from a committed profile (the v1 scripted swipe, a fling, slow drags, v1 finger replays).
4. `HeadlessExperimental.beginFrame({frameTimeTicks})`: animations advance **without seeking**, and rAF callbacks
   fire inside the rendering steps as in real life. 5. Read the counter deltas.

**One held state in WebKit.** The Simulator has no BeginFrameControl, so WebKit stepping needs seeking plus "two
rAFs" (native rAF kept), and WebKit counts are classified per count type (V-i). Seek overhead is measured on a
fixture with N accelerated animations (seeked vs free-running) and the affected counts are tagged `harness-induced`.
Compositor status comes only from free-running `LayerTree` censuses. Time box 2 agent-days; the fallback is held-state
censuses plus timeline counts from a real gesture run, with a stated tolerance (*stable*, not *deterministic*).

`Math.random` is seeded (mulberry32); `t0` and the seed are part of the artifact key.

**What the runs showed.** Classes and their use are the V-i rules (§1.2). The first rows were local debug runs, made
before the measure-on-CI rule; the class counts that matter are the CI rows.

| Finding | Engine | Source |
|---|---|---|
| Whole count files are never byte-identical (thread ids, GC, async); deterministic types held under heavy host load | Chromium | 70c3370 |
| Local runs (rev 6): 28 deterministic, 14 stable, 8 quarantined of 50 types; superseded by the CI rows below | Chromium | ddc91b2 |
| The rewrite under `scrollTo`: all 43 types deterministic except MinorGC | Chromium | 70c3370 |
| A 10 ms barrier floor (`FW_BARRIER_MIN_MS`) cuts a rewrite run from 45 s to 7 s with identical classes | Chromium | 70c3370 |
| CI, 3 workflow runs of 3 runs each (det/stable/quar): 33/20/9, 31/21/10, 27/25/10; with the pixel-area bound 33/22/7, 31/23/8, 27/27/8 | Chromium | 13b6c98, 5879861 |
| Classes drift between runs of the same code: 6 types det → stable, `trace.Paint` stable → quarantined; cause runner noise or an unpinned image (INFERRED), so `class-freeze` pins the image and signs the worst of ≥ 3 runs | Chromium | `spk-i.md` |
| `census.activeTileAreaPx` and `census.drawingAreaPx` leave quarantine under the pixel bound (largest gap 382 ppm) | Chromium | 5879861 |
| Touch wedged BeginFrame (5 of 5 at one frame): `WaitForLateScrollEvents` set a timer at virtual frame time, ~4,900 s ahead of the container clock. Flag off: 21 local runs, at most 1 wedge (retried); CI check is task `touch-ci-verify` | Chromium | 25bd9f4 |
| `HitTest` stays quarantined (touchmove lands in frame k or k+1) | Chromium | 25bd9f4 |
| Per-step Layout, Paint, InvalidateLayout, ObserverCallback quarantined; RecalculateStyles within 1; totals within 3-5 % | WebKit | 367fec2 |
| The first load after a Simulator boot differs (FireAnimationFrame 703-709 vs 729-739), so `--warmup 1` is the default and the Simulator stays booted | WebKit | 367fec2 |
| `RenderingFrame` reads 0 on iOS 27.0 (24A434) and ~60/s on 26.5; to compare on the CI image | WebKit | 367fec2 |
| Host load correlated with counts but was confounded with pass order; a quiet rerun was clean (INFERRED: not the cause) | WebKit | 367fec2 |
| The rewrite's hit-skip cuts RecalculateStyles 164 → 19, but its steps do not align with the original's (74 vs 107): no Δ yet (task `step-align`) | WebKit | 367fec2 |
| CI Simulator runs take 10-38 min and fail at warm-up; task `sim-speed` | WebKit | `10-17-ci-trigger-scope.md` |

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

**Why sheet mutations are a family of their own.** In the [09.04] spike, inserting 100 CSS rules during the scroll
left every planned count unchanged; only style-recalc time differed (20-24 vs 8-10 ms, CONFIRMED, Chrome 155). One
insertion costs a full-document style rebuild in WebKit (`StyleScope.cpp` l.585-619 @77db40e2fa70) and, with
`@layer`, a rule-data rebuild in Blink (path CONFIRMED, cost INFERRED [09.03 §1]). The original reads 0 after load
(SPK-q). The family is in every declared-complete vector (§4.3); K10 prices it.

**WebKit element counts (decided now, Q10).** WebKit's largest model term is the restyled-element count, and Phase A
does not have it; v1's WebKit costs were dominated by restyle (custom-property restyle 2.2×, presence-flip layouts;
v1 `research/cpu-throttle-calibration/README.md` l.39). So, from M1:
- until a WKTR count exists, the WebKit model is at most `ranks-only` for style-affecting changes, and **class W is
  barred for any diff that touches selectors, classes or custom properties**;
- **WKTR without a build** (rev 7; `10-17-wktr-on-github-actions.md`). WebKit's public build archive holds the
  iOS-Simulator WebKitTestRunner with `internals` (315 MB, CONFIRMED); it runs on the iOS 26.5 runtime that this Mac
  and the GitHub `macos-26` image have (CONFIRMED). No WebKit build, no rented Mac, ~3 GB disk. Order: `wktr-local`
  (one debug run) → `wktr-ci-lane` → `calibration`; `wktr-readme-fix` corrects the old "needs a cloud Mac" text. It
  no longer waits for M3 and can start now. The rented cloud Mac (`wktr-cloud`) is a fallback only.
- **Version caveat.** The archive build is pinned WebKit trunk (324039@main), not the WebKit in shipped iOS 27.0, so
  WKTR counts carry that version note and are ranked against the Simulator and the phone in calibration (INFERRED:
  close enough for element counts; checked there).

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
  Coefficients are not fitted: there is no Android phone (Q1, Q8). Near the B1 boundary the scheduler can switch
  mode, so a screen result there is reported as "mixed" (INFERRED [FR §1.3]).
- **Page factor.** Per-unit cost depends on the page (v1: custom-property restyle at 2.2× the blank-page cost,
  CONFIRMED, v1 `research/cpu-throttle-calibration/README.md` l.39). The fit is `T = θ_run · ρ_page · (κ + c·x)`, with
  `ρ_page` estimated on arm A in M3; until then fixture-only predictions are `uncalibrated`.
- **Fits are constrained to `c ≥ 0`**, including the τ = 0.9 quantile fit, and checked by the L1 certificate (§3.3).
- **Model status per output:** `uncalibrated` → `ranks-only` (passes V-c and V-d) → `sizes` (also passes V-e),
  per (engine, device, browser build, output).

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

**Golden fixtures from v1.** `fwcore screen` is tested on two v1 hand rulings: case A (layout passes per frame
dominate → class W) and case B (paint moved 1-3 frames earlier, total equal, more memory → not W) [08]. Steps run at
60 Hz (the iPhone's page-rendering rate); Chromium budgets are also reported at 120 Hz (Q11).

### 4.4 Step 3: calibration

| | iPhone Safari (the target, first) | Mac Chrome (development aid) |
|---|---|---|
| Fixtures | the 9-page suite K1 restyle … K9 presence flip [04 §9], plus **K10 sheet mutation** (8 kinds, ~2 min of phone time [09.03 §5.2]); style and layout fixtures take the original's rule and custom-property counts as **parameters** (never copied CSS) | ~8 synthetic micro-pages, each sweeping one count [03 §9.2], plus K10 |
| Page term | `ρ_page` fitted on arm A in M3 | not fitted |
| Timing truth | Timeline segments joined by `performance.mark`; Instruments for K7 (backdrop) and K8 (CA animations) | `PipelineReporter` + BlinkBreakdown per frame, used for timing parity (PL6) |
| Fit | NNLS on segments; thermal class recorded per run; a block whose thermal class changes mid-block is refused; ABBA order | none (no Android phone; the emulator gives counts, never timing) |
| Re-calibrate when | the Safari/iOS version changes, 14 days pass, or 2 spot-checks fall outside the band | — |
| Device time | ~10 min of fixtures per session, plus holdout scenarios | none |

All fixtures are our own pages in `fixtures/calibration/`. No Fastwork code goes in them.

### 4.5 Step 4: validation and the validity table

- **Pre-registration:** every candidate carries its predicted Δ by stage and zone before any device data (an L1
  check). **Holdout scenarios** (3-5 real page scenarios with flags) produce V-c to V-e.
- **Feel check:** v1's blind pairs rebuilt as flag configurations; 5 of 5 with no sign disagreement (V-f) before the
  model may stand in for the device for that change class.
- **Validity table** (`results/validity/*.jsonl`): one row per (model output, mechanism class, engine build); an
  output that disagrees with the device twice is retired [01 §A.4]. **Spot-check:** one blind device A/B per 5
  landings; any sign disagreement demotes the output.

### 4.6 What only the phone can tell us (honest limits)

| Limit | Why | Handling |
|---|---|---|
| **Work is not feel** | v1's cost card was right about the work and wrong about what you felt (CONFIRMED [03 §0]) | Decision agreement + blind feel (V-d, V-f); landing classes (§9.2) |
| **Render server / GPU** (backdrop-filter, filter passes, CA animation rate) | Off the rAF path; visible only to Instruments on the device (CONFIRMED [04 §2.2, §4.6]) | Class X: always on the device; `RS` is calibration-only |
| **Finger-only effects** | iOS toolbar resizes (775↔815), velocity-based tile coverage (`scrollTo` sets no velocity [04 §8.3]), 80 Hz runs, layout only while dragging | Replay toolbar steps in the counts lane; a Simulator finger-drag counts profile (*stable* types) for drag-state mechanisms [08]; feel and timing on the device |
| **First-interaction layer builds, hydration** | Count-based predictions missed in the same direction five times in v1 [01 §A.4]; Emotion still hashes styles at hydration (≈ +16 ms script, +27 kB gz in the [09.04] spike, directional) | Class X; `markMeasureStart()` only after `__fw.hydrated`; N5; the M4 PL6 check includes rest 6 s + first scroll; SPK-s prices the load cost |
| **Emergent dynamics** | Back-pressure, catch-up frames, coalesced layouts: a stepped harness removes them [04 §12] | The device outer loop must still see them |
| **Heat and Low Power Mode** | Coefficients drift; LPM halves rAF to 30 Hz (CONFIRMED [04 §2.3]) | Thermal class per run; θ factor; LPM recorded and refused for calibration |
| **Blink cannot see WebKit-only costs** | presence-flip layouts, `steps()`/`linear()` off the CA path, store discard on resize [01 §A.3] | A separate WebKit count vector and coefficients; never predict iPhone feel from Blink counts |
| **Version skew** | Phone iOS 27.0.1; Simulator iOS 27.0 (24A434) and 26.5; CI `macos-26` has iOS 26.5; WKTR is WebKit trunk 324039@main (CONFIRMED [ENV], §4.2) | Every count and coefficient stored with (engine, family, platform, OS build); V-b checks Simulator vs phone per count type |
| **Experimental interfaces** | `HeadlessExperimental`, BeginFrameControl (Linux only), the Playwright webview backend [03 §12, 04 §4.3] | Pin versions and the container image digest; keep a thin raw Inspector client |

**Primary device metric:** frames > 50 ms per 100 moving frames in the finger's zone, from the swiped run (7 of 7 in
v1). Also reported: slow-frame % (> 34 ms) and the longest frame per zone, binned by **vsync ticks** (proved tick
math, `Fw.Frames.tickAt hz dtNs`, parameterised by refresh rate since 9367dea, so 60 Hz on the iPhone) and placed by **crossing coordinates**
(the nearest code threshold, not raw y).

## 5. Lean strategy

### 5.1 What is proved

**Lean-first (your requirement of 2026-10-17).** [10.03] places 87 console and tooling decisions, state machines and
pure functions at a proof level (site and part items are not counted yet, INFERRED). `lean/README.md` holds the
inventory; the math view (§5.3) shows each item's math.

| Level | Count | Meaning |
|---|---|---|
| **L1** | 54 | Implemented and proved in Lean, run through `fwcore`; inputs are the console's own events, ids and counts |
| **L1-cond** | 30 | Proved in Lean, but its real-world meaning needs a named L3 premise (for example: the counts are right, every spawn passes the hook, the declared dependencies are complete, the signer's identity) |
| **L2** | 3 in [10.03]; more to re-estimate | Lean spec; the shipped TS/React/CSS is generated by Lean or passes Lean golden vectors (§3.3): flag resolver, JSON wire codecs, console-web's optimistic preview, media strings, motion curves, part logic |
| **L3** | 18 categories | Not provable; each names how it is checked and which L1 decision it feeds (below) |

Lean reaches the code in one of the three ways of §3.3: it runs in `fwcore`, it generates the artifact, or it emits
golden vectors. Site and measurement items are in scope too: the breakpoint model `Fw/Site/Breakpoints` (conditions,
edges, overlaps, the fractional-gap and pure-860-vs-C860 facts; it generates `breakpoints.gen.json`, the media
strings the parts import and the 124-load gate matrix), motion curves, and count reduction and verdicts (in `fwcore`).

**Modules by milestone** (P = proved in a kickoff sketch: `05-lean-sketch`, or `10-automation-and-proof/lean-scratch`):

| Milestone | Lean modules | v1 bug classes they remove |
|---|---|---|
| M0 | `Fw/Console` (reducer, authority, steps, needs-you, landing rule); `Fw/Spec/DeviceQueue`; `Fw/Ops` (spawn-guard, path check, usage, identity); `Fw/Wire`; `Fw/Spec/{Frames, Verdict, Null}`; `Fw/Gate`; `Fw/Plan`; the math-view lint | hand-kept board, double-answered steps, scheduler, spawn storms (I-044, I-059, I-011 and others) |
| M1 | `Fw/Site`; `Fw/Spec/{ArtifactKey, Store}`; rows, threads, proposals, notices, digests; run queue, sessions, preflight, lease (Q26), user step; stage lifecycle, land queue; determinism classes | stale reuse, cherry-picking, lease mid-step (I-122, I-123), a lost queue place (I-113) |
| M2 | `Fw/Parts` (pilot-part specs and their golden vectors; workstream lean-parts); `Fw/Spec/Flags` + `Fw/Gen/Registry` (P), presets; parity bands and part lifecycle; `Cost`/`screen`, alignment, uncounted families, landing classifier, `land_requires` (full) | arms that changed more than the named thing; over-trusting proxies |
| M3 | model ladder, fit-certificate checker, WebKit model monotonicity, licence, spot-check schedule, validation metrics, block validity | a model used beyond its evidence |
| M4 | sequential ABBA, Hodges–Lehmann (in `FwMath` if it needs Mathlib, §5.2), union bound; **per-module evidence review** | — |

**Built by d41aef0** (the dependency graph ran ahead of the milestone order):
- `Fw/{Board, Console, Serve, Wire}`; `Fw/Spec` (10 modules); `Fw/Site` (4); `Fw/Parts` (5); `Fw/Sched` (100
  theorems, 4bd850f; in `fwcore` as `ops.admit`, `metrics.*`, 49b7ff4).
- `Fw/Measure`: classes, tolerances, zones, WebKit reduction (ddc91b2); `measure.selfCheck` and `snapshotCounts`
  (baa3291); the pixel-area bound with `classifyU_*` proofs (5879861).
- `Fw/Gate/{Rule, Compare, Items, State}`: the breakpoint-gate verdict, 51 theorems; `verdict.mjs` now calls
  `fwcore` (0d02aff).
- `Fw/Plan/{Core, Graph, Trailer}`: the work graph (derived state, acyclicity, critical path, parallel-safe groups;
  0de2fec) and `Task:` trailers (acc5d83).
- `Fw/Obs/Health`: 5 agent states and 14 alert codes behind `fw watch` (0877f7a); `Fw/Ops/{Identity, Obs}` (dec2d82,
  acc5d83).
- **Mutants (V-r) for M0:** 625 mutants, 621 killed, 1 stillborn, 3 equivalent, 0 survived (MEASURED 8074907); the
  killers run in `lake test` (c67cbe4). Later runs move to CI (`mutants-ci`).

Not built yet: the `unreachable` gate cell (`gate-unreachable`, §6.6), `ops.gate`, the lease, the artifact store
(`store-and-run`) and the M3 model modules.

**Evidence, not a go/no-go.** Each L1 module ships with mutants (V-r) and is counted in the per-module bug ledger
(V-l). **Demotion rule:** a module moves from L1 to L2 by a decision record when its proofs cost more than 1
agent-day on each of two consecutive changes while the ledger shows 0 bugs caught by its proofs or mutants, or when
it blocks a console feature for more than 1 working day. The Lean spec then stays as the oracle for a TS
implementation. At M4 the lead reviews the per-module table; Lean as a whole is not on trial.

**Still dropped:** engine decision rules as Lean data and part geometry claims (a proof about our
transcription of an engine rule cannot catch a transcription error); engine rules get **table tests** instead.

**Not proved (L3), each with its check:** engine behaviour (table tests); work counts (V-a, V-b, V-i, V-n);
coefficient fitting (calibration, holdouts, the certificate checker); run independence (A/A, ABBA); sha256
collisions (an assumption); pixels (tiers vs A/A); the React parts (PL0-PL6); IO (contract suites, nightly `fwcore
replay`); YAML and CSS parsing (golden files); human and LLM judgement (blind protocol, typed commands); the UI
(Playwright); `fwcore` speed (a budget test); the clock (console-api stamps time); **completeness of observation**
(reconcilers); **actor identity** (the capability hook, SPK-t); **completeness of declared dependencies** (SPK-u);
**"answered / complete"** (your click or a typed close).

**Multiplicity.** Each experiment records how many comparisons it made (k). A landing needs `k · p_null ≤ 0.05`.
Under the null, Pr[better] ≤ 1/C(8,4) = 1/70 for 4v4 and ≤ 1/C(10,5) = 1/252 for 5v5, with equality iff ties have
probability 0 (premise: runs exchangeable; L1-cond). Proved: `land_null_prob` enumerates the 70 orderings (9367dea) and
`falseBetterProb_eq_pNull` covers any m, n (74ffd03), so 5v5 gives 1/252. 4v4 allows k ≤ 3 (`multOk`, proved);
above that use 5v5 or v1's sequential rule.

### 5.2 How TypeScript and Lean connect

- **Lean decides and holds the console state; TypeScript moves data** (architecture (B) of [10.03 §4]). `lean/`
  builds the native executable `fwcore`; `fwcore serve` is one long-lived, single-threaded process (JSON-lines,
  hardened as in §3.2). console-api stamps each event with an id and the time, appends and fsyncs it, sends it to
  `fwcore`, and publishes the changed rows over SSE; a refused event is logged with its reason. Nightly,
  `fwcore replay events.jsonl` must reproduce the live state hash.
- **One reducer, one data layout.** `Fw/Console` merges [10.02]'s semantics (actors, cards, authority, landing with
  violations, review independence, seen-on-accept) with [10.03]'s data structures (`Std.HashMap`/`HashSet`,
  `modifyGet`); the 100k-event speed test runs in `lake test` (budget < 1 s).
- **Mathlib-free core, optional `FwMath` (decided 2026-10-17).** Core Lean (`omega`, `decide`, `simp`, `grind`,
  `Rat`, `Lean.Json`) covered every kickoff sketch. A proof that needs Mathlib (Hodges–Lehmann, exact p-values beyond
  enumeration) goes in a separate `FwMath` package that `Fw` never imports, so Mathlib's several-GB cache stays
  optional [05 §0]; it follows the same math and sign-off rules.
- Types: zod is the source of truth (`packages/contracts`). Lean types derive `ToJson`/`FromJson`. `fwcore samples`
  emits golden JSON that zod must parse byte-for-byte, so the Lean JSON shape cannot drift [05 §2, 06 §2.5].
- TS copies: only L2 items (§3.3), each generated by Lean or held to Lean golden vectors in TL2.

### 5.3 How you read a theorem, and a worked example

**You read math, not Lean (decided 2026-10-17).** Every theorem, and every definition you are expected to read (for
example `may`, `stage`, `ready`, `stale`, `eff`), carries its math in its docstring: one English sentence, then one
`$$…$$` LaTeX block, using one notation table ([10.04 §3]). Lean checks the proof; the **math-reviewer** role checks
that the math says exactly what the Lean says; you check that it is what we mean. `#guard` lines are examples that
run at build time.

**The math view is generated, never hand-kept** ([10.04 §2]):

- **Export.** `lake exe mathview` exports per declaration: name, file:line, the docstring's English and math, the
  signature, a machine-made LaTeX form of the statement (no LLM), axioms (`sorryAx` = not proved) and a 64-bit
  **deep statement hash** (the statement plus every `Fw` definition it reaches).
- **Page.** `docs/plan/tools/build-math-view.mjs` renders it into `docs/plan/loop-plan.html` with KaTeX as MathML (no
  script or font files). Per entry: math, English, chips (proved / sorry; signed / unsigned / stale), the Lean collapsed.
- **Sign-off.** Today: review records `research/notes/*/*-math-review-*.md` keyed by statement and math hash; the
  page marks agree, disagree, stale or pending. Planned: an event, `pnpm fw math:sign <decl>`, that only the
  math-reviewer and you may cause, exported to `lean/math.lock.json` (edits denied), so an editor cannot re-sign.
- **Lint** (`lake exe mathview --lint`, TL0) fails on missing math, `sorry` outside an allowlist, a hash or math
  changed since signing, a KaTeX error, or an axiom other than `propext`, `Classical.choice`, `Quot.sound`.
- **Review.** The math-reviewer sees the signature, the machine-made math and the definitions, not the docstring,
  writes its own math and compares clause by clause (ℕ vs ℤ, ≤ vs <, truncated subtraction, empty lists, ties,
  ⇔ vs ⇒). Disagreement goes to a second reviewer, then you (Q28). Before review, lean-prover runs a 6-item checker
  pass on its own docstrings (Fable review, 98526a5).
- **Toolchain bump.** `mathview accept --toolchain-bump` re-signs only entries whose signature and machine-made
  LaTeX are unchanged (R24).

**Review rounds so far (MEASURED).** No round found a wrong proof; every disagreement was a docstring fix.

| Round | Commit | Declarations | Agree | Disagree, and the fix |
|---|---|---|---|---|
| r4 | 226c35b | 258 | 187 | 71 (00c09bf, which added a free-variable lint) |
| r5 | 28b18ee | 490 | 428 | 62 (69d7773) |
| r6 | e6908db | 62 re-reviewed | 61 | 1, `Admit.Inv` (77b381c) |
| r7a | ff55f4e | 234 | 214 | 20 (acc5d83, 5879861) |

The rest of round 7 (`Fw.Obs`, `Fw.Gate`, `Fw.Console` rows after their fixes) is task `math-r7`, an M0 exit item.

**Worked example** (committed: `lean/Fw/Spec/Verdict.lean` and `lean/Fw/Spec/Null.lean`, 9367dea; proofs elided):

```lean
/-- Soundness for lower-is-better: "better" means every variant run was strictly lower than every control run.
$$\forall C, V \in \mathbb{Z}^{*}:\quad \operatorname{verdict}(\mathrm{lower}, C, V) = \mathrm{better} \;\Rightarrow\; \forall y \in V,\ \forall x \in C:\ y < x$$ -/
theorem better_sound {ctl var : List Int} (h : verdict .lower ctl var = .better) :
    ∀ y ∈ var, ∀ x ∈ ctl, y < x := …

/-- 4 control vs 4 variant runs: if the 8 values are distinct and every labeling is equally likely (the L3
premise), a false "better" has probability exactly 1/70 (all 70 rank assignments enumerated through `verdict`).
$$\operatorname{falseBetterProb}(4, 4) = 1/70 = \operatorname{pNull}(4, 4)$$ -/
theorem land_null_prob : falseBetterProb 4 4 = 1 / 70 ∧ pNull 4 4 = 1 / 70 := by decide +kernel

#guard verdict .lower [5, 5, 5] [4, 4, 4] == .better
#guard verdict .lower [10, 11, 12] [9, 10, 8] == .noise
```

The JSON-lines op it backs (one line each way, the id echoed):
`{"id":"r-17","op":"verdict","dir":"lower","ctl":[21,19,23,20],"var":[4,3,5,2]}` →
`{"id":"r-17","verdict":"better","pNull":{"num":"1","den":"70"}}`

### 5.4 Test strategy per layer

| Layer | What | Tool | Runs when | Budget |
|---|---|---|---|---|
| TL0 | proofs, `#guard` examples, the math-view lint (missing / stale / unsigned math, sorry, axioms, KaTeX), mutant patches (each must break the build, V-r), the 100k-event speed budget, partial-op grep on `Wire`/`Main` | `lake build`, `lake test`, `lake exe mathview --lint`, grep for `sorry`, `native_decide`, `implemented_by`, `unsafe`, `!`-ops | `lean/` affected | 0.5 s per changed module (MEASURED) |
| TL1 | pure unit + property tests; no real time, host load, ports, process lists or shared temp folders (lint; 2 s per-test cap); engine rule table tests | Vitest + fast-check | pre-commit, affected packages | < 20 s whole repo |
| TL2 | contracts: zod ⇄ JSON Schema ⇄ Lean golden round trips (the `Rat` wire form, every event `type@n` with upcasters); recorded hook payloads through the Lean decoders; the resolver over its whole domain (+ 2,000 fast-check cases) | Vitest + `fwcore` | pre-commit, affected | < 30 s |
| TL3 | visual parity per part (PL0-PL4) | Playwright (Chromium + WebKit) | pre-land, affected parts | < 10 s per part per config |
| TL4 | measurement plugins on real engines, incl. harness-neutrality fixtures (V-n) | `fw run` (cached by artifact key) | on demand; pre-land for touched parts | 0 on a cache hit |
| TL5 | device + your finger | console steps | milestone gates and scheduled blocks | scheduled |

**Console fault injection (TL4, on demand and nightly):** golden event logs replayed with duplicates, drops followed
by a reconcile pass, reorders within a subject, a torn last line and skewed producer clocks must give the fault-free
state; v1's status history replayed through the v2 reducer measures V-t [10.02 §6.5].

**The local gate:** a pre-commit hook (built: `scripts/scrub.mjs` through `core.hooksPath`, which blocks emails, home
paths, LAN IPs, device ids and secrets in staged files, 0.17 s, d2574b0) + `pnpm fw gate` (re-runs the checks at
land, so a commit made with hooks skipped still cannot land).

**CI** (d70619d, 6723de2): four workflows on `main` (`lean`, `chromium-counts`, `breakpoint-gate` in 8 shards,
`webkit-sim`) plus `wktr` on its branch. Read-only contents, actions pinned by SHA, inputs through env. Since rev 7
CI is where measurement runs (§4.1); timing and device lanes stay local, because shared runners give no stable time.
CI never replaces `fw land`. State: `breakpoint-gate` passes in about 5 min; `chromium-counts` passes (classes in
§4.2); `lean` fixed by `restoreAllArtifacts = true` (67192ef); `webkit-sim` takes 10-38 min and fails at warm-up
(task `sim-speed`); mutation runs move to CI, since the M0 pass (625 Lean builds) drove this Mac's load average to ~500 (task `mutants-ci`).

## 6. Pluggable parts and flags

### 6.1 Parts

The parts follow the page anatomy in [02 §2]: `nav`, `nav.hitTest`, `nav.langMenu`; `hero.{orbit, deck, exit,
accent, countdown, cue}`; `people.{card, o, deck, carousel}`; `pain`, `pain.notes`; `commission`,
`commission.typing`; `platform.{sweep, glint, entries, stageBg, marquee}`; `morph.{mount, tween, panel, countdown,
columns}`; `overlays.{signup, drawer}`; the cross-cutting parts `engine.scroll`, `engine.scene` and `images`; and,
added from the breakpoint inventory [11], the section shells `hero` and `platform`, the shared buttons `ui.shared`
(`sb-*`) and the root `theme.tokens` (with the 320 px floor) (about 36 in all).

**Every part with markup is built from Material UI components** (decided 2026-10-17: `Box`, `Stack`, `Typography`,
`Button`, `Link`, `AppBar`, `Card`, `Avatar`, `Dialog`, `Drawer`, `Menu`, `Tab` …). Looks come from CSS Modules that
restate the original's values; motion comes from our drivers (§6.5). MUI's wrapper elements (Paper, Backdrop, Portal
roots) are listed in each part's `parity.json` wrapper map, which PL0/PL1 and N3 use.

**Experiment parts** (the M5 backlog): `morph.*`, `people.*` (reveal and deck), avatars, `engine.scroll` and
`nav.hitTest` (scroll-engine reads), `hero.countdown`. Only these need full work parity (PL5-PL6). All other parts
need look parity only (PL0-PL3).

Dead CSS (about half of the Platform section's animation CSS never runs [02 §2.6]) is not ported as live rules.
Whether `faithful` adds it back as an **inert stylesheet** with the same rule count is **open (Q35)**. The
recommendation is no: MUI's static CSS already puts the rewrite above the original's rule count, so N4's difference
becomes a K-fixture parameter instead (`10-17-css-decisions.md`).

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
| `faithful` | same DOM shape, the original's CSS values restated; for experiment parts also the **same per-frame reads and writes**, bad ones included (rect reads in rAF, the `elementFromPoint` hit test, the scroll-jack) | look parity PL0-PL3; PL4-PL6 for experiment parts; time box 1 agent-day (2 for `engine.*`, `morph.*`), then **`faithful-with-delta`** with the difference recorded; no compositor gate |
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
pnpm fw run --preset original --fw hero.countdown:strip --engines chromium,webkit --profile swipe-v1  # one part swapped
pnpm fw run --preset original --impl hero.countdown:plain --engines chromium,webkit     # N3: MUI vs plain twin
pnpm fw run --preset original --fw nav.hitTest:hit-skip --lane timing --abba 4          # timing lane, ABBA n=4
pnpm fw run --preset original --fw hero.countdown:strip --engines chromium --dry        # config, hash, cache hits
```

Output: raw artifacts go to the local store `<git-common-dir>/fw/artifacts/<key>/`; the run summary goes to
`results/runs/<date>-<configHash7>.json` (committed) with a line in `results/index/runs.jsonl`. `fw report <run>`
prints per-zone counts, the screen result (dominates / mixed / worse) and the model prediction with its status.

The console's Run builder does the same with ticks and pickers, and shows `fw run --dry` before queueing.

### 6.5 Runtime rules inside parts

1. **No per-frame value goes through React state, context, MUI `sx` or Emotion.** Drivers write refs, inline styles
   or CSS variables on the consuming element, or use WAAPI or scroll timelines.
2. All JS motion goes through the injectable `MotionClock` and the scroll source; no free-running rAF or timers.
3. `engine/Signals` gives each scroll threshold **one owner** (the faithful engine keeps the triple flip at 0.72).
4. The faithful `engine.scroll` is literal: one passive listener, one rAF, the original's callback and layout order.
5. The site is prerendered, as the original is. Only production builds are measured.
6. **Styling: MUI everywhere, Emotion AOT** (decided 2026-10-17; [09] README §1 has every source line). Material UI
   9.5.0 and Emotion 11.14.x, pinned exactly. A build-only **census route** renders every MUI component in every
   state the parts declare (`muiStates`); `extractCriticalToChunks` (`@emotion/server` 11.11.0) writes those styles
   to a static, linked `mui.[hash].css` in `@layer mui`, plus `emotion-ids.json`. The prerendered HTML has no `<style
   data-emotion>` tags. Before `hydrateRoot`, the client marks every census id in `cache.inserted`, so Emotion inserts
   nothing (mechanism CONFIRMED in Emotion's source; pipeline MEASURED in Chromium by SPK-r, WebKit pending). Measurement builds wrap
   `cache.insert`, and one miss fails the build. The static CSS declares `@layer reset, mui, parts, flags;` first.
   **Cache wiring** (CONFIRMED in source, rev 4 review): no `StyledEngineProvider` (in MUI 9.5.0 its own client-only
   cache would bypass the pre-marked one); one `createCache({ key: 'mui' })` per side through `CacheProvider`, the
   server one through `createEmotionServer`; the client cache copies MUI's insert wrapper so a miss lands in the layer. **Portals:** MUI `Portal` renders
   nothing on the server, so the census renders every overlay with `disablePortal`, closed (`keepMounted`) and open.
   **Build variants:** `style-engine: aot` (default); `runtime` (plain Emotion SSR, the negative control N0/N5 must
   catch); `pigment` (Pigment 0.0.30 with MUI 9.0.1 in its own workspace package; optional, SPK-s). **Fallbacks:** per
   part, Base UI 1.9.0 + CSS Modules when its census cannot be completed, an N0/N1/N5 incident cannot be fixed in its
   time box, or its N3 delta comes from styling (§6.7); whole site, `pigment` if SPK-r fails at the mechanism level.
   The rules below extend rules 1-5 (lint = an ESLint or ast-grep rule in `apps/site`; N = the gate in §6.7).

   | # | Rule | Prevents | Enforced by |
   |---|---|---|---|
   | S1 | No `sx`, no `styled()`, no Emotion `css`/`keyframes` under `src/parts/**`; style MUI through `className` and `slotProps.*.className` from CSS Modules in `@layer parts` | runtime insertion; class churn | lint; N0 |
   | S2 | Theme `styleOverrides`/`variants` branch only on props whose values are listed in `part.json` `muiStates` | a census miss = an insertion mid-run | census test; N5 |
   | S3 | Per-frame values only through `MotionClock` writers: a custom property on the *consuming* element, inline `transform`/`opacity`, WAAPI or scroll timelines; never React state, props, context or className | React commits, churn | rules 1-2; N2 |
   | S4 | Discrete flips (tab change, menu open, avatar swap) may re-render but must map to classes already in the static CSS | an insertion at a flip | N0 in W-trigger; N2 |
   | S5 | No MUI `Fade`/`Grow`/`Slide`/`Collapse`/`Zoom` on scroll-linked or always-mounted paths; overlays replace `slots.transition` with class-toggled keyframes restated from the original | forced reflow (`node.scrollTop`), rect reads, inline writes from JS | lint; PL4 in the overlay's own scenario |
   | S6 | Ripples off theme-wide (`disableRipple`, `disableTouchRipple` on `MuiButtonBase`); focus styles restated in CSS | a re-render, rect read and `@keyframes` insertion at the first touch of a swipe | theme unit test; N0 in the finger-replay profile |
   | S7 | On scroll paths: no MUI `Tabs` (use `ButtonBase` with `role="tab"` in a plain `tablist`), no `Popper`/`Tooltip`/`Autocomplete`; `Avatar` gets its `<img>` as a child, never `src` (details below) | rect reads; resize-driven forced layouts; hidden commits and image loads | lint; PL5 forced layouts (exact); N2 commit count |
   | S8 | One theme at module scope, one colour scheme, nothing written on `<html>` at hydration; `cssVariables` is **open** (Q34: today `true` with `disableStyleSheetGeneration`; recommended `false`) | `<Global>` insertion, root invalidation, consumer re-renders | N0/N1 in W-load/W-rest; N4; N5 |
   | S9 | No Emotion `<Global>` at runtime (`CssBaseline`, `GlobalStyles`, `enableColorScheme`); the reset is static CSS in `@layer reset` | `<Global>` bypasses `cache.inserted` and moves or flushes tags | lint; N0 |
   | S10 | No `useMediaQuery` or `useScrollTrigger` for looks; breakpoints live in CSS | commits on scroll and on toolbar resizes (775↔815) | lint with an allow-list |
   | S11 | Emotion configuration is fixed: production `speedy`, one cache with key `mui` (cache wiring above), MUI rules in `@layer mui` unless K10 says otherwise, no `injectFirst`/`prepend`; config and MUI version in the build ID; every MUI bump re-runs N0-N5 | an unpriced change to the styling engine | build-ID hash; K10 |
   | S12 | Overlays (`Dialog`, `Drawer`, `Menu`) closed during scroll scenarios, mounted at load or `keepMounted`; `disableScrollLock` matches the original; FocusTrap's 50 ms timer allowed while a modal is open; MUI's default `@media` replaced by `breakpoints.gen.json` conditions | insertion and body writes at the trigger; an unmeasured timer | N0 in W-trigger; PL5 in the modal scenario |
   | S13 | The theme uses the original's font families and metrics (no Roboto default) | layout and paint differences that look like styling cost | PL1/PL3; N4 lists `@font-face` |

   **S7 details.** Hiding the indicator does not stop MUI `Tabs` from measuring: it reads `getBoundingClientRect`
   after every render and on every `resize` and tab `ResizeObserver` callback (`Tabs/Tabs.js` l.338-381, l.561-611,
   l.644-646 @9.5.0), so an iOS toolbar step triggers it mid-swipe. A `Tab` outside `Tabs` throws in 9.5.0
   (MEASURED), so `Tabs`/`Tab` stay in the census only. With `src`, `Avatar`'s `useLoaded` creates an off-DOM image
   and commits twice per mount (`Avatar/Avatar.js` l.115-145 @9.5.0), which N0-N3 cannot see. **S12:** `Dialog`
   `maxWidth` and `Container` emit MUI's `xs…xl` `@media` (1 rule in `mui.css`, MEASURED).

   **Census ids:** the client marks **every** id the server inserted (`styled(Wrapper)` rules never reach the HTML;
   marking only HTML ids left 8 inserts on first overlay open, MEASURED). **Build gates** (every build): census test with 0 misses; no `@media` in `mui.css` that is not in
   `breakpoints.gen.json`; no `<style data-emotion>` in prerendered HTML; no
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
| PL5 | work counts per scenario (rest 6 s, scripted scroll, the part's trigger), per family; N0/N1 sheet mutations, N2 DOM writes; N3 against the `impl: plain` twin | bands listed below the table | experiment parts (N0 on all parts) |
| PL6 | timing parity: Mac Chrome timing lane, per stage, R within A's A/A band (ABBA, n ≥ 4); at M4 one Simulator and one phone whole-page check with N5 | within band; N5 green | experiment parts; whole page at M4 |

**PL5 bands** (proposals, re-set once from the M2 pilot, then frozen by `bands-freeze`; INFERRED): rAF callbacks and
forced layouts **exact**; style and layout passes and elements `|R−A| ≤ max(2, 5 %)`; paint/raster `|R−A| ≤ max(2,
10 %)`; layers ±0; compositor/main split exact; sheet mutations 0; N2 equal to the plain twin. Only deterministic
and stable count types take part, stable ones as totals with margin 2t (V-i).

**Transfer check (V-p), at every landing.** If the change can be an overlay on the original, the runner applies it to
arm A in the counts lane and requires the **same sign of Δ per stage** as on the rewrite; otherwise it is "transfer
unchecked" and cannot land as class W.

**Every breakpoint, identically, for every part (your requirement of 2026-10-17).** The inventory [11] found 30
distinct media conditions (29 in CSS, plus `(hover: none)` in JS only), 92 CSS `@media` blocks, 29 JS `matchMedia`
sites and 20 non-media gates, giving **18 edges** (CONFIRMED [11 §1]). `breakpoints.json` is generated from the
snapshot by an extractor (L3, golden files) and never edited by hand. The Lean breakpoint model (§5.1) generates
`breakpoints.gen.json`, the media strings and the gate matrix; the build fails unless it equals the extracted file.

| Edges (N → N+1) | Gated by |
|---|---|
| 319→320 (the root `min-width` floor), 400, 461, 480, 640, 720, 960, 1030, 1100, 1200, 1511 | CSS only |
| 600, 860, 1000, 1279 | CSS and JS |
| device-width 500; the touch arm `(hover: none) and (pointer: coarse) and (width <= 1200px)` | the OR-combos C860, C1000, C1030 (C1000-nodw, the countdown's, has no device-width arm) |
| pain-notes container width < 1100 | JS (the viewport width where it flips is still to be MEASURED) |

- **Pure 860 is not C860 (parity rule).** A touch tablet at 861-1200 or a phone in landscape (device-width ≤ 500)
  takes the desktop path for people.o, the pain layout, pain-dark and hidden notes, and the compact path for the deck,
  note drag and shrinks. The rewrite keeps the two conditions apart, and the gate tests both paths at 1024 (touch)
  and 932×430 (v1's README said tablets take the phone path; they take both [11 §5]).
- **Overlaps** (there C860 and `>=861` both match, as do C1000 and `>=1001`) keep the original's source order and
  specificity winner (visible outcome still to be MEASURED). **Fractional gaps** (600.5, 640.5, 860.5, 1000.5 match
  neither side) need exactly restated bounds. **JS gates** run the identical query with the same update style.

**Breakpoint lint** (in `fw gate --part`; the set check is an L1 decision in `fwcore`): per part and kind (CSS, JS),
the normalised conditions must **equal** the inventory's set (an extra, missing or shifted condition fails;
`useMediaQuery` for looks fails, S10), and per condition the rewrite must cover the original's property names.
**Breakpoint gate**, required before **any** part is promoted (`faithful-with-delta` never waives it): PL0-PL3,
original vs rewrite with a per-config A/A, in Chromium and Playwright WebKit, **124 loads per engine** (INFERRED
arithmetic [11 §4]): the 15 width pairs as desktop, desktop reduced-motion and touch (90), touch reduced (10), phone
landscape (2), the device-width arm alone (6), the hover × pointer cross (4), dark (2), the fractional gaps (4) and
height probes (6); plus one width inside each continuous band (clamp knees), and **live-resize sweeps** compared with
the original after the same sequence (1512 → 320 → 1512 across every edge, 430×932 ↔ 932×430, touch 1024 ↔ 1201,
v1's 1440 → 600 → 1440 pain sequence, live reduced-motion and touch flips). **Per PR**, the core matrix (430×932 and
430×775/815 at DPR 3 with touch; 375×667 and 1440×900 at DPR 2; reduced motion) is the fast subset; one Simulator
check closes promotion, because Playwright WebKit has no toolbar and no Conservative compositing policy [02 §7].

**Gate status at d41aef0 (MEASURED, e7fb102, d23cf7c, 0d02aff).** 124 loads × 2 engines (headless Chromium,
Playwright WebKit) × 2 arms plus 4 sweeps, byte-identical across two runs.

| Item | Result |
|---|---|
| Pilot parts | all 4 pass all 14 cells in both engines (after fixes 95693f4, 2566949) |
| Covered | PL0, PL1, PL2 and the `matchMedia` truth |
| Not covered yet | PL2b, PL3 pixels, the Simulator check, live reduced-motion and touch flips |
| Verdict | in Lean: `Fw.Gate.{Rule, Compare, Items, State}`, 51 theorems; `verdict.mjs` calls `fwcore` (0d02aff) |
| Speed | a full run takes 554 s; `--parts` saves no time until each part declares its probe scope (`gate-probe-scope`); CI runs 8 shards in about 5 min |

**The cells no engine could reach (Q33, answered: "Simulator or device check for both").** Two research notes
(`10-17-gate-gaps-fractional.md`, `10-17-gate-gaps-hover-pointer.md`) split the answer by engine:

| Cells | Chromium | WebKit (Simulator and iPhone) |
|---|---|---|
| Fractional gaps (600.5, 640.5, 860.5, 1000.5) | reachable: browser zoom 200 % with override width 2N+1 gives media width N + ½ (MEASURED) | **unreachable**: the media width is an integer by type (CONFIRMED in source, MEASURED) |
| Hover × pointer cross (4 cells) | reachable through `--blink-settings`; passes | **unreachable**: every Apple WebKit derives primary hover and pointer from one constant (`WebPageIOS.mm` l.4233-4246, `WebPageMac.mm` l.762-780, CONFIRMED) |

So the gate gets a new cell state, **`unreachable`** (the engine cannot produce this environment; distinct from
not-comparable). Order, Lean first: `gate-unreachable` (a proved realizability rule in `Fw/Site`/`Fw/Gate`; the Lean
fractional probe moves from DPR 5/4, which no browser produces, to DPR 2) → `gap-harness` (the Simulator check
against Lean's expected values; its review found it used the retired TS verdict and a wrong touch-arm check) →
`gap-device` (a 2-load probe page in one booked phone session, confirming the iOS 27.0.1 build matches the source).

### 6.7 Styling-neutrality gate (N0-N5)

This gate shows that MUI adds no style-sheet mutations, DOM writes, React commits or engine work counts compared with
arm A and with the part's `impl: plain` twin. If it passes, PL5 compares mechanisms, not styling engines [09.03 §2].
It cannot see JS time (Emotion still serialises and hashes on every styled render) or the per-element cost of a
differently shaped style sheet; those are left to N4 as a proxy and to PL6 timing parity (§12.3).

Windows: **W-load** = navigation → `__fw.hydrated`; **W-rest** = `__fw.hydrated` → `markMeasureStart()` (incl. the
6 s rest); **W-measure** = the scenario; **W-trigger** = an interaction scenario's own window.

| Check | What and how | Gate |
|---|---|---|
| **N0** sheet mutations, page side (every counts run, both engines, both arms) | an init script, run before any page script, wraps the CSSOM write APIs and watches `<style>`/`<link>` changes (details below); a sheet-shape hash at every window edge | W-rest, W-measure, W-trigger: **0**. W-load: equal to arm A's (0) or a class X delta |
| **N1** sheet mutations, engine side | Chromium: `blink,blink_style` slices `StyleEngine::updateActiveStyleSheets`, `scheduleInvalidationsForRuleSets`, `InvalidateStyleAndLayoutForFontUpdates`. WebKit: `CSS.styleSheet*` events over iwdp, attribution runs only | W-rest and W-measure: **0**. Non-zero on arm A is a harness finding |
| **N2** DOM-write and commit census | per frame and per `data-fw` anchor: `class`/`style` changes, childList mutations, React commits per part (a `<Profiler>` counter); commits catch MUI work that writes no DOM | `impl: mui` = `impl: plain`, **exact per frame**; equal to arm A where `parity.json` maps the write |
| **N3** work counts, MUI vs plain | the PL5 families on the `impl` pair, same flags otherwise | passes, forced layouts and layers **exact**; `elementCount`/`dirtyObjects` within `max(2, w)`, where w = MUI wrappers in the invalidated subtree (wrapper map); paint/raster: the PL5 band. Until WKTR exists, a style-affecting diff cannot pass N3 on WebKit by counts alone (Q10) |
| **N4** static style shape (once per build, A and R) | at the end of W-rest, walk `document.styleSheets`. Count style rules, selectors by their rightmost compound, `:root` custom properties, `@property`, `@layer`, `@keyframes`, `@font-face`, and `@media` rules (how many match) | rule count and `:root` custom-property count within ±10 % of arm A, or the difference becomes a K-fixture parameter and is flagged for PL6 |
| **N5** hydration | the SSR `class`/`style` per anchor vs the DOM after `__fw.hydrated`; `cache.insert` misses | **0** attribute diffs, 0 misses, 0 style-tag moves |

**N0 details.** The init script is `Page.addScriptToEvaluateOnNewDocument` in Chromium, `Page.setBootstrapScript` in
WebKit over iwdp, or the first `<head>` script for both arms. It wraps `insertRule`/`deleteRule`/`replace*`, grouping
and keyframes rules, the `selectorText` setter, `adoptedStyleSheets`, `StyleSheet.disabled`, `MediaList` mutators and
rule-level `setProperty`/`cssText` (only when `parentRule != null`, so MotionClock's inline writes stay allowed). One
`MutationObserver` sees `<style>`/`<link>` adds, removes, moves and text edits.

A failed N0, N1 or N5 is an **incident against the part, never a result**; it is fixed inside the part's time box, or
the part moves to the Base UI fallback. A failed N2 or N3 makes the part `faithful-with-delta`, with the delta in the
validity table, or moves it to the Base UI fallback if the delta comes from MUI. N0 runs in the counts lane; in the
timing lane and on the phone only the end-of-run hash runs.

## 7. Repo layout and the knowledge store

### 7.1 Tree (MVP; "later" items are added only when needed, §3.4)

```
fastwork-com-web-optimize-lean/
├─ CLAUDE.md                  < 300 words at the start (≤ 1,500 ever): rules with "Enforced by", trust boundary, lanes
├─ LICENSE  NOTICE  README.md MIT for our code; NOTICE and README carry the Fastwork approval and snapshot source
├─ .github/workflows/         lean, chromium-counts, breakpoint-gate, webkit-sim; wktr on its branch (CI, §4.1, §5.4)
├─ .claude/                   settings.json (hooks, permissions, env), agents/*.md (14 roles, §8.2), skills/
├─ .mcp.json                  serena (TypeScript), serena-lean (from lean/), lean-lsp (search tools off); §8.1
├─ .serena/ pnpm-workspace.yaml package.json biome.json snapshot.lock.json (id + hash, no content)
├─ scripts/                   scrub.mjs (pre-commit), hooks/, wt-prep.sh (worktree setup), refs-fetch.mjs, sim-lock.sh
├─ breakpoints.json           GENERATED from the snapshot's CSS and JS: every breakpoint edge, per part (§6.6)
├─ apps/
│  ├─ site/                   React 19 + Material UI 9.5 + Vite 8, prerendered; /__harness/:part; /__census (build only)
│  │  └─ src/{engine/, registry/, theme/, mui-aot/, parts/<id>/{part.json, parity.json, faithful/, variants/<v>/}}
│  ├─ console-web/            shadcn/ui + Tailwind 4: run builder, steps, results (later: validity, proposals, usage)
│  ├─ console-api/            Node 24 + Hono; single writer; CLI socket; reconcilers, watchers; fwcore serve (§7.3)
│  └─ runner/                 `fw`: run | gate | land | screen | report | usage | snapshot | sim; hooks/ (emit, cap, spawn-guard)
├─ packages/
│  ├─ contracts/              zod + generated JSON Schema + golden fixtures (leaf)
│  ├─ measure-chromium/ measure-webkit/   container driver + counts; Simulator + iwdp, LayerTree census, timeline
│  ├─ model/                  stats + cost model (PURE: no fs, clock, random, browser)
│  └─ fwcore-client/ kb/      id-checked JSON-lines client; frontmatter schema, index, find, lint
├─ docker/counts-chromium/    Dockerfile pinned by digest, apt and npm pinned; fonts only from snapshot/site
├─ lean/                      Lake project fwcore (seeded from the 05 and 10 sketches); math.lock.json GENERATED
├─ fixtures/calibration/      our own micro-pages (WebKit K1-K9 first, K10 both engines, Chromium set)
├─ presets/  profiles/        flag presets, priority.json (yours); scroll scripts, viewport and toolbar replays
├─ research/                 kickoff/ (01-10, unchanged), notes/YYYY/MM-DD-<slug>.md, decisions/ (ADR), INDEX.md GENERATED
├─ refs/                     external/ (papers, docs), upstream/ (sources.lock.yaml, PINS.md, excerpts ≤ 40 lines,
│                            protocol/), rules/<engine>/<family>/*.yaml (with table tests), v1/ (pointers, never copies)
├─ results/                  experiments/<date>-<slug>/{card.md, result.json} (predictions only in card.md), runs/,
│                            index/, validity/, calibration/<device>/, bugs/ledger.jsonl, console/ daily event exports
├─ docs/                      plan/PLAN.md (this file), plan/loop-plan.html (explainer + GENERATED math view);
│                             team/ (token policy, parallel plan, CI brief, handoffs/, improvements/)
├─ .fw-console/               GITIGNORED: live console state, written only by console-api (§7.3, §8.3)
├─ snapshot/site/             the Fastwork original, tracked unmodified (269 files, 30.1 MB; tree id = lock), read-only;
│                             snapshot/site-pretty/ GITIGNORED
└─ .cache/                    GITIGNORED: sparse upstream clones, raw traces, kb.json
```

### 7.2 Frontmatter (one zod schema in `packages/kb`, checked by `pnpm kb lint`)

```yaml
id: 2026-10-17-webkit-presence-flip       # date-slug: no collisions across worktrees
kind: note | decision | ref | rule          status: draft | review | accepted | superseded
title: "..."   created: 2026-10-17   updated: 2026-10-17   authors: [agent:<role>-<topic>, user]
topics: [measurement, webkit]   engines: [webkit]   parts: [people.carousel]   # parts must exist in the registry
builds: ["webkit:7624/ios", "chromium:155.0.8059.80"]   # where the claims apply
links: { refs: [], sources: [], experiments: [], v1: [] }
claims: [{ text: "...", status: CONFIRMED | OBSERVED | INFERRED | WEAKENED | REFUTED, cite: "<id|url>" }]
```

A **rule card** (`kind: rule`) adds `statement`, `source {repo, commit, path, lines}`, `counts`, `test` (its table
test) and `mechanism`; `kb lint` fails when two live cards share a mechanism with opposite statuses [08], and
`fw refs:drift` flags changed cited lines at a new engine tag (it would have caught 7624 → 7625 [04 §11]).

### 7.3 Public repo: what enters git and what never does

- No Fastwork code outside `snapshot/site/`. The repo is **public** (your decision of 2026-10-17, MIT for our code):
  Fastwork approved publishing its compiled homepage, fonts included, so the snapshot is tracked unmodified with its
  source in `NOTICE` (9492807, 53ca23e). Assets are served from it, pinned by tree id (`snapshot.lock.json`), and
  the server refuses to start on a mismatch. An analytics token inside Fastwork's own `index.html` stays as shipped.
- No screenshots, diff images or raw traces. They stay in the local artifact store; git gets index lines and
  summaries only (Q15). Simulator frames may be captured; phone-screen frames only for named recording sets made with
  Do Not Disturb on (Q19; v1 changed this rule three times mid-investigation [08]).
- No personal data: no emails, names, LAN IPs, device ids or home paths (pre-publish grep 454cbe0; now checked on
  every commit). `.local/` (v1 chat digests) is gitignored.
- The live console state: `.fw-console/` in the main checkout (event log, snapshots, spool, socket, secrets),
  gitignored (a `.gitignore` entry) and written only by console-api (Q23; protection in §8.3). Git gets daily
  exports only (`results/console/`).

The ported copy and design values in `apps/site/src/parts/**` count as Fastwork-derived: CSS values are restated,
never copied. Enforced today by the `git add -f`/`--force` and `--no-verify` deny rules (`.claude/settings.json`),
the pre-commit scrub of staged files (`scripts/scrub.mjs` through `core.hooksPath`, set by `wt-prep.sh`; d2574b0;
the whole tree was clean) and Serena `ignored_paths` for `snapshot/**`. Planned: a path rule in the scrub and a
`kb lint` rule. Only you push `main`, add remotes or create repos; agents may push `ci/*` branches only (§8.2).

## 8. Agent teams

### 8.1 Verified mechanics this design relies on

Checked against Claude Code 2.1.301 docs on 2026-10-17 [07 §2, FR §5]; re-verify on upgrade.
- In-process teammates honour the definition's `model`, `effort`, `tools`, `disallowedTools` and
  `autoCompactWindow` (CONFIRMED; split-pane ones do not). One team per session, no nested teams; `/resume` drops
  teammates. Teammates never call `EnterWorktree` (v1 I-272).
- Code-editing roles run as **named worktree subagents**: `name` plus `isolation: "worktree"` **on the call**; without
  `isolation` on the call a named spawn becomes a teammate in the main checkout (CONFIRMED); spawn-guard flags that.
  `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS` does not count teammates (CONFIRMED), so spawn-guard will cap teammates.
- Task tools need `CLAUDE_CODE_ENABLE_TODO_TOOLS=1` in the settings `env` (SPK-a answered). Agent permission rules
  match literal call parameters only, so Fable is behind an `Agent(model:*fable*)` ask rule **and** a lint that
  forbids `fable` in role files (CONFIRMED).
- **Observed in v1** [08]: a finished background task did not wake an idle teammate (I-274); a long foreground
  command left an agent deaf; 20 sends failed on guessed lead names. SPK-p: the v2 lead address is `team-lead`
  (33 of 33 sends); the wake test is open (`spk-p-wake`), and `fw watch` (§8.5) covers the gap.
- **Measured in v2 ([CU]).** Every subagent and teammate cache write is 5-minute (18.0M tokens); only the lead
  writes 1-hour cache (resume rule in §8.2). Agent "API stalls" were the Mac sleeping; `caffeinate -i -w <claude
  pid>` fixes it.
- **Forks have no role (SPK-c, MEASURED 2e0d21b).** 225 of 249 SubagentStops came from internal forks with an empty
  `agent_type`, so "no `agent_type`" cannot mean "the lead"; 18 of 26 workflow spawns skipped spawn-guard (fixed:
  `SubagentStart` logging, 618c1b6). Identity is now: lead iff the hook payload has no `agent_id`
  (`Fw/Ops/Identity`, proved; dec2d82), and `cap.mjs` fails closed.
- **Code tools (rev 6).** Serena 2.0.0 (GPL-3.0, run only as a tool via `uvx`, 5c18b73, d797c60) serves TypeScript
  from the root and Lean from `lean/` (`serena-lean`; it works only from the Lake root, SPK-k). `lean-lsp-mcp` 0.31.0
  runs with its remote search tools off, `lean_hammer_premise` included (SPK-l). Upstream engine source is read from
  pinned sparse clones in `.cache/upstream/` (b65e983), never through WebFetch.

**Bootstrap.** Writing `.claude/**` prompts you (an `ask` rule), so the lead batches settings changes into planned
sittings. No second Claude Code session for side tasks (v1's was nothing but approvals [08]).

### 8.2 Roster

Models are pinned to full IDs: `opus` = `claude-opus-5-5`, `sonnet` = `claude-sonnet-5-5`, `haiku` = `claude-haiku-5-5`,
`fable` = `claude-fable-5-1`. The 14 files in `.claude/agents/` are the truth; this table restates them at 28b18ee.
Helper roles and their rules come from the token policy (`docs/team/token-policy.md`, D1-D7, applied at a0b9053).

| Role | Runs as | Model / effort | Spawned when | Writes |
|---|---|---|---|---|
| lead (main session) | session | opus / medium; `high` when it speeds a decision | always; no `CronCreate`; delegates multi-file reading | lands on `main` (ff-only); commits (rule below) |
| part-builder (`part-<slug>`) | named worktree subagent | sonnet / medium; opus/high per call for `engine.*`, hero exit, morph, the MUI theme and AOT census, and a part that failed its gate once | one part or variant; time box 1 agent-day (2 for engine/morph) | `apps/site/src/parts/<slug>/**` |
| console-builder (`console-<feature>`) | named worktree subagent | sonnet / medium | console features, paired with the `lean-<module>` that owns the behaviour | `apps/console-*/**`, `apps/runner/**` |
| measure-engineer (`meas-<plugin>`) | named worktree subagent | sonnet / high; opus/high per call for the fit, harness neutrality and N0-N5 | one plugin or fit | `packages/measure-*`, `packages/model` |
| lean-prover (`lean-<module>`) | named worktree subagent | opus / high; fable per call (ask) for a stuck theorem | one Lean module; up to 3 alive in M0-M2 | `lean/**`, golden fixtures |
| reviewer (`review-<topic>`) | subagent, fresh, read-only | opus / medium | every change's review stage and every new theorem statement; never the card's owner | nothing (its reply) |
| math-reviewer (`mathrev-<module>`) | subagent, fresh, read-only | opus / high | stale or unreviewed math-view entries; a second instance on a disagreement | a review record (§5.3) |
| researcher, plan-editor | teammate | opus / high | one question per task; plan changes (the only writer of this file) | `research/notes/**`; `docs/plan/PLAN.md` |
| env-ops, page-writer | teammate | sonnet / medium | installs (Homebrew first); explainer pages, never the generated math | toolchain notes; named page files |
| **scout** · **runner** | helper subagent, read-only | haiku / low | a search/read sweep whose answer fits in 1k tokens · build/test runs that need several runs or a diagnosis | nothing (≤ 1k tokens back to its spawner) |
| **checker** · **patcher** | helper subagent | sonnet / medium · sonnet / low | checklist judgement over > 20 KB · a small named edit (lead-spawned only) | nothing · the named files |
| *(no agent)* | scripts + hooks | — | gates, usage meter, device runs, watchers, queue order, land queue, digests (§8.5) | `results/index`, console log |

Not written, and not needed so far: engine-researcher, source-locator, ref-librarian and an Explore override (scout
covers search) and experiment-owner (it arrives with M5).

**Helpers and concurrency (token policy).** lean-prover, researcher, measure-engineer, console-builder and
plan-editor may spawn scout, runner and checker; only the lead spawns patcher. Each parent runs one helper at a time
(two if the lead has at most three direct agents). Spawn depth stays 2. The session cap is 10 subagents
(`CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`), shared across depths; teammates are not counted, so spawn-guard will cap them
at 5 and at 10 spawns per 10 minutes per spawner (shadow mode logs only, §8.3; v1: one agent made 133 spawns in an hour [08]). The parallel
study (5b8a2b1) measured a peak of 12 busy agents, a speedup of 4.9 and the lead busy 46 % of the time; the real limit
is this Mac (16 GB RAM, one Simulator, one timing queue), so the admission rule `Fw/Sched` (§10.1) decides what starts.

**Cache TTL and resumes.** MEASURED: only the lead gets 1h cache; every agent writes 5-minute cache (token policy D6).
So an agent is resumed only while it has been idle less than 5 minutes or its context is under 30k tokens; otherwise
the lead stops it (`TaskStop`, no model turn) and spawns a fresh agent of the same role from its handoff note
`docs/team/handoffs/<name>.md`. A context over 250k is never resumed (124a614).

**From the Fable team review** (`10-17-team-review-fable.md`; applied 98526a5, 492d3fe): editing work goes to
named worktree agents, not Workflow agents; a finished agent is stopped at once; lean-prover runs a 6-item checker
pass before math review; measure-engineer claims classes only over ≥ 3 CI runs; non-gate work left M0 (§10.2).
The lead owns team problems and asks a Fable agent when it cannot decide.

**Who commits.** Teammates never commit: they report their changed files and the lead commits them. Named worktree
subagents commit only on their own branch in their own worktree (`git add -- <paths>`, `git commit -m`). Every change
reaches `main` only through the lead's `fw land` (ff-only, built at 840f7d6, §9.2); any other move of `main` is
detected by the git reconciler and shown to you as a violation. Only you push `main`, add remotes or create repos;
agents may push `ci/*` branches to trigger CI (never force, never delete).

### 8.3 `.claude/settings.json` (committed; the file is the truth)

| Part | As built (3e67d48, 6756bb9, a0b9053) | Still planned |
|---|---|---|
| env | agent teams and task tools on; spawn depth 2; 10 concurrent subagents; Bash output ≤ 16,000 characters; Read ≤ 8,000 tokens; never `CLAUDE_CODE_EFFORT_LEVEL` | — |
| session | `teammateMode: in-process`; worktrees from `head` | — |
| allow | 47 verb patterns: `pnpm fw/kb/test/exec`, `lake build/test/exe`, read-only git, `git add -- *`, `git commit -m *`, `git push origin ci/*`, `gh run list/view/watch/download`, lean-lsp and Serena read tools | more read-only commands after a prompt count (SPK-o) |
| ask | `git remote add`, `git config remote.*`, `Agent(model:*fable*)`, `Agent(general-purpose)`, `Agent(fork)`, `CronCreate`, edits to `.claude/**` and `CLAUDE.md` | — |
| deny | pushes to `main`, force, delete, mirror, `--all`, `+refs`, `git -C * push`; `git add -f`; `--no-verify`, `-n`; `gh api`, `gh pr`, `gh repo create`, releases, gists; the v1 repo; `.local/`; `pkill`, `killall` (b205acc) | edits to `snapshot/**`, `.fw-console/**`, `.cache/upstream/**`, generated files; `git clean` |
| hooks | `emit.mjs`, `cap.mjs`, `spawn-guard.mjs` in `apps/runner/hooks/` (§3.4) | `session-brief.mjs` on SessionStart and after compaction |
| sandbox | none yet | `denyWrite .fw-console`, `denyRead .fw-console/secret`, the CLI socket as the only door (SPK-t) |

**Spawn rule (resolved in rev 6).** Revision 5 had spawn-guard deny every unnamed call, while §8.1 and the token
policy need unnamed read-only helpers. The lead decided (30e3264, `Fw/Ops/SpawnGuard`): unnamed read-only subagents
are allowed (`caps.unnamedReadOnly = true`); a name is still required for anything that edits, and a name in use, an
editing role without worktree isolation, a 6th teammate or a spawn burst is refused. Spawn-guard runs in **shadow
mode** (logs, blocks nothing). Every spawn is now logged, workflow spawns included (`SubagentStart`, 618c1b6).
**Q31 answered: yes, block**, once three things hold (task `spawn-enforce`): a liveness feed fills `alive` and
`recent` (today they are empty, so name-in-use, 6th-teammate and burst refusals cannot show), 1 day of clean shadow
logs, and the A/B bench (`ab-bench`). The Lean decision is proved; the switch is a setting change.

Notes:
- Bash patterns are a convenience, not the guard. The real guards: the snapshot hash refusal at serve time, `fw land`
  re-running the checks (so a commit made with `-n` cannot land), and the land-time path check (`Fw/Ops/PathCheck`,
  proved sound and complete: the diff's paths ⊆ the role's write globs). No `Write(path)` rules: Claude Code never
  reads them; `Edit(path)` rules cover every writing tool (A22).
- The console folder sits inside the project (Q23), so it needs the planned sandbox entries: deny rules do not cover
  a Node or Python process that opens files itself (CONFIRMED, permissions doc). SPK-t checks the paths from worktree
  subagents; the fallback is console-api as a separate macOS user owning `.fw-console/` at mode 0700.
- Prompts: the lead counts permission prompts per hour and adds read-only commands that still prompt. SPK-o measured
  8.4 % of worktree Bash calls refused (2d33185).
- Processes: never kill by name; `pkill`/`killall` are denied since one closed your browser (b205acc).

### 8.4 Cost reporting (speed first, no hard caps)

**Decision of 2026-10-17: speed over token savings.** Removed: the project, milestone and daily caps, their stop
rules, and the Opus share limit. Kept: reporting, a forecast to report against, and soft alerts.

- **v1's bill was context and idling, not thinking** (MEASURED [08 §3], list price, $11.4k): cache reads 44 % of
  dollars, cache writes 41 %, output 14 %; cold rewrites after 5-60 min idle cost 24 %; 19 agents alive over 24 h 36 %.
- **Rules kept because they make the work faster or better:** (1) do not idle past the 5-minute cache (§8.2); (2) no
  LLM polling; (3) fresh, short agents with `maxTurns`; (4) scripts, not agents, for routing and the device;
  (5) search and test runs on Haiku helpers; (6) Bash and Read output caps (§8.3); (7) measurement on CI (§4.1).
- **Loosened for speed:** Opus or `high` effort wherever it shortens the path (§8.2); 5 teammates and 10 subagents;
  up to 5 experiment owners in M5.
- **Forecast, not caps** (rev 3 bottom-up, list-price USD; role split at 931aa35): M0 370 · M1 1,165 · M2 775 ·
  M3 785 · M4 1,450 · M5 1,070 · M6 115 · **total ≈ 5,730**, plus 20-40 % for rev 4's Opus use and $700-1,100 of
  Lean work in place of $280, minus $200-300 of console TS (INFERRED [10.03 §7.1]).
- **Soft alerts, no stops** (a gate above 1.5× its forecast, a day above 2× the average, cold wakes above 10 %).
  **The weekly usage limit is the one real stop** (the provider's; v1 hit it three times [08]): alerts at 60 % and 80 %.
- **Reporting.** `pnpm fw usage` (transcript tailer, deduped by `message.id`, an L1 decision): tokens and dollars per
  gate, role and day; cache-read and cold-wake shares; compactions, refusals and resumes per role; the lead's
  counterparts and inbound messages per hour (alarms at 10 and 60; v1's p90 was 13 and 80).

### 8.5 Coordination rules (from the v1 chat history)

Each rule cites the v1 evidence in [08] and is enforced by a script, hook or lint, not by a memory note. They exist
for speed and quality (a lead free of polls decides faster); their savings are a side effect.

- **Topology.** The lead decides and lands; it does not route. A worker sends its result to its consumer and gives
  the lead ≤ 300 characters plus a file path; reports live in notes and cards. One manager per worker (its spawner).
  *Enforced by* role files and "reports to" in spawn prompts. *v1:* 64 % of messages touched the lead; hand-backs
  ≈ 4k characters; 22 % two-boss switches.
- **No routing agents.** Queue order, land queue, device dispatch, digests and card pre-data reads are `fwcore`
  decisions over `events.jsonl`. A status question in a thread gets a board-rendered reply with no LLM; your "not
  answered" click escalates to the lead (Q29). *Enforced by* console-api. *v1:* 10 mgmt-ops hubs; the lead first on
  78 % of your console messages.
- **Nobody writes status.** Every status field is derived (§3.2) from evidence events. Agents' only console inputs
  are the typed commands below, each refusable by the Lean reducer. Landing with `fw land --task <id>` writes a
  `Task:` trailer, and the trailer, not an agent, marks the work-graph task done (`plan.trailers`, af618a6, acc5d83).
  *Enforced by* deny rules, the capability check and the reducer (proved: `unauthorized_rejected`,
  `only_user_answers`, `review_independent`, `land_requires`). *v1:* 4,412 hand status writes [10.01]; 55 status nags.
- **No LLM polling.** No recurring prompt checks the device, agents or queues; `CronCreate` is `ask`. Watchers are
  scripts: `fw watch` (`obs.health` in Lean: 5 agent states, 14 alert codes; `--interval`, `--until-alert`; 0877f7a,
  noise fix 6eb9068, review fixes in `watch-fix`), the device watcher, and a coalescer for repeated notices.
  *v1:* 3,761 cron fires (42 % of lead turns); one "finished" notice repeated 83 times.
- **Slow work.** The lead checks for agents whose work runs long against its estimate; today a scratch script stands
  in, and `watch-slow` moves the rule into `obs.health`. A load spike from one task (the M0 mutation pass drove the
  load average to ~500) moves that task to CI (§5.4).
- **Waiting.** Waits are foreground with a bounded timeout, never a sleep-poll. Every agent keeps
  `docs/team/handoffs/<name>.md` current (≤ 30 lines), so a stopped agent can be replaced (§8.2). *v1:* $2,763 of
  cold rewrites; a device owner idled 11 h 26 min.
- **Lifetime and compaction.** `maxTurns` on every role; no agent lives across two gates without a handoff note;
  after a compaction the planned `session-brief` re-injects roster, lead address and naming rule. *v1:* 19 agents
  over 24 h = 36 % of dollars; the naming rule lost at a compaction.
- **Names and addresses.** Spawn-guard refuses names in use and unnamed editing spawns (shadow mode until
  `spawn-enforce`, §8.3); restarts are `<role>-<topic>-<n>`; one verified lead address. *v1:* 45 failed sends; 6
  same-name reuses.
- **Your attention.** The console is your channel (§10.1): every row shows "needs you" plus the exact action; one
  digest per card stage change; alarms go to an ops log behind one counter; one question per thread, closed by your
  click; a landing that bypassed the console shows as a violation; device chores are batched into sessions you book
  (§4.1). *v1:* 61 of 80 lead-made threads were alarms; 82-105 of 166 steps were chores.
- **Coaching.** Your rules go into role files and `CLAUDE.md` with their enforcers (§2.1), not into memory notes
  (`kb lint` on role files). *v1:* the same asks on 11 days.

**The judgement commands that remain** (the one catalogue, from [10.01 §5]; each is one typed event, refused when
invalid):

| Who | Commands |
|---|---|
| you (console-web only) | step answer / cancel; proposal decision; priority list; session booking; decision answer; best-build pick when more than one candidate remains; thread posts and "answered / not answered"; `math:sign` |
| lead | card approve; `fw land [--task <id>]` (refused unless land-ready); card drop with a reason; rulings; queue move with a reason |
| owner | card open; `fw park --until <predicate>`; `fw wait --on agent:<id>`; `fw ask-lead --kind …`; hand-back result `landed\|no-gain\|refuted\|blocked`; optional note |
| reviewer | `fw review --sha --accept\|--reject --reasons` (refused if the reviewer owns or built the card, or the sha is not the head) |
| math-reviewer | `fw math:sign <decl>` |
| any agent | `fw screen\|gate\|run\|device` job requests (console-api runs the job and emits the result fact as `script`); kb and bug commands |

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
| **question** | hypothesis, part, variants, mechanism (rule cards), **pre-registered predicted Δ** per stage and zone, landing class, planned comparisons k; a contested behaviour first gets a class P decision | `results/experiments/<date>-<slug>/card.md` | card schema valid; prediction before any data | experiment-owner writes, **lead** approves |
| **build** | the variant behind its flag | commit on `<role>/<topic>`; config hash; parity report | `fw gate --part`: typecheck, TL1/TL2, lints S1-S13, breakpoint lint, build gates, parity level, compositor gate, N0 (+ N2/N3), path check | script |
| **screen** | counts lane on CI, both engines, original preset vs variant; ablations for attribution; transfer overlay on arm A | artifact keys + `screen.json` (dominates / mixed / worse; model prediction; transfer sign) | V-i rules (§1.2); uncounted-family lint; `fwcore screen` | script |
| **review** | fresh-context check: does the result match the card; attribution (positive and negative ablation); no cherry-picking; the `kb lint` mechanism check | `review.md` | reviewer verdict `accept` | **reviewer** (independent: not the owner, not a builder of the card; enforced by the reducer) |
| **device** (only when the class requires it) | a job card queued for the next session you book; preflight first; phone block C V V C, warm-up, sentinel; blind A/B for feel; the owner hands off and exits while it waits | device record + `fwcore verdict` (4v4, k recorded) | verdict `better` or `level` as declared; validity row written | **you** (the swipe) + script |
| **land** | preset updated; validity table updated with prediction vs outcome | `result.json`; `results/index` line | the reducer accepts the land request only when the card is ready (`landReq_ready`); `fw land` fast-forwards `main`; any other move of `main` is a landing **with a violation** (rule below) | **lead** (`fw land`, ff-only) |

**Landing classes** decide whether the device stage is needed:

| Class | When | Device needed? |
|---|---|---|
| **W** less work | the W conditions below all hold | No. Lands on counts; part of the 1-in-5 spot-check sample |
| **SM** smoothness claim or mixed counts | trades one cost for another, claims a feel improvement, or fails any W condition | No, if the model output for this mechanism class has status `sizes` and a valid licence (V-f passed); otherwise yes |
| **X** device-only mechanism | the lint finds `filter`, `backdrop-filter`, `mix-blend-mode` or group opacity changes; toolbar or first-interaction effects; heat | Always |
| **P** proposal | changes the look | Your decision on a Try-it page + blind A/B |

**W conditions:** per-frame componentwise dominance on anchor-aligned steps in both engines, over a vector declared
complete for the mechanism class (sheet mutations included, and 0); the uncounted-family lint passes; no touched
selector, class or custom property until WKTR counts exist (§4.2) and no styling-engine change (S11); same-sign
transfer check; parity level met; layers within budget.

**Land rule.** The git reconciler emits `landed`; a move of `main` that no accepted land request explains is recorded
as a landing with a violation (detected, not prevented). `land_requires` (landed ∧ no violation ⇒ all evidence at
the landed commit) holds over every log (proved, M0).

Rules carried over from v1: one change per arm; stalls belong in the slow landing of an eased motion; a single probe
never becomes a rule. **Every stage is derived from evidence events keyed by the build commit:** a new build sends
the card back to screen and voids older screen, review and device evidence (`built_resets`); between device and land
the state is `landReady` (the lead's move). So the console shows stage, owner, next action and ETA unwritten (§8.5).

## 10. Roadmap: a dependency graph, not a calendar

**No dates (your decision of 2026-10-17).** A workstream starts as soon as its inputs exist; independent ones run in
parallel, each in its own worktree. Milestones M0-M6 are **gates** (exit states). Time is measured, not planned: git
history is the timeline, and the meter reports time and cost per gate (G3, §8.4). The tools are installed [ENV].

### 10.1 Workstreams

This table holds no status: the live state is in the console. "Landed" lists commits on `main` (checked at
d41aef0); "Left" names the open work-graph tasks. Task-level dependencies live in `docs/team/work-graph.json`, which
`fwcore` now reads (`Fw/Plan`; `fw plan sync/show`; the console Plan tab, e920459, with evidence links, 630110e).
A task id is also the agent name and the card id.

| Workstream (where) | Blocked by | Landed | Left (task ids), and what it unblocks |
|---|---|---|---|
| **lean-core** (`lean/`) | — | 9367dea, 14152f1 (`Fw/Serve`), 30e3264 (`Fw/Ops`), 8074907 (M0 mutants), c67cbe4 | `math-r7`; `math:sign` and `math.lock.json`; `mutants-ci` → M0 |
| **console** (`apps/console-*`, `apps/runner`, `packages/contracts`) | lean-core | 8bec088, 3fe1876, eacb660, 840f7d6 (`fw land`), e920459 (Plan tab), af618a6 (`--task`), acc5d83 (last TS stand-ins), 6228fcf | the step queue before any device step; `watch-web`, `alert-steps` → M0 |
| **agent-ops** (`.claude/`, hooks, `scripts/`) | console | 6756bb9, a0b9053, 124a614, d2574b0 (scrub), 618c1b6, dec2d82, 0877f7a (`fw watch`), b205acc | sandbox (SPK-t); `spawn-enforce` (Q31); `watch-fix`, `watch-slow`; `spk-p-wake`; `session-brief` → M0 |
| **counts-chromium** (`packages/measure-chromium`) | the snapshot | e01f9e5, 70c3370, 13b6c98 (SPK-i), 25bd9f4 (touch fix), 5879861 | `touch-ci-verify`, `class-freeze`, `hittest`, `spk-q`, `zone-baselines-chromium` → M1 |
| **counts-webkit** (`packages/measure-webkit`) | — | 1d6c88c, 367fec2 | `sim-speed`, `webkit-quiet`, `step-align`, `webkit-table-regen`, `zone-baselines-webkit` → M1 |
| **lean-measure** (`lean/Fw/Measure/`) | counts lanes | ddc91b2, baa3291 | — (classes, tolerances, zones, self-check in `fwcore`) |
| **store-and-run** (`packages/contracts`, `apps/runner`) | lean-measure | — | `store-and-run` (artifact store, `fw run`), then `vj-vt` (V-j, V-t) → M1 |
| **CI** (`.github/workflows/`) | publishing | d70619d, ee18c6b, 67192ef, 6723de2 (trigger scope) | `ci-webkit`, `fw-ci` (a remote check on every `ci/*` push) → M1 |
| **WKTR** (`packages/measure-webkit`, CI) | CI | 591a815 (research) | `wktr-local` → `wktr-ci-lane`; `wktr-readme-fix`; `wktr-cloud` only as fallback → calibration |
| **site-aot** (`apps/site`) | — | d380999 | SPK-r in WebKit; `css-decide` (Q34, Q35) → port parts |
| **breakpoints and lean-site** | the snapshot | a3e1e9c, ee04fc4, 8bd00aa | — → breakpoint gate |
| **breakpoint gate** (`packages/gate-breakpoints`) | lean-site, pilot parts | e7fb102, 95693f4, d23cf7c, 0d02aff (verdict in Lean) | `gate-unreachable` → `gap-harness` → `gap-device`; `gate-probe-scope`; `ops-gate`; PL2b, PL3, live flips → M2 |
| **lean-parts and pilot parts** (`engine.scroll`, `nav.hitTest`, `hero.*`) | site-aot, M1 baselines | 4d179c3, a2e1ced, 30c814b, 50e5cd1, 88a4302, 4421679, 2566949 | `faithful-checks` (PL3-PL6, N0-N5), then `bands-freeze` → M2 |
| **parallel work** (`lean/Fw/Sched/`) | `Fw/Ops` | 5b8a2b1, 4bd850f, 7d22517, c0bf898, 49b7ff4 | `ab-bench` (Q32) → admission in console-api, `spawn-enforce` |
| **math review** | each Lean module | r4-r7a (§5.3) | `math-r7` → M0 |
| **explainer and plan** (`docs/plan/`) | this plan | rev 7 | — |
| **lean-m1+** (`lean/`) | lean-core | — | the M1-M3 Lean modules of §5.1, each when its consumer needs it |
| **rule cards** (`refs/rules/**`) | counts lanes | — | v1's 16 WebKit rules, Chromium's `compositeFailed` reasons, K1-K10 drafts → calibration |
| **calibration** (fixtures, phone) | WebKit counts, WKTR, phone sessions | — | `phone-session-1`, `calibration`: K1-K10, `ρ_page`, holdouts, validity table v0 → M3 |
| **port parts**, **experiments**, **write-up** | M2; M4; M5 | — | `port-parts` → M4; `experiments` → M5; `write-up` → M6 |

```mermaid
flowchart LR
  LC[lean-core] --> CON[console] --> OPS[agent-ops] --> M0{{M0 bootstrap}} --> M1{{M1 original measured}}
  LC --> LM[lean-m1+] & SCH[parallel work] & M0
  CC[counts-chromium] & WK[counts-webkit] --> LMS[lean-measure] --> SR[store-and-run] --> M1
  CI[CI] --> CC & WK & WKTR[WKTR]
  AOT[site-aot] --> M1
  WK --> RC[rule cards]
  BP[breakpoints, lean-site] --> PP[lean-parts, pilot parts] --> GATE[breakpoint gate]
  GATE & M1 & LM --> M2{{M2 pilots faithful}}
  M2 --> PORT[port parts] --> M4{{M4 all parts promoted}} --> EXP[experiments] --> M5{{M5}} --> WR[write-up] --> M6{{M6}}
  RC & CON & WKTR --> CAL[calibration] --> M3{{M3 calibrated}} -. "class SM only" .-> EXP
```

**Critical path** (INFERRED, re-checked for rev 7). M0 closes with `math-r7` and the remaining agent-ops items. The
M1 chain is the long one: `touch-ci-verify` and `class-freeze`, the per-engine zone baselines on CI (the slow
WebKit Simulator runs, `sim-speed`, are the risk, R33), `store-and-run`, then `vj-vt`. Then pilot PL3-PL6 (M2),
port parts (M4), experiments (M5), write-up. The breakpoint gate's Q33 work (`gate-unreachable` → `gap-harness` →
`gap-device`) runs in parallel and needs one phone session. Calibration (M3) is the second chain: WKTR no longer
waits for a rented Mac, so it is now gated by your phone sessions; class W experiments do not wait for it. Added
only when their absence causes a failure: Turborepo, knip, dependency-cruiser, ast-grep rule sets, REUSE.toml, JCS
keys, `kb lint` beyond the schema, and the later hooks (§3.4).

### 10.2 Gates (exit states)

| Gate | Reached when |
|---|---|
| **M0 Bootstrap** | `fwcore serve` behind console-api; the M0 Lean modules agreed in the math view (`math-r7`: 0 disagree, 0 stale); every M0 mutant killed (done, 8074907); the step queue live; the M0 spikes decided (below the table) |
| **M1 Original measured** | Chromium: every used type signed deterministic or stable (V-i rules, `class-freeze`); touch fix checked on CI; N0/N1 read 0 on arm A (SPK-q). WebKit: deterministic + stable types cover K1-K9. Both: the rest below the table |
| **M2 Pilots faithful** | 3 of 4 pilot parts `faithful` (V-g, V-h, V-o, V-q) through the breakpoint gate, `unreachable` cells checked (§6.6); breakpoint lint green; PL5 and N3 bands frozen; Q34 and Q35 answered and applied |
| **M3 Calibrated** | V-b and V-c on the phone; WKTR counts on CI; model status per output recorded; `@layer mui` kept or dropped from K10; first V-f attempt scheduled |
| **M4 All parts promoted** | every part `faithful` or `faithful-with-delta` through the full breakpoint gate (§6.6); Simulator check passed; console validity, proposals and usage views; **per-module Lean evidence review** (§5.1) |
| **M5 Experiments** | the end-of-page decision made (class P, Try-it); the backlog run as flag arms by v1's measured impact, each known v1 outcome also a **postdiction test**; G1 reached; V-d/V-e/V-f on ≥ 10 changes |
| **M6 Distill** | G4 met; report published (your call) |

**M0 spikes:** SPK-a…e, i, j, k, l, o, p, t recorded as decisions (SPK-t passed, or the separate-user fallback set
up); non-gate work left M0 after the Fable review. **M1, both engines:** per-zone baselines of the original on CI;
V-j shown; SPK-r passed or a fallback chosen; V-t and the stall-alarm precision (≥ 90 %) reported.

**Contradiction resolved (rev 7).** The rev-6 M1 row asked for "all used count types deterministic", while the SPK-i
decision lets stable types in as totals with margin 2t. The plan follows the decision, because "deterministic only"
would drop the main scroll-cost types (§1.2, V-i rules).

## 11. Risks and mitigations

| # | Risk | Likelihood / impact | Mitigation |
|---|---|---|---|
| R1 | The React port looks right but does different engine work (reconciliation, effect order, DOM depth, hydration), so findings do not transfer | medium / high | PL5 bands + PL6 timing parity for experiment parts; the transfer check on arm A at every landing; prerender; DOM shape kept close |
| R2 | The model looks precise and steers wrong (v1: right about work, wrong about feel; one 4-5x over-prediction) | medium / high | Decision and feel agreement before any stand-in; "ranks-only" status; class X always on device; spot-checks; retire outputs after 2 misses |
| R3 | WebKit-only and render-server costs are invisible off the device | certain / high | Separate WebKit counts; CA-rate component; `RS` priced by Instruments; class X |
| R4 | Experimental interfaces break (`HeadlessExperimental`, Playwright webview backend, agent-team fields) | medium / medium | Pin versions and the container digest; re-verify fields on each Claude Code upgrade |
| R5 | Coefficients are unidentifiable (collinear flag designs) or drift (heat, LPM, versions) | medium / medium | Micro-fixtures; fractional factorial designs; θ per run; `ρ_page`; re-calibration triggers |
| R6 | Wrong spec, correct proof | medium / high | Math-reviewer back-translation without the docstring (§5.3); deep statement hashes; `#guard` examples from v1 data; mutants (V-r: 0 of 625 survived in M0); no proofs about transcribed engine rules. The kickoff check found 8 translation errors that compiled fine [10] |
| R7 | Over-engineering before the first measurement (v1 day 1 was 38 % process) | high / medium | M0 is a vertical slice; MVP tier (§3.4); every new tool names the incident class it prevents; a new agent rule must cite an agent-mistake incident, otherwise fix the tool |
| R8 | Port size: ~11.8k lines of CSS, half dead; Platform visual mapping only inferred; every breakpoint of every part must match (your requirement), which multiplies PL0-PL3 runs | high / medium | Full work parity only for experiment parts; time box per part; `faithful-with-delta` never for breakpoints; a generated breakpoint inventory and lint; the core matrix per PR, the full gate before promotion |
| R9 | MUI everywhere pollutes measurements: Emotion inserts or moves style sheets (a WebKit full style rebuild per frame; invisible to the planned counts, CONFIRMED [09.04]), class churn, theme re-renders | high if unconstrained | Emotion AOT (§6.5); rules S1-S13 with lint; N0-N5 (§6.7) with `impl: plain` twins; K10 prices one insertion; SPK-r first; `runtime` build as a negative control |
| R10 | Legal scope of a public port of copy and design values (public by your decision of 2026-10-17, 1594cd5; publish prep 454cbe0) | low / high | Fastwork's approval covers the compiled site, fonts included (README, NOTICE); the snapshot is tracked unmodified; our code restates CSS values and copies no Fastwork code (§7.3); the pre-publish personal-data grep was clean (454cbe0) |
| R11 | Toolchain churn (Lean monthly, TS 7 native port vs tools, MUI minors) | medium / low | Pin `lean-toolchain` to `leanprover/lean4:v4.35.0`, `typescript@6.0.3` and exact MUI/Emotion versions; bump in one deliberate PR; an MUI bump re-runs N0-N5 on all parts (S11) |
| R12 | `servedHash` under-invalidates (runtime-fetched assets) | low / medium | Assets only through Vite imports; the runner refuses a result whose requests leave the manifest closure |
| R13 | Shared caches fill the disk (v1 I-095); `.lake` is ~603 MB logical per worktree (APFS clone, MEASURED); 22 GB free at d41aef0 | medium / medium | `wt-prep` clones `main`'s `.lake` (7d22517); the Lake artifact cache (c0bf898); measurement on CI; WKTR needs ~3 GB, not a WebKit build; `fw cache prune` + size caps |
| R14 | Spend surprises or hitting the weekly usage limit (more likely now that caps are gone) | medium / medium | Daily cost reporting; soft alerts; 60 % / 80 % weekly-limit alerts; agents on 5-minute cache, stopped and respawned from handoff notes (§8.2); `maxTurns` (§8.4) |
| R15 | The harness changes the mechanism it measures | CONFIRMED / high | No seeking in Chromium; native rAF; seek overhead measured in WebKit; V-n per family |
| R16 | Container counts differ from Mac Chrome (fonts, software raster) | medium / medium | Fonts from `snapshot/` only; V-a per family; Chromium as a development aid |
| R17 | Device link instability: v1 had 36 USB, WDA and Wi-Fi incidents, never root-caused, and a toolchain update broke its compiled link shim [08] | high / high | Device watcher logs every attach and detach from the first device step; preflight before each session; SPK-n link soak with a cable and port swap; no compiled native shims, or a pinned toolchain |
| R18 | Agents stall or go deaf: a background notice does not wake an idle teammate; long foreground commands block messages [08] | medium / medium | Stall watcher in console-api; bounded foreground waits; re-checked by SPK-p on each Claude Code upgrade |
| R19 | The lead becomes the hub again (polls, relays, first responder) [08] | medium / high | §8.5: no LLM polling, no routing agents, results peer-first, span alarms at 10 counterparts and 60 messages an hour |
| R20 | You become the device technician and status bus again [08] | medium / high | G2 chore target; booked sessions with one get-ready step; "needs you" set only by events; status questions answered by script |
| R21 | Emotion AOT fails as a whole: server and client class hashes differ, states the census cannot reach, Popper styles, hydration mismatches that production React does not patch [09.02, 09.03] | medium / high | SPK-r before any part is built; a `cache.insert` miss fails the build; per-part Base UI fallback; whole-site Pigment fallback on MUI 9.0.1 (paused alpha, a build about 25× slower) |
| R22 | MUI behaviour, not styling, breaks parity: Tabs indicator layout animation, transitions with forced reflow, FocusTrap's 50 ms interval, Modal scroll lock, wrapper elements in PL0/PL1/PL5 [09.01 §6] | high / medium | S5-S7, S12; `parity.json` wrapper map; N3 wrapper allowance; per-part Base UI fallback; `faithful-with-delta` |
| R23 | The uniqueness trap: a stateful Lean loop that reads then writes the state copies the whole map per event (66× slower, MEASURED [10.03 §4.2]) | medium / medium | `modifyGet` in the ~30-line IO loop; `seen` as a `HashSet`; a 100k-event speed budget in `lake test` |
| R24 | A toolchain bump changes statement hashes and marks many math entries stale | high on a bump / low | `mathview accept --toolchain-bump` re-signs only entries whose signature text and machine-made LaTeX are unchanged; one reviewed PR per bump (R11) |
| R25 | The strict Bash sandbox (Q22; not applied yet, SPK-t unmet) breaks worktree builds, or its relative paths resolve to a worktree instead of the main checkout | medium / medium | SPK-t before the team relies on it; absolute paths in `settings.local.json`; fallback: console-api as a separate macOS user owning `.fw-console/` at 0700 |
| R26 | A fact producer misses events (a hook does not fire, a commit is made with hooks off, `SessionEnd` is cut at 1.5 s) and the console is briefly wrong | high / low | reconcilers re-read git refs, transcripts and artifacts every 2-60 s and are the only git producer; agent end = latest of `SubagentStop` and transcript idle; seen-on-accept keys make re-sends converge (`reorder_converges`, to prove) |
| R27 | Role claims on the CLI socket are forged, so a builder reviews its own work or an agent acts as lead | medium / high | `cap.mjs` binds each request to the agent id; lead iff no agent id (proved, dec2d82; it once mapped forks to the lead, SPK-c); `review_independent`; your decisions never come from the socket |
| R28 | The console folder lives inside the project (Q23): `main` moves outside `fw land`, or `git clean -x` damages the folder | medium / medium | every unexplained move of `main` is a violation on your needs-you list; deny rules on `.fw-console/`; snapshots plus daily exports to rebuild from |
| R29 | Public CI leaks a secret or runs untrusted code, or a commit makes personal data public | low / high | `contents: read`; actions pinned by SHA; inputs through env; agents push only `ci/*` (§5.4, §8.3); the pre-commit scrub on every commit (d2574b0, §7.3) |
| R30 | Host load and sleep disturb runs and agents (load1 is no gauge on macOS; the Mac slept mid-run; the mutation pass drove load to ~500) | high / medium | measurement on CI (§4.1); `caffeinate`; `scripts/sim-lock.sh`; per-type classes (V-i); mutation runs on CI; the A/B bench (Q32) |
| R31 | An agent kills the wrong process (one ran `pkill -f "Google Chrome"` and closed your browser) | happened / medium | `CLAUDE.md` (6fba06c): kill only own PIDs; `pkill` and `killall` denied (b205acc) |
| R32 | Lean-first debt grows: TS stand-ins outlive their Lean spec | medium / low | console stand-ins are gone (acc5d83); left: `compositeCuts`, `reduceWindows` in the WebKit harness; agents list stand-ins in every report |
| R33 | CI capacity is the new bottleneck: WebKit Simulator runs take 10-38 min and fail at warm-up; 5 macOS jobs at a time on the free plan | high / medium | `paths:` filters and stale-run cancel (6723de2); `sim-speed`; WKTR as a second WebKit lane; one short local debug run allowed (§4.1) |

## 12. Decisions

### 12.0 Decisions made 2026-10-17

| # | Question | Your decision | Applied in |
|---|---|---|---|
| Q1 | Devices and sessions | **iPhone 15 Pro Max on iOS 27.0.1 (Safari 27); no Android phone.** The iOS 27.0 Simulator matches. Chromium stays a development aid (Q8). Rev 7: **phone sessions on demand**; the second iPhone stays free-play, out of measurement | §0, §1.2 V-c, §4.1, §4.6, §10.2 |
| Q2 | Install the Lean toolchain? | **Yes.** elan 4.2.4 (Homebrew `elan-init`) and Lean 4.35.0 are installed (CONFIRMED [ENV]). `lean-toolchain` pins `leanprover/lean4:v4.35.0` | §3.2, §10, R11 |
| Q3 | Repo visibility (1594cd5) | **Public, with history, MIT for our code.** Fastwork approved publishing its compiled site, fonts included; the snapshot is tracked unmodified. Only you push `main`; agents may push `ci/*` | §5.4, §7.1, §7.3, R10, R29 |
| Q4 | MUI scope | **MUI everywhere**, compiled to static CSS with **Emotion AOT** on MUI 9.5 (Pigment is paused). SPK-r and N0-N5 check it; fallbacks: Base UI per part, Pigment on MUI 9.0.1 for the whole site ([09] README) | §0, §3.1, §6.1-§6.7, R9, R21, R22 |
| Q12 | Lean scope | **Lean-first** (your requirement): every decision, queue and status view that can be proved is an L1 module, by milestone; mutants and a per-module demotion rule replace the M4 go/no-go | §0, §1.2, §3.3, §3.4, §5.1, §10.1, R6 |
| Q16 | Budget | **Looser: speed over token savings.** No hard caps or stop rules; cost reporting, the forecast and soft alerts stay; Opus or `high` effort where it speeds the work; anti-waste rules that also save time stay | §1.1 G3, §8.2-§8.5, R14 |
| Q22 | Sandbox for every agent | **Yes, strict** (no unsandboxed retry); not in `settings.json` yet, waiting on SPK-t | §8.3, R25, SPK-t |
| Q23 | Where the console lives, and who moves `main` | **Inside the repo** in the gitignored `.fw-console/`, console-api its single writer, guarded by deny rules. **`main` stays a normal branch**; the lead lands with `fw land` (ff-only); any other commit on `main` is flagged as a violation | §2.2, §3.2, §3.4, §7, §8.3, §9.2, R28, A21 |
| — | Breakpoints | **The rewrite supports every breakpoint of the original identically, for every part**: a generated `breakpoints.json`, a breakpoint lint, and a breakpoint gate (PL0-PL3 at both sides of every edge, input-mode combinations, JS-gated widths, live resizes) before any part is promoted | §1.2 V-g, §6.6, §9.2, §10.1 M2/M4, R8, Q5 |
| — | Schedule | **No calendar:** a dependency graph run as soon as possible in parallel; milestones are gates, not dates; time is reported per gate | §0, §10, G3 |
| Q24 | Lean first, everywhere reproducible | Console (so Q24: `fwcore` is the console brain), site, measurement and tooling: specified and proved in Lean before coding; Lean runs it, generates it, or provides golden vectors; only I/O, rendering and glue stay unproved | §3.1, §3.3, §5.1, §6.6, §10.1 |
| — | Console upkeep | **Nobody writes status** (your requirement): every view is derived from the event log; agents have no write path; judgement is a typed command | §0, §2.2, §3.2, §7, §8.3, §8.5, §9.2, §10.2 |
| — | Reading proofs | **You read math, not Lean** (your requirement): docstring math, a generated math view, a build gate on unsigned or stale math, a math-reviewer role | §0, §5.3, §5.4, §8.2 |
| — | Lean packaging | **Mathlib-free core, optional `FwMath`** for proofs that need Mathlib; `Fw` never imports it | §3.4, §5.1, §5.2 |
| — | Installs | **Homebrew** (`brew install` / `--cask`) whenever a formula or cask exists; otherwise the lead is asked first | §8.2 env-ops, §10 |
| — | Agent operations | **Token policy r2 approved** (a0b9053: helper roles, output caps, concurrency 10) and **hooks installed** (3e67d48); project-level Serena 2.0.0 (d797c60) | §8.1-§8.3 |
| — | Measure on CI | **Counts and gates run on GitHub Actions, not on this Mac** (417d90d); this Mac keeps phone sessions, one short debug run, and lanes CI cannot run yet | §4.1, §5.4, R30, R33 |
| — | Kill by name | **`pkill` and `killall` denied** after an agent closed your browser (b205acc) | §8.3, R31 |
| Q31 | Spawn-guard blocking | **Yes**, after a liveness feed, one day of clean logs and the A/B bench (task `spawn-enforce`) | §8.3 |
| Q33 | Breakpoint cells the harness cannot reach | **A Simulator or device check for both** the fractional gaps and the hover × pointer cross; the gate gets an `unreachable` cell state (task `gate-unreachable`) | §6.6, §10.2 M2 |
| — | Count-type classes (SPK-i) | **Stable types count as totals with margin 2t; the signed class is the worst over ≥ 3 CI runs** (lead decision 6b4237e; `class-freeze`) | §1.2 V-i, §4.2, §10.2 M1 |
| — | WKTR | **WebKit's prebuilt iOS-simulator products on GitHub macos-26** (591a815); the rented cloud Mac is a fallback only | §4.2, §10.1, Q10 |

### 12.1 Open questions for you (Q32 from rev 6; Q34-Q35 added in rev 7)

Q1, Q31 and Q33 are answered (§12.0).

**Q32. A window for the A/B bench.** The parallel-work bench (8 blocks, a random labeling out of 70) must run with no
agent alive: about 96 minutes plus baselines (`docs/team/parallel-plan.md`). It tests whether admission control
beats the current free spawning, and Q31's blocking waits for it. **Recommend:** one evening slot after M0, when no
phone session is booked.

**Q34. MUI `cssVariables` (rule S8).** Today the theme emits its tokens as `:root` custom properties (`true`), and
nothing reads them. Options: (a) keep `true`, (b) `true` trimmed to the referenced tokens, (c) `false`.
**Recommend:** c, because only c keeps N4's root custom-property count within ±10 % of the original, and the one
measured benefit of `true` also holds with `false` in MUI 9.5 (INFERRED from code, `10-17-css-decisions.md`
Decision 1). Task `css-decide` applies your answer.

**Q35. The original's dead CSS (§6.1).** Should `faithful` add the never-matching rules back as an inert stylesheet?
**Recommend:** a, no inert sheet: MUI's static census already puts the rewrite above the original's rule count, and
neither engine's per-element matching sees unmatched class-keyed rules. The N4 rule-count difference becomes a
K-fixture parameter (§12.3; same note, Decision 2).

### 12.2 Defaults we will use unless you object (one line each)

- **Q5 Fidelity:** look + work parity (PL0-PL6) for experiment parts; look parity (PL0-PL3) for the rest; every breakpoint for all parts (decided); time box per part, then `faithful-with-delta`.
- **Q6 Parity reference:** the snapshot `b1789284481295-a455e793`; the faithful morph is the original 680 ms scroll-jacked tween; g0.0m is the preset `v1-best`, and its look changes are proposals.
- **Q7 Device budget:** iPhone 15 Pro Max on iOS 27.0.1 (Safari 27) is the target; sessions on demand (Q1); expect 5-10 before the first licensed class; classes X and P always use the phone; calibration every Safari/iOS change, every 14 days, or after 2 out-of-band spot-checks.
- **Q8 Chromium's role:** a development aid (counts, mechanism, screening, timing parity), with no fitted coefficients, since there is no Android phone; the Android emulator adds Chrome-for-Android counts, never timing.
- **Q9 Acceptance bands:** V-a to V-t as in §1.2; a licence is per change class, never for all changes at once.
- **Q10 WebKit element counts:** until WKTR counts exist, no class W for style-affecting diffs and ranks-only for style changes. WKTR runs from WebKit's prebuilt archive on GitHub macos-26 (`wktr-local` → `wktr-ci-lane`, 591a815); a rented cloud Mac (`wktr-cloud`) only if that fails.
- **Q11 Optimized variants:** compositor gate (free-running), layer budget, no pixel-moving filter animation, no scroll-linked JS style writes unless waived; 60 Hz canonical, 120 Hz also reported for Chromium.
- **Q13 Landing verdict:** 4 vs 4 runs with a null false-win rate ≤ 1/70 (proved, `land_null_prob`, 9367dea); comparisons counted per experiment; 5v5 or sequential when k > 3.
- **Q14 Loop protocol:** question → build → screen → review → (device) → land, with classes W/SM/X/P (§9).
- **Q15 Raw traces:** local artifact store only; git gets index lines and summaries.
- **Q17 Agent-team operation and helper tools:** the lead writes one decision record after the M0 spikes, starting from the draft in Appendix C.
- **Q18 Waiting:** the lead on the 1h cache, every agent on 5m (MEASURED); an agent idle past 5 minutes with over 30k context is stopped and respawned from its handoff note, and an agent over 250k is never resumed (§8.2, §8.5).
- **Q19 Screen capture:** Simulator frames allowed; phone-screen frames only for named recording sets made with Do Not Disturb on, kept in the local artifact store.
- **Q20 Supervision:** no recurring LLM check prompts; `CronCreate` asks you first; console-api watchers wake agents only on a change (§8.5).
- **Q21 MUI fallbacks and the style-engine A/B:** SPK-r decides. A part falls back to Base UI 1.9.0 + CSS Modules, one at a time, when its census cannot be completed, an N0/N1/N5 incident cannot be fixed in its time box, or its N2/N3 delta comes from MUI (§6.7). The whole site moves to Pigment on MUI 9.0.1 only if SPK-r fails at the mechanism level. The optional Pigment arm (SPK-s, 1 agent-day, M2) runs once unless you say skip.
- **Q25 Math view placement and scope:** a tab in console-web that shows the generated page (also openable on its own); math required on every theorem and on every definition you read, not only on theorems. Default: both.
- **Q26 Lease starvation:** the device lease can be renewed forever today (MEASURED [10.04 §5]). Default: no renewing while someone is waiting, plus a cap on total hold time, with a bounded-wait theorem; alternatives: the cap only, or a fairness assumption stated in the theorem.
- **Q27 Aging step:** a waiting job rises one priority level every A = 300 s, so a spot-check overtakes newly arriving user steps only after about 25 h. Default: a tighter bound, every job starts within 2 h of a booked window that fits it. (The agent admission rule `Fw/Sched` has its own, proved aging bound: an aged job is admitted before $t + (1+\Psi)\cdot d_{max}$, where $\Psi$ counts older queued jobs that can fit; the first, simpler bound was false, 4bd850f.)
- **Q28 Math disagreements:** when the math-reviewer's own math and the docstring disagree, a second independent reviewer decides first; you see only what stays unresolved. Alternative: ask you every time.
- **Q29 Status questions in threads:** answered automatically from the board (no agent), with a "not answered" button that escalates to the lead. Default: yes.
- **Q30 Small defaults:** class W cards still need the lead's `fw land` (no auto-land); knowledge-base read receipts (v1: 1,006 acks) are dropped, and "read by" is derived from read events; an ETA, if an agent has one, goes in its note and is shown with its age, never used by the scheduler; the best build is the set of versions no head-to-head comparison beats, and you pick when there is more than one.

### 12.3 Open items from the revision 4 review (styling), with recommendations

| Item | Recommendation |
|---|---|
| Base UI vs Pigment as the fallback | Base UI per part first; Pigment for the whole site only if SPK-r fails at the mechanism level (Q21): Pigment is a paused alpha |
| Neutrality-gate blind spots (Emotion's per-render JS, style-sheet shape cost) | N4 and PL6 for now; if SPK-h finds Chromium's selector-stats trace, add its match-attempt count as a deterministic N4 family |
| MUI behaviours replaced (S5-S7, S12: transitions, Tabs indicator, Avatar `src`, ripples) | Accept, and list each in `part.json`, so the write-up can say how much of MUI ran |
| N4: gate or parameter (it cannot fail today; a shape difference beyond ±10 % becomes a K-fixture parameter) | Keep it a parameter that flags the part for PL6; a gate only if K10 shows shape alone moves frame cost |

## Appendix A. Conflicts between the kickoff notes, and how this plan resolves them

| # | Conflict | Resolution | Why |
|---|---|---|---|
| A1 | **Where decisions run.** [05]: Lean decides at runtime via `fwcore`. [06]: TS `core` with differential tests | [05]'s rule, widened by [10.03]: decisions **and** bookkeeping in `fwcore` (Lean-first); a TS mirror only in the browser (the flag resolver, tested on its whole domain) (§3.3) | One implementation; the round trip costs microseconds, and v1's failures were in the bookkeeping |
| A2 | **Console storage.** [05]: `events.jsonl` + snapshots. [06]: Hono + SQLite | The event log is the truth; SQLite only later, as a disposable read model | MVP tier |
| A3 | **MUI.** [06] and [07] write "React + MUI" for parts; [02] limits MUI after reading its source; [09.04] puts Pigment first, [09.01]-[09.03] put Emotion first | MUI everywhere (your decision, rev 4) with Emotion AOT; Base UI per part and Pigment on MUI 9.0.1 as fallbacks | The engines see static CSS on a supported MUI; MUI behaviours (S5-S7, S12) are gated by N0-N5 |
| A4 | **Copying the original.** [07]'s part-builder says never copy class names or CSS. [02] maps anchors to original selectors and restates CSS values | Parts use their own class names; `parity.json` may name original selectors as locators; design values are restated; code and assets are never copied | Parity needs locators and values; the legal line is code and assets |
| A5 | **Serena `rename_symbol`.** [06] enables it; [07]'s draft denies it | `ask` until the Q17 decision record | Your call |
| A6 | **Teammate effort.** [01] (v1, 2.1.286): teammates ignore `effort`. [07] (2.1.301 docs): in-process teammates honour it | [07]; CONFIRMED again by [FR §5] | Newer docs |
| A7 | **Acceptance thresholds.** [03] and [04] propose different sets | Merged into V-a to V-p (§1.2), with the Chromium fit made optional | They measure different things |
| A8 | **The compositor gate vs faithful variants.** | The gate applies to `optimized` variants only | Faithful variants exist to reproduce costs |
| A9 | **Lifecycle.** [05]'s sketch proves v1's R→I→D→F→V→L | v2's question → … → land (§9), derived from evidence keyed by commit and proved in M0 (`Fw/Console`); [05]'s R/I/D/F/V/L cards become sections of `card.md`, not stage transitions | Engine-stat measurement changes the gates, as [05 §7 Q4] anticipated |
| A10 | **Reference store paths.** [01] `references/`; [04] `refs/webkit/…`; [06] `refs/upstream/…` | `refs/upstream/` for pins, excerpts and protocol; `refs/rules/<engine>/<family>/` for rule cards | One store for both engines |
| A11 | **Spec-reviewer model.** [05]: mid-tier is enough. [07]: Opus high/xhigh | Opus medium; `high`/`xhigh` per call for theorem statements and neutrality-gate rulings (§8.2) | Wrong spec is the main Lean risk (R6); effort where it speeds a correct ruling (§8.4) |
| A12 | **An `ask` rule on every measurement-code edit** ([07] draft) | Dropped; the golden-semantics gate and the review stage guard it | It would interrupt you without adding a check |
| A13 | **Snapshot location.** [02]: `FW_SNAPSHOT_DIR`. [06]: gitignored `snapshot/` | `snapshot/site/`, tracked unmodified since the repo went public (rev 6), read-only and verified against `snapshot.lock.json` | One path for tools; Fastwork approved publishing it |
| A14 | **Where the cost model lives.** [05]: `Cost.lean`. [06]/[03]: TS `cost-model` | Fitting and evaluation in TS (`packages/model`); the screening theorem in Lean (`fwcore screen`); an L1 checker accepts the coefficients (non-negative, exact fractions) before deployment | Fitting is numeric; the landing decision is not |
| A15 | **Bootstrap order.** [06]: site skeleton first. [03], [04]: counts first | Counts on the **original snapshot** from the start (counts-chromium), in parallel with the other workstreams | Baseline first; de-risks the method (R7) |
| A16 | **Cache TTL.** [08]'s lenses: "1h for waiting roles" vs "keep 5m for device-blocked owners"; rev 5 set 1h on most roles | Rev 6: the lead 1h, every agent 5m; idle past 5 minutes with over 30k context → stop and respawn from the handoff note (§8.2) | MEASURED: agents only ever write 5-minute cache; resuming them later re-reads the whole context |
| A17 | **Three stage models.** [10.01] stage cards closed by judgement; [10.02] stages derived from evidence; [10.03] a third list | [10.02]'s evidence-derived `Stage`, used by every module | No stage command to forget; a rebuild voids old evidence by itself |
| A18 | **Three manual-input catalogues.** [10.01 §5], [10.02 §5] (13 inputs), [10.03] (`note` events) | One catalogue (§8.5, from [10.01 §5]) | One list to enforce in the `may` table |
| A19 | **Numbers that differ across notes 10.01-10.03** (status writes, upkeep turns, round trip) | One canonical value each, with its command, in the "Canonical numbers" table of `docs/plan/rev5-delta.md`; this plan quotes only those | Each figure has one command |
| A20 | **Math sync.** [10.02] `math:` lines + regenerated `MATH.md`; [10.03] `#math_doc` tags; [10.04] deep hash + lock + reviewer | [10.04] (§5.3), with the sign-off as an event | The other two passed a retag alone, missed definition bodies or skipped imported modules (MEASURED) |
| A21 | **Who lands.** Rev 4: the lead runs `git merge --ff-only`. [10.02]: console-api merges in its own bare repo | The lead lands on the normal `main` with `fw land` (ff-only, after the reducer accepts); state in `.fw-console/` (Q23); other moves of `main` are flagged as violations | Your choice: one normal repo is simpler. The guard is detection, not prevention (R28) |
| A22 | **`Write(path)` rules.** Rev 4 §8.3 and the revision 5 delta list `Write(...)` allow and deny rules; the config review found Claude Code never consults them | `Edit(...)` rules only (§8.3) | A rule that is never read gives false comfort |
| A23 | **Unnamed spawns.** Rev 5 §8.3: spawn-guard denies every unnamed call; §8.1 and the token policy: unnamed read-only helpers | Unnamed read-only allowed (`caps.unnamedReadOnly`), shadow mode first (§8.3) | Helpers need no name or worktree; a name still guards every editing spawn |
| A24 | **M0 determinism.** Rev 5: two byte-identical Chromium vectors. SPK-i: whole files never match | Per-type classes (V-i, §1.2) | The deterministic types do match; byte identity fails on thread ids, GC and async work, which feed no model |
| A25 | **Which classes M1 accepts.** Rev 6 §10.2: every used type deterministic. SPK-i decision (6b4237e): stable types too, as totals with margin 2t | The decision (§1.2 V-i rules, §10.2 M1) | "Deterministic only" would drop the main scroll-cost types; totals with 2t keep them, with a proved margin |
| A26 | **Where WKTR runs.** Rev 6 Q10: a rented cloud Mac (~120 GB build). 591a815: WebKit's prebuilt iOS-simulator archive (315 MB) runs on GitHub macos-26 | Prebuilt on CI first (`wktr-local` → `wktr-ci-lane`); the cloud Mac only as fallback | No build, no rental, and CI is where counts run now |
| A27 | **Unreachable breakpoint cells.** Rev 6 recommended accepting the fractional gaps; you answered Q33 "a Simulator or device check for both" | Your answer: an `unreachable` state in the Lean gate, then a Simulator or device check per such cell (§6.6) | Your rule is every breakpoint identically; a cell the harness cannot reach must still be checked somewhere |
| A28 | **Where counts are measured.** Rev 6: local container and local Simulator runs. CLAUDE.md (417d90d): CI | CI (§4.1); local runs are debug only and never reported as results | Local runs fought agent load and sleep (R30); CI runs are clean and reviewable |

## Appendix B. Spikes (each answer becomes a decision record)

Statuses at d41aef0, from the decision-record drafts (`research/notes/2026/10-17-spk-drafts/`, 2d33185) and later commits.

| Spike | Question | Status |
|---|---|---|
| SPK-a | Does `CLAUDE_CODE_ENABLE_TODO_TOOLS` take effect from the project `env`? | ANSWERED (MEASURED, 2d33185) |
| SPK-b | Does `name` + `isolation: "worktree"` on one Agent call give a named, messageable worktree subagent? | ANSWERED (MEASURED: 28 agents, 50 sends, 0 errors) |
| SPK-c | Do hooks inside in-process teammates carry `agent_type`, or only `agent_id`? | ANSWERED (MEASURED, 2e0d21b): forks carry an empty `agent_type` (225 of 249 SubagentStops); 18 of 26 workflow spawns skipped spawn-guard; fixed by the `SubagentStart` log and `Identity` (dec2d82) |
| SPK-d | Does `Agent(model:*fable*)` match (wildcards in parameter values)? | partial: docs say yes; one observed firing missing |
| SPK-e | Where do teammate transcripts live, for the usage meter? | ANSWERED (MEASURED: `<session>/subagents/agent-<id>.jsonl`) |
| SPK-f | Do per-package `CLAUDE.md` files load when an agent works in that package? (Turborepo `cacheDir` moves to the later tier) | open |
| SPK-g | Can `xctrace` System Trace attached to macOS Safari decode WebKit kdebug trace points by name [04 §4.6]? | open |
| SPK-h | Do the Chromium trace argument paths (`elementCount`) and the invalidation-rect categories hold on the pinned build [03 §7.4]? Do the N1 slices (`StyleEngine::updateActiveStyleSheets`, `scheduleInvalidationsForRuleSets`, font-update) exist there, and what does the `blink_style` category cost [09.03 §6.4]? | open; before SPK-q relies on N1 |
| SPK-i | Does linux-arm64 headless-shell in a container accept BeginFrameControl with the three flags, with fonts only from `snapshot/`, and give byte-identical count vectors? | DECIDED (6b4237e): never byte-identical, so per-type classes; stable types as totals with margin 2t; the worst class over ≥ 3 CI runs (`class-freeze`); pixel-area bound (5879861) |
| SPK-j | Harness neutrality: clock shim with native rAF vs free-running (Chromium); seek overhead per accelerated animation (WebKit) | partial: WebKit seek adds 122 style records, independent of N; Chromium shim vs free-running open |
| SPK-k | Does Serena's `lean4` language server answer `find_symbol` on a Lean file? (`lean4` is in Serena's language list, CONFIRMED in `.serena/project.yml`.) If not: Serena for TypeScript only, lean-lsp-mcp for Lean | ANSWERED (MEASURED): works only from the `lean/` project (`serena-lean`) |
| SPK-l | lean-lsp-mcp: exact local tool names, and a launch flag that disables its remote search tools | ANSWERED: `--disable-tools`, 5 local tools in 0.31.0; `lean_hammer_premise` disabled too (2d33185) |
| SPK-m | WebKit determinism per count type (stepped vs held-state) | answered in part (367fec2): per-step Layout/Paint quarantined, totals within 3-5 % (§4.2) |
| SPK-n | Device link soak: one hour idle with an attach/detach logger, then a cable and port swap; do WDA, the proxy and UI Automation survive a re-plug? | open; first booked phone session (M3 at the latest) |
| SPK-o | Can a named `isolation: "worktree"` subagent run `pnpm fw gate --part x`, `git add -- p` and `git commit -m` with zero isolation refusals? | partial: 8.4 % of worktree Bash calls refused; plain add and commit work |
| SPK-p | On the v2 Claude Code version: the lead's SendMessage address; does a finished background task wake an idle teammate; does `SessionStart` fire with source `compact`? | partial: lead address `team-lead` 33 of 33; the wake test is task `spk-p-wake` (with `fw watch`) |
| SPK-q | Styling-neutrality baseline: do N0/N1 read 0 on arm A in W-rest and W-measure, in both engines? | open (moved to M1): the lanes do not record N0/N1 yet; needs SPK-h |
| SPK-r | Emotion AOT: with Button, Dialog, Menu, Tabs and Drawer in the harness, 0 insertions and 0 tag moves after hydration in both engines, nothing inserted when an overlay opens, and a green N5? Details below the table | **Chromium half MEASURED, pass** (d380999): `aot` 0 insertions, 0 `cache.insert` after the mark; the `runtime` control caught (69 insertions). Open: WebKit, N5, plain vs mui, timing, the `styled(Wrapper)` extractor fix |
| SPK-s | `style-engine` A/B: Pigment 0.0.30 with MUI 9.0.1 vs AOT on the pilot parts: load and hydration script ms, heap, bytes, N0-N3 | MUI 9.0.1 builds with Pigment 0.0.30 and 0.0.31; 0 insertions seen in Chrome only [09.01 §2.2]; WebKit at runtime INFERRED [09.04]; M2, 1 agent-day, optional (Q21) |
| SPK-t | With the sandbox on: can worktree agents build, test and commit with zero refusals, while writes to `.fw-console/` fail from every agent? Checks (a)-(g) below the table | partial: (f), (g) unit-tested; no sandbox block yet |
| SPK-u | Hermetic dependency recording: can a measurement plugin's run record the files and env it actually read (e.g. `fs` tracing in Node, `sandbox-exec` read logs), so that "declared deps ⊇ actual reads" is checked for artifact keys? | open; M1, with the artifact store |

**SPK-r details.** It also checks the §6.5 cache wiring (own `mui` cache, no `StyledEngineProvider`,
`createEmotionServer` compat), the census with `disablePortal` overlays, and the `runtime` variant as the negative
control (N0/N5 must flag it). It records trace `UpdateLayoutTree` ms for `aot` vs `runtime` (ABBA, n ≥ 4): in the
[09.04] spike a build with 0 scroll insertions still showed 13-15 ms against Pigment's 8-10 ms per scroll phase,
while CDP `RecalcStyleDuration` showed no gap (2 runs, unexplained). The Chromium half ran on Mac Chrome 155 headless,
430×932, 3 runs, no variance (`apps/site/README.md`).

**SPK-t checks.** Sandbox settings: `allowUnsandboxedCommands: false`, `allowUnixSockets` = the CLI socket,
`denyWrite` = `.fw-console`. (a) A named worktree subagent runs `pnpm fw gate`, the tests and `git commit` with zero
refusals (with SPK-o); (b) appending to `events.jsonl` from that agent fails; (c) Edit/Write there are denied;
(d) `pnpm fw screen` reaches the socket; (e) the deny paths resolve to the main checkout's `.fw-console/` from a
worktree, and a commit put on `main` outside `fw land` shows as a violation within one reconcile pass; (f) the
capability hook adds `--cap`, and console-api refuses a missing, wrong or reused capability; (g) `emit.mjs` finishes
in < 100 ms and prints nothing.

## Appendix C. Draft for the Q17 decision record (agent-team operation and helper tools)

The lead finalises after the spikes: permission mode `default` with the lane allow list (§8.3), not `acceptEdits` or
`auto` (v1's auto mode refused 211 calls [08]); `CronCreate` and Fable behind `ask`; the lead on Opus `medium`, 200k
cap; in-process teammates; pnpm workspaces, `typescript@6.0.3`; Serena with `rename_symbol` behind `ask`; lean-lsp-mcp
with remote search off; chrome-devtools-mcp for exploration only (`--isolated --no-usage-statistics`).

## Appendix D. Review log

### Revision 7 delta (catch-up to d41aef0; rev 6 was a48aa54)

Source: the catch-up log `[CU]` from its rev-6 entry on, and the notes it cites; each claim checked against its
commit or note. Status words as in §0.

| # | Change | Where | Source |
|---|---|---|---|
| 1 | Measure on CI, not on this Mac; trigger scope (21 of 28 runs touched no input; 248 of 414 job-minutes wasted) | §4.1, §5.4, §8.4, §12.0, R30, R33, A28 | 417d90d, 6723de2 |
| 2 | SPK-i decided: stable types as totals with margin 2t; worst class over ≥ 3 CI runs; pixel-area bound re-classes the CI runs to 33/22/7, 31/23/8, 27/27/8; stale 28/14/8 removed | §1.2, §4.2, §10.2, App B, A25 | 6b4237e, 5879861, 13b6c98 |
| 3 | Touch wedge fixed by a flag (MEASURED locally, 21 runs; CI check `touch-ci-verify`); class drift between CI runs | §4.2 | 25bd9f4 |
| 4 | WKTR from WebKit's prebuilt iOS-simulator products on GitHub macos-26; the cloud Mac a fallback; Q10 and R13 updated | §4.2, §10.1, §12.2, A26 | 591a815 |
| 5 | Your answers: Q1 sessions on demand, free-play phone; Q31 yes after liveness feed, clean day and A/B bench; Q33 a Simulator or device check for both, `unreachable` state | §6.6, §8.3, §10.2, §12.0, A27 | the task, `gate-gaps-*` notes |
| 6 | Q34 (`cssVariables`) and Q35 (inert dead CSS) stated as open, with recommendations | §6.1, §6.5, §10.2 M2, §12.1 | `10-17-css-decisions.md` |
| 7 | Gate verdict, work graph, obs health, identity and console ops now in `fwcore`; console TS stand-ins gone; `Task:` trailers; `fw watch`; scrub hook; `pkill`/`killall` denied | §3.2-§3.4, §5.1, §7.3, §8.3, §8.5, R27-R32 | 0d02aff, e920459, 0877f7a, dec2d82, d2574b0, b205acc, acc5d83, af618a6 |
| 8 | Team changes from the Fable review; SPK-c answered (forks carry no role); slow-work watch; mutants 0 of 625 survived; math review r6, r7a | §5.3, §8.1, §8.2, §8.5, App B | 3b861ab, 98526a5, 2e0d21b, 8074907, e6908db, ff55f4e |
| 9 | Contradiction resolved: rev 6's "M1: all used types deterministic" gives way to the SPK-i decision | §10.2, A25 | 6b4237e |
| 10 | Dense tables split (Fable review): no cell over ~40 words; §5.3, §8.5 and the rev 6 log became lists or text | §1.2, §3.2, §5.3, §6.5-§6.7, §8.5, §9.2, §11, App B, App D | 98526a5 |

Not taken: the open work-graph tasks and the live status stay in the console, not the plan. Some landed tasks lack
evidence links in the work graph (`plan-evidence-link`).

**Length, and which rule wins.** The file has about 1,620 lines (rev 6: 1,463) but about 27,400 words (rev 6:
28,500). The two rules for this revision pull apart: splitting dense table cells into lists (the Fable review) adds
lines, while the ~1,300-line target counts lines. The plan follows the split, because a cell of 80-120 words was the
readability problem, and cuts words instead. The next cut: move the §4.2 findings and §6.6 details into their notes.

### Revision 6 (catch-up to e4d9853; item tables in git history: a48aa54)

Revision 6 made the repo public (MIT, snapshot tracked), added public CI, the token policy and helper roles, the
cache-TTL rule (lead 1h, agents 5m), spawn-guard in shadow mode, the console M0 core (`Fw/Serve`, `fw land`, the git
reconciler), the parallel-work study and `Fw/Sched`, per-type count classes (A24), the first breakpoint-gate
results, the roadmap's "Landed" column and the kill-own-PIDs rule. Two reviewers (facts and consistency) raised 15
findings; all were checked against the repo and applied, 4 in part, with reasons in that revision.

### Revisions 2 to 5 (item tables in git history: 032ed71, 931aa35, c04c8ef)

Revision 5 (your requirements: automated console, Lean-first, math view) applied [10] from `docs/plan/rev5-delta.md`
after a verification pass that fixed 4 design faults and 8 math-translation errors; it added the event-log console,
the L1-L3 inventory, the math view, the device answers [ENV], breakpoints for every part [11], the dependency-graph
roadmap and Q22-Q30. Revision 4 (your four decisions, [09]): MUI everywhere with Emotion AOT, S1-S13, N0-N5, V-q,
`impl: plain` twins, K10. Revision 3 applied the 18 improvements of [08]; revision 2 the 34 items of [FR].
