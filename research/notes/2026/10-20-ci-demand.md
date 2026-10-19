---
id: 2026-10-20-ci-demand
kind: note
title: "CI demand of the experiment in job-minutes (2026-10-17..19)"
status: final
created: 2026-10-20
topics: [ci, capacity, cost]
---

# CI demand estimate (lead, 2026-10-20 about 00:30 +0700)

Window 2026-10-17 11:19Z .. 2026-10-19 16:08Z (2.2 days). 2152 runs; run wall total 14748 min (MEASURED, gh run list).
Job-minutes = sum over workflows of wall x (job/wall ratio from a sample of the 6 newest runs >1 min per workflow, 87 runs, 405 jobs; MEASURED sample, INFERRED total):
- total ~30,200 job-min (~504 h): Linux arm ~25,200, macOS ~5,000
- per day ~13,700 job-min (Linux ~11,450, macOS ~2,260); a 30-day month at this pace ~410k (Linux ~345k, macOS ~68k)
- biggest: breakpoint-gate ~13,500 (ratio 4.0), chromium-counts ~5,500, mutants ~2,600, webkit-sim ~2,550 (90% macOS), wktr ~1,770 (85% macOS)
Caveats: run wall includes queue time; sample is the newest runs (some during the 2026-10-19 GitHub incident); ratios from 6 runs each.
