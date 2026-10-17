---
title: Plan evidence and history moved out of PLAN.md (revision 8 length cut)
date: 2026-10-17
status: CONFIRMED
---

# Plan evidence and history (moved out of PLAN.md in revision 8)

PLAN revision 8 (task `plan-cut`) moved evidence, history and long worked examples here so the plan stays readable.
The plan keeps every decision, open question, rule and risk, plus a one-line summary that links to a section of this
note as `[EV §n]`. Every block below is copied verbatim from PLAN revision 7.1 (cdcb907): each claim keeps its own
status tag (CONFIRMED, INFERRED, MEASURED) and citation. Section references inside the moved text (§x.y, A-, Q-, R-
and V- ids, App B, App D) point to `docs/plan/PLAN.md`; citation keys such as [01], [08], [FR], [CU] and [ENV] are
defined in the plan's introduction. The state these blocks describe is the one of 7d564e2 (or the commit they name).

## 1. Revision highlights (revisions 4 to 7.1)

### Revision history from the introduction

*Moved from PLAN the introduction in revision 8; text unchanged (PLAN rev 7.1, cdcb907, lines 54-60).*

why. Appendix D logs every change. **Revisions 4-5 apply your decisions and requirements of 2026-10-17 (§12.0).
Revision 6 caught up with the public repo, CI and the console core. Revision 7 catches up with 65 more commits (the
catch-up log `[CU]`, `docs/team/improvements/2026-10-17.md`): measuring moves to CI, SPK-i is decided, WKTR is planned
without a cloud Mac, and you answered Q1, Q31 and Q33. Revision 7.1 applies the 15 findings of the rev 7 review and adds the
frozen Chromium class table, the freeze rule in Lean, the rewrite on the Chromium CI lane and math review round 8.**
Open for you: Q32, the two M2 CSS questions (§12.1), and whether the WKTR route the lead read for you stands (Q10,
§12.2). Work runs as a dependency graph, not a calendar (§10).

### Since revision 6 and since revision 7

*Moved from PLAN §0 in revision 8; text unchanged (PLAN rev 7.1, cdcb907, lines 126-146).*

**Since revision 6 (rev 7, [CU]).**
- **Measure on CI, not on this Mac** (your direction, 417d90d): Chromium counts, WebKit Simulator counts, the
  breakpoint gate and WKTR run on GitHub Actions; this Mac keeps only phone sessions and short debug runs (§4.1, §5.4).
- **SPK-i decided** (6b4237e): screening uses deterministic types, plus stable types as totals only; a signed class is
  the worst over at least 3 CI runs; pixel-area types get a relative bound (§1.2 V-i, §4.2).
- **WKTR without a cloud Mac:** WebKit's own prebuilt iOS-simulator products are planned to run on GitHub `macos-26`
  (INFERRED until `wktr-local` runs; §4.2, Q10).
- **Your answers:** phone sessions on demand (Q1), spawn-guard blocking after three conditions (Q31), and a
  Simulator or device check for the unreachable gate cells (Q33), which led to a new `unreachable` cell state (§6.6).
- **Lean took over the last console TS stand-ins**, the gate verdict, the work graph and a team health watch (§5.1).

**Since revision 7 (rev 7.1).**
- **Chromium classes signed on CI** (da287ff): worst class over 3 workflow runs on one pinned image: swipe-v1
  27/25/10, swipe-touch-v1 16/27/19 (deterministic/stable/quarantined); the touch fix held, 0 wedges in 9 CI jobs
  (MEASURED). The freeze rule now runs in Lean (`measure.freeze`, bc2e28a); the table it regenerates is unchanged.
- **The rewrite runs on the Chromium CI lane** next to the original, one VM per run (fee88b2): the rewrite has far
  fewer stable or quarantined types (it also reports 44 types against 62, so not like for like; §4.2, MEASURED).
- **Done since rev 7:** `touch-ci-verify`, `class-freeze`, `store-and-run`, `gate-unreachable`, `freeze-lean`,
  `rewrite-ci-lane`, math review round 8 (453 of 502 agree; the 49 fixes are `math-r8-fix`).
- **The review's corrections:** WKTR on CI is a plan, not a result; the Simulator lane runs on `xcode-27`; Chromium
  paint is quarantined, so it is not screened (§1.2, §4.1, §4.2).

## 2. Keep and drop, with the v1 evidence

