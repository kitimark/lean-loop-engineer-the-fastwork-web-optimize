# dead-selectors handoff

State: branch worktree-wf_ebd5ee90-ef5-3, one commit. Selectors of pain.notes and nav.hitTest now target our data-fw hooks.

- pain.notes: `CARD_SELECTOR` (logic.ts) = `[data-fw="commission-card"]`; the hook is new on the commission card (commission/index.tsx).
- nav.hitTest/logic.ts: EXCLUDE = commission-card, people-card (the original future card), hero; INCLUDE = pain, platform (card sits inside);
  SHRINKING = `[data-fw="commission"][class*="shrinking"]` (CSS-Module class, substring match); ALLOW = nav actions, morph-panel[data-expanded],
  nav-earn when the nav is not hero-pill/morphing. Removed with reason: the original's `.morph-pill` entry (our pill is the nav itself).
- probe.ts: profile sticky/section now `[data-fw="people-deck"] > [class*="sticky"]` and `#profile-showcase, [data-fw="people-deck"]`.
- Test: pain.notes/liveness.test.ts prerenders the home page and matches every selector unit with a small built-in matcher.
  State-dependent units (shrinking class, nav-earn while hero-pill) check their static half; the morph panel is client-mounted (checked in source).
- Regenerated footprint.gen.json + FootprintData.lean (line numbers shifted); lake build of FootprintData green.

Open / follow-ups: nav/index.tsx still defaults `stickySelector`/`sectionSelector`/`splashSelector` to original classes (nav lane).
engine/pilot-frame.test.ts mock updated for the new sticky selector. check.sh not run here (load); run at land.
Read first: apps/site/src/parts/nav.hitTest/logic.ts, pain.notes/liveness.test.ts.
