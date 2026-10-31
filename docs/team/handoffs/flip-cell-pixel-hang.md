# Handoff: flip-cell-pixel-hang (finisher round 2, graph r614)

Branch: worktree branch `worktree-wf_400db961-014-1`, CI branch `ci/flip-cell-pixel-hang`.
Worktree: .claude/worktrees/wf_400db961-014-1. Last work commit: ad74ddb22 (round 2 fixes); CI push commit follows it.
CI runs: round 1 run 41231318047 (d6dcdce9a, both engines green, 0 faults). Round 2 run: pending (id below once pushed).

Round 2 (only the two refused items plus cheap follow-ups):
- Fault = stall only: Lean `errKind`, `ErrKind.attempt` and theorems `err_limit_is_stall`, `err_timeout_is_stall`, `err_other_is_defect`, `err_stall_is_fault`, `err_defect_not_retried`, `err_defect_first_fails` in `lean/Fw/Parts/MorphGeomReady.lean`; golden `verifyErr` rows in `packages/contracts/golden/morph-geom-timed.jsonl`; TS `errKind` and the rethrow at the top of the `takeCell` catch in `packages/gate-breakpoints/src/bounded.mjs`; tests in `test/bounded.test.mjs` (golden replay, TypeError rejects after 1 attempt with 0 onFault, TimeoutError retried).
- Job `flip-cell` `timeout-minutes: 90` in `.github/workflows/breakpoint-gate.yml`; note says which limit fires first.
- Fault count printed in the `flip cell ... pass` and `look ...` summary lines.
- Note corrected (4 dispatched runs ran both engines) and open items added: `research/notes/2026/11-01-flip-cell-pixel-hang.md`.

Verified locally (not a result): lean check.sh rc 0; gate-breakpoints 859 pass; premise-tests 20 pass; ci-paths 56 pass; runner 3749 pass.

Open: Flip verify/repeats/mutation page-call bounds (follow-up); more first-attempt WebKit runs; flag-page screenshot cost (record base and flag shotMs); look.mjs per-cell loop is a TS stand-in.
Read first: the note, `bounded.mjs`, `MorphGeomReady.lean`.
