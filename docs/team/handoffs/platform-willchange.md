# platform-willchange

Cause (CONFIRMED by diff): 4d724e12 ("platform: gate fixes") deleted `will-change: transform` from `.artboard`
(stage.module.css, platform.stageBg) and `.track` (visuals.module.css, platform.marquee). The original sets it on
`.start-selling-platform-stage-artboard`, `-secure-currencies-track`, `-profile-reviews-track` (assets/2.gBuqKVzi.css).
It was removed while the original read `auto` because the port had no scene attribute; 8276822d
(platform-scene-faithful) added `data-fw-scene`, so the original now reads `transform` when active.
The paused rule (`will-change: auto !important` under `[data-fw-scene=paused]`) is the original's own and stays; no flag differs.
Fix: both declarations restored; footprint.gen.json and FootprintData.lean regenerated (part-footprint --write).
No Lean decision logic changed (PlatformScene untouched).
Verified locally: apps/site test + typecheck, runner test, ci-paths test, lean check.sh green.
Round 1 (v2-proved arm, run 39271938577, branch tip 49f21c7f, dispatched with
`gh workflow run breakpoint-gate --ref ci/platform-willchange -f preset=v2-proved -f parts=platform,platform.stageBg,platform.sweep,platform.glint,platform.entries,platform.marquee`;
the old command `parts=platform` skipped the subparts, run 39269772180):
- site and all 7 gate jobs (3 chromium, 4 webkit) succeeded and produced raw JSON; the merge job failed twice (attempt 2 too) in
  setup-lean: elan download SSL error, infra, no code cause. So no merge verdict table exists; rows read from the artifacts.
- Artifact read (40 probes per engine, all six parts covered, will-change of orig vs port):
  webkit: 0 differences in platform.stageBg.artboard and platform.marquee.track (both read auto/paused on both sides).
  chromium: all 40 probes differ: orig `transform` (animation-play-state running), port `auto` (play-state paused) on
  artboard x4 and track. Also platform.card: orig `transform, border-radius`, port `auto`. Cause: the port's scene
  state is paused where the original runs on chromium (the port's own paused rule gives auto); the CSS declaration is
  present. Not fixed here: follow-up is why the port scene reads paused in chromium on the v2-proved arm
  (PlatformScene input), not will-change CSS.
- Not run by the narrowed scope (listed, not judged): platform dark cells, hover/pointer-cross cells, height probes
  (84 of the 124 probes).
- Mapping: the port's `.track` (visuals.module.css) is the original's profile-reviews track; the currencies track has no port element.
