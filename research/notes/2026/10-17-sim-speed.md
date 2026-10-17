---
id: 2026-10-17-sim-speed
kind: note
title: "Simulator speed on GitHub macOS runners (webkit-sim lane)"
status: review
created: 2026-10-17
topics: [webkit, simulator, ci, github-actions, iwdp, timing]
---

# Simulator speed on GitHub macOS runners (webkit-sim lane)

Question: why does the webkit-sim job take so long to boot and connect the Simulator (seen in run 39036078841), and
what makes it faster? Probe: `.github/workflows/sim-speed.yml` + `.github/scripts/sim-speed-*.{mjs,sh}` (boot, connect,
one page load, marks, host sampler; imports `packages/measure-webkit/src` read-only). Nothing here is phone time and no
counts are taken. Revision 2 answers the review in `research/notes/2026/10-17-sim-speed-review.md` (11 issues); every
number below was re-derived from `gh run view <id> --log` of the four runs and, for host load, from the runs' artifacts.

## Answer first

- The wait is **host capacity, not wait logic**. `simctl boot` returns in 1.3 to 11.0 s; `simctl bootstatus -b` alone
  then takes 49 to 223 s on the standard `xcode-27` runner (3 CPUs, `hw.ncpu` in the facts step), 16 new-device jobs
  (MEASURED). Per-job peaks in `sampler.txt` (artifacts, 15 s sampler): 1-minute load 401 to 836, kernel_task 39 to
  202 % in `top`, compressor 1.1 to 2.5 GB, swap up to 324 MB (MEASURED, 24 standard jobs; one more job, R3 f6-3, has
  only 3 samples, peak 5.5). Load alone is not a clean signal: xlarge peaked at 322 to 459 too.
- **The largest measured lever, `xcode-27-xlarge`, is rejected (user decision 2026-10-17: no paid runners).** Kept as
  evidence: boot 40.6 to 50.3 s (n=5, mean 43.6 s), a saving of about 77 s against the 120.2 s median of the standard
  pool, or about 60 s against the pure base arm (103.2 s). Larger runners are always billed, also on public repos (see
  the cost row).
- **Largest remaining loss: no fail-fast.** In the baseline run, v2 session 1 lost a 120 s `Runtime.evaluate` timeout
  plus 397 s of "no page target" waits, and v2 session 2 pass 2 stalled for about 19 min until the run was cancelled
  (MEASURED, see "Baseline run"). Cutting these needs a fail-fast rule, not a faster host.
- **Keep Safari running between sessions.** The lane already boots once per job (`webkit-sim.yml:99`, `:112`,
  `:124-126` at 41ffc98, log "Device already booted, nothing to do."). What session 2 still pays is the Safari terminate
  + launch, a `T(3000)` sleep and the proxy start: 72 and 82 s from "serving" to "proxy up" (n=2). A probe session on a
  booted device with Safari left running attached in a median of 12.0 s (standard, n=18). Restarting Safari exists for
  determinism, so this is a determinism change and needs a count check.
- No gain: overlapping the boot with brew (brew went from 8 to 24 s to 242 and 278 s), host quieting (Spotlight,
  logging), booting out Simulator daemons, the image's own device. The "fast" connect (`openurl` launches Safari, poll,
  resend) gave no gain when it worked; its failures follow a proxy restart in the probe itself (INFERRED, see Caveats).
- Not tested (INFERRED): a direct Web Inspector or safaridriver connection instead of iwdp.

## Table

Run ids: R1 39038015877, R2 39041142432, R3 39043591653; baseline run 39036078841 (harness at 41ffc98). `s` = seconds.
**Boot** = wall time from the "boot begin" mark to the "bootstatus -b returned" mark (it includes `simctl boot`; e.g.
R2 qe-1: boot 116.8 s, `bootstatus` alone 96.5 s). n = jobs (one VM each). **Standard pool** = the 12 standard jobs
on a new device with no boot treatment (arms base, fast, early, f6); **base arm** = the 5 base jobs. quiet and qe are
treatments and are compared against both, not included in them.

