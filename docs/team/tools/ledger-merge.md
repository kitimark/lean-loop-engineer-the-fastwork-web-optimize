# Ledger merge driver (`merge=ledger`)

Driver: `scripts/merge-ledger.mjs`. Decision: Lean `Fw.Ops.LedgerMerge` (`merge`, `rows`, `pick3`); the script only
parses, applies the rule and renders. Golden: `packages/contracts/golden/ops/ledger-merge.jsonl` (16 id cases and 6 note cases, checked
by `lake test`; regenerate with `cd lean && lake test -- --write-ledger-merge-golden`); the script is checked against
it by `apps/runner/test/ledger-merge.test.ts`.

## Why
Three `fw land` refusals on 2026-10-18 were line conflicts in `docs/team/incidents/ledger.json`: two branches each
appended an entry at the end of the same JSON array. Per id there was no conflict at all (`merge_appends`).

## Enable (once per clone; lead only)
`.gitattributes` already marks the three ledgers `merge=ledger`. git config is per clone and not in the repo, so run
once in the main checkout (worktrees share its config):

```
git config merge.ledger.driver "node scripts/merge-ledger.mjs %O %A %B"
```

Check: `git config --get merge.ledger.driver`. Without it, git ignores `merge=ledger` and uses its line merge.
git runs the driver from the work tree root, so the relative script path works in every worktree.

## Rule (per id; MEASURED by the golden, CONFIRMED by the theorems)
| base | ours | theirs | result |
|---|---|---|---|
| b | b | t | t (theirs' add, edit or delete) |
| b | o | b | o |
| b | x | x | x (both alike) |
| b | o | t, all different | conflict (`conflict_iff`) |

Absent counts as a version: ours deletes and theirs edits is a conflict; both add the same id with different
values is a conflict. Order: ours' ids in ours' order, then theirs' new ids in theirs' order. Branches keep the base
order and append, so this is base order, then ours' additions, then theirs'.

Theorems: `conflict_iff`, `merge_comm_up_to_order` (swapping ours and theirs gives the same entry set),
`no_conflict_disjoint_ids`, `merge_idempotent` (merge(b, x, x) = x, order included, for distinct ids),
`merge_appends` (merge(B, B++X, B++Y) = B++X++Y for distinct ids), and for notes `add_only_merge` /
`distinct_notes_merge` (both sides only add, no key new on both sides: no clash, every row of both sides kept) and
`distinct_notes_append`. The key type is generic in Lean (ids are strings, note keys are pairs).

## Per-task notes (`notes`, findings ledger)
Why: a finding's `mechanism` is one string of one id. Two tasks that each extend it change that id differently,
which is a conflict by `conflict_iff` (inc-findings-shared-entry: hero.exit, resolved by hand in 212c919, dc1fee1).

Convention (research/findings/ledger.json):
- A task that adds facts to an existing finding appends one row to the top-level `notes` array instead of editing
  the shared string: `{"entry": <the finding's candidate text, verbatim>, "task": <work-graph task id>,
  "field": <the finding field it extends, e.g. "mechanism">, "text": <the addition, with its CONFIRMED/MEASURED
  status>}`. One row per (entry, task); a task edits only its own rows.
- The full mechanism of a finding is its `mechanism` string followed by its `field: "mechanism"` notes, in array
  order. Later notes may supersede earlier ones; say so in the text ("Restated (task): ...").
- Edit the shared fields (`mechanism`, `verdict` fields, `next`, ...) only for a deliberate restatement that owns
  the finding, ideally when no other open task writes it; that edit can still clash, by design.
- Driver key of a note row: `note:` + `JSON.stringify([entry, task])` (`keyOf`); the `notes` member is merged per
  key like `findings`. The test checks every note names an existing candidate and the keys are distinct.
- Migration (task findings-subentries): the labelled per-task tails of 16 mechanism strings moved verbatim into
  18 notes (why-engines 15, wktr-p1p4 2, hero-exit-restate 1); mechanism + notes rejoined equals the old text,
  except that hero.exit's wktr-p1p4 note joins its two segments (the old text had the restatement between them).

## What the script does (glue)
- Entry id: `id`, else `candidate` (`research/findings/ledger.json` has no `id`; editing a candidate's text is a
  delete plus an add).
- Top-level array: merged by id. Top-level object: each member is merged by the same rule, as a whole value, except
  an id-keyed array member (`incidents`, `findings`, `mistakes`, `classes`, ...) that differs between ours and theirs:
  that one is merged per id.
- Output: `JSON.stringify` with the indent of ours (1 space for incidents and findings, 2 for mistakes) and ours'
  trailing newline (findings has none). The test checks `merge(x, x, x)` is byte-identical for all three ledgers.
- Conflict: exit 1; each conflicting entry or member is written as a standard block
  `<<<<<<< ours` / `=======` / `>>>>>>> theirs` (a deleted side is empty), the rest merged. git then lists the
  file as unmerged.
- Not a ledger (unparsable JSON, entries without ids, duplicate ids): `git merge-file` line merge, exit 1 on
  conflicts.
- No field backfill: if one side adds a field to every entry and the other appends an entry without it, both
  changes survive, and the new entry still lacks the field. `pnpm fw incidents lint` catches that for incidents.

## Replay of the real merges (MEASURED, 2026-10-18)
The driver on base/ours/theirs of all six non-trivial merges of `docs/team/incidents/ledger.json` in history:
0 conflicts in all six (git had reported conflicts). Compared with the hand resolution: 1 identical; 2 the same
entries with formatting differences from that time; 1 the same entries in another order (theirs' addition placed
first by hand); 2 differ only in the 1 to 2 entries the lead backfilled by hand.
