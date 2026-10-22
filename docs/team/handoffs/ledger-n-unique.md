# ledger-n-unique handoff
Branch: worktree-wf_5c5931a4-08f-1. Worktree: .claude/worktrees/wf_5c5931a4-08f-1. No CI runs pushed (local-only task).

State: nav.clip-box (landed later: 209ace6ee 04:12 vs 685dc82a9 04:05 +0700) renumbered 48 -> 52 in research/findings/ledger.json.
Rule: candidate rows (id + candidate text) have pairwise distinct n from n >= 26 (floor); legacy ids at n 6, 9, 12 share
their parent's n and stay allowed (accepted limit). No Lean model of the findings ledger rows' n existed
(Fw.Ops.LedgerMerge is the merge model; Console.Compose.LRow has no n), so a new small module was added.
- Lean: lean/Fw/Console/LedgerUnique.lean (bad, ok, ok_iff, exempt_below_floor, dup_refused, append_fresh); golden
  packages/contracts/golden/console/ledger-unique.jsonl (regenerate: cd lean && lake test -- --write-ledger-unique-golden).
- TS stand-in (marked for Lean replacement): apps/console-api/src/ledger-unique.ts, tested against the golden and the real
  ledger in apps/console-api/test/ledger-unique.test.ts. Runs in the apps/console-api land check; PACKAGE_EXTRA_READS
  in apps/runner/src/land.ts lists research/findings/ledger.json for it.
Verified: lean check.sh green, console-api tests 780 pass, runner tests 2831 pass.
Open: the stand-in is not run by fwcore; the second land of two parallel rows fails the console-api check and renumbers after merging main.
