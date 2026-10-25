---
id: 2026-10-17-v2-report
kind: note
title: "v2 report: a measurable, provable loop for the fastwork.com scroll experiment (final, draft 3 text frozen 11:15 +0700)"
status: final
created: 2026-10-17
updated: 2026-10-20
authors: [agent:researcher-report-draft, agent:researcher-report-draft-2, agent:researcher-report-draft-3]
topics: [report, write-up, lean, measurement, ci, agent-teams, cost, composition]
---

# v2 report (final)

**State of this draft.** Draft 3 was written at `dcd3e13d` (2026-10-19 23:31 +0700), after checkpoint C3 (decided
22:55 +0700, [C3]). It adds the C3 result per flag (§4.2), independence and composition (§4.5), runs per flag before
and after (§4.6), the findings and negative results of 2026-10-18 and 2026-10-19 (§5), token totals and a CI demand
estimate (§6) and a new not-done list (§7). Sections 2 and 3 keep the text of draft 2 (`e5bf4e4`, `a3196a4`) with
dated additions. The two open result blocks of draft 2 are closed: the faithful bands are in §4.9, and the F3/F4
table is §4.2. Three named slots were open at this draft and were filled after it (`people-layout-shift` landed `9ff2ef77`, `gh-status` landed `f39818c8`, `compose-check` landed `ac087e08`): `people-layout-shift` (§7),
`gh-status` (§6.5) and `compose-check` (§4.5). The text freezes 2026-10-20 11:15 +0700 and the experiment ends
13:15 +0700. CONFIRMED [P11:1043, 1052]

**Final (2026-10-20 13:15 +0700).** The text below is draft 3 as frozen at 11:15 +0700; it is the report. Work that
landed on `main` between the freeze and the end is outside it and listed here only, each with its note or handoff:
the breakpoint gate is green on `main` (WebKit screen size set with the viewport, `Fw.Gate.WebkitScreen`; three green
runs 39368032874, 39369683085, 39370632229, MEASURED, `0e0233f9`); the optimization lane `mount-scroll-tap`
(`76249c2b`) changed `morph.mount` under its `shift` flag, which v2-proved already ships, and `countdown-one-chain`
(`dc392640`) landed as a flag whose preset inclusion is not decided;
`land-fwcore-once` closed as a negative finding (one shared fwcore build made lands slower, `Fw.Ops.WallTime`,
`6d175439`); tooling: `ci-wait-lag` (`e6b5a637`), fwcore replay and query made linear with equality proofs
(`54e26907`, `a3ac6de1`), and the land queue rebuilds fwcore after a Lean land (`c5ff0f65`). CONFIRMED by those commits.

**Erratum (2026-10-20, after the final).** On real devices the user found three visible bugs that no check of this report saw. (1) `morph.tween:waapi`, a v2-proved member counted as proved and win/win in §4: the nav classes stay stale for the whole end-of-page morph and the logo jumps, in Chromium and Safari, because the WAAPI driver writes `data-fw-morph` only at start and finish; the Lean theorem holds for scenes that are functions of the morph view, which the shipped code is not. It is falsified (ledger row `morph.tween.waapi.falsified`, fResult model-bug) and the generator dropped it: v2-proved now has 8 flags (`384bec6f`). The v2-proved gate, model-check and count runs cited in this report measured the 9-flag preset. (2) `hero.exit:scoped` (not in v2-proved) freezes the hero in Safari only: open WebKit bugs 325900 and 321094 (`research/notes/2026/10-21-engine-release-notes.md`). (3) `is-on-dark` is not re-evaluated during the morph in any rewrite arm (a port bug). Why the gate, counts and proofs missed them, and the new trajectory probe: `research/notes/2026/10-21-measure-probe-review.md`. CONFIRMED by user report and source; CI confirmation pending (task trajectory-probe).

**Status words.** MEASURED: a number from a run or a count in this repo, with its commit, run id or file. CONFIRMED:
a cited source, doc or record says so. INFERRED: a judgement or expectation not yet checked.

**Short citations.**

| Tag | File |
|---|---|
| [PLAN] | `docs/plan/PLAN.md` (revision 8; line numbers at `e5bf4e4`, used in §2-§3) |
| [P10] | `docs/plan/PLAN.md` (revision 10; line numbers at `698b775`) |
| [P11] | `docs/plan/PLAN.md` (revision 11.2; line numbers at `dcd3e13d`) |
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
| [C3] | `research/notes/2026/10-19-c3-decision.md` |
| [W1] | `research/notes/2026/10-19-integrate-wave-1.md` |
| [W2] | `research/notes/2026/10-19-integrate-wave-2.md` |
| [MC] | `research/notes/2026/10-19-model-checks.md` |
| [MB] | `docs/team/handoffs/model-bug-fixes.md` (landed `024e2d06`) |
| [LP] | `research/notes/2026/10-19-lego-parts-plan.md` |
| [FR] | `research/notes/2026/10-19-faithful-rerun.md` |

Numbers taken from git or `gh run list` in §2-§3 were counted at `e5bf4e4`; the CI run list was read at 16:35 UTC
(23:35 +0700). Numbers new in draft 3 were read from `dcd3e13d` up to `3ff0dbdc`: the review fixes and the slot fills (§4.5 F6, §6.5 gh-status, §7 people-layout-shift) and the 9-flag re-run of §4.6 came after `dcd3e13d`; run walls are `gh run list` created-to-updated times
and include queue time.

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
the set of optimizations with a proved pair and no falsified prediction [P10:93]. Rev 11 added the C3 rule: a
falsified prediction that cannot be fixed by C3 drops its flag, and a proof task still open is reported as "modelled,
not proved". CONFIRMED [P11:1051]

**Answer at C3** (2026-10-19 22:55 +0700, [C3]).

| Question | Answer | Status, source |
|---|---|---|
| Does the rewrite with `v2-proved` pass the breakpoint gate? | Yes in Chromium: 7056 readings, 0 fail, 7 excused. WebKit: 0 fail, 291 excused, verdict "incomplete" only because of 1 cell (matchMedia =Lean, sweep:phone-rotation) whose 2 readings, stops 1 and 3, cannot be compared (an accepted limit, §7). Both runs conclude "failure" on GitHub because the merge job exits non-zero whenever a merged verdict is not pass (Lean `exit_zero_iff`); the per-engine verdict lines are the result | MEASURED, run 39271987926 (10 flags, before the strip was dropped) and run 39282664077 (9 flags, `639f9475`; read from the C3 note at `e25e6f97`) |
| How many flags are in `v2-proved`? | 9: nav.hitTest:elements-skip, pain.notes:visible, people.card:mq, morph.columns:hidden-pause, morph.countdown:hidden-pause, engine.scene:hidden-pause, morph.mount:shift, morph.tween:waapi, engine.scroll:batched | CONFIRMED, `apps/site/src/registry/presets/v2-proved.json` (generated by `lean/Fw/Preset/Gen.lean`; c3-preset-update, `639f9475`) |
| Which proved flag dropped out? | hero.countdown:strip (with morph.countdown:strip). Its only prediction could not be checked, and the strip arm did more pipeline work | MEASURED, runs 39257533380 / 39259074927; decision [C3] |
| How much less style work does the whole page do? | Style recalcs 1832 → 821 (swipe-v1) and 1864 → 856 (swipe-touch-v1), deterministic in 3 of 3 shards, measured with the 10-flag preset | MEASURED, runs 39253166643 / 39253172750 and 39253177864 / 39253184136 [W2] |
| Is the rewrite faithful to the original in the counts? | No. It fails all 6 count zones (faithful-band rule PL5), while the control passes | MEASURED, §4.9 |
| Can each flag's saving be attributed by proof? | No. None of the flag parts is isolated under the adopted independence rule, so per-flag attribution stays INFERRED | CONFIRMED, `Fw.Parts.Bridge.isolated_code` (§4.5) |
| Proof tasks | 14 of 15 closed; `variant-morph-panel-rest` cut | CONFIRMED [C3] |
| F6 (composition check) | At C3: "statement landed, run after C3". Run after C3 (`compose-check`, landed `ac087e08`): on swipe-v1 whole-run unit types the deltas compose wherever a margin exists; no zone cell is decided; flag independence not checked | CONFIRMED [C3]; result MEASURED §4.5 (runs 39295469515 base, 39295484486 combined) |

---

## 2. The loop as built

### 2.1 Lean core

| Measure | Value | Status, source |
|---|---|---|
| Declarations in the math view | 2,171 (1,005 theorems, 1,166 definitions) in 56 modules | MEASURED, `docs/plan/loop-plan.html` at `e653a14` (module rows summed) |
| Review state of the math view | 2,167 agree, 4 disagree, 0 pending; the 4 were fixed in `25b68d2` and wait for re-review; superseded by §4.8 (r14) | MEASURED, same file; fix CONFIRMED (`25b68d2`) |
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
| Wall time at `e5bf4e4` | 10 h 19 min (2026-10-17 13:15 → 23:34 +0700) of the 72 h box | MEASURED (git) |
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

**Count at draft 2.** `main` held 1295 commits, from `931aa35` (2026-10-17 13:15 +0700) to `a3196a4`
(2026-10-18 20:16 +0700). MEASURED (`git rev-list --count main`).

**Count at draft 3.** `main` holds 2039 commits at `dcd3e13d` (2026-10-19 23:31 +0700). 739 of them came after draft
2's last commit (`68f3522e`, 2026-10-18 22:29 +0700, where `main` held 1300; the 1295 above were counted earlier, at `a3196a4`), 444 of those not merges. `docs/team/handoffs/` holds 299 handoff files.
MEASURED (`git rev-list --count`, `ls`). The tasks that landed after draft 2 include, by `Task:` trailer: wave 1
(`site-assets`, `content-hero`, `content-people-pain-commission`, `faithful-checks-rerun`, `integrate-wave-1`), wave 2
(`morph-group-integrate`, `proved-flags-ts`, `model-bug-fixes`, `part-stage`, `counts-only`, `contract-rows-from-code`,
`integrate-wave-2`), the C3 fixes (`platform-willchange`, `c3-preset-update`), the proof tasks (`indep-bridge`,
`compose-lean`, `countdown-hidden-pause`, `morph-tween-inherit`), the port gaps (`port-fonts-check`, `port-font-gaps`,
`svg-extract`, `people-o-glyph`, `asset-icons-gaps`, `port-completeness-gate`, `nav-scroll-hide-check`) and the
console and CI tasks (`ci-main-triggers`, `land-lane`, `preview-original-missing`, `latex-mathview-b2`). CONFIRMED
(git log of `main`).

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
| N1 `updateActiveStyleSheets` (A) | First: categories `blink_style`/`blink` not traced, so 0 for a wrong reason. Then 17 in one frame: 17 isolated SVG-image documents running their first style update | Slices inside `IsolatedSVGDocumentHost` counted as `trace.N1.svgImageDocument` | N1 = 0 on A in W-rest and W-measure; N0 = 0 with a positive control (4 of 4 seen) | N0/N1 counts MEASURED, runs 39044815926, 39044812879; positive control from one local debug run only (`fixtures/sheet-mutate`), not CI; same note §2 |
| `census.activeTileAreaPx`, `census.drawingAreaPx` | Pixel areas jitter in parts per million | Relative bound for pixel-area types | Both leave quarantine (largest gap 382 ppm) | MEASURED, `5879861` [EV:160] |
| Touch: BeginFrame stall | `WaitForLateScrollEvents` set a timer at virtual frame time, about 4,900 s ahead of the container clock | `--disable-features=WaitForLateScrollEvents` | 0 stalls in 9 CI jobs, all on attempt 1 | MEASURED, `25bd9f4`, `da287ff` [EV:161] |
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

