# variant-hidden-pause (handoff)

State: TS variants `hidden-pause` for morph.columns, morph.countdown and a new part engine.scene (`apps/site/src/parts/engine.scene/`). Flag: `?fw=morph.columns:hidden-pause`, `morph.countdown:hidden-pause`, `engine.scene:hidden-pause`. Faithful path untouched.
- Shared logic in `engine.scene/logic.ts` (constants, `createSceneClock` = Lean origClock, `createWriteGate`), `observe.ts` (one IntersectionObserver per part; thresholds `[HIDDEN_FRACTION]`, or `[0]` for the rect form).
- `HIDDEN_FRACTION` (2/25) and `SCENE_ACTIVE_ABOVE` (1/1000) are TS constants pinned by `logic.test.ts`, which parses `lean/Fw/Parts/HiddenPause.lean`. Lean emits no JSON for them yet (open item: generate it).
- morph.columns: `data-fw-hidden` attribute -> `animation-play-state: paused !important` (scene.module.css); on return `getAnimations({subtree})` are seeked to origClock (time the scene was active). Reduced motion / <=640 unchanged (no animations exist).
- morph.countdown: driver untouched; face `transform` writes are shadowed on each face's `style` and replayed (latest per face) in the IO callback on unhide.
- engine.scene: `<EngineScene variant/>` pauses `[data-fw-scene]` sections with no positive-area overlap; resume seeks to the free-running clock. Not mounted anywhere yet: App.tsx/registry/Census wiring is the lead's (registry imports `engine.scene/part.json`).

Open premises: the IO fraction of the stage stands in for the panel's morph <= 0.08 (morph.panel will own the real hidden signal); clock t0 is taken at effect time (<= 1 frame after the animation starts); the original scheduler's 100% margin pause is not ported, so engine.scene resumes at the free-running clock; breakpoint-gate has no flag input and its scope lists no morph/engine.scene parts.

Read first: `lean/Fw/Parts/HiddenPause.lean`, `engine.scene/logic.test.ts`.
