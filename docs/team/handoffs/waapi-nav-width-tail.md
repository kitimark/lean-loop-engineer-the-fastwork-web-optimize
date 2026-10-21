# waapi-nav-width-tail handoff (round 3, final design round)

State: branch worktree-wf_b3496b15-80f-1; driver c934d86b, r3 Lean b93f6dde, note 6eae4413. Run 39504209400 (7ae872ab,
every cand search `?fw=morph.tween:waapi`): Chromium 1280 5/5 hits with |cand - pred| ≤ 0.008 px. macOS WebKit 1280:
4 hits, 1 miss, 0 of 4 hits equal (0.65-1.67 px): WebKit starts no width transition in the waapi arm, before and after
the window. The unit holds on Chromium only; the WebKit half is a finding (`model-false`), not patched here.
Read first: research/notes/2026/10-21-waapi-nav-width-tail.md (identity rule, per-rep table, WebKit finding, cost).

Lean (`Fw.Parts.MorphTweenOpt`, WidthTail): new `hit_iff_mP` (exact hit: m(P) ≤ closeAt(baseDelay) ≈ 0.01508),
`miss_look_ge` + `missFloor` (#guards 3.60 px at 1280, 0.11 px at 390). Hit chain: `hit_iff_mP`/`base_hits` + driver
test "a close writes the base --morph ..." + `tail_eq_of_base`. Data scripts: scratchpad wnwt3/py/tail3.py, mr2.py.
Verified: lean check.sh, apps/site test + typecheck (see report).

Findings-ledger row (the lead applies it; no ledger.json or part.json edit here):
- n 9; id `morph.tween.waapi.navWidthTail`; part `morph.tween`; flag `morph.tween:waapi`; status `partly-proved`
- candidate: the waapi driver writes the base `--morph` from 100 ms before the 0.001 marker to the end of a close
- chromium `trade` (9 extra script frames per close at 60 Hz, tail restored); webkit `model-false` (same cost, no
  width transition starts in the waapi arm)
- mechanism: CSS 2.gBuqKVzi.css:11355-11361; JS 2.DyWL8TcE.js:12947, 13221-13243; Chromium css_animations.cc:3214-3293,
  2703-2716, 2861-2882 @f842f52; WebKit Styleable.cpp:604-632, 705-756, StyleTreeResolver.cpp:894-898 @862f17d
- leanFor: hit_iff_mP, base_hits, tail_eq_of_base, miss_look_ge, tail_zero_of_base_still, tailDecision, tail_orig_pos
- visual: Chromium 1280 5 hit/0 miss, 5 equal; macOS WebKit 1280 4 hit/1 miss, 0 equal; Chromium 390 5/0, 5 within
  0.05 px; macOS WebKit 390 4/1, 2 within 0.05 px
- evidence: run 39504209400 (pre-fix 39471466367 for the WebKit shape)
- missingWhy: Linux WebKit by design (walks_linux_webkit); 390 not discriminating; misses bounded below by miss_look_ge
- lesson: a base write under a script animation restores the transition start on Chromium; WebKit needs its own check
- next: locate why WebKit starts no width transition (debug run, transition events); `waapi-tail-drop` (option b)
- userDecision: pending
Open: WebKit cause INFERRED (class flip and base write in different style change events), unverified.
