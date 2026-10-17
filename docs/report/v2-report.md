---
id: 2026-10-17-v2-report
kind: note
title: "v2 report: a measurable, provable loop for the fastwork.com scroll experiment (draft skeleton)"
status: draft
created: 2026-10-17
updated: 2026-10-17
authors: [agent:researcher-report-draft]
topics: [report, write-up, lean, measurement, ci, agent-teams, cost]
---

# v2 report (draft)

**State of this draft.** Written at commit `e5bf4e4` (2026-10-17 23:34 +0700). Sections 1-3, 5 and 7 hold what
exists now. Every place that waits for a result is a **PENDING** block that names the task that fills it. The
experiment ends by **2026-10-20 13:15 +0700** (user decision, `ad5eeea`). The final step adds results only.

**Status words.** MEASURED: a number from a run or a count in this repo, with its commit, run id or file. CONFIRMED:
a cited source, doc or record says so. INFERRED: a judgement or expectation not yet checked.

**Short citations.**

| Tag | File |
|---|---|
| [PLAN] | `docs/plan/PLAN.md` (revision 8) |
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

**Question.** Can a loop built on deterministic engine counts, a proved Lean core and an agent team reproduce v1's
result with far less phone time, fewer tool bugs and less elapsed time? [PLAN:134-136]

**v1, as the plan states it** (all CONFIRMED by the plan's citations; nothing here is read from v1's raw data).

