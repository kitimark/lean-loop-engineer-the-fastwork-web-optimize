---
title: Adversarial review of the sim-speed note (4b54e32)
date: 2026-10-17
status: CONFIRMED
---

# Adversarial review of the sim-speed note

One fresh-context reviewer agent (workflow `sim-speed`, read-only) checked research/notes/2026/10-17-sim-speed.md at 4b54e32 against the CI logs and the harness at 41ffc98. Fixes go to sim-speed-fix.

**Verdict: changes-requested**

I checked the note (`research/notes/2026/10-17-sim-speed.md` at 4b54e32) against the logs of runs 39036078841, 39038015877 (R1), 39041142432 (R2) and 39043591653 (R3), the baseline run's artifacts, and the harness at 41ffc98.

**What holds up:**
- The boot numbers reproduce:
  - standard runner, new device: median 120.2 s, range 51 to 231 s, n=16
  - xlarge: 40.6 to 50.3 s, n=5
  - image device: median 92.5 s, range 83 to 162 s, n=7
  - quiet arm: 51 and 144 s; qe arm: 117 and 96 s
  - second boot: 58 to 219 s standard, 28 to 57 s xlarge
  - boot overlapped with brew: brew took 242 and 278 s
- The cited lines `session.mjs:63`, `wip.mjs:125` and `:136`, `sim.mjs:85-92` and `:119`, `webkit-sim.yml:117-118`, and iwdp `:1197` and `:1339` match the code.
- No personal data in the branch diff.

**Issues:**

1. **HIGH: recommendation 2 is already the default.**
   - The lane already boots once per job: `webkit-sim.yml:99`, `:112` (`FRESH: no`) and `:124-126` (`--keep`) at 41ffc98. The baseline log says "Device already booted, nothing to do."
   - So the 101 to 218 s for session 2 is not a boot. The probe's warm session saves time because it skips the Safari terminate + launch (`sim.mjs:86-92`), the `T(3000)` sleep and the warm-up.
   - The comment at `sim.mjs:86` says Safari is restarted "so the run starts from the same state". Removing that restart is a determinism change, not a boot change.
   - Fix: rename the item to "keep Safari running between sessions". Say the device already boots once per job. Merge its savings with recommendation 3 so they are not counted twice. Require a check that session-2 counts equal a cold session 2 before adopting it.

2. **HIGH: the "before" of 101 to 218 s cannot be reproduced, and the comparison is not like for like.**
   - In 39036078841 session 2, from "serving" to "proxy up" took 72 s (v1) and 82 s (v2). From "serving" to warm-up done took 172 s and 178 s.
   - There are only 2 values, so a range is not justified. The harness interval includes a warm-up pass; the probe measures one page load.
   - Fix: define the interval, report n=2 with both values, and state the mismatch.

3. **HIGH: the xlarge "start to attached" figure and "fewer load timeouts" mix runner and connect method.**
   - All 5 xlarge jobs used the fast connect (log lines read `fast1: attached`). The legacy connect that the lane actually uses was never run on xlarge.
   - 2 of the 5 xlarge jobs failed: R3 xl2 and xl3 ended with `no tab (fetch failed)`. That is 40 %, so "fewer timeouts" is not supported.
   - Only the boot saving (about 76 s) is supported.
   - Fix: run an xlarge arm with the legacy connect for at least 3 reps. Until then, mark the 160 s figure and "fewer timeouts" as INFERRED.

4. **MEDIUM: the "cheaper" claim does not hold once the repo is public, and the job minutes are off.**
   - The repo is going public. GitHub's docs say standard hosted runners are free on public repos; I found no source saying larger runners are. On that reading, xlarge costs money that the standard runner does not.
   - Measured job minutes:

     | Runner | Note says | Logs show | Detail |
     |---|---|---|---|
     | xlarge | 3.0 to 4.7 min | 3.0 to 5.1 min | the failed jobs took 5:08 and 5:06 |
     | standard | 6.5 to 15.5 min | 4.3 to 14.8 min | the longest is quiet1 at 14:46 |

   - Fix: restate the cost for a public repo and correct both ranges.

