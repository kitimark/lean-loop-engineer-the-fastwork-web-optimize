# proof-morph-mount (handoff)
**State:** done in the worktree branch (commit in the report). `lake build` green, mathview 0 failing, standard axioms only, no sorry.
**Files:** `lean/Fw/Parts/MorphMountOpt.lean`, one import in `lean/Fw.lean`, `packages/contracts/golden/engine/morph-mount.jsonl` (20 rows,
generated from `goldenText`; regenerate with a `def main := IO.FS.writeFile "../packages/contracts/golden/engine/morph-mount.jsonl" goldenText` driver run by `lake env lean --run` from `lean/`).
**Visual (E):** `E_after_mount`: once the original has mounted, both scenes are equal for every env (all widths) and t; `visSame_mount`: E everywhere under `HiddenBefore`. Engine-free, so both engines.
**Work:** `chromium_shift` / `webkit_shift` (generic) and `cr_swipe_shift` / `wk_swipe_shift` (8-frame swipe): `ShiftLt` = motion peak strictly lower, unit and hit totals equal (so `shift_mainUs`: mainUs totals equal).
**Not Core `Shift`:** the warm-up frame is an extra rendering update, so commit passes are +1 (`shift_passes_succ`; #guard on both engines); style/layout pass totals are equal (`shift_passes_eq`).
**Screen says mixed** (`chromium_mixed`, `webkit_mixed`, `shift_screen_mixed`): the still frame gets heavier and the motion frame lighter, so no framewise order exists; `ShiftLt` is the right claim.
**Premises (INFERRED):** DOM insertion = one layout-level change per box plus one script callback; panel out of flow; `PhaseFree`; `HiddenBefore`; the counting window contains the warm-up frame.
**TS variant `morph.mount:shift` (flag on R) must:** keep the near/push mount triggers; add a `warm` trigger at a still moment (idle callback, no scroll or push in progress) that mounts the panel early;
start no animation, timer or phase at mount (state at t depends only on t, `PhaseFree`); keep the panel invisible until the morph is active (`HiddenBefore`);
report `meta.target`+search as `rewrite+?fw=morph.mount:shift` with base `rewrite` so engine-check pairs the rows; the counting run must include the warm-up frame.
**Golden predictions:** Chromium Layout, LayoutCount, dirtyObjects, invalidationAreaPx `=o` (totals); FunctionCall, UpdateLayoutTree, cc.Commit, PrePaint `any`. WebKit rows assume totals classes (none frozen yet; revisit when they freeze).
**Open:** the peak drop itself is not checkable by engine-check (no window); the design note's per-zone check (Layout/UpdateLayoutTree out of y04500) needs a windowed lane.
**Read first:** module doc of `MorphMountOpt.lean`, then `mount_shift`, `shift_screen_mixed`, `goldenLines`.
