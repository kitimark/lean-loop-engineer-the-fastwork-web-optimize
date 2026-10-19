# port-completeness-gate (L7), fix round 1

State: branch `worktree-wf_ebd5ee90-ef5-1` (main merged). CI: the `port` job of visual-diff on `ci/port-completeness-gate`.
- Lean: `lean/Fw/Port/{Sections,Text,Attrs,Svg}.lean`, `lean/Fw/Site/Assets.lean`. Goldens come from
  `lean/scripts/PortGolden.lean` into `packages/contracts/golden/port/`. `exclusions.json` is now `{entries, crawlSkip}`.
- Round 1: Assets gains `inlineNorm` (ECMAScript white space, Vite 8.3.4 `svgToDataURL`), `renameRows` (identity rows
  `bytes:`/`svgtext:` sha256, then manifest rows), `rename_renameRows` and `present_of_hit`, `crawlSkip` (`/__vendor/`),
  and the exclusion `/fonts/fastwork-Bold.ttf`. Sections drops nav.hitTest, morph.mount, hero.exit and engine.scene
  (`dropped`, with reasons), leaving 29 rows. It adds `roots_distinct` (decide) and `unrooted` (4 rows that own nothing
  until check 5), and `wf` requires `secOk`. The Svg doc states the 64-bit key truncation.
- Site side: `scripts/port/digest.mjs` scans `data:` URIs, `renameFiles` feeds `renameRows`. The tests check inlineNorm
  and renameRows against goldens, renameFiles on temp files, and node-distinct rows on snapshot + dist (FW_SITE_DIST).

Gap list on main (MEASURED, CI run 39221773141 at 01e784ce, artifact `port-report`; the local dist agrees):
- assets: 0 missing of 111. The two commission arrows are inlined (`inline:svgtext:`); Bold.ttf is excluded.
- svg: the nav wordmark loses its `<g>` (10 vs 9 elements; one missing, one extra). The platform.entries pin is a
  REAL GAP: the original prerenders an inline 24x24 svg, while Visuals.tsx:97 draws `<img /selling/icons/pin.svg>`, which
  is different art. Gap lane: render GenSvg `platform.pin`. people.deck/panel.tsx:38,65 uses the same img; check it
  against the original's client markup (INFERRED: the original JS holds the 24x24 pin).

TS stand-ins: the HTML tokenizer, the selector subset, the URL scanner, the `data:` scanner and identity hashing.
Accepted limits: checks 1 and 2 are Lean only; check 5 comes after C3; inlineNorm follows Vite 8.3.4 (re-check on a
bump); keys are 64-bit; the gate step stays advisory; unrooted rows are undecided until check 5.
Notes: land-inputs fails locally while `apps/site/dist` exists (serve.mjs/site-lane reads); it is green without it.
No checker ran because this session has no agent tool, so the docstrings were self-reviewed against the 6-point list.
Read first: `lean/Fw/Site/Assets.lean`, then `scripts/port/digest.mjs`.