5. **MEDIUM: the warm-session range leaves out an outlier.**
   - R3 combo2 `warm2` took 65.0 s to attach (`openurl #1` took 45 s, `#2` took 105 s).
   - The full data is 21 warm sessions from 4.9 to 65.0 s; the 18 on standard runners run from 7.1 to 65.0 s. The note says "5 to 22 s, n=12".
   - Fix: report all values, or the median with the outlier named.

6. **MEDIUM: the iwdp cause is marked CONFIRMED but the cited code does not show it.**
   - Lines 1197 and 1339 are event handlers. They show that the tab list is event-driven, but `iwdp_on_applicationConnected` would also fire for a Safari launched after the proxy. They do not show that a later Safari stays unlisted.
   - There is no pinned clone under `.cache/upstream`.
   - Fix: mark it INFERRED and pin the source in `refs/upstream/sources.lock.yaml`.

7. **MEDIUM: the fast-connect failures look like a probe bug, not host load.**
   - In the R3 xl2 log, every poll after the line `fast1: proxy restarted` gives `fetch failed`, even though `proxy up` was logged.
   - Fix: check the proxy restart in `.github/scripts/sim-speed-probe.mjs` before calling the fast connect "less reliable".

8. **MEDIUM: the baseline run's biggest losses are not covered.**
   - v1 session 1 (about 8 min from serving to warm-up):
     - 225 s from "serving" to "proxy up"
     - an 81 s tab wait, then the URL was opened again
   - v2 session 1 (about 12.5 min):
     - a 120 s `Runtime.evaluate` timeout
     - 397 s of "no page target" waits
   - v2 session 2 pass 2 (until the run was cancelled at 14:26):
     - stalled from 13:56 to 14:15 (LayerTree timeout)
     - then a 1006 close
     - then `ECONNREFUSED`
   - These come from the scale-8 timeouts: `T(60000)` = 480 s in `wip.mjs:123`, `T(120000)` in `wip.mjs:63` and `sim.mjs:101`.
   - Fix: add a recommendation to fail fast when the proxy dies or reports "no page target", with lower caps on retries.

9. **LOW: the boot definition and the baseline pool are wrong.**
   - The note defines Boot as "`bootstatus -b` wall time", but the numbers are from boot begin to bootstatus return. Example: qe1 `bootstatus` alone took 96.5 s; the note says 117 s.
   - The n=16 baseline includes the 4 quiet and qe treatment jobs, and those arms are then compared against it.
   - Without them the median is still 120.2 s (n=12). The pure base arm alone has a median of 103 s (n=5), which makes the xlarge boot saving about 60 s.
   - Fix: correct the definition and give both baselines.

10. **LOW: small number mismatches.**

    | Item | Note | Logs |
    |---|---|---|
    | Standard start-to-attached, n | 14 | 18 successful jobs (median 286 s holds) |
    | xlarge boot mean | 43.8 s | 43.6 s |
    | Boot saving | 80 s in the note, 75 s in the recommendation | 76.6 s |
    | Device create | 3 to 8 s | 0.9 to 7.8 s |

11. **LOW: "80 s per pass" is computed, not measured.**
    - It is 4 seek navigations plus 1 navigation home, each sleeping `T(2000)` = 16 s.
    - The `close()` wait of up to `T(3000)` = 24 s (`wip.mjs:86`) is not cited.
    - Fix: mark it INFERRED and cite `wip.mjs:86`.

Scratch logs: `/private/tmp/claude-501/-Users-markmark-source-fastwork-com-web-optimize-lean/7b8c7c6d-7a95-4f3a-b051-47bf2935948b/scratchpad/logs/`

Sources:
- [GitHub Actions runner pricing](https://docs.github.com/en/enterprise-server@3.17/billing/reference/actions-runner-pricing)
- [Bitrise: GitHub Actions runners pricing 2026](https://bitrise.io/blog/post/best-github-actions-runners-in-2026-and-hidden-pricing-traps-to-avoid)
