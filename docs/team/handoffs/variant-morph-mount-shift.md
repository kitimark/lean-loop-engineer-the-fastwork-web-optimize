# variant-morph-mount-shift (handoff)
**State:** `morph.mount:shift` in `apps/site/src/parts/morph.mount/` (logic.ts `mountNextWarm`, `warmStill`, `WARM_QUIET_MS`; index.tsx warm trigger; part.json variant `shift`; logic.test.ts). vitest 78 pass, tsc clean.
**Mount rule:** mirrors Lean `mountV`: `mountNext(m, near || warm, push)`; near/push triggers unchanged, so mounted whenever the original is (`mountV_of_mountO`).
**Warm tick (INFERRED):** a timer + idle callback fires once the morph is idle and no scroll/push for 150 ms; mounts once, starts no animation/timer/phase (PhaseFree). Flag off: no listener, no timer.
**Open:** App passes no `onMount` yet (no panel ported), so warm mount is observable only through the owner callback; the counting run must include the warm frame; peak drop not checkable by engine-check (no window).
**Golden:** variant name `rewrite+?fw=morph.mount:shift`, base `rewrite`, rows in packages/contracts/golden/engine/morph-mount.jsonl.
