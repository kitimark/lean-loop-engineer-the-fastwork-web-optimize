# compose-lean handoff (branch worktree-wf_ed01bde3-026-1)

State: all 7 statements of parts plan §C item 2 proved (no sorry, standard axioms only), module `Fw.Engine.Compose`
(imported in lean/Fw.lean), visual composition appended to `Fw.Engine.Visual`. Commit: see `git log -1` on the branch.

Proved (lean/Fw/Engine/Compose.lean unless noted):
- `passes_not_compositional` (any engine, any change `c` dirtying `s`): `g₁` drops `s`, is `≺ f₁` alone, page passes
  of `s` equal. General form `passes_absorb_part` (`passes_absorb` is taken by Lessons). Instances `passes_not_compositional_chromium/_webkit` (layout).
- `FrameIn.append` (`++` instance), `touched_append` (membership iff, not list equality), `passes_append`.
- `frameWork_append_units`, `frameWork_append_hits`, `frame_le_append_units`, `someLt_append_units`.
- `frame_le_append` as Fable wrote it (over ≼ alone) is FALSE for passes: `frame_le_append_passes_fails` (a forced
  style pass traded for a touched one is not absorbed on the page). True versions: `frame_le_append` from per-part
  `unionLe` (via `unionLe_append`), `frame_le_append_cover` from per-part covers (perm partitioned by part,
  `coverB_append`), strict `frame_lt_append` (units or hits strict in part 1).
- `someLt_append_units` needs a hypothesis Fable omitted: part 2 no larger on units.
- Visual.lean: `PartArm` (height, scene by offset), `stackScene`, `visible_scene_append`, `Q_append`,
  `visible_append_of_boxes_eq` (E) and `_Q`; heights must be EXACTLY equal (PL1 ½ px nearness does not compose).
- Lego: `swapSel`, `ReadsOnly Indep obs` (abstract dependency premise; contract-lean supplies `Independent`),
  `lego_swap_sound`, `lego_swap_units` (page units move by exactly the swapped part's change), `lego_swap_visible`,
  `pageOf`, `pageOf_congr`, `mem_zip_map_self`.

Open / limits:
- `Independent` is abstract; contract-lean must prove `ReadsOnly` for its table's frame/arm functions.
- Run-level (per-frame list) composition (`leAll`/`someLt` over zipped part runs) not stated; frame level only.
- Docstring checker: no subagent tool was available in this session; checklist applied by hand.

Read first: Compose.lean module doc, then `passes_not_compositional`, `frame_le_append_passes_fails`.
