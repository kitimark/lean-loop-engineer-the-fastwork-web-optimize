# mem-gate-bypass handoff

State: research done, note committed on branch `worktree-wf_f48889d4-126-2` (base bea13736). No code changed.

Read first: `research/notes/2026/10-21-mem-gate-bypass.md` (entry-point table, burst mechanism, lease kind, interim fix).

Verified:
- Gate coverage per Lean entry point, CONFIRMED file:line at bea13736 (only check.sh takes the heavy lock).
- Bursts are single check.sh runs admitted at n=0 (Heavy.lean:80) at width 8, beside ungated Lean work (sampler i=27, 34, 38).
- RSS overstates per-job footprint 2.4-6.9x; one `/usr/bin/time -l` run each for HeavyGolden, InitCostLint import, `lean -o`.
- heavy-lock.mjs:80-84 memory gate reads memory_pressure available %, not vm_stat free; only the swap gate bites.
- Run counts today from `.fw-console/timings.jsonl` and transcript Bash calls (lower bound).

Open:
- Implement I1 (holder registry for fwcore-build.sh, land axiom lint, lake-slot.sh) and I2 (`Fw.Sched.Heavy.width`, footprint cost replacing jobMB 5000), Lean first.
- User edits: settings.json allowlist from bare `lake *` to `sh scripts/lake-slot.sh`; disable lean-lsp-mcp `lean_build`.
- sup-baseline: log footprint (top or proc_pid_rusage) and heavy acquire/release; record memorystatus_level at bursts.
- Footprint not measured for the axiom `--stdin` check and `lake test`.

Conventions: peaks are MEASURED footprint, RSS only as a ceiling; the sampler and design scratch are uncommitted, cited by name.
