# macOS CI lanes: measurement, a shared-pipeline design and its check (2026-10-20)

User 2026-10-20: combine the macOS lanes into one pipeline that shares the macOS resource, with short jobs, and fall back when the limit is reached. Three agents: measure (gh run data, 3 days, 305 jobs), design (with a replay of the measured jobs through a 5-slot queue), adversarial check (re-ran the numbers). The check's verdict is changes-requested; its findings are the design changes to apply.

Headline: combining lanes alone saves about 3 % of macOS job-minutes. The larger levers are failed or cancelled jobs (29 % of minutes, 882 of 1173 in webkit-sim), fixed per-lane max-parallel (539 min of waiting), and skipping unchanged inputs (at most 745 min; the sound share is UNKNOWN).

---

## macOS CI lanes: measurement (2026-10-20)

Source: `gh run list --json` per workflow (created >= 2026-10-13), then `gh run view --json jobs` for the 176 runs that
lasted >= 3 min (gate-gaps and trajectory-probe: dispatch runs only, their macOS job is dispatch-only). 3 job logs
(`gh run view --job --log`) for in-step phases. The repo's telemetry store has no macOS record
(`.fw-console/telemetry/records.jsonl`: 13 Linux records), and `timings.jsonl` CI rows start 10-17, so gh filled the rest.
The first macOS run of the repo is 10-17 11:19 UTC: the "7 days" window holds 3.0 days of data (10-17 11:32 to 10-20 11:37 UTC).
Raw data: `scratchpad/macos-pool/jobs/<run>.json`, `jobs-an.json`, analysis `an.py`, `rep2.py`.

## Lanes: what runs, triggers

| lane (job) | runner | runs | triggers | matrix / max-parallel |
|---|---|---|---|---|
| webkit-sim `sim` | xcode-27 (image xcode-27-arm64) | Safari in iOS 27.0 (24A434) Simulator via ios_webkit_debug_proxy; determinism sessions on the site-dist build | push `ci/**` + path cone (measure-webkit, snapshot, check-simulator, telemetry); dispatch | vm x arm, max-parallel 2 |
| wktr `wktr` | macos-26 (macos-26-arm64) | prebuilt iOS-sim WKTR r324039 + Xcode 26.5 + iPhone 17 iOS 26.5; style counts per step, original + variants | push `ci/**` + cone (measure-wktr, fwcore, snapshot); dispatch | j1..jN, max-parallel 1 |
| wktr-fixtures `fixtures` | macos-26 | same WKTR archive/Xcode/device; fixture cells | push `ci/**` + cone (measure-wktr, fwcore, wktr.fixtures golden); dispatch | j1..jN, max-parallel from golden (1-5) |
| engine-premises `webkit` | macos-26 | same WKTR archive/Xcode/device; premise page from golden | push `ci/**` + cone (measure-chromium, measure-wktr, premises golden); dispatch | j1..jN, max-parallel 1 |
| gate-gaps `collect-macos` | xcode-27 | Playwright WebKit + WKWebView + Simulator gap collection | dispatch with `inputs.macos` only | 1 job |
| sim-speed `probe` | xcode-27 | Simulator boot-speed probe arms | push `ci/sim-speed` only + cone; dispatch | arm x rep (10), no max-parallel |
| trajectory-probe `probe-apple` (branch worktree-wf_b2d9cca1-299-1) | macos-26 | Playwright WebKit (macOS build) hero-path walk | dispatch only, engines include playwright-webkit | 1 job |

Runs listed in window (most are guard-skipped `ci/**` pushes, 0 macOS minutes): engine-premises 236, webkit-sim 324,
wktr 316, gate-gaps 345, sim-speed 3, wktr-fixtures 253, trajectory-probe 15. (MEASURED)

## Per lane: macOS jobs that ran (MEASURED, 305 jobs; 59 more were skipped/cancelled before a runner)

