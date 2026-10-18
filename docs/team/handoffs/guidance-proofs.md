# Handoff: guidance-proofs

State: branch `worktree-wf_9a58162f-174-2`; Lean in `lean/Fw/Guidance/` (6 modules, imported in `lean/Fw.lean`),
note `research/notes/2026/10-18-guidance-proofs.md`. Round 2 (final design round) relabelled cells only: no new
theorem, model term or mechanism.

Verified:
- 38 cells (19 "yes/partly" rules × Chromium, WebKit): 0 proved, 0 refuted, 29 conditional, 9 out-of-model (round 3: box-size cells conditional, label only).
- Label rule: decided by the theorem as stated. proved = every case the quote covers; conditional = named special case
  or premise (note says "encoding" when the premise is the choice of frames); refuted = counterexample to the quoted
  claim; out-of-model = no term for the claim.
- Round 2 changes: no-js-size-measurement conditional (write-read-write only); transform-over-inset conditional on both
  (per-frame JS writes, not `@keyframes`; `wk_inset_lt_transform` is a side finding); break-long-tasks and
  sticky.scroll-state out-of-model; split/defer pass counts are side notes.
- No sorry, no native_decide; engine models unchanged; `lean/scripts/check.sh` green at the last commit.

Open items (model terms, not started):
- a theorem for plain measure-then-write, and work theorems for `@keyframes` transform vs inset animations;
- Chromium will-change compositing reason and backing store; content-visibility skip and intrinsic size;
- font metrics and swap; a layout-shift score; scroll-state query; `:has()` invalidation;
- timer and task queue; task duration, pending input, INP input delay.

Conventions:
- `Basic.join`, `rep`, `offLe`: a frame relation "≤ off `comp`".
- Per-engine proofs use `cases` on the mode, layer and Bool fields, then `rfl` or `Nat.zero_lt_one`. `decide` fails
  with a free element id.
- Theorems over a generic `E` hold for both engines.

Read first: the note's table and legend, then `lean/Fw/Guidance/Basic.lean`.
