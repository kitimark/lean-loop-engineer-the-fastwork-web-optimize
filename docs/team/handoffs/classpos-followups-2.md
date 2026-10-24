# classpos-followups-2 handoff

- Branch `worktree-wf_aeb2820e-ba8-1`, worktree `.claude/worktrees/wf_aeb2820e-ba8-1`, last code commit `4e2b10251`
  (report `4b5fec84b`, main merged after).
- CI runs: none (accepted limit).
- Verified: `lean/scripts/check.sh` green (axioms, init-cost, all goldens); `@fw/site` test 6559 vitest + 158 node pass,
  typecheck ok; `scripts/ci-paths.test.mjs` 56 pass; runner `land-inputs.test.ts` 56 pass.
- Open: `FootprintRows.lean` and `footprint-diff.gen.json` are regenerated outputs outside the named writes.

## What changed
- `Fw.Parts.ClassPos`: same-module consts resolve to their initializer (`E.const`); booleans, numbers ("number"),
  `null`/`undefined` per context (`Ctx` attr/text/list/join/elem); `&&` left side reported unless a test; list helpers
  (clsx, classNames, classnames) vs join helpers (cx, cls); `V.alt` keeps every union value; `assignWrites` gives
  `setClass *` only when open; `modLost` tokens (computed CSS-module key) open the site but not the element
  (`elemOpen`); `classMatch`/`strength`/`pick` decide weak matches against open elements.
- `part-footprint.mjs` mirrors these (`collectClassTokens(expr, env, ctx)`, `classEnv`, `classAssign`, `classUnion`,
  `isOpenElement`, `classMatch`, `classStrength`, `pickOwners`); golden `footprint.classpos.jsonl` 136 lines.
- Footprint: accesses 1734 to 1890, findings 106 to 93; `.pain`, `.hero-track`, `.start-selling-platform` now weak
  matches on open elements of hero.accent, nav, people.deck (`dynamic-match`). `chainPairs_code_length` 287 to 298.

## Follow-ups
- `frameCls[k]` (hero.accent:115) and component `className` props (people.deck icons, hero.countdown) stay lost and
  open; resolving them removes most new weak owners.
- A cond inside a template is one opaque hole, so nav:133 reports glued `*is-hero-pill` and `***`.
- `str ∪ unknown` in `valueOf` still drops the unknown side; imports stay open.

## Read first
`lean/Fw/Parts/ClassPos.lean`, then `apps/site/scripts/part-footprint.classpos.test.mjs`. Regen chain: `part-footprint.mjs
--write`, `ContractsGolden --rows` into `FootprintRows.lean`, `--diff` into `footprint-diff.gen.json`, retable `Bridge.lean`.