| lane | runs | jobs | job-min | share | wall med / p90 (min) | queue med / p90 / max (min) | setup %* | meas % (step) |
|---|---|---|---|---|---|---|---|---|
| webkit-sim | 63 | 100 | 2131 | 52% | 19.4 / 38.1 | 0.5 / 31.9 / 78.6 | 19 | 81 |
| wktr | 52 | 108 | 971 | 24% | 9.3 / 11.8 | 10.6 / 34.2 / 58.0 | 13 | 87 |
| wktr-fixtures | 16 | 43 | 613 | 15% | 14.0 / 16.2 | 0.7 / 16.5 / 30.8 | 8 | 92 |
| sim-speed | 3 | 30 | 233 | 6% | 7.6 / 12.4 | 14.9 / 24.8 / 32.9 | 14 | 86 |
| engine-premises | 8 | 18 | 78 | 2% | 4.2 / 5.8 | 4.4 / 12.8 / 14.5 | 22 | 78 |
| gate-gaps | 3 | 3 | 50 | 1% | 19.2 / 19.9 | 4.7 / 12.4 / 12.4 | 5 | 95 |
| trajectory-probe | 3 | 3 | 11 | 0% | 3.6 / 3.8 | 0.1 / 0.2 / 0.2 | 17 | 83 |
| **all** | 148 | 305 | **4086** | 100% | | | 15.5 | 84.5 |

*setup % = boot/checkout + toolchain + site/artifact + Simulator steps + upload + inter-step gap, by step name.
Queue = job startedAt minus the completedAt of its `needs` jobs (not run createdAt: that would count the Linux site
build). Example runs (median wall): webkit-sim 39046570019, wktr 39073755302, wktr-fixtures 39121958562,
sim-speed 39043591653, engine-premises 39088367495, gate-gaps 39042512691, trajectory-probe 39412301221.

Non-success jobs (failure + cancelled after start): 1173 job-min = 29% of all (webkit-sim 44 of 100 jobs). (MEASURED)

## Step split, median seconds per successful job (MEASURED)

| lane | boot+checkout | toolchain | site/artifact | Simulator steps | measurement step | upload | wall |
|---|---|---|---|---|---|---|---|
| webkit-sim | 9 | 13 (iwdp 14, node 1) | 1 | 138 (boot 119 avg, delete 33) | 1128 | 10 | 1314 |
| wktr | 11 | 33 (Xcode select 21, archive 15, cache 4) | 1 | 4 | 512 | 2 | 569 |
| wktr-fixtures | 12 | 30 (Xcode 16, archive 16) | 0 | 2 | 779 | 2 | 842 |
| sim-speed | 7 | 14 (iwdp 29 avg) | 0 | 10 | 425 (boot is the measurement) | 4 | 475 |
| engine-premises | 10 | 30 (archive 14, Xcode 13) | 0 | 6 | 211 | 2 | 282 |
| gate-gaps | 7 | 14 (Playwright WebKit 8, pnpm 5) | 2 | 11 | 1114 | 3 | 1151 |
| trajectory-probe | 9 | 20 (Playwright WebKit 14, pnpm 6) | 4 | 0 | 180 | 2 | 219 |

Setup hidden inside the "measurement" step (from logs, few samples):
- WKTR lanes create and cold-boot the device inside the run step (`packages/measure-wktr/src/sim.mjs:44-48`):
  device created -> first serve 187 s (wktr job 117408805624, run 39036983052) and 233 s (fixtures job 117524189727,
  run 39075991405). MEASURED for those 2 jobs. Extrapolated to 169 WKTR-family jobs at ~3.5 min: ~590 job-min. INFERRED.
- webkit-sim job 118426812356 (run 39360085910): step start 02:51:06, proxy up 02:52:09, Safari tab retries and one
  120 s warm-up timeout, pass 1 starts 02:59:18: 492 s of 1172 s session before the first pass. MEASURED for 1 job;
  how often this repeats across the 100 jobs is not measured.
