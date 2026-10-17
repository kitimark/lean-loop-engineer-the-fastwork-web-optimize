# Handoff: mutant-ids-stable

State: mutant ids no longer hold line numbers (commit on branch `worktree-agent-ade12f4bf2d8fb4d9`, see `git log
-- lean/FwTest/Mutants/gen.mjs`). Same 621 mechanical mutants as before (TSV columns other than the id unchanged).

Id format (`lean/FwTest/Mutants/gen.mjs`, `mutantId`): `<decl>#<k>:<op>:<repl>`, e.g. `samples#6:str:""`.
- decl = the enclosing def/abbrev/instance name; `_` if anonymous; `name@n` (n-th, 1-based) if the file has several
  declarations with that short name (two namespaces). None of the 9 M0 modules has one today.
- k = 1-based rank of the site's start offset among the sites of the same op in that declaration (per op, so an
  added literal does not renumber the `num` mutants).
- repl = replacement; `drop` if empty; `x` if > 12 chars or holding a tab/newline; `num` always in full.
- Unique: (decl, op, k) fixes the offset; only `num` puts two mutants on one offset (n+1, n-1), rendered in full.
  `mutants()` also throws on a duplicate id. Only edits inside a declaration move its ids.

Migrated `equivalent.tsv`: 3 rows, reasons unchanged (Wire `samples#1`, `samples#6`; SpawnGuard `hasInfix#1:num:2`).

Added:
- `lean/FwTest/Mutants/gen.test.mjs` (`cd lean && node --test FwTest/Mutants/gen.test.mjs`, 8 tests, about 1.5 s): uniqueness
  on the M0 set and on duplicate names, anonymous instances and long numerals; ids kept under edits above, below
  and inside a declaration; every equivalent.tsv row names exactly one mutant; 16 shards partition the list.
- `mutants.sh`: after listing, a stale equivalent.tsv id of a listed file fails at once ("stale equivalent.tsv id"),
  checked against the uncapped list, so `-s` does not matter. Shard hash and merge check unchanged (they key on
  column 2, now the new id). gen.mjs runs its CLI only when run as a script, so the tests can import it.

Gate (local, not a result): `mutants.sh -S 1/16 -n 6`: pool 633, 6 of 6 killed, 81 s (baseline 49 s);
`lean/scripts/check.sh` green; shellcheck -S warning and actionlint clean.

Open items: `node --test` is not part of `lean/scripts/check.sh` or `mutants.yml` (outside this task's write set);
adding it to the `plan` job of mutants.yml would catch a stale id before any shard starts. Old `-i` survivor
lists hold old ids and no longer match.

Read first: the gen.mjs header, then `mutants()` id block and gen.test.mjs.
