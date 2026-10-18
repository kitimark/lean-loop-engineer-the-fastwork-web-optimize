# proved-flags-ts (part-builder) handoff

State: branch worktree-wf_9847872a-d87-1, one commit. `pnpm test` (5048) and `pnpm typecheck` green in apps/site.

Built, wired, registered in part.json and added to presets/v2-proved.json (not the default; lead decides):
- n21 pain.notes `visible`: pain.notes/armed.ts (Lean armed, resumeAt, ticksIn; tests restate the #guard rows and
  naive_rearm_shifts), driver option `armWhenVisible`, env.now, index.tsx; visible.test.ts runs a virtual clock.
- n16 people.card `mq`: driver option `gate` (c860 band: no --future-shrink write, no re-request, class kept), index.tsx
  reads mq.c860; gate.test.ts compares gated and faithful runs. Limit: Lean premise P1 (band fixed per load); a resize
  across c860 leaves --future-shrink stale until the next frame outside the band.
- n15 hero.accent `steps`: steps.ts (bounds, chain, chainVal, plan; test = exact_chain_vis sweep vs step-end original),
  boil.ts (WAAPI zero-duration fill-forwards chain), accent.module.css rule disables the CSS boil under
  [data-fw-boil=steps]; index.tsx takes the start time from the CSS animation at mount. Chromium work: a trade when the
  original boil is compositor-run (cr_comp_*), WebKit equal: a lead call before default.

Built, NOT registered, NOT in the preset (wiring file is edited by a running wave-1 lane):
- n8 hero.countdown clock-aligned: hero.countdown/aligned.ts (nextAim, startAligned) + test. Needs index.tsx to call
  startAligned instead of startFaithful; also the variant slot is shared with `strip` (needs a combined variant name).
  Lean claim is noClaim (same work), a correctness fix only.
- n11 morph.panel rest: morph.panel/rest.ts (fade, radius, filterV, filterCss) + test. The filter lives in
  parts/platform (platform.module.css:12) and --morph-fade is written by parts/morph.tween: both outside this task.

No-op: n5 nav.hitTest write-on-change: Lean toggle_noop says the DOM already skips an unchanged class; nav.hitTest/logic.ts
already has `changed`. Nothing to build.

Goldens: no Lean golden rows exist for the Opt functions (packages/contracts/golden is outside this task); tests restate
the Lean #guard rows and compare against the faithful TS. A `Fw.Parts.*Golden` row kind per Opt function would let
goldenConformance check them directly.

Read first: pain.notes/driver.ts (sync, armed), hero.accent/index.tsx (boil), registry/presets/v2-proved.json.