- So the true measurement share is below 84.5%: with the two hidden setups it is about 55-70%. INFERRED.

## Job-minutes per day (UTC, MEASURED)

| day | total | webkit-sim | wktr | wktr-fixtures | sim-speed | engine-premises | gate-gaps | trajectory |
|---|---|---|---|---|---|---|---|---|
| 10-17 (from 11:32) | 2552 | 1448 | 780 | 41 | 233 | 0 | 50 | 0 |
| 10-18 | 1159 | 319 | 191 | 571 | 0 | 78 | 0 | 0 |
| 10-19 | 208 | 208 | 0 | 0 | 0 | 0 | 0 | 0 |
| 10-20 (to 11:37) | 167 | 156 | 0 | 0 | 0 | 0 | 0 | 11 |

Mean 1360 job-min/day over the 3.0 days; 91% of it on 10-17/10-18 (the WKTR spike and webkit-sim determinism days).

## The 5-job macOS cap (MEASURED, this repo's jobs only)

- Peak concurrent macOS jobs: 5. Time with all 5 slots busy: 348 min (10-17 13h-22h UTC, 10-18 00h-11h).
- Jobs that waited while 5 slots were busy: 148 of 305 (49%); 2012 min of cap waiting in total; max 72.3 min
  (webkit-sim run 39053799594 `sim (r3, rewrite)`, 10-17 18:56). Per day: 10-17 122 jobs / 1838 min (median 11.8);
  10-18 26 jobs / 174 min (median 6.8); 0 on 10-19 and 10-20.
- Cap-queued jobs per lane (median wait, min): wktr 61 (12.4), webkit-sim 36 (7.2), sim-speed 28 (14.4),
  wktr-fixtures 12 (7.5), engine-premises 8 (4.3), gate-gaps 3 (4.5).
- Self-queue from the lane's own `max-parallel` (slot free but sibling limit hit): 539 min (wktr 247, webkit-sim 136,
  wktr-fixtures 122, engine-premises 34).
- Provisioning wait with free slots: median 38 s, p90 167 s. Outliers up to 45 min with no other macOS job of this repo
  running (webkit-sim run 39337860689, 10-19 22:56-23:41; run 39076390198, 10-17). INFERRED: the cap is per account,
  so macOS jobs of another repo (for example the v1 repo) or xcode-27 image supply held them; not verified.

## Setup that repeats across lanes

| repeated setup | lanes | per job | jobs in window | job-min | tag |
|---|---|---|---|---|---|
| WKTR archive restore + extract (same key `wktr-ios-min-324039-*`) | wktr, wktr-fixtures, engine-premises | 14-16 s + cache 3-4 s | 169 | ~50 | MEASURED |
| `sudo xcode-select` Xcode 26.5 + tool listing | wktr, wktr-fixtures, engine-premises | 13-21 s | 169 | 54 | MEASURED |
| iPhone 17 iOS 26.5 device create + cold boot (in run step) | wktr, wktr-fixtures, engine-premises | ~190-230 s | 169 | ~590 | INFERRED (2 logs) |
| iOS 27.0 24A434 runtime check + device create | webkit-sim, gate-gaps, sim-speed | 4-5 s | 133 | ~10 | MEASURED |
| Simulator boot (iPhone 15 Pro Max, iOS 27.0) | webkit-sim (step), gate-gaps + sim-speed (in step) | 84-119 s | 133 | ~200+ | MEASURED (webkit-sim), INFERRED (others) |
| ios_webkit_debug_proxy setup | webkit-sim, sim-speed | 14-29 s | 130 | 37 | MEASURED |
| Simulator shutdown/delete | all Simulator lanes | 8-33 s | 302 | ~90 | MEASURED |
| Playwright WebKit macOS install + setup-pnpm | gate-gaps, trajectory-probe | 13-20 s | 6 | 2 | MEASURED |
| site-dist artifact download (built per workflow on Linux) | webkit-sim, gate-gaps, trajectory-probe | 1-4 s | 106 | 2 | MEASURED |
| checkout + set up job + post steps | all | 7-12 s | 305 | ~55 | MEASURED |

