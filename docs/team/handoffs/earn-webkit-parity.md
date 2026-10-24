# earn-webkit-parity handoff
Branch: worktree-wf_f45ca365-4a6-1 (CI branch ci/earn-webkit-parity). Worktree: .claude/worktrees/wf_f45ca365-4a6-1.
Last commit before this note: 86dde9fc4 (dispatch-1 trigger commit).
CI runs: dispatch 1 = run 40082730706 at 86dde9fc4, success (artifacts transitions-apple-390/-1280, download with
`gh run download <id> -n <artifact>`; `pnpm fw ci <id>` only reads chromium-counts runs). Dispatch 2 pushed at 2245a5009, running.
Dispatch 1 result: Playwright WebKit padding 24/16 -> 0 in the flip frame (0 frames between), Chromium eases ~10-15 frames; Safari 26.6
ran via safaridriver but its page showed no nav flip and `transition-property: none` (diagnostics added in dispatch 2).
Chromium on the macOS runner renders at 20-30 fps (headless, no GPU); WebKit at 60. Max 3 dispatches.
Verified: Lean `Fw.Engine.TransitionStart` builds, golden `transition-start.jsonl` --check passes (588 rows), engine-goldens
13 files equal; gate-breakpoints tests 718 pass; ci-paths 56 pass; actionlint clean.
Open: CI numbers for Chromium vs Playwright WebKit vs Safari (not read yet); research note; results summaries; check.sh/Fw.lean lines for lead.

## State
- Cause (CONFIRMED by source, to be corroborated by CI): WebKit@862f17d Styleable.cpp:535-566 sets the `padding-inline` shorthand's
  longhands to the logical `padding-inline-start/end`; their animation wrapper is nullptr (process-css-properties.py:5956), so
  Style::Interpolation::equals answers true and no transition starts on the physical padding-left/right. Chromium
  css_animations.cc:2993-3007 maps them `.ToPhysical`. Lean: theorems wk_paddingInline_never, cr_paddingInline_ltr, hero_entry_*.
- Harness: packages/gate-breakpoints/src/trajectory/transitions.mjs (capture, summary), transitions-safari.mjs (safaridriver),
  tests in test/transitions*.test.mjs. Workflow: probe-apple steps gated by `[transitions:` (needs `[frames:...]` flag token too).
- The 15 min macOS cap (Lean) forces `--morph 0` (hero sequences only) in CI.
- One local debug run is used (sim-lock, WebKit 1280, not a result).

## Next
1. `pnpm -s fw ci wait --branch ci/earn-webkit-parity --workflow trajectory-probe --sha <sha>`; fetch `pnpm fw ci <runId>`;
   artifacts transitions-apple-390 / -1280 (summary/*.summary.txt, safari-status.txt).
2. Dispatches 2 and 3 (empty commit with the same two lines) for >= 3 separate CI jobs per width.
3. results/earn-webkit-parity/ summaries, research/notes/2026/10-2x-earn-webkit-parity.md (answer first, per-frame tables,
   ranked fixes: logical longhands, physical longhands, padding shorthand, others).
4. Final gates: lean check.sh (expect missing Fw.lean import + check.sh job), merge main, fw plan lint, dry land, fw review ready.
For lead (not edited by me): `import Fw.Engine.TransitionStart` in lean/Fw.lean; job line in lean/scripts/check.sh:
`job "transition-start golden check" lake env lean --run scripts/TransitionStartGolden.lean --check ../packages/contracts/golden/engine/transition-start.jsonl`.
Outside writes made: lean/scripts/EngineGoldens.lean (row + import), lean/Fw/Ops/Premise.lean (engineFiles entry).
TS stand-in: the reduction in transitions.mjs.