### 3.2 WebKit lanes

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
| Zone baselines of the original | Gateable per zone: RenderingFrame, Composite, EventDispatch | MEASURED, run 39061324429; run concluded failure (v1 step timeout after its session JSON was written; data used, per handoff `docs/team/handoffs/zone-baselines-webkit.md:3-4`); `6b5933d` |
| Rewrite arm, `hero.countdown:strip` | 3 green runs; 86 of 95 class rows agree across them | MEASURED, runs 39104964068, 39123585294, 39123621097; `docs/team/handoffs/webkit-sim-rewrite.md:12-17` (`ad6ba7c7`) |
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

### 3.4 Waves 1 and 2 (added in draft 3)

Rev 11 replaced per-flag whole-page runs with two integration waves, each closed by one whole-page gate in both
engines and combined counts per profile [P11:1134-1143].

**Wave 1** (main `4283c5a1`, [W1]).

| Result | Value | Status, source |
|---|---|---|
| Gate, default arm, Chromium | pass: 7056 readings, 7049 pass, 7 excused, 0 bad. Excused fell from 64 to 7, because all 57 commission live-resize readings now pass | MEASURED, run 39184687325 |
| Gate, default arm, WebKit | incomplete: 6763 pass, 291 excused, 2 bad; the 2 bad readings are not-comparable, not fails (0 fail): phone-rotation stops 1 and 3, one cell | MEASURED, run 39184687325 |
| Gate, `v2-proved` arm | not run: the workflow could not name the preset; fixed by `gate-preset-input` | MEASURED, run 39185920522 |
| Base counts refreeze | 3 runs per profile; rewrite classes (det/stable/quarantined) swipe-v1 44/7/1 → 30/22/18, touch 50/1/0 → 27/26/17 (70 types); original swipe-v1 32/28/10 → 33/27/10, touch 23/32/15 → 24/35/11 | MEASURED, runs 39184638066, 39186469962, 39186477379 (swipe-v1) and 39184646781, 39186485136, 39187013275 (touch); adopted by `model-bug-fixes` [MB] |

The refreeze moved many rewrite types out of the deterministic class. The rewrite's animation and event work varies
per runner VM. INFERRED, not diagnosed [W1:80].

**Wave 2** (main `c6912998`, [W2]).

| Result | Value | Status, source |
|---|---|---|
| Gate, `v2-proved`, Chromium | fail: 248 bad readings, all `platform.stageBg` / `platform.marquee` `will-change` ("transform" in the original, "auto" in the rewrite) | MEASURED, run 39253059266 |
| Gate, default arm, Chromium | fail: the same 248 plus 1 commission probe | MEASURED, run 39253066988 |
| Gate, both arms, WebKit | incomplete, 0 fail, the same phone-rotation cell (2 readings) | MEASURED, runs 39257945326 (v2-proved arm, WebKit-only re-run) and 39253066988 (default arm) |
| Cause of the 248 | a regression on main, not a flag effect (§5.2) | CONFIRMED [C3] |
| Gate after the fix | pass in Chromium, WebKit incomplete as in wave 1 | MEASURED, run 39271987926 (full) and run 39266552780 (default arm) |
| Combined counts per profile | §4.6 | MEASURED |
| Single-flag part pages | 7 pairs, Chromium only: 20 pass, 4 model-bug, 18 unusable rows | MEASURED [W2:138] |
| G2 morph group, base against `v2-proved` | UpdateLayoutTree 2476 → 833, Paint 2338 → 1369 | MEASURED, runs 39261906990 / 39262007729 |

The part pages (`?only=<part>&stage=…`) became possible only after `driver-stage-mode` (`046320e9`). The first
part-page run was refused by the driver at its viewport gate; a static read of the driver found two more gates (mode, scroll plan) behind it (§5.2). CONFIRMED [W2], `research/notes/2026/10-19-counts-only-finding.md`.

---

## 4. Results: the proof ledger and C3

### 4.1 How to read a row

Every row of §4.3 is one ledger finding [LG] (`L<k>`). Its verdicts, premises and Lean names are the ledger's, which
cite engine lines at `chromium@f842f52` and `WebKit@862f17d`. Lean names are in `lean/Fw`; the prefix `Fw.Parts.` is
dropped. Names new in draft 3 were checked by grep at `dcd3e13d`.

| Column | Meaning |
|---|---|
| (vis) | The theorem that the visible scene of the variant equals the original's: E (equal), E-s (equal at each sample), Q (within the gate's tolerances). "none" means the ledger has no such theorem |
| (work) | The theorem that bounds the variant's work per frame, and the theorem against a claim where one exists |
| Ledger | `proved` or `partly-proved` as recorded in the ledger |
| Cr, Wk | The ledger's verdict per engine model: win (less work, no more layers), trade (less of one, more of another), no-win (equal), worse, unknown |
| Open premise | The premise of the row that is not CONFIRMED, with the ledger's status |
| RG | Research gaps the row rests on, with their status from [RG] |
| F | The flag the row runs under and where its F-result is (§4.2), or why it has none |

All verdicts are under the engine models. They are CONFIRMED as Lean results and INFERRED as engine facts until
F3/F4 (Chromium) or F5 (WebKit) check them. F3/F4 ran per flag in two rounds: whole-page runs per flag
(`model-checks`, [MC]) and single-flag part pages (wave 2, [W2]). An F row reads pass, model-bug or unusable.
Unusable means the count type is quarantined, or its class cannot decide the predicted relation. engine-check has no
WebKit lane (`laneRes_webkit`, `lean/Fw/Measure/EngineCheck.lean:605`), so every WebKit row is unusable and F5 stays
the Simulator result of §4.9. CONFIRMED [MC:46]

### 4.2 Per flag at C3: theorem pair, premises, F-results, verdict

One row per flag of the generated `v2-proved` preset at wave 2 (10 flags) plus three flags that were candidates.
"MC" is the whole-page model check per flag on swipe-v1 [MC]; "part page" is the single-flag part page of wave 2
[W2:138]. Both read pass / model-bug / unusable. "Re-judged" rows were judged again on the refrozen classes by
`model-bug-fixes` [MB]. Every count is MEASURED on Chromium CI runs; verdicts are Lean's (`fw engine-check`).

| Flag (ledger rows) | (vis) / (work) | Model Cr / Wk | Premises H1-H3, RG | MC (run) | Part page (runs base / arm) | C3 |
|---|---|---|---|---|---|---|
| nav.hitTest:elements-skip (L4) | `NavHitTestOpt.elementsSkip_visSame` (E under AL) / `elementsSkip_run_dominates` | win / win | H1-H3 not touched (no path change, INFERRED); AL from CSS has no theorem; RG4 CONFIRMED | 7 / 1 / 1 (39131395370); the model-bug row (FunctionCall `=o`, sums 2552 = 2552, frames differ) re-judged unusable (`Engine.Chromium.navHit_functionCall_rejudged`) | 5 / 0 / 4; UpdateLayoutTree 2060 → 155 (39253271676 / 39253292170) | keep |
| pain.notes:visible (L34) | `PainNotesOpt.pain_visSame` (E; premise CovOk OPEN) / `hiddenTick_lt`, `cr_idle_tick`, `wk_idle_tick` | win / win | H1-H3 not touched (INFERRED); Chromium timer rule OPEN [LG N21] | not run (`pain.notes:arm` was not on main) | 3 / 2 / 3 (39253313203 / 39257459959); both model-bug rows are a class premise: the base itself has two states in tail frames 698-713 | keep; prediction `<=o` met by equality |
| people.card:mq (L25) | `PeopleCardOpt.peopleCard_visSame` (E) / `cr_dominates`, `wk_dominates` | win / win | swipe profiles contain tail frames: OPEN | not run | 3 / 2 / 3; UpdateLayoutTree 895 → 834, the arm below in 61 frames and above in none (39253313203 / 39257496442); model-bug rows: the same tail jitter | keep |
| morph.columns:hidden-pause (L20, L42) | `HiddenPause.panel_visSame` (E while hidden) / `pause_le` | no-win / trade | RG6 residual OPEN | 3 / 0 / 1 (39131207849) | 2 / 0 / 2, arm equal to base (39259109607 / 39259146065) | keep (weak) |
| morph.countdown:hidden-pause (L10, L44) | `HiddenPause.hidden_pause_eq` (E under hsync) / `skipWrites_leE`, `unhide_leE` | win / win | hsync OPEN; RG6 residual OPEN | 3 / 0 / 1 (39131217951) | no part page | keep |
| engine.scene:hidden-pause (L45, L42) | `HiddenPause.hiddenPause_visSame` (E) / `pause_le` | win / win (L45) | RG1 OPEN | 2 / 1 / 1 (39131168588); UpdateLayoutTree `<=o` reads 1851 > 1850, still a model bug after the re-judge: a forced style pass from `getAnimations` after `removeAttribute` (`Engine.Chromium.sceneReturn_style`, `Chromium.lean:1726`) | 2 / 0 / 2, weak: the stage page has no hidden state (39260614233 / 39260841413) | keep; full gate passes every platform and engine.scene row (39271987926) |
| morph.mount:shift (L17) | `MorphMountOpt.visSame_mount` (E under HiddenBefore) / `shift_peak_lt`; against `Engine.shift_not_dominates` | trade / trade | the counting window holds the warm-up frame | 5 / 1 / 2 (39131302530); LayoutCount re-judged pass (`Engine.Chromium.mount_layoutCount_rejudged`) | 5 / 0 / 3; the arm adds FunctionCall +952, quarantined (39259991865 / 39260576409) | keep |
| morph.tween:waapi (L11) | `MorphTweenOpt.waapi_vis` (E-s) / `waapi_work_le_chromium`, `waapi_work_le_webkit` | win / win | RG2, RG3, RG3b CONFIRMED; RG8 MEASURED; RG5 lane OPEN | 3 / 1 / 2 (39131146372); FireAnimationFrame `<o` reads 1748 = 1748: swipe-v1 never pushes the morph, so the right prediction is `=o` (`Engine.Chromium.waapi_raf_eq_iff`, INFERRED cause) | no part page | keep, unmeasured per part |
| engine.scroll:batched (L1) | none (E needs premise NI) / `EngineScroll.batched_le_faithful`, `total_batch_win_iff` | no-win / unknown | RG4 CONFIRMED; the Chromium dirty-style premise INFERRED | not run | no part page (page-level by construction, G4) | keep, unmeasured per part |
| hero.countdown:strip + morph.countdown:strip (L7, L19) | `HeroCountdownOpt.strip_visSame` (E) / `strip_claim`; against `strip_backing_gt` (`HeroCountdownOpt.lean:689`) | trade / trade | H1-H3 relevant (a new layer per digit), unchecked; each layer backs its whole box INFERRED | 1 / 0 / 0 (39131314391); F5 Simulator green 3 times (§4.9) | 0 / 0 / 1: `census.layers <o` reads 12960 = 12960 in every shard, which the stable class cannot refute (39257533380 / 39259074927) | **out**: "modelled, not proved"; curated exclusion (`Preset.Gen.curated_not_mem`, `Gen.lean:118`), landed `639f9475` |
| nav.hitTest:hit-skip (L3) | `NavHitTestOpt.hitSkip_visSame` (E) / `hitSkip_run_dominates` | win / win | swipe-v1 reaches morph > 0.2: OPEN | 7 / 1 / 1 (39131343835), same FunctionCall row | none | not in the preset: shadowed by elements-skip (the generator takes the first qualifying flag per part, `Gen.lean:13`) |
| morph.panel:rest (L13) | `MorphPanelOpt.rest_visSame_E` (E under RG10) / `cr_rest_claim` | trade / win | RG10 CONFIRMED | none | none | cut: `variant-morph-panel-rest` not landed; "modelled, not proved" [C3] |
| hero.accent:steps (L23) | `HeroAccentOpt.exact_chain_vis` (E) / `cr_main_run_dominates`; against `cr_comp_step_not_le` | trade / no-win | RG5 lane phase gap | none | none | curated exclusion in `Gen.lean:61`: a trade on Chromium and no win on WebKit |

