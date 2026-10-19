# svg-extract handoff (fix round 1)

State: branch worktree-wf_f0e4209d-fe6-2, see git log.

- `apps/site/scripts/svg-extract.mjs` exports `extractSvg()` (writes only when changed) and runs standalone. It reads the
  nav wordmark, the accent words and 14 more artworks (`art` map: nav.globe, icon.bell, icon.calendar, platform.star/pin/
  shield, brand.mark, commission.chevron/underline/zero, hero.cue, drawer.close) from snapshot/site/index.html and
  nodes/2.*.js into the gitignored `src/svg.gen.json` (svg attrs + child shapes, class/style dropped).
- `build.mjs` calls `extractSvg()` itself (console preview and CI call it directly); `test` and `typecheck` scripts run the
  extraction first; the npm pre* hooks are gone.
- `src/GenSvg.tsx`: `GenSvg`, `art(name)`, `frames(name)`; renders with the original's viewBox and attributes.
- Parts now reading it: hero, morph.panel, hero.cue, overlays.drawer/signup, platform Visuals, commission, nav.langMenu,
  nav, hero.accent. No snapshot path string remains in a tracked file.
- Guard (`src/svg-extract.test.ts`): fails if any tracked file under apps/ or packages/ holds a 24-char run of any snapshot
  `d` string (html and script templates); no allowlist. Checked against the old Visuals pin path: it is caught.
- Reads declared in apps/runner/src/land.ts (apps/site: snapshot/site/index.html, snapshot/site/_app/**). The script builds
  its snapshot paths as files so land-inputs sees them as files.
- Footprint golden and lean FootprintData regenerated (--write), not hand-edited.
- Verified: apps/site test + typecheck, build.mjs --engine aot (15 pages, gates pass), ci-paths, land-inputs, runner test.
- Not run: browser, CI, pixel equality (the gate/visual run decides). Stand-ins left: langMenu check circle, short icon
  paths under 24 chars (close, search, check, mute) are not in the guard's reach.
- No Lean piece: extraction and rendering are glue; no decision logic. TS stand-in: none.
