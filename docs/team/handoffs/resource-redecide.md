# resource-redecide handoff

- Branch `worktree-wf_6702813d-087-1`, worktree `.claude/worktrees/wf_6702813d-087-1`; last sha in `git log -1`.
- No CI runs and no phone use in this task (accepted limit).

## State

- `lean/Fw/Engine/ResourceFlags.lean`: `decided` (evidence-resolved verdict: `moved`, `evidenceSign`, `resolvedSign`,
  proved per branch), DPR 3 repaint theorems (`strip_repaint_down`, `own_frame_repaint`, `logo_repaint_down`,
  `logo_frame_repaint_down`, `panel_repaint_up`), `strip_peaks_fit`, phone thermal strip rows (`thermalStrip`), CI rows
  for scene-pause and panel:rest, `thermalStripLayers`/`thermalStripBytes` census outside `observations`.
- `becomesWin` = strip WebKit; `leavesWin` = scene-pause WebKit trade, idle-none both open, panel:rest WebKit trade.
- `lean/Fw/Preset/Gen.lean`: `resourceOf`, `resourceTrade`, `Exclusion` (`hand` or `resourceTrade`, guarded),
  `panel_rest_not_mem`; every decision row has a `resource` field. `v2-proved.json` unchanged.
- Note: `research/notes/2026/10-2x-resource-redecide.md`; ledger notes with task `resource-redecide`.

## Verified

- `lake build Fw.Preset.Gen`, engine goldens `--write` then equal, Gen `--check` up to date,
  `packages/measure-webkit/test/resource-check.test.mjs` 5 of 5.

## Open

- Strip WebKit layer bound 72 is refuted on the phone (y 1500 drops at least 74); dropping it needs
  `resource-check.test.mjs` to accept 3 bounds (outside this task's writes).
- Range bounds need a spread rule before per-state CI layer rows enter (panel:rest y 3000).
- Scene-pause WebKit style rise (MEASURED) has no mechanism lemma.
- Strip enters `v2-proved` only after its trajectory cells pass (CI) and Chromium is decided.

## Read first

The note above, then `decided` and `becomesWin` in `ResourceFlags.lean`.