**What the strip measured.** The strip arm did more pipeline work than the base on the hero.countdown page:
UpdateLayoutTree and RecalcStyleCount 1161 → 1182, commits 1064 → 1085, `UpdateLayoutTree.elementCount` 11264 →
22445, `Layout.totalObjects` 47161 → 53433. FireAnimationFrame fell 2649 → 2130. MEASURED, runs 39257533380 /
39259074927 [C3]. The model calls the strip a trade (fewer repaints, more layers). The page shows more style and
layout work too, which the model does not predict. INFERRED: one element per digit multiplies the elements each
style pass visits.

**After the re-judge** the whole-page model checks hold two model bugs that are not class findings: morph.tween:waapi `trace.Animation.compositeFailedBits <o` (167936 = 167936; the same no-push cause as the FireAnimationFrame row, which is now unusable and whose right prediction on swipe-v1 is `=o`; the fix to the golden rows in `lean/Fw/Parts/MorphTweenOpt.lean` is open [MB]) and engine.scene
UpdateLayoutTree. Its fix is open (add the forced pass to the golden rows, or seek before `removeAttribute` in the
site, INFERRED) [MB]. The swipe-touch-v1 lane did not run in `model-checks`: the touch swipe "did not finish within
maxFrames" on the base with no flag set (runs 39131406685, 39135255809). MEASURED [MC:44-45]

### 4.3 All ledger rows with a proved pair

| L | Part: optimization | (vis) | (work) | Ledger | Cr | Wk | Open premise (status) | RG | F |
|---|---|---|---|---|---|---|---|---|---|
| L1 | engine.scroll: batched reads then writes | none; E needs premise NI (INFERRED) | `EngineScroll.batched_le_faithful`, `total_batch_win_iff` | proved | no-win | unknown | Chromium runs UpdateLayoutTree only when style is dirty at a lifecycle step: INFERRED (CI 784 vs a local no-write probe 94 per 385 frames) | RG4 CONFIRMED | `engine.scroll:batched` in `v2-proved`; no per-part run (§4.2) |
| L3 | nav.hitTest: hit-skip while morph > 0.2 | `NavHitTestOpt.hitSkip_visSame` (E) | `hitSkip_run_dominates` | proved | win | win | swipe-v1 reaches morph > 0.2: OPEN, INFERRED false, so F3 may see no skipped frame | RG4 CONFIRMED | `nav.hitTest:hit-skip`: MC 7 / 1 / 1; shadowed by elements-skip (§4.2) |
| L4 | nav.hitTest: elements-skip with an allow-list | `elementsSkip_visSame` (E under premise AL) | `elementsSkip_run_dominates` | proved | win | win | AL generated from CSS: no theorem yet (missingWhy) | RG4 CONFIRMED | `nav.hitTest:elements-skip` in `v2-proved` (§4.2) |
| L5 | nav.hitTest: write-on-change | `NavHitTest.changed_write` (E) | `writeOnChange_le`; against: `toggle_noop` | proved | no-win | no-win | none: `toggle` is a no-op when unchanged, CONFIRMED in both engines | none | no flag |
| L6 | hero.exit: threaded scroll-driven consumers | `HeroExitOpt.consumer_eq_s` (E-s under RG11) | `cr_real_tradeE`, `wk_tradeE` (trade) | partly-proved | trade | trade | WebKit ticks scroll-timeline animations each update: MEASURED, CI 39075991405 [LG N2, N7] | RG11 CONFIRMED; RG7 O3 CONFIRMED | no flag |
| L7 | hero.countdown: strip (one strip per digit) | `HeroCountdownOpt.strip_visSame` (E) | `strip_claim`; against: `strip_backing_gt` | proved | trade | trade | each layer backs its whole box: INFERRED | none | `hero.countdown:strip`: out at C3, "modelled, not proved"; F5 green 3 times (§4.2, §4.9) |
| L8 | hero.countdown: cd-roll-ca (WAAPI roll) | none (E-s at one cadence is missingWhy) | engine level only: `Engine.Chromium.compTransform_no_layout_paint` | partly-proved | win | trade | Safari time-based animations off the threaded path: OPEN (RG7 O2) | RG5 lane shim breaks it; RG7 O2 OPEN | no flag |
| L9 | hero.countdown: clock-aligned timer | `HeroCountdown.drift_skips` (not E on WebKit under timer alignment) | against: `HeroCountdownOpt.same_run_noClaim` | proved | no-win | worse | iOS 26 thermal timer grid: OPEN | none | no flag |
| L10 | hero/morph.countdown: skip face writes while hidden | `HiddenPause.hidden_pause_eq` (E) | `skipWrites_leE` | proved | win | win | which hidden forms skip paint: OPEN (RG6 residual) | RG6 residual OPEN | `morph.countdown:hidden-pause` in `v2-proved` (§4.2) |
| L11 | morph.tween: one WAAPI animation on registered `--morph` | `MorphTweenOpt.waapi_vis` (E-s) | `waapi_work_le_chromium`, `waapi_work_le_webkit`, `drop_run_dominates` | proved | win | win | timeline zero under the lane clock shim needs an offset: OPEN | RG2, RG3, RG3b CONFIRMED; RG8 MEASURED; RG5 lane OPEN | `morph.tween:waapi` in `v2-proved` (§4.2) |
| L13 | morph.panel: `blur(0)` → `none` at rest | `MorphPanelOpt.rest_visSame_E` (E under RG10) | `cr_rest_claim` with against `cr_toggle_not_le`; `wk_cross_claim` | proved | trade | win | WebKit toggle frames on the variant page: OPEN, not measured [LG N20] | RG10 CONFIRMED; check on the rewrite DOM OPEN | cut: `variant-morph-panel-rest` not landed; "modelled, not proved" [C3] |
| L16 | morph.panel: own layer during the blur fade | `fade_visSame_Q` (Q) | `wk_fade_trade`; against: `cr_fade_noClaim` | proved | no-win | trade | original panel already its own layer in the lane: OPEN | none | no flag |
| L17 | morph.mount: warm-up mount at a still moment | `MorphMountOpt.visSame_mount` (E under HiddenBefore) | `shift_peak_lt` (peak); against: `Engine.shift_not_dominates` | proved | trade | trade | the counting window holds the warm-up frame: premise | none | `morph.mount:shift` in `v2-proved` (§4.2) |
| L19 | morph.countdown: strip, reused from L7 | `HeroCountdownOpt.strip_visSame` (E) | `strip_frame_ltE`; against: `strip_backing_gt` | partly-proved | trade | trade | shared-loop scheduling delta of the TS strip: OPEN, not modelled | none | `morph.countdown:strip`: out with L7 (curated, `Gen.lean:68`) |
| L20 | morph.columns: still picture while closed | `HiddenPause.panel_visSame` (E while hidden) | `pause_le`; against: `cr_realChrome_pause_eq`, `wk_pause_eq` | partly-proved | no-win | trade | which hidden forms drop the Chromium property node: OPEN (RG6) | RG6 residual OPEN | `morph.columns:hidden-pause` in `v2-proved` (§4.2) |
| L23 | hero.accent: boil as a chain of opacity steps | `HeroAccentOpt.exact_chain_vis` (E) | `cr_main_run_dominates`; against: `cr_comp_step_not_le` | proved | trade | no-win | the Chromium original is composited: OPEN (`compositeFailedBits` decides) | RG5 lane phase gap CONFIRMED | `hero.accent:steps`: curated out (`Gen.lean:61`) |
| L25 | people.card: skip the shrink write in the c860 band | `PeopleCardOpt.peopleCard_visSame` (E) | `cr_dominates`, `wk_dominates` | proved | win | win | swipe profiles contain tail frames: OPEN | none | `people.card:mq` in `v2-proved` (§4.2) |
| L28 | people.card: pre-painted card (g0.0m) | none (pixels E per the ledger) | `Engine.shift_peak`; against: `shift_not_dominates` | partly-proved | trade | trade | WebKit paints the opacity-0 `will-change` layer: INFERRED at the pin | RG6 CONFIRMED | no flag |
| L33 | people.deck: cqi sizing | `PeopleDeckOpt.deck_vis` (E in Q) | `deck_run_dominates`; against: `Engine.WebKit.wkRounds_ge_two` | partly-proved | no-win | win | relayout link from sticky to shells: UNRESOLVED | none | no flag |
| L34 | pain.notes: arm the 3 s interval only while visible | `PainNotesOpt.pain_visSame` (E; premise CovOk OPEN) | `hiddenTick_lt`, `cr_idle_tick`, `wk_idle_tick` | proved | win | win | Chromium per-tick saving is model-only; the timer rule is OPEN [LG N21] | none | `pain.notes:visible` in `v2-proved` (§4.2) |
| L36 | commission.typing: forced-layout fix | none (E per the ledger; ResizeObserver timing INFERRED) | `EngineScroll.batched_le_faithful`, `HiddenPause.skipWrites_le` | partly-proved | win | win | read parity of the reorder: OPEN | none | no flag (`commission-resize` cut) |
| L38 | commission.typing: 2 characters per step | not E (class L, `PlatformEntries.typing_subsample`) | `HiddenPause.skipWrites_le` | proved | win | win | text writes restyle no element: INFERRED | none | a look change: proposal only (class L cut) |
| L39 | platform.sweep: band moved by `translateX` | geometry `PlatformSweep.band_eq_bgpos`; pixels Q | `Engine.comp_move_le_off`; against: `comp_move_not_le` | partly-proved | trade | trade | WebKit keeps the masked band on the compositor: UNRESOLVED in source | none | no flag |
| L42 | engine.scene: pause compositor marquees while hidden | `HiddenPause.scenePaused_imp_hiddenPause` (E) | `cr_pause_style_units`; against: `cr_realChrome_pause_eq`, `wk_pause_eq` | proved | no-win | no-win | every BeginFrame is a main frame in the lane: INFERRED (RG1) | RG1 OPEN; RG6 residual OPEN | `engine.scene:hidden-pause`, `morph.columns:hidden-pause` (§4.2) |
| L43 | engine.scene: hysteresis and idle pre-warm | `HiddenPause.hiddenPause_visSame` (E) | `flips_le_one`; against: `flips_oscillate` | partly-proved | unknown | unknown | the 800 per 10 s flap rate came from a v1 build with deferral: CONFIRMED | none | no flag |
| L44 | morph.countdown: hidden, spring keeps integrating | `HiddenPause.hidden_pause_eq` (E under hsync) | `unhide_leE`, `cr_countdown_style` | proved | win | win | hsync writes the state before paint on unhide: OPEN | none | `morph.countdown:hidden-pause` in `v2-proved` (§4.2) |
| L45 | engine.scene: pause per element, not per section | `HiddenPause.hiddenPause_visSame` (E with the original clock) | `pause_le` | partly-proved | win | win | a descendant-selector flip restyles the subtree: INFERRED | none | `engine.scene:hidden-pause` in `v2-proved`, now mounted (§4.2) |

