# morph-panel-content handoff

State: branch worktree-wf_ded5198b-b6e-2. morph.panel now carries the original's English copy and links.
- apps/site/src/parts/morph.panel/content.ts: title, "Join waitlist" (cta), "RSVP Demo day", operated, copyright, privacy.
- index.tsx: RSVP anchor -> https://f.fastwork.co/demoday (target=_blank, rel=noopener, data-selenium demo-day);
  privacy -> https://fastwork.com/privacy; cta data-selenium other-role; bell/calendar via art ids (already).
- content.test.ts reads snapshot/site/_app/immutable/nodes/2.DyWL8TcE.js at test time (template anchors, backtick
  string literals, rsvp en entry), renders mui and plain, compares hrefs/strings. Nothing copied.
Verified: apps/site test+typecheck, ci-paths test, runner land-inputs test.
Outside write set: regenerated footprint.gen.json and lean/Fw/Parts/FootprintData.lean (line numbers only,
via scripts/part-footprint.mjs --write; the footprint test demands it).
Open: only English; other locales (rsvp th/id/vi/ar map) not ported. Pixel equality is for the gate.
Read first: content.ts, content.test.ts.
