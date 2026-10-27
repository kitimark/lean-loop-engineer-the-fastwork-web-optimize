# geom-page-diff: why the whole-page region at m=1 differs (task geom-page-diff, graph r543)

Question: in CI run 40553185213 (breakpoint-gate on ci/geom-veil-restore) the look report of `morph.geom:on` against base at m=1
shows the whole-page region differing on 5.6-42.3 % of pixels on both engines, nav and columns only 0.05-3.1 %. Investigation only.

## Answer
A harness artefact in the base arm (b), on the platform section. No site bug found; the flip arm shows what the real tween shows.

- CONFIRMED (packages/premise-tests/src/look.mjs:19-27, 66-71): the look pins m by writing `--morph` and `data-fw-morph` on the nav,
  nothing else. The real driver also writes the platform fade: `--morph-fade = 1 - min(1, m / 0.55)` on the platform section
  (apps/site/src/parts/morph.tween/driver.ts:117-121; opacity and `blur(calc((1 - fade) * 12px))` in
  apps/site/src/parts/platform/platform.module.css:12-13). The pin bypasses the driver, so the base page keeps the platform at opacity 1.
- CONFIRMED (apps/site/src/parts/morph.geom/tracks.ts:177-178): in the flip the platform has its own tracks, `opacity = fade(m)` and
  `filter = blur(12 * (1 - fade(m)))` (WAAPI, fill both, applied by the observer of `data-fw-morph`, index.tsx:83-89). At m >= 0.55 that is opacity 0.