| Option | Before | After | Runs | Status |
|---|---|---|---|---|
| xlarge runner (boot) | standard pool median 120.2 s (51 to 232 incl. treatments, n=16; 81 to 232 without, n=12); base arm median 103.2 s (81 to 201, n=5) | mean 43.6 s, median 42.9 s, 40.6 to 50.3 (n=5) | R2, R3 | MEASURED; saving 76.6 s (pool) or about 60 s (base arm). **Rejected: user, no paid runners** |
| xlarge runner (start to attached) | standard, fast connect: median 286.0 s, 218 to 476 (n=11); all standard attaches 285.9 s (n=18) | 108.5, 126.4, 180.8 s (n=3 of 5; xl-2 and xl-3 of R3 failed, 40 %) | R2, R3 | MEASURED for the fast connect only. With the lane's legacy connect: INFERRED (never run on xlarge). "Fewer timeouts": INFERRED, not supported (2 of 5 failed). Rejected with the row above |
| xlarge, job minutes and cost | standard 4.3 to 14.8 min (all 25 standard jobs, failed ones included) | 3.0 to 5.1 min (n=5; the failed R3 jobs took 5.1 and 5.1) | R1 to R3 | MEASURED (job start/end from `gh run view --json jobs`). Cost: CONFIRMED in the docs, see "Cost on a public repo" |
| Keep Safari running between sessions (device already booted) | harness session 2, "serving" to "proxy up": 71.8 s (v1), 82.2 s (v2); to warm-up done: 171.6 s, 177.6 s (n=2) | probe warm session, "serving" to "attached": all 21: 4.9 to 65.0 s, median 11.7; standard 18: 7.1 to 65.0, median 12.0 (17 without the outlier R3 combo-2 at 65.0: 7.1 to 21.5); xl 3: 4.9, 6.2, 9.4 | 39036078841, R1 to R3 | MEASURED, but not like for like: the harness interval includes Safari terminate + launch, `T(3000)` and `phoneIds()`, and its warm-up figure a full warm-up pass; the probe measures one page load. Saving per extra session about 60 to 70 s: INFERRED (n=2) |
| Second boot of the same device (`reboot` sessions) | standard 57.6 to 219.4 s (n=18), xl 27.8 to 57.2 s (n=3) | 0: the lane already boots once per job | R1 to R3 | MEASURED; CONFIRMED that the lane does not reboot (`webkit-sim.yml:99,112,124-126`@41ffc98) |
| Boot overlapped with brew (arm bg) | boot 80.8 and 201.0 (base, R1) + brew 8 to 24 | boot 247.6 and 285.1 with brew 241.7 and 277.7 inside it | R1 (2) | MEASURED, no gain |
| Host and Simulator quieting (arm quiet) | base arm median 103.2; pool median 120.2 | 50.9, 144.3 | R1 (2) | MEASURED, no gain shown (n=2, noise larger than effect) |
| Daemons booted out during boot (arm qe) | base arm 103.2; pool 120.2 | 116.8, 96.0 | R2 (2) | MEASURED, no gain |
| Image's own device (arms pre, combo) | pool median 120.2 (new device) | median 92.5, 82.8 to 161.5 (n=7) | R1 to R3 | MEASURED, weak; it is also a different device |
| Fast connect (`openurl` launches Safari, poll, resend) | legacy, standard base arm, "serving" to "attached": 142.2, 143.3, 175.3 s | 100.0 to 174.3 s when it works (standard, n=9, bg arm excluded) | R1 to R3 | MEASURED, no gain; failures INFERRED probe-side (Caveats) |
| Early proxy (before first openurl) | n/a | listed no tab until the probe restarted the proxy (early-1, early-2) | R2 (2) | MEASURED, does not work as tried |
| Preinstalled runtime | create 0.9 to 7.8 s | n/a | R1 to R3 | CONFIRMED: `check-simulator.sh --create` already finds iOS 27.0 (24A434); nothing to install or cache |
| Cache brew/iwdp | brew 8.4 to 23.7 s (bg arm excluded) | n/a | R1 to R3 | INFERRED: saves at most 8 to 24 s |
| Parallel jobs | per job boot unchanged | n/a | | INFERRED: more VMs do not shorten one VM's boot; they only parallelise the lane |
| Direct Inspector / safaridriver | n/a | n/a | | INFERRED, untested |

### Cost on a public repo

The repo is going public. GitHub's billing docs (fetched 2026-10-17):

- "GitHub Actions usage is free for self-hosted runners and for public repositories that use standard GitHub-hosted
  runners." and "Larger runners are always charged for, even when used by public repositories or when you have quota
  available from your plan." (https://docs.github.com/en/billing/concepts/product-billing/github-actions, CONFIRMED)
