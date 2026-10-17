# Simulator speed on GitHub macOS runners (webkit-sim lane)

Question: why does the webkit-sim job take so long to boot and connect the Simulator (seen in run 39036078841), and
what makes it faster? Probe: `.github/workflows/sim-speed.yml` + `.github/scripts/sim-speed-*.{mjs,sh}` (boot, connect,
one page load, marks, host sampler; imports `packages/measure-webkit/src` read-only). Nothing here is phone time and no
counts are taken.

## Answer first

- The wait is **host capacity, not wait logic**. `simctl boot` returns in 2 to 11 s; `simctl bootstatus -b` then takes
  41 to 231 s on the standard `xcode-27` runner (3 vCPU, 7 GB) while the host sits at load 450 to 700, kernel_task about
  29 %, memory compressor 1.2 to 2 GB, swap up to 324 MB (MEASURED, sampler.txt in every artifact).
- **Biggest lever: the larger runner `xcode-27-xlarge`** (5 CPU, 14 GB): boot 41 to 50 s (5 jobs) against a median of
  120 s (16 jobs) on standard; start to "Safari attached" about 126 s against about 286 s. Even at $0.102 against $0.062
  per minute the probe job is cheaper (3.0 to 4.7 min, about $0.31 to $0.48, against 6.5 to 15.5 min, about $0.40 to
  $0.96). Prices from the GitHub docs (INFERRED for this org: a pool must exist; it did).
- **Second biggest: never boot twice.** A second session on the same booted device with Safari still open attached in 5
  to 22 s (median 12 s, standard) against 101 to 218 s for session 2 of the harness in run 39036078841; a second boot of
  the same device cost 58 to 219 s (standard).
- No gain: overlapping the boot with brew (work is conserved, brew went from about 11 s to 240 to 280 s), host quieting
  (Spotlight, logging), booting out Simulator daemons, the image's own device, a "fast" connect that launches Safari
  with `openurl` instead of terminate + launch.
- Not tested (INFERRED): a direct Web Inspector or safaridriver connection instead of iwdp. The proxy itself is cheap on
  a quiet host; what is slow is the host, so it would not remove the boot cost.

## Table

Run ids: R1 39038015877, R2 39041142432, R3 39043591653; baseline run 39036078841. `s` = seconds. Boot = `bootstatus
-b` wall time. n = jobs (one VM each).

| Option | Before | After | Runs | Status |
|---|---|---|---|---|
| xlarge runner (boot) | 120 s median, 51 to 231 (n=16 standard, new device) | 43.8 s mean, 41 to 50 (n=5) | R2, R3 | MEASURED |
| xlarge runner (start to attached, legacy-equivalent) | about 286 s median (n=14) | 109, 126, 181 s (n=3; 2 of 5 xl jobs failed, see below) | R2, R3 | MEASURED, thin |
| xlarge, job minutes | 6.5 to 15.5 min | 3.0 to 4.7 min | R1 to R3 | MEASURED |
| Reuse the booted device and Safari for the next session | 101 to 218 s (harness session 2) | 5 to 22 s (n=12), xl 5 to 9 s | 39036078841, R1 to R3 | MEASURED |
| Second boot of the same device | 58 to 219 s (standard), 28 to 57 s (xl) | 0 (do not reboot) | R1 to R3 | MEASURED |
| Boot overlapped with brew (arm bg) | boot 81 to 201 + brew 11 | boot 248 to 285 with brew 242 to 278 inside it | R1 (2) | MEASURED, no gain |
| Host and Simulator quieting (arm quiet) | 51 to 201 (base) | 51, 144 | R1 (2) | MEASURED, no gain (n=2, noise larger than effect) |
| Daemons booted out during boot (arm qe) | 120 median | 117, 96 | R2 (2) | MEASURED, no significant gain |
| Image's own device (arms pre, combo) | 120 median (new device) | 92 median (83 to 161, n=7) | R1 to R3 | MEASURED, weak; it is also a different device |
| Fast connect (`openurl` launches Safari, poll, resend) | legacy connect 142, 143, 175 s | 100 to 174 s when it works | R1 to R3 | MEASURED, no gain, less reliable |
| Early proxy (before first openurl) | n/a | lists no tab until a restart or later openurl | R2 | MEASURED, does not work |
| Preinstalled runtime | create 3 to 8 s | n/a | R1 to R3 | CONFIRMED: `check-simulator.sh --create` already finds iOS 27.0 (24A434); nothing to install or cache |
| Cache brew/iwdp | brew 8 to 24 s | n/a | R1 to R3 | INFERRED: at most 8 to 24 s |
| Parallel jobs | per job boot unchanged | n/a | | INFERRED: more VMs do not shorten one VM's boot; they only parallelise the lane |
| Direct Inspector / safaridriver | n/a | n/a | | INFERRED, untested |

