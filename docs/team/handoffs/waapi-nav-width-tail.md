# waapi-nav-width-tail handoff

State: branch worktree-wf_b3496b15-80f-1. Decision (b), look change: driver, golden and part.json are unchanged; no
CI push. Verified: `sh lean/scripts/check.sh` is green (axioms, props-lint); the module elaborates in about 5 s.
Read first: research/notes/2026/10-21-waapi-nav-width-tail.md (mechanism with file:line, measured table, cost).

Lean (`Fw.Parts.MorphTweenOpt`, section `WidthTail`):
- `closeAt_cross`, `morphing_iff`: on a close, `is-morphing` turns off at 612 ms.
- `tailPx_eq`, `tail_orig_pos`: the original jumps `(panelW - pillW) * closeAt(prev)`, which is positive.
- `tail_waapi_zero`: the waapi arm has no jump. `tail_not_view`: the jump depends on the frame before.
- `skip_once`, `skips_le_one`: an exact driver skips script on at most one next frame.
- `tailArm`, `tail_decided`: the decision is `.lookChange`. #guards give px at 60 Hz and at Linux WebKit p50/p90 gaps.

Findings-ledger row (the lead applies it; ledger.json is not edited here):
- id `morph.tween.waapi.navWidthTail`; part `morph.tween`; flag `morph.tween:waapi`; status `look-change`
- candidate: the waapi arm drops the original's 680 ms nav width transition that starts when `is-morphing` turns
  off on a close
- chromium ≤0.81 px (not visible); webkit up to 209 px on Linux WebKit at 1280 px, ≤2.92 px on macOS (MEASURED:
  runs 39457767229, 39412301221, 39471466367; control 39457063232)
- mechanism: CSS 2.gBuqKVzi.css:11355-11361, JS 2.DyWL8TcE.js:12947 and 13221-13243, Chromium
  css_animations.cc:3214-3293 @f842f52, WebKit Styleable.cpp:604-632 and StyleTreeResolver.cpp:894-898 @862f17d
- lean: tail_orig_pos, tail_waapi_zero, tail_not_view, skip_once, tail_decided
- lesson: a transition keyed on a class flip starts from the previous frame's base style; a frame-skipping driver
  cannot reproduce it.

Open:
- An optimized variant cannot carry visClass L: the registry needs a decision (proposal kind, or record the change).
- The `waapi_vis` docstring says E-s; `tail_not_view` refutes this for nav width.
- The background transition at the flip belongs to trajectory-close-start.
- Count the original's post-close width-transition layout frames as saved work.
