# lean-specs-now handoff (branch worktree-wf_1f78144b-bf8-1)

State: 4 spec sections proved, no sorry, standard axioms only; `lake build` of each module and `lean/scripts/check.sh`
ran green. Commits: df1202f4 (n22), dc6a38ea (n8), then one commit for n18/n19 and this note (`git log -1`).
No Engine, ledger or golden file touched; flags stay off.

Proved:
- n22 `Fw.Parts.CommissionTyping`: `flag_sublist`, `frame_sublist_le`, `variant_total_le` (variant callback is a
  sublist, so forced and total passes never exceed, any frame context), `ro_compact_saves` (exactly 1 style pass;
  layout 1 only when the next layout access is a write), `ro_desktop_eq` (no saving).
- n8 `Fw.Parts.HeroCountdown`: `rollFrames_eq_run` (spring state depends only on the concatenated 16 ms slices),
  `frameDurs_mul16`, `rollFrames_mul16`, `stepFrames_eq_run`; 60 Hz splits differ (#guard).
- n18 `Fw.Parts.PeopleO` (imports Fw.Engine.Core): `flipMid_work`, `origMid_work`, `flip_main_lt`, `flip_not_le`,
  `flip_lt_of_comp_sub`. Finding: the ledger's `flip_work_lt` (≺) is FALSE whenever a compositor stage is outside the
  size change's stages and base (both tables: `comp`); FLIP is a trade per frame, main-thread stages drop to 0.
- n19 `Fw.Parts.PeopleCarousel` (imports Fw.Engine.Core): `swap_main_le`, `swap_layout_units`, `swap_lt` (0.999 bridge,
  engine-agnostic), `swap_not_le` (st6 slide adds translate anims: trade), `st6_no_flip`, `st6_anim_lt_one`,
  `st6_slide_no_flip`, `st5_flip`, `follower_shift` (followers move 24p px = the translate).

Proposed ledger rows (lead applies):
- row 35 n22: status proved (passes component); leanFor += CommissionTyping.variant_total_le, frame_sublist_le,
  flag_sublist, ro_compact_saves, ro_desktop_eq. Open: RO delivery phase cost, units per pass, matchMedia script.
- row 7 n8: stays partly-proved; leanFor += HeroCountdown.rollFrames_eq_run, rollFrames_mul16, stepFrames_eq_run,
  frameDurs_mul16. Open: fixed-cadence E-s theorem (HeroCountdownOpt).
- row 28 n18: missingWhy flip_work_lt refuted as ≺; leanFor += PeopleO.flip_main_lt, flipMid_work; leanAgainst +=
  PeopleO.flip_not_le. Status: trade (main-thread win, comp cost), not "dominates".
- row 30 n19 st6 rest: leanFor += PeopleCarousel.swap_lt, st6_no_flip, st6_slide_no_flip, st5_flip. Open: CI fixture,
  Chromium table premise (stagesOf rest ⊆ flip, layout only in flip) once model-bug-fixes lands.
- row 31 n19 slide geometry: leanFor += swap_main_le, swap_layout_units, follower_shift; leanAgainst += swap_not_le.

Open: edge frames of FLIP (start/end, cleanup) and run totals not stated; docstring checker: no subagent tool in this
session, checklist applied by hand.
Read first: the section docs before `flipMid` (PeopleO) and `frameWith` (PeopleCarousel).
