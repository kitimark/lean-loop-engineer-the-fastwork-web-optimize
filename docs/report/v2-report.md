---
id: 2026-10-17-v2-report
kind: note
title: "v2 report: a measurable, provable loop for the fastwork.com scroll experiment (draft 2, rev-10 shape)"
status: draft
created: 2026-10-17
updated: 2026-10-18
authors: [agent:researcher-report-draft, agent:researcher-report-draft-2]
topics: [report, write-up, lean, measurement, ci, agent-teams, cost]
---

# v2 report (draft)

**State of this draft.** Sections 2, 3, 5 and 7 were written at `e5bf4e4` (2026-10-17 23:34 +0700). Sections 1, 4
and 6 were rewritten at `698b775` (2026-10-18) to the rev-10 shape of [P10:1073-1074, 1083]: per part the theorem
pair, its premises, the RG status, the engine verdicts and an F-result slot. Sections 2, 3, 5 and 7 got dated
updates at `a3196a4` in place of their open items. Two named pending blocks remain, both in
§4.7, and close at C3 (2026-10-19 23:15 +0700). The experiment ends by **2026-10-20 13:15 +0700** (`ad5eeea`).

**Status words.** MEASURED: a number from a run or a count in this repo, with its commit, run id or file. CONFIRMED:
a cited source, doc or record says so. INFERRED: a judgement or expectation not yet checked.

**Short citations.**

