# lean-specs-now handoff (branch worktree-wf_1f78144b-bf8-1)
State: 4 spec sections proved, no sorry, standard axioms only; the 4 modules build, mathview lint 0 failing. Commits:
df1202f4 (n22), dc6a38ea (n8), d7e889fd (n18/n19), then fix round 1 (`git log -1`, main merged). No Engine, ledger
or golden file touched; flags stay off.

Proved:
- n22 `Fw.Parts.CommissionTyping`: `flag_sublist`, `frame_sublist_le`, `variant_total_le`, `ro_compact_saves`,
  `ro_desktop_eq`; all scoped to the scroll-list phase of a frame (RO delivery not counted).
- n8 `Fw.Parts.HeroCountdown`: `rollFrames_eq_run`, `frameDurs_mul16`, `rollFrames_mul16` (gaps of whole 16 ms
  multiples), `stepFrames_eq_run`; 60 Hz splits differ (#guard).
- n18 `Fw.Parts.PeopleO`: `flipMid_work`, `origMid_work`, `flip_main_lt` (part alone), `flip_not_le`,
  `flip_lt_of_comp_sub`; `#guard` refutes ⪯ on the real `Chromium.chromium` (height) and `WebKit.webkit` (size).
  Finding: the ledger's `flip_work_lt` (≺) is false in both tables (`comp`); FLIP is a per-frame trade.
- n19 `Fw.Parts.PeopleCarousel`: `swap_main_le`, `swap_layout_units`, `swap_lt` (premise open, no added anims),
  `swap_not_le`, `st6_no_flip`, `st6_anim_lt_one`, `st6_slide_no_flip`, `st5_flip`, `follower_shift` (border-box).

Proposed ledger rows (lead applies):
- row 35 n22: stays partly-proved; leanFor += CommissionTyping.variant_total_le, frame_sublist_le, flag_sublist,
  ro_compact_saves, ro_desktop_eq; missingWhy 'RO delivery phase (post-layout writeStyle) not bounded'.
- row 7 n8: stays partly-proved; leanFor += rollFrames_eq_run, rollFrames_mul16, stepFrames_eq_run, frameDurs_mul16.
  Open: fixed-cadence E-s theorem (HeroCountdownOpt).
- row 28 n18: missingWhy flip_work_lt refuted as ≺; leanFor += PeopleO.flip_main_lt (page saving needs
  Compose.passes_absorb_part), flipMid_work; leanAgainst += PeopleO.flip_not_le. Status: trade, not "dominates".
- row 30 n19 st6 rest: leanFor += swap_lt, st6_no_flip, st6_slide_no_flip, st5_flip. Open: CI fixture, both tables'
  premise (stagesOf rest ⊆ flip, layout only in flip) once model-bug-fixes lands.
- row 31 n19 slide geometry: leanFor += swap_main_le, swap_layout_units, follower_shift; leanAgainst += swap_not_le.

Open (accepted limits): RO delivery phase (n22); n18 FLIP start/end frames and run totals; n19 CI fixture; the
Chromium premise of swap_lt. Docstring checker: no subagent tool in these sessions, checklist applied by hand.
Read first: the section docs before `flipMid` (PeopleO) and `frameWith` (PeopleCarousel).