- "The larger runners are not free for public repositories." and "Included minutes cannot be used for larger
  runners."; rows "macOS 3-core or 4-core (M1 or Intel) | `actions_macos` | $0.062" and "macOS 5-core (M2 Pro) |
  `macos_xl` | $0.102" (https://docs.github.com/en/billing/reference/actions-runner-pricing, CONFIRMED)

So on the public repo a standard `xcode-27` job costs $0 and an xlarge job about $0.31 to $0.52 (3.0 to 5.1 min at
$0.102, INFERRED: that `xcode-27` bills as the standard 3-core row and `xcode-27-xlarge` as the 5-core row rests on
`hw.ncpu` 3 and 5 in the facts step). The earlier "xlarge is cheaper" held only while every minute was billed; it does
not hold now, and the user rejected paid runners.

### Baseline run 39036078841 (harness, standard runner, 2 VMs)

All MEASURED from the job log timestamps:

| Session | Serving to proxy up | Serving to warm-up done | Losses |
|---|---|---|---|
| v1, 1 | 224.6 s | 463.6 s (about 7.7 min) | an 81 s tab wait (65 tries), then the URL opened again (ask 2); later, pass 2 attempt 1 failed on a 120 s LayerTree timeout |
| v1, 2 | 71.8 s | 171.6 s | none before warm-up |
| v2, 1 | 56.6 s | 752.6 s (about 12.5 min) | a 120 s `Runtime.evaluate` timeout, then 8 "no page target" waits up to 397 s of 480 s |
| v2, 2 | 82.2 s | 177.6 s | pass 2 began 13:55:45, failed 14:14:58 (LayerTree timeout), then a 1006 close at 14:24:08, then `ECONNREFUSED` every 0.5 s until the run was cancelled at 14:25:53 |

These waits come from scale-8 deadlines (`webkit-sim.yml:117-118`@41ffc98 sets `FW_WK_TIMEOUT_SCALE` 8,
`FW_WK_ATTEMPTS` 3): `reconnect` waits `T(60000)` = 480 s (`wip.mjs:123`), `runAsync` `T(120000)` (`wip.mjs:63`), and
`openUrl` `T(120000)` (`sim.mjs:101`) (CONFIRMED in code). An `ECONNREFUSED` on the proxy port means the proxy is gone,
yet the loop keeps polling to its 480 s cap (INFERRED from the log).

## Cause of the connect time

CONFIRMED in code, harness at 41ffc98: fixed sleeps scaled by `T()` (`session.mjs:63` `T(3000)` before the first
`openurl`, `wip.mjs:125` `T(1500)` in `reconnect`, `wip.mjs:136` `T(2000)` after each navigation), Safari terminate +
launch on every session (`sim.mjs:84-92`; the comment at `:84` says it is there "so the run starts from the same
state"), and `phoneIds()` with an unscaled 15 s `idevice_id` timeout (`sim.mjs:119`) that fails closed under load (R1
bg-2: "idevice_id -l failed; not starting the proxy").

Per pass at scale 8 (INFERRED, computed, not measured): a pass with seek runs 4 seek navigations (`seek.mjs:50`,
default `ns` of 4) and, from pass 2 on, 1 navigation home (`determinism.mjs:19`); each sleeps `T(2000)` = 16 s, so up
to 80 s of fixed sleep, plus each `close()` waits up to `T(3000)` = 24 s (`wip.mjs:86`).

iwdp behaviour. Source pinned: `google/ios-webkit-debug-proxy` v1.9.2 at 278bf4874e6d (= Homebrew 1.9.2_2 installed
in every job; `refs/upstream/sources.lock.yaml`, clone `.cache/upstream/ios-webkit-debug-proxy@278bf48`). The code
shows the tab list is event-driven (CONFIRMED): `iwdp_on_applicationConnected` (`src/ios_webkit_debug_proxy.c:1197-1200`
@278bf48) records the app and sends `forwardGetListing` through `iwdp_add_app_id` (`:1180-1188`);
`iwdp_on_reportConnectedApplicationList` (`:1303-1337`) does the same for apps already running; pages enter the list
in `iwdp_on_applicationSentListing` (`:1339`). The code also shows a Safari launched after the proxy is handled by
`applicationConnected`, so it does **not** show that such a Safari stays unlisted. Why the first `openurl` after a fresh
boot shows no tab for a while (MEASURED in every first session) is therefore INFERRED, not explained by this code.

## Caveats and failures

