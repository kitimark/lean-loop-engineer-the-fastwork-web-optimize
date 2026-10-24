# classpos-followups-2 handoff

- Branch `worktree-wf_aeb2820e-ba8-1`, worktree `.claude/worktrees/wf_aeb2820e-ba8-1`. Round 2 code commit `4336d7f1a`,
  main merged after it (`c19a37d51`). Round 1 code `4e2b10251`.
- CI runs: none (accepted limit).
- Round 2 verified: `ClassPosGolden --check` (138 lines), classpos node test 146 pass, `part-footprint.mjs --check` exit 0.
  Check, package tests and dry land: see the report.

## Round 2 changes
- Finding 1: `union()` in `part-footprint.mjs:87` takes the class branch before the two unknown early returns, so a
  class union with an unknown side keeps the unknown side (Lean `union_unknown_open`, `unknown_union_open`).
  `classListOf` (`part-footprint.mjs:791`) is the production classList path (valueOf, classValue, classListReport);
  the test `classList.add(cond ? css.a : x) keeps the unknown side open` runs it on both branch orders.
- Finding 2: `Strength.weak` sits between `.dynamic` and `.spread`; `strength` maps a weak match to `.weak` unless
  spread; `pick` tiers literal, dynamic, weak, rest (`pick_literal`, `pick_dynamic`, `pick_weak_tier`, `pick_rest`).
- MEASURED: the regenerated footprint is byte-identical (accesses 1890, findings 93, `chainPairs_code_length` 298).
  The union fix fires 99 times, but no classList call in the site receives the resulting value; JSX className goes
  through `collectClassTokens`. No selector has dynamic and weak candidates without a literal one, so the new tier
  changes no owner. The 127 weak rows the reviewer counted come from selectors whose only candidates are weak ones
  (`frameCls[k]`, component className props).

## Follow-ups
- Findings 3-6 of round 1: a boolean literal left of `&&`, module-hole selectors vs `css[k]` elements, runtime
  `setClass` writes as open elements, the check replay.
- `frameCls[k]` and component `className` props stay lost and open; imports stay open.

## Read first
`lean/Fw/Parts/ClassPos.lean`, then `apps/site/scripts/part-footprint.classpos.test.mjs`. Regen chain: `part-footprint.mjs
--write`, `ContractsGolden --rows` into `FootprintRows.lean`, `--diff` into `footprint-diff.gen.json`, retable `Bridge.lean`.