- MEASURED (local WebKit debug run, probe results/geom-page-diff/probe.mjs, computed style): at m=1 the platform has opacity 1 and
  `blur(0px)` in base, opacity 0 and `blur(12px)` in the flip. At the page bottom (the look scrolls to `scrollHeight`) the platform box
  spans the viewport (top < 0, bottom = innerHeight, all three bands), so base shows the dark card (#131922) and the flip shows the page behind it.
- Verdict for the pinned unit: cause = harness step look.mjs:19-27 (pin) without the platform fade; element = the platform section
  (`[data-fw="platform"]`); flip is right (tracks.ts:177-178 equals the driver's fade).

## Evidence from run 40553185213 (MEASURED, tables in results/geom-page-diff/bands.md, JSON in ci-40553185213/)
Share of pixels differing by more than 12 in a channel, m=1, look/on. "outside" = the pixels outside the nav box, derived from the
page and nav rows (table.mjs).

| band | page | nav box of page | nav | outside nav box |
|---|---|---|---|---|
| 390x844 | 0.091 | 0.912 | 0.003 | 1.000 |
| 640x360 | 0.080 | 0.898 | 0.004 | 0.750 |
| 640x1000 | 0.056 | 0.939 | 0.001 | 0.903 |
| 768x1024 | 0.209 | 0.759 | 0.001 | 0.865 |
| 1280x800 | 0.077 | 0.920 | 0.001 | 0.954 |
| 1920x1080 | 0.423 | 0.553 | 0.001 | 0.944 |

Both engines agree to 0.001 on every band except 641x700 (Chromium nav 0.031 against WebKit 0.003, page 0.141 against 0.115; not explained here).

- The page share is the outside area times 0.75-1.00: the page region is the nav region plus everything that is not the nav, and the
  second part differs almost entirely. The 42.3 % at 1920x1080 is the 44.7 % of the page outside the nav box times 0.944.
- Not scroll, not capture moment, not toolbar: m=0 is equal in all 24 readings (page 0.000 except 768x1024 0.010-0.011 on both engines),
  with the same scroll call and the same screenshot path; the m=1 shares are identical on the two engines, so they are layout facts, not render noise.
- Not the region box: the outside fraction is ~1 where the nav box is small (390x844: 1.000) and 0.75-0.95 elsewhere (the platform
  card is mostly dark, a few pixels equal after the 12-step threshold).

## Per-band images (local debug run; not a CI result)
One local WebKit run on this Mac (<= 5 min, site-dist artifact of the same run 40553185213), three arms: base, flip, and base+fade
(the base page pinned like look.mjs, plus the one driver write `--morph-fade` on the platform). Diff images (red: differs by > 12;
light blue: inside the nav box) are not committed (the render guard refuses images outside snapshot/); results/geom-page-diff/local-debug/maps.txt
has them as 64x24 text maps (maps.mjs). Page share at m=1, base against flip and
base+fade against flip:

| band | base vs flip | base+fade vs flip | outside nav, base vs flip | outside nav, base+fade vs flip |
|---|---|---|---|---|
| 390x844 | 0.090 | 0.001 | 1.000 | 0.000 |
| 1280x800 | 0.057 (see below) | 0.001 | 0.702 | 0.000 |
| 1920x1080 | 0.423 | 0.000 | 0.944 | 0.000 |

390x844 and 1920x1080 reproduce the CI numbers (0.090 and 0.423). Per horizontal strip (8 strips of the page height) at 1920x1080 the
difference of base against flip is 0.272 in the middle strips (the part left and right of the 1398 px nav box: 522 / 1920 = 0.272),
0.37 and 0.67-0.98 in the top and bottom strips; with the fade written on base every strip is <= 0.002. The same pattern holds at
390x844 (0.062 = 24 / 390 beside the box, 0.17 top and bottom) and 1280x800.

## Harness hazard seen locally (INFERRED, not in the CI run)
In the local run the base page at 1280x800 stopped at scrollY 6074 where the other two arms reached 7794 (scrollHeight 8594), so it
differed at m=0 as well (page 0.712 at m=0, against 0.000 for base+fade vs flip). The look scrolls once to `scrollHeight` and waits 1800 ms
(look.mjs:58-59); if the page grows after the call (lazy layout), an arm lands short. CI shows m=0 equal in 24 of 24 readings, so this
did not happen there, but the look has no check that both arms share a scroll position. Follow-up: assert `scrollY` equality per reading.

## Timed arm measures nothing (MEASURED zeros, INFERRED cause)
look/timed (`morph.geom:on,morph.tween:geom-timed`) shows 0.000 differences in every band, m and region on both engines. With
`morph.tween:geom-timed` the geom component takes the timed branch (apps/site/src/parts/morph.geom/index.tsx:65-82) and returns
before installing the `data-fw-morph` observer (index.tsx:83-89); the tween, not the pin, starts a flip there. The pin starts none, so both
pages are unflipped and equal. That arm needs the tween to run (task timed-m0-webkit covers the timed cell; the timed look is a follow-up).

## Lean
No decision rule is the cause: the regions and the 12-step threshold behave as written, and the difference is a missing write in
glue code (look.mjs is I/O, no decision logic). No Lean lemma is written. The fix task should take the fade value from the Lean-generated tween constants (`fade` in `morph.tween/logic`, FADE_END 0.55)
rather than restate it in the harness.

## Proposed fix task (new; not done here)
`geom-look-fade`: in packages/premise-tests/src/look.mjs, after each `pin`, write `--morph-fade` on `[data-fw="platform"]` of the base arm (the
driver's value, from generated constants), assert equal `scrollY` of both arms per reading, then re-run look/on on CI over >= 3 jobs;
expected: page share at m=1 <= nav-region level (0.1-3 %). Separately, make look/timed start a real tween (or drop it from the report).
Mid-morph picture differences stay with geom-image-model; WebKit timed m=0 stays with timed-m0-webkit.

## Limits
- Images are from a local WebKit debug run on this Mac (not Chromium, not CI); the CI numbers are from run 40553185213. No CI push was made; the fix task measures on CI.
- 641x700 Chromium nav 0.031 is not explained (not run locally).
- Mid-morph rows (m 0.25-0.75) differ on the whole page for the same reason plus picture scaling; not separated here.
