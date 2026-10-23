branch: worktree-wf_7d990bc5-d34-1
worktree: .claude/worktrees/wf_7d990bc5-d34-1 (under the repo root)
last commit: see `git log -1` on the branch (note + this handoff)
CI runs started by me: none (no setup-lean change was proposed that a run could prove). Logs read: 39965489939, 39966639416, 39955108083.

State: finding delivered in research/notes/2026/10-2x-ci-setup-lean-slow.md.
Verified (MEASURED from logs): setup-lean time follows the download rate of the same 1354 MB Lake cache blob (25 to 159 MB/s ->
88 s to 41 s); key, hit and blob size are identical on fast and slow legs; module building is the next step (`fwcore build`, 78-81
modules, ~90 s), not setup-lean. Land legs restore a stale main entry (ci/* saves are invisible to other branches).
Open: (1) prune step in lean.yml job lean before the end (find .lake-cache -type f -links 1 -delete), one lean.yml run to prove link
counts and size; (2) main entry freshness / trigger change (lead); (3) cache quota 9.48 of 10 GB.
Read first: the note.
