# Handoff jev-file-context-note

- Branch `worktree-wf_eab180aa-d3f-1`, worktree `.claude/worktrees/wf_eab180aa-d3f-1`; last commit: see `git log -1`.
- CI runs: none (research note, no measurement lane).
- Delivered: `research/notes/2026/10-2x-jev-file-context.md` (negative result: do not expand named files into the
  Jev state) and `scripts/jev-leak.mjs` (the scan every number in the note comes from).

## Verified
- Scan run once with Node 24.22.0:
  `node scripts/jev-leak.mjs --rows <dir with rows-d1.json, rows-d2.json> --clean results/jev-arms-clean`.
  It reads files from git at `ecdc0787` (D1) and `c31e0848` (D2), never the working tree; ~12 s.
- The three CONFIRMED refs re-checked with `git show`: `scripts/checkmap.mjs:2@ecdc0787`,
  `apps/runner/hooks/wait-guard.mjs:2@ecdc0787`, `docs/team/work-graph.json:12347@c31e0848`.
- Lean refs at `7e676da5`: Redact.lean:195 stateCap, :303-307 capState, Send.lean:9 dailyCap, :24 bodyCap.

## Open (follow-ups, outside the unit)
- D1-only ablation: designed, not run. `Fw.Oracle.Expand`: described, not written.
- The jev-replay note's "Limits" line pointing here (lead edit).

## Conventions
- The trial rows hold dataset text and stay out of git; the scan takes their directory as `--rows`.
- Counts depend on `PATH_RE` (`scripts/jev-leak.mjs:25`); change it and re-run before quoting new numbers.

## Read first
- The note, then `scripts/jev-leak.mjs`.
