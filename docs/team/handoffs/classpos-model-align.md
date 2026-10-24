branch: worktree-wf_e1ce08cb-1bf-1
worktree: .claude/worktrees/wf_e1ce08cb-1bf-1
last commit: see git log (work 291a55e3b; goldenText computed on call c75c44c8e, for the init-cost lint)
CI runs: none (accepted limit: no CI run); check.sh, site tests, ci-paths and land-inputs tests green locally

State: one class-position rule in Lean, mirrored by the extractor branch for branch.
- Rule: lean/Fw/Parts/ClassPos.lean `go` (tokens + string pieces), `wordToks` (glue), `methodToks` (join/filter),
  `helpers`, `isSep`, `writes`/`findings` (what a className site emits). Theorems: one per branch (`call_helper`,
  `call_other`, `join_ok`, `join_glued`, `filter_irrelevant`, `method_other`, `other_lost`, `spread_lost`,
  `glued_reported`, `chars_kept`, `lost_open`, `call_names`, `join_names`, ...).
- Golden: packages/contracts/golden/parts/footprint.classpos.jsonl, head row = helpers + separators, then one row per
  form (classes, modules, writes, findings). Generator lean/scripts/ClassPosGolden.lean (run after `lake build Fw.Parts.ClassPos`).
- JS: apps/site/scripts/part-footprint.mjs `collectClassTokens` / `classWords` / `classReport`; collectElements uses the
  same rule (old `literalClassTokens` removed, output unchanged). Test: part-footprint.classpos.test.mjs.
- Report kinds: `lost` (unmodelled call, method, bad join separator, spread, other form) -> finding `unmodelled-class`
  + one `setClass ?` access; `glued` (a word of text and holes, e.g. `'btn-' + size`) -> finding `glued-class`, its
  literal parts stay classes (no `?`, so no footprint widening).

Footprint change: one finding added, nav/index.tsx:133 `glued-class *is-hero-pill` (`${boxClass}is-hero-pill`);
footprint-diff findings 75 -> 76. No access row changed. A `?` for glue was tried and widened 15 diff rows; rejected.

Open / follow-ups: computed CSS-module keys `v[\`dot${..}\`]` resolve to `#null` in valueOf (platform/Visuals.tsx:446-448);
classList.add/contains go through valueOf, not this rule; identifiers in className are not resolved.
