# park-attrib handoff
Branch: worktree-wf_e8ba3c22-914-1 (CI branch ci/park-attrib). Worktree: .claude/worktrees/wf_e8ba3c22-914-1 (under the main checkout).
Last commit: see `git log -1`; the gate ran on 72d0bfd91 (workflow edit since reverted to main's).

## CI runs
- 41078004214 breakpoint-gate push (72d0bfd91, ?fw=engine.scroll:unthrottle,hero.exit:threaded): complete, merge red. Chromium pass (7056/7049/0 fail/7 excused);
  WebKit FAIL 147 readings, hero.orbit 1060 + hero.deck 164 card translate, table sha e524c0ee... identical to the park pair run 41054732597.
- Second gate push: not used (the plan's second run applies only when WebKit passes). 1 of 2 pushes spent.

## Verified
- Lean rule lean/Fw/Ops/Attrib.lean (same commit, one differing part, else notAttributable), goldens packages/contracts/golden/ops/attrib.jsonl
  (generator lean/Fw/Ops/AttribGolden.lean), check.sh job "attrib golden check", lean.yml trigger row + triggers.jsonl.
- Result: the failure is present without the park flags; park not the cause; threaded the INFERRED carrier; rule says notAttributable (no same-commit one-part pair).
- Note research/notes/2026/10-31-park-attrib.md; ledger row hero.exit.threaded-park (visual, lesson, next, evidence, missingWhy) updated.
## Open
- Same-commit attribution needs two lead dispatches on one ref at one commit, e.g. --ref main (fw empty, fw=hero.exit:threaded). The remote ci/park-attrib holds 72d0bfd91 (workflow edit); the final commit was refused by the pre-push lane check.
- v2-proved/shipped hold hero.exit:threaded; no passing breakpoint-gate with it is on record (39774976109, 41078004214 fail WebKit).
## Conventions
- BSD sed needs `sed -i ''`; pnpm install --offline --frozen-lockfile before pnpm fw in a fresh worktree; lean goldens run from lean/.
