# svg-extract handoff

State: branch worktree-wf_f0e4209d-fe6-2, one commit.

- `apps/site/scripts/svg-extract.mjs` reads the nav wordmark (9 paths) from snapshot/site/index.html and the accent
  base word plus the 6 visible words (3 boil frames each) from snapshot nodes/2.*.js (`LE`, `RE`) into the gitignored
  `apps/site/src/svg.gen.json`. Runs as pretest, prebuild(:runtime/:all) and pretypecheck; `pnpm gen:svg` by hand.
- Parts reading it: `hero.accent` (`strokePath`, replaces the stand-in wave), `nav` (wordmark replaces two rects).
- `src/svg-extract.test.ts`: shape check, plus a fail if a tracked file under apps/ holds a snapshot path string
  of >= 40 chars. Known offenders sit in `PENDING_CLEANUP` (hero, morph.panel, overlays.drawer/signup, platform
  Visuals, commission); task `snapshot-paths-cleanup` moves them and empties the list.
- Footprint golden regenerated (nav line shift only; Lean FootprintData regenerated with it).
- Verified: apps/site test (5149 pass), typecheck. Not run: build, browser, CI.
- Open: commission underline/zero frames and the waitlist/shield logos are also inline paths in index.html; not yet
  in svg.gen.json. No Lean piece: pure extraction/glue, no decision logic.
- Read first: svg-extract.mjs, hero.accent/data.ts.
