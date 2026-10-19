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
  (hosts + fixed-height stubs) with the profile plan, reads the position from `document.scrollingElement.scrollTop` (pinned `scrollY` is
  constant) and gates the viewport on `clientWidth/clientHeight` (the pinned inner sizes equal the profile by construction: `pinned_size_vacuous`).
  Meaning of a part-page count: browser work of the part's own band under real scrolling with scroll-driven part logic at rest. It is not a slice of
  the whole-page count and part counts do not sum to it. Premise `declared-rows-unverified` carried (golden premise row, run.txt). Follow-up
  to let y follow the plan: live pinned getter in fixedEnv.ts plus a stage grammar decision.
- TS stand-ins: none for the decisions (twin `packages/measure-chromium/src/stage-mode.mjs` checked by `test/stage-mode.test.mjs`). The string round trip
  (planned search parses to the profile env, for every part id and group) is `#guard roundTrips`, not a forall theorem.

Wiring: run.mjs uses `scrollRead`, `viewportGate`, `accepts` (mode check replaced); chromium-counts.yml plan step calls `node .../stage-mode.mjs plan`
(sparse checkout now profiles + src); land.ts reads of measure-chromium and Trigger.lean (lean.yml row) declare the new golden.
Not done (lead): no work-graph row for this task (graph writes list the files above).

## Static pre-check, before dispatch: `?only=hero` through each driver gate (profile swipe-v1, 430x932)
Plan search: `?only=hero&stage=vw:430,vh:932`. Lean parse: ok, target hero, hosts [hero], mounted hero + 6 hero.* parts, writes/neighbours/unset empty,
stubs people=2936 pain=2796 commission=988 platform=1864 columns=932 (stubPx at vh 932).
| gate | reads | expected for ?only=hero |
|---|---|---|
| navigate | static server `pageFor` | index.html shell (no prerender for `only=`) |
| quiet | readyState complete, fonts loaded, 0 requests in flight, 30 frames | expected pass, not verified |
| viewportFaithful | clientWidth x clientHeight vs 430x932 (stage page) | pass if hero content is not wider than 430 px; else refused (same rule as the 645x1398 run) |
| `__fw` present | `window.__fw` | present (installFw runs before render) |
| mode / hydrated | `accepts` | mode client-render (stage never hydrates), hydrated true from PartStage effect, errors 0, `__fwStage.env` = [0,430,932]: accepted |
| scroll plan | scrollTo per frame, position from scrollTop | doc height = hero + 9516 px stubs; plan ends at maxScroll = docH - 932 |
Before the fix: viewport gate read the pinned 1280x800 -> refused (the pilot failure). Unverified until dispatch: hero width at 430, `quiet`, and anything the classes job does with a part page.

Read first: lean/Fw/Site/StageMode.lean header, packages/measure-chromium/src/stage-mode.mjs, the diff of run.mjs.

## Result: run 39194916578 (ci/driver-stage-mode @ 5c5ed307, only=hero, target rewrite, swipe-v1, 1 run)
- plan, fwcore, image, site, counts (rewrite, r1) passed; counts.json produced (artifact chromium-counts-rewrite-r1): search
  `?only=hero&stage=vw:430,vh:932`, mode client-render, hydrated, `__fwStage.env` [0,430,932], 1085 frames, docH 11380, observed viewport 430x932,
  scrollRead scrollTop, maxScroll 10448. MEASURED (CI).
- Observation, not diagnosed: the last recorded scrollTop is 9888, below maxScroll 10448 (the plan reaches 10448 by construction). Either the
  document is shorter after load than at the geometry read, or the clamp is lower; read frames[].scrollY vs docHeightPx over the run before
  reading zone sums of this page.
- classify FAILED, not from the driver: with `runs=1` actions/download-artifact (pattern `chromium-counts-*`, one match) extracts into `runs/` without
  the artifact subdirectory, so the glob `chromium-counts-rewrite-*/counts.json` matches nothing (ENOENT). Dispatch with runs >= 2 or fix the download step.
- Unverified: determinism across runs (1 run), classes of a part page against the whole-page frozen classes (premise declared-rows-unverified).
- Verified locally: Lean build, check.sh exit 0, measure-chromium tests 55/55, ci-paths 32/32, apps/runner 1029/1029 (tsc + vitest).