**What the table says** (counts from [LG] by `python3 -c` over `findings`, MEASURED at `698b775`):

| Ledger status | Rows | Cr win / trade / no-win / other | Wk win / trade / no-win / other |
|---|---|---|---|
| proved | 17 | 8 / 4 / 5 / 0 | 9 / 3 / 3 / 2 (worse 1, unknown 1) |
| partly-proved | 10 | 3 / 4 / 2 / 1 (unknown) | 3 / 6 / 0 / 1 (unknown) |
| not-proved | 14 | 8 / 2 / 3 / 1 (worse) | 7 / 5 / 2 / 0 |
| not-tried | 4 | 0 / 1 / 3 / 0 | 1 / 2 / 1 / 0 |

- Proved with a win in both engine models: 8 rows, L3, L4, L10, L11, L25, L34, L38, L44. MEASURED [LG].
- L38 changes the look (class L), so it is a proposal, not a flag. CONFIRMED [P10:1073].
- L25 and L34 got flags after draft 2 (`people.card:mq`, `pain.notes:visible`, `proved-flags-ts`). CONFIRMED
  (preset JSON at `c6912998`).
- At C3, 6 of these 8 rows run under a `v2-proved` flag (L38 is a proposal; L3 is shadowed by L4). Four more flags rest on rows that
  are not a win in both models: L1 (`engine.scroll:batched`), L17 (`morph.mount:shift`) and L20/L42
  (`morph.columns:hidden-pause`). The ninth flag, `engine.scene:hidden-pause`, rests on L45 (win in both models, partly-proved) and L42 (proved, no-win in both). CONFIRMED (preset at `639f9475`). The generator admits a flag on a
  proved pair, not on a win in both models; an engine-win field is a follow-up (`Gen.lean:61-63`). CONFIRMED
- Proved but not a win in both models: L1, L5, L7, L9, L13, L16, L17, L23, L42. Each is a negative or mixed result
  with its mechanism in the ledger. MEASURED [LG].

### 4.4 Candidates without a proved pair

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
holds in Chromium and fails intermittently in WebKit. MEASURED [LG L46, L47]. Both were premises of the landed task
`gate-settle` (§7).

### 4.5 Independent and coupled parts; what composes

**Answer.** The 9 flags of `v2-proved` all sit on coupled parts. Their combined saving is MEASURED, but which flag
saves how much is INFERRED, except `morph.mount:shift` (F6 below measures one single-flag arm per flag; only that flag moves a decided cell past the margin). Unit counts add across frames; pass counts do not. So a passes-type win stays a
part-local, model-only claim.

| Result | Lean name, file:line at `dcd3e13d` | Status |
|---|---|---|
| Work in units adds over appended frames | `Fw.Engine.frameWork_append_units` (`Compose.lean:217`) | CONFIRMED (proved) |
| Pass counts are not compositional: two changes can each add no pass and still add one together | `passes_not_compositional` (`Compose.lean:137`), `frame_le_append_passes_fails` (`Compose.lean:194`) | CONFIRMED (proved) |
| Swapping one part's variant changes only its own work, given an abstract `Indep` | `lego_swap_sound` (`Compose.lean:371`), `lego_swap_units` (`Compose.lean:411`) | CONFIRMED (proved under `Indep`) |
| The contract's `Independent P Q` does not imply that `Indep`: 298 pairs of parts sit on a dependency chain | `Fw.Parts.Bridge.chainPairs_code_iff` (`Bridge.lean:582`), count 298 by `chainPairs_code_length` (`Bridge.lean:596`, `4336d7f1`) | CONFIRMED (proved) |
| Adopted rule: `Flow` / `Reach` over the part specs, with premise `FlowSound` (the specs list every channel) | `flow_of_isolated` (`Bridge.lean:125`) | proved; `FlowSound` OPEN |
| Isolated parts under that rule: 12 (commission.typing, hero.deck, nav.langMenu, overlays.drawer, overlays.signup, people, people.carousel, platform.entries, platform.glint, platform.marquee, platform.stageBg, platform.sweep) | `isolated_code` (`Bridge.lean:495`) | CONFIRMED (proved by `decide`) |
| No `v2-proved` flag part is in that list | compare the list with §4.2 | CONFIRMED |
| Pass counts of appended frames are bounded by the sum of the parts | `passes_append_le` (`Bridge.lean:246`) | CONFIRMED (proved) |

**Coupled groups** (from the part contract, [LP:41-45]): G1 hero threshold (hero.exit, people.card, pain, nav,
nav.hitTest), G2 morph (morph.mount → morph.tween → morph.panel → morph.countdown, morph.columns), G3 the page-offset
chain, G4 cross-cutting (engine.scroll, engine.scene), G5 commission ↔ resize. The `v2-proved` flags fall in G1
(nav.hitTest, pain.notes, people.card), G2 (the four morph flags) and G4 (the two engine flags). CONFIRMED [LP]

**The totals pilot** (wave 2, descriptive, not F6) shows the limit in numbers. On swipe-v1 the combined run cut
UpdateLayoutTree by 1011, while the 7 single-flag part pages summed to −1944, a residual of +933. Per frame the style
family reads −2.01 combined against −1.98 for the sum, within 10 %. `census.layers` rose by 1054 combined against +1
summed over the parts. MEASURED, runs 39253166643 / 39253172750 and the part pages of §4.2 [W2:190-203]. The part
pages run other trajectories (727-1329 frames against 503), so totals cannot add; per-frame rates came close on the
style family. INFERRED. The layer rise comes from something no part page holds: engine.scroll, morph.tween, or flags
acting together. INFERRED [W2:202]. Superseded by F6 below: on the full page the single `morph.mount:shift` arm adds +1,056 layers by itself, and the other 8 add 0 to 3 each (MEASURED, `research/notes/2026/10-20-compose-check.md`)

**Composition lesson.** Prove composition before planning a "one combined run stands for all flags" step. The rev-11
plan assumed it; the bridge proof then showed that no flag part is isolated. The combined run is still the cheaper
measurement (§4.6). It answers "does the preset save work". Single-flag arms on the same base and trajectory (the F6 set below) give a delta per flag, but only `morph.mount:shift` clears the margin, so "which flag saved it" otherwise stays with the per-part pages and is INFERRED.

**F6.** At C3: "statement landed, run after C3" [C3]; it ran after C3 (F6 result below). `compose-check` runs F6 per (part, stage, zone) on units-type counts
[P11:1138].

**F6 result** (`compose-check`, landed `ac087e08`; research/notes/2026/10-20-compose-check.md; Lean
`Fw.Measure.Compose.verdict`). One coherent set on one commit (ci/f6-set at `575e3087`, chromium-counts, swipe-v1,
2 runs per side, frozen image 39049264131): base 39295469515 (all faithful), combined 39295484486 (the 9 v2-proved
flags), and one single-flag arm per flag (39295496884 to 39295598591). Whole run, unit types, MEASURED:

| stage | count type | combined Δ | sum of single Δ | residual | margin | verdict |
|---|---|---|---|---|---|---|
| paint, raster | raster.invalidationAreaPx | -563,778 | -563,778 | 0 | 0 | composes |
| paint, raster | raster.invalidationRects | +790 | +790 | 0 | 0 | composes |
| comp | census.layers | +1,056 | +1,066 | -10 | 60 | composes |
| script | trace.FireAnimationFrame | -370 | -369 | -1 | none | not comparable (quarantined) |
| script | trace.FunctionCall | +38 | +43 | -5 | none | not comparable (quarantined) |
| layout | trace.Layout.dirtyObjects | -414 | -410 | -4 | none | not comparable (quarantined) |

Pass types are reported, not judged: `trace.UpdateLayoutTree` -1,011 against a sum of -1,012, `trace.Paint` -274
against -271. No cell is coupled. The 5 decided cells are informative, but only `morph.mount:shift` moves them past the
margin, so they test one flag against eight that do nothing there. The cells where several flags add up are the
quarantined ones, where no margin exists. None of the 96 zone cells is decided (60 have no per-zone margin, 36 are
quarantined). Flag independence (`lego_swap_units`) is not checked. Answer: the measured deltas add up wherever they can
be judged, and nearly add up where they cannot; per-flag attribution beyond `morph.mount:shift` stays INFERRED.

### 4.6 Runs per flag, before and after rev 11

**Answer.** Rev 10 checked each flag with its own whole-page counts run. Rev 11 checks all flags with one combined
run per profile, plus a short single-flag page per part. The before round took 406 min of run wall for 9 flags on
one profile; the after round took 247 min for 7 parts plus both profiles and the G2 group. MEASURED (run walls from
`gh run list`, created to updated, queue included).

