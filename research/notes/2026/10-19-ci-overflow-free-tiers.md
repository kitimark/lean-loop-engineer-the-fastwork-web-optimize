---
id: ci-overflow-free-tiers
kind: note
title: "Other CI free tiers as overflow for macOS and Arm Linux jobs (2026-10-19)"
status: draft
created: 2026-10-19
topics: [ci, capacity, free-tier, macos, arm]
---

# Other CI free tiers as overflow for macOS and Arm Linux jobs

**Answer.** None of these services can carry a real share of our load for free. The free macOS supply is about
500 to 800 min/month in total (Codemagic plus Bitrise). Our macOS lanes ran about 5,100 wall-clock min in 2.2 days
(about 70,000 min/month), so free macOS overflow covers a few hours a month. Free Arm Linux is about 5,400 min/month
(Semaphore credits plus GitLab Free). Our Arm lanes ran about 8,700 min in 2.2 days (about 120,000 min/month), so that
covers about 1.4 days of demand per month (and the Semaphore part assumes free accounts may use ARM, UNKNOWN). The only large pool is GitLab for Open Source (Ultimate, 50,000 compute
minutes at cost factor 0.5). It needs an application, a public GitLab namespace and a pull mirror, and its macOS
runners are Beta. GitHub Actions already gives unlimited minutes; our limit is concurrency (20 jobs, 5 macOS), and
each extra service adds a second CI config to keep correct.

Demand figures: lead's MEASURED window 2026-10-17 11:19Z to 10-19 16:08Z (wall-clock, not job-minutes). The macOS sum
(webkit-sim + wktr + gate-gaps + wktr-fixtures) and the Arm sum (breakpoint-gate + chromium-counts + lean + visual-diff +
mutants) are my grouping of the lead's per-workflow totals (INFERRED: which runner each workflow uses).

| Service | Free minutes | macOS free | Arm Linux free | Concurrency (free) | OSS program | Status |
|---|---|---|---|---|---|---|
| Buildkite hosted | up to 2,000 Linux min/mo, Small only | no | no (AMD64 only; ARM64 Enterprise on request) | 20 vCPU hosted; 10 self-hosted jobs | yes, "special pricing", contact them | CONFIRMED [1] |
| Semaphore cloud | $15 credits/mo (about 2,000 Ubuntu x64 2-vCPU min) | not stated for free | not stated for free; ARM 2 vCPU is $0.003/min (about 5,000 min if allowed) | 20 jobs | old OSS-plan doc URL now redirects away; current page has none | CONFIRMED [2]; ARM/macOS on free UNKNOWN; OSS plan gone INFERRED [3] |
| Travis CI | trial 10k credits (1k Linux min), 14 days; "Free Trial Plans are currently unavailable" | macOS support ended 2025-03-31 | arm64 not listed in billing docs | 20 jobs (Free Plan) | OSS credits "on occasion", via support | CONFIRMED [4][5] |
| Bitrise Hobby | 300 credits/mo; credit-to-minute rate not on page | macOS Medium M4/M2 Pro listed for Hobby ($0.0072/min) | Linux is AMD EPYC (x86) | 5 concurrencies, 90 min build timeout, 1 private app | none; public apps "unlimited" (table) | CONFIRMED [6][7]; minutes per credit UNKNOWN |
| Codemagic personal | 500 macOS M2 min/mo, reset on the 1st | yes (M2, 8 cores, 8 GB) | Linux has no free minutes | 1 build (third-party; not on docs page) | not mentioned | CONFIRMED [8]; concurrency INFERRED |
| Cirrus CI | n/a | n/a | n/a | n/a | n/a | shut down 2026-06-01 CONFIRMED [9]; `cirrus-ci.org` did not resolve today MEASURED |
| GitLab.com Free | 400 compute min/mo | no (macOS: Premium, Ultimate, OSS program; Beta) | `saas-linux-small-arm64` cost factor 1, so about 400 min | not stated | see next row | CONFIRMED [10][11][12] |
| GitLab for Open Source | 50,000 compute min (period not stated), factor 0.5 on public projects | M1 medium factor 6, M2 Pro large 12; images incl. `macos-27-xcode-27` (beta) | yes, small/medium/large | not stated | OSI licence, public namespace, non-commercial; apply by form | CONFIRMED [10][12][13]; mirror eligibility UNKNOWN |

Notes on the GitLab path:
- Pull mirroring from GitHub needs Premium or Ultimate (CONFIRMED [14]); the OSS program grants Ultimate, so the mirror
  would work only after acceptance (INFERRED).
- How the 0.5 OSS factor combines with the macOS factor 6 is not stated (UNKNOWN [10]). If they multiply, 50,000
  compute minutes buy about 16,700 macOS M1 job-minutes, about 1 week of our macOS demand (INFERRED).
- Whether a project whose canonical repo is on GitHub qualifies is not stated; the page says to email the program
  (UNKNOWN [13]).

Not checked: Xcode 27 / macOS 26 image availability on Codemagic and Bitrise (UNKNOWN). Our WebKit Simulator and WKTR
lanes need it.

## Sources (read 2026-10-19)
1. https://buildkite.com/pricing/
2. https://semaphore.io/pricing
3. https://docs.semaphoreci.com/account-management/free-and-open-source-plans/ (301 to docs.semaphore.io, then 301 to
   /using-semaphore/organizations, which has no plan text)
4. https://docs.travis-ci.com/user/billing-overview/
5. https://docs.travis-ci.com/user/reference/osx/
6. https://www.bitrise.io/pricing
7. https://docs.bitrise.io/en/bitrise-build-hub/infrastructure/build-machine-types.html
8. https://docs.codemagic.io/billing/pricing/
9. https://macstadium.com/blog/cirrus-labs-is-joining-openai ; PostgreSQL removal patch
   https://www.postgresql.org/message-id/3ydjipcr7kbss57nvi67noplncqhesl5eyb6wgol4ccjxynspv%40yatlykpribmm
10. https://docs.gitlab.com/ci/pipelines/compute_minutes/
11. https://docs.gitlab.com/ci/runners/hosted_runners/linux/
12. https://docs.gitlab.com/ci/runners/hosted_runners/macos/
13. https://about.gitlab.com/solutions/open-source/join/
14. https://docs.gitlab.com/user/project/repository/mirror/pull/

## What this changes in the plan
- §11 R33 (CI capacity): add "other free CI tiers checked 2026-10-19 (`10-19-ci-overflow-free-tiers.md`): about
  500 to 800 macOS and at most 5,400 Arm free min/month, about 1% and 5% of demand; not a mitigation". The mitigations stay `paths:`
  filters, stale-run cancel and fewer job-minutes.
- §12 decision "No paid runners": no change. The GitLab for Open Source application is the one free option that could
  matter, and the user would have to apply. Record it as an open question for the user, not a plan step.
