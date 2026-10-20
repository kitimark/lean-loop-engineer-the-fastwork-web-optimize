# exit-scoped-inline handoff

State: branch `worktree-wf_a2e03981-f12-2`, see the last commit there; `ci/exit-scoped-inline` points at it.

Verified:
- Mechanism of bug A CONFIRMED from WebKit source @862f17d (MatchedDeclarationsCache key ignores the parent's
  non-inherited custom properties; a hit re-applies only `inherit` declarations). Cites in
  research/notes/2026/10-20-exit-scoped-inline.md and the ledger note (task exit-scoped-inline).
- Lean `Fw.Parts.HeroExitOpt` (section Scoped): `wkResolve` cache model, `wkRun_chain_frozen`, `chain_stale_webkit`,
  `chain_eq_chromium`, `inline_visSame`, `inline_units`, `inline_touched` (17), `inline_lt_faithful`,
  `inline_narrow_delta` (90).
- Golden packages/contracts/golden/parts/hero.exit.scoped.json regenerated from lean/scripts/ExitScopedGolden.lean;
  apps/site scoped.test.ts checks readerWrites, reader classes, SSR reader count 16 and writer order.
- Fix: apps/site/src/parts/hero.exit/{scope.ts,driver.ts,index.tsx} write --exit-opacity and --exit-scatter inline on
  each reader (READER_SELECTOR by data attributes, queried once on mount) in the same writer as the stage.
- Regenerated (outside graph writes): footprint.gen.json, FootprintData.lean, FootprintRows.lean,
  footprint-diff.gen.json; Bridge.lean literals recomputed (hero.cue no longer isolated, 13 rows; 322 chain pairs).

Open (lead dispatch, not delivered):
- Trajectory `--fw hero.exit:scoped` x2 and A/A `--fw hero.exit:faithful` on ci/exit-scoped-inline; expect WebKit
  new units 187 -> 0.
- Chromium counts swipe-v1 for scoped and faithful (elementCount per scrolled frame).
- Then update the ledger note with run ids and MEASURED status.
- docs/report/v2-report.md lines 124, 559 (14 isolated parts incl. hero.cue) are stale; the Contract row of hero.exit
  does not yet declare the reader outputs (footprint-diff lists them as missing).

Conventions: ledger edits are one appended `notes` row per (entry, task); never edit the shared mechanism string.

Read first: the research note, then `section Scoped` in lean/Fw/Parts/HeroExitOpt.lean (search `wkResolve`).
