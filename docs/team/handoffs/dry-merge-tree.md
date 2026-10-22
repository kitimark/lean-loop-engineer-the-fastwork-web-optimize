# dry-merge-tree handoff

- Branch: worktree-wf_12f1146e-520-1; worktree: .claude/worktrees/wf_12f1146e-520-1
- Last code commit: see `git log -1` on the branch (first: e37aa8b2). CI runs: none (no CI lane needed; local check.sh + runner tests).
- git found: 2.53.0 (merge-tree --write-tree needs >= 2.38).

## State
- Lean `Fw.Console.LandDry`: `Base` (contains | clean | conflict), `Base.of behind mergeClean`; `dryKind w base`
  (empty first, then a conflicted base refuses `conflict`, else the old stages). Theorems: `never_stale`,
  `clean_never_stale`, `conflict_refuses`, `conflict_not_dry`, `conflict_land_refuses`, `clean_is_contains`;
  `dry_refusal_is_land_refusal` / `dry_iff_land_pass` now need `base ≠ .conflict`.
- Path model: `mergeVal`/`mergePath` (three-way per path, `ContentMerge` for both-changed paths), `mergedDiff`,
  `ownPaths`; `merged_diff_own`, `main_alone_kept`, `main_only_not_in_diff`, `mergedDiff_sub_own`,
  `mergedDiff_eq_own` (equal when no path changed on both sides), `contains_diff_is_own`, `conflict_iff`,
  `mergeBase_clean_diff`, `mergeBase_conflict`. Premise row `land.mergeTreeIsMergePath`.
- Goldens: land-dry.jsonl loses its 3 stale rows (195 rows); new land-dry-merge.jsonl (32 rows: base, baseKind,
  mergeTree), both written by `scripts/LandDryGolden.lean`.
- land.ts: dry computes `dryMerge` (merge-tree at main's HEAD, `git diff --no-renames --name-only main tree`) before
  the scope check; scope, reads and lints use that diff; the stale refusal is gone. Real land unchanged.
- Tests (land-dry.test.ts): behind-clean gives VERDICT dry with `scope ok (1 files)`; behind-conflict gives VERDICT
  conflict; every merge golden row is built as a fixture repo and replayed through `dryMerge`.

## Open / follow-ups
- land-verdict.ts `dryKind({containsMain})` still maps containsMain=false to stale; golden rows now only carry true.
- docs/team/tools/land.md:140 and lean/Fw/Spec/Incidents.lean:41 still describe the stale rule (outside writes).
- Dry scope sees the merged diff; the real land still checks `main...sha`. They differ only on paths both sides
  changed identically (dry omits them) and renames (dry lists both paths).
