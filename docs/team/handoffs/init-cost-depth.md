# init-cost-depth handoff

- Branch: worktree-wf_77b610a8-3fd-1; worktree: .claude/worktrees/wf_77b610a8-3fd-1
- Last commit: 9525f69ac (check.sh green there, main merged); this handoff commit follows it
- CI runs: none (accepted limit: the next lean run on any ci/* branch after the land is the live check)

## State
- Cause CONFIRMED: the scan's one `initCostRows` list literal compiles to `5N+1` lets; LCNF simp recurses per let
  (Simp/Main.lean:218,258@eb6cafb) under `max 8192 maxRecDepth` (LCNF/Main.lean:122@eb6cafb). MEASURED boundary:
  1637 pass, 1638 fail (main had 1636).
- Fix: `addListTree` in lean/Fw/Lint/InitCostScan.lean builds each list from constants of at most `fanOut = 256`
  elements (leaves, then `List.flatten` nodes). Lemmas `chunks_*`, `flatten_chunks`, `length_le_of_mem_chunks`,
  `length_chunks_lt`.
- Regression: check.sh job `init cost lint scale` lints lean/scripts/init-cost-cases/Many.lean (8192 constants).
- Times and details: research/notes/2026/10-2x-init-cost-depth.md.

## Verified
- check.sh green at 9525f69ac; real lint 1636 constants, 7-9 s (same as before); scale job 10 s, fails on the old scanner.
- Dry land: VERDICT scope (the three writes under Open are not in the graph row); with --allow for them: VERDICT dry.

## Open
- Writes outside the graph's list: lean/Fw/Lint/InitCostScan.lean, lean/scripts/check.sh,
  lean/scripts/init-cost-cases/Many.lean. lean/scripts/InitCostLint.lean is unchanged.
- Follow-up: grow Many.lean when fwcore passes 2048 start-time constants (keeps 4x).

## Read first
- research/notes/2026/10-2x-init-cost-depth.md, then `addListTree` in lean/Fw/Lint/InitCostScan.lean.
