branch: worktree-wf_fab081fd-3ca-1 (CI branches ci/nav-fixed-size, ci/nav-fixed-size-bar, ci/nav-fixed-size-logo)
worktree: .claude/worktrees/wf_fab081fd-3ca-1 (repo-relative)
last commit: see `git log -1`; CI tips (checkpoint 4, 2026-10-22 18:25Z): ci/nav-fixed-size cece43bf, ci/nav-fixed-size-bar d6671674, ci/nav-fixed-size-logo 7de81c8d (same code as 3b96c928; tips 3 got NO runs at all, the pushes were dropped; `fw ci push` rewrites the tip message, so the tips were pushed with plain branch -f + git push)
CI runs: none listed yet for the checkpoint-4 tips; list with `gh run list --commit <sha>`. Trajectory lines are in each tip message.
  Superseded (stale, old CSS location): lean 39822710985 success (13954230), breakpoint-gate 39822711037, trajectory-probe 39822710976, lean 39822861544 (7b361731), trajectory-probe 39822861643.
  Current tips: run ids not yet created when this was written; list with `gh run list --branch <b>`.

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
