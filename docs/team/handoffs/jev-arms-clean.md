# Handoff: jev-arms-clean

- Branch `worktree-wf_88bc7158-4e4-1`, worktree `.claude/worktrees/wf_88bc7158-4e4-1`; last commit: `git log -1`
  (note and handoff; Sonnet arm 8cbc0616, Haiku arm 7caffdef, probe 9223c4da).
- CI runs: none (the task makes local `claude -p` calls only).
- Done: probe PASS for haiku and sonnet (`results/jev-arms-clean/probe.json`); clean rows for both models on D1 and
  D2 (412 calls, 0 failed); scores in `results/jev-arms-clean/d1.json`, `d2.json`; old-vs-clean table and cost in
  `table.md` / `table.json`; note `research/notes/2026/10-2x-jev-arms-clean.md`.
- Verified: `node --test scripts/jev-arms-clean.test.mjs` 11 pass; results grep clean of home paths, emails and
  session ids; prompts byte-identical to the first run's.
- Open: `answerOf`, `probeVerdict`, `costOf` are TS stand-ins (no Lean spec); the test file runs in no CI workflow;
  the replay note's arm section still cites first-run numbers (plan-editor change, see the note's last section).
- Rebuild the table: `node scripts/jev-arms-clean.mjs table --out results/jev-arms-clean --old
  results/jev-arms-clean/first-run`. Runs resume: rows in `<set>-<model>.rows.jsonl` are skipped.
- Conventions: cwd per call = fresh `mkdtemp` under `<scratchpad>/jev-arms-clean/cwd/`; child env allowlist
  (`ENV_KEEP`); never `fw oracle send`.
- Read first: the note, then `scripts/jev-arms-clean.mjs`.
