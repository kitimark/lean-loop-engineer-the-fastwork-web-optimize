# morph.stage (design rank 1 of 10-26-end-scroll-designs)

Status: in progress. Look change, class L; T and the look are for the user's review. Never a preset.

- Flag `morph.stage:on`: the platform scene is `position: sticky` over T px of added page; `--morph` and
  `--morph-fade` run on `animation-timeline: scroll(root)` over [maxY - T, maxY]. No scrollTo, no non-passive
  listener; morph.mount and morph.tween scroll-jack is not mounted.
- Lean: `lean/Fw/Parts/MorphStage.lean`; golden `packages/contracts/golden/parts/morph-stage.jsonl`.
- Results: pending (sections are added as runs finish).
