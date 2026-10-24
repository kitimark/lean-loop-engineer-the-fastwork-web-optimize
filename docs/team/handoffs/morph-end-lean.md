# morph-end-lean handoff

- Branch `worktree-wf_a57c56cc-7d7-1`, worktree `.claude/worktrees/wf_a57c56cc-7d7-1`; work merged with main at
  `b5e0f3b18`, this handoff is the next commit. CI runs: none (Lean only).
- Verified: `lake build Fw.Parts.MorphEnd Fw.Parts.MorphEndGolden` green; `lean/scripts/check.sh` green in the check
  slot; `#print axioms` on the main theorems shows propext, Classical.choice, Quot.sound only; golden `--check` ok;
  `fw plan lint` has no error for this task.
- Read first: `research/notes/2026/10-2x-morph-end-bricks.md` (theorems in plain words, cases, accepted limits), then
  `lean/Fw/Parts/MorphEnd.lean` (`step`, `Hooks`, `Brick.apply`, `all_combinations`).
- Design: one reducer `step (h : Hooks)`; each brick rewrites one hook (`target` A, `allow` B, `release` C), so the 8
  picks are `Cfg.hooks` and `order_free` holds by `Brick.apply` commuting. `Orig` restates N2 and `faithful_eq_orig`
  ties `base` to it.
- Golden: `packages/contracts/golden/parts/morph.end.jsonl` (const line + spring-back, wiggle, drag-back × 8 picks),
  from `lean/scripts/MorphEndGolden.lean`; integers are JSON ints, the tween value is `{"num","den"}`.

## Lead wiring (shared files)

- `lean/Fw.lean`: `import Fw.Parts.MorphEnd` and `import Fw.Parts.MorphEndGolden`.
- `lean/scripts/check.sh`:
  `  job "morph-end golden check" lake env lean --run scripts/MorphEndGolden.lean --check ../packages/contracts/golden/parts/morph.end.jsonl  # morph.end bricks A clamp, B flip, C release (Fw.Parts.MorphEnd)`

## Open

- `flipN` = 16 is a placeholder; morph-end-measure tunes it from the recorded passes.
- C stops `preventDefault` mid-drag; whether WebKit honours that mid-sequence is unchecked (INFERRED risk).
- The bricks cover the `createTweenDriver` path only; `morph.tween` waapi / scroll-lock / band drivers are a follow-up.
- Registry rows for the three parts and the TS bricks belong to morph-end-bricks (checked against this golden).
