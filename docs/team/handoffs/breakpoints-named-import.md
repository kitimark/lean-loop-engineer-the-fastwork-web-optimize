# breakpoints-named-import handoff
- State: apps/site/src/breakpoints.ts uses a named import of `conditions`; `neutralConditions()` and GenNeutral removed.
- Verified locally (debug build only): typecheck ok, check-breakpoints ok, entry-client JS 625,895 B raw / 204,470 B gzip, no matrix/edgePairs/backingTheorems.
- Open: CI artifact sizes (site-dist), breakpoint-gate and webkit-sim results, chromium-counts (expected no change).
- Not done (follow-ups): Lean golden list of absent bundle keys plus build assertion; engine-source citations.
- Read first: research/notes/2026/10-20-breakpoints-named-import.md.