Not repeated on macOS: the site build itself runs on Linux (`site` job per workflow), so a shared macOS job saves no
site build; each workflow still builds its own site-dist on Linux (webkit-sim, gate-gaps, trajectory-probe). INFERRED.

## Takeaways for one shared macOS pipeline

- Fixed cost per macOS job: WKTR family ~4-4.5 min (1 min steps + ~3.5 min cold boot), webkit-sim ~3 min of steps
  plus a Safari-tab warm-up seen at 8 min once. Matrix fan-out multiplies it: jobs/run wktr 2.1, fixtures 2.7,
  engine-premises 2.2, webkit-sim 1.6, sim-speed 10. (MEASURED per-step; boot INFERRED)
- Two device families never mix in one job today: macos-26 + Xcode 26.5 + iOS 26.5 (WKTR) and xcode-27 + iOS 27.0
  (Safari/Playwright). A shared job per family keeps one booted device for all its passes. (CONFIRMED from workflow files)
- Cap pressure came from matrix fan-out on 10-17/10-18 (sim-speed 10 jobs at once, wktr/webkit-sim matrices), not from
  steady load; 10-19/10-20 never hit it. (MEASURED)
- 29% of macOS job-minutes ended in failure or cancel; a long single job raises the cost of one late failure. (MEASURED)

---

## One shared macOS pipeline: design (2026-10-20)

Input: `measure.md` in this folder (3.0 days, 305 macOS jobs, 4086 job-min). Replays of those jobs: `co/co.py`, `co/sim2.py`.
Limit: 5 macOS jobs at once per account, all labels share them (research/notes/2026/10-17-macos-queue.md, MEASURED);
free runners only. Public repo minutes are free, so the cost is slot time and queue wait.

## 0. What the data says before any design

- Pushes that asked for 2+ macOS lanes of one image: 14 of 96 shas. Merging them by leg removes 34 of 305 jobs (MEASURED, co.py).
- The merge saves about 136 job-min (3%). The larger measured losses are elsewhere: failed or cancelled jobs 1173 job-min
  (webkit-sim 882), push re-runs of the same branch+lane+leg 61 jobs / 745 job-min (upper bound for input-digest skips),
  static `max-parallel` self-queue 539 min (MEASURED).
- So the pipeline below merges lanes, but most of the gain comes from per-lane caps, digest skips and slot allocation.

## 1. One workflow: `.github/workflows/macos.yml`

| job | runner | does |
|---|---|---|
| guard | ubuntu | reads every `[ci:<lane>]` token of the head commit and each lane's input cone (Fw.Ci.Intent, Fw.Ci.Trigger, unchanged); dispatch reads `requests` (JSON list of {lane, cfg}) |
| plan | ubuntu | Lean plan (section 5) via `scripts/ci-pool.mjs`; verifies the snapshot lock; computes digests; emits matrix per image |
| site | ubuntu | builds site-dist once per sha+preset+fw (today built per workflow: webkit-sim, gate-gaps, trajectory-probe) |
| pool-26 | macos-26 | WKTR family + trajectory-probe: one setup, then its lanes in order |
| pool-27 | xcode-27 | Safari/Playwright family (webkit-sim, gate-gaps, sim-speed): one setup, then its lanes |
| reduce | ubuntu | per-lane classes, freeze, verdict, align (the current Linux jobs, as a matrix over lanes) |

Two images stay two job kinds: WKTR r324039 needs Xcode 26.5 + iOS 26.5 on macos-26, Safari lanes need iOS 27.0 24A434
on xcode-27 (CONFIRMED, workflow files). A probe whether xcode-27 ships Xcode 26.5 + the iOS 26.5 runtime is a follow-up.

