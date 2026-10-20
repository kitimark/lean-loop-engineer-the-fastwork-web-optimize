# Handoff: scoped-close-start-cause

State: branch `worktree-wf_da1a1d10-06c-1`; the commit is the one `git log -1` shows on `ci/scoped-close-start-cause`.

Decision: (b), timing-only. No part change, no golden change, no look change.

Mechanism (note `research/notes/2026/10-21-scoped-close-start-cause.md`):
- The close start colour is `bgAlpha(m_prev)`, `m_prev` the morph value of the last frame that saw `is-morphing`
  (removed at m <= 0.001, 68 ms before the tween ends). WebKit keeps the previous style-change event as the transition's
  before-change style (`Styleable.cpp:606-617, 646-676@862f17d`, `StyleTreeResolver.cpp:926 before :940`).
- A gap of g ms to the first frame without the class allows `m_prev <= ((68+g)/680)^3`; 114 ms gives ~226, 203 ms ~203.
- `hero.exit:scoped` writes `--exit-opacity` and `--exit-scatter` on hero elements only; the nav reads `--morph`.

Verified:
- Lean `Fw.Parts.HeroExitCloseStart` (new, imported in `lean/Fw.lean`): `closeAt_cube`, `morphing_of_lt`,
  `not_morphing_of_ge`, `prev_le_bound`, `bgAlpha_lt`, `bgAlpha_inj`, `startAccepts_tween`, `startAccepts_above`,
  `scoped_writes_miss_nav_bg`, `scoped_writes_miss_nav_elements`. `sh lean/scripts/check.sh` green.
- `node --test scripts/ci-paths.test.mjs` 49/49; `apps/runner` `land-inputs.test.ts` 55/55.
- Stored runs 39466179818 (flag-alone `?fw=hero.exit:scoped`) and 39472217441 (A/A), `?fw` hashes read per arm.
  Not fresh runs: the lead dispatches those (see `open[0]` of the report).

Findings:
- Cells below 245 of 20: flag-alone scoped 7, orig 3, base 2; A/A orig 3, base 2, candidate 2 (low tails in every arm).
- Scoped has more low cells than the others in its run; n = 20 does not separate it from frame-cadence noise.

Open:
- Fresh flag-alone and A/A mac-webkit morph runs (>= 3 reps, 4 widths) from the lead.
- `trajectory-envelope-scope` owns `Trajectory.lean`: the rule is `startAccepts` (reading in
  `(bgAlpha morphingCut, bgAlpha (prevBound g)]`, g the observed gap at close@0). Not applied here.

Ledger keys (the lead edits the ledger): update `hero.exit.scoped.inline` (mac morph bg close-start mechanism and
decision (b)); new candidate row for "close start colour is a frame-phase value (`bgAlpha(m_prev)`)".

Read first: the note's Mechanism and Decision sections, then `HeroExitCloseStart.lean`.
Other writes: `lean/Fw.lean` (import line, required by `check-imports.mjs`).