*Moved from PLAN §2.1 and §2.2 in revision 8; text unchanged (PLAN rev 7.1, cdcb907, lines 213-249).*

#### 2.1 Keep (each with its v2 form)

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

#### 2.2 Drop (each with what replaces it)

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

## 3. Measurement evidence

### 3.1 Measure on CI: the figures

*Moved from PLAN §4.1 in revision 8; text unchanged (PLAN rev 7.1, cdcb907, lines 404-412).*

**Measure on CI, not on this Mac** (your direction, 417d90d; `CLAUDE.md`). Chromium counts, WebKit Simulator counts,
the breakpoint gate and WKTR run on GitHub Actions: an agent pushes its `ci/<task>` branch and reads the result with
`gh run view` / `gh run download`. Chromium runs in the container on `ubuntu-24.04-arm`; WebKit Simulator counts on
the `xcode-27` image (iOS 27.0, 24A434; `webkit-sim.yml`); WKTR is planned for `macos-26` (iOS 26.5). This Mac
measures only (a) the phone in a session you booked, (b) one short debug run (≤ 5 min) while harness code changes,
(c) a lane CI cannot run yet, named in the work graph with the reason. A local run is never a result. Each workflow has a `paths:` filter and cancels stale runs on `ci/**` only, because 21 of 28 runs touched
no input and 248 of 414 job-minutes were wasted (MEASURED, 6723de2; `10-17-ci-trigger-scope.md`). macOS jobs share
one pool: 5 concurrent macOS jobs (the cap for Free, Pro and Team; our tier INFERRED), shared by `xcode-27` and
`macos-26` and filled by our own jobs (MEASURED, 56fe6c9; `10-17-macos-queue.md`; budget in R33).

### 3.2 The harness as built (flags and sources)

*Moved from PLAN §4.2 in revision 8; text unchanged (PLAN rev 7.1, cdcb907, lines 422-445).*

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

### 3.3 What the count runs showed (all findings)

*Moved from PLAN §4.2 in revision 8; text unchanged (PLAN rev 7.1, cdcb907, lines 447-469).*

**What the runs showed.** Classes and their use are the V-i rules (§1.2). The first rows were local debug runs, made
before the measure-on-CI rule; the class counts that matter are the CI rows.

