# People section layout shift: port against original

Task `people-layout-shift`. User, 2026-10-19: "people section layout quite a bit shift. it's difference from original
website." Port preview main 7e5cff2f. Probe: `packages/visual-diff/src/people-layout.mjs` (+ `people-layout-analyze.mjs`),
CI job `people-layout` of `visual-diff.yml` (`-f peoplelayout=true`). All numbers below are MEASURED on CI unless marked.

## What the user saw (short answer)

- The section itself does not shift: top, height and document height are equal (0 px) in both engines at 1920, 1440,
  1280, 861 and 401 wide, in every frame and hold (MEASURED, 4 runs x 2 reps x 2 engines). Layout-shift scores are equal
  between the arms (0.01 / 0.04 / 0.11 / 0.34 / 0.01 at the five widths).
- One deterministic geometry difference existed, at widths above 1030 px (checked at 1920, 1440, 1280): in the profile
  card, the cover picture and the tag row started 12 CSS px (14.64 px on screen, the card is scaled by 1.22) lower in the
  original than in the port. Cause: the original's cover is `<picture><source><img>` with `picture { display: contents }`,
  and the empty `<source>` is a flex item of the column, so the 12 px gap sits above the cover. The port draws the cover
  as one span and had no such item. Fixed with `.coverBlock::before` (empty item), commit 2b37d60a. After the fix no
  non-motion box differs by more than 0.5 px at load in any of 6 CI jobs (3 runs x 2 engines).
- What stays different is motion, not layout, and part of it is a measured bias. The port's 'o' opens 1 to 2 scroll
  samples later than the original's in Chromium (port later in 23 of 32 cold-pass pairs, earlier in 2, at 1920, 1440,
  1280 and 861; the original against itself differs in 11 of 16 with no direction; MEASURED by the review on runs
  39279857839, 39288152363, 39288315945, 39288339116). In WebKit it closes about one sample later in most repetitions.
  In the frame table the title, its words, the 'o' and its stage differ in 39 of 197 frames, by up to 177.66 px; at
  1920 the port's title collapse starts one sample later (scrollY 1248: original +33.72, port +9.03). Cause INFERRED:
  the port commits React state after the IntersectionObserver callback (opener timeline, people.o/index.tsx:65); the
  original toggles a class. This is the likeliest part of "quite a bit shift" that the fix does not remove; it is a
  follow-up. The scroll-driven card shrink/lerp also differs between repetitions; no original-against-original table
  is measured for the motion keys, so its arm difference is not shown to be noise.

## Runs

| run | commit | what | state |
| --- | --- | --- | --- |
| 39279857839 | 2d0ac41b | probe before the fix | success; rows below marked "before" |
| 39288152363 | 2b37d60a | probe after the fix | success |
| 39288315945 | 2b37d60a | probe after the fix | success |
| 39288339116 | 2b37d60a | probe after the fix | success |

Each run: Chromium Headless Shell 156.0.8078.4 and WebKit 27.2 (playwright-core 1.64.1), 5 widths, 2 repetitions, orig
arm = `snapshot/site`, port arm = the site build. A later comment-only commit changes no CSS output.

## Step 1: rules that set box size or position (original against port)

Original CSS is one line, `snapshot/site/_app/immutable/assets/2.gBuqKVzi.css`, cited as character offset. JS:
`nodes/2.DyWL8TcE.js`. Port: `apps/site/src/parts/...`.

| rule | original | port | equal |
| --- | --- | --- | --- |
| section height = sticky.offsetHeight + 1.45 inner + (n-1) 0.34 inner heights | js@293394 (`W`) | people.deck/driver.ts:86-91 (+ logic) | yes (section h equal) |
| sticky: `position:sticky; top:48px; --profile-scale:1.22; width:100%` (motion, >= 861) | css@56074 | people.deck/deck.module.css:788-792 | yes |
| narrow sticky: `position:relative; top:auto; --profile-scale:1` | css@58433 | deck.module.css:1009 | yes |
| shell scale `transform:scale(var(--profile-scale,1)); origin 100% 0` | css@52193 | deck.module.css:113 | yes |
| future card shrink `scale(var(--future-shrink-scale)); origin 50% 100%` | css@40272 | people.card/card.module.css | yes (motion, per frame) |
| `.future` width | none | card.module.css:16 `max(100%, 320px)` | port-only; no box difference measured |
| `picture { display: contents }` in the profile | css@51938 | none (spans) | the cause below |
| cover-block: flex column, `gap:12px` | css@55086 | deck.module.css:281-285 | yes, plus the empty item at :291 |
| cover aspect ratio 358.5/201.75 (361/169 narrow) | css@55086 / @56764 | deck.module.css:295 / :833 | yes |
| cover-meta: flex, `gap:12px`, space-between | css@55310 | deck.module.css:304 | yes |
| cover-block narrow `order:-1; gap:0` (<= 1030 px) | css@56764 | deck.module.css:828-831 | yes |
| deck bleed, shell width | css@51884, @59574 | deck.module.css:100, 1069 | yes (probe: 0 px) |
| 'o' grid-template-columns 0.92s cubic-bezier(.22,1,.36,1) | css (people-o rules) | people.o/o.module.css:15 | yes |

Method for the rest: a declaration-level comparison of every size/position property per class (original 187 rules,
port 384, 101 size declarations identical, 43 declaration pairs differ after normalising spaces and leading zeros). The
43 are: font-family declarations the port sets elsewhere (about 14), and same-named classes of different components
(`.avatar`, `.name`, `.meta`, `.copy`) that the name-level comparison conflates (INFERRED: the probe shows 0 px for each
of those boxes). The probe, not the rule list, decides: it measured 176 nodes per width (287 at 401) in both arms.

