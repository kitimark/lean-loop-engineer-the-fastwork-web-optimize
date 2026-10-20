# platform-willchange

Cause (CONFIRMED by diff): 4d724e12 ("platform: gate fixes") deleted `will-change: transform` from `.artboard`
(stage.module.css, platform.stageBg) and `.track` (visuals.module.css, platform.marquee). The original sets it on
`.start-selling-platform-stage-artboard`, `-secure-currencies-track`, `-profile-reviews-track` (assets/2.gBuqKVzi.css).
It was removed while the original read `auto` because the port had no scene attribute; 8276822d
(platform-scene-faithful) added `data-fw-scene`, so the original now reads `transform` when active.
The paused rule (`will-change: auto !important` under `[data-fw-scene=paused]`) is the original's own and stays.
Default arm verified (run 39266552780): stageBg and marquee pass in both engines.
Fix: both declarations restored; footprint.gen.json and FootprintData.lean regenerated (part-footprint --write).
No Lean decision logic changed (PlatformScene untouched).
Verified locally: apps/site test + typecheck, runner test, ci-paths test, lean check.sh green.
Round 1 (v2-proved arm, run 39271938577, branch tip 49f21c7f, dispatched with
`gh workflow run breakpoint-gate --ref ci/platform-willchange -f preset=v2-proved -f parts=platform,platform.stageBg,platform.sweep,platform.glint,platform.entries,platform.marquee`;
the old command `parts=platform` skipped the subparts, run 39269772180):
- site and all 7 gate jobs (3 chromium, 4 webkit) succeeded and produced raw JSON; the merge job failed twice (attempt 2 too) in
  setup-lean: elan download SSL error, infra. The reviewer recomputed the verdict from the artifacts (merge-gate.mjs + summary).
- chromium: platform.stageBg and platform.marquee FAIL in every probe block (artboard will-change 160, track 40: orig
  `transform`/running, port `auto`/paused); platform.glint FAIL desk 1/14 (dash w 44.1 vs 0 at desk-641). webkit: pass,
  but both sides read paused, so only the default arm covers the running state.
- Cause (INFERRED from source + artifacts): v2-proved sets engine.scene=hidden-pause, which pauses the platform scene while
  the section is off-viewport (engine.scene/index.tsx:24-50); the original keeps it running. Not the will-change CSS.
  Closed here as a finding; follow-up: engine.scene hidden-pause vs the original's play-state on chromium (C3 decision).
- platform.card will-change differs in raw data on both arms but is in no verdict (the platform row passes).
- Not run by the narrowed scope (listed, not judged): platform dark cells, hover/pointer-cross cells, height probes
  (84 of the 124 probes).
- Mapping: the port's `.track` (visuals.module.css) is the original's profile-reviews track; the currencies track has no port element.
