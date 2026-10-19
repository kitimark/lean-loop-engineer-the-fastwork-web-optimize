# nav-oof-root-finding

State: done on branch `worktree-wf_887f1e36-223-2` (commit in the report). Negative finding, no site change, no CI run.

Verified:
- `lean/Fw/Parts/NavOofRoot.lean` builds with no sorry; `sh lean/scripts/check.sh` is green at the final commit.
- Key theorems: `Tree.oof_view_full` (a dirty out-of-flow box whose containing block is the view schedules a full
  pass for every boundary choice), `Tree.layoutRoot_skips_self`, `nav_pass_full`.
- Run 39292323514 r1-r3 re-read from artifacts: frames 498-530 give 33 passes, 1077 dirty, 52470 total, partial 0.
- Engine lines re-read at chromium@f842f52 and WebKit@862f17d; cites are in the note.

Deviation from the brief: `oof_root_indep` is proved as `layoutRoot B x = climb B c`. The brief's form
`layoutRoot B x = layoutRoot B c` is false when `c` is a boundary.

Open items:
- Frames 517-530 (32 objects and 318 elements per frame with no rAF) belong to tween-platform-scope.
- WebKit was not measured; its half rests on source.
- The nav attribution of the 32 dirty objects is INFERRED.

Registry write: one appended import line in `lean/Fw.lean`.

Read first: `research/notes/2026/10-20-nav-oof-root-finding.md`.
