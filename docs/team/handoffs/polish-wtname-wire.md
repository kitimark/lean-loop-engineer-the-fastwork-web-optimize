branch: worktree-wf_efb32ee2-da5-1
worktree: .claude/worktrees/wf_efb32ee2-da5-1
last commit: see git log (top: "polish-wtname-wire")
CI runs: none (accepted limit: no CI run)

# polish-wtname-wire

Done
- (1) Wire op `plan.wtName` {dir} -> {name|null} in lean/Fw/Wire/Plan.lean (`opWtName`, calls `Fw.Plan.Polish.wtName`). Nine golden rows in
  packages/contracts/golden/plan/polish.jsonl (valid absolute, trailing slash, space, ~, relative, `..`, empty, no .claude, deeper).
  The TS `wtName` in apps/runner/src/polish.ts is deleted; `fw polish plan` asks fwcore; polish.test.ts replays the goldens through fwcore.
- (2) Lean statement (end of lean/Fw/Wire/Plan.lean): `inWtAt_inWtAny`, `other_checkout_passes_name_only`, `inWtAt_below`.
  Answer: name uniqueness is not enough. The name-only filter accepts a same-named worktree of another checkout; wf_ id uniqueness is a
  generator property Lean cannot prove. The strays filter must pin the main checkout root (parent of git-common-dir): accept only
  `<main>/.claude/worktrees/<name>/...`. Not applied: build-review.js is under .claude/ (lead).
Open: lead's build-review.js edit should use the root-pinned test, not `includes('/.claude/worktrees/<name>/')`.
Read first: lean/Fw/Wire/Plan.lean (end), apps/runner/src/polish.ts plan branch.
