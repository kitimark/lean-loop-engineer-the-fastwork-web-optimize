branch: worktree-wf_f89668d1-656-1; worktree: .claude/worktrees/wf_f89668d1-656-1 (split from morph-geom: the first builder hit 255k context; lead wrote this)
design: research/notes/2026/10-27-morph-compositor-geometry.md, section "Lean spec to write first" is the checklist.
state: lean/Fw/Parts/MorphGeom.lean (879 lines, no sorry, builds; not yet imported in lean/Fw.lean). Last commit: see git log (lead WIP commit on top of 4d73805c8).
done (proved): Track/eval/mk, chord, ChordOk, chord_aff, exact_of_aff, chord_sub_eq, chord_rat_eq, chord_rat_within, chordOk_grid_rat;
  sizes wd/ht/x0/y0/rad/kk (wd_eq, ht_eq, y0_eq, sizes, pill_le, rad_facts, mKnot phone knot); clip doors (RR, cTL..cBR, door, clip_eq, boxAt, cover, clip_pill);
  net offset bound navX/navY per band (net_ok_bands over bandVps by decide +kernel).
open (from the note's list): AnimProp allowlist inductive + Anim + layers/anims; rect_eq (bar, actions, columns, images, veil, centre, footer, backdrop clip, panel centre);
  fill_eq (premultiplied colorMix); panel_eq, fade_eq; earn_eq per engine (NavEarnWebkit / NavEarnOpt on the 60 Hz grid); logo_err; end_eq;
  accelerable v and noTransition; memBytes <= budget per band; generators: knot JSON, .is-flip and goal CSS, golden vectors for the TS track builder
  (lean/scripts/MorphGeomGolden.lean -> packages/contracts/golden/morph-geom*.jsonl), Fw.lean import, check.sh golden check + Trigger.lean row + triggers.jsonl.
conventions: decide +kernel over the band viewport table for numeric facts; grind for Rat algebra; keep each statement one line of English in the note, no LaTeX in Lean.
read first: the note's Lean section, then MorphGeom.lean lines 1-130 (Track, chord) and 360-430 (clip doors), lean/Fw/Parts/Nav.lean:244-257.
