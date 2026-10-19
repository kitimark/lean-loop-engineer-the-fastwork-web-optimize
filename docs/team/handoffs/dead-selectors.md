# dead-selectors handoff

State: branch worktree-wf_ebd5ee90-ef5-3. Commits a051b0a8 (selectors + liveness test), 55ee1b6c (regenerated rows), r1 commit (identity hooks).
Every selector pain.notes and nav.hitTest query is an identity hook (no `class*=`).

- New hooks: `data-fw="people-sticky"` (people.deck sticky div), `data-fw="nav-actions"` (nav actions div), `data-fw-shrinking`
  (commission driver `toggleAttribute` beside the class toggle; `StyleEl` gains `toggleAttribute`). `[data-fw="commission-card"]` from r0.
- nav.hitTest/logic.ts: EXCLUDE = commission-card, people-card, hero-exit (the hero stage, as the original `.hero`); INCLUDE = pain, platform;
  SHRINKING = `[data-fw-shrinking]` (the resolver needs one element carrying all attributes: toggleAttribute is its own runtime element,
  so a compound with data-fw would not resolve); ALLOW = one string literal: nav-actions, `[data-expanded]` (only morph.panel writes it,
  same reason), nav-earn while the nav is not hero-pill/morphing. Constants PAIN/NAV (logic.ts), PAIN_COPY/NOTE (pain.notes/logic.ts) exported.
- Removed with reason: the original's `.start-selling-morph-pill` and `.start-selling-morph` alternatives; the original renders no such element
  (CSS only, 2.gBuqKVzi.css:10496, 10518); only the top-nav `.is-expanded` panel rule was live.
- Footprint: nav.hitTest has no dynamic-match/dynamic-selector; rects name people.deck and hero.exit; no hero.countdown/hero.orbit.
  FootprintRows nav.hitTest loses those two inputs; footprint-diff `missing` is `rect:people.deck` only. The pain.notes rect:commission change is r0's.
- Test pain.notes/liveness.test.ts: every selector constant is a unit; stateful ones check their static part plus source (commission driver
  writes data-fw-shrinking; nav driver toggles is-hero-pill/is-morphing via CLASS_OF; morph panel writes data-expanded); asserts no `class*=`.

Accepted limits: (1) `[data-fw-note="<id>"]` is client-written and templated: footprint reports `templated-selector`; liveness = source check.
(2) morph panel, shrinking and nav-earn states are checked by source read, not rendering. (3) the test matcher is TS, not Lean-derived.
Follow-up (lead to add to work-graph; not edited here): nav/index.tsx defaults `stickySelector`/`sectionSelector`/`splashSelector` still use
original class names ("nav defaults selectors dead", nav lane).
Verified at r1: site test 88 files/5352 pass, typecheck, part-footprint --check, ci-paths 32, land-inputs 40, lake build, ContractsGolden --check.
check.sh result: see the report.
