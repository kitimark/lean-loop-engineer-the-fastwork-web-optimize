# Handoff: macos-minutes-note (branch worktree-wf_9e6e7c91-9ad-1)

State: note + data + generator committed (see `git log --oneline main..HEAD`). No Lean, no package code touched.
Read first: research/notes/2026/10-21-macos-minutes.md (Answer, then section 4 plan and Accepted limits).

Files
- research/notes/2026/10-21-macos-minutes.md: the note; its 11 tables are pasted output of the generator.
- research/notes/2026/macos-minutes/tables.mjs: prints every table; `--check` exits 1 unless each block is verbatim in
  the note. Run from the repo root: `node research/notes/2026/macos-minutes/tables.mjs [--check]` (Node 24.22.0).
- jobs.json (94 macOS jobs, steps, waits; from the measure job's telemetry rows + gh run view), circleci.json
  (Insights runs + per-job totals), facts.json (hand-entered: loss classes, series runs, teardown seconds, plan, saved).
  Copies of uncommitted scratch data; no paths, actors or session ids.

Verified
- tables.mjs --check: ok (11 tables). ci-paths 54/54, apps/runner land-inputs 55/55.
- Check numbers reproduced: 914.0 dispatch (82 %), 588.6 / 325.4, 31 of 33 all widths, lost split 55.0 / 30.73 /
  57.3 / 42.0, peak 6 for 2.3 min, wait share 85 %, overlap 6.4, credits 5,559 / 24,441 left.
- Rounding: exact-second sums differ from the check's rounded-minute sums for class b (30.73 vs 30.8), the series
  (273.55 vs 273.5) and the series' wait (405.0 vs 405.3); stated in the note.

Open
- premise-tests credits 724 (run level) vs 71 (summary): unresolved.
- 6-vs-5 macOS concurrency peak: open under pool-fallback.
- tables.mjs is a JS stand-in (no decision logic).

Conventions: to change a table, edit the JSON or the generator, regenerate, paste the block, run --check.
No write outside the task's graph writes; work-graph.json untouched.
