# compose-superseded-rows handoff

State: branch `worktree-wf_529e3a24-f84-1`, last commit is the one this file lands with (WIP 7e719c95 before it). Not landed.

Built:
- Ledger: optional `supersededBy: <row id>` on 2 rows of `research/findings/ledger.json`, no other field touched:
  `hero.exit.scoped.falsified` (refuted) and `hero.exit.scoped` (partly-proved), both -> `hero.exit.scoped.inline`.
  Reasons are in `docs/team/tools/compose.md` "Superseded rows".
- Lean `Fw.Console.Compose`: `LRow` gets `id?`, `supersededBy?` (default `none`); `classBy` is the old `classOf`; `classOf` is
  `classBy` over `live` rows; `varRows` = `rowsFor` ++ the rows that supersede one of them (by `id`, transitively; `extraRows`);
  `refusalOf` reads live rows only; `otherRows` leaves out the superseding rows; `supersedeErrors` lists dangling ids.
- Wire `Fw.Wire.Compose.facts` parses `id`, `supersededBy` (`strOpt`: a non-string is an error) and throws on `supersedeErrors`.
- Goldens: 3 new `console.compose` cases (`cmpLedgerFixed`; dangling id; non-string); the old 19 lines are unchanged.
- TS: `apps/console-api/src/preview/compose.ts` passes `id`, `supersededBy`; test asserts hero.exit:scoped is `ledger-proved`
  with link `?fw=hero.exit:scoped`; the golden error check compares the error string, not its JSON escape.

Proved: `classOf_superseded_never_refutes`, `classOf_superseding`, `classOf_superseded_cons`, `classOf_no_superseded`,
`varRows_no_superseded`, `extraRows_no_superseded`, `varRows_superseding`, `varRows_superseded_by`, `supersedeErrors_nil_iff`;
`classOf_*` restated over `live rows`. `#guard`s in `Fixture` (`fixedRows`).

Verified: `sh lean/scripts/check.sh` green; console-api (638), contracts, runner (1618), ci-paths tests green.

Result: hero.exit:scoped shows `ledger-proved` (live row = the inline row only), no longer `refuted`; still not in v2-proved.

Open / follow-ups:
- Duplicate `id`s are not rejected (`idxOf` takes the first); the ledger has none today.
- Writes outside the graph list: `lean/Fw/Wire/Compose.lean`, `lean/Fw/Ops/Golden.lean`, the two console-api files.

Read first: `docs/team/tools/compose.md`, then `lean/Fw/Console/Compose.lean` section "Superseded rows".