| Finding | Engine | Status, source |
|---|---|---|
| Whole count files are never byte-identical (thread ids, GC, async); deterministic types held under heavy host load | Chromium | MEASURED, 70c3370 (local debug) and CI run 39029423874 |
| Local runs (rev 6): 28 deterministic, 14 stable, 8 quarantined of 50 types; superseded by the CI rows below | Chromium | MEASURED locally (debug), ddc91b2 |
| The rewrite under `scrollTo`: all 43 types deterministic except MinorGC (the CI rewrite rows are below) | Chromium | MEASURED locally (debug), 70c3370 |
| A 10 ms barrier floor (`FW_BARRIER_MIN_MS`) cuts a rewrite run from 45 s to 7 s with identical classes | Chromium | MEASURED locally (debug), 70c3370 |
| CI, 3 workflow runs of 3 runs each (det/stable/quar): 33/20/9, 31/21/10, 27/25/10; with the pixel-area bound 33/22/7, 31/23/8, 27/27/8 | Chromium | MEASURED, runs 39029423874, 39031884554, 39033771018; 13b6c98, 5879861 |
| Classes drift between runs of the same code: 6 types det → stable, `trace.Paint` stable → quarantined; cause runner noise or an unpinned image, so `class-freeze` pinned the image and signed the worst of 3 runs | Chromium | drift MEASURED, cause INFERRED; `spk-i.md` |
| **Frozen table** (worst class over 3 workflow runs of 3 jobs, one pinned image, 62 types): swipe-v1 27/25/10, swipe-touch-v1 16/27/19. `trace.Paint` is quarantined in both, `trace.RasterTask` under touch. The pooled class over all 9 files is stricter and kept for reference only | Chromium | MEASURED, runs 39038861283, 39038967198, 39038970307 (swipe) and 39038973297, 39038976656, 39038979125 (touch); da287ff |
| The freeze rule runs in Lean (`measure.freeze`: order-independent, monotone, idempotent; refuses fewer than 3 runs, a repeated run, a missing or mixed image); `freeze.mjs` regenerates `classes.frozen.json` with identical class data | Chromium | CONFIRMED (proofs in `Fw/Measure/Freeze.lean`; `freeze.mjs --check` reports identical), bc2e28a |
| `census.activeTileAreaPx` and `census.drawingAreaPx` leave quarantine under the pixel bound (largest gap 382 ppm) | Chromium | MEASURED, 5879861 |
| Touch wedged BeginFrame (5 of 5 at one frame): `WaitForLateScrollEvents` set a timer at virtual frame time, ~4,900 s ahead of the container clock. With the feature off: **0 wedges in 9 CI jobs**, all on attempt 1. Locally (debug, cause found): exactly 1 wedge in 21 runs, passed on retry | Chromium | MEASURED, runs 39038973297, 39038976656, 39038979125; da287ff (fix 25bd9f4) |
| **Original vs rewrite on CI** (one VM per run; same image, profile, flags and host), det/stable/quar per workflow run of 3: swipe-v1 original 27/25/10 and 30/22/10, rewrite 37/6/1 and 37/7/0; swipe-touch-v1 original 31/20/11, rewrite 40/0/4 (quarantined: EventDispatch, FunctionCall, HitTest, PrePaint). The original reports 62 types and the rewrite 44, so the tallies are not like for like; the rewrite has no frozen table yet | Chromium | MEASURED, runs 39039958580, 39040442530, 39040473427; fee88b2 |
| `HitTest` stays quarantined (touchmove lands in frame k or k+1; also on CI, two trajectories differing in one frame) | Chromium | MEASURED, 25bd9f4, da287ff |
| Per-step Layout, Paint, InvalidateLayout, ObserverCallback quarantined; RecalculateStyles within 1; totals within 3-5 % | WebKit | MEASURED locally (debug), 367fec2 |
| The first load after a Simulator boot differs (FireAnimationFrame 703-709 vs 729-739), so `--warmup 1` is the default and the Simulator stays booted | WebKit | MEASURED locally (debug), 367fec2 |
| `RenderingFrame` reads 0 on iOS 27.0 (24A434) and ~60/s on 26.5; to compare on the CI `xcode-27` image | WebKit | MEASURED locally (debug), 367fec2 |
| Host load correlated with counts but was confounded with pass order; a quiet rerun was clean (not the cause) | WebKit | INFERRED, 367fec2 |
| The rewrite's hit-skip cuts RecalculateStyles 164 → 19, but its steps do not align with the original's (74 vs 107): no Δ yet (task `step-align`) | WebKit | MEASURED locally (debug), 367fec2 |
| CI Simulator runs take 10-38 min and fail at warm-up; task `sim-speed` | WebKit | MEASURED, [CU] sim-speed entry (`docs/team/improvements/2026-10-17.md`) |

### 3.4 WebKit element counts and WKTR

*Moved from PLAN §4.2 in revision 8; text unchanged (PLAN rev 7.1, cdcb907, lines 494-508).*

**WebKit element counts (decided now, Q10).** WebKit's largest model term is the restyled-element count, and Phase A
does not have it; v1's WebKit costs were dominated by restyle (custom-property restyle 2.2×, presence-flip layouts;
v1 `research/cpu-throttle-calibration/README.md` l.39). So, from M1:
- until a WKTR count exists, the WebKit model is at most `ranks-only` for style-affecting changes, and **class W is
  barred for any diff that touches selectors, classes or custom properties**;