Cause of the connect time (CONFIRMED in code, harness at 41ffc98): fixed sleeps scaled by `T()`
(`session.mjs:63`, `wip.mjs:125`, `wip.mjs:136`), Safari terminate + launch (`sim.mjs:85-92`), and `phoneIds()` with an
unscaled 15 s `idevice_id` timeout (`sim.mjs:119`) that fails closed under load (R1 bg-2: "idevice_id -l failed; not
starting the proxy"). `webkit-sim.yml:117-118` sets `FW_WK_TIMEOUT_SCALE` 8 and `FW_WK_ATTEMPTS` 3, so at scale 8 the
navigation sleeps alone sum to about 80 s per pass.

iwdp behaviour (CONFIRMED, google/ios-webkit-debug-proxy `src/ios_webkit_debug_proxy.c` at 278bf4874e6d: applicationConnected
line 1197, applicationSentListing line 1339): a page is listed only after the proxy has seen the app connect and its
listing event; Safari launched after the proxy shows no tab until a later event or a proxy restart. That is why the
first `openurl` after a fresh boot is dropped or unlisted in every first session (MEASURED).

## Caveats and failures

- R3: 5 of 9 fast-connect jobs ended `no tab (0 tabs)` or `no tab (fetch failed)` (f6 2 of 3, combo 1 of 3, xl 2 of 3).
  This is a probe-side proxy fragility I did not root-cause (proxy output was empty); it does not affect the boot
  numbers, but it means the fast connect is not a validated replacement. base-1 and base-2 failed on load
  (`simctl list devices` ETIMEDOUT, `simctl openurl` timeout) which is the same capacity problem.
- Standard runners are noisy: boot 51 to 231 s on identical steps. Compare medians, n ≥ 5.
- Round 1 `du` after boot polluted connect timings; removed in round 2. Connect is compared from the "serving" mark.
- One mistake: during this task I ran `launchctl disable` on a local device while another agent held the sim-lock; I
  reverted it. Always check the lock first.

## Determinism risks of each change

- **xlarge**: same image, same iOS build, same WebKit; only host speed changes. Counts come from DOM/layout, not wall
  time, so classes should not move, but timing-sensitive counts (lazy images, late scripts) can: re-run the
  class check over ≥ 3 CI jobs (policy kMax 4, tMax 24) before trusting it.
- **Warm reuse of device and Safari**: carries cookies, localStorage, HTTP cache and Safari tab state into the next
  session. Needs a clean page state (about:blank, clear website data) and a check that counts of session 2 equal
  those of a cold session 2.
- **Image's own device**: iPhone 18 Pro Max, different viewport than `fw-iphone-27`; counts change. Do not use.
- **Shorter sleeps / polling**: safe only with a condition that proves readiness (tab listed, `readyState`, network
  idle); a fixed sleep removed without one can read the page early.
- **Raising/retrying `phoneIds` timeout**: no effect on counts.

## Recommendation (ranked by seconds saved per job)

1. Run the sim lane on `xcode-27-xlarge` (about 80 s on boot and about 160 s start to attached, and fewer
   load-induced timeouts).
2. One boot per job: run all sessions on the same booted device (and one Safari), saving 100 to 200 s per extra
   session; reset page state between sessions.
3. Scale deadlines, not sleeps: replace `T()`-scaled fixed sleeps with polling conditions (about 80 s per pass at
   scale 8).
4. Resend `openurl` every 6 s while no tab is listed instead of one long window; start the proxy after Safari is up.
5. Scale or retry the 15 s `idevice_id` timeout (`sim.mjs:119`).
6. Skip: boot/brew overlap, quieting, bootout, image device.
7. For feedback loops use dispatch inputs vms=1 sessions=1.
