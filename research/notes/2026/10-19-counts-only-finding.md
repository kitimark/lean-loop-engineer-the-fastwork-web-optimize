# counts-only: the counts harness cannot measure a part page yet (finding)

Task counts-only, branch `worktree-wf_11ac09ad-a60-2`, CI branch `ci/counts-only`. Status words: MEASURED (CI run cited), CONFIRMED (file:line cited).

## Finding

The premise "the counts harness can measure a part page as it is" is refuted. One dispatch (`only=hero`, target rewrite, swipe-v1, run 39189237058) passed
plan, site, fwcore and image and then failed in all three counts jobs at `packages/measure-chromium/src/run.mjs:151`: `viewport not faithful: the page
reports 1280x800 ... the profile 430x932` (MEASURED). A static read of the driver against the stage code shows two more gates behind that one (CONFIRMED).

## Mechanism: three independent causes

1. Viewport. `pinEnv` (apps/site/src/stage/fixedEnv.ts:24-29) redefines `scrollY`, `innerWidth` and `innerHeight` on `window` to the stage env. Without
   `&stage=` the env is `DEFAULT_ENV` (apps/site/src/registry/only.ts:85), the Lean `Env.default` = (y 0, vw 1280, vh 800) (lean/Fw/Site/Stage.lean:30-31).
   `entry-client.tsx:36` calls it before the first render, so the driver's `innerWidth`/`innerHeight` read (run.mjs:148) sees 1280x800 and
   `viewportFaithful` (run.mjs:149-151) refuses. The real emulated viewport was 430x932; only the pinned getters differ.
2. Mode. For `?only=` the entry installs mode `client-render` (`same` is false when `only.kind !== 'none'`, apps/site/src/entry-client.tsx:26-33), by design: the
   static shell is the home page. The driver requires `mode === 'hydrate'` (run.mjs:161-163). It would refuse the page next even with cause 1 fixed.
3. Scroll. The pinned `scrollY` is constant (y 0 unless `&stage=y:N`). The swipe plan (run.mjs:167 on) drives `scrollTo`; the page reads the pinned
   getter, so the part never sees a scroll and the swipe would measure an idle part (INFERRED from fixedEnv.ts:1-9; not run).

## Why it happened

The workflow input, the Lean `goldenRuns` row and the site stage route were each correct on their own. The driver's three gates (viewport, mode, scroll plan)
were never read against what a stage page serves; the first dispatch was the first check.

## Resolution

- `chromium-counts.yml` plan job: a non-empty `only` input fails with "part pages are not measurable by the driver yet: needs driver stage mode (task driver-stage-mode)".
- Kept: Lean `goldenRuns` row `?only=hero` and `answers_only_hero` (they stay true: they state which base series a run answers, not that the harness can run it);
  the regenerated `keys.jsonl`.
- Next step is task `driver-stage-mode` (a driver change: pass `&stage=y:..,vw:<profile>,vh:<profile>` from the profile, accept mode `client-render` for a stage
  page only, move the stage env y per frame instead of `scrollTo`), not an apps/site patch.

## General lesson

Before a CI dispatch of a new page kind through an existing driver, list every gate the driver applies to the loaded page (viewport, `__fw` mode and hydration,
scroll plan, quiet check) and check each against what that page serves by reading the code. One static pass costs minutes; the dispatch costs a run per gate, and
a driver reports only the first refusal, so three causes took one dispatch to show one.
