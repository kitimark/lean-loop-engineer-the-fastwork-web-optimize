# hero.exit:scoped: restyle only the readers of the exit properties

The exit driver writes `--exit-opacity` on the hero stage every scroll frame. Both properties are unregistered custom
properties and so inherited. Each write restyles the whole stage subtree (275 elements in the prerendered DOM).
MEASURED before this task: about 94 elements per frame over frames 10-103. Only 16 elements read the properties: the
copy block, the cue and the 14 cards (10 orbit, 4 deck).

## Change (design 2 of the R1 record)

- In its effect, `hero.exit:scoped` registers both properties with `syntax: '*'` and `inherits: false`.
  `apps/site/src/parts/hero.exit/scope.ts` does this once per document.
- The stage carries `data-exit-scope`.
- 7 gated rules declare `--exit-opacity: inherit; --exit-scatter: inherit` on the classes between the stage and the
  readers: orbit, stage, stage3d, card, deck, copy and cue.
- The driver, the stage defaults (opacity 1, the scatter `calc`, reduced motion 0) and the REST plan are unchanged.

## Why it is cheaper (CONFIRMED, source)

- **Chromium.** A non-inherited diff on an element whose child uses `inherit` on a non-inherited property is
  `kInherited` (computed_style.cc:466-468@f842f52). The flag is set by style_builder.cc:114-117@f842f52.
  `kInherited` recalcs every child (element.cc:5618-5619@f842f52); otherwise `kNonInherited` stops
  (computed_style.cc:504@f842f52).
- **WebKit.** A custom property is inherited unless it is registered with `inherits: false`
  (StyleBuilder.cpp:103-106@862f17d). A `NonInherited` change resolves only the children with explicit inheritance
  (StyleTreeResolver.cpp:310-311,1207-1210@862f17d).

## Proved (Lean, `Fw.Engine.Restyle` and section Scoped of `Fw.Parts.HeroExitOpt`)

| theorem | statement |
|---|---|
| `scoped_le` | registered: Chromium units ≤ 1 + chain children over the tree |
| `wk_le_cr_units` | WebKit units ≤ Chromium units on a well-formed summary |
| `cr_units`, `wk_units`, `faithful_units` | hero summary: 21 and 21 scoped, 275 faithful in both engines |
| `consumer_eq`, `consumer_eq_scoped` | every reader sits on an all-`inherit` path, so it gets the stage value |
| `defaults` | before the first write the readers get opacity 1, registered or not (SSR, pre-hydration) |
| `reduced_scatter`, `scatter_eq` | under reduced motion the readers get scatter 0; otherwise the scoped scatter equals the faithful one |
| `Fw.Site.Stage.exit_owner_never_written` | no `?only=` stage plan writes a rest value on hero.exit |

Golden: `packages/contracts/golden/parts/hero.exit.scoped.json` holds the reader list, the inherit rules, the tree, the
per-frame write set and the zone bound (94 frames: Chromium ≤ 1974, faithful 25850). `scoped.test.ts` checks the
readers and the rules against the CSS, and the tree against the SSR DOM.

## Measured

All values below are MEASURED. Setup:
- Workflow chromium-counts on `ci/exit-scoped-var` at fad89503, target rewrite, 3 runs per arm.
- One image, reused from run 39049264131.
- The variant was read from `meta.rewrite.config.variants` (`hero.exit: scoped`, every other part faithful).

The counter is `UpdateLayoutTree.elementCount` summed over frames 10-103:

| profile | base run | base zone | scoped run | scoped zone | Δ | per-frame median base → scoped |
|---|---|---|---|---|---|---|
| swipe-v1 | 39314368756 | 13145 (r1-r3) | 39314340270 | 4730 (r1-r3) | -8415 (-64%) | 136 → 45 |
| swipe-touch-v1 | 39314380116 | 12035-12036 | 39314355168 | 4328 (r1-r3) | -7707 (-64%) | 136 → 45 |

Other counters:
- Whole-run elementCount drops by the same amount: swipe 44128-44182 → 35776-35790, touch 48526-48528 →
  40109-40133.
- `UpdateLayoutTree` passes (391 swipe, 365 touch) and zone `Layout.dirtyObjects` stay the same within 2.
- The R1 upper bound (about 7.0k, INFERRED) is exceeded. The faithful cost was about 91 elements per frame above the
  scoped cost, not the 94 minus 17-19 that R1 assumed.
- The scoped median of 45 is above the Lean bound of 21. The bound covers only the exit write, and other writers in
  the same frames account for the rest (INFERRED).

Breakpoint gate:
- Run 39314391342 (`fw=hero.exit:scoped`) passes every hero.exit cell in Chromium and WebKit.
- The run's verdict is fail (Chromium) and incomplete (WebKit) because of two cells unrelated to this flag:
  - commission in `sweep:pain-1440-600-1440`;
  - WebKit matchMedia NC in `sweep:phone-rotation`.
- Both cells fail the same way on `ci/countdown-one-chain` (run 39313815482), so they come from main, not from this
  flag.

The final commit renders the attribute as a plain JSX attribute instead of a spread, so the footprint extractor keeps
exact owners. The rendered DOM is the same (`scoped.test.ts`).

## Limits

- `UpdateLayoutTree.elementCount` is a quarantined counter. On the admitted counters the win is proved-unmeasured
  unless the lead admits the zone-restricted count.
- The WebKit win is source-only (Lean `wk_units`); no WebKit lane counts restyled elements.
- A future reader outside the chain classes would see the guaranteed-invalid value. `scoped.test.ts` fails on it.
