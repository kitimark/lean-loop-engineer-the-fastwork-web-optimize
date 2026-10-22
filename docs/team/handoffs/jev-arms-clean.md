# Handoff: jev-arms-clean

- Branch `worktree-wf_88bc7158-4e4-1`, worktree `.claude/worktrees/wf_88bc7158-4e4-1`; last commit: `git log -1`
  (Haiku arm commit; probe commit 9223c4da).
- CI runs: none (the task makes local `claude -p` calls only).
- Verified: probe PASS for haiku and sonnet (`results/jev-arms-clean/probe.json`): init tools [] and MCP [];
  minimal call 629/608 prompt tokens (CLAUDE.md is about 1600, MEMORY.md about 2100); introspection quotes only 3
  harness blocks (SDK line + our system prompt, Environment, userEmail reminder). Arm prompts from
  `fw oracle arm-input` are byte-identical to the first run's.
- Haiku arm done: d1 116/116 rows (right 64/116, first run 69), d2 90/90 (right 43/90, first run 38); 0 failed calls.
  Scores in `results/jev-arms-clean/d1.json`, `d2.json` (jev re-scored from the answer log, no sends).
- Open: sonnet d1 (running in background when this was written), sonnet d2; scoring; `table` subcommand
  (`node scripts/jev-arms-clean.mjs table --out results/jev-arms-clean --old results/jev-arms-clean/first-run`);
  note `research/notes/2026/10-2x-jev-arms-clean.md`; merge main; dry land; review ready.
- Runs resume: rows already in `results/jev-arms-clean/<set>-<model>.rows.jsonl` are skipped; a half-written run
  leaves its `runs.jsonl` line out, so wall time then needs the calls log.
- Conventions: cwd per call = fresh `mkdtemp` under `<scratchpad>/jev-arms-clean/cwd/`; child env allowlist
  (`ENV_KEEP`); never `fw oracle send`. Results carry no home path, email or session id (grep before commit).
- Read first: `scripts/jev-arms-clean.mjs`, `results/jev-arms-clean/probe.json`.
