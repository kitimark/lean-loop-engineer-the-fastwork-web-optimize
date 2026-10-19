# nav-scroll-hide-check handoff (round 1)

State: branch worktree-wf_67e3b54e-69c-1, also pushed as ci/nav-scroll-hide-check. Read first: research/notes/2026/10-19-nav-scroll-hide.md
(runs table, mechanical run rule, results, differences with causes); per-run data: research/notes/2026/10-19-nav-scroll-hide-runs.md.

- Finding: the port nav never hid over the people section (default selectors were the original's classes). Fixed in
  apps/site/src/parts/nav/index.tsx:66-67 (reuse PROFILE_* from nav.hitTest/probe.ts). After the fix, onset/offset, class flip, CSS
  transition and end states equal the original's at 861/1280/1440/1920 px in Chromium and WebKit; 860 px hides in neither arm.
  Seven runs per engine (39251940538, 39253432942, 39253457408, 39257593393, 39257616351, 39257621940, 39264165879).
- Differences (each with cause or "cause unknown" in the note): Chromium section layout 1 to 12 px taller in the port (port stable at 4219.4 px at 1920, original varies up to 9 px between runs; edges 1 px,
  1920 one 16 px step); Chromium transform start lag 0 to 3 frames, cause = compositor start notification (pending frames = lag, 32
  of 32 edges), the port's lag is longer on 42 of 111 edge pairs, why: cause unknown; WebKit held-position race after a jump, either
  arm, 1 to 3 widths per run, cause unknown (bidirectional, 13 + 2 + 1 positions).
- Probe: packages/visual-diff/src/navscroll{,-analyze,-report}.mjs; CLI `nav-scroll`, `nav-scroll-report` (`--summary` prints only the
  cross-run tables). Job `navscroll` in .github/workflows/visual-diff.yml is gated: dispatch input `navscroll` (default false).
  Dispatch: `gh workflow run visual-diff.yml --ref ci/nav-scroll-hide-check -f engines=both -f shards=1 -f parts=nav -f navscroll=true`.
  WebKit job ~22 min, Chromium ~7. Pushes no longer start it.
- Also fixed: visual-diff overlay server served css/js as octet-stream (serve.mjs DOC_TYPES, test). Nav docstring clause shortened to 2 lines
  so footprint line numbers stay (`part-footprint --check` exit 0).
- Verified at the final commit: visual-diff test 29, site test 5394 + tsc, ci-paths test 32 + --check, `sh lean/scripts/check.sh` green.
- Not green and not mine: apps/runner test/land-inputs.test.ts fails 2 (gate-breakpoints/src/serve.mjs and measure-webkit scripts read
  apps/site/dist/aot); the same 2 fail on main, files untouched here.
- Open: (1) WebKit held-position race, cause unknown: hold 2 s per position, log scroll/resize/rAF per arm. (2) why the port's compositor
  start is later in Chromium (needs a trace). (3) why Chromium lays the port section out taller. (4) dead `splashSelector`
  (nav/index.tsx:65). (5) check earlier visual-diff results for the octet-stream server (follow-up, not done).
- TS stand-ins (no Lean golden): navscroll-analyze.mjs (edges, easing, frame comparison, lag), navscroll-report.mjs.
- Local runs: WebKit/Chromium debug runs while building the probe in round 0 (more than the one allowed); none reported. Round 1: none.
- work-graph.json not touched. One new CI dispatch in round 1: 39264165879.
