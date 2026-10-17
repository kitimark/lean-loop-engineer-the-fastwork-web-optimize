# ledger-merge-driver handoff

State: done on branch worktree-agent-ac9c84b70eb4c78d8 (commit: see `git log -1 -- scripts/merge-ledger.mjs`).

## What exists
- Lean `lean/Fw/Ops/LedgerMerge.lean`: `pick3`, `ids`, `rows`, `merge`; theorems `conflict_iff`,
  `merge_comm_up_to_order`, `no_conflict_disjoint_ids`, `merge_idempotent`, `merge_appends` (+ helpers). Core only,
  no Fw imports. Golden generator in namespace `Fw.Wire.LedgerMerge.Golden` (Fw.Wire is skipped by the mathview lint).
- Golden `packages/contracts/golden/ops/ledger-merge.jsonl` (16 cases), checked in `lean/FwTestMain.lean` (one hook,
  outside the original write list); regenerate: `cd lean && lake test -- --write-ledger-merge-golden`.
- Driver `scripts/merge-ledger.mjs` (`%O %A %B`), `.gitattributes` `merge=ledger` for the three ledgers.
- Test `apps/runner/test/ledger-merge.test.ts`: golden, byte roundtrip of all three ledgers, scratch-repo
  reproduction of the 2026-10-18 append conflict (fails without driver, clean with), backfill + append, a clash.
- Doc `docs/team/tools/ledger-merge.md` (rule, enable command, replay of 6 historical merges).

## Conventions
- Order deviates from the task text on purpose: ours' order then theirs' new ids (not base order first), so that
  `merge(b, x, x) = x` holds exactly; for append-only branches it equals base, ours' adds, theirs' adds.
- findings ledger has no `id`; the driver keys it by `candidate`.

## Open items
- Lead: run `git config merge.ledger.driver "node scripts/merge-ledger.mjs %O %A %B"` in the main checkout.
- No field backfill (semantic); incidents lint catches missing fields.
- scripts/wt-prep.sh skips the clone whenever any `lean --server` (LSP) has its cwd in main lean/; a long-lived
  language server blocks it forever. I cloned by hand (same `cp -c -R`).
