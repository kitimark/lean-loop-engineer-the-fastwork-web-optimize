# findings-ledger-1020 handoff

State: branch `worktree-wf_3b439646-714-1`, rows at cd51f386 on top of 84a662d4; the lead added this handoff and set
row `premise.cv.margin-typed-om` (n 31) to status `proved` (the builder wrote a new word, `holds`).

Verified (builder and review): findings 48 -> 64 rows, notes 38 -> 43 rows; the old rows are byte-identical; the file
round-trips as `JSON.stringify(d, null, 1)`; all cited Lean names exist on main; every run id and number traces to a
note, handoff or results/ file; preset `--check` says v2-proved is up to date (9 flags); apps/runner `pnpm test`
1437/1437 (after `lake build fwcore`); ci-paths 41/41.

Conventions:
- New findings rows carry an `id` and no `flag`, so the preset generator does not pick them up. Adding a `flag` is a
  preset decision (lead).
- Notes rows copy their `entry` text from the existing candidate exactly.
- Tooling rows use parts `tooling.*` (n 35-38).
- The next catch-up scans notes and handoffs changed since this branch's land commit.
- A fresh worktree needs `lake build fwcore` before the runner tests.

Open:
- Rows for fwcore-query-speed and fwcore-replay-speed (tooling, Lean equality proofs, local timings only) and a
  premise row for preview-original-gate.
- Still OPEN inside rows: cmr-strut-asym, morph-nav-scope, the waapi touch row, countdown touch frame 499, the
  CircleCI repeat samples, the breakpoints absent-key golden.
- 2026-10-20 user report: the all-flags client-rendered search froze the hero and broke the nav logo (investigations
  hero-scroll-bug, nav-logo-bug); their rows go in when those close.

Read first: `research/notes/2026/10-21-findings-ledger-1020.md`.