| Tag | File |
|---|---|
| [PLAN] | `docs/plan/PLAN.md` (revision 8; line numbers at `e5bf4e4`, used in §2-§3) |
| [P10] | `docs/plan/PLAN.md` (revision 10; line numbers at `698b775`) |
| [LG] | `research/findings/ledger.json` at `698b775`: `L<k>` is the k-th row of `findings` (1-based, 47 rows), `N<k>` the k-th row of `notes` (0-based, 23 rows) |
| [R14] | `research/notes/2026/10-18-math-review-r14-f9b30af.md` (math review round 14) |
| [RG] | `research/notes/2026/10-18-engine-gaps.md` (RG1-RG11 at the pins; RG<k> is the note's R<k>) |
| [CU] | `docs/team/improvements/2026-10-17.md` (the catch-up log) |
| [EV] | `research/notes/2026/10-17-plan-evidence.md` |
| [WG] | `docs/team/work-graph.json` |
| [CHR] | `packages/measure-chromium/README.md` |
| [WK] | `packages/measure-webkit/README.md` |
| [WKTR] | `packages/measure-wktr/README.md` |
| [BL] | `results/baselines/chromium/README.md` |

Numbers taken from git or `gh run list` in this draft were counted at `e5bf4e4`; the CI run list was read at
16:35 UTC (23:35 +0700).

---

## 1. Question and setup

**Question.** Can a loop built on proofs over engine models, deterministic engine counts and an agent team reproduce
v1's end-of-page result with far less phone time, fewer tool bugs and less elapsed time? CONFIRMED [P10:1063-1064]

**Answer shape (rev 10).** Each optimization is a Lean theorem pair: (vis) the visible scene equals the original's
for every width band and instant, and (work) no engine stage does more work in any frame, under a cited model of
Chromium and of WebKit. CI counts can falsify a model; they do not decide. The phone is an optional spot check and
never evidence. CONFIRMED [P10:493-534]

**v1, as the plan states it** (all CONFIRMED by the plan's citations; nothing here is read from v1's raw data).

| v1 figure | Value | Source |
|---|---|---|
| Slow frames in the swipe | 20.1 % → 1.7 % | [P10:113] |
| End-of-page longest frame | 584 ms → 42 ms | [P10:114] |
| Elapsed time | 10 days | [P10:114] |
| Agents started (transcripts) | 442 (848) | [P10:114] |
| Model cost at list price | about $11.4k (v1's own readout: about $13.5k) | [P10:115] |
| Incidents | 276; 231 filed against its own tools; 45 were feature requests | [P10:115-116] |
| Incidents involving the iPhone or Simulator driver | about 111 of 276 | [P10:121] |
| Phone block length | 12-35 min plus cooling | [P10:121] |
| Full test suite per tooling commit | 250-280 s | [P10:123] |
| Chore steps per phone session | 82-105 of 166 | [P10:183] |
| Device incident share | about 40 % | [P10:183] |

**v2 setup.**

| Item | v2 | Status, source |
|---|---|---|
| Time box | 72 h: first commit `931aa35` at 2026-10-17 13:15 +0700, end 2026-10-20 13:15 +0700 | MEASURED (commit log); deadline CONFIRMED (`ad5eeea`) |
| Evidence | A (vis)/(work) theorem pair per part and optimization under `Fw.Engine.{Core, Visual, Chromium, WebKit}`; every engine rule cites a line at `chromium@f842f52` or `WebKit@862f17d` | CONFIRMED [P10:493-512] |
| Model check | Lean emits one prediction per (scenario, variant, stage); F0-F2 on a fixture, F3/F4 on the rewrite arm per flag in the Chromium lane, F5 on the WebKit Simulator lane; a mismatch is a model bug | CONFIRMED [P10:515-530] |
| Inner loop | Chromium headless shell counts on CI; WebKit Simulator counts on CI where green; WKTR not modelled | CONFIRMED [P10:1070-1071] |
| Phone | Optional spot check with no dependents; session 1 held (`0c901f2`); session 2 is not a condition | CONFIRMED [P10:157, 532-534, 1087] |
| Site | React rewrite as pluggable parts, picked by flags; presets `original`, `v1-best`, `v2-proved` | CONFIRMED [P10:711-713] |
| Decisions | One Lean 4 process, `fwcore`; TypeScript moves data | CONFIRMED [P10:123] |
| Where counts run | GitHub Actions, free runners of the public repo | CONFIRMED [CU:444-446] |
| Cost rule | Speed first; cost reported, no hard caps | CONFIRMED [P10:184] |

**Success criteria (rev 10)** are G1-G4 [P10:182-185]. G1 is "reproduced, proved": every flag in `v2-proved` has its
theorem pair in both engine models at every width band, and no F0-F5 prediction is falsified on CI. `v2-proved` is
the set of optimizations with a proved pair and no falsified prediction [P10:93]. §4.2 gives each pair; §4.7 holds
the two results that close at C3 (2026-10-19 23:15 +0700).

---

## 2. The loop as built

### 2.1 Lean core

| Measure | Value | Status, source |
|---|---|---|
| Declarations in the math view | 2,171 (1,005 theorems, 1,166 definitions) in 56 modules | MEASURED, `docs/plan/loop-plan.html` at `e653a14` (module rows summed) |
| Review state of the math view | 2,167 agree, 4 disagree, 0 pending; the 4 were fixed in `25b68d2` and wait for re-review | MEASURED, same file; fix CONFIRMED (`25b68d2`) |
| Growth since revision 8 of the plan | 1,947 declarations (910 theorems) in 51 modules at `7d564e2` | MEASURED [PLAN:120-123] |
| Lean source | 87 files, 34,930 lines in `lean/Fw` and `lean/FwTest` | MEASURED (`find`/`wc` at `e5bf4e4`) |
| Plan's up-front estimate | about 20 modules, $700-1,100 of Lean work | INFERRED in the plan [PLAN:120] |
| Wire ops on `fwcore` | about 70 dotted op names (console, card, step, task, store, gate, measure, metrics, ops, ...) | INFERRED: string grep of `lean/Fw/**/Wire.lean`; a lower bound, undotted ops such as `screen` are not counted |
| Mutants (M0) | 625 mutants, 0 survived (local); 633 on CI in 13.3 min against 23 min locally | MEASURED, `8074907` [CU:495]; `cd49282` [CU:535-536] |
| `fwcore serve` replay | 100k events: 36 s (old list reducer) → 0.4 s; apply round trip p50 40 µs | MEASURED, `14152f1` [CU:239-242] |
| Fresh worktree `lake build` | 80 s → 0.18 s (shared Lake artifact cache) | MEASURED, `c0bf898` [CU:252-258] |

**Math review rounds.** A fresh math-reviewer writes the math from the Lean, then compares it with the docstring's
LaTeX, clause by clause.

| Round | At | Reviewed | Agree | Disagree | Agree rate | Source |
|---|---|---|---|---|---|---|
| r1 (Fw/Spec) | sketch | 72 | 72 | 0 | 100 % | `research/notes/2026/10-17-math-review-fw-spec.md:15` |
| r2 (fwcore) | `9367dea` | 156 | 156 (math); 7 English rows disagree | 0 | 100 % (math) | `…-math-review-fwcore.md:24-35` |
| r3 | `a65aaa7` | 450 | 396 | 54 | 88.0 % | `…-math-review-r3-a65aaa7.md:26` |
| r4 | `740b06c` | 258 | 187 | 71 | 72.5 % | `…-math-review-r4-740b06c.md:24` |
| r5 | `c4ca5ad` | 490 | 428 | 62 | 87.3 % | `…-math-review-r5-c4ca5ad.md:25` |
| r6 | `77b381c` | 62 | 61 | 1 | 98.4 % | `…-math-review-r6-77b381c.md:20` |
| r7a | `e6908db` | 234 | 214 | 20 | 91.5 % | `…-math-review-r7a-e6908db.md:21` |
| r8 | `fee88b2` | 502 | 453 | 49 | 90.2 % | `…-math-review-r8-fee88b2.md:23` |
| r9 | `a82e4a4` | 155 | 148 | 7 | 95.5 % | `…-math-review-r9-a82e4a4.md:21` |
| r10 | `c6fada5` | 334 | 330 | 4 | 98.8 % | `…-math-review-r10-c6fada5.md:23` |
| **r3-r10** | | **2,485** | **2,217** | **268** | **89.2 %** | sum of the rows above (MEASURED) |

All rows MEASURED (review records). Rows are review verdicts, not distinct declarations: a declaration fixed after a
disagree is reviewed again.

**What the reviews found, and the lints that followed.** Each recurring finding became a check, so the next round
is cheaper.

| Pattern found | Became | Status, source |
|---|---|---|
| Free variables in the math that the Lean quantifies (44 of 71 in r4) | Free-variable lint in `mathview --lint` (warning); flagged 181 → 71 | MEASURED, `00c09bf` [CU:66-69, 140-142] |
| A bound variable that shadows a function in the same formula (top r8 finding) | ShadowLint: a mathview **error**, 0 false positives | CONFIRMED, `19e980e` [CU:537-538] |
| A where-clause outside the `$$` block (r10) | WhereLint (warning): 64 hits elsewhere | MEASURED, `25b68d2` |
| Docstring entries checked by `check.sh` | 963 entries in 35 modules, 0 failures, 96 quantifier warnings | MEASURED, `30e3264` [CU:182-188] |

**Lean caught a false plan claim.** The aging bound in `docs/team/parallel-plan.md` §3.2 had a counterexample (an
item still queued at t = 25 against a bound of 20). The proved bound is $(1+\Psi)\cdot dur_{max}$. CONFIRMED,
`4bd850f` [CU:330-333].

### 2.2 Console and observation

| Piece | What it does | Status, source |
|---|---|---|
| console-api + `fwcore serve` | Single writer of the event log; every view is a Lean projection; nobody writes status | CONFIRMED, `14152f1`, `eacb660` [CU:234-249, 286-294] |
| Tests at con-wire | console-api 127/127, runner 32/32, typecheck green | MEASURED, `eacb660` [CU:287] |
| TS stand-ins in the console | none left | CONFIRMED, `acc5d83` [CU:500-501] |
| Plan tab, `fw plan sync` | Lean derives ready / running / blocked, refuses cycles, finds the critical path | CONFIRMED, `e920459` [CU:390-396, 472-473] |
| `fw watch` and Health tab | Slow-work and health rules in Lean (`obs.health`: agent gone, slow tool, slow CI, long process, high load) | CONFIRMED, `8a430c3`, `fa032f4`, `138e039` [CU:539-541] |
| Alert steps | Alert rule in Lean (`console.alert`) | CONFIRMED, `c92c310` |
| Only the user answers a step | The console refused the lead's attempt to record a user answer (Q33): the Lean rule worked as designed | CONFIRMED [CU:418-420] |

Problems the observation layer found in itself:

| Finding | Status, source |
|---|---|
| 225 of 249 SubagentStops came from Claude Code's internal forks with an empty `agent_type`; the capability hook mapped empty to the lead. Fixed to fail closed | MEASURED, `2e0d21b` [CU:436-440] |
| 18 of 26 workflow spawns skipped spawn-guard | MEASURED [CU:439-440] |
| The strict ObsRecord schema rejected every SpawnGuard record, so no agent claimed its task; after the fix 31 spawn records were accepted (was 12) | MEASURED, `6228fcf` [CU:502-505] |
| "Agent main needs input" alerts copied the lead's own permission prompts; removed | CONFIRMED, `6eb9068` [CU:462-466] |
| The first `fw watch`: 6 of 7 alerts were intended long-runners | MEASURED [CU:546-548] |

### 2.3 Agent team

| Measure | Value | Status, source |
|---|---|---|
| Wall time so far | 10 h 19 min (13:15 → 23:34 +0700) of the 72 h box | MEASURED (git) |
| Commits on main | 380 (304 non-merge, 76 merges; 71 distinct merged branch names) | MEASURED (`git log` at `e5bf4e4`) |
| Commits by co-author model trailer | Opus 283, Sonnet 80, none 17 | MEASURED (`Co-Authored-By` trailers) |
| Handoff notes | 83 files in `docs/team/handoffs/` | MEASURED (`ls`) |
| Tasks in the work graph | 107 (M0 22, M1 31, M2 15, M3 8, M4 1, M5 1, M6 2, no milestone 27) | MEASURED [WG] |
| Tasks with a commit on main | 78 of 107 (task id in a commit subject or `Task:` trailer, or `evidence` set); a few are partial or landed inside another task's commit | MEASURED by a subject match at `e5bf4e4`; the edge cases INFERRED |
| Tasks by owner role | lean-prover 32, measure-engineer 31, console-builder 10, researcher 9, lead 8, part-builder 4, plan-editor 5, math-reviewer 3, user 3, env-ops 1, page-writer 1 | MEASURED [WG] |
| Sub-agents profiled by 16:32 | 120+ | MEASURED [CU:34] |
| Peak sub-agents busy at once | 12 | MEASURED [CU:163] |
| Speedup during build windows | 4.9 (6.8-7.5 after 08:00 UTC) | MEASURED [CU:164] |
| Lead busy share; lead pickup median | 46 %; 5 s | MEASURED [CU:166-167] |
| Concurrency cap | 6 → 10 agents | CONFIRMED, `a0b9053` [CU:150-152] |

Commits per hour (MEASURED, git, +0700):

| 13 | 14 | 15 | 16 | 17 | 18 | 19 | 20 | 21 | 22 | 23 (to :34) |
|---|---|---|---|---|---|---|---|---|---|---|
| 7 | 10 | 40 | 18 | 41 | 19 | 54 | 55 | 55 | 56 | 25 |

**Count at this draft.** `main` holds 1295 commits, from `931aa35` (2026-10-17 13:15 +0700) to `a3196a4`
(2026-10-18 20:16 +0700). MEASURED (`git rev-list --count main`). Wall time to each milestone gate, tasks landed
per milestone and agents started are counted at the end by task `write-up`.

---

## 3. Measurement

### 3.1 Chromium: original (A) against rewrite (R)

Classes per count type: **deterministic** (equal in every job), **stable** (within the tolerance, kMax 4 frames,
tMax 24), **quarantined** (beyond it). A class is signed as the worst over 3 CI workflow runs of 3 jobs each, on one
pinned image. The freeze rule runs in Lean (`measure.freeze`: order independent, monotone, idempotent). CONFIRMED,
`bc2e28a` [CU:522-524].

**The frozen table (original), det / stable / quarantined.**

| Profile | Per workflow run | Frozen (worst of 3) | Pooled over 9 files (reference only) | Source |
|---|---|---|---|---|
| swipe-v1 | 28/25/9, 27/26/9, 30/25/7 | **27/25/10** | 27/23/12 | MEASURED, runs 39038861283, 39038967198, 39038970307; `da287ff` [CHR:249-260] |
| swipe-touch-v1 | 17/31/14, 18/25/19, 18/33/11 | **16/27/19** | 16/25/21 | MEASURED, runs 39038973297, 39038976656, 39038979125; `da287ff` [CHR:249-260] |

62 types. `trace.Paint` is quarantined in both profiles, `trace.RasterTask` under touch. MEASURED [PLAN:423].

**A against R on CI** (one VM per job; same image, profile, flags and host).

| Profile | Original A | Rewrite R | Source |
|---|---|---|---|
| swipe-v1 | 27/25/10 and 30/22/10 | 37/6/1 and 37/7/0 | MEASURED, `fee88b2` [PLAN:426] |
| swipe-touch-v1 | 31/20/11 | 40/0/4 | MEASURED, `fee88b2` [PLAN:426] |

A reports 62 types and R 44, so the tallies are not like for like. The rewrite had no frozen table at `e5bf4e4`; the refrozen table below has one. MEASURED
[PLAN:426].

**Splits found, and their causes.** "Quarantined" was often a harness finding, not engine noise. Each split moves
browser work out of a page count by containment of trace slices; it adds no decision logic to TypeScript.

| Count | Cause | Fix | Result | Status, source |
|---|---|---|---|---|
| `trace.HitTest` (swipe, A) | `OverlayInterstitialAdDetector` runs at most once per second of **wall clock** (`overlay_interstitial_ad_detector.cc:26,84-88@f842f52`) | Its slices are counted as `trace.HitTest.overlayAdDetector` | HitTest quarantined (116, 0) → deterministic (0, 0); the detector type is quarantined by design | CONFIRMED in source, MEASURED on CI run 39044815926; `f90c08f`; `research/notes/2026/10-17-hittest-and-spk-q.md` §1 |
| N1 `updateActiveStyleSheets` (A) | First: categories `blink_style`/`blink` not traced, so 0 for a wrong reason. Then 17 in one frame: 17 isolated SVG-image documents running their first style update | Slices inside `IsolatedSVGDocumentHost` counted as `trace.N1.svgImageDocument` | N1 = 0 on A in W-rest and W-measure; N0 = 0 with a positive control (4 of 4 seen) | MEASURED, runs 39044815926, 39044812879; same note §2 |
| `census.activeTileAreaPx`, `census.drawingAreaPx` | Pixel areas jitter in parts per million | Relative bound for pixel-area types | Both leave quarantine (largest gap 382 ppm) | MEASURED, `5879861` [EV:160] |
| Touch: BeginFrame wedge | `WaitForLateScrollEvents` set a timer at virtual frame time, about 4,900 s ahead of the container clock | `--disable-features=WaitForLateScrollEvents` | 0 wedges in 9 CI jobs, all on attempt 1 | MEASURED, `25bd9f4`, `da287ff` [EV:161] |
| Class drift between runs of the same code | Runner noise or an unpinned image | Pin the image; sign the worst of 3 runs | Frozen table above | drift MEASURED, cause INFERRED [EV:157] |

**The touch race** (`research/notes/2026/10-17-touch-race.md`, `c38088e`). In touch profiles, EventDispatch,
FunctionCall, HitTest and PrePaint were quarantined.

- Cause, CONFIRMED in source: the renderer holds an async touchmove back for 200 ms when the queue holds exactly one
  event (`main_thread_event_queue.cc:758-770@f842f52`). Whether it holds one or two depends on a thread race, so a
  touchmove runs in frame n+1 or n+2. A second race: the gesture events reach the compositor while the harness sends
  the next BeginFrame.
- Fix in the harness: `--async-touch-move-throttle-time-ms=0`, plus a 100 ms real-time delay after an acked touch
  frame (a margin, not a proof).
- Result, MEASURED on 3 CI workflow runs (39046992424, 39047378531, 39047820525):

| Arm, type | Before | After (3 runs) |
|---|---|---|
| R, all 4 types | quarantined | deterministic (0, 0) in every run |
| A, EventDispatch | quarantined | stable (2, 2) ×3 |
| A, FunctionCall | quarantined | stable (2, 6) ×3 |
| A, HitTest | quarantined | stable (2, 2), (4, 2), (4, 2) |
| A, PrePaint | quarantined | stable, quarantined (6, 2), stable |

- Residual: three one-frame shifts, each in 1 job of 3, near scroll positions 1549 and 3203 and the page end. Their
  cause is open: CI uploads no trace for those frames. INFERRED page-side.

**Refrozen table** (task `refreeze`, merged at `82e8934`). `classes.frozen.json` schema 2 holds both arms and the
HitTest, N1 and touch-race splits, over 3 CI runs per profile. One touch run was left out because its R job sent
403 frames instead of 409. MEASURED, `docs/team/handoffs/refreeze.md`.

| Profile | Arm | Before (det/stable/quar, types) | After | Runs |
|---|---|---|---|---|
| swipe-v1 | A | 27/25/10 (62) | 32/28/10 (70) | 39049264131, 39049466889, 39049469621 |
| swipe-v1 | R | none | 44/7/1 (52) | same |
| swipe-touch-v1 | A | 16/27/19 (62) | 23/32/15 (70) | 39049471997, 39049481754, 39050423094 |
| swipe-touch-v1 | R | none | 50/1/0 (51) | same |

The zone baselines read this table: 0 unlisted types (was 8) and no deterministic drift. MEASURED, `ccb83a5`.

### 3.2 WebKit lanes (honest status)

The first two tables are the state at `e5bf4e4`, when neither WebKit lane gave stable page counts
[CU:549-550]. The third table gives what came after.

| Lane | What runs | State | Status, source |
|---|---|---|---|
| Simulator (Mobile Safari over Web Inspector, iOS 27.0, `xcode-27` image) | Per-step Timeline counts of the scripted scroll | Local debug runs only: per-step Layout, Paint, InvalidateLayout, ObserverCallback quarantined; RecalculateStyles within 1; totals within 3-5 % | MEASURED locally (debug, before the measure-on-CI rule), `367fec2` [EV:164] |
| Simulator on CI | Same harness on GitHub `xcode-27` | 1 success in 35 runs (21 cancelled, 11 failed, 2 running at 23:35). Hardening landed, but runs fail at session 2 on an overloaded runner; task `webkit-green` | MEASURED (`gh run list`); `7818dbb` [CU:539] |
| WKTR (prebuilt trunk WebKitTestRunner, iOS 26.5 Simulator, `macos-26`) | Restyle counts from WebKit's test runner | Green on CI (2 runs, 6 jobs), but only `renderingUpdates` and `layerFlushes` are deterministic, and the harness drives both. Every style, layout and compositing count is quarantined; warming did not help | MEASURED, runs 39036983052, 39042087508; `2357452` [WKTR:89-118] |

More facts that bound what WebKit can say:

| Fact | Status, source |
|---|---|
| Simulator boot on the standard `xcode-27` runner: 120 s median; `bootstatus` alone 49-223 s; job load 401-836 | MEASURED, `7563f79`; `research/notes/2026/10-17-sim-speed.md:20-24` |
| `xcode-27-xlarge` boots in about 44 s but is paid; rejected (user: never pay for runners) | MEASURED; decision CONFIRMED, `2a29286` |
| Largest remaining loss is missing fail-fast: one session lost 120 s + 397 s of waits, another stalled about 19 min | MEASURED, sim-speed note:29-31 |
| `RenderingFrame` reads 0 on iOS 27.0 (24A434) and about 60/s on 26.5 | MEASURED locally (debug), `367fec2` [CU:322] |
| WKTR is trunk WebKit at the archive's revision, not the WebKit that ships in iOS 27.0 | CONFIRMED, `591a815` [CU:423-429] |
| The rewrite's hit-skip cuts RecalculateStyles 164 → 19, but its steps do not align with the original's (74 vs 107); no Δ yet | MEASURED locally (debug), `367fec2` [EV:168] |

**After 2026-10-18.**

| Item | Result | Status, source |
|---|---|---|
| C1 WebKit go/no-go | GO: two consecutive `webkit-sim` runs on `ci/webkit-green` took 19 and 24 min | MEASURED, runs 39048376821, 39050061299; `f03e94b` [P10:1080] |
| Host load | 0-12 CPU burners change neither step time nor jitter; classes over 3 sessions: 49 det / 9 stable / 46 quarantined of 104 | MEASURED, runs 39053364004, 39055950094; `80676e0` |
| Step alignment | Original and rewrite steps are aligned by scroll position in Lean (`StepAlign`); rows pair by key (`pairRows`) | CONFIRMED, `e0fa48c`, `b865f47`; CI run 39081148105 (`670099a`) |
| Zone baselines of the original | Gateable per zone: RenderingFrame, Composite, EventDispatch | MEASURED, run 39061324429; `6b5933d` |
| Rewrite arm, `hero.countdown:strip` | 3 green runs; 86 of 95 class rows agree across them | MEASURED, runs 39104964068, 39123585294, 39123621097; `319e5f8` |
| WebKit role (rev 10) | The model `Fw.Engine.WebKit` carries the WebKit claim; Simulator counts can only falsify it (F5) | CONFIRMED [P10:1071, 515-530] |

### 3.3 Breakpoint gate and the gaps lane

| Item | Value | Status, source |
|---|---|---|
| Load matrix | 124 loads per engine × 2 engines × 2 arms (original, rewrite), plus 4 sweeps; generated from Lean (30 conditions, 124 probes) | CONFIRMED, `e7fb102`, `32c6336` [CU:217-218, 470] |
| Repeatability | A full run is byte-identical across 2 runs | MEASURED [CU:218] |
| Pilot parts | All 4 (engine.scroll, nav.hitTest, hero.countdown, hero.exit) pass all 14 gate cells in Chromium and Playwright WebKit | MEASURED, `95693f4`, `2566949` [CU:304-308] |
| What the gate caught | hero.exit failed above 600 px and under reduced motion: padding/position not restated, `filter: none` missing, 320 px floor missing | MEASURED [CU:224-228] |
| On CI | breakpoint-gate passed (4 m 40 s, then 5 m 06 s); no hang at ≥ 1000 px on real runners | MEASURED [CU:365, 382] |
| Probe scope per part (proved in Lean) | engine.scroll 4 probes, nav.hitTest 1, hero.countdown 9 + 3 sweeps, hero.exit 9 + 3; hero.exit gate 10.8 vs 34.6 job-min | MEASURED, `78b850a` |

**The gaps lane (Q33).** 8 cells the default run cannot reach: 4 fractional widths (600.5, 640.5, 860.5, 1000.5 at
DPR 2) and 4 hover × pointer cross probes. Lean decides each cell's state (`gate.state`, `Fw.Gate.Reach`).
CONFIRMED, `packages/gate-breakpoints/src/gaps/README.md:1-30`.

| Engine | Result | Status, source |
|---|---|---|
| Chromium | 8 of 8 pass | MEASURED on CI, `0d561fa` |
| WebKit | 8 of 8 unreachable, as Lean predicts (media width is an integer; the primary pointer pair is one platform constant) | MEASURED on CI, `0d561fa` |
| iPhone and iPad Simulator arms | ran OK | MEASURED, `0d561fa` |
| Real iPhone | 8 of 8 agree with Lean and the Simulator; 8 of 8 again in Light mode | MEASURED on the phone, `0c901f2`, `82954ed` |

---

## 4. Results: the proof ledger

### 4.1 How to read a row

Every row is one ledger finding [LG] (`L<k>`). Its verdicts, premises and Lean names are the ledger's, which cite
engine lines at `chromium@f842f52` and `WebKit@862f17d`. Lean names are in `lean/Fw` at `698b775` (each name in §4.2
resolves to one declaration, CONFIRMED by grep at `698b775`); the prefix `Fw.Parts.` is dropped.

| Column | Meaning |
|---|---|
| (vis) | The theorem that the visible scene of the variant equals the original's: E (equal), E-s (equal at each sample), Q (within the gate's tolerances). "none" means the ledger has no such theorem |
| (work) | The theorem that bounds the variant's work per frame, and the theorem against a claim where one exists |
| Ledger | `proved` or `partly-proved` as recorded in the ledger |
| Cr, Wk | The ledger's verdict per engine model: win (less work, no more layers), trade (less of one, more of another), no-win (equal), worse, unknown |
| Open premise | The premise of the row that is not CONFIRMED, with the ledger's status |
| RG | Research gaps the row rests on, with their status from [RG] |
| F | Where the row's F3/F4 result goes: the flag it runs under, or why it cannot run at `698b775` |

All verdicts are under the engine models, so they are CONFIRMED as Lean results and INFERRED as engine facts until
F3/F4 (Chromium) or F5 (WebKit) check them. F3/F4 have not run on any flag at `698b775` (§4.7).

### 4.2 Per part: theorem pair, premises, engine verdicts, F-result

| L | Part: optimization | (vis) | (work) | Ledger | Cr | Wk | Open premise (status) | RG | F |
|---|---|---|---|---|---|---|---|---|---|
| L1 | engine.scroll: batched reads then writes | none; E needs premise NI (INFERRED) | `EngineScroll.batched_le_faithful`, `total_batch_win_iff` | proved | no-win | unknown | Chromium runs UpdateLayoutTree only when style is dirty at a lifecycle step: INFERRED (CI 784 vs a local no-write probe 94 per 385 frames) | RG4 CONFIRMED | `engine.scroll:batched` |
| L3 | nav.hitTest: hit-skip while morph > 0.2 | `NavHitTestOpt.hitSkip_visSame` (E) | `hitSkip_run_dominates` | proved | win | win | swipe-v1 reaches morph > 0.2: OPEN, INFERRED false, so F3 may see no skipped frame | RG4 CONFIRMED | `nav.hitTest:hit-skip` |
| L4 | nav.hitTest: elements-skip with an allow-list | `elementsSkip_visSame` (E under premise AL) | `elementsSkip_run_dominates` | proved | win | win | AL generated from CSS: no theorem yet (missingWhy) | RG4 CONFIRMED | `nav.hitTest:elements-skip` |
| L5 | nav.hitTest: write-on-change | `NavHitTest.changed_write` (E) | `writeOnChange_le`; against: `toggle_noop` | proved | no-win | no-win | none: `toggle` is a no-op when unchanged, CONFIRMED in both engines | none | no flag |
| L6 | hero.exit: threaded scroll-driven consumers | `HeroExitOpt.consumer_eq_s` (E-s under RG11) | `cr_real_tradeE`, `wk_tradeE` (trade) | partly-proved | trade | trade | WebKit ticks scroll-timeline animations each update: MEASURED, CI 39075991405 [LG N2, N7] | RG11 CONFIRMED; RG7 O3 CONFIRMED | no flag |
| L7 | hero.countdown: strip (one strip per digit) | `HeroCountdownOpt.strip_visSame` (E) | `strip_claim`; against: `strip_backing_gt` | proved | trade | trade | each layer backs its whole box: INFERRED | none | `hero.countdown:strip`; F5 lane green 3 times (§4.6) |
| L8 | hero.countdown: cd-roll-ca (WAAPI roll) | none (E-s at one cadence is missingWhy) | engine level only: `Engine.Chromium.compTransform_no_layout_paint` | partly-proved | win | trade | Safari time-based animations off the threaded path: OPEN (RG7 O2) | RG5 lane shim breaks it; RG7 O2 OPEN | no flag |
| L9 | hero.countdown: clock-aligned timer | `HeroCountdown.drift_skips` (not E on WebKit under timer alignment) | against: `HeroCountdownOpt.same_run_noClaim` | proved | no-win | worse | iOS 26 thermal timer grid: OPEN | none | no flag |
| L10 | hero/morph.countdown: skip face writes while hidden | `HiddenPause.hidden_pause_eq` (E) | `skipWrites_leE` | proved | win | win | which hidden forms skip paint: OPEN (RG6 residual) | RG6 residual OPEN | `morph.countdown:hidden-pause` |
| L11 | morph.tween: one WAAPI animation on registered `--morph` | `MorphTweenOpt.waapi_vis` (E-s) | `waapi_work_le_chromium`, `waapi_work_le_webkit`, `drop_run_dominates` | proved | win | win | timeline zero under the lane clock shim needs an offset: OPEN | RG2, RG3, RG3b CONFIRMED; RG8 MEASURED; RG5 lane OPEN | `morph.tween:waapi` |
| L13 | morph.panel: `blur(0)` → `none` at rest | `MorphPanelOpt.rest_visSame_E` (E under RG10) | `cr_rest_claim` with against `cr_toggle_not_le`; `wk_cross_claim` | proved | trade | win | WebKit toggle frames on the variant page: OPEN, not measured [LG N20] | RG10 CONFIRMED; check on the rewrite DOM OPEN | no `morph.panel` part on main |
| L16 | morph.panel: own layer during the blur fade | `fade_visSame_Q` (Q) | `wk_fade_trade`; against: `cr_fade_noClaim` | proved | no-win | trade | original panel already its own layer in the lane: OPEN | none | no `morph.panel` part on main |
| L17 | morph.mount: warm-up mount at a still moment | `MorphMountOpt.visSame_mount` (E under HiddenBefore) | `shift_peak_lt` (peak); against: `Engine.shift_not_dominates` | proved | trade | trade | the counting window holds the warm-up frame: premise | none | `morph.mount:shift`; engine-check has no peak window |
| L19 | morph.countdown: strip, reused from L7 | `HeroCountdownOpt.strip_visSame` (E) | `strip_frame_ltE`; against: `strip_backing_gt` | partly-proved | trade | trade | shared-loop scheduling delta of the TS strip: OPEN, not modelled | none | `morph.countdown:strip` |
| L20 | morph.columns: still picture while closed | `HiddenPause.panel_visSame` (E while hidden) | `pause_le`; against: `cr_realChrome_pause_eq`, `wk_pause_eq` | partly-proved | no-win | trade | which hidden forms drop the Chromium property node: OPEN (RG6) | RG6 residual OPEN | `morph.columns:hidden-pause` |
| L23 | hero.accent: boil as a chain of opacity steps | `HeroAccent.exact_chain_vis` (E) | `cr_main_run_dominates`; against: `cr_comp_step_not_le` | proved | trade | no-win | the Chromium original is composited: OPEN (`compositeFailedBits` decides) | RG5 lane phase gap CONFIRMED | no hero.accent part on main |
| L25 | people.card: skip the shrink write in the c860 band | `PeopleCard.peopleCard_visSame` (E) | `cr_dominates`, `wk_dominates` | proved | win | win | swipe profiles contain tail frames: OPEN | none | none yet: people is a shell; `people.card:shrink` planned in `model-checks` |
| L28 | people.card: pre-painted card (g0.0m) | none (pixels E per the ledger) | `Engine.shift_peak`; against: `shift_not_dominates` | partly-proved | trade | trade | WebKit paints the opacity-0 `will-change` layer: INFERRED at the pin | RG6 CONFIRMED | none: people is a shell |
| L33 | people.deck: cqi sizing | `PeopleDeck.deck_vis` (E in Q) | `deck_run_dominates`; against: `Engine.WebKit.wkRounds_ge_two` | partly-proved | no-win | win | relayout link from sticky to shells: UNRESOLVED | none | none: people is a shell |
| L34 | pain.notes: arm the 3 s interval only while visible | `PainNotes.pain_visSame` (E; premise CovOk OPEN) | `hiddenTick_lt`, `cr_idle_tick`, `wk_idle_tick` | proved | win | win | Chromium per-tick saving is model-only; the timer rule is OPEN [LG N21] | none | none yet: pain is a shell; `pain.notes:arm` planned in `model-checks` |
| L36 | commission.typing: forced-layout fix | none (E per the ledger; ResizeObserver timing INFERRED) | `EngineScroll.batched_le_faithful`, `HiddenPause.skipWrites_le` | partly-proved | win | win | read parity of the reorder: OPEN | none | none: commission is a shell |
| L38 | commission.typing: 2 characters per step | not E (class L, `PlatformEntries.typing_subsample`) | `HiddenPause.skipWrites_le` | proved | win | win | text writes restyle no element: INFERRED | none | a look change: proposal only |
| L39 | platform.sweep: band moved by `translateX` | geometry `PlatformSweep.band_eq_bgpos`; pixels Q | `Engine.comp_move_le_off`; against: `comp_move_not_le` | partly-proved | trade | trade | WebKit keeps the masked band on the compositor: UNRESOLVED in source | none | no flag |
| L42 | engine.scene: pause compositor marquees while hidden | `HiddenPause.scenePaused_imp_hiddenPause` (E) | `cr_pause_style_units`; against: `cr_realChrome_pause_eq`, `wk_pause_eq` | proved | no-win | no-win | every BeginFrame is a main frame in the lane: INFERRED (RG1) | RG1 OPEN; RG6 residual OPEN | `morph.columns:hidden-pause` |
| L43 | engine.scene: hysteresis and idle pre-warm | `HiddenPause.hiddenPause_visSame` (E) | `flips_le_one`; against: `flips_oscillate` | partly-proved | unknown | unknown | the 800 per 10 s flap rate came from a v1 build with deferral: CONFIRMED | none | no flag |
| L44 | morph.countdown: hidden, spring keeps integrating | `HiddenPause.hidden_pause_eq` (E under hsync) | `unhide_leE`, `cr_countdown_style` | proved | win | win | hsync writes the state before paint on unhide: OPEN | none | `morph.countdown:hidden-pause` |
| L45 | engine.scene: pause per element, not per section | `HiddenPause.hiddenPause_visSame` (E with the original clock) | `pause_le` | partly-proved | win | win | a descendant-selector flip restyles the subtree: INFERRED | none | `engine.scene:hidden-pause` exists but is not mounted |

**What the table says** (counts from [LG] by `python3 -c` over `findings`, MEASURED at `698b775`):

| Ledger status | Rows | Cr win / trade / no-win / other | Wk win / trade / no-win / other |
|---|---|---|---|
| proved | 17 | 8 / 4 / 5 / 0 | 9 / 3 / 3 / 2 (worse 1, unknown 1) |
| partly-proved | 10 | 3 / 4 / 2 / 1 (unknown) | 3 / 6 / 0 / 1 (unknown) |
| not-proved | 14 | 8 / 2 / 3 / 1 (worse) | 7 / 5 / 2 / 0 |
| not-tried | 4 | 0 / 1 / 3 / 0 | 1 / 2 / 1 / 0 |

- Proved with a win in both engine models: 8 rows, L3, L4, L10, L11, L25, L34, L38, L44. MEASURED [LG].
- Of these, L38 changes the look (class L), so it is a proposal, not a `v2-proved` flag. CONFIRMED [P10:1073].
- L25 and L34 have no flag on the page at `698b775`, because people and pain are shells (`part.json` variants
  `shell`). CONFIRMED (repo at `698b775`).
- The `v2-proved` candidates with a flag on main are therefore L3 or L4 (two answers to the same nav probe), L10/L44
  (`morph.countdown:hidden-pause`) and L11 (`morph.tween:waapi`). INFERRED: task `experiments` decides at C3 after
  F3/F4.
- Proved but not a win in both models: L1, L5, L7, L9, L13, L16, L17, L23, L42. Each is a negative or mixed result
  with its mechanism in the ledger. MEASURED [LG].

### 4.3 Candidates without a proved pair

One line each; the reason is the ledger's `visual` or `premises` text. Verdicts are the ledger's model verdicts.

| L | Part: candidate | Ledger | Cr | Wk | Why there is no pair |
|---|---|---|---|---|---|
| L2 | engine.scroll: observers instead of per-frame rect reads | not-tried | no-win | no-win | not E: Blink delivers IntersectionObserver one frame late, and thresholds cannot drive continuous outputs |
| L12 | morph.tween: compositor-morph on a scroll timeline | not-proved | trade | trade | not E (class L): scaling a box is not resizing it, and a scroll timeline replaces the 680 ms tween |
| L14 | morph.panel: constant 20 px glass | not-proved | no-win | no-win | not E (class L); the GPU cost of a changing radius has no counter (OPEN) |
| L15 | morph.panel: bar from two flat GPU layers (Safari) | not-tried | no-win | trade | Q only: v1 found the 1 px outline differs mid-motion |
| L18 | morph.countdown: own clock layer while the menu is open | not-proved | worse | trade | not E in Chromium: new-layer text drawn up to 1 device px off in v1 |
| L21 | morph.columns: images sized to the drawn size | not-proved | no-win | no-win | not E: a smaller source changes resampling, outside PL1/PL2 |
| L22 | hero.accent: wipe instead of the stroke draw | not-proved | win | win | not E (class L): the stroke-order drawing becomes a wipe |
| L24 | hero.accent: boil-ca (linear with 0.01 % jumps) | not-proved | no-win | trade | E-s only under a phase premise; Safari's CA path for time-based animations is OPEN (RG7 O2) |
| L26 | people.card: instant reveal after a fast flick | not-proved | win | win | not E (class L); v1's look, accepted there |
| L27 | people.card: blur tail cut to 0.9 s | not-proved | win | trade | fails the gate: blur 0.24 px against `none` is outside `filterQ` (1e-3) |
| L29 | people.o: FLIP with WAAPI translate | not-proved | win | win | not E (class L): layout snaps to device pixels, the compositor does not |
| L30 | people.carousel: keep 5 slots mounted (st5) | not-proved | win | win | no Lean pair yet; E assumes an in-place `src` swap paints the same image (INFERRED) |
| L31 | people.carousel: rest at opacity 0.999 (st6) | not-proved | win | win | Q at the gate's boundary; pixel E needs the engines' alpha rounding (OPEN) |
| L32 | people.carousel: clip-path crop instead of a shrink | not-proved | win | win | not E (class L): the crop cuts the border ring and moves followers by sub-pixels |
| L35 | pain.notes: solid-colour layer for the dark flip | not-tried | trade | trade | Q at best: 8-bit rounding happens at different points (≤ 1 LSB, INFERRED) |
| L37 | commission.typing: no `container-type` above per-frame text | not-tried | no-win | win | E only if no container query resolves against it: OPEN; the rewrite declares `container-type` |
| L40 | platform.glint: clip-path span instead of SMIL | not-proved | trade | trade | geometry E-s unproved; pixels Q (≤ 64 LSB in Chrome, ≤ 33 in WebKit, v1) |
| L41 | engine.scene: pause the hero while covered | not-proved | win | win | occlusion is not modelled; 0.999 cover alpha can flip rounding by 1 LSB (OPEN) |

Two rows are premises, not optimizations: L46 (`cv.auto-margin`) is refuted in both engines, and L47 (`anim.list`)
holds in Chromium and fails intermittently in WebKit. MEASURED [LG L46, L47]. Both were premises of the cut task
`gate-settle` (§6).

### 4.4 Premises H1-H3 and research gaps RG1-RG11

**H1-H3** are the path premises: the engine rasterizes the same scene the same way whichever thread draws a box
[P10:509-513]. In Lean they are the structure `PathPremises` (`Fw/Engine/Visual.lean:461`, C1-C3 there), and at
`698b775` only `Fw.Parts.MorphPanelOpt` uses it (grep over `lean/Fw`). The other (vis) theorems are scene-level, and
`visSame_render` (`Visual.lean:446`) turns equal scenes into equal images for any `R : Scene → α`, so H1-H3 sit in the
step from "equal scene" to "equal pixels". CONFIRMED (Lean source at `698b775`). They matter for the rows whose
variant changes which thread or layer draws a box: L6, L7, L16, L19, L39 (INFERRED from the ledger's `visual` text).

| Premise | Statement | Status, source |
|---|---|---|
| H1 | no LCD text in a box whose path differs between the arms | not vacuous in the Chromium lane: DPR 3 does not turn LCD text off on Linux. CONFIRMED [RG] R9 |
| H2 | no compositor scale animation on such a box | not checked; INFERRED from the variant code only |
| H3 | the compositor samples the same value function at its own frame time | not checked; INFERRED |

The check for H1-H3 was `pixel-spot` (Chromium only), cut in §6.

**Research gaps** (12 items, RG3b counted alone; status at the pins `f842f52` / `862f17d`, [RG] summary table):

| Gap | Status | Rows that rest on it |
|---|---|---|
| RG1 lane main frame per BeginFrame | OPEN (value MEASURED, requester not found) | L42 |
| RG2 same restyle set for animated and inline writes | CONFIRMED | L11 |
| RG3 registered `<number>` interpolation is linear | CONFIRMED | L11 |
| RG3b discrete flag flip at p ≥ c | CONFIRMED | L11 |
| RG4 forced-update sites | CONFIRMED | L1, L3, L4 |
| RG5 timeline zero is the HR-time origin | CONFIRMED in the engines; the Chromium lane's clock shim breaks it | L8, L11, L23 |
| RG6 paint skip and ticking per hidden form | CONFIRMED, small residual OPEN | L10, L20, L28, L42 |
| RG7 threaded animation modes | O3 CONFIRMED; O2 CONFIRMED for the lane, OPEN for shipping Safari | L6, L8, L24 |
| RG8 fp tie of the curve | MEASURED (Node golden, max diff 3.33e-16) | L11 |
| RG9 LCD text at DPR 3 | CONFIRMED not vacuous in the Chromium lane | H1 |
| RG10 `blur(0)` makes a containing block and stacking context | CONFIRMED | L13, L27 |
| RG11 scroll-timeline progress = offset / range | CONFIRMED, engine-specific quantization | L6 |

### 4.5 Math review state

| Measure | Value | Status, source |
|---|---|---|
| Round 14 at `f9b30af`: reviewed / agree / disagree | 2357 / 2266 / 91 | MEASURED [R14] counts table |
| `Fw.Parts.*` modules in round 14 (21 modules) | 454 reviewed, 451 agree, 3 disagree | MEASURED [R14] per-module table |
| Round 14 fixes | all 91 fixed in docstrings only, no Lean statement changed | CONFIRMED, `3c2a1de`; `docs/team/handoffs/math-final.md` |
| Math view after the fixes (main `c2410d2`) | 5109 agree, 0 disagree, 517 stale, 1373 pending | MEASURED, `docs/team/handoffs/math-final.md` |
| Held back from round 14 | `Gate.*`, `Plan.*`, `Console*`, `Engine*` (1389 entries) | CONFIRMED, same handoff |

C4 asks for 0 disagree and 0 stale [P10:1083]. At round 14 the view has 0 disagree and 517 stale, and the engine
model modules `Fw.Engine.*` that every (work) theorem uses were not in the round. A round 15 over the stale and
held-back entries is the open step. INFERRED from the counts above.

### 4.6 Measured inputs

| Result | Value | Status, source |
|---|---|---|
| Chromium zone baselines, 4 (profile, arm) pairs, 3 shards each | det/stable/quarantined: swipe-v1 A 32/28/10, R 44/7/0; touch A 23/32/15, R 50/1/0; 0 unlisted, detDrift empty | MEASURED, `f4c6ea5`, runs 39048702153, 39050423094 [BL] |
| WebKit zone baselines of the original | gateable per zone: RenderingFrame, Composite, EventDispatch | MEASURED, `6b5933d`, run 39061324429 |
| Touch race | R deterministic in 4 touch types; A stable; 0 wedges | MEASURED, `c38088e` |
| N0 / N1 neutrality reads on A (Chromium) | 0 and 0 after the SVG-document split | MEASURED, `f90c08f` |
| Engine premises in the lane (17 untested) | 5 held, 7 refuted, 5 not measurable | MEASURED, run 39088367495; `docs/team/handoffs/engine-premise-measure.md` |
| Model fixes from those runs | `morph.panel` own layer: Chromium trade → no-win; `blur(0)` → `none`: WebKit trade → win | MEASURED, run 39088367495 [LG N18, N19] |
| WebKit Simulator on the rewrite, `hero.countdown:strip` | 3 green runs (39104964068, 39123585294, 39123621097); 86 of 95 class rows agree across them | MEASURED, `docs/team/handoffs/webkit-sim-rewrite.md` |
| F0-F2 on the fixture | no result through `fw engine-check` yet: no fixture artifact was fed to it (open item of the task) | CONFIRMED, `docs/team/handoffs/engine-ci-check.md` |
| Breakpoint gate, pilot parts | 4 of 4 pass, both engines | MEASURED, `2566949` |
| Breakpoint gate settle wait | 212.4 → 65.5 job-min with a 60-frame settle budget; per-cell verdicts equal | MEASURED, `088315d`; `research/notes/2026/10-18-gate-shard-balance.md` |
| Gaps lane | Chromium 8/8 pass; WebKit 8/8 unreachable as predicted | MEASURED, `0d561fa` |

### 4.7 Pending until C3

These two blocks are the only open results in this draft. Both close at C3 (2026-10-19 23:15 +0700); a block still
open at C3 moves to §6 with its reason [P10:1082].

> **PENDING 1: faithful bands table** (task `faithful-checks`). PL5 band verdict per zone (y04000, y04500, tail) and
> count type, rewrite against original, bands from the frozen Chromium zone baselines, verdict in Lean
> (`Fw.Faithful`).
>
> | Zone | Count type | Band (lo, hi) | Original | Rewrite (`faithful`) | Verdict | Run |
> |---|---|---|---|---|---|---|

> **PENDING 2: F3/F4 per flag table** (tasks `model-checks`, then `experiments`). One Chromium counts run per flag
> on the rewrite arm, read with `fw engine-check`; a mismatch is a model bug, never a tolerance change.
>
> | Flag | Ledger rows | F3 (=0 stages) | F4 (=o, <o stages) | Model bugs | Run |
> |---|---|---|---|---|---|

---

## 5. What the loop cost

### 5.1 CI minutes

GitHub billing for this repo in October (the repo's first CI run was 2026-10-17 11:19 UTC, so this is one day).
Source: GitHub billing usage read by the user with `gh api` on 2026-10-17, relayed in the report-draft brief; no repo
file holds it yet. MEASURED (by the user).

| Runner | Minutes | Charge |
|---|---|---|
| Linux ARM | 2,490 | free (public repo) |
| macOS 3-core (standard) | 919 | free (public repo) |
| macOS XLarge | 19.6 | **$2.00**, the only charge |

The XLarge minutes came from the `sim-speed` probe's xl arm; that arm was removed after the user decided never to pay
for runners (`2a29286`). INFERRED (the only workflow that used `xcode-27-xlarge`). The list price is $0.102/min,
CONFIRMED `research/notes/2026/10-17-macos-rent.md:9`; 19.6 × 0.102 = $2.00.

Agents cannot read billing: `gh api` stays denied (CLAUDE.md, Upstream source). This table is the only billing
read until the user reads it again. CONFIRMED.

### 5.2 Runs, failures and stray runs

All CI runs to 16:35 UTC (MEASURED, `gh run list --limit 1000`: 208 runs, 34 branches; 174 push, 34 dispatch).
"Run wall min" is created-to-updated time per run, summed; it is not billed minutes (jobs run in parallel).

| Workflow | Success | Failure | Cancelled | Running | Run wall min |
|---|---|---|---|---|---|
| chromium-counts | 42 | 2 | 20 | 1 | 303 |
| breakpoint-gate | 18 | 6 | 14 | 2 | 232 |
| lean | 25 | 4 | 5 | 0 | 75 |
| mutants | 4 | 3 | 2 | 1 | 101 |
| gate-gaps | 6 | 0 | 4 | 1 | 99 |
| webkit-sim | 1 | 11 | 21 | 2 | 467 |
| wktr | 3 | 0 | 7 | 0 | 160 |
| sim-speed | 0 | 3 | 0 | 0 | 103 |
| **All** | **99** | **29** | **73** | **7** | **1,540** |

Why runs failed or were wasted:

| Cause | Size | Status, source |
|---|---|---|
| Every `ci/**` push started all four workflows | 21 of 28 measured runs touched no input of their workflow | MEASURED, `6723de2` [CU:497-499] |
| New `ci/*` branches were diffed against an `origin/main` 142 commits behind, so every lane started | until the user pushed main | MEASURED, `56fe6c9` [CU:516-518] |
| webkit-sim on branches that do not touch WebKit | about 17 % of macOS slot time since 13:30 UTC; 5 stray runs cancelled later | MEASURED, `research/notes/2026/10-17-macos-queue.md:30-31`; [CU:546-547] |
| Merging main into `ci/*` branches started macOS lanes | 7 stray runs; fixed by `ci-paths-guard` | MEASURED, `c6bd596`, `df77488` |
| Our own jobs held all 5 macOS slots (the account cap, shared by `xcode-27` and `macos-26`) | 5 busy for 33.7 min; 14 of 14 delayed starts began 2-18 s after one of ours ended | MEASURED, macos-queue note:17-24 |
| Lean CI cache: Lake hard-links only `.ilean` for cached modules | lean failed from the second run on, until `67192ef` | CONFIRMED [CU:403-406] |
| Snapshot check on a gitignored folder | 3 of 4 workflows stopped on the first CI run | MEASURED [CU:351-353] |

### 5.3 Local incidents (this Mac)

| Incident | Effect | Status, source |
|---|---|---|
| Machine sleep looked like 14-26 min "API stalls" across 7 agents | fixed with one `caffeinate -w <session pid>` | CONFIRMED by `pmset` [CU:48-51] |
| An agent ran `pkill -f "Google Chrome"` | may have closed the user's browser; new kill-by-PID rule | CONFIRMED [CU:232-233] |
| An agent wrote copies of 3 files into the main checkout | removed before the merge | CONFIRMED [CU:301-302] |
| Simulator re-boot every ~2 min and 4 parallel full Lean rebuilds | CPU idle 0 %; load1 ~430 | MEASURED [CU:104-117, 168-171] |
| Local mutation pass (625 Lean builds) | load ~500; moved to CI | MEASURED [CU:482-484] |
| Merge-only test and typecheck breaks | several; test scripts now typecheck first | CONFIRMED, `bc4c46d`, `7fcbbfa`, `aa8d961` |

### 5.4 Model tokens

| Measure | Value | Status, source |
|---|---|---|
| Session profile at 16:32 | 93 agents, 3,932 requests, 80.25 M cost units (input 1, cache write 1.25, cache read 0.1, output 5) | MEASURED, `research/notes/2026/10-17-token-usage-profile.md:3`, [CU:28-41] |
| Share from cache reads / writes / output | 62 % / 27 % / 11 % | MEASURED [CU:36-38] |
| Opus share of tokens | about 85 % | MEASURED [CU:39] |

There is no list-price dollar figure per milestone or role. `main` at `a3196a4` has no `fw usage` command (the
`fw` usage text lists none), so G3's comparison with v1's $11.4k [P10:115] has no v2 number. MEASURED (`pnpm -s fw`
usage text, 2026-10-18).

---

## 6. Not done

**Cut for the deadline.** Each line names the tasks and what the result lacks without them. Task titles are in [WG].

- Gate hardening (`gate-webkit-red`, `gate-run-identity`, `gate-wall-target`, `gate-settle`): the WebKit gate stays red on the stageBg desktop sweep cell and phone-rotation stops 1 and 3, a gate run is not bound to the gate code it measured, an iteration push still runs the full gate, and the rule that a sample counts only when settled is not proved.
- Parked integration fixes (`fix-misc`, `fix-orbit`, `fix-nav-hittest`, `fix-people-webkit`): the gate cells they name from run 39067170911 stay open (pain.notes, hero.orbit, stageBg, overlays.signup, nav border colour, people tails in WebKit).
- `port-parts` and `visual-diff-3`: people.o, people.carousel, hero.accent, hero.cue and commission.typing get no ported part, so their ledger candidates get no flag, and there is no deterministic visual diff of the integrated site.
- `pixel-spot` and `phone-session-2`: H1-H3 stay unchecked in both engines (§4.4), and nobody swipes `v2-proved` against `original` on the phone.
- Tooling backlog (`lfg-*`, `jev-*`, lints): the Lean-first gate has its spec (`lfg-spec`, `lfg-props-shape`, `lfg-mathview-facts`) but no shadow run or enforcement, the Jev oracle stops at its research note (`research/notes/2026/10-18-jev-decision-model.md`), and `claim-lint`, `plan-principles-lint`, `task-spec-lint` and `ci-runner-lint` are not built (commit log of main at `a3196a4`).

**Negative results of 2026-10-18.**

- `gate-shard-balance`: no shard plan lowers the gate's wall time. An LPT plan over measured costs costs the same as a count-balanced deal (28.5-28.6 against 27.5-28.1 job-min), and the 5.6-6.1 min wall is the unsplittable WebKit desktop sweep plus setup. MEASURED, runs 39125771186, 39125776112, 39126934987, 39126939905 (`research/notes/2026/10-18-gate-shard-balance.md`).
- `wktr-fixture-speed`: its claim that 12 WKTR class changes between runs are run-to-run variance is UNEXPLAINED. 9 of the 12 keys also change class among 8 other green runs; 3 never do. MEASURED [LG N22]; Lean `Fw.Measure.WktrVariance`.
- The Chromium timer rule is OPEN: whether an empty timer task runs PrePaint. The engine-premises step meant to test it ran the clock shim's callback inside `Runtime.evaluate`, not a native timer task, so the Chromium half of L34 is proved in the model only. MEASURED, run 39124427211 [LG N21].

---

## 7. Lessons for v3

Each lesson is a judgement (INFERRED) resting on the evidence named.

| # | Lesson | Evidence |
|---|---|---|
| 1 | Budget macOS CI jobs per lane before the first push. The free account runs 5 macOS jobs at once, shared across every macOS label, and our own jobs filled them | MEASURED, macos-queue note:17-24 |
| 2 | Push main early and guard paths, or every new `ci/*` branch starts every lane. Most early runs (21 of 28) touched none of their inputs | MEASURED [CU:497-499, 516-518]; `df77488` |
| 3 | Free macOS runners are too loaded for Simulator counts; check one CI Simulator run is green before building a WebKit plan on it | MEASURED: webkit-sim 1 of 35 runs green; boot 120 s median |
| 4 | Before calling a count "engine noise", look for browser work tied to wall clock or to side documents, and split it by containment | MEASURED: HitTest 116 → 0 differing frames; N1 17 → 0 (`f90c08f`) |
| 5 | Read the engine source for every quarantined input type; the touch race and the touch wedge both had one-line causes in Chromium | CONFIRMED in source: `c38088e`, `25bd9f4` |
| 6 | Turn each recurring math-review finding into a lint; the disagree rate fell from 27.5 % (r4) to 1.2 % (r10) | MEASURED, review records; ShadowLint `19e980e` |
| 7 | Proving a plan's claim finds wrong plan claims: the aging bound was false | CONFIRMED, `4bd850f` |
| 8 | Share one Lean build cache across worktrees from the first hour: a fresh build fell from 80 s to 0.18 s | MEASURED, `c0bf898` |
| 9 | Keep the machine awake for the whole session; sleep looked like API stalls | CONFIRMED [CU:48-51] |
| 10 | Run CI waits in background subagents; an idle in-process teammate is not woken when its background task ends (54 min until the next message) | MEASURED, `548f99c` |
| 11 | Heavy local passes (mutation, Simulator re-boots) slow every agent; run them on CI from the start | MEASURED [CU:482-484, 535-536] |
| 12 | Validate the observation layer itself: a strict schema silently dropped every spawn record, and empty agent types were read as the lead | MEASURED, `6228fcf`, `2e0d21b` |

| 13 | A shimmed API measures the shim. Check that a probe runs the engine path it names: the timer step ran the clock shim's callback inside `Runtime.evaluate`, so the Chromium timer rule stays OPEN | MEASURED, run 39124427211 [LG N21] |
| 14 | Measure an engine premise before proving on it. One premise run changed two signs: the blur on its own layer still re-rasters in Chromium (trade → no-win), and the original's `blur(0)` ↔ `blur(x)` change already lays out in WebKit (trade → win) | MEASURED, run 39088367495 [LG N18, N19] |
| 15 | Declare the variance rule before reading the diff. Under a rule fixed first, 3 of 12 WKTR class changes never occur among 8 rival runs, so "run-to-run variance" does not explain them | MEASURED [LG N22]; Lean `Fw.Measure.WktrVariance` |
| 16 | A scripted swipe is not a finger. On the phone the original showed 2.6 frames per 100 over 50 ms under a finger and 22.9 under the script, longest 81 ms, with jank only in 0-2500 px | MEASURED on the phone, `82954ed` |

---

## Sources

Commits are on `main` of this repo. CI run ids are GitHub Actions runs of this repo. Upstream source lines are at
the pinned Chromium commit `f842f52` (`.cache/upstream/chromium@f842f52/`), as cited in the notes above.
