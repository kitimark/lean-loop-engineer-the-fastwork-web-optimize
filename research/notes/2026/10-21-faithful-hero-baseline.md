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
| A | every hero node `rect`, `opacity`, `transform` on the hero path | 390, 640, 641, 1280 | the steps whose original rest y differs from the rewrite's (s25..s200, b25, b50, mid, hold) | macOS WebKit (all 54, 54 and 114 `both` units of b, c, d sit on such a step: 0 unexplained), Linux WebKit | the original glides (`html{scroll-behavior:smooth}`) and WebKit stops a smooth scroll short; the port jumps. Same label, different y. Port defect 1 below; on the probe it is cleared by the retry in `kit.mjs`, not shown cleared by the port fix (see "Two effects"). |
| B | `nav.cls.is-on-dark` (+ `logo.color`) | 390 | open@3..10, open-hold@10, close@3..10, approach a0 | Chromium | the original derives `is-on-dark` as hit-test or morph > 0.2 and re-derives on every morph change; the port derived it only in the scroll callback. A push moves the morph, not the scroll. |
| C | `earn.max-width` (timing) | 390 | open@3..10 | Chromium | **follow-up, no cause cited.** The units are `both` in the A/A run 39409003529 re-reduced (open@3..10: seven `both`, one `cleared`), and absent from both final runs. A search of `2.gBuqKVzi.css` finds four `is-on-dark` rules (language switch, nav background twice, logo colour); none selects the earn button or its transition, so the earlier "follows B" is withdrawn. |
| D | `nav.background-color` | 641, 1280 | approach a2..a11 | Chromium | in-flight transition at an approach step; repeats in the A/A run (MEASURED), flicker, not a defect (A/A run re-reduced: 6 failing units at 641 and 4 at 1280, in both the candidate and the faithful arm) |
| E | every morph property | 390, 641 | open@1 | Chromium, Linux WebKit | coverage (empty bucket); sampling, in the A/A run too (42 coverage units at 641 in both arms and at 390 in the candidate) |
| F | `earn.opacity`, `earn.max-width` | 640, 641, 1280 | close@0, close-hold@0 | Chromium | in-flight sampling of one CSS transition, same in both arms and in the A/A run; not a port defect (see "Row F"). |

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

## Row F: earn max-width and opacity at close@0 and close-hold@0

Values restated by value, original `assets/2.gBuqKVzi.css` (button `.start-selling-top-nav-btn.is-earn`, offsets 221119,
221979, 224421) against the port `apps/site/src/parts/nav/nav.module.css:167-197` (`.btn.earn`):

| | original | port |
|---|---|---|
| `--earn-out` | `clamp(0, morph / .2, 1)` | same |
| `--earn-layout` | `nav-expand * (1 - earn-out)` | same |
| `max-width` | `earn-layout * 11rem`; `earn-layout * 9.5rem` at `width<=640px` | same, same media |
| `opacity` | `(1 - earn-out) * nav-expand` | same |
| `transition` | `max-width .68s cubic-bezier(.33,0,.2,1), opacity .32s (same curve) .12s delay, padding-inline .68s (same curve)` | same |
| `transition` on `.is-hero-pill` | `opacity .2s`, no delay | same |
| reduced motion | `filter:none; transition:none` | same |

CONFIRMED: no value differs, so there is no port defect in the transition itself. (How the target is retargeted while the
morph passes 0.2 is the subject of the task earn-transition-retarget; nothing here changes it.)

What the units are: after a close push the morph reaches 0 and the button grows from 0 to 11rem (176 px at 1280) over
0.68 s; `close@0` and `close-hold@0` read the first samples of that growth. Raw rows of run 39457063232, 1280, the first three
reads of the hold per rep (ms since the first read, `max-width`): orig 144.2 / 158.0 / 166.9, 148.3 / 160.7 / 168.6,
140.9 / 155.8 / 165.4 (reps 1 to 3); faithful 149.3 / 163.5 / 170.2, 148.2 / 160.6 / 168.6, 140.1 / 158.2 / 167.0;
candidate 148.6 / 160.9 / 170.1, 144.6 / 160.8 / 168.7, 135.8 / 152.4 / 165.3. Every arm reaches 176.0 after 300 to
370 ms; only the phase of the first read differs from rep to rep, and by as much inside one arm as between arms.

First read of the hold (`max-width`, min to max over reps), Chromium:

| run | 1280 orig | 1280 faithful | 1280 candidate |
|---|---|---|---|
| 39453764374 | 144.5 to 148.4 | 144.2 to 148.7 | 144.0 to 151.7 |
| 39457063232 | 140.9 to 148.3 | 140.1 to 149.3 | 135.8 to 148.6 |
| 39409003529 (A/A) | 141.7 to 146.9 | 140.2 to 149.6 | 136.0 to 144.8 |

A/A numbers (candidate and faithful are the same config, so the pair is the control; `fail:apart` units of
`earn.opacity` and `earn.max-width` at close@0 and close-hold@0, all widths):

