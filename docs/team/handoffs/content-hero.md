# content-hero handoff

State: branch worktree-wf_e6ffd6eb-9d3-1. Hero placeholders replaced by the original's content; DOM shape, classes and data-fw anchors unchanged.

Done (restated from snapshot/site/index.html prerender and nodes/2.DyWL8TcE.js):
- hero/index.tsx: headline "Show the world / what [accent] can do", supporting text, "Join waitlist", "RSVP Demo day" link (demo day URL, new tab), note.
- hero.countdown: labels days/hours/mins/seconds. hero.cue label was already "Scroll down".
- hero.orbit/data.ts: CARDS (name, role, cover, avatar per piece, same order as PIECES) + ONLINE_ICON; card.tsx takes cover/avatar; hero.deck uses CARDS[d.piece] (leobeer, bold, weng, mod).
- hero.accent/data.ts: generated from the original word list (base + 6 visible words, 3 boil-frame paths each, labels); stand-in wave removed.
- apps/runner/src/land.ts: apps/site inputs now include selling/hero/**, profile/online.svg, the two sellers avatars.

Verified locally (not a CI result): site vitest 70 files / 5026 tests pass, tsc clean, site build gates pass.

Open items (needs lead, outside my write list):
- apps/site/scripts/build.mjs must copy these from snapshot/site into dist/<engine>/selling/: hero/ (dir), profile/online.svg, sellers/ai-video-editor/avatar.jpg, sellers/ux-ui-designer/avatar.jpg. Until then the pictures 404 (img src is /selling/...).
- Original ring has an empty avif <source> per picture; not reproduced (DOM kept as before).
- No CI pushed: wave 1 gate decides.

## Round 2 (2026-10-19)
- Merged main and site-assets (land.ts taken from site-assets). hero.accent: snapshot path strings removed, labels/viewBox/inset kept, strokes back to `standInPath`. BLANK_GIF dropped from hero.orbit; accent CSS comment back to main.
- Verified locally: site vitest (5026), tsc, assets.test.mjs (every /selling/ URL listed). Breakpoint-gate on ci/content-hero: run id in the report.
- Limits: avif source not reproduced; counts not judged; accent strokes are stand-ins (svg-extract).
