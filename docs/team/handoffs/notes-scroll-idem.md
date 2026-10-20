# notes-scroll-idem handoff

## State
- Branch `worktree-wf_887f1e36-223-1`. CI ran at 9ec81757 (`ci/notes-scroll-idem`). Later commits add the Lean
  theorem `move_layout_stale`, the regenerated preset decisions, the note, the results and this handoff.
- Variant `pain.notes:visible-idem` (on `visible`) skips the covered-frame clear and commit when `Idem.skips` holds:
  no extra notes and no note move since the last commit (`dirty` flag in `driver.ts`).

## Verified
- Lean `Fw.Parts.PainNotesOpt.Idem`: `run_eq`, `scroll_dom_eq` (E), `commits_le`, `commits_lt`, `naive_not_E`,
  `move_layout_stale`. `goldenCommits` rows in `pain.notes.jsonl` are replayed by `logic.test.ts` through the real driver.
- Chromium counts (3 runs per arm vs `v2-proved`): FunctionCall -733 on swipe-v1, -720 to -724 on swipe-touch-v1;
  3 calls per covered frame. Paint, Layout and Raster stay within noise.
- webkit-sim: both arms green; FunctionCall is quarantined there, so no delta is claimed.
- Breakpoint gate: `pain.notes` passes everywhere. The commission margin-inline flake was red in all 3 attempts.
- check.sh, site test and typecheck, ci-paths and runner land-inputs tests are green.

## Open
- Preset inclusion (lead).
- `move_layout_stale`: check the original Svelte for the same behaviour.
- Identify the 3 calls per React commit.

## Conventions
- Writes outside the listed files: `index.tsx` line 99 (variant wiring), `logic.test.ts`, and the generated
  `pain.notes.jsonl` and `v2-proved.decisions.jsonl` (regenerated from Lean, not hand-edited).

## Read first
- `research/notes/2026/10-20-notes-scroll-idem.md`, `results/notes-scroll-idem/runs.json`.
