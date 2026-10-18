# content-people-pain-commission handoff

State: branch worktree-wf_e6ffd6eb-9d3-2, one commit. Site vitest 71 files / 5029 tests pass, tsc clean, local aot build
passes (debug only, not a result). No CI run made.

Done
- people/assets.ts: Vite glob of snapshot/site/selling/sellers/<profile-id>/ (six RING_ORDER dirs only; avatar, cover, post-*, service-*). Maps profile/post/service ids to files (exceptions listed in the file). assets.test.ts checks every data id resolves.
- Pictures are inline `background-image` on the existing neutral-fill spans (CSS adds background-size/position), so DOM
  shape and boxes are unchanged: deck avatar, cover, post tiles, audio vinyl label (cover), service thumbs; o faces, seller
  card tiles and avatar; carousel ring avatars (RING_ORDER = showcase order, nodes/2.DyWL8TcE.js 11270).
- commission: client faces 1-3, direct/compact arrow: ONE <img> direct child of .clientDiagram, src swapped in a JS effect from matchList('mq.c1000') (as the original; round 2), typing avatar
  = avatar-john.jpg. Why-bring button calls openDrawer from overlays.drawer (no overlays.* edit needed).
- land.ts hunk reverted; reads now come from the site-assets branch (merged, f8e5d422).
- Round 2: stale placeholder comments fixed. Follow-ups (lead rows): deck-panels-lean, people-o-glyph, people-pain-deferral.
- Finding: the original's pain section has no drawings (text notes only).
- Gate: ci/content-people-pain-commission, breakpoint-gate both engines (run ids in the report).

Open
- Deck tabs Services/Reviews/About are still empty panels (reviewers r1-r12 and about logos are in sellers/). Needs a
  Lean-first panel spec.
- Pain drawings: none found in the original's pain section (notes are text); nothing added.
- Content-visibility deferral (original CSS: [data-start-selling-render=deferred], contain-intrinsic-block-size auto
  var(--start-selling-intrinsic-block-size, 100vh), set by dE deferRendering at JS 2692-2703) NOT added: it needs a Lean
  box rule (measured height kept as intrinsic size) and a zones CI run to prove no box moves.
- claim.svg/pin.svg icons and the o.svg glyph are still drawn with CSS shapes.
- apps/runner/src/fw.ts shows a mode-only change from pnpm install; not committed.
Read first: apps/site/src/parts/people/assets.ts.
