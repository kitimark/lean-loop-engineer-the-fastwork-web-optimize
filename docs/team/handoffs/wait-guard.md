# wait-guard handoff

State: branch worktree-agent-a2581c4b84b8f7e56. Lean `lean/Fw/Ops/Wait.lean` (theorems `wait_bounded`, `handback_no_open_bg`,
`bg_long_denied`, `clean_allowed`, `foreground_never_bgLong`, `deny_iff_check`), wire op `ops.wait` in `lean/Fw/Ops/Wire.lean`,
goldens `packages/contracts/golden/ops/ops.wait.jsonl` (25 cases, generated), hook `apps/runner/hooks/wait-guard.mjs`
(+ `.d.mts`), tests `apps/runner/test/wait-guard.test.ts`, doc `docs/team/tools/wait-guard.md`.

## Turn it on (lead only; I did not touch .claude/settings.json)
Add under `hooks.PreToolUse` a second entry (the hook ships in shadow mode: logs `WaitGuard` records, prints nothing):
`{ "matcher": "Bash", "hooks": [ { "type": "command", "command": "node apps/runner/hooks/wait-guard.mjs" } ] }`
(use the same command form/cwd as the existing `Agent` -> spawn-guard.mjs entry). To enforce later: `FW_WAIT_GUARD=enforce`
or `.fw-console/wait-guard.json` `{"mode":"enforce"}`; check the shadow log first (`verb` starts `deny:`) for false positives.

## Conventions
Lean decides, hook only moves JSON (same as spawn-guard; imports its `ask`/`fwcorePath`). Parse is approximate by design;
blind spots listed in the tool doc. `handbackOk`/`openBg` are proved but have no wire op yet.

## Open items
- Wire `handbackOk` to the Stop/SubagentStop hook (needs BG start/end events per agent; obs-signals has BG minus END).
- Shadow-log review, then flip to enforce. `sh -c '...'` strings are not parsed (a recursive parse would close that).
- Math view: new theorems are unsigned until math-reviewer signs them.

Read first: `lean/Fw/Ops/Wait.lean` header, then `docs/team/tools/wait-guard.md`.
