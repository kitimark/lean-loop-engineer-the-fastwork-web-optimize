# breakpoints-named-import handoff
- State: commit d3fe21d3 (change), round 2 on this branch; CI branch ci/breakpoints-named-import c1e669a8, base ci/breakpoints-named-import-base 3b7ca6a4.
- apps/site/src/breakpoints.ts uses a named import of `conditions` with a checked assignment; `neutralConditions()` removed.
- MEASURED (CI site-dist, runs 39352403687 base / 39352271160 change): entry-client 731,665 -> 626,880 B raw, 209,430 -> 204,919 B gzip-6.
- Gate: chromium pass both; webkit incomplete both with the same one not-ok cell (phone-rotation not-comparable), 0 fail.
- Verified locally: apps/site test + typecheck green; ci-paths test green. apps/runner test has 118 failures from the stale cloned fwcore (unknown op console.landLaneState), unrelated.
- Open: follow-up task for the Lean golden absent-key list plus build assertion; engine-source citations.
- Read first: research/notes/2026/10-20-breakpoints-named-import.md.
