# Handoff: lean-doc-fix-r3 (fixes from math review round 3)

State: all 54 disagreements of `research/notes/2026/10-17-math-review-r3-a65aaa7.md` applied; 6 statements
strengthened or added instead of narrowing the text. Based on main 664323c. Gates: `lean/scripts/check.sh` green
(build, `lake test`, `mathview --lint`: 630 entries, 270 theorems, 0 failing, standard axioms only; wire goldens and
both `breakpoints.gen.json` copies byte-identical). `lean/MathView.lean` not touched.

## Statements changed (re-review the Lean and the $$)
- `Fw.Site.Breakpoints.gap600`, `gap640`, `gap860`, `gap1000`: hypothesis `e.width = Px.half N` (one
  representation) replaced by `2 * e.width.num = (2N+1) * e.width.den` (every `Px` whose value is N+½, e.g.
  2402/4). Strictly stronger; nothing used the old form.
- `Fw.Site.Breakpoints.matrix_fractional_in_gaps`: was "each fractional probe lies in some gap"; now the list of
  gaps containing each probe, in matrix order, is `[[600],[640],[860],[1000]]` (four probes, each in exactly one
  gap, four distinct gaps).

## New declarations
- `Fw.Site.Breakpoints.half_bounds` (2p = (2N+1)q, q > 0 implies Nq < p < (N+1)q) and `half_value`
  (`Px.half N` meets the gap hypothesis).
- `Fw.Parts.HeroExit.pointerOff_iff_threshold`: pointer events are off iff y > T + 19/20 n, n = max(1, h - v)
  (the threshold that `pointerOff_mono`'s old English claimed). `pointerOff_mono` keeps its statement, English
  narrowed.

## Docstring only (Lean unchanged)
Null `null_prob_5v5`, `null_prob_3v3`; Screen `leRun_spec`; Console `cardRefusal` (`;\\` row breaks fixed to
`;\ `); Breakpoints `pointerKw`, `motionKw`, `schemeKw`, `mediaTypeKw`, `forcedColorsKw`, `Feature.legacyCss`,
`MQ.legacyCss`, `MQ.taggedEdges`, `combo`, `Kind.str`, `catalogue_css`, `catalogue_axis_edges`,
`MQ.eval_indep_height_dpr`, `pairProbes`, `matrix_pairs_agree`, `matrix_cross_no_touch_arm`, `matrix_dw_arm`,
`matrix_landscape_overlaps` (stale inventory sentence); BreakpointGen `gapsJson`, `genJson`, `natList`,
`strList`, `checkCond`, `checkInventory`, `opBreakpointsGen`, `argOf`, `run`; EngineScroll `entryLe_trans`,
`orderCallbacks_perm`, `faithfulFrom`, `isRead_read`, `isRead_write`, `forced_mono`, `batched_le_one`,
`runs_le`; NavHitTest `findIdx?_congr'`, `findIdx_congr`; Golden `decimal?`, `rin`, `springJ`, `main`;
HeroCountdown `lexLe`, `faceDelta_settled`, `slices_nonpos`; HeroExit `pointerOff_mono`.

## Decisions
- `Golden.main`: the math now says 7 files (no `hero.countdown.spec.jsonl`); the generator was not changed, so
  the part goldens are unchanged.
- The gap proofs go through `half_bounds` and then `omega`: `omega` directly on `2p = 2001q` timed out
  (200k heartbeats).
