# slot-main-code handoff

State: branch worktree-wf_d6948b7f-59c-1.
- `apps/runner/src/slot-resolve.ts`: `mainCheckout`, `resolveSlotMain`, `slotMainPath` (main's slot-main.ts, local fallback).
- `apps/runner/src/fw.ts` and `scripts/slot-self.mjs` import slot-main.ts through it; Node pin guard and the Monitor line unchanged.
- Test `apps/runner/test/slot-resolve.test.ts` (pure table + fixture repo with a worktree). Docs: `docs/team/tools/slot.md` last section; incident `inc-slot-branch-code`.
- Limits: a waiting run keeps its loaded code; no state.json schema change, so main's code must read older callers' writes.
- Read first: slot-resolve.ts, then fw.ts lines 5-13.
