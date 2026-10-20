# macOS pool v2: webkit-sim failure forensics, phase-1 design with fallback route, and its check (2026-10-20)

Follows 10-20-macos-pool.md. User asked for a shared macOS pipeline with fallback when the limit is reached. The check's verdict on design v2 is changes-requested (7 blocking items, listed at the end); the build tasks take those fixes into their specs.

---

## webkit-sim non-success jobs, 10-17..10-20: causes, minutes, fixes

Scope: the 57 non-success `sim` jobs of `.github/workflows/webkit-sim.yml` (xcode-27) in `jobs-an.json` (28 cancelled,
27 failure, 2 skipped). Minutes = job start to end. Total 882.4 min, matching the pool note (MEASURED).
Sources: `gh run view --json` job and step data already in `jobs/`, 5 job logs (`wsf-logs/`; a 6th, 117497194568,
returned "log not found"), handoffs `ci-webkit.md` and `sim-transient-retry.md`, notes `10-17-ci-trigger-scope.md`,
`10-17-zone-baselines-webkit.md` and `10-20-tween-platform-scope.md`, and the workflow file at each run's head sha.
Scripts: `wsf.py` (job list), `wscls.py` (classes and sums), both in this folder.

## Headline
- 839 of the 882 min (95 %) are from 10-17 UTC, the lane's first day on CI. Since 10-18 00:00 UTC, 1 of 28 started jobs
  failed (43.4 min of 683 min, 6 %). (MEASURED)
- Every cause except one is fixed on main. The one left is the inspector stall (B): 43 min on 10-19. (MEASURED)
- 375 min (42 %) were runs on branches that did no WebKit work, or a main push. Today's guard would not start them: it
  needs `[ci:webkit-sim]` in the head commit (cb11bf12), and a main push starts no run (14a17b94). (INFERRED from branch names)
- No job failed on a measurement verdict, and none on a Simulator boot. Boot-step cancels were manual. (MEASURED)