| v1 figure | Value | Source |
|---|---|---|
| Slow frames in the swipe | 20.1 % → 1.7 % | [PLAN:88], [01 §0] |
| End-of-page longest frame | 584 ms → 42 ms | [PLAN:89] |
| Elapsed time | 10 days | [PLAN:89] |
| Agents started (transcripts) | 442 (848) | [PLAN:89], [08 §3] |
| Model cost at list price | about $11.4k (v1's own readout: about $13.5k) | [PLAN:89-90] |
| Incidents | 276; 231 filed against its own tools; 45 were feature requests | [PLAN:90-91] |
| Incidents involving the iPhone or Simulator driver | about 111 of 276 | [PLAN:96] |
| Phone block length | 12-35 min plus cooling | [PLAN:96] |
| Full test suite per tooling commit | 250-280 s | [PLAN:98] |
| Chore steps per phone session | 82-105 of 166 | [PLAN:150] |
| Device incident share | about 40 % | [PLAN:150] |

**v2 setup.**

| Item | v2 | Status, source |
|---|---|---|
| Time box | 72 h: first commit `931aa35` at 2026-10-17 13:15 +0700, end 2026-10-20 13:15 +0700 | MEASURED (git); deadline CONFIRMED (`ad5eeea`) |
| Inner loop | Deterministic work counts on CI: Chromium headless shell in a Linux container; WebKit on the iOS Simulator and WKTR | CONFIRMED [PLAN:94-96], [CU:444-446] |
| Outer loop | The real iPhone, in sessions the user books | CONFIRMED [PLAN:105-112] |
| Site | React rewrite as pluggable parts, picked by flags | CONFIRMED [PLAN:97] |
| Decisions | One Lean 4 process, `fwcore`; TypeScript moves data | CONFIRMED [PLAN:98] |
| Where counts run | GitHub Actions, public repo (user direction `417d90d`) | CONFIRMED [CU:444-446] |
| Cost rule | Speed first; cost reported, no hard caps | CONFIRMED [PLAN:151] |

**Success criteria** are G1-G4 in [PLAN:149-152]. G1 (on the iPhone, `v2-best` at or below 1.7 % slow frames and
42 ms end-of-page longest frame) needs the phone and is PENDING (§4).

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

> **PENDING** (task `write-up`): final commit count, wall time to each milestone gate (G3 measure), tasks landed per
> milestone, and agents started, from git and the console event log at the end.

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

A reports 62 types and R 44, so the tallies are not like for like. The rewrite has no frozen table yet. MEASURED
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

**Frozen table is stale for 8 types.** The zone run has 70 types; `classes.frozen.json` lacks `n0.*`,
`trace.HitTest.overlayAdDetector` and `trace.N1.*`, and still has `trace.HitTest` quarantined. Task `refreeze`
regenerates it. MEASURED [BL:27].

> **PENDING** (task `refreeze`): the frozen table after the HitTest, N1 and touch-race splits, for A and R.

### 3.2 WebKit lanes (honest status)

Neither WebKit lane gives stable page counts yet. The lead decides the WebKit role after `sim-speed` and
`webkit-green` report. CONFIRMED [CU:549-550].

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

> **PENDING** (tasks `webkit-green`, `webkit-quiet`, `step-align`, `zone-baselines-webkit`): a green Simulator run on
> CI, per-type WebKit classes over ≥ 3 CI runs, and the lead's decision on the WebKit role.

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
| Real iPhone | not run | PENDING (task `gap-device`) |

---

## 4. Results so far, and what is pending

**What exists now.**

| Result | Value | Status, source |
|---|---|---|
| Chromium classes, original | frozen: swipe-v1 27/25/10, touch 16/27/19 | MEASURED, `da287ff` |
| Chromium classes, rewrite | swipe-v1 37/6/1 and 37/7/0; touch 40/0/4 (not frozen) | MEASURED, `fee88b2` |
| Touch race | R deterministic in 4 touch types; A stable; 0 wedges | MEASURED, `c38088e` |
| N0 / N1 neutrality reads on A (Chromium) | 0 and 0 after the SVG-document split | MEASURED, `f90c08f` |
| Per-zone sums of the original, swipe-v1 | 12 zones × 70 types, 3 shards (CI run 39048702153). Zone ids, frames and scrolled px equal in all 3 shards. Cells that differ between shards: 18 of stable types, 25 of quarantined types, 0 of deterministic types | MEASURED, `c719d73` [BL:1-24]; `results/baselines/chromium/swipe-v1/original.zones.json` |
| Breakpoint gate, pilot parts | 4 of 4 pass, both engines | MEASURED, `2566949` |
| Gaps lane | Chromium 8/8 pass; WebKit 8/8 unreachable as predicted | MEASURED, `0d561fa` |

> **PENDING: zone baselines.**
> - Chromium cross-shard baseline per zone and type (lo, hi, base, class): tasks `zone-baseline-lean`
>   (Lean op `measure.zoneBaseline`) and `refreeze`.
> - WebKit zone baselines: task `zone-baselines-webkit`, after `webkit-green`.
> - Validity table rows V-j and V-t: task `vj-vt`.
>
> | Engine | Profile | Zones | Baseline | Source |
> |---|---|---|---|---|
> | Chromium | swipe-v1 | 12 | _pending_ | |
> | Chromium | swipe-touch-v1 | 12 | _pending_ | |
> | WebKit | scroll | _pending_ | _pending_ | |

> **PENDING: parts and gates.** Faithful checks (`faithful-checks`), bands freeze (`bands-freeze`), all parts ported
> (`port-parts`, M4), CSS decisions (`css-decide`, the user's).

> **PENDING: experiments (M5, task `experiments`).** One row per landed experiment card: arm, change class, count
> Δ per zone (Chromium, WebKit), verdict (4 vs 4, disjoint ranges), phone check.
>
> | Experiment | Parts / flags | Class | Count Δ | Verdict | Phone | Card |
> |---|---|---|---|---|---|---|
> | _pending_ | | | | | | |

> **PENDING: phone sessions (M3, tasks `phone-session-1`, `calibration`, `gap-device`).** G1 and G2 need these.
>
> | Session | Date | Purpose | Slow frames > 34 ms | End-of-page longest frame | Blind verdicts | Chore steps | Incidents |
> |---|---|---|---|---|---|---|---|
> | _pending_ | | | | | | | |
>
> G1 target: `original` within v1's A/A band; `v2-best` ≤ 1.7 % slow frames and ≤ 42 ms [PLAN:149].

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

> **PENDING** (task `write-up`): October totals at the end of the experiment.

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

> **PENDING** (task `write-up`): list-price dollars per milestone and role from `pnpm fw usage` (G3), against v1's
> $11.4k.

---

## 6. What was cut for the 3-day limit

> **SLOT** (task `plan-rev9`, Fable's plan revision 9): the list of cuts, each with what it costs the result.

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

> **PENDING** (task `write-up`): lessons from the phone sessions and the experiments.

---

## Sources

Commits are on `main` of this repo. CI run ids are GitHub Actions runs of this repo. Upstream source lines are at
the pinned Chromium commit `f842f52` (`.cache/upstream/chromium@f842f52/`), as cited in the notes above.
