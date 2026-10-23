# people-o-preview-translate: handoff

Branch: worktree-wf_2ffa3f6a-227-1 (CI branch ci/people-o-preview-translate)
Worktree: .claude/worktrees/wf_2ffa3f6a-227-1
Last commit: e7f5b39b1 (finish), then the lead fix-before-land commit
CI runs: gate 39850908365 SUCCESS (both engines). Counts BLOCKED by task chromium-desktop-crash (renderer SIGSEGV at load of any page wider
than 860 px, base and flag alike); the 15 failed run ids are in research/notes/2026/10-2x-people-o-preview-translate.md and results/people-o-preview-translate/report.json.
Verified: Lean check.sh, site tests, gate. Open: re-run people-o-hover counts after chromium-desktop-crash; then set the ledger row (n 53) chromium/webkit.
Removed: the flag-drop and width bisect profiles and run.mjs profile.dropFlags (untested). Kept in run.mjs: load diagnostics (crash log, hangProfile) for chromium-desktop-crash.


- **Unit:** `people.o:preview-translate` (desktop > 860 px). Lean `lean/Fw/Parts/PeopleOPreview.lean` (check.sh green), golden
  `packages/contracts/golden/parts/people-o-preview.jsonl` (246 lines, `lean/scripts/PeopleOPreviewGolden.lean`), flag code
  `apps/site/src/parts/people.o/{preview.ts,index.tsx}`, site test `preview.golden.test.ts`.
- **Lean theorems:** `snap_noFlip` (position and phase equality for integer y, y0, no flip), `step_faithful` (shown top and left equal
  the faithful ones from any held state, so flips, clamps and viewport changes are faithful), `keep_translate`, `keep_clamped`,
  `keep_whole`, `keep_pixel`, `frac_counter` (a fractional shift breaks the pixel), `faithful_layout`, `translate_layout_kept`
  (layoutPasses 0 on non-flip frames, both engines, own layer), `translate_layout_flip`, `translate_work_lt`, `layer_budget_zero`.
- **WebKit scroll offsets are integral:** `ScrollTypes.h:47-49` (`ScrollPosition = ScrollOffset = IntPoint`),
  `LocalDOMWindow.cpp:1466` (`scrollY` is `int`)@862f17d. Chromium may be fractional: the keep test falls back to a rewrite then.
- **Premise (INFERRED):** the fixed card has its own layer (`RenderLayerCompositor.cpp:4097-4150`@862f17d). WebKit table: `transform`
  on a non-composited layer still runs layout.
- **Outside the task's writes (lead to accept):** `lean/Fw.lean`, `lean/scripts/check.sh`, `lean/scripts/PeopleOPreviewGolden.lean`,
  `lean/Fw/Ci/Trigger.lean` + `golden/ci/triggers.jsonl`, `lean/Fw/Parts/FootprintData.lean`, `FootprintRows.lean`,
  `golden/parts/footprint*.json`, `golden/preset/v2-proved.decisions.jsonl` (regenerated), `packages/measure-chromium/src/run.mjs`
  (segment `anchor` and `eval`), `packages/measure-chromium/profiles/people-o-hover.json`, `research/findings/ledger.json` (row n 53).
- **Counts scenario:** profile `people-o-hover` (1280x800, synthetic mouseover on the first face, 40 scroll frames at 10 px). Question:
  Layout count per frame of phase `scroll`, base vs `--fw people.o:preview-translate`.
- Note: `research/notes/2026/10-2x-people-o-preview-translate.md`.
