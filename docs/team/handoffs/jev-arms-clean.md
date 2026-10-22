# Handoff: jev-arms-clean

- Branch `worktree-wf_88bc7158-4e4-1`, worktree `.claude/worktrees/wf_88bc7158-4e4-1`; last commit: see `git log -1` (probe commit).
- CI runs: none (the task makes local `claude -p` calls only).
- Verified: probe PASS for haiku and sonnet (`results/jev-arms-clean/probe.json`): init tools [] and MCP [];
  minimal call 629/608 prompt tokens (CLAUDE.md is about 1600, MEMORY.md about 2100); introspection quotes only 3
  harness blocks (SDK system line + our system prompt, Environment, userEmail reminder). Arm prompts from
  `fw oracle arm-input` are byte-identical to the first run's (`cmp` on d1/d2-prompts.jsonl).
- Open: arms haiku d1/d2, sonnet d1/d2 (`node scripts/jev-arms-clean.mjs run ...`, resumable: rows already in
  `results/jev-arms-clean/<set>-<model>.rows.jsonl` are skipped); scoring with `pnpm fw oracle score --set <s> --arm
  <m> --answers results/jev-arms-clean/<s>-<m>.answers.jsonl --out results/jev-arms-clean/<s>.json`; note
  `research/notes/2026/10-2x-jev-arms-clean.md`; dry land; review ready.
- Conventions: cwd per call = fresh `mkdtemp` under `<scratchpad>/jev-arms-clean/cwd/`; child env allowlist
  (`ENV_KEEP`); never `fw oracle send`. Results carry no home path, email or session id (grep before commit).
- Read first: `scripts/jev-arms-clean.mjs`, `results/jev-arms-clean/probe.json`.
