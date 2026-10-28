# timed-m0-webkit handoff
Branch worktree-wf_2db7bec6-7d6-1 (CI branch ci/timed-m0-webkit); worktree .claude/worktrees/wf_2db7bec6-7d6-1
Last commit: see git log (this file is committed with the first CI push).
CI runs: none finished yet (push 1 pending: current reader, no site edit).

State: forensics done. Run 40553185213 ran on ci/geom-veil-restore at 47f7fd747, which does not contain the reader fixes e56ef0507 / 59fd94946 (`git merge-base --is-ancestor e56ef0507 47f7fd747` exits 1). Its flip-cell.mjs had no panel-mount agreement, no scroll-settle and no recheck. So the 3 failures are harness (reader) faults already fixed in HEAD, not a WebKit rest difference.
Verified: per-cell JSON read (results/timed-m0-webkit/run/timed-wk.json), reader diff 47f7fd747..HEAD.
Open: one CI run at HEAD must show timed 24 of 24 on both engines; then the note 10-2x-timed-m0-webkit.md gets the run id.
Read first: research/notes/2026/10-2x-timed-m0-webkit.md, research/notes/2026/10-2x-flip-verify-auto.md (section "The cause of the two WebKit geom-timed m=0 failures").