**Job = (sha, image, leg, shard).** A lane's legs are separate VMs by premise ("fresh macOS VMs": wktr-fixtures.yml:7,
engine-premises.yml:7, webkit-sim `vms`; CONFIRMED). So job k runs leg k of every lane in the batch; two legs of one
request never share a job. Leg k of wktr and leg k of wktr-fixtures may share one.

Shared setup per job, once: checkout, toolchain (Xcode select, WKTR archive restore, iwdp or Playwright WebKit as the
job's lanes need), site-dist download, one device create + boot. WKTR lanes already reuse a named, booted device:
`ensureDevice` returns an existing device (packages/measure-wktr/src/sim.mjs:31-34@8473028a), `boot` accepts "Booted"
(sim.mjs:44-46), and `--keep` skips shutdown/delete (cli.mjs:98). CONFIRMED. All but the last lane run with `--keep`.

Order inside a job (deterministic): own-boot lanes first (sim-speed, where the boot is the measurement; webkit-sim with
`fresh_boot`), then shortest estimate first, ties by (lane, cfg digest). Each lane runs under its cap with
`continue-on-error`, re-checks the branch tip before it starts (a newer tip marks the rest `stale`, recorded per key),
and uploads its own artifact `mres-<key>` at once, so a late failure never loses earlier lanes' results.

Per-lane caps (min, ~1.3x measured p90 job wall): webkit-sim 30, gate-gaps 25, wktr-fixtures 20, wktr 15, sim-speed 15,
engine-premises 8, trajectory-probe 6. Job timeout = 10 + sum of its lanes' caps.

## 2. Coalescing and identity

- Request key = (sha, lane, cfg digest); cfg = the lane's config with Lean defaults filled, canonical JSON, sha256 (the
  Store job-key scheme, lean/Fw/Wire/Store.lean:17). Result key = request key + leg.
- Push: one push = one run = one batch, all of one sha. Concurrency groups stay as today, so no `ci/**` run is cancelled
  (Fw.Ci.Cancel `ci_never_cancelled`); only the existing stale-tip rule drops a superseded commit, and it now says so per key.
- Dispatch: `requests` input; `fw ci pool --lane wktr --jobs 3 ...` replaces `gh workflow run wktr.yml -f ...`.
- Land lane: Linux only today. A land that needs macOS pushes `ci/land-*` with `[ci:<lane>]` tokens like any push.
- Duplicate requests in one batch collapse to one key. Different shas are never merged (no shared checkout or build).
- Parked (phase 2): cross-sha batching through a durable queue (request artifacts, a claim job in one concurrency group
  per image, every finished run dispatches the next drain tick; a cancelled pending tick holds no request). It would
  share only setup + boot (~4 min per F26 job). Start it only if cap wait stays > 60 min/day for 3 days after phase 1.

## 3. Off macOS (to Linux)

Site build once per sha (was up to 3x), snapshot-lock verify (macOS in webkit-sim today), Lean plan/caps/digests/slots,
reduce/classes/freeze/verdict/align/merge. macOS keeps only Simulator, WKTR, Safari, Playwright WebKit, iwdp, runner facts.

## 4. Per-lane runtime cuts

| cut | where | saves | tag |
|---|---|---|---|
| shared device boot across lanes of one job | F26 ~190-230 s, F27 84-119 s per extra lane | ~136 job-min / 3 days at measured traffic | MEASURED counts, INFERRED min |
| per-lane caps + fail-fast | all; webkit-sim proxy/target fail-fast (10-17-sim-speed.md, rec. 1) | 285 job-min / 3 days at the caps above | MEASURED replay |
| input-digest skip | push requests only: key digest = lane, cfg, image pins, git blob ids of the lane's expanded input cone, site-dist digest; an earlier success with the same digest is replayed (Fw.Ci.Trigger `skipped_replays`) | <= 745 job-min / 3 days | upper bound |
| per-run slot allocation instead of static `max-parallel` | plan | <= 539 min self-queue / 3 days | upper bound |
| shard a big leg | only when its estimate > T = 25 min and slots are spare; whole lane-units by LPT | wall, not job-min | design |
| keep Safari between sessions | webkit-sim, in-lane (rec. 2) | ~60-70 s per extra session | INFERRED n=2 |

