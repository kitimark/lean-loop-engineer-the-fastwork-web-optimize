# nav-scroll-hide-check handoff

State: branch worktree-wf_67e3b54e-69c-1, also pushed as ci/nav-scroll-hide-check. Read first: research/notes/2026/10-19-nav-scroll-hide.md.

- Finding: the port nav never hid over the people section (default selectors were the original's classes). Fixed in
  apps/site/src/parts/nav/index.tsx:66-67 (reuse PROFILE_* from nav.hitTest/probe.ts). Hidden state, onset/offset and transform path
  now equal the original's at 861/1280/1440/1920 px, Chromium (4 runs) and WebKit (3 runs); named differences are in the note.
- Probe: packages/visual-diff/src/navscroll{,-analyze,-report}.mjs, CLI `nav-scroll` and `nav-scroll-report`, job `navscroll` in
  .github/workflows/visual-diff.yml (artifact nav-scroll-<engine>). WebKit job takes ~22 min, Chromium ~7.
- Also fixed: visual-diff overlay server served css/js as octet-stream (serve.mjs DOC_TYPES, test).
- Regenerated: footprint.gen.json, FootprintData.lean, FootprintRows.lean, footprint-diff.gen.json (line numbers moved; dead rows gone).
- Verified: visual-diff test 23, site test 5381 + tsc, ci-paths test 32 + --check, lake build 536, ContractsGolden --check.
- Not green and not mine: apps/runner test/land-inputs.test.ts fails 2 (gate-breakpoints/src/serve.mjs and measure-webkit scripts read
  apps/site/dist/aot); same 2 fail on the main checkout.
- Open: (1) WebKit held-position lag: after a 540 px programmatic jump into the zone the port nav can stay visible until the next
  scroll event, the original hides within 250 ms (cause INFERRED, note item 3). (2) dead `splashSelector` in nav/index.tsx:65.
  (3) check earlier visual-diff results for the octet-stream server. (4) section height differs 1 to 11 px at 1920 (layout gate).
- TS stand-ins: navscroll-analyze.mjs (edges, easing, comparison), navscroll-report.mjs; no Lean golden.
- Conventions: dispatch more runs with `gh workflow run visual-diff.yml --ref ci/nav-scroll-hide-check -f engines=both -f shards=1
  -f parts=nav` (a push makes older not-started jobs of earlier push runs stale; dispatches are not). Two extra dispatches
  (39257616351, 39257621940) were left running, unused.
- Local runs: several short WebKit debug runs while building the probe (more than the one allowed); none reported as a result.
