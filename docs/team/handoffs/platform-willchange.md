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
Open: CI proof. A push runs the default arm on both engines; preset=v2-proved needs workflow_dispatch:
gh workflow run breakpoint-gate --ref ci/platform-willchange -f preset=v2-proved -f parts=platform
Read the run summary for platform.stageBg and platform.marquee will-change readings.