| Round | Runs | What they cover | Wall per run | Run wall sum | Source |
|---|---|---|---|---|---|
| Before: `model-checks` (rev 10), 10 runs at once | base 39130874266 + 9 flag runs | 9 flags, swipe-v1 only (the touch lane failed on the base) | 39.0-44.9 min | 406 min | [MC] |
| After: combined counts (wave 2) | 39253166643, 39253172750, 39253177864, 39253184136 | all 10 flags, both profiles, base and preset | 22.0-27.7 min (started with 2 gates and 3 part pages) | 100 min | [W2] |
| After: single-flag part pages | 13 runs (§4.2) | 7 parts | 4.2-9.4 min; 3 runs queued behind the gates took 27.1-27.6 min | 138 min | [W2] |
| After: G2 morph group | 39261906990, 39262007729 | G2 base against the preset | 4.8, 4.3 min | 9 min | [W2] |

**Combined counts per profile** (10-flag preset including hero.countdown:strip; 3 of 3 shards each):

| Count type (class) | swipe-v1 base → preset | swipe-touch-v1 base → preset |
|---|---|---|
| RecalcStyleCount (deterministic) | 1832 → 821 (−1011) | 1864 → 856 (−1008) |
| UpdateLayoutTree (deterministic) | 1849 → 838 | 1881 → 873 |
| ScheduleStyleRecalculation (deterministic) | 1865 → 855 | 1897 → 890 |
| FireAnimationFrame (quarantined) | 2057 → 1454 | 2112 → 1503 |
| cc.Commit | 503 → 503 | 523 → 520 |
| census.layers (stable) | +1054 | +1119 |
| census.drawingAreaPx (stable) | +8.8e7 | +9.7e7 |

MEASURED, runs 39253166643 / 39253172750 (swipe-v1) and 39253177864 / 39253184136 (touch) [W2:91-101]. The preset
JSON at `c6912998` lists `"hero.countdown":"strip"` (CONFIRMED). **Re-run with the 9-flag preset** (strip out, `639f9475`,
same frozen image 39049264131, 3 shards per arm): swipe-v1 1832 -> 821 (all shards agree; runs 39292304129 /
39292310716); swipe-touch-v1 1864 -> 856 or 857 (runs 39292317241 / 39292323514). MEASURED. So dropping the strip
changed no whole-page recalc count. One new fact: the 9-flag touch arm is not deterministic by one recalc. Shards r1
and r3 count 2 recalcs at frame 498 of 531, shard r2 counts 1 (MEASURED); the 10-flag run counted 856 in 3 of 3. Its
cause is not examined (§7).

**Per flag, before and after.**

| Flag | Before: model check, swipe-v1 (wall) | After: part page base / arm (wall) | Main reading after |
|---|---|---|---|
| nav.hitTest:elements-skip | 39131395370 (39.1 min) | 39253271676 / 39253292170 (27.6 / 27.5 min, queued) | UpdateLayoutTree 2060 → 155 |
| pain.notes:visible | none | 39253313203 / 39257459959 (27.1 / 4.2 min) | equal to base |
| people.card:mq | none | 39253313203 / 39257496442 (27.1 / 4.6 min) | UpdateLayoutTree 895 → 834 |
| morph.columns:hidden-pause | 39131207849 (40.5 min) | 39259109607 / 39259146065 (5.3 / 5.3 min) | equal to base |
| morph.countdown:hidden-pause | 39131217951 (40.4 min) | none | none |
| engine.scene:hidden-pause | 39131168588 (41.2 min) | 39260614233 / 39260841413 (9.4 attempt 2 / 4.2 min) | equal to base |
| morph.mount:shift | 39131302530 (39.5 min) | 39259991865 / 39260576409 (4.5 / 8.8 min attempt 2) | FunctionCall +952 (quarantined) |
| morph.tween:waapi | 39131146372 (42.0 min) | none | none |
| engine.scroll:batched | none | none | none |
| hero.countdown:strip (out) | 39131314391 (39.3 min) | 39257533380 / 39259074927 (4.5 / 4.7 min) | more work (§4.2) |

With a free queue a whole-page counts run of both arms took 7.3 and 8.0 min (runs 39146329183, 39146332555) and a
part page 4.2-4.7 min. MEASURED. So most of the 39-45 min walls of the model checks was waiting: they ran 10 at
once on a shared runner pool. INFERRED

### 4.7 Premises H1-H3 and research gaps RG1-RG11

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

The check for H1-H3 was `pixel-spot` (Chromium only), cut (§7).

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

### 4.8 Math review state

| Measure | Value | Status, source |
|---|---|---|
| Round 14 at `f9b30af`: reviewed / agree / disagree | 2357 / 2266 / 91 | MEASURED [R14] counts table |
| `Fw.Parts.*` modules in round 14 (21 modules) | 454 reviewed, 451 agree, 3 disagree | MEASURED [R14] per-module table |
| Round 14 fixes | all 91 fixed in docstrings only, no Lean statement changed | CONFIRMED, `3c2a1de`; `docs/team/handoffs/math-final.md` |
| Math view after the fixes (main `c2410d2`) | 5109 agree, 0 disagree, 517 stale, 1373 pending | MEASURED, `docs/team/handoffs/math-final.md` |
| Held back from round 14 | `Gate.*`, `Plan.*`, `Console*`, `Engine*` (1389 entries) | CONFIRMED, same handoff |

C4 asks for 0 disagree and 0 stale [P11:1052]. At round 14 the view had 0 disagree and 517 stale, and the engine
model modules `Fw.Engine.*` that every (work) theorem uses were not in the round. On 2026-10-19 16:39 +0700 the user
removed the math review step and asked for no LaTeX in new Lean (`4e55971c`). `latex-mathview-b2` (landed
`de6e4073`) retired the math view build. So no round 15 ran, and the C4 math criterion is not met as written (§7).
CONFIRMED (commits); the round-14 numbers above are the last MEASURED state.

### 4.9 Measured inputs

| Result | Value | Status, source |
|---|---|---|
| Chromium zone baselines, 4 (profile, arm) pairs, 3 shards each (zone-baseline table, 51 rewrite types; differs from the frozen table in §3.1, which lists swipe-v1 R as 44/7/1 of 52) | det/stable/quarantined: swipe-v1 A 32/28/10, R 44/7/0; touch A 23/32/15, R 50/1/0; 0 unlisted, detDrift empty | MEASURED, `f4c6ea5`, runs 39048702153, 39050423094 [BL] |
| WebKit zone baselines of the original | gateable per zone: RenderingFrame, Composite, EventDispatch | MEASURED, `6b5933d`, run 39061324429; run concluded failure (v1 step timeout after its session JSON was written; data used, per handoff `docs/team/handoffs/zone-baselines-webkit.md:3-4`) |
| Touch race | R deterministic in 4 touch types; A stable; 0 wedges | MEASURED, `c38088e` |
| N0 / N1 neutrality reads on A (Chromium) | 0 and 0 after the SVG-document split | MEASURED, `f90c08f` |
| Engine premises in the lane (17 untested) | 5 held, 7 refuted, 5 not measurable | MEASURED, run 39088367495; `docs/team/handoffs/engine-premise-measure.md` |
| Model fixes from those runs | `morph.panel` own layer: Chromium trade → no-win; `blur(0)` → `none`: WebKit trade → win | MEASURED, run 39088367495 [LG N18, N19] |
| WebKit Simulator on the rewrite, `hero.countdown:strip` | 3 green runs (39104964068, 39123585294, 39123621097); 86 of 95 class rows agree across them | MEASURED, `docs/team/handoffs/webkit-sim-rewrite.md` |
| F0-F2 on the fixture | no result through `fw engine-check` yet: no fixture artifact was fed to it (open item of the task) | CONFIRMED, `docs/team/handoffs/engine-ci-check.md` |
| Breakpoint gate, pilot parts | 4 of 4 pass, both engines | MEASURED, `2566949` |
| Breakpoint gate settle wait | 212.4 → 65.5 job-min with a 60-frame settle budget; per-cell verdicts equal | MEASURED, `088315d`; `research/notes/2026/10-18-gate-shard-balance.md` |
| Gaps lane | Chromium 8/8 pass; WebKit 8/8 unreachable as predicted | MEASURED, `0d561fa` |
| Faithful bands (PL5), first re-run after `page-root-clip` | rewrite FAIL in all 6 zones; off-band cells swipe-v1 y04000 26 of 44, y04500 14 of 43, tail 14 of 38; touch 26 of 40, 15 of 41, 15 of 41; control A' passes every zone with 0 failing cells | MEASURED, runs 39146329183, 39146332555 at `b8c051ab` [FR:27-36] |
| Faithful bands under the adopted wave-1 classes | rewrite FAIL in all 6 zones; off-band cells swipe-v1 27 / 14 / 14, touch 28 / 14 / 10 (y04000 / y04500 / tail); control passes | MEASURED, wave-1 runs 39184638066, 39184646781; [MB:6-8] |
| What stays off band | layout work only the rewrite does (LayoutCount 0 vs 24 in y04000), fewer rAF callbacks (204 vs 154 on swipe-v1), the compositor census (`census.layers` 3188 vs 3662), `raster.invalidationRects` 571 vs 103 | MEASURED [FR:39-46] |
| Pairs scored only when comparable | `Fw.Faithful.comparable` refuses a pair whose viewport, profile or preset differ, before any cell is scored (`comparable_iff`, `refusal_sound`) | CONFIRMED (proved) [FR:48-58] |
| WebKit gate, both waves | 0 fail, 291 excused, incomplete only by the phone-rotation cell (2 readings) | MEASURED, runs 39184687325, 39257945326, 39271987926, 39282664077 |

### 4.10 engine.scroll:unthrottle: lifting Mobile Safari's 100 ms scroll throttle (task unthrottle-preset)

Mobile Safari holds visible-rect updates to 100 ms while the toolbar collapses, unless the page reports a main-thread
scroll-driven animation (`WKWebViewIOS.mm:3256-3268`, `AnimationTimelinesController.cpp:267-279` @862f17d). The flag adds one
absolute 1 px, transparent element that animates a registered custom property on the root scroll timeline, inside
`@supports (animation-timeline: scroll())` and `@media (pointer: coarse)`. CONFIRMED by source, PROVED in Lean
(`Fw.Parts.EngineScrollUnthrottle`: `reported_iff`, `lifted_when_supported`, `visible_withFlag`, `guard_keeps_ios`,
`guard_fine_noop`, `lift_anim_position_free`).

