# Handoff: guidance-proofs

State: branch `worktree-wf_9a58162f-174-2`; Lean in `lean/Fw/Guidance/` (6 modules, imported in `lean/Fw.lean`),
note `research/notes/2026/10-18-guidance-proofs.md`. `lake build` and `lean/scripts/check.sh` were green at the last commit.

Verified:
- 38 cells (19 "yes/partly" rules × Chromium, WebKit): 5 proved, 3 refuted, 25 conditional, 5 out-of-model.
- The note's Answer-first table names the theorem behind each cell.
- No sorry, no native_decide. `#print axioms` on 17 key theorems shows only propext, Quot.sound and
  Classical.choice.
- Engine models unchanged.

Findings worth keeping:
- WebKit refutes transform-over-inset on a box without its own layer (`Motion.wk_inset_lt_transform`).
- break-long-tasks raises total passes on both engines (`Tasks.cr_split_total`, `wk_split_total`).
- defer-to-scrollend adds one props (Cr) or commit (WK) pass (`Scroll.cr_defer_more_props`).
- Layout batching gives at most one pass only from a clean frame (`Style.batched_dirty_two`).
- Chromium composites non-blur filter and backdrop-filter but never blur (`Motion.cr_filter_thread`).

Open items (model terms, not started):
- Chromium will-change compositing reason and backing store;
- content-visibility skip and intrinsic size;
- font metrics and swap;
- a layout-shift score;
- scroll-state query and `:has()` invalidation (stand-ins today: a style-only change);
- timer and task queue; INP input delay.
- No checker was run on the docstrings: no agent-spawn tool in this session. The author checked them against the
  6-point checklist.

Conventions:
- `Basic.join`, `rep`, `offLe`: a frame relation "≤ off `comp`".
- Per-engine proofs use `cases` on the mode, layer and Bool fields, then `rfl` or `Nat.zero_lt_one`. `decide` fails
  with a free element id.
- Theorems over a generic `E` hold for both engines.

Read first: the note's table, then `lean/Fw/Guidance/Basic.lean`.
