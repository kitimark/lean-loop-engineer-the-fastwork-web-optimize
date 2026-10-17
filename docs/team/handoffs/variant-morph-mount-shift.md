# variant-morph-mount-shift (handoff)
**State:** `morph.mount:shift` in `apps/site/src/parts/morph.mount/` (logic.ts `mountNextWarm`, `warmStill`, `WARM_QUIET_MS`; index.tsx warm trigger; part.json variant `shift`; logic.test.ts). vitest 78 pass, tsc clean.
**Mount rule:** mirrors Lean `mountV`: `mountNext(m, near || warm, push)`; near/push triggers unchanged, so mounted whenever the original is (`mountV_of_mountO`).
**Warm tick (INFERRED):** a timer + idle callback fires once the morph is idle and no scroll/push for 150 ms; mounts once, starts no animation/timer/phase (PhaseFree). Flag off: no listener, no timer.
**Wiring:** apps/site/src/App.tsx passes `onMount` and inserts a hidden fixed placeholder box (`data-fw=morph-panel`, visibility hidden) once, so the insertion is real in both arms (admitted at land).
**INFERRED:** the 150 ms idle check stands for Lean's still moment (the `warm` Tick feeding `mountV`, whose monotonicity is `mountNext_mono`/`mountV_of_mountO`); Lean does not define 'still', the 150 ms is ours. Test vector: exactly 150 ms is still.
**Open:** the counting run must include the warm frame; peak drop not checkable by engine-check (no window).
**Golden:** variant name `rewrite+?fw=morph.mount:shift`, base `rewrite`, rows in packages/contracts/golden/engine/morph-mount.jsonl.
