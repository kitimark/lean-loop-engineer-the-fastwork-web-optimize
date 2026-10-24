branch: worktree-wf_f9a6d967-63c-1
worktree: .claude/worktrees/wf_f9a6d967-63c-1
last commit: 33edec3d6 (round 2: dotted paths raw to Lean, realpathSync.native)
CI runs: none (accepted limit: no CI run)

# Polish strays follow-ups

Done
- (1) lean/Fw/Plan/Polish.lean `ownFact main name raw resolved` (+ `Own.unresolved`): resolved=false is never own
  (`ownFact_unresolved`, `_resolved`, `_unresolved_not_own`, `_own_iff`). Op `plan.inWt` takes optional `resolved` (default true).
  TS `resolveFacts` (apps/runner/src/polish.ts) only gathers facts: realpath of the longest existing ancestor + the rest;
  no resolvable ancestor sends resolved=false. Goldens `inWtFact: ...` in packages/contracts/golden/plan/polish.jsonl; TS tests
  in apps/runner/test/polish.test.ts (symlinked parent, no ancestor).
- (2) `nested_checkout_inside` carries `main ≠ main ++ wtSegs name ++ ["sub"]`.
- (3) fw-main.ts usage line lists `strays`.

Open: build-review.js wiring stays the lead's (text in polish-strays-sound.md).
Read first: Polish.lean ownFact, polish.ts resolveFacts.