- **WKTR without a build** (rev 7; `10-17-wktr-on-github-actions.md`). WebKit's public build archive holds the
  iOS-Simulator WebKitTestRunner with `internals` (315 MB, CONFIRMED). It is built with Xcode 26.5 against the iOS
  26.5 Simulator SDK, which matches this Mac and the GitHub `macos-26` image (MEASURED, 591a815); that it runs there
  is INFERRED until `wktr-local` (nothing has run end to end; webkitpy's SDK choice and CI disk are unchecked). No
  WebKit build, no rented Mac, ~3 GB disk. Order: `wktr-local`
  (one debug run) → `wktr-ci-lane` → `calibration`; `wktr-readme-fix` corrects the old "needs a cloud Mac" text. It
  no longer waits for M3 and can start now. The rented cloud Mac (`wktr-cloud`) is a fallback only.
- **Version caveat.** The archive build is pinned WebKit trunk (324039@main), not the WebKit in shipped iOS 27.0, so
  WKTR counts carry that version note and are ranked against the Simulator and the phone in calibration (INFERRED:
  close enough for element counts; checked there).

## 4. Lean modules built by 7d564e2

*Moved from PLAN §5.1 in revision 8; text unchanged (PLAN rev 7.1, cdcb907, lines 620-639).*

**Built by 7d564e2** (the dependency graph ran ahead of the milestone order):
- `Fw/{Board, Console, Serve, Wire}`; `Fw/Spec` (10 modules); `Fw/Site` (4); `Fw/Parts` (5); `Fw/Sched` (100
  theorems, 4bd850f; in `fwcore` as `ops.admit`, `metrics.*`, 49b7ff4).
- `Fw/Measure`: classes, tolerances, zones, WebKit reduction (ddc91b2); `measure.selfCheck` and `snapshotCounts`
  (baa3291); the pixel-area bound with `classifyU_*` proofs (5879861); the class freeze rule `measure.freeze`
  (`Fw/Measure/Freeze`, bc2e28a).
- `Fw/Gate/{Rule, Compare, Items, State}`: the breakpoint-gate verdict, 51 theorems; `verdict.mjs` now calls
  `fwcore` (0d02aff). `Fw/Gate/Reach` and the `unreachable` cell state, op `gate.reach` (`gate-unreachable`,
  3a8c263).
- `Fw/Store/{Layout, Reduce}` (layout, run plan and reduction proved; `store.*` ops) behind the artifact store and `fw run` (`store-and-run`,
  da3632e); `Fw/Console/Alert` (`alert-steps`, c92c310).
- `Fw/Plan/{Core, Graph, Trailer}`: the work graph (derived state, acyclicity, critical path, parallel-safe groups;
  0de2fec) and `Task:` trailers (acc5d83).
- `Fw/Obs/Health`: 5 agent states and 14 alert codes behind `fw watch` (0877f7a); `Fw/Ops/{Identity, Obs}` (dec2d82,
  acc5d83).
- **Mutants (V-r) for M0:** 625 mutants, 621 killed, 1 stillborn, 3 equivalent, 0 survived (MEASURED 8074907); the
  killers run in `lake test` (c67cbe4). Later runs move to CI (`mutants-ci`).

Not built yet: `ops.gate`, the lease and the M3 model modules. `fw run` reports a non-default `preset`/`fw` as
BLOCKED until the Lean `workflowInputs` for chromium list them (in task `math-r8-fix`).

## 5. Math review

### 5.1 Review rounds r4 to r8

*Moved from PLAN §5.3 in revision 8; text unchanged (PLAN rev 7.1, cdcb907, lines 709-722).*

**Review rounds so far (MEASURED).** No round found a wrong proof; every disagreement was a docstring fix.

| Round | Commit | Declarations | Agree | Disagree, and the fix |
|---|---|---|---|---|
| r4 | 226c35b | 258 | 187 | 71 (00c09bf, which added a free-variable lint) |
| r5 | 28b18ee | 490 | 428 | 62 (69d7773) |
| r6 | e6908db | 62 re-reviewed | 61 | 1, `Admit.Inv` (77b381c) |
| r7a | ff55f4e | 234 | 214 | 20 (acc5d83, 5879861) |
| r8 (planned as 7b) | fee88b2 | 502 | 453 | 49, being fixed in task `math-r8-fix` (7d564e2) |

Round 8 finished round 7 (`Fw.Obs`, `Fw.Console`, `Fw.Gate`, `Fw.Site`, `Fw.Store`, `Fw.Plan`; task `math-r7`, done).
Its 49 disagreements show docstring patterns (shadowed names, free variables, "at or above" where the Lean is
strict; CONFIRMED, round 8 record); `math-r8-fix` is the M0 exit item now. The page at 7d564e2 reads 1,806 agree, 49 disagree, 14 stale and 78
pending of 1,947 declarations (MEASURED, math view).

### 5.2 The full worked example

*Moved from PLAN §5.3 in revision 8; text unchanged (PLAN rev 7.1, cdcb907, lines 724-743).*

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

## 6. MUI runtime details (S7) and census ids

*Moved from PLAN §6.5 in revision 8; text unchanged (PLAN rev 7.1, cdcb907, lines 893-904).*

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

## 7. Breakpoint gate evidence

### 7.1 The load matrix

*Moved from PLAN §6.6 in revision 8; text unchanged (PLAN rev 7.1, cdcb907, lines 955-963).*

**Breakpoint gate**, required before **any** part is promoted (`faithful-with-delta` never waives it): PL0-PL3,
original vs rewrite with a per-config A/A, in Chromium and Playwright WebKit, **124 loads per engine** (INFERRED
arithmetic [11 §4]): the 15 width pairs as desktop, desktop reduced-motion and touch (90), touch reduced (10), phone
landscape (2), the device-width arm alone (6), the hover × pointer cross (4), dark (2), the fractional gaps (4) and
height probes (6); plus one width inside each continuous band (clamp knees), and **live-resize sweeps** compared with
the original after the same sequence (1512 → 320 → 1512 across every edge, 430×932 ↔ 932×430, touch 1024 ↔ 1201,
v1's 1440 → 600 → 1440 pain sequence, live reduced-motion and touch flips). **Per PR**, the core matrix (430×932 and
430×775/815 at DPR 3 with touch; 375×667 and 1440×900 at DPR 2; reduced motion) is the fast subset; one Simulator
check closes promotion, because Playwright WebKit has no toolbar and no Conservative compositing policy [02 §7].

### 7.2 Gate status at d41aef0

*Moved from PLAN §6.6 in revision 8; text unchanged (PLAN rev 7.1, cdcb907, lines 965-974).*

**Gate status at d41aef0 (MEASURED, e7fb102, d23cf7c, 0d02aff).** 124 loads × 2 engines (headless Chromium,
Playwright WebKit) × 2 arms plus 4 sweeps, byte-identical across two runs.

| Item | Result |
|---|---|
| Pilot parts | all 4 pass all 14 cells in both engines (after fixes 95693f4, 2566949) |
| Covered | PL0, PL1, PL2 and the `matchMedia` truth |
| Not covered yet | PL2b, PL3 pixels, the Simulator check, live reduced-motion and touch flips |
| Verdict | in Lean: `Fw.Gate.{Rule, Compare, Items, State}`, 51 theorems; `verdict.mjs` calls `fwcore` (0d02aff) |
| Speed | a full run takes 554 s; `--parts` saves no time until each part declares its probe scope (`gate-probe-scope`); CI runs 8 shards in about 5 min |

### 7.3 The cells no engine could reach

*Moved from PLAN §6.6 in revision 8; text unchanged (PLAN rev 7.1, cdcb907, lines 976-989).*

**The cells no engine could reach (Q33, answered: "Simulator or device check for both").** Two research notes
(`10-17-gate-gaps-fractional.md`, `10-17-gate-gaps-hover-pointer.md`) split the answer by engine:

| Cells | Chromium | WebKit (Simulator and iPhone) |
|---|---|---|
| Fractional gaps (600.5, 640.5, 860.5, 1000.5) | reachable: browser zoom 200 % with override width 2N+1 gives media width N + ½ (MEASURED) | **unreachable**: the media width is an integer by type (CONFIRMED in source, MEASURED) |
| Hover × pointer cross (4 cells) | reachable through `--blink-settings`; passes | **unreachable**: every Apple WebKit derives primary hover and pointer from one constant (`WebPageIOS.mm` l.4233-4246, `WebPageMac.mm` l.762-780, CONFIRMED) |

So the gate gets a new cell state, **`unreachable`** (the engine cannot produce this environment; distinct from
not-comparable). Order, Lean first: `gate-unreachable` (done, 3a8c263: `Verdict.unreachable`, `Fw.Gate.Reach` with
the Apple and GLib WebKit primary pairs, op `gate.reach`; the fractional probe moved from DPR 5/4, which no browser
produces, to DPR 2 with a realizability theorem) → `gap-harness` (the Simulator check
against Lean's expected values; its review found it used the retired TS verdict and a wrong touch-arm check) →
`gap-device` (a 2-load probe page in one booked phone session, confirming the iOS 27.0.1 build matches the source).

## 8. Agent team

### 8.1 Verified mechanics, full wording

*Moved from PLAN §8.1 in revision 8; text unchanged (PLAN rev 7.1, cdcb907, lines 1104-1127).*

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

### 8.2 Helpers, cache TTL, Fable review and commits, as in revision 7.1

*Moved from PLAN §8.2 in revision 8; text unchanged (PLAN rev 7.1, cdcb907, lines 1156-1178).*

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

### 8.3 Coordination rules with their v1 evidence

*Moved from PLAN §8.5 in revision 8; text unchanged (PLAN rev 7.1, cdcb907, lines 1236-1273).*

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

## 9. Workstreams with landed commits (at 7d564e2)

*Moved from PLAN §10.1 in revision 8; text unchanged (PLAN rev 7.1, cdcb907, lines 1343-1369).*

This table holds no status: the live state is in the console. "Landed" lists commits on `main` (checked at
7d564e2); "Left" names the open work-graph tasks. Task-level dependencies live in `docs/team/work-graph.json`, which
`fwcore` now reads (`Fw/Plan`; `fw plan sync/show`; the console Plan tab, e920459, with evidence links, 630110e).
A task id is also the agent name and the card id.

| Workstream (where) | Blocked by | Landed | Left (task ids), and what it unblocks |
|---|---|---|---|
| **lean-core** (`lean/`) | — | 9367dea, 14152f1 (`Fw/Serve`), 30e3264 (`Fw/Ops`), 8074907 (M0 mutants), c67cbe4 | `math-r8-fix`; `math:sign` and `math.lock.json`; `mutants-ci` → M0 |
| **console** (`apps/console-*`, `apps/runner`, `packages/contracts`) | lean-core | 8bec088, 3fe1876, eacb660, 840f7d6 (`fw land`), e920459 (Plan tab), af618a6 (`--task`), acc5d83 (last TS stand-ins), 6228fcf, c92c310 (`alert-steps`) | the step queue before any device step; `watch-web` → M0 |
| **agent-ops** (`.claude/`, hooks, `scripts/`) | console | 6756bb9, a0b9053, 124a614, d2574b0 (scrub), 618c1b6, dec2d82, 0877f7a (`fw watch`), b205acc, 1a4a062 (`watch-fix`) | sandbox (SPK-t); `spawn-enforce` (Q31); `watch-slow`; `spk-p-wake`; `session-brief` → M0 |
| **counts-chromium** (`packages/measure-chromium`) | the snapshot | e01f9e5, 70c3370, 13b6c98 (SPK-i), 25bd9f4 (touch fix), 5879861, da287ff (`touch-ci-verify`, `class-freeze`), fee88b2 (`rewrite-ci-lane`) | `hittest`, `spk-q`, `zone-baselines-chromium`; a frozen table for the rewrite → M1 |
| **counts-webkit** (`packages/measure-webkit`) | — | 1d6c88c, 367fec2 | `sim-speed`, `webkit-quiet`, `step-align`, `webkit-table-regen`, `zone-baselines-webkit` → M1 |
| **lean-measure** (`lean/Fw/Measure/`) | counts lanes | ddc91b2, baa3291, bc2e28a (`freeze-lean`) | — (classes, tolerances, zones, self-check, freeze in `fwcore`) |
| **store-and-run** (`packages/contracts`, `apps/runner`) | lean-measure | da3632e (`store-and-run`: artifact store, `fw run`) | `vj-vt` (V-j, V-t) → M1 |
| **CI** (`.github/workflows/`) | publishing | d70619d, ee18c6b, 67192ef, 6723de2 (trigger scope) | `ci-webkit`, `fw-ci` (a remote check on every `ci/*` push) → M1 |
| **WKTR** (`packages/measure-webkit`, CI) | CI | 591a815 (research) | `wktr-local` → `wktr-ci-lane`; `wktr-readme-fix`; `wktr-cloud` only as fallback → calibration |
| **site-aot** (`apps/site`) | — | d380999 | SPK-r in WebKit; `css-decide` (Q34, Q35) → port parts |
| **breakpoints and lean-site** | the snapshot | a3e1e9c, ee04fc4, 8bd00aa | — → breakpoint gate |
| **breakpoint gate** (`packages/gate-breakpoints`) | lean-site, pilot parts | e7fb102, 95693f4, d23cf7c, 0d02aff (verdict in Lean), 3a8c263 (`gate-unreachable`) | `gap-harness` → `gap-device`; `gate-probe-scope`; `ops-gate`; PL2b, PL3, live flips → M2 |
| **lean-parts and pilot parts** (`engine.scroll`, `nav.hitTest`, `hero.*`) | site-aot, M1 baselines | 4d179c3, a2e1ced, 30c814b, 50e5cd1, 88a4302, 4421679, 2566949 | `faithful-checks` (PL3-PL6, N0-N5), then `bands-freeze` → M2 |
| **parallel work** (`lean/Fw/Sched/`) | `Fw/Ops` | 5b8a2b1, 4bd850f, 7d22517, c0bf898, 49b7ff4 | `ab-bench` (Q32) → admission in console-api, `spawn-enforce` |
| **math review** | each Lean module | r4-r8 (§5.3; `math-r7` done, 7d564e2) | `math-r8-fix` → M0 |
| **explainer and plan** (`docs/plan/`) | this plan | rev 7 (9ffa4fe), rev 7.1 (`plan-rev7-1`) | — |
| **lean-m1+** (`lean/`) | lean-core | — | the M1-M3 Lean modules of §5.1, each when its consumer needs it |
| **rule cards** (`refs/rules/**`) | counts lanes | — | v1's 16 WebKit rules, Chromium's `compositeFailed` reasons, K1-K10 drafts → calibration |
| **calibration** (fixtures, phone) | WebKit counts, WKTR, phone sessions | — | `phone-session-1`, `calibration`: K1-K10, `ρ_page`, holdouts, validity table v0 → M3 |
| **port parts**, **experiments**, **write-up** | M2; M4; M5 | — | `port-parts` → M4; `experiments` → M5; `write-up` → M6 |

## 10. Superseded text

*Moved from PLAN §10.2 in revision 8; text unchanged (PLAN rev 7.1, cdcb907, lines 1410-1412).*

The plan follows the SPK-i decision (A25). Revision 8 also moved the critical path's list of later-tier tools into the §3.4 table, where it already stood.

**Contradiction resolved (rev 7).** The rev-6 M1 row asked for "all used count types deterministic", while the SPK-i
decision lets stable types in as totals with margin 2t. The plan follows the decision, because "deterministic only"
would drop trace.Layout, trace.RasterTask and LayoutCount (§1.2, V-i rules); trace.Paint is quarantined either way.

## 11. Spikes at d41aef0 (full table and details)

*Moved from PLAN Appendix B in revision 8; text unchanged (PLAN rev 7.1, cdcb907, lines 1570-1609).*

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

## 12. Review-log item tables of revisions 7.1 and 7

*Moved from PLAN Appendix D in revision 8; text unchanged (PLAN rev 7.1, cdcb907, lines 1620-1682).*

#### Revision 7.1 delta (catch-up to 7d564e2; rev 7 was 9ffa4fe)

Source: the adversarial review of rev 7 (`research/notes/2026/10-17-plan-rev7-review.md`, 15 findings, fix-needed)
and the commits after rev 7. Each finding was checked against the files it cites before the text changed; all 15
were applied (rows 1-15, numbered as in the review). Rows 16-19 add the work that landed after rev 7.

| # | Change | Where | Source |
|---|---|---|---|
| 1 | WKTR: built against the iOS 26.5 SDK (MEASURED); that it runs on `macos-26` is INFERRED until `wktr-local` | §0, §4.2, §12.2 Q10, A26, App D rev 7 row 4 | 591a815, `wktr-ci.md` handoff |
| 2 | "Deterministic only" rationale no longer names trace.Paint: it is quarantined in the frozen table, so Chromium paint is not screened | §1.2, §10.2, A25 | `classes.frozen.json` |
| 3 | WebKit Simulator lane on `xcode-27` (iOS 27.0, 24A434), WKTR planned on `macos-26` | §4.1, §4.6 | `webkit-sim.yml` l.61, [CU] |
| 4 | Frozen class table, touch result on CI, macOS queue causes; `touch-ci-verify`, `class-freeze`, `store-and-run`, `gate-unreachable` marked done | §0, §4.2, §5.1, §6.6, §10.1, §10.2, R33 | da287ff, da3632e, 3a8c263, 56fe6c9 |
| 5 | Local touch runs: exactly 1 wedge in 21 (passed on retry), next to the CI result | §4.2, explainer | `touch-wedge.md` handoff |
| 6 | WKTR route is the lead's reading of an unanswered card, not your decision: moved from §12.0 to the §12.2 default Q10, open to your override | §0, §12.0, §12.2, A26 | [CU] seq 22 |
| 7 | "Fast and deterministic" Chromium lane → counts classed per type | §0 | V-i |
| 8 | Touch fix reported with the CI runs, not the local runs | §4.2, App D rev 7 row 3 | da287ff |
| 9 | Source of "10-38 min, fail at warm-up" → [CU] sim-speed entry, MEASURED | §4.2, R33 | [CU] |
| 10 | 5-slot macOS cap: our tier INFERRED; shared by both labels, filled by our jobs (MEASURED) | §4.1, R33 | 56fe6c9 |
| 11 | Source of your answers → [CU] console answers seq 22 | App D rev 7 row 5 | [CU] |
| 12 | Rev 7 row 2 says 28/14/8 was "marked superseded", which is what §4.2 does | App D rev 7 row 2 | — |
| 13 | §4.2 findings carry a status column with CI run ids | §4.2 | `spk-i.md`, README |
| 14 | Q35 lists options a, b, c | §12.1 | `10-17-css-decisions.md` |
| 15 | One Lean size in plan and explainer: 1,947 declarations, 910 theorems, 51 modules (MEASURED, math view at 7d564e2) | §0, explainer | math view |
| 16 | The freeze rule in Lean (`measure.freeze`, proofs of order independence, monotonicity, idempotence); `classes.frozen.json` regenerated by `fwcore`, class data unchanged | §1.2, §4.2, §5.1, §10.1 | bc2e28a |
| 17 | The rewrite on the Chromium CI lane: original vs rewrite classes per workflow run (MEASURED) | §0, §4.2, §10.1 | fee88b2 |
| 18 | Math review round 8: 453 of 502 agree; 49 to fix in `math-r8-fix`, the new M0 exit item | §5.3, §10.1, §10.2 | 7d564e2 |
| 19 | Also landed and marked: `alert-steps`, `watch-fix` | §5.1, §10.1 | c92c310, 1a4a062 |

**Which way the plan goes.** Finding 6 offered two fixes; the plan moves the WKTR row to §12.2, because that section
already holds defaults you can override and Q10 already covered WKTR. Finding 15 named 1,898 declarations in 50
modules; the math view was regenerated since, so the plan uses its current figure. The task brief said "68 modules":
that is the number of `.lean` files under `lean/Fw` plus `Fw.lean`, while the math view groups declarations into 51
modules; the plan uses the math view's count so plan and page agree. The rewrite's tallies are per workflow run, not
frozen, and cover 44 types against the original's 62, so they are reported, not compared as a signed result.

**Length.** About 1,700 lines (rev 7: about 1,620). This revision was told not to cut, so the ~1,300-line target is
still open; the next cut stays as rev 7 named it: move the §4.2 findings and the §6.6 details into their notes.

#### Revision 7 delta (catch-up to d41aef0; rev 6 was a48aa54)

Source: the catch-up log `[CU]` from its rev-6 entry on, and the notes it cites; each claim checked against its
commit or note. Status words as in §0.

| # | Change | Where | Source |
|---|---|---|---|
| 1 | Measure on CI, not on this Mac; trigger scope (21 of 28 runs touched no input; 248 of 414 job-minutes wasted) | §4.1, §5.4, §8.4, §12.0, R30, R33, A28 | 417d90d, 6723de2 |
| 2 | SPK-i decided: stable types as totals with margin 2t; worst class over ≥ 3 CI runs; pixel-area bound re-classes the CI runs to 33/22/7, 31/23/8, 27/27/8; stale 28/14/8 marked superseded | §1.2, §4.2, §10.2, App B, A25 | 6b4237e, 5879861, 13b6c98 |
| 3 | Touch wedge fixed by a flag; result on CI: 0 wedges in 9 jobs (MEASURED, runs 39038973297, 39038976656, 39038979125; da287ff); the local runs were debug only (cause found); class drift between CI runs | §4.2 | 25bd9f4, da287ff |
| 4 | WKTR from WebKit's prebuilt iOS-simulator products, planned on GitHub macos-26 (INFERRED until `wktr-local`); the cloud Mac a fallback (the lead's reading); Q10 and R13 updated | §4.2, §10.1, §12.2, A26 | 591a815 |
| 5 | Your answers: Q1 sessions on demand, free-play phone; Q31 yes after liveness feed, clean day and A/B bench; Q33 a Simulator or device check for both, `unreachable` state | §6.6, §8.3, §10.2, §12.0, A27 | [CU] console answers seq 22 (`docs/team/improvements/2026-10-17.md`), `gate-gaps-*` notes |
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
