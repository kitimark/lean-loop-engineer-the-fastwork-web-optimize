# Handoff: integrate-ports-3 (branch worktree-wf_b37180a7-494-1, CI ref ci/integrate-ports-3)

Merged in order: integrate-ports-2 (26e5f53), fix-page-offset (incl. fix-pain-notes), fix-commission-margin, main (already up to date).
Conflicts: research/findings/ledger.json (kept the *Opt names + why-engines mechanism of integrate-ports-2),
lean/Fw/Ops/Premise.lean (registry union: cv.skip-flag, cv.fresh-after-resize are p24, p25), premise.jsonl (regenerated).
Generated files replayed (sweepsgen, partsgolden, scopegen, ci-paths): no further diffs. Added $$ math to PageOffset.lean and PainNotes.Render.

## Gate runs (breakpoint-gate, full matrix, both engines)
| run | head | chromium | webkit |
|---|---|---|---|
| 39101532038 | merge | morph.countdown wrap margin-top (40 probes), commission inner/rows margin-inline desk-rm-1280, hero.orbit card z-index desk-rm-860 | morph.countdown wrap margin-top |
| 39105279831 | a1eccb8 | hero.orbit card z-index desk-rm-861 | commission: 11 probes (view reading flips scene state), touch-rm-1000/1201 |
| 39108604447 | 9e23e15 | hero.orbit card z-index desk-rm-860 | pass (72 cells) |
Run 4 (this head): orbit z-index skipped in anchors.json (result in the final report).

## Cells
1. pain.notes note x: PASSES since fix-page-offset (the 152 px page offset was the cause), all three runs.
2. morph.panel vs morph.countdown: panel's `countdown` role owns the wrapper (margin 32); morph.countdown `wrap` role skipProps margin-top (anchors.json).
3. commission margin-inline desk-rm-1280: Chromium reads stale used auto margins of a skipped (content-visibility) original subtree. Fixed in the gate: the
   Settle `view` reading (bring into view, read again) is on for Chromium probes only, root-aligned scroll (page.mjs bringInPage). WebKit breaks with it
   (run 39105279831), and does not need it. Passes in 39105279831 and 39108604447.
4. hero.orbit card z-index (new): orig-only inline hover raise (never lowered), card 3 covers (0,0) where a fresh page's pointer starts; 1 of 30 desk-rm probes per run.
   Pointer parked before navigation (engines.mjs) did not remove it; z-index is now in the card role's skipProps. Not proved by a Lean row.

## Open
- The settle wait reports 312 of 392 samples UNSETTLED in every run (orig and rewrite, running 4, parked): verdicts still computed; not investigated.
- Gate page-offset cell (PageOffset.lean) is still a proposal, not wired into page.mjs.
- View reading choice per engine is glue in run.mjs viewFor, with no Lean row for "which engine".
