branch: worktree-wf_efb32ee2-da5-1
worktree: .claude/worktrees/wf_efb32ee2-da5-1
last commit: see git log (top: "polish-wtname-wire")
CI runs: none (accepted limit: no CI run)

# polish-wtname-wire

Done
- (1) Wire op `plan.wtName` (takes dir, returns name or null) in lean/Fw/Wire/Plan.lean (`opWtName`, calls `Fw.Plan.Polish.wtName`). Nine golden rows in
  packages/contracts/golden/plan/polish.jsonl (valid absolute, trailing slash, space, ~, relative, `..`, empty, no .claude, deeper).
  The TS `wtName` in apps/runner/src/polish.ts is deleted; `fw polish plan` asks fwcore; polish.test.ts replays the goldens through fwcore.
- (2) Lean statement (end of lean/Fw/Wire/Plan.lean): `inWtAt_inWtAny`, `other_checkout_passes_name_only`, `inWtAt_below`.
  Name uniqueness is not enough: the name-only filter accepts a same-named worktree of another checkout, and wf_ id uniqueness is a
  generator property Lean cannot prove. The strays filter must pin the main checkout root (parent of git-common-dir): accept only
  `<main>/.claude/worktrees/<name>/...`. Not applied: build-review.js is under .claude/ (lead).
  Pinning the root is necessary, not sufficient: inWtAt reads raw segments, so the workflow must first resolve each edited path (path.resolve against the main checkout, then fs.realpathSync) and reject any path with a . or .. segment; <main>/.claude/worktrees/<name>/../../apps/x.ts passes inWtAt unresolved.
Open: lead's build-review.js edit should use the root-pinned test, not `includes('/.claude/worktrees/<name>/')`.
Read first: lean/Fw/Wire/Plan.lean (end), apps/runner/src/polish.ts plan branch.
