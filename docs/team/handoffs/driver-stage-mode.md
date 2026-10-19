# driver-stage-mode handoff

State: branch worktree-wf_1dd196ae-727-2 (merged worktree-wf_11ac09ad-a60-2 = counts-only first; it was not on main). Pushed as ci/driver-stage-mode.

Cause of the counts-only pilot failure (run 39189237058): the stage route pins `scrollY`, `innerWidth`, `innerHeight` on `window` to the
stage env (`apps/site/src/stage/fixedEnv.ts`), defaults 0/1280/800. The plan sent `?only=hero` without `stage=`, so the driver read
1280x800 and refused. INFERRED from fixedEnv.ts and the error text (scrollWidth 501 = real layout, innerWidth 1280 = the pin).

Lean: `lean/Fw/Site/StageMode.lean` (golden `packages/contracts/golden/parts/stage-mode.jsonl`, writer `lean/scripts/StageModeGolden.lean`,
check job "stage-mode golden check" in lean/scripts/check.sh). Decisions, each OR-branch its own theorem:
- (a) `planSearch`: no `only` key -> unchanged; `only` and no `stage` -> append `&stage=vw:<w>,vh:<h>` of the profile; typed `stage` -> refused.
- (b) `accepts`: hydrated and 0 errors, and (`only` search: mode client-render and the page's `__fwStage.env` = [0, w, h]; other search: mode hydrate).
  Stricter than "client-render only for a parsed only search": a hydrate page for an `only` search is refused too (a stage page never hydrates).
  The twin checks the page's own parse (`__fwStage`), not a JS port of the contract table.
- (c) DECISION: the stage `y` does NOT follow the scroll plan (query `y` = 0, pinned for the whole run). The driver scrolls the real document
  (hosts + fixed-height stubs) with the profile plan and reads the position from `document.scrollingElement.scrollTop` (pinned `scrollY` is
  constant). Round 1 REVERSED the viewport part of (c): the gate decides on the REAL frame size, not on `clientWidth/clientHeight` (see below).
  Meaning of a part-page count: browser work of the part's own band under real scrolling with scroll-driven part logic at rest. It is not a slice of
  the whole-page count and part counts do not sum to it. Premise `declared-rows-unverified` carried (golden premise row, run.txt). Follow-up
  to let y follow the plan: live pinned getter in fixedEnv.ts plus a stage grammar decision.
- TS stand-ins: none for the decisions (twin `packages/measure-chromium/src/stage-mode.mjs` checked by `test/stage-mode.test.mjs`). The string round trip
  (planned search parses to the profile env, for every part id and group) is `#guard roundTrips`, not a forall theorem.

Wiring: run.mjs uses `scrollRead`, `viewportGate`, `accepts` (mode check replaced); chromium-counts.yml plan step calls `node .../stage-mode.mjs plan`
(sparse checkout now profiles + src); land.ts reads of measure-chromium and Trigger.lean (lean.yml row) declare the new golden.
Not done (lead): no work-graph row for this task (graph writes list the files above).

## Round 1 fixes (commit 4d6bfe3f and this commit)
- Viewport gate (CONFIRMED from Chromium @f842f52: innerWidth = View()->Size(), grows with overflow; clientWidth = ICB, stays at the meta width):
  `Page.addScriptToEvaluateOnNewDocument` captures the native `innerWidth/innerHeight` getters before any page script (the stage pin) and
  the driver gates on them (`Fw.Site.StageMode.gateSize/viewportGate`, theorems `viewportGate_refuses_overflow`, `_accepts_real`, `_ignores_pinned_client`;
  golden row pinned 430x932, client 430x932, real 645x1398 is refused). meta.innerWidthPx/innerHeightPx = real frame; new meta fields
  pinnedInnerWidthPx/HeightPx, clientWidthPx/HeightPx, gateSize, scrollRead.
- Run 39194916578 (ci/driver-stage-mode @ 5c5ed307, only=hero, 1 run) is INVALID: meta.scrollWidthPx 501 > 430 at scale 1 (frame about 501x1086, not
  430x932), so it is not viewport-faithful; the old clientWidth gate let it through. Its counts and its last scrollTop 9888 (< maxScroll 10448) are not evidence.
- Hero overflow diagnosis: the original page clips at its root (`[data-fw=page-root]`, `overflow-x: clip`, apps/site/src/styles/reset.css, App.tsx:64);
  the stage route had no such root, so the hero's overflow (501 px) enlarged the layout viewport on the stage only: a STAGE ARTIFACT, fixed on the site
  side (PartStage.tsx wraps the main sections in `data-fw="page-root"`, columns outside it as in App.tsx; `MAIN_SECTIONS`/`COLUMNS_SECTIONS` in hosts.ts,
  a TS stand-in layout list, not Lean, no decision). Whether the whole page also overflows is excluded by that same clip (INFERRED from the CSS); the re-dispatch measures it.
- `roundTrips` docstring now states the split on parse(?only=t) (ok: same target, members, env E(p); err e: same err e).
- `accepts` refuses a part page with `missing` input writes (`refuses_missing_inputs`, golden rows with missing 0/1).
- Counts workflow: plan refuses runs < 2 (Lean `Fw.Store.Layout.reqProblems`: runs 2 to 10; a single artifact is extracted without its directory, so classify's glob
  finds nothing); `only` input described as usable.
- Accepted limits: scroll-driven part logic at rest on a stage page (decision c); part counts are not slices of the whole-page count; premise declared-rows-unverified;
  `parseEnv-stageParam-checked-not-proved` (the string round trip planned search -> parseEnv is `#guard roundTrips` over 3 profile viewports and 81 boundary sizes, not a forall theorem).

## Work-graph writes (lead)
No work-graph row exists for this task. The writes must add, besides the files above: apps/runner/src/land.ts, lean/Fw/Ci/Trigger.lean,
packages/contracts/golden/ci/triggers.jsonl (all touched here: land reads of measure-chromium declare the stage-mode golden and the counts workflow).

## Static pre-check, before dispatch: `?only=hero` through each driver gate (profile swipe-v1, 430x932)
Plan search: `?only=hero&stage=vw:430,vh:932`. Lean parse: ok, target hero, hosts [hero], mounted hero + 6 hero.* parts, stubs people=2936 pain=2796 commission=988 platform=1864 columns=932.
| gate | reads | expected for ?only=hero |
|---|---|---|
| navigate | static server `pageFor` | index.html shell (no prerender for `only=`) |
| quiet | readyState, fonts, requests, 30 frames | expected pass, not verified |
| viewportFaithful | REAL frame (captured native getters) vs 430x932 | pass only if the real frame is 430x932; the overflowing page (645x1398) or 501 px content without the clip is refused |
| `__fw` present | `window.__fw` | present |
| mode / hydrated / missing | `accepts` | client-render, hydrated, 0 errors, `__fwStage.env` [0,430,932], missing 0 |
| scroll plan | scrollTo per frame, position from scrollTop | doc height = hero + stubs; plan ends at maxScroll = docH - 932 |
Unverified until dispatch: hero width at 430 under the new page root, `quiet`, scrollTop reaching maxScroll.

Read first: lean/Fw/Site/StageMode.lean header, packages/measure-chromium/src/stage-mode.mjs, the diff of run.mjs.

## Verified locally (not a result)
Lean build of Fw.Site.StageMode, stage-mode golden --check up to date, measure-chromium tests 58/58, ci-paths 32/32, apps/runner 1034/1034 (tsc + vitest), apps/site 5148/5148 + tsc.

## Result after round 1: run 39199144167 (ci/driver-stage-mode @ 4af7b978, workflow_dispatch only=hero, rewrite, swipe-v1, runs 2)
- plan, fwcore, image, site, counts r1+r2, classify all passed. MEASURED (CI). Search `?only=hero&stage=vw:430,vh:932`, mode client-render, `__fwStage.env` [0,430,932], missing 0, unset [].
- Viewport-faithful YES: real frame 430x932 (pinned 430x932, client 430x932), scrollWidth 430, scale 1, docH 11380, maxScroll 10448, last scrollY 10448 = maxScroll (the 9888 gap of the invalid run is gone), 1085 frames in both runs. The hero overflow (501) was a stage artifact (no page root clip), fixed by the page-root wrapper.
- Counts YES for 2 runs; classes (artifact chromium-classes): see classes.txt in the run. Only 2 runs: below the >= 3 runs claim bar; determinism of the part page is not claimed. Premise declared-rows-unverified applies.
