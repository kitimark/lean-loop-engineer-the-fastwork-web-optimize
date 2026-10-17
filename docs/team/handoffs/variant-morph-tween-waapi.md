# variant-morph-tween-waapi (part-builder)

State: branch `worktree-agent-a2a7b69d4bc70996d`; CI branch `ci/variant-morph-tween-waapi`. Site vitest 1781 green, tsc clean.
Files (apps/site/src/parts/morph.tween/): `waapi.logic.ts` (pure plan: EASING, TIMING, keyframes, offsets, settledProps),
`waapi.driver.ts` (driver, no clock), `index.tsx` (`variant === 'waapi'` -> waapi driver; `CSS.registerProperty` of --morph,
--fw-morph-dark, --fw-morph-expanded, all `<number>`, inherits false), `part.json` (variant `waapi`, optimized T0),
tests `waapi.golden.test.ts`, `waapi.driver.test.ts`, helper `waapi.fake.testutil.ts`. `driver.ts`/`logic.ts` untouched.

Design: one animation per element (nav: `--morph` + two flag props; platform: `--morph` + `pointerEvents`), both with
`startTime = document.timeline.currentTime` read at the push (R5). Effect easing `cubic-bezier(1/3,1,2/3,1)`, `fill:both`.
Flags = discrete keyframe quadruple `[0:a, c:a, c:b, 1:b]`, c = clamp01((theta-f)/(t-f)) (Lean flagV). Platform fade is
inline `--morph-fade: calc(1 - min(1, var(--morph) / 0.55))` (written once). `from` of a retarget = animation's
computed progress read at the push (not the last frame: P-from differs by under one frame). No rAF, no per-frame write.

Outside my folder (lead admits at land): the gate had no variant flag. Added `FW_SEARCH` (serve.mjs `rewriteFor`, run.mjs) and
workflow input `fw` in `.github/workflows/breakpoint-gate.yml` (same convention as measure-webkit: configs.json bySearch).
Run: `gh workflow run breakpoint-gate --ref ci/<x> -f fw=morph.tween:waapi`.

Golden: `morph-tween-waapi.jsonl` has only engine-prediction rows (no keyframes/offsets). The test checks those 11 rows
against the driver (script `<o` = zero clock subscriptions; `=o` rows = animated props are exactly the original's) and checks
easing and flag flips against the Lean `ease` rows of `morph.tween.jsonl`. OPEN: ask lean-prover for Lean rows of
`kfOffset`/`flagV` (theta,f,t -> offset, flags) in the golden file so offsets are Lean numbers, not derived.

Open premises: R5 lane offset c equal for both reads (CI lane, not the gate); P-from (above); R8 fp (RG8 test covers the
bezier); consumers: `nav.hitTest` reads `data-fw-morph` (published only at start = from, and at finish = to, so its
`morph > 0.2` is stale mid-tween); `--fw-morph-dark/-expanded` have no CSS consumer yet. Local check: WebKit (playwright) showed
values following ease, dark flip at 0.2, pointer none at 0.5225; Chromium not run locally (no browser installed).