Dispatch requests never digest-skip: determinism dispatches exist to repeat (freeze needs >= 3 runs). A booted device
shared by lanes is a premise per lane, checked by count equality (section 7); Safari lanes use their own port (own
origin) and terminate Safari between lanes (INFERRED isolation until checked).

## 5. Lean first: `lean/Fw/Ci/Pool.lean`

```
structure Req  where sha lane cfg : String; image : Image; legs est cap : Nat; ownBoot readsBuild : Bool
structure Unit where req : Req; leg : Nat                       -- leg < req.legs
structure Job  where sha : String; image : Image; leg shard : Nat; units : List Unit
def plan  (slots T : Nat) (rs : List Req) : Plan                -- dedup by key, group (sha, image, leg), shard, order
def alloc (slots : Nat) (demand : List (Image × Nat)) : List (Image × Nat)  -- max-parallel per image
def report (p : Plan) (out : Unit → Outcome) : List (Key × Nat × Outcome)
def serves (poolLanes : List String) (l : String) : Side         -- .pool or .old, for migration
```
Theorems (each a closed statement, no TS decides any of it):
- `plan_exactly_once`: every leg of every deduped request is in exactly one job; no job holds anything else.
- `job_one_sha`: every unit of a job has the job's sha and image (implies: a batch never mixes shas for a lane that
  reads the build; the build a unit reads is keyed by its own sha).