| Evidence | Value | Status, source |
|---|---|---|
| Phone, real iPhone, one person, one session, throttle-lift diagnostic against the faithful rewrite | hero band runs 90 to 2 and 28 to 0-1 per viewport height; hero felt marks 12 to 0; end-of-page slow frames 2.46-6.56 to 0.00-1.17 per 100 and felt marks 12-14 to 3-5 | MEASURED, `results/phone/2026-10-24-throttle-lift/summary.md`; the shipped text is not itself recorded on the phone (INFERRED same mechanism) |
| Simulator touch lane, shipped text, rewrite against unthrottle | 19 band runs in 1600 exit frames (one usable rewrite pass) against 0 in 6330 (4 passes); verdict `lifted` | MEASURED, run 40078755847 (job 1 failed on its VM) |
| Chromium counts, 3 x 575 swipe frames, absolute plus guard | +0 compositor layers in 575, 573, 572 frames (position fixed gave +2); +1 element restyled in 532, 514, 531 frames; no extra layout or style recalc | MEASURED, run 40078781031 against push run 40068835905 (older sha) |
| Trajectory probe, Chromium hero and morph; WebKit hero | pass | MEASURED, runs 40078755889 and 40080296257 |
| Trajectory probe, WebKit morph | no verdict (Mac WebKit coverage units at the two desktop widths, where the element is inactive) | MEASURED, run 40080296257; cause INFERRED |
| Breakpoint gate on the shipped text, `fw=engine.scroll:unthrottle` (the preset has no member) | Chromium and Playwright WebKit, failing-items table empty on both | MEASURED, run 40083527306 |
| Power cost of leaving the throttle (WebKit measured up to 2 percent) | not measured | open |

Result: the ledger row is `proved`; `v2-proved` stays empty because its WebKit morph trajectory cell has no verdict for any
flag. The first text paid
2 compositor layers on Chromium for `position: fixed`, and the move to `absolute` was decided by a count, not by a bound.
Note `research/notes/2026/10-2x-throttle-lift-ship.md` section 6.

### 4.11 Phone review of 2026-10-24 and the preset delta (task look-decisions-1024)

On the real iPhone the user said that `?fw=hero.exit:threaded` and `?fw=engine.scroll:throttle-lift` both look the same
as the original, and that the accent animation looks different from the original. CONFIRMED (user words, task
look-decisions-1024). Lean records this in `Fw.Preset.Gen.lookDecisions`:

| Flag | Decision | Basis |
|---|---|---|
| `hero.exit:threaded` | accepted 2026-10-24 (same look on the iPhone) | the user's words |
| `hero.accent:draw-nolayout-full` | rejected 2026-10-25 (row of task accent-look-refused, reused) | the user's words |
| `hero.accent:draw-nolayout` | rejected 2026-10-24 | same clip-path wipe as `draw-nolayout-full` (INFERRED; never shown alone) |

`Gen.run --check` throws unless every decision agrees with the ledger row's `userDecision`, so `ledgerDisagreements` is
empty at this commit. The same run throws on a stale decision or on a refused flag inside the preset.
`decisionKept_of_accepted` keeps an acceptance of a registered flag that is not class L.
`engine.scroll:throttle-lift` gets no decision row, because it is a diagnostic flag and never enters a preset.

Phone numbers (real iPhone, one person, one session, viewport h 775, faithful rewrite against the flag):

| Flag | Hero felt marks | Hero-exit band runs | Status, source |
|---|---|---|---|
| `hero.exit:threaded` | 12 → 0 | no data (the variant clears the inline value the recorder reads) | MEASURED, `results/phone/2026-10-24-hero-exit-threaded/summary.md` |
| `engine.scroll:throttle-lift` | 12 → 0 | 90 → 2 | MEASURED, `results/phone/2026-10-24-throttle-lift/summary.md` |

Lean decides whether `hero.exit:threaded` may enter v2-proved (`Gen.entry`, `entryReqs`). The answer is not yet. Each requirement and its evidence is in the `entry` field of the flag's row in
`packages/contracts/golden/preset/v2-proved.decisions.jsonl`:

| Requirement | Met | Evidence |
|---|---|---|
| proofs | no | `HeroExitOpt.consumer_eq_s` (E-s under RG11) and the trade pair `cr_real_tradeE`, `wk_tradeE`. The ledger row is partly-proved and `Gen.linkTable` has no link (`threaded_proofs_unmet`) |
| trajectory gate, Chromium | no | run 40156078840: hero fail, morph pass. PathPix runs 39924527942 and 39929556147 grade every valid P cell L |
| trajectory gate, WebKit | no | run 40156078840: hero fail on Linux WebKit and on macOS WebKit, morph pass on macOS WebKit; the PathPix cells are L |
| look decision | yes | accepted on the iPhone (`threaded_look_met`) |
| q6 "same scroll offset" | no | open. `Fw.Engine.PathPremises.c3o`/`c3v` are hypotheses, and `HeroExitOpt` does not model which scroll offset the compositor shows (`q6_open`) |

Trajectory run 40156078840 walked `?fw=hero.exit:threaded` at main `fbca417` against the faithful arm, at widths 390,
640, 641 and 1280 (inputs read back from its `trajectory-inputs` artifact). `Fw.Preset.Gen.record` stored its five rows in
`packages/contracts/golden/preset/v2-proved.trajectory.jsonl`, and `Gen.run` wrote the decision row from them. MEASURED,
run 40156078840:

| Engine | Hero path | New content units | Morph path |
|---|---|---|---|
| Chromium | fail | 25 | pass (0 new; 43 undecided) |
| Linux WebKit | fail | 40 | not walked (hero only) |
| macOS WebKit | fail | 40 | pass (0 new; 128 red in both arms, 4 undecided) |

On each engine the new units sit at the same node properties: `hero.orbit.card` opacity and translate at 390 px, and
`hero.deck.card` opacity at 640, 641 and 1280 px (5 of 10 units each on Chromium, 8 of 10 on WebKit, all `apart`).
A failing run of the flag alone fails its cell (`tcell_own_fail`), so the trajectory verdict is `falsified: trajectory`
and both gate requirements block (`gate_blocked_of_own_fail`). On the morph path, pass means only that the gate found
no new failing unit; the path is not clean. The probe fails the hero path on all three engines, while the user saw the
same look on the iPhone. One possible cause: the original's JS writer shows a value one scroll event late, while
the scroll-driven animation follows the current offset. That is the question q6 asks (INFERRED, not tested). Task
hero-exit-q6 owns q6 and the proofs link.

Theorems: `threaded_not_yet` (q6 and proofs block, the look requirement does not), `gate_blocked_of_own_fail`, `entry_enter_iff`,
`entry_notYet_of_unmet`, and `ok_of_enter` (a flag that enters, is registered as optimized and is not class L
satisfies the preset's `ok`). Preset delta: none. v2-proved stays `{engine.scroll:unthrottle}` (CONFIRMED,
`packages/contracts/golden/preset/v2-proved.json`), with 0 flags added and 0 removed.

---

## 5. Findings and negative results

Each item gives what was seen, the mechanism and the lesson.

### 5.1 Of 2026-10-18 (from draft 2)

- `gate-shard-balance`: no shard plan lowers the gate's wall time. A longest-processing-time-first (LPT) plan over measured costs costs the same as a count-balanced deal (28.5-28.6 against 27.5-28.1 job-min), and the 5.6-6.1 min wall is the unsplittable WebKit desktop sweep plus setup. MEASURED, runs 39125771186, 39125776112, 39126934987, 39126939905 (`research/notes/2026/10-18-gate-shard-balance.md`).
- `wktr-fixture-speed`: its claim that 12 WKTR class changes between runs are run-to-run variance is UNEXPLAINED. 9 of the 12 keys also change class among 8 other green runs; 3 never do. MEASURED [LG N22]; Lean `Fw.Measure.WktrVariance`.
- The Chromium timer rule is OPEN: whether an empty timer task runs PrePaint. The engine-premises step meant to test it ran the clock shim's callback inside `Runtime.evaluate`, not a native timer task, so the Chromium half of L34 is proved in the model only. MEASURED, run 39124427211 [LG N21].

### 5.2 Of 2026-10-19

**Platform `will-change` regression.** The wave-2 gate failed 248 Chromium readings on platform.stageBg and
platform.marquee: the original read `will-change: transform`, the rewrite `auto`. MEASURED, run 39253059266 [W2].
Mechanism: `4d724e12` (2026-10-18) deleted `will-change: transform` from the port's `.artboard` and `.track`. At that
time the original read `auto` too, because the port set no scene attribute. `8276822d` (platform-scene-faithful)
added `data-fw-scene`, and from then on the original read `transform` while the scene runs. The fix restored both
declarations (landed `7e5cff2f`); the platform.stageBg and platform.marquee rows of the default arm then passed in both engines (the WebKit verdict stays incomplete by the phone-rotation cell). CONFIRMED by diff and MEASURED, run
39266552780 (`docs/team/handoffs/platform-willchange.md`). Lesson: a gate fix that deletes a declaration to match a
reading is a claim about the reading's context. It needs a test that fails when the context changes.

**The narrowed-run difference.** A gate run narrowed to the platform part ids failed platform.stageBg and
platform.marquee in Chromium again (artboard `will-change` 160 readings, track 40; original running, port paused) and
platform.glint on 1 of 14 desktop probes. The full run on the same branch passed. MEASURED, runs 39271938577
(narrowed) and 39271987926 (full). INFERRED cause: `engine.scene:hidden-pause` pauses the platform scene while the
section is off-viewport, and the original keeps it running (`docs/team/handoffs/platform-willchange.md`). Why the full
run does not show it is not known. The merge job of the narrowed run also failed on an `elan` SSL download, and 84 of 124 probes were not in its scope.
C3 cites only un-narrowed runs; the difference is a follow-up (§7). Lesson: a narrowed gate is a different
experiment, not a faster copy; decide on the full run.

**More pipeline work under hero.countdown:strip.** The strip arm raised UpdateLayoutTree / RecalcStyleCount
1161 → 1182, commits 1064 → 1085, `UpdateLayoutTree.elementCount` 11264 → 22445 and `Layout.totalObjects`
47161 → 53433, and lowered FireAnimationFrame 2649 → 2130. MEASURED, runs 39257533380 / 39259074927. Its only
prediction (`census.layers` below the original) read 12960 = 12960, which a stable class cannot refute. The model
treats each digit strip as a layer and counts no extra style work. INFERRED mechanism: one element per digit
doubles the elements each style pass visits. The flag left `v2-proved` as "modelled, not proved" [C3]. Lesson: a
"trade" in the model needs a row for every stage the variant touches, or the check has nothing to falsify.

