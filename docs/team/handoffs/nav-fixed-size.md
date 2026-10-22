branch: worktree-wf_fab081fd-3ca-1 (CI branches ci/nav-fixed-size f22e9fdbb, ci/nav-fixed-size-bar 0345da658, ci/nav-fixed-size-logo a4029ea02)
worktree: .claude/worktrees/wf_fab081fd-3ca-1 (repo-relative)
Round 2 (checkpoint 6): fix for the gate failure (transition-property lost `width`): box.module.css no longer names any transition; the union width is `width: var(--pill-w)` + `min-width: var(--panel-w)` while morphing, so the declared width equals the rest width at morph end. Lean: NavClipBox usedW_eq_unionW, decl_eq_rest_zero, decl_close_rest, used_eq_rest_one, layout_only_at_endpoints.
CI runs for round 2 (all success): per-flag breakpoint gates both engines nav:clip-box 39842609609, nav:bar-fixed 39846092556, nav:logo-3d 39848853982; trajectory-probe (inputs read back, verdict runs) 39842561544 / 39842569267 / 39842581192; lean 39842561311 / 39842569417 / 39842581076. Ledger rows nav.clip-box/bar-fixed/logo-3d added (partly-proved) so the compose test passes; dry land VERDICT dry nav-fixed-size. Open: layer census, cost lane, trajectory nav clip cell. Earlier failed gates: 39835303279, 39837964273.

## Verified (local, not results)
- Lean: Fw.Parts.NavClipBox, NavBarFixed, NavBarFixedWork, Fw.Engine.WebKitSimple build with no sorry; goldens nav-clip-box.jsonl and nav-bar-fixed.jsonl (100 rows each, `#guard include_str`); contracts golden (FootprintRows.lean, footprint-diff.gen.json) regenerated, `--check` up to date.
- Site: whole @fw/site vitest (117 files) green, tsc --noEmit clean; box.golden.test.ts evaluates box.module.css against the Lean rows.
- sh lean/scripts/check.sh: all stages green except contracts golden, which is fixed after it.

## Design facts a fresh agent needs
- A part has one variant, so the arms are cumulative variants (bar-fixed includes clip-box, logo-3d includes bar-fixed); part.json `requires` cannot name a flag of the same part. All three conflict with morph.panel:const-bounds.
- The rules live in nav/box.module.css, not nav.module.css: morph.tween/waapi.golden.test.ts pins the list of --morph readers of nav.module.css, and nav.module.css has a media test. Elements are named by data-fw hooks (data-fw-box-role on bar and logo only when a box variant is on).
- No JSX spread on the header: part-footprint.mjs resolves owners by literal attributes and a spread degrades them.
- Regenerate after source edits: `node apps/site/scripts/part-footprint.mjs --write`; in lean/: `lake build Fw.Parts.Contract`, `lake env lean --run scripts/ContractsGolden.lean --rows > Fw/Parts/FootprintRows.lean`, `lake build`, `--diff > ../packages/contracts/golden/parts/footprint-diff.gen.json`; `Fw.Preset.Gen.run []` for the v2-proved decisions (pre-commit checkmap asks).

## Open
- Dispatches only the lead can start (gate with fw=, layer census, cost lane): commands in the report.
- Trajectory nav clip cell: pending on gpu-trajectory-cells (the stock nav rect, border-radius and logo rect-in-nav units differ by design).
- Read first: research/notes/2026/10-2x-nav-fixed-size.md.