## Step 3: differences by cause (per width and engine)

Before the fix (run 39279857839, load dump, same in both engines; orig minus port):

| width | node | difference | first at | cause |
| --- | --- | --- | --- | --- |
| 1920 | cover-block | height +14.64 | load | structure: empty `<source>` flex item |
| 1920 | cover-meta | offset-y +14.64 | load | same (parent has an unmatched child) |
| 1920 | meta | height +14.64 | load | same (contains the cover-block) |
| 1920 | body | height -14.64 | load | same (fills the rest of the shell) |
| 1440 | cover-block, cover-meta, meta, body | same four rows, +14.64 / +14.64 / +14.64 / -14.64 | load | same |
| 1280 | cover-meta | offset-y +14.64 | load | same (cover-block height equal) |
| 861, 401 | none | gap is 0 in the narrow layout | | |

After the fix (runs 39288152363, 39288315945, 39288339116, both engines): zero non-transform origins in every load dump
of every width and repetition. All dumps of Chromium: zero. Remaining rows:

| group | where | size | cause | status |
| --- | --- | --- | --- | --- |
| record, label, hole | all widths, both engines, hold dumps | up to 3.5 px / 27 px (hole) | vinyl rotation phase at the dump instant | MEASURED, animation, not layout |
| scroll-driven transforms (card, header, shell, panel ...) | holds | tens of px | per-frame lerp (rate 0.22, snap 0.0008) against slow CI frames | not a layout rule; no orig-vs-orig baseline for motion keys |
| 'o' expand onset | Chromium cold pass, 1920/1440/1280/861 | 1 to 2 samples (at 1280 often 800 against 736) | port later in 23/32 pairs, earlier in 2/32; orig rep-to-rep 11/16, no direction | MEASURED bias (review re-analysis of the 4 runs); cause INFERRED (React commit after the IntersectionObserver callback, people.o/index.tsx:65); follow-up |
| image boxes (cover, avatar, post, face) | all widths, both engines, load | 14.64 px dy before the fix, 0 after | the analyzer pairs children by tag, so `picture>img` and the port's span are unmatched; compared by path by hand in the 6 after-fix jobs (rep 0) | MEASURED; analyzer mapping is a follow-up |
| tab-label width | WebKit holds only | +-0.6 to +-60 px, sign changes | tab-switch transition caught at a different sample | timing; unknown, varies run to run |
| title offset-x, stage width | WebKit holds (2 to 5 per run) | 14.6 to 118 px | 'o' expand/collapse caught mid-transition | timing; same cause as below |
| 'o' collapse | WebKit cold pass, first sample after trigger | port 608..662 against orig 512..589 of 728 to 505 (8 of 8 in run 39288152363, 6 of 8 in 39288339116) | port starts the 0.92 s grid transition about a sample later | INFERRED (React commit against Svelte class toggle) |

Layout shifts over time (Chromium `layout-shift`, entries per run 94 to 147, sum rounded to 2 decimals):

| width | orig sum | port sum | note |
| --- | --- | --- | --- |
| 1920 | 0.01 | 0.01 | |
| 1440 | 0.04 | 0.04 | largest source: `section:0>div...` at load, 0.02 (above the people section) |
| 1280 | 0.11 | 0.11 | same source, 0.09 |
| 861 | 0.34 | 0.34 | same source, 0.31 |
| 401 | 0.01 | 0.01 | |

Equal in all 4 Chromium runs. The large source is outside the people section; it is the same in both arms. WebKit
per-frame shifts with the transform unchanged: 14 to 197 per case in both arms, comparable counts, no one-arm-only
shift found (the timing group above).

## Step 4: fix and proof

- Fix: `apps/site/src/parts/people.deck/deck.module.css` `.coverBlock::before { content: '' }` (restates the original's
  empty flex item; the value is the original's gap 12px, no code copied). Decision logic: none (a static box rule).
- Regenerated, never hand-edited: `packages/contracts/golden/parts/footprint.gen.json` and
  `lean/Fw/Parts/FootprintData.lean` (`node scripts/part-footprint.mjs --write`, the footprint test demands it).
- CI trigger rows for the new job's caches: `lean/Fw/Ci/Trigger.lean` `cacheWriters` + regenerated
  `packages/contracts/golden/ci/triggers.jsonl` (`lake test -- --write-ci-trigger-golden`).
- Shown gone on CI: 3 runs x 2 engines x 5 widths x 2 repetitions, section above (cover-block, cover-meta, meta and body
  rows over the 10 cases of a run: 4 / 6 / 4 / 4 before in each engine, 0 after).

## TS stand-ins

- The probe and analyzer (`people-layout.mjs`, `people-layout-analyze.mjs`) are measurement glue; `causeOf` and
  `compareDumps` carry classification logic that has no Lean golden. Tests: `packages/visual-diff/test/people-layout-analyze.test.mjs`.

## Not found / follow-ups

- An earlier note of a 1 to 12 px taller people section was not reproduced (0 px at all widths); cause unknown.
- 'o' opens 1 to 2 samples later in Chromium (MEASURED bias), closes about one later in WebKit; a probe that counts rAF frames from the click
  would settle it. A fix would belong in `people.o/driver.ts`, with the trigger timing proved in Lean first.
- Stale Google Sans comment in `people.card/card.module.css`; port-only `.future { width: max(100%, 320px) }`.
- Widths other than the five are untested; the cover gap rule changes at 1030 px and 1200 px (coarse pointer).
- Pixel equality stays the visual gate's job; overlay content and other sections are out of scope.
