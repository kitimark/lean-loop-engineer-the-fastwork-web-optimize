# mem-gate-bypass handoff

State: round 2 research done on branch `worktree-wf_f48889d4-126-2`; round 1 was b49892f6, round 2 merges main
2edd65b1 (merge 1186e05e) and rewrites the note; the round-2 note commit is afb6bca1. No code changed.

Read first: `research/notes/2026/10-21-mem-gate-bypass.md` (22-row entry-point table with the sweep commands, burst
tables from samples, memory-gate section, lease kind, I1/I1-L/I2, round-1 findings answered with line numbers).

Verified:
- Gate coverage per entry point, CONFIRMED file:line at 2edd65b1, incl. pre-commit:13 -> checkmap.mjs:70,132 ->
  CheckMap.lean:225-226, `pnpm test` (package.json:9-10), site breakgen, gate-breakpoints generators, mutants, math-pending.
- Three bursts (i=27, 34, 38; 4.4-5.4 GiB Lean RSS), each one check.sh; i=23 is a land-wt/0 fwcore-build (1701 MiB).
- Per-burst VM counters; free 58-1809 MB, median 118; swap 71.8-73.5%; RSS/footprint 2.4-6.4x.
- Memory gate at the bursts unknown (INFERRED): threshold 43% free, readings 48/40/43%.

Open:
- Implement I1 + I1-L (`land` kind admitted at once, counts for others) and I2 width, Lean first.
- User edits: settings.json allowlist to `sh scripts/lake-slot.sh`; disable lean-lsp-mcp `lean_build`.
- sup-baseline: log footprint, memory_pressure free %, swap-outs, heavy acquire/wait/release spans.
- Swap gate reads swap in use (high all day, swap-outs flat): a swap-out-rate gate is a follow-up.

Conventions: sample source is scratch `node-resources/samples.jsonl` (uncommitted, 46 samples 17:01-17:16); analysis
scripts `mem-gate-bypass/r2*.py` in the session scratchpad. Peaks: footprint is the real cost, RSS only a ceiling.
