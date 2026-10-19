# deck-panels-lean handoff (final design round)

State: branch worktree-wf_f0e4209d-fe6-3, main merged (svg-extract landed), final-round commit on top.

Done
- people.deck/icons.tsx holds no geometry: star, clock, play, mute and the four review dimension icons render through
  GenSvg with the ids people.star, people.clock, people.play, people.mute, review.bolt, review.shield, review.star, review.tag.
- feedPanels.tsx DimIcon removed (DimensionIcon in icons.tsx maps skill keys to ids); no geometry element left in people.deck.
  svg-guard passes with zero people.deck entries in svg-allow.json.
- Article byline dot has no class (inherits #737373), not the Services .dot rule.
- footprint.gen.json and FootprintData.lean regenerated after the merge conflict (part-footprint.mjs --write).
- Stats strip "★4.9" stays a text glyph: the original's template holds a plain <strong> text node, not an svg.
- svg-extract.test.ts: snapshotPaths now keeps only strings made of path-command characters; the prose
  "Music videos, aftermovies..." in the snapshot matched the 24-char run check against panels.data.ts (file outside
  this task's writes; lead may fold it into svg-extract writes).

Verified: apps/site test 82 files / 5288, typecheck.
Read first: apps/site/src/parts/people.deck/icons.tsx.