## Causes
| cause | jobs | min | on unwanted branches | still on main? |
|---|---|---|---|---|
| A Safari tab / warm-up: waits not scaled for the 3-vCPU runner | 16 | 146.8 | 101.1 | no: 31736295, 41ffc988, cb008b56 |
| B inspector stall, proxy or Safari gone | 4 | 185.7 | 0 | **yes** (39337860689, 10-19) |
| C process hangs after its result, then a 50 min step or 60 min job timeout | 5 | 286.1 | 174.4 | no: 9e5641cd (exit watchdog) |
| D harness bug | 5 | 86.7 | 0 | no: 12271fd5, e168f256, fbe51cc0 |
| E cancelled by a newer push (workflow-level cancel-in-progress) | 2 | 15.2 | 0 | no: no cancel on ci/* since cf503987 |
| F cancelled by hand while running | 12 | 161.9 | 99.0 | partly: cancels of unwanted runs are gone with the guard |
| never started (cancelled while queued) | 11 | 0 | 0 | n/a |
| Simulator boot failure, real verdict failure | 0 | 0 | 0 | n/a |

Job ids (run/job):
- A: 39029423848/117387273136, /117387273181; 39031884551/117393845021, /117393845027; 39033771025/117399413640;
  39036982894/117408726948, /117408726979; 39038861282/117414113394; 39040442577/117418744189, /117418744209;
  39040510569/117418990069, /117418990078; 39041100555/117420971139, /117420971190; 39044569584/117430661279,
  /117430661315. Logs 117387273136 and 117420971139 (MEASURED): `tee: out/v2-session-1.md: No such file`, then
  "0 tabs match", warm-up "Runtime.evaluate timed out after 15000 ms", "no page target", exit 1 after 4-6 min. The others
  are INFERRED from the same signature: step failure at 190-600 s, and a head sha whose workflow has no
  `FW_WK_TIMEOUT_SCALE`. 39033771025 has the scale but predates the tab re-asks (41ffc988).
- B: 39031126962/117391650739 (INFERRED: 26 min in, scaled waits, before the proxy restart c5bbc918);
  39036078841/117406017486 (handoff ci-webkit.md: LayerTree reply 120 s, proxy process gone; cancelled at 66.5 min);
  39040808182/117419965709 (handoff: DOM.getDocument 120 s, proxy closed 1006, no Simulator inspector socket);
  39337860689/118369136298 (note 10-20-tween-platform-scope.md:143-146: Runtime.evaluate 120 s, tab unreachable,
  ECONNREFUSED, failed on both attempts).
- C: 39061324429/117480561796 (note: "hit its 50 min timeout after writing v1-session-1.json");
  39068024107/117511359431 (handoff sim-transient-retry.md: "ran into its 50 min limit"); 39071369132/117509586001
  (INFERRED: step 3014 s = the 50 min limit); 39073568684/117516359177 (log, MEASURED: session json written 22:31:40,
  nothing until "timed out after 50 minutes" at 22:59:15, 27.6 min idle); 39067170890/117497194568 (INFERRED: 65 min
  > job limit 60, steps never closed, no log; GitHub reports a job timeout as `cancelled`).
- D: 39031126962/117391650782 (merge crash "reading 'cls'", rows joined by index; handoff cause 3; fix 12271fd5);
  39064063957/117488447008, /117488447011 ("Within-VM classes" step failed at 39-62 s on macOS; INFERRED: it needs
  fwcore, a Linux binary; moved to the merge job in e168f256); 39052493251/117454202564, 39052515610/117454353331
  (failed at 6-42 s, head e2620077; its child fbe51cc0 fixes an unbound EXPERIMENT/ARMS/REPS; INFERRED link).
- E: 39029077046/117385748840, /117385748899 (newer push 39029423848 was created 1.9-2.9 min before the job ended).
- F: 39037820556/117411118799, /117411118823 (manual `gh run cancel --force`, note 10-17-ci-trigger-scope.md:86);
  39046255969/117435485192 and 39049539671/117445178852 (logs: "The operation was canceled." mid-pass and in session 2;
  no newer run on the branch, so manual: INFERRED); 39038861282/117414113414; 39040503104/117418926261, /117418926267;
  39043544460/117427674641, /117427674669; 39048248989/117441276450; 39064063957/117488447023, /117488447077 (cancelled
  at 20:49, 4.8 min after re-dispatch 39068024107).

## What the data rules out
- cancel-in-progress on ci/*: across the window, running jobs overlapped a newer push to their branch for only 17.5 min
  in all (3 runs). The `tip re-check` at job start already drops stale queued jobs. Restoring cancel-in-progress would
  save about 6 min/day at most, and a macOS cancel can hold its slot for minutes anyway (note 10-17-ci-trigger-scope.md:86).
  (MEASURED)
- Simulator boot: no failures. Boot steps ran 80-155 s in cancelled jobs, the same as in green ones. (MEASURED)

## Fixes that recover minutes without changing what is measured
Forward base rate: 28 started jobs in 2.9 days, so about 10 jobs/day. Window savings are counterfactual for 10-17.
| # | fix | targets | window min saved | forward |
|---|---|---|---|---|
| 1 | already on main: the intent guard (cb11bf12) and no main-push runs (14a17b94) | A, C, F on unwanted branches | 375 | holds |
| 2 | already on main: the exit watchdog (9e5641cd) ends a finished process 20 s after its result | C | ~150 (5 x ~28 idle min; 1 MEASURED) | holds |
| 3 | fail fast on a dead inspector. When a reconnect finds no inspector socket, or ECONNREFUSED twice, relaunch Safari and re-open the URL once (handoff ci-webkit.md item 6). If that fails, exit non-zero at once, without spending the remaining 120 s evaluate and 480 s tab waits per attempt | B | ~100-140 (INFERRED: 4 jobs ran 26-66 min; a fail-fast stop lands within ~10 min of the first death) | ~25-35 min per event, ~1 event per 3 days (INFERRED) |
| 4 | lower the stall watchdog from 12 min (90 s x scale 8) to 6 min (FW_WK_STALL_MS=360000 in the workflow). The longest silence in 4 logs was 239 s (warm-up timeouts included) | B, unknown hangs | ~6 per stall event | small |
| 5 | step `timeout-minutes` from the session count, ~30 min per session (`timeout-minutes` accepts expressions), instead of a fixed 50. 55 of 56 green jobs had a determinism step <= 31.1 min (max 39.3, likely a 2-session dispatch: INFERRED) | any future hang that #2/#4 miss | 15-20 per hang | backstop only |
| 6 | skip the post-failure steps for cancelled jobs: `Keep logs` + `Shut down` + upload take 1-2 min | F | ~12 x 1.5 = 18 | small |

Not proposed: cancel-in-progress (17.5 min in the window, see above), and changes to waits used inside a pass. Counts do
not depend on the waits, but "Runtime.evaluate 120 s, then recover from a fresh load" also happens in green jobs (log of
job 118426812356). Shortening that wait would turn recoveries into failures.

Open: in 39337860689 only the second attempt's job is in `jobs-an.json` (`gh run view` lists the latest attempt). The
first attempt's minutes are not counted in the 882 (INFERRED from the note's "both attempts").

---

## macOS pool, phase 1, with provider fallback: design v2 (2026-10-20)

Inputs: research/notes/2026/10-20-{macos-pool,github-plan-concurrency,circleci-free-tier,bitrise-macos}.md and
lean/Fw/Ci/Provider.lean. v2 applies every CHANGE/DROP of the check and the user's "fallback when the limit is reached".

## 1. What changed from v1 (check finding -> v2)

| # | v1 | v2 |
|---|---|---|
| 1 | caps ~1.3x p90 of all job walls | cap = ceil(1.3 x p90 of successful job walls), computed in Lean from MEASURED p90 rows |
| 2 | `continue-on-error`, green job hides a failed lane | one outcome record per request key; Lean `delivered`; job conclusion from Lean `jobConclusion` |
| 3 | key (sha, lane, cfg); duplicates collapse | key (sha, lane, cfg digest, rep); artifact name carries leg and `run_attempt` |
| 4 | pool-27 merges webkit-sim, gate-gaps, sim-speed | dropped: F27 lanes keep one job per leg; only site build and plan move to Linux |
| 5 | WKTR `--keep` shares app container across lanes | uninstall + install between lanes, distinct port per lane, `bootstatus`, re-create after a failed lane |
| 6 | "most gain from digest skips" | the 745 min bound is UNKNOWN until the cone-diff row exists (task pool-replay) |
| 7 | shortest-first merge always | merge only when demand > free slots (`merge_only_when_bound`); latency replayed per lane, both arms |
| 8 | sharding, `plan_exactly_once` on legs, `alloc_le` | no sharding; exactly-once on units; `alloc_le_per_run`, cross-run overflow is an accepted limit |
| 9-13 | trajectory-probe in pool-26; keeps | probe out until on main; keep two images, site once on Linux, shadow, `served_once`, A/B, F26-only merge, 5 slots; add a `df -h` span |

## 2. Caps (MEASURED p90 of successes, jobs-an.json, 305 jobs, linear-interpolated p90)

Per lane (successes, p90 min, cap min): webkit-sim (56, 28.9, 38; kills 1 success at 42.6), wktr-fixtures
(35, 16.0, 21), wktr (93, 11.9, 16), sim-speed (20, 12.4, 17), engine-premises (15, 5.6, 8), gate-gaps (3, 19.7, 26;
re-derive at n >= 10). Only webkit-sim loses a measured success.

Lean: `capMin p90ds := (13 * p90ds + 99) / 100` on p90 in deciseconds; rows carry source and n. The cap is the lane step's
`timeout-minutes`; pooled job timeout = 10 + sum of its lanes' caps (`caps_fit`: <= 360). pool-replay reruns row C with
killed successes counted as lost plus a re-run.

## 3. Identity, outcomes, delivery (`lean/Fw/Ci/Pool/Key.lean`)

- `Key := (sha, lane, cfgDigest, rep)`. cfg digest = sha256 of the lane config with Lean defaults, canonical JSON (Store
  job-key scheme). Push requests have rep 0; a dispatch of n repeats yields reps 0..n-1. Dedup only on the whole key.
- Artifact `mres-<sha40>-<cfg16>-r<rep>-l<leg>-a<run_attempt>-<lane>` (lane last, every other field fixed form);
  `artifact_name_inj`: distinct (key, leg, attempt) give distinct names. Each holds `outcome.json` with the full key.
- `Outcome := result | failed | stale | skipped | notRun`. A final `if: always()` step writes `notRun` for every planned
  key with no row (timeout, runner loss). `delivered`: for any written rows, `rows plan written` has exactly one row per
  planned (key, leg), none for anything else. `jobConclusion rows = fail` iff some row is `failed` or `notRun`, so job-name
  readers see the failure too; consumers move to the records (task pool-consumers).
- `portOf lane` injective over pool lanes (WKTR serve port per lane).

## 4. Plan (`lean/Fw/Ci/Pool/Plan.lean`), phase 1

- Units = (request, leg); a job = (sha, image, leg, units). F26 (wktr, wktr-fixtures, engine-premises) may merge leg k of
  several lanes of one sha; F27 never merges. No shards.
- `plan freeSlots rs`: merge F26 units only while units > freeSlots; otherwise one job per unit.
- Theorems: `plan_exactly_once` (each unit in exactly one job, nothing else), `job_one_sha`, `legs_apart`,
  `merge_only_when_bound` (a job with 2+ units implies units > freeSlots), `f27_never_merged`, `alloc_le_per_run`
  (sum of max-parallel of one run <= ghMacCap; each image with demand gets >= 1), `order_det`, `report_own` via
  `delivered`, `caps_fit`, `served_once` (each lane served by exactly one of macos.yml and its old workflow for any
  `poolLanes`), `Pool.accept` (count classes equal; lane wall median <= old median + max(10 %, 30 s); latency not worse).
- WKTR device between lanes in one job: `simctl uninstall` + `install`, the lane's own port, `simctl bootstatus` before
  each lane, `delete` + `create` + boot after a failed lane. Count-equality A/B stays the gate.

## 5. Fallback route (`lean/Fw/Ci/Pool/Fallback.lean`), extends `Fw.Ci.Provider.route`

Types: `Provider` gains `bitrise` (in Provider.lean). `Engine := iosSimSafari | wktrIosSim | pwWebkitMac | pwWebkitWpe`,
`Engine.apple` false only for `pwWebkitWpe`. `Target := {provider, cls, engine}`. `Decision := run Target | wait`.

```
structure Req    where key : Key; lane : String; engine : Engine; capMin estMin : Nat
structure Slots  where ghMacBusy ghTotalBusy ghQueuedAhead circleBusy bitriseBusy : Nat; ghDegraded : Bool
                       ghRemainingS : List Nat      -- our running macOS jobs: estimate minus elapsed, floor 0
structure Quotas where circleCreditsLeft : Nat      -- base pool, from circleci-insights-credits
def expWaitS (s : Slots) : Option Nat               -- 0 if a slot is free; else the (ahead+1)-th smallest remaining; none if unknown
def route (r : Req) (s : Slots) (q : Quotas) : Decision
def step  (rs : List Req) (s : Slots) (q : Quotas) : List (Key × Target) × List Req × Slots × Quotas
```

Order inside `route` (first match wins):
1. GitHub macOS: not degraded and (ghMacBusy < ghMacCap or expWaitS < some ghWaitMaxS). Target = lane image, `r.engine`.
2. CircleCI `m4pro.medium`: lane in `circleMacAllow`, capMin <= circleShortMaxMin, circleBusy < circleMacConc, and
   `Provider.affordable` with estMs := (capMin + circleSetupMin) x 60000 (the cap, not the estimate, so a job that runs to
   its cap still fits). The step runs under `timeout <cap>`.
3. Bitrise: bitriseOn, lane in `bitriseAllow`, capMin <= bitriseMaxMin, bitriseBusy < bitriseConc.
4. Linux Playwright WebKit (`ubuntu-24.04-arm`, engine `pwWebkitWpe`): lane in `wpeTolerant`, ghTotalBusy < ghTotalCap.
5. `wait`: stays queued; the shared poller tick (>= 120 s) calls `step` again. `ghOnly` lanes (sim-speed) stop after 1.

Constants (Lean, golden-exported): ghMacCap 5, ghTotalCap 20, ghWaitMaxS 1200 (design choice, swept in pool-replay), circleMacConc 1, circleShortMaxMin 10, circleSetupMin 3, circleMacAllow [], bitriseOn false,
bitriseConc 1, bitriseMaxMin 45, bitriseAllow [], wpeTolerant [], ghOnly ["sim-speed"],
appleOnly ["webkit-sim", "wktr", "wktr-fixtures", "engine-premises", "sim-speed"].

Results: `Res := {key, leg, attempt, provider, cls, engine, outcome}`; freeze, classes and verdicts group by
`poolKey res := (lane, cfgDigest, provider, engine)`. Apple results of two providers pool only for lanes in `crossPoolOk`
(empty; a lane enters after a pair verdict, Provider.compare).

Theorems:
- `never_exceeds_quota`: from a state within quotas, `step` keeps circleBusy <= circleMacConc, bitriseBusy <= bitriseConc,
  reserved CircleCI credits <= circleCreditsLeft, ghTotalBusy <= ghTotalCap; GitHub macOS beyond a free slot only with
  `expWaitS < some ghWaitMaxS` (`gh_overflow_bounded`; GitHub's own queue enforces its cap).
- `routed_once`: `step` partitions its input (dispatched keys ++ remaining keys is a permutation of input keys); over any
  sequence of steps a key is dispatched at most once (`dispatch_nodup`), and a non-waiting decision removes it.
- `result_identity`: every dispatched pair and every `Res` built from it carries its target's provider and engine;
  `no_pool_apple_wpe`: equal `poolKey` implies equal provider and equal `Engine.apple`.
- `apple_only_never_linux`: lane in `appleOnly` (or not in `wpeTolerant`) never routes to engine `pwWebkitWpe`;
  `wpe_disjoint_apple` (decide): `wpeTolerant` and `appleOnly` share no lane.
- `bitrise_off_never`: bitriseOn = false gives no Bitrise target. `gh_first`: a free GitHub slot gives GitHub.
- `circle_extends_provider_route`: Fallback picks CircleCI only if `Provider.route` with ghDegraded := true picks
  CircleCI for the same lane, class, allowlist and credits (Fallback widens "degraded" to "no slot and the wait is over
  the bound"); Linux lanes keep `Provider.route` unchanged.
Phase 1 (allowlists empty, bitriseOn false) routes GitHub or wait; each later enablement is a constant edit.

## 6. If the user takes the GitHub Enterprise seat (macOS cap 50)

Only constants change: ghMacCap 5 -> 50 and ghTotalCap 20 -> 500; goldens regenerate. Every theorem takes the caps as
parameters, so none is re-proved. Effects follow from the rules: `merge_only_when_bound` stops F26 merges whenever
units <= free slots, and fallback rarely fires. Outside the code: the repository moves into an enterprise-owned org
(user step, 10-20-github-plan-concurrency.md); whether the 50 applies to public-repo minutes is INFERRED until a trial.

## 7. Build split (work-graph tasks, dependency order, smallest first)
Lean tasks share lean/scripts/check.sh, so they chain. Each task also writes docs/team/handoffs/<id>.md.

1. `pool-caps` (lean-prover, S). Writes lean/Fw.lean (one `import Fw.Ci.Pool`), lean/Fw/Ci/Pool.lean (umbrella),
   lean/Fw/Ci/Pool/{Caps,Key,Plan,Fallback,Lanes}.lean (stubs except Caps; Lanes: `poolLanes := []`),
   lean/scripts/PoolCapsGolden.lean, lean/scripts/check.sh, packages/contracts/golden/ci/pool-caps.jsonl. Deps: none.
   Unit: one cap per lane. Limits: gate-gaps n=3; trajectory-probe excluded; webkit-sim cap kills 1 of 56 successes.
2. `pool-replay` (researcher, S, parallel to 1). Writes research/notes/2026/10-21-macos-pool-replay.md. Deps: none.
   Unit: one table row per scenario. Rows: C with killed successes; per-lane result latency both arms through the
   5-slot replay; real cone-diff skip count (git diff of each lane's cone per repeat pair); ghWaitMaxS sweep with the
   CircleCI credits each value spends. Limits: local analysis of measured data, no CI; other repos' jobs unseen.
3. `pool-key-outcome` (lean-prover, S). Writes lean/Fw/Ci/Pool/Key.lean, lean/scripts/PoolKeyGolden.lean,
   lean/scripts/check.sh, packages/contracts/golden/ci/pool-key.jsonl. Deps: pool-caps. Unit: one key/outcome/name rule.
   Limits: cfg digest reuses Store's canonical JSON; no TS.
4. `pool-fallback` (lean-prover, M). Writes lean/Fw/Ci/Pool/Fallback.lean, lean/Fw/Ci/Provider.lean (`bitrise`
   constructor only), lean/scripts/PoolFallbackGolden.lean, lean/scripts/check.sh,
   packages/contracts/golden/ci/pool-fallback.jsonl. Deps: pool-key-outcome. Unit: one route decision per request.
   Limits: Telemetry.Provider keeps two constructors (follow-up); expected wait sees only this repo's jobs.
5. `pool-plan` (lean-prover, M). Writes lean/Fw/Ci/Pool/Plan.lean, lean/scripts/PoolPlanGolden.lean,
   lean/scripts/check.sh, packages/contracts/golden/ci/pool-plan.jsonl. Deps: pool-fallback (check.sh chain),
   pool-key-outcome. Unit: one plan per batch (one sha). Limits: no shards, no F27 merge, no cross-sha batches.
6. `pool-wktr-device` (measure-engineer, S). Writes packages/measure-wktr/src/{sim,cli}.mjs, packages/measure-wktr/test/**.
   Deps: pool-key-outcome (portOf golden). Unit: one lane switch (uninstall, install, port, bootstatus, re-create on
   failure). Limits: one local debug run <= 5 min; isolation proven only by the A/B.
7. `pool-consumers` (console-builder, M). Writes lean/Fw/Wire/Store.lean (ciRun reads outcome rows),
   apps/runner/src/{fw,timing-ci,land-remote}.ts, apps/runner/test/**, scripts/circleci.test.mjs. Deps:
   pool-key-outcome. Unit: one consumer moved from job names to outcome records. Limits: old names read until retired.
8. `pool-ts-port` (measure-engineer, S). Writes scripts/ci-pool.mjs, scripts/ci-pool.test.mjs. Deps: pool-plan.
   Unit: plan output equals pool-plan.jsonl row for row. Limits: TS stand-in for the Linux plan job (listed as such).
9. `pool-shadow` (measure-engineer, M). Writes .github/workflows/macos.yml, the guard step of wktr.yml,
   wktr-fixtures.yml, engine-premises.yml, webkit-sim.yml, gate-gaps.yml, sim-speed.yml. Deps: pool-wktr-device,
   pool-consumers, pool-ts-port. Unit: one workflow change serving `poolLanes` (empty) plus `[ci:pool-ab]`. Limits:
   site once per sha; `if: always()` notRun step; `df -h` span; no lane leaves its old path here.
10. `pool-ab-f26` (measure-engineer, M). Writes lean/Fw/Ci/Pool/Lanes.lean, research/notes/2026/10-2x-macos-pool-ab.md.
    Deps: pool-shadow. Unit: one lane's CI A/B (n >= 5 per arm), `Pool.accept`. Limits: F26 only; a refused lane stays.
11. `ci-route` (existing task, lean-prover): add dep `pool-fallback`; its ordered provider list takes macOS lanes from
    `Fallback.route` (one router, one source). Wiring of `wait` re-tries rides on its ci-push/poller work.

Gated follow-ups: CircleCI macOS pilot for engine-premises (fills circleMacAllow after a pair verdict); Bitrise public-app
test (user: credits, machine class, `sw_vers`, artifact API) then bitriseOn; WPE-tolerance declarations by lane owners;
F27 merge, sharding, cross-sha queue (if cap wait > 60 min/day for 3 days); trajectory-probe; one Provider for Telemetry.

## 8. Accepted limits
- `alloc_le_per_run` bounds one run; concurrent ci/** runs overflow into GitHub's queue. Other repos' macOS jobs on the
  account are invisible to `alloc` and `expWaitS` (provisioning outliers to 45 min stay unexplained).
- GitHub enforces its macOS cap; the router bounds only its own overflow. The CircleCI credit bound assumes the step
  ends by cap + circleSetupMin (`timeout`); credits left come from the insights reader.
- Fallback capacity is tiny (CircleCI ~150 m4pro min/month, concurrency 1; Bitrise UNKNOWN). webkit-sim cap 38 kills 1
  of 56 measured successes; the merge saves ~3 %; digest-skip gain UNKNOWN.
- Shared-device isolation between WKTR lanes is a premise per lane until its A/B passes.

---

**Verdict: changes-requested**

The design applies all 13 first-round check findings, and the cap numbers and the forensics minute counts reproduce. Seven things block acceptance:
- **Wait rule:** an unknown wait routes to GitHub, the opposite of the intent.
- **Wait loss:** a request in `wait` can be lost.
- **Double routing:** a push can run on two providers.
- **Result mixing:** `crossPoolOk` contradicts `poolKey`.
- **Caps formula:** the Lean formula is in the wrong unit.
- **Bitrise constructor:** adding `bitrise` breaks a file the task does not own.
- **Write overlaps:** several pool tasks write files that open tasks also write.

Files: D = `<scratchpad>/macos-pool/design-v2.md`, W = `<scratchpad>/macos-pool/webkit-sim-failures.md`.

## Re-checked (MEASURED, all match)
- **Caps from `jobs-an.json`:** recomputed as successes, linear p90 and ceil(1.3 × p90):

  | lane | n | p90 (min) | cap (min) |
  |---|---|---|---|
  | webkit-sim | 56 | 28.88 | 38 (kills only the 42.6 min success) |
  | wktr-fixtures | 35 | 16.02 | 21 |
  | wktr | 93 | 11.89 | 16 |
  | sim-speed | 20 | 12.39 | 17 |
  | engine-premises | 15 | 5.59 | 8 |
  | gate-gaps | 3 | 19.72 | 26 |

- **Job minutes from the raw `jobs/<run>.json` (startedAt to completedAt):**

  | run / job | class | min |
  |---|---|---|
  | 39337860689/118369136298 | B | 43.4 |
  | 39036078841/117406017486 | B, cancelled | 66.48 |
  | 39073568684/117516359177 | C | 55.58 |
  | 39067170890/117497194568 | C | 65.0 |
  | 39061324429/117480561796 | C | 56.1 |

  - In 39073568684 the log shows the session file written at 22:31:40 and "timed out after 50 minutes" at 22:59:15.
  - Job 117509586001 has a 3014 s step, as W says.
- **Totals:** `wscls.py` gives 882.37 min and the class sums 146.8 / 185.7 / 286.1 / 86.7 / 15.2 / 161.9. Jobs on unwanted branches total 374.5 min. Since 10-18, 1 of 28 started jobs failed (43.4 of 683 min).
- **Cited commits and note lines:** all 12 commits are on main. `10-17-ci-trigger-scope.md:86-87` and `10-20-tween-platform-scope.md:143-147` say what W claims.
- **Watchdog:** 90 s × scale 8 = 12 min (`packages/measure-webkit/src/watchdog.mjs:13`, `webkit-sim.yml:349`). Tab waits log every 10 s (`packages/measure-webkit/src/wip.mjs:114`), so W fix #4 does not kill legitimate waits.
- **Quotas against the cited notes:**

  | constant | source | match |
  |---|---|---|
  | ghMacCap 5 / 50 | plan note | yes |
  | ghTotalCap 500 (Enterprise) | plan note | yes |
  | CircleCI m4pro.medium 200 credits/min, concurrency 1, ~150 min/month | circleci-free-tier note | yes (that note also records a 25k credits / concurrency 2 disagreement) |
  | Bitrise 1 concurrency / 45 min | 2018 public-app terms, UNKNOWN | see item 13 |

## Items

**1. KEEP:** D §1 rows 1-13. Every first-round CHANGE and DROP is reflected (caps, outcome records, rep + run_attempt, F27 drop, WKTR uninstall/port/bootstatus, 745 min UNKNOWN, `merge_only_when_bound`, no shards plus `alloc_le_per_run`, probe out, `df -h`). The exceptions are items 2, 9 and 10.

**2. CHANGE: D §2, `capMin`.**
- Problem: `(13 * p90ds + 99) / 100` is correct only for tenths of a minute. For deciseconds it gives 2253 for webkit-sim.
- Fix: write `capMin p90dm := (13 * p90dm + 99) / 100 -- p90 in tenths of a minute`, or keep deciseconds and use `(13 * p90ds + 5999) / 6000`. Add the golden row `capMin 289 = 38`.

**3. CHANGE: D §5 rule 1 and `gh_overflow_bounded`.**
- Problem: in Lean 4.35, `none < some x` holds. I checked with `#print Option.lt`: the case `| none, some val => True`. So an unknown wait routes to GitHub, and the theorem is vacuous for `none`.
- Fix: write rule 1 as `!s.ghDegraded && (s.ghMacBusy < ghMacCap || (match expWaitS s with | some w => w < ghWaitMaxS | none => false))`.
- Also restate `gh_first` with the hypothesis `s.ghDegraded = false`, since rule 1 requires it.

**4. CHANGE: D §5 `wait`, a request can be lost.**
- Problems:
  - Nothing says where waiting requests live.
  - A dead poller, a sha superseded while waiting, or a persistent `ghDegraded` with empty allowlists all drop the request with no row.
  - `delivered` covers only planned keys of a run.
- Fixes:
  - Waiting requests are durable records keyed by `Key`.
  - Add `Outcome.waiting` and a bound `waitMaxS`, after which `step` emits `notRun`.
  - A tip re-check emits `stale`.
  - Add a theorem `wait_resolves`: every key in the input appears in exactly one of dispatched, still waiting with age ≤ waitMaxS, or a terminal row.

**5. CHANGE: D §5 `routed_once`, double routing on push.**
- Problem: `macos.yml` is push-triggered, so GitHub queues the job before any `step` runs. If `step` then routes the same key to CircleCI, Bitrise or WPE, it runs twice. `dispatch_nodup` covers only `step` output. A GitHub "re-run" is also a second dispatch.
- Fixes:
  - Make the macos.yml plan job the only dispatcher. It calls `Fallback.route` and runs a key on GitHub only when the decision is `run {provider := github}`. Non-GitHub keys are handed off via a claim record keyed by `Key`.
  - State `dispatch_nodup` per (key, attempt).
  - Accepted limit: no re-route after a GitHub dispatch, even if the real wait exceeds `ghWaitMaxS`.

**6. CHANGE: D §5 Results, Apple results can mix or the rules contradict.**
- Problem: `poolKey` contains `provider`, so `crossPoolOk` can never pool two providers. If it does pool them, `no_pool_apple_wpe` ("equal provider") is false.
- Fixes:
  - Define `poolKey r := (lane, cfgDigest, if r.lane ∈ crossPoolOk && r.engine.apple then none else some r.provider, r.engine)`.
  - Theorems: equal `poolKey` implies equal `engine` (hence equal `Engine.apple`), and equal provider unless the lane is in `crossPoolOk`.
  - Also state the target engine for rules 2 and 3 (`r.engine`).

**7. CHANGE: D §5 constants, `appleOnly`.**
- Problem: `appleOnly` omits `gate-gaps` (xcode-27, WKWebView + Simulator).
- Fix: drop `appleOnly` and prove `apple_only_never_linux` as "lane ∉ wpeTolerant implies engine ≠ pwWebkitWpe". Or derive `appleOnly := macLanes.filter (· ∉ wpeTolerant)` and include gate-gaps.
- Also `Req` has one `engine`, but gate-gaps uses three engines. Exclude gate-gaps from Fallback until it is split.

**8. CHANGE: D §5 constants, sources and status tags.**
- Problems:
  - `cir