| run | candidate | faithful | where |
|---|---|---|---|
| 39409003529 (re-reduced; stored file: 4 and 3) | 4 | 4 | 1280 only (faithful also 641 close@0) |
| 39453764374 | 3 | 4 | 640 close-hold@0, 1280 close@0 |
| 39457063232 | 3 | 3 | 641 close@0, 1280 close@0 or close-hold@0 |

Verdict: in-flight sampling of the same transition in both arms (MEASURED: the family fails for the candidate and the
faithful arm in all three runs, at a different width and step each time; the raw curves coincide). It is not a port defect.
Outside this family no `earn` unit is `fail:apart` in the two final runs.

## CI result

Dispatch: `pnpm -s fw run --trajectory --ref ci/faithful-hero-baseline --fw hero.exit:faithful --engines both` (code 412d16a),
twice; the candidate arm is the default config, so cand against base is the A/A control in the same run, and 39409003529
is the earlier A/A run. Both runs completed with conclusion `success` (39457063232 after round 1 was written).

**Lean outcome (`Fw.Gate.Trajectory.outcome`, `lean/Fw/Gate/Trajectory.lean`).** I ran the units files of both runs through
`Fw.Preset.Gen.storedOf` and `outcome`, the calls `record` makes, without its write to the stored admission file (a baseline
check is not a flag admission; script in the session scratchpad, dummy sha). Verdict lines:

```
outcome: run 39453764374 chromium hero: pass
outcome: run 39453764374 chromium morph: pass
outcome: run 39453764374 mac-webkit hero: pass
outcome: run 39453764374 linux-webkit hero: pass
outcome: run 39453764374 linux-webkit morph: no verdict: coverage
outcome: run 39457063232 chromium hero: pass
outcome: run 39457063232 chromium morph: pass
outcome: run 39457063232 mac-webkit hero: pass
outcome: run 39457063232 linux-webkit hero: pass
outcome: run 39457063232 linux-webkit morph: no verdict: coverage
```

Chromium and macOS WebKit hero pass in 2 completed runs. Raw `new` units that `outcome` does not count remain (below); the
Lean rule fails a node property only on content `new` units at 2 or more widths, and no run has that.

| run | engine | new (content, coverage) | both | cleared | ok |
|---|---|---|---|---|---|
| 39453764374 | macOS WebKit (hero path) | 0 (0, 0) | 0 | 0 | 4000 |
| 39457063232 | macOS WebKit (hero path) | 0 (0, 0) | 0 | 0 | 4000 |
| 39453764374 | Chromium | 42 (0, 42) | 3 | 43 | 14328 |
| 39457063232 | Chromium | 2 (2, 0) | 43 | 44 | 14327 |

MEASURED. Chromium: B is gone (no `is-on-dark` or `logo.color` unit in either run; before, 89 `both` and 43 `new` in the
re-reduced A/A run). What is left moves between runs and widths:

- run 39453764374: 42 coverage `new` units, all `earn` at 640 open@1 (one width); run 39457063232 has the same 42 as `both`
  (the faithful arm failed them too): an empty tenth of the morph value in a time-driven push, row E.
- run 39457063232: 2 content `new` units, `earn.max-width` and `earn.opacity` at 1280 close-hold@0: row F.

Linux WebKit (accepted limit): push cells are `no verdict: coverage` (frames every 150 ms or more).

## Two effects behind the macOS WebKit result

Round 1 changed the port (`html{scroll-behavior:smooth}`, reset.css) and the instrument (`kit.mjs` `heroPath` re-issues an
instant scroll up to twice when a rest stops short of the target) in one commit. Run 3 of 4, 39461484608, branch
`ci/faithful-hero-baseline-nosmooth` (the same code with only the reset.css block removed; the built CSS has no
`scroll-behavior:smooth`, checked in the `site-dist` artifact; the run's `trajectory-apple` artifact, hero path):

| run | port `scroll-behavior` | kit retry | macOS WebKit hero: new / both / ok |
|---|---|---|---|
| 39412301221, 39415671864, 39419128841 | no | no | 54, 54, 114 `both` (A) |
| 39453764374, 39457063232 | yes | yes | 0 / 0 / 4000 |
| 39461484608 | no | yes | 0 / 0 / 4000 |

MEASURED. What each shows: the instrument change alone clears A in the probe (the retry puts both arms at the target of
the step; run 3 has the faithful arm jumping and the original gliding, and they agree). So the probe does not show that the
reset.css fix cleared A, and the retry hides the original's WebKit stall from every later comparison. The reset.css fix is a
fidelity fix shown by `apps/site/src/scroll-behavior.test.ts` and the CSS restated above, not by the probe. The reverse
variant (port fix, no retry) was not run (run 4 of 4 is unused); whether the port fix alone clears A stays open. Run 3 completed with conclusion
`success` (`fw ci wait`: pass).

## Limits

- The close@0 and close-hold@0 steps sample a transition in flight; a clock-aligned read would remove the noise. Not done
  here (reducer and Lean untouched).
- The retry in `heroPath` covers the hero path only; a WebKit stall on another path would need the same.
- The Apple lane runs only when the search holds `hero.exit` (dispatched as `--fw hero.exit:faithful`).
