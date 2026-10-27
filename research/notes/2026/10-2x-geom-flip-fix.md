# geom-flip-fix: the five flip look bugs (A1, A3a, A3b, A3c, A4)

Task geom-flip-fix, branch ci/geom-flip-fix. Source: research/notes/2026/10-27-end-columns-probe.md.

## What was fixed (CONFIRMED in Lean, proved)
- A1 columns stacked in Ub: the column row is a flex row again (Lean flip layout statements in lean/Fw/Parts/MorphGeomLook.lean).
- A3b earn double transform (-8 px), A3c phone actions inset (24 px), A3a animation time kept across the flip, A4 quiet leave:
  Lean models and a golden (packages/contracts/golden/morph-geom.jsonl lines layout, leave, move, flipCell, flipBand); the site
  code replays them (apps/site/src/parts/morph.geom/tracks.golden.test.ts, tree.test.ts).

## Flip-state cell (MEASURED on CI)
Cell: packages/gate-breakpoints/src/flip-cell.mjs, job flip-cell, 12 bands x m in {0, .25, .5, 1}, bound 1 px from the Lean golden.
- Run 40508656325 (fb742cf55), morph.geom:on, both engines: 47 of 48 readings pass; the failing one is 640x1000 m=1 (nav 976 px, both engines).
- Cause (MEASURED, INFERRED to be the whole cause): the phone grid knots end at 0.9999999999999999 for h = 1000
  (12/(h-52) plus 320 steps), so the K clipper tracks have no keyframe at offset 1 and WAAPI ends on the neutral value; the clippers stay 2x. Lean knots are
  exact rationals (last knot 1). Fix: last knot is exactly 1 (apps/site/src/parts/morph.geom/tracks.ts gridKnots, test in tracks.golden.test.ts).
  Run 40512085722 (a54d893b8): morph.geom:on passes 48 of 48 readings on Chromium and WebKit (MEASURED).
- The job steps end in `|| true`, so a failed cell shows as a green job. Read the artifact flip-cell-<engine>.
- geom-timed arm (webkit), run 40512085722: 2 of 24 readings fail (1280x800 nav/lang/earn: base pill hidden at y -72, flag at y 16;
  1920x1080 flag shows 0 of 5 columns; flip class off on both pages in both readings, cause not shown); run 40508656325 had 4 of 24 at m=0 after a real scroll back to top (lang, nav, earn edges; at 1280x800 21 images vs base 0, so, for run 40508656325 only, the flip had
  not left yet, INFERRED). Chromium timed: 0 fail, 12 of 24 skipped (the take guard, A5, task timed-take-retry). Follow-up: WebKit leave time, timed arm.

## Look report (MEASURED, pixels differing by more than 12 in a channel, share of the region)
Run 40508656325, morph.geom:on vs base, per engine over 12 bands: m = 0 equal (Chromium max 0.23 %, WebKit 1.38 %). For 0 < m <= 1 the columns region differs 65-98 %
and the nav region 57-88 % on both engines. So the pinned bound (regions equal to base) is not met in pixels although every rect is within 1 px.
Reasons: (1) the veil (A2, task geom-veil-restore) and the whole panel at m = 1; (2) images, below.
## Finding: images (follow-up)
INFERRED from the rects: base keeps an image's height at 0 < m < 1 (object-fit cover crops it), the flip scales images in both axes (the column scale s(m)), so image y edges
differ; the Lean faithful .image model is wrong in that range. The cell compares images by x edges only. A fix needs the image model changed in Lean (object-fit) first.

## Not done
- Chromium swipe-touch-v1 base vs flag x3 with morph.geom:on: needs workflow inputs, dispatch by the lead (command in the report).
- Accepted limits: veil (A2), take guard (A5), persistent wrappers (P4), class L is the user's look review, no phone run.