- Fast connect failures: R2 combo-1 and combo-2 (`no tab (0 tabs)`), R3 f6-1 and f6-3 (`0 tabs`), R3 combo-1, xl-2
  and xl-3 (`fetch failed`). In all three `fetch failed` jobs every poll after the mark "proxy restarted" failed with
  `fetch failed` (xl-2: 26, xl-3: 25, combo-1: 17 polls), although the restart logged "proxy up" (MEASURED). Code at
  d97ffab (`.github/scripts/sim-speed-probe.mjs:160`) restarts the proxy after the third `openurl`; `stop()`
  (`sim.mjs:157`@41ffc98) sends SIGKILL after 2 s without waiting for the exit, and after "proxy up" the probe never
  checks `alive()` and polls the same ports to its 240 s deadline. A refused tabs port after a successful "proxy up"
  fits a new proxy that died or lost the port to the old one (INFERRED; proxy output was empty). So these failures
  are most likely a probe bug, not host load, and the fast connect is neither validated nor shown less reliable.
  Fix before reuse: await the old proxy's exit, check `alive()` while polling, log the exit code.
- R3 base-1 and base-2 failed on load (`simctl list devices` ETIMEDOUT, `simctl openurl` timed out): the capacity
  problem (MEASURED).
- Standard runners are noisy: boot 51 to 232 s on identical steps. Compare medians, n ≥ 5.
- Round 1 `du` after boot polluted connect timings; removed in round 2. Connect is compared from the "serving" mark.
- One mistake: during this task I ran `launchctl disable` on a local device while another agent held the sim-lock; I
  reverted it. Always check the lock first.

## Determinism risks of each change

- **xlarge** (rejected): same image, same iOS build, same WebKit; only host speed changes. Timing-sensitive counts
  (lazy images, late scripts) could move.
- **Keep Safari running between sessions**: Safari is restarted today so each session starts from the same state
  (`sim.mjs:84`). Keeping it carries cookies, localStorage, HTTP cache and tab state into the next session. Needs a
  clean page state (about:blank, clear website data) and, before adoption, a check over ≥ 3 CI jobs that session-2
  counts with Safari kept equal those of a session 2 with Safari restarted (policy kMax 4, tMax 24).
- **Fail fast**: no effect on counts; it ends a doomed pass sooner and leaves the retry to the next attempt or job.
- **Image's own device**: iPhone 18 Pro Max, different viewport than `fw-iphone-27`; counts change. Do not use.
- **Shorter sleeps / polling**: safe only with a condition that proves readiness (tab listed, `readyState`, network
  idle); a fixed sleep removed without one can read the page early.
- **Raising/retrying `phoneIds` timeout**: no effect on counts.

## Recommendation (ranked by seconds saved per job, paid runners excluded)

1. Fail fast: when the proxy is gone (`ECONNREFUSED` on its port, 1006 close) or reports "no page target" for more
   than one or two tries, restart the proxy at once or abort the attempt; lower the scale-8 caps on `reconnect`
   (`wip.mjs:123`, 480 s) and on evaluate/LayerTree waits (`wip.mjs:63`, 120 s). Baseline losses this targets: 397 s +
   120 s (v2 session 1), about 19 min plus cancellation (v2 session 2) (MEASURED losses; saving INFERRED).
2. Keep Safari running between sessions (the device already boots once per job): skip terminate + launch and the
   `T(3000)` sleep when Safari is up, reset page state instead; about 60 to 70 s per extra session (INFERRED from n=2,
   counted here only, not again in 3). Adopt only after the session-2 count check above.
3. Replace `T()`-scaled fixed sleeps with polling conditions (up to 80 s of navigation sleep per pass plus `close()`
   waits of up to 24 s each, INFERRED, computed).
4. Resend `openurl` every 6 s while no tab is listed instead of one 80 s window (baseline v1 session 1 waited 81 s);
   unvalidated until the probe's proxy restart is fixed (INFERRED).
5. Scale or retry the 15 s `idevice_id` timeout (`sim.mjs:119`).
6. Skip: xlarge (rejected, user: no paid runners), boot/brew overlap, quieting, bootout, image device.
7. For feedback loops use dispatch inputs vms=1 sessions=1.

## What this changes in the plan

- Section 4.1 (Three lanes), WebKit Simulator lane: the lane stays on the free standard `xcode-27` runner; add
  fail-fast proxy/target handling and "keep Safari between sessions, gated by a session-2 count check" as the speed
  work, owned by the ci-webkit owner.
- Section 12.0 (Decisions made 2026-10-17): record "no paid larger runners" with the xlarge evidence (boot about 60 to
  77 s faster) as the rejected alternative.