- `legs_apart`: two units of one request in one job have the same leg.
- `alloc_le`: sum of `max-parallel` <= slots (5); each image with demand gets >= 1 when images <= slots.
- `order_det`: the order depends only on the set of units (sorted by a total order on distinct keys).
- `report_own`: every reported entry is (key u, leg u, out u) for a unit u of the plan; no key reported twice.
- `caps_fit`: job timeout >= setup + sum of unit caps, and <= 360 min (GitHub's job limit).
- `served_once`: each macOS lane is served by exactly one of macos.yml and its old workflow, for any `poolLanes`.
Golden vectors `packages/contracts/golden/ci/pool.jsonl` from Lean: one lane; wktr+fixtures+premises (3 lanes, 3/3/2
legs); webkit-sim vms=3 x both (6 legs > 5 slots); two shas in one input; a duplicate request; sim-speed with a shared
lane; a 40-min leg with spare slots (shard). `scripts/ci-pool.mjs` is a TS port checked against them (as ci-paths.mjs).

## 6. Expected effect (replay of the measured 305 jobs through a FIFO 5-slot queue, `co/sim2.py`)

| scenario | job-min/day | queue wait min/day | wait p90 (min) | jobs |
|---|---|---|---|---|
| today (replay) | 1362 | 742 | 24.2 | 305 |
| + merge same sha/image/leg | 1317 | 679 | 24.4 | 273 |
| + per-lane caps | 1222 | 596 | 23.1 | 273 |
| + digest skip, upper bound | 977 | 289 | 16.5 | 212 |

Assumptions: fixed cost per merged lane 255 s (F26: 60 s steps + 195 s boot, boot INFERRED from 2 logs) and 180 s
(F27); a failed job would have stopped at its lane cap; ready times as measured; no other repo's macOS jobs; the
replay ignores static `max-parallel`, so measured self-queue (539 min) is extra and mostly removed by `alloc`. 91% of
the load sat on 10-17/10-18; on quiet days the cap was never hit and the gain is the failure and skip cut only.
Latency: the 24 merged groups' last result came at a median 18.3 min after the first lane was ready (with queue); one
serial pool job takes a median 17.7 min (no queue), so no median loss.

## 7. Migration, rollback, proof

1. Lean `Pool.lean` + theorems + golden + TS port and its test. No CI change.
2. macos.yml in shadow: serves only lanes in `poolLanes` (Lean constant, starts empty) plus `[ci:pool-ab]` pushes, which
   run the old and the pool path on the same sha.
3. A/B per lane, F26 first (32 of the 34 merged jobs; deterministic counts), then F27 (failure-heavy; Safari state).
   n >= 5 per lane and path, medians (boot noise 51-232 s, 10-17-sim-speed.md).
4. Pass per lane: count classes identical for the same sha and arm; lane wall (lane start to `mres` uploaded) median
   <= old measurement-step median + max(10 %, 30 s); push-to-result latency median not worse. A Lean verdict
   `Pool.accept` decides it from the measured rows (golden-checked).
5. Add the lane to `poolLanes`; the old guard skips it (`served_once`). Old files stay 7 days, then their macOS jobs go.
Rollback: remove the lane from `poolLanes` and regenerate goldens; no workflow edit. A lane that fails step 4 stays on
its old path (a finding, with its cause).
Measure: per-lane spans (key, digest, start, end, outcome, queue) into telemetry records.jsonl (no macOS row today).

## Accepted limits

- Two images, two job kinds (until the xcode-27 probe); no cross-sha merge in phase 1 (parked, trigger above).
- The merge alone is small (~3%) at measured traffic; caps, skips and allocation carry the gain.
- `alloc` cannot see other repositories' macOS jobs on the same account; GitHub's queue absorbs them.
- Shared-device isolation between lanes is a premise per lane until its A/B passes.

---

## check: macOS pool design (2026-10-20) — verdict: changes-requested

## Re-checked (MEASURED, gh run view + jobs-an.json + co.py/sim2.py re-run)
- run 39073755302 wktr: j1 8.85 min, j2 9.48 min, j2 wait 13.1 min (cap 468 s, maxp 63 s) — matches.
- run 39053799594 webkit-sim: r3 queued 78.6 min (cap 4336 s = 72.3 min) — matches measure.md max.
- run 39121958562 fixtures: 10.3/14.0/12.2 min, j3 maxp wait 615 s — matches.
- 305 jobs, 4086 job-min, 1173 non-success, per-lane jobs/min/medians: all reproduce.
- sim2 rows A-D (4086/3950/3665/2931 job-min, 2227 wait) and 24-group latency 18.3 vs 17.7 reproduce.

## Ranked findings
1 CHANGE design.md §1 caps — webkit-sim cap 30 is below 1.3x its success p90 (29.0 -> 37.7). 5 of 56 successful
  webkit-sim jobs (31.6, 32.4, 33.7, 37.2, 42.6 min) would be killed; wktr cap 15 kills 1 success (15.9). sim2 `capped`
  cuts only failures, so row C hides the lost results. Fix: caps = ceil(1.3 x p90 of successes) (webkit-sim 38, wktr 16),
  and rerun row C counting killed successes as lost + rerun.
2 CHANGE §1/§2 lane outcome — `continue-on-error` turns a failed lane into a green job; consumers read job names and
  conclusions (Fw.Wire.Store `store.ciRun` jobs[{name,conclusion}], scripts/circleci.test.mjs job names like
  `sim (rewrite, 430, 1, <digest>, v1)`, fw ci wait). Fix: name every consumer in §7 step 1. Port them to per-lane outcome
  records (`mres-<key>` + outcome.json) before shadow. Add Lean `delivered`: every request key gets exactly one row in
  {result, failed, stale, skipped, not-run}, including on a job timeout (an `if: always()` step writes not-run).
3 CHANGE §2 dedup — "Duplicate requests in one batch collapse to one key" drops dispatch repeats, but §4 says
  determinism dispatches exist to repeat (freeze needs >= 3). Fix: request key = (sha, lane, cfg digest, rep). The
  artifact name adds `run_attempt` (re-run attempts reuse names; upload-artifact v4 refuses duplicates).
4 DROP pool-27 merging in phase 1 — under phase-1 rules (push batches only), F27 merges 0 jobs in the window (sim2
  merges push only; the 2 F27 co.py groups pair webkit-sim with dispatch-only gate-gaps). sim-speed cannot share a VM:
  arm `quiet` runs `sudo mdutil -a -i off` / `log config --mode level:off` (sim-speed.yml:161), arms pre/combo use the
  image's own device, and its boot is the measurement on a fresh VM. It also only pushes `ci/sim-speed`. webkit-sim has 44%
  non-success and would take others down with it. Fix: F27 lanes keep one job per leg; only the Linux site/plan move.
5 CHANGE §1 WKTR shared device = cross-lane cache — `--keep` keeps the app data container (cli.mjs:94-98, `install` over
  an existing app), so lane 2's pass 1 runs warm on the same served origin where today it is cold. Fix: between lanes
  `simctl uninstall` + `install` (keeps boot, drops container), a distinct port per lane, `bootstatus` health check, and
  re-create the device after a failed lane. Count-equality A/B stays the gate.
6 CHANGE §0/§4/§6 claimed gain — "most of the gain comes from ... digest skips" rests on a bound that skips every
  repeat of (branch, lane, leg) whether or not the input changed (co/sim.py:21). The real sound-skip count is
  unmeasured, and re-pushes with a `[ci:lane]` token are often deliberate flake retries. Fix: compute the real cone
  diff per repeat pair (git diff of the lane's cone between the two shas) and report that row. Until then tag the 745
  min UNKNOWN, not the main gain.
7 CHANGE §6 latency — 18.3 (measured, with queue) vs 17.7 (serial, no queue) compares unlike things. Shortest-first
  order also pushes the longest lane (fixtures 14 min) behind premises+wktr: about +9-13 min when slots are free (10-19/20
  never hit the cap). Fix: replay per-lane result latency through the 5-slot sim for both arms. Let `plan` merge only
  when demand > free slots (parallel otherwise), and prove it in Pool.lean (`merge_only_when_bound`).
8 CHANGE §5 Lean — `plan_exactly_once` ("every leg in exactly one job") contradicts §4 sharding (Job.shard, a leg
  split across jobs); sharding also breaks the "leg = one VM" premise. Fix: drop sharding from phase 1, or state it on
  units (lane-unit in exactly one job) and record the premise change. `alloc_le` bounds one run only: concurrent
  ci/** runs each get 5, so it does not bound the account cap. Rename it as a per-run bound and list "cross-run
  overflow goes to GitHub's queue" in accepted limits. `order_det` is trivial (keep, it is cheap).
9 CHANGE §1 pool-26 includes trajectory-probe — workflow exists only on branch worktree-wf_b2d9cca1-299-1, not
  .github/workflows on main; it uses Playwright WebKit macOS, not WKTR. Fix: leave it out until it lands.
10 KEEP two images as two job kinds (CONFIRMED: webkit-sim/gate-gaps/sim-speed runs-on xcode-27; wktr,
   wktr-fixtures, engine-premises runs-on macos-26).
11 KEEP site build once per sha on Linux, plan/reduce off macOS, per-lane `mres-<key>` uploads, shadow +
   `served_once` + per-lane A/B with Lean `Pool.accept`, rollback by `poolLanes`.
12 KEEP F26 merge as the only merge in phase 1 (32 of 32 push merges, ~136 job-min/3 days = 3%; boot 195 s INFERRED
   from 2 logs — A/B must measure it). Add a disk check (`df -h` span) per pooled job.
13 KEEP 5-slot premise (peak concurrency 5 measured; 348 min all-busy).

## Request-loss / mixing paths found
- dedup of dispatch repeats (3); green job hiding a failed lane (2); timeout kills later lanes without a row (2);
  artifact name reuse on re-run attempt (3); warm container / same origin across lanes (5).
