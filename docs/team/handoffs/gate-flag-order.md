# gate-flag-order handoff

- Branch `worktree-wf_63795c34-543-1`, worktree `.claude/worktrees/wf_63795c34-543-1`, CI branch `ci/gate-flag-order`.
- Last commit pushed to CI: 329c0e92e (main merged). Later commits only add this file.
- CI runs:
  - lean push 40103195750: success.
  - breakpoint-gate dispatch 40103202517 (`--fw morph.countdown:strip,hero.countdown:strip`, both engines): success -> pass (smoke found the page; before the fix the same set failed smoke in runs 40081933958 and 40089874311).
    Both typed orders give the same dispatch input `fw=hero.countdown:strip,morph.countdown:strip` (`fw run --gate --dry`).

## Verified
- `lean/scripts/check.sh` green at the first code commit (FlagKey, FlagKeyGolden, Store.sortFlags).
- Tests green: site, console-api (builds fixture moved to the canonical key), gate-breakpoints, measure-webkit,
  measure-chromium, measure-wktr, visual-diff, contracts, runner `land-inputs`, `scripts/ci-paths.test.mjs`.

## Design
- Key = distinct flags ordered by part, then variant, joined by commas (`Fw.Wire.FlagKey.canon`). Theorems:
  `canon_eq_of_same_set`, `canon_roundtrip` (`mem_canon`), `exactly_one_page`, `enumerated_one_page`.
- Golden `packages/contracts/golden/wire/flag-key.jsonl` (guard in `lean/Fw/Wire/FlagKeyGolden.lean`, outside the fwcore cone
  so `scripts/ci-paths.mjs` sees no golden in a cone). TS twin `packages/contracts/src/flag-key.mjs` (`keyOf`, `canonSearch`),
  replayed by `apps/site/test/prerender-keys.test.ts`.
- `entry-server.tsx` stores every page under `canonSearch(search)`; every `configs.json` lookup wraps its search in `canonSearch`.

## Open
- TS stand-in: `canonSearch` (URL rewriting) is glue, checked by tests, not Lean. The comma join/split is not proved.
- Old artifacts keyed by author order stay as they are.

## Read first
`lean/Fw/Wire/FlagKey.lean`, then `packages/contracts/src/flag-key.mjs`.
