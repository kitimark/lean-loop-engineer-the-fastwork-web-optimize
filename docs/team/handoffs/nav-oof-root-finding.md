# nav-oof-root-finding

State: round 2 on branch `worktree-wf_887f1e36-223-2`; round 1 content at 92ceee51, round 2 content in the commit
after it on this branch. Negative finding, no site change, no CI run.

Verified:
- `lean/Fw/Parts/NavOofRoot.lean` builds with no sorry; axioms propext and Quot.sound only; `sh lean/scripts/check.sh`
  green at the final commit.
- Key theorems: `Tree.oof_view_full` (a dirty out-of-flow box whose containing block is the view schedules a full
  pass for every boundary choice), `Tree.layoutRoot_skips_self`, `nav_pass_full`.
- Round 2: `Tree.fixedCb` recomputes out-of-flow containing blocks from a fixed-container test that can be the
  boundary test; `fixedCb_partial_moved` (partial pass implies the containing block left the view) and
  `nav_contained_root` (a boundary on #root gives `subtree #root`, the nav re-anchored).
- Run 39292323514 r1-r3 re-read from artifacts: frames 498-530 give 33 passes, 1077 dirty, 52470 total, partial 0.
- Engine lines re-read at chromium@f842f52 and WebKit@862f17d, incl. ComputeIsFixedContainer (:2012-2061) and
  WebKit mayContainOutOfFlowPositionedObjects (RenderElementStyleInlines.h:55-79): containment there is read in source.

Scope of the claim: only boundary choices that leave the nav's containing block at the view. Containment, transform
or filter (filter not on html) on html, body or #root moves the containing block; ruled out by the visual change.

Deviation from the brief: `oof_root_indep` is proved as `layoutRoot B x = climb B c`. The brief's form
`layoutRoot B x = layoutRoot B c` is false when `c` is a boundary.

Open items:
- Frames 517-530 (32 objects and 318 elements per frame with no rAF) belong to tween-platform-scope.
- WebKit was not measured; its half rests on source.
- The nav attribution of the 32 dirty objects is INFERRED.

Registry write: one appended import line in `lean/Fw.lean`. Read first: `research/notes/2026/10-20-nav-oof-root-finding.md`.