**Preview CSP.** The console's preview showed the original without its scripts. The proxy's `rewriteBody` changed
root paths inside the inline boot script, so its sha256 no longer matched the page's hash-only CSP and hydration
never ran. CONFIRMED (the user's DevTools capture, reproduced by a test). Fix: inline script bodies are never
rewritten; module scripts get a 302; the manifest link gets `crossorigin` (INFERRED from the spec, not measured).
CI loads the snapshot directly and was not affected. `research/notes/2026/10-19-preview-original.md`, landed
`55a42117`. The rewrite is a TS stand-in with no Lean rule. Lesson: a proxy that edits a page must treat every hashed
or signed byte as read-only.

**Fonts.** Buttons drew Arial (`-webkit-standard` in WebKit) instead of Google Sans, and countdown digits and
morph.panel text drew `system-ui`. Mechanism: no form-control `font: inherit` rule, and the MUI theme's
`fontFamily` was `system-ui`. Fix: a form-control inherit rule in `reset.css` and the theme font set to the
original's body stack. After the fix: 0 font changes in every probe in both engines (run 39262636419); assets 0
missing of 111 and SVG 31 of 31 (run 39254252262). MEASURED (`docs/team/handoffs/port-font-gaps.md`). The earlier
visual-diff claim of "about 25 flips" was wrong: 63 of 496 cells hold no single verdict over 3 runs (29 Chromium,
34 WebKit). MEASURED (`docs/team/handoffs/port-fonts-check.md:22`). Left: the people.o "o" moves to people.card in
every probe (ownership), and time-driven leaves stay unpaired. Lesson: the browser default for form controls is not
the page font; a port check must compare families leaf by leaf.

**Nav hide.** In the original the nav hides while the people section is stuck on desktop. The port never hid it.
MEASURED, run 39250254933. Mechanism: the nav's default selectors were the original's class names, which the port
DOM does not have, so the stuck test was always false. Fix `b5bbbd3f` wires them to the port's `data-fw` hooks.
After the fix, 7 runs per engine show the nav hide at 861, 1280, 1440 and 1920 px and never at 860, in both arms.
MEASURED (`research/notes/2026/10-19-nav-scroll-hide.md`, check landed `fd71ee28`). Left: Chromium edges move by
1 px (one 16 px step at 1920), the transform starts 0-3 frames after the class flip, and a WebKit race after a
programmatic jump leaves either arm wrong for up to 700 ms. The visual-diff server also served CSS and JS as
`application/octet-stream` (fixed). The analysis is a TS stand-in. Lesson: a selector copied from the original is a
dependency on the original's DOM; derive it from the port's own hooks.

**Part pages refused three times.** The first part-page counts run was refused by the driver at three gates: the
viewport (`pinEnv` reported 1280x800), the mode (client-render, not hydrate) and the scroll (pinned `scrollY`).
MEASURED for the viewport gate, run 39189237058; the mode gate is CONFIRMED by a static read of the driver against the stage code and the scroll gate is INFERRED, not run (`research/notes/2026/10-19-counts-only-finding.md:17-20`). Fixed by `driver-stage-mode` (`046320e9`). Lesson: list every gate of the driver before
the first dispatch (`research/notes/2026/10-19-counts-only-finding.md`).

**Infra.** `setup-lean` failed on TLS downloads in runs 39260031147 and 39260070268, and on an `elan` SSL download in
the merge job of 39271938577. The commission probe failed in 2 of 3 default-arm gate runs and in 0 of 2 `v2-proved`
runs. MEASURED [W2]. Cause not isolated; INFERRED a live-resize transient of the commission part (research/notes/2026/10-19-integrate-wave-2.md:84).

---

## 6. What the loop cost

### 6.1 CI minutes

GitHub billing for this repo in October (the repo's first CI run was 2026-10-17 11:19 UTC, so this is one day).
Source: GitHub billing usage read by the user with `gh api` on 2026-10-17, relayed in the report-draft brief; recorded in
`docs/team/improvements/2026-10-17.md:552-553` (`d0a15bd`). MEASURED (by the user).

| Runner | Minutes | Charge |
|---|---|---|
| Linux ARM | 2,490 | free (public repo) |
| macOS 3-core (standard) | 919 | free (public repo) |
| macOS XLarge | 19.6 | **$2.00**, the only charge |

The XLarge minutes came from the `sim-speed` probe's xl arm; that arm was removed after the user decided never to pay
for runners (`2a29286`). INFERRED (the only workflow that used `xcode-27-xlarge`). The list price is $0.102/min,
CONFIRMED `research/notes/2026/10-17-macos-rent.md:9`; 19.6 × 0.102 = $2.00.

Agents cannot read billing: `gh api` stays denied (CLAUDE.md, Upstream source). This table is the only billing
read until the user reads it again. CONFIRMED (`d0a15bd`).

### 6.2 Runs, failures and stray runs (to 2026-10-17 16:35 UTC)

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

### 6.3 Local incidents (this Mac)

| Incident | Effect | Status, source |
|---|---|---|
| Machine sleep looked like 14-26 min "API stalls" across 7 agents | fixed with one `caffeinate -w <session pid>` | CONFIRMED by `pmset` [CU:48-51] |
| An agent ran `pkill -f "Google Chrome"` | may have closed the user's browser; new kill-by-PID rule | CONFIRMED [CU:232-233] |
| An agent wrote copies of 3 files into the main checkout | removed before the merge | CONFIRMED [CU:301-302] |
| Simulator re-boot every ~2 min and 4 parallel full Lean rebuilds | CPU idle 0 %; load1 ~430 | MEASURED [CU:104-117, 168-171] |
| Local mutation pass (625 Lean builds) | load ~500; moved to CI | MEASURED [CU:482-484] |
| Merge-only test and typecheck breaks | several; test scripts now typecheck first | CONFIRMED, `bc4c46d`, `7fcbbfa`, `aa8d961` |

### 6.4 Model tokens

**Answer.** About $2.2k at list price from the start to C3, against v1's about $11.4k [P10:115]. Tokens are
MEASURED; dollars are INFERRED.

There is still no `fw usage` command at `dcd3e13d` (the `fw` usage text lists none). The Lean op `ops.usage` exists
(`lean/Fw/Ops/Wire.lean:21`, golden `packages/contracts/golden/ops/ops.usage.jsonl`); the CLI glue and the price
table are missing. CONFIRMED. So the totals below come from a one-off script, not from `fw usage`.

**Method.** A scratch Python script read every session transcript file (JSONL, 1448 files, local only, not in git),
kept assistant messages with a `usage` block, counted each `message.id` once (63,622 requests) and put each request
in a checkpoint window by its timestamp. The windows end at the checkpoint deadlines (C1 2026-10-18 11:15, C2
23:15, C3 2026-10-19 23:15 +0700), so they are a proxy for milestones (INFERRED mapping). Prices are list prices per
million tokens (input / 5-min cache write / 1-h cache write / cache read / output): Opus 5.5 4 / 5 / 8 / 0.20 / 20,
Sonnet 5.5 2 / 2.5 / 4 / 0.10 / 10, Haiku 5.5 0.10 / 0.125 / 0.2 / 0.01 / 0.5 (requests over 100k input at the
higher tier), Fable 5.1 10 / 12.5 / 20 / 0.25 / 50. CONFIRMED `research/notes/2026/10-17-token-usage-facts.md:134-142`.
Long-context pricing and any plan discount are not modelled.

| Window (+0700) | Requests | Opus | Sonnet | Fable | Haiku | List price |
|---|---|---|---|---|---|---|
| before 2026-10-17 13:15 (setup) | 1,105 | $82 | 0 | 0 | 0 | $82 |
| start → C1 (2026-10-18 11:15) | 28,855 | $743 | $279 | $17 | $0 | $1,040 |
| C1 → C2 (2026-10-18 23:15) | 18,855 | $545 | $70 | $10 | $0 | $625 |
| C2 → C3 (2026-10-19 23:15) | 14,178 | $333 | $69 | $58 | $0 | $460 |
| after C3 (to 23:50) | 629 | $12 | $3 | 0 | $0 | $15 |
| **Total** | **63,622** | | | | | **about $2,223** |

Requests per model: Opus 42,748, Sonnet 20,033, Fable 716, Haiku 123; the other 2 requests carry no model attributed by the script. Opus cache reads were the largest item:
4.61 billion tokens (about $921), 2.08 billion of them before C1. MEASURED (transcripts, first request 2026-10-17 02:06 +0700, last
2026-10-19 23:50 +0700). The window sums use the same price table as v1's figure, so the ratio of about 1 to 5 is
INFERRED to hold under one pricing rule.

### 6.5 CI demand and the GitHub incident

**CI demand estimate** (the lead's estimate, committed in 4d1a187a at 2026-10-20 00:17 +0700, `research/notes/2026/10-20-ci-demand.md`). Window 2026-10-17
11:19Z to 2026-10-19 16:08Z (2.2 days): 2152 runs and 14,748 min of run wall. MEASURED (`gh run list`). Job minutes
were estimated as run wall × the job-to-wall ratio of each workflow, the ratio taken from its 6 newest runs over
1 min (87 runs, 405 jobs). INFERRED totals:

| Measure | Job-min (INFERRED) |
|---|---|
| Total in 2.2 days | about 30,200 (about 504 h): Linux ARM about 25,200, macOS about 5,000 |
| Per day | about 13,700 (Linux about 11,450, macOS about 2,260) |
| A 30-day month at this pace | about 410,000 |
| breakpoint-gate (ratio 4.0) | about 13,500 |
| chromium-counts | about 5,500 |
| mutants | about 2,600 |
| webkit-sim (90 % macOS) | about 2,550 |
| wktr (85 % macOS) | about 1,770 |

Caveats: run wall includes queue time, and the sample is the newest runs, some taken during the incident below. The
runners are the free ones of a public repo, so the minutes cost no money; they cost wall time when the pool is full
(§4.6). No billing read was made after the one of §6.1.

**GitHub incident of 2026-10-19.** GitHub reported "Degraded availability for GitHub Actions, GitHub Pages and
Webhooks": investigating at 15:49Z, degraded Actions at 15:56Z, recovery under way at 16:30Z with delays possible,
resolved at 16:56Z. CONFIRMED, https://www.githubstatus.com/incidents/8tzbpcnl75jp (read through the status history feed). That is
22:49-23:56 +0700, the last half hour before the C3 deadline and past it. The C3 confirmation gate run 39282664077 ran 16:04-16:34Z
(29.8 min) inside that window. MEASURED (`gh run list`). The GitHub incident is a platform event, not a team mistake, so it has no ledger row; the lead's misattribution of the queue to the slot cap does (`inc-` rows of `incidents-1019`, landed `2f82db9d`; `docs/team/incidents/ledger.json` now holds 105 incidents, lint 0 errors). The task `gh-status` (added at `dcd3e13d`) reads githubstatus.com in `fw watch`, raises an alert
while Actions is degraded and names the incident on slow or queued CI alerts [WG].

`gh-status` landed at `f39818c8` (2026-10-20 00:05 +0700): `fw watch` reads the githubstatus summary each pass (Lean `Fw.Obs.GhStatus`: `sys.ghDegraded` opens while Actions is not operational, closes when it is, keeps its state when the fetch fails; a `ci.slow` alert raised during an open Actions incident names it). The console Health tab shows the component states and the open incident. Delay the incident added (MEASURED, `gh run view`): the `lean` and `premise-tests` runs of the main push of 2026-10-19 15:50Z (836bbba6; runs 39281019901, 39281019914) were reported finished after 24 min, although the lean job itself ran 15:51-15:54Z; those of the 16:08Z push (639f9475; runs 39283085798, 39283085790) after 16 and 22 min; the C3 confirmation gate run 39282664077 took 29.8 min. Without a run outside the incident at the same load, the share of that time due to the incident is INFERRED.

---

## 7. Not done

Each line names what is missing, what the result lacks without it, and its task where one exists ([WG] at
`3ff0dbdc`; a task with no `evidence` field has not landed). PLAN R34: a missed item is listed, never hidden
[P11:1207].

**Results after C3, still open at this draft.**

- F6 per zone and on the quarantined types: no verdict (no per-zone margin for stable classes with k ≥ 1; no class for FireAnimationFrame, FunctionCall, dirtyObjects); one profile only (swipe-v1); flag independence not checked (§4.5).
- People layout against the original (`people-layout-shift`, landed `9ff2ef77`, research/notes/2026/10-19-people-layout-shift.md):
  done, two items stay open. MEASURED on CI (runs 39279857839 before the fix; 39288152363, 39288315945, 39288339116
  after; both engines; widths 1920, 1440, 1280, 861, 401): the section's top, height and the document height are equal
  in every frame; layout-shift sums are equal between the arms. One real difference, fixed: above 1030 px the
  original's empty `<source>` inside `<picture>` is a flex item, so its 12 px gap (14.64 px on screen) sits above the
  cover; the port lacked it (`.coverBlock::before`), and after the fix no non-motion box differs by more than 0.5 px at
  load. Open: the port's 'o' opens 1 to 2 scroll samples later in Chromium (23 of 32 pairs, a measured bias) and closes
  about one sample later in WebKit (cause INFERRED: React state commit against the original's class toggle); and no
  original-against-original baseline exists for the motion keys.

- The 9-flag swipe-touch-v1 arm differs by one recalc between shards at frame 498 (856 or 857, run 39292323514, §4.6); the cause is not examined.
- The WebKit phone-rotation cell (matchMedia =Lean, 2 readings, stops 1 and 3) cannot be compared, so every WebKit gate verdict is "incomplete" (an accepted limit; `gate-webkit-red` not landed).
- Gate box-model coverage: unanchored people descendants and section height are not gated, and the "host font" exclusion premise is stale since the fonts ship [C3].
- The narrowed-run difference of §5.2 is not explained.
- The g1 tail class decision (frames 698-713 have two states in the base) is open; until then pain.notes and people.card keep 2 model-bug rows each.
- The engine.scene UpdateLayoutTree model bug (1851 > 1850) has no fix in the golden rows or the site [MB]; task `model-golden-rows` has not landed.
- The swipe-touch-v1 base failed on 2026-10-18 ("did not finish within maxFrames", chromium-counts runs 39131406685, 39135255809) [MC:44-45]; later swipe-touch-v1 counts runs finish (39292317241, 39292323514, §4.6), but why the earlier runs failed was not investigated.
- No per-part runs for engine.scroll:batched and morph.tween:waapi; no part page for morph.countdown:hidden-pause.
- The commission probe flake (2 of 3 default-arm gate runs) is not diagnosed (INFERRED live-resize transient, research/notes/2026/10-19-integrate-wave-2.md:84).
- `negative-lemmas` (due before this text freeze) has not landed: no Lean why-lemma yet for commission.typing fill-no-layout, hero.orbit splash-native, platform.stageBg artboard-layer.
- `flag-verdicts-c1` (per-flag whole-page counts on each part's own profile) and the after-C3 optimizations `orbit-read-first`, `entries-due-ticks`, `exit-scoped-var`, `carousel-hidden-pause` have not landed.
- Open follow-ups of landed tasks: `port-font-gaps` (overlay buttons outside what CI verified; `fonts-followups` not landed), `compose-check` (not-comparable cells still carry an evidence mark computed at margin 0), `preview-original-missing` (pain-notes count 0 in headless, not investigated), `gh-status` (no `ci.queued` code, no GhCard component test).

**Proof and model gaps.**

- `FlowSound` (the part specs list every channel) is a premise, not a theorem; the bridge rests on it (§4.5).
- engine-check has no WebKit lane (`laneRes_webkit`); F5 is the Simulator result for the strip only (§4.9).
- F0-F2 on the fixture never ran through `fw engine-check` (no fixture artifact).
- H1-H3 stay unchecked in both engines: `pixel-spot` was cut [P11:1164-1167] (§4.7).
- The Chromium timer rule (L34) and RG1, RG6 residual, RG5 lane stay OPEN (§4.7, §5.1).
- The C4 math criterion (0 disagree, 0 stale) is not met: the math review step was removed by user decision (§4.8).

**Cut before the report** [P11:1164-1167]: `commission-resize`, the WebKit part lane, the Thai locale, new
variants for partly proved parts, class L proposals, `pixel-spot`, phone sessions. Phone session 2 did not run, so
nobody swiped `v2-proved` against `original` on the phone. `variant-morph-panel-rest` was cut at C3.

**Tooling and port.**

- `fw usage` does not exist; §6.4 used a one-off script.
- `speed-after-c3` (after C3) has not landed. The port audit moved `snapshot-paths-cleanup` before C3, to close with `svg-extract` (landed `ae6e1ba`). A guard test for it is on main (`apps/site/src/svg-extract.test.ts:76`, which flags 24-character runs of snapshot path data in tracked files under `apps/` and `packages/`), but its graph row has no `evidence` field.
- Gate hardening from draft 2: `gate-settle` (`ee57e36`) and the parked fixes (`fix-misc`, `fix-orbit`, `fix-nav-hittest`, `fix-people-webkit`) landed; `gate-run-identity` and `gate-wall-target` did not, so a gate run is still not bound to the gate code it measured.
- Port gaps: the audit found 26 gaps, 12 with no task (`research/notes/2026/10-19-port-completeness.md`). Ten follow-up tasks landed (`svg-extract`, `people-o-glyph`, `deck-panels-lean`, `asset-icons-gaps`, `doc-head-locale`, `morph-panel-content`, `dead-selectors`, `port-completeness-gate`, `port-pin-gap`, `port-wordmark-g`); which gaps remain was not measured again. The people.o "o" ownership move is left (§5.2).
- TS stand-ins with no Lean rule: the wave-2 analysis (`packages/engine-check/src/wave2.mjs`), the nav-hide analysis, the preview rewrite, the fonts reader, the people-layout analyzer (`packages/visual-diff/src/people-layout-analyze.mjs`) and the console Builds `readPresets` extends resolution (`apps/console-api/src/preview/builds.ts`).
- Tooling backlog: `visual-diff-3`, `claim-lint`, `plan-principles-lint`, `task-spec-lint`, `ci-runner-lint`, the Lean-first gate past its spec (`lfg-shadow` and later) and the Jev oracle (`jev-oracle`, `jev-eval`) have not landed.

---

## 8. Lessons for v3

Each lesson is a judgement (INFERRED) resting on the evidence named.

| # | Lesson | Evidence |
|---|---|---|
| 1 | Budget macOS CI jobs per lane before the first push. The free account runs 5 macOS jobs at once, shared across every macOS label, and our own jobs filled them | MEASURED, macos-queue note:17-24 |
| 2 | Push main early and guard paths, or every new `ci/*` branch starts every lane. Most early runs (21 of 28) touched none of their inputs | MEASURED [CU:497-499, 516-518]; `df77488` |
| 3 | Free macOS runners are too loaded for Simulator counts; check one CI Simulator run is green before building a WebKit plan on it | MEASURED at `e5bf4e4`: webkit-sim 1 of 35 runs green; boot 120 s median. Then GO at C1 after hardening (`f03e94b`): the lane needs fail-fast and hardening, not paid runners |
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
| 17 | Prove that parts compose before you plan one combined run to stand for many flags. The bridge proof found no `v2-proved` flag part isolated, so per-flag attribution stays INFERRED | CONFIRMED, `Fw.Parts.Bridge.isolated_code`, `chainPairs_code_iff` (§4.5) |
| 18 | Count passes per part, never as a page sum: units add over frames, passes do not | CONFIRMED, `Fw.Engine.Compose.passes_not_compositional`; MEASURED on one trajectory, F6 `trace.UpdateLayoutTree` -1,011 combined against a single-flag sum of -1,012 (run 39295484486 vs base 39295469515, `research/notes/2026/10-20-compose-check.md`), so the page-sum failure rests on the Lean counterexample; the totals-pilot residual +933 [W2] compared different trajectories (INFERRED, §4.5) |
| 19 | A model "trade" needs a predicted row for every stage the variant touches, or the check cannot falsify it. The strip's only row was unusable, and the page did more style and layout work | MEASURED, runs 39257533380 / 39259074927 (§5.2) |
| 20 | A part page on a free queue is about 5 min; 10 whole-page runs at once took about 40 min each. Queue time, not page size, set the old cost | MEASURED (§4.6) |
| 21 | A gate fix that deletes a declaration to match a reading depends on the reading's context; pin it with a test that fails when the context changes | CONFIRMED, `4d724e12` then `8276822d` (§5.2) |
| 22 | Decide on the full gate run. A narrowed run showed a difference the full run does not | MEASURED, runs 39271938577 and 39271987926 |
| 23 | A proxy that edits a page must leave hashed bytes alone; a hash-only CSP turns one rewritten path into a page with no scripts | CONFIRMED (§5.2) |
| 24 | Compare the port's fonts leaf by leaf; form controls do not inherit the page font by default | MEASURED, run 39262636419 |
| 25 | List every driver gate (viewport, mode, scroll) before the first dispatch of a new run shape | MEASURED, run 39189237058 |
| 26 | Watch the platform's status page during a checkpoint; the C3 gate ran inside a GitHub Actions incident and nothing in the console said so | CONFIRMED, githubstatus.com incident 8tzbpcnl75jp; run 39282664077 |

---

## Sources

Commits are on `main` of this repo. CI run ids are GitHub Actions runs of this repo. Upstream source lines are at
the pinned Chromium commit `f842f52` (`.cache/upstream/chromium@f842f52/`) and WebKit commit `862f17d` (`.cache/upstream/WebKit@862f17d/`), as cited in the notes above.
Notes of 2026-10-19 used in draft 3: `research/notes/2026/10-19-{c3-decision, integrate-wave-1, integrate-wave-2,
counts-only-finding, model-checks, lego-parts-plan, nav-scroll-hide, port-fonts-check-cells, port-completeness,
preview-original, faithful-rerun, people-layout-shift}.md`, notes of 2026-10-20 `research/notes/2026/10-20-{ci-demand, compose-check}.md`, and the handoffs in `docs/team/handoffs/` named in the text. GitHub status:
https://www.githubstatus.com/incidents/8tzbpcnl75jp (read 2026-10-20).
