# faded-pause-entry handoff

Branch `worktree-wf_debe029b-131-1` (CI branch `ci/faded-pause-entry`), worktree `.claude/worktrees/wf_debe029b-131-1`.
Last commit: 80d9c0b3c (push 1 of 2).
CI runs: 40900090514 trajectory-probe (fw=platform:faded-pause engines=both debug=nav-transition): running; 40900090425 lean: running.

Verified (Lean, LSP clean): lean/Fw/Parts/PlatformFadedPause.lean adds resume_phase (run_inv, step_inv), settled_skipped,
restore_skips, invisible_iff, escape_shows, writer_or, writer_order_free, setFaded_idem, setActive_idem, setFaded_writes.
Gate facts: Gen's gate is the trajectory cells (V2Proved.tcell); breakpoint-gate run 40287895072 is not a trajectory run
(no trajectory artifacts), and a breakpoint-gate push runs the faithful page (fw input empty), so only a dispatch can gate the flag.

Open: record 40900090514 with Gen.record, link the theorems (Gen linkTable + fadedRowNames), ledger row and note, Gen.run,
note research/notes/2026/10-2x-faded-pause-entry.md, check.sh and tests through fw slot, dry land, review ready.

Conventions: Gen.record / Gen.run only (scratch scripts under the scratchpad, `lake env lean <file>` from `lean/`).
Read first: research/notes/2026/10-2x-platform-faded-pause.md, research/notes/2026/10-2x-end-wktr-flip.md.
