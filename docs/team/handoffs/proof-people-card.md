# proof-people-card handoff

**State:** `lean/Fw/Parts/PeopleCard.lean` proved (no sorry, standard axioms), imported in `lean/Fw.lean`; golden
`packages/contracts/golden/engine/people-card.jsonl` (20 rows) written by `goldenText`. Commit: see `git log` on this branch.

**Variant:** `rewrite+?fw=people.card:mq`, base `rewrite`. Gate = the generated `c860` media query (Fw/Site/Breakpoints).

**Theorems:** lerp restatement (`progress`, `target`, `lerpStep`, `stO`) with snapshot JS/CSS cites in the module doc.
(vis) `peopleCard_visSame` (class E, every env), from `look_gated`/`look_ungated`/`look_const_iff` (CSS forces scale 1,
radius 0 exactly in c860) and `cls_agree` (`is-future-shrinking` class agrees). (work) `run_le` (pointwise ⪯, any engine),
`frames_ungated_eq` (out of band identical), `cr_dominates` / `wk_dominates` (strict when a tail frame or a value-moving
write occurs in band), helpers `gate_le`, `gate_lt_*`, `frame_lt_tail`, `frame_lt_read`.

**Premises:** P1 band fixed per load; P2 in band, no-scroll frames keep progress t; P3 Rat for doubles; P4 the rest
of the frame is equal in both arms; P5 same-value inline write is a no-op (Chromium cpvs.cc:606-608, apscsd.cc:278-281
@f842f52; WebKit MutableStyleProperties.cpp:221-223 @862f17d).

**Golden:** model predicts `<o` for FunctionCall/UpdateLayoutTree, but `soften` emits `≤o` (swipe-v1 scrolls every frame,
so no tail frame is guaranteed; other parts may write style the same frame). WebKit RecalculateStyles/Composite `≤o`.

**TS variant must:**
- gate on the full c860 `matchMedia` string (`c860.css`), not `(max-width:860px)`; read once per load;
- in band: skip the `--future-shrink` setProperty and the rAF re-request in the lerp step `l`;
- keep the `is-future-shrinking` class toggle (threshold 0.04), the rect reads and the `.pain` toggle;
- out of band: run the original lerp unchanged.

**Open:** WebKit table has no custom-property restyle row (its restyle is not counted); Chromium subtree style units
(R2); no ungated-band profile (all swipe profiles are 430 px); band change mid-run (P1); P2 when the IO entry is
inactive; tail-frame existence in the swipe profiles (decides whether `<o` could be claimed).

**Read first:** module doc of `PeopleCard.lean`, then `peopleCard_visSame`, `run_le`, `cr_dominates`, the golden section.
