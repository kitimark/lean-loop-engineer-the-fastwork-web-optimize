# mem-gate-bypass handoff

State: round 3 (final design round) on branch `worktree-wf_f48889d4-126-2`; round 1 b49892f6, round 2 8d005700,
round 3 merges main 5c188cca (merge fe80fd7f); the round-3 commit is named in the lead report. No code changed.

Read first: `research/notes/2026/10-21-mem-gate-bypass.md`, then `research/notes/2026/mem-gate-bypass/numbers.md`
(every sample-derived number; rules in its header) and `reduce.mjs` (the generator).

Verified:
- `node research/notes/2026/mem-gate-bypass/reduce.mjs <scratch samples.jsonl> | diff - .../numbers.md` is empty.
- Gate coverage per entry point, CONFIRMED file:line at 2edd65b1 (22 rows, sweep commands in the note).
- Three bursts (i=27, 34, 38) summed 4.4-5.4 GiB of Lean RSS but grew compressor+wired by 0.7-1.1 GB; each one
  check.sh; i=23 is a land-wt/0 fwcore-build (1701 MiB tree). Values: numbers.md, Bursts and VM counters.
- Row 21: serena-lean pid 92446 is a child of the live lead session pid 92347, not reapable (Reap.lean:5-14, :128).
- Memory gate at the bursts unknown (INFERRED): threshold 43% free, readings 48/40/43%.

Open:
- Implement I1 + I1-L (`land` kind before the rank branch, Heavy.lean:79; bound cap + 1, two while swap high;
  assumes one land at a time) and I2 width, Lean first (fw-sup stage 1b).
- Correct `jobMB` 5000 (Heavy.lean:26-28, :34) from footprint, not summed RSS.
- User edits: settings.json allowlist to `sh scripts/lake-slot.sh`; disable lean-lsp-mcp `lean_build`.
- sup-baseline: log footprint, memory_pressure free %, swap-outs, heavy acquire/wait/release spans.

Conventions: samples.jsonl stays in scratch `node-resources/` (home paths, session ids); never type a sample-derived
number by hand: change reduce.mjs, regenerate numbers.md, copy. Footprint is the real cost, RSS only a ceiling.
