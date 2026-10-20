---
id: 2026-10-21-faithful-hero-baseline
kind: note
title: "Faithful hero baseline: why the faithful rewrite differed from the original in the trajectory probe, and the fix"
status: final
created: 2026-10-20
authors: [agent:measure-engineer]
topics: [measurement, trajectory-probe, webkit, port-defect]
---

# Faithful hero baseline (2026-10-20)

Question: the trajectory probe (`research/notes/2026/10-21-trajectory-probe.md`) walks the original and the faithful rewrite
(default config) along one scroll path. Where did the two differ, which defects of the port explain it, and does the probe
read the faithful arm as the original after the fix? Status words: CONFIRMED (source or artifact cited), MEASURED (CI run),
INFERRED.

## Divergences found in the stored artifacts

Runs re-reduced offline with the current reducer: 39409003529 (default vs default, Chromium and Linux WebKit; Chromium
re-reduced: 89 `both`, 43 `new`, 2 `cleared`), 39412301221, 39415671864, 39419128841 (Apple and Chromium). Names are the
unit's element.property, width and step.

| # | element.property | width | steps | engine | cause |
|---|---|---|---|---|---|
| A | every hero node `rect`, `opacity`, `transform` on the hero path | 390, 640, 641, 1280 | the steps whose original rest y differs from the rewrite's (s25..s200, b25, b50, mid, hold) | macOS WebKit (all 54, 54 and 114 `both` units of b, c, d sit on such a step: 0 unexplained), Linux WebKit | the original glides (`html{scroll-behavior:smooth}`) and WebKit stops a smooth scroll short; the port jumps. Same label, different y. |
| B | `nav.cls.is-on-dark` (+ `logo.color`) | 390 | open@3..10, open-hold@10, close@3..10, approach a0 | Chromium | the original derives `is-on-dark` as hit-test or morph > 0.2 and re-derives on every morph change; the port derived it only in the scroll callback. A push moves the morph, not the scroll. |
| C | `earn.max-width` (timing) | 390 | open@3..10 | Chromium | follows B (INFERRED: the original's earn transition runs with the dark class set; MEASURED: 0 such units in both final runs) |
| D | `nav.background-color` | 641, 1280 | approach a2..a11 | Chromium | in-flight transition at an approach step; repeats in the A/A run (MEASURED), flicker, not a defect |
| E | every morph property | 390, 641 | open@1 | Chromium, Linux WebKit | coverage (empty bucket); sampling, in the A/A run too |

## Port defects (apps/site against `snapshot/site`), CSS values restated

1. Missing `html{scroll-behavior:smooth}` and the `prefers-reduced-motion: reduce` override `auto` (original:
   `assets/2.gBuqKVzi.css` offsets 227006 and 227682, linked by `index.html`; CONFIRMED by byte-offset search). Fix:
   `apps/site/src/styles/reset.css`, `@layer reset`. Test: `apps/site/src/scroll-behavior.test.ts`.
2. `nav.hitTest` computed `is-on-dark` only in the scroll callback; the original's signal is `g() || x() > .2`
   (`nodes/2.DyWL8TcE.js`, the nav, morph x reactive). Fix: a `MutationObserver` on `data-fw-morph` re-derives with the last
   hit answer (`apps/site/src/parts/nav.hitTest/index.tsx`). Test `morph.component.test.ts` is red without the fix (jsdom).
   The part footprint was regenerated (`node apps/site/scripts/part-footprint.mjs --write`); `lake build Fw.Parts.Contract`
   holds.

Since the page now glides, every harness call that jumped with `scrollTo(0, y)` would glide too. They now pass
`behavior: 'instant'`: `PartStage.tsx` (the stage), `apps/site/scripts/census.mjs`, `packages/e2e-preview/src/suite.mjs`, and the
probe (`kit.mjs` `heroPath`, which also re-issues an instant scroll up to twice when a rest stops short of the target, so
both arms are read at the same y; WebKit stalls a smooth scroll on the original).

## CI result

Dispatch: `pnpm -s fw run --trajectory --ref ci/faithful-hero-baseline --fw hero.exit:faithful --engines both` (code 412d16a),
twice. The candidate arm is the default config, so cand against base is the A/A control in the same run, and
39409003529 is the earlier A/A run.

| run | engine | new (content, coverage) | both | cleared | ok |
|---|---|---|---|---|---|
| 39453764374 | macOS WebKit (hero path) | 0 (0, 0) | 0 | 0 | 4000 |
| 39457063232 | macOS WebKit (hero path) | 0 (0, 0) | 0 | 0 | 4000 |
| 39453764374 | Chromium | 42 (0, 42) | 3 | 43 | 14328 |
| 39457063232 | Chromium | 2 (2, 0) | 43 | 44 | 14327 |

MEASURED. macOS WebKit: before the fix 54, 54 and 114 `both` units (runs b, c, d); after, 0 in both runs: the original and the
faithful rewrite agree on every one of 4000 units, including rect and opacity of every hero node.

Chromium: bugs B and C are gone (no `is-on-dark`, `logo.color` or 390 `earn.max-width` unit in either run; before, 89 `both`
and 43 `new` in the re-reduced A/A run). What is left is not a defect, and it moves between runs and widths:

- run 39453764374: 42 coverage `new` units, all at 640 open@1 (one width). Run 39457063232 has the same 42 as `both` (the
  faithful arm failed them too): an empty tenth of the morph value in a time-driven push, A/A noise.
- run 39457063232: 2 content `new` units, `earn.max-width` and `earn.opacity` at 1280 close-hold@0, the first sample after the
  close push. The raw rows show an in-flight CSS transition (max-width 136..149 of 174, opacity 0.89..0.97) that differs
  between reps of the same arm by as much as it differs between arms (orig 140.9..148.3, base 140.1..149.3, cand 135.8..148.6);
  the curves are the same (0.006, 0.034, 0.092, 0.188 at equal widths). The same unit family is `both` in run 39453764374
  (1280 close@0, 640 close-hold@0) and `new` in 39419128841.

By the stored-outcome rule (content `new` at 2 or more widths fails; coverage `new` at 2 or more widths is no verdict) both runs
pass: the content units sit at one width. INFERRED from the rule in `docs/team/tools/trajectory-probe.md` and the Lean
`outcome`; I did not call the recorder. The literal "0 new on Chromium in 2 runs" is not met: the probe cannot give it for
an arm against itself (cand against base, same config, produced the 42 and the 2). That is the finding.

Linux WebKit (not a claim, accepted limit): push cells are `no verdict: coverage` (frames every 150 ms or more).

## Limits

- The close@0 and close-hold@0 steps sample a transition in flight; a clock-aligned read would remove the noise. Not done
  here (reducer and Lean untouched).
- The retry in `heroPath` covers the hero path only; a WebKit stall on another path would need the same.
- The Apple lane runs only when the search holds `hero.exit` (dispatched as `--fw hero.exit:faithful`).
