# compose-superseded-rows handoff

State: branch `worktree-wf_529e3a24-f84-1`. Round 1 at 8788f0b3 (refused), round 2 at f97e588b plus the commit that adds this
file. Main merged at 78330dc8. Not landed.

Built:
- Ledger: `supersededBy: hero.exit.scoped.inline` on `hero.exit.scoped.falsified` and `hero.exit.scoped`; the branch diff
  of `research/findings/ledger.json` is those 2 lines (round 1's merge had reordered rows; rebuilt from main).
- Lean `Fw.Console.Compose`: `classOf` = `classBy` over live rows; `varRows` = `rowsFor` ++ transitive successors.
  `reachesLive` follows `supersededBy` through at most `rows.length` rows. `supersedeErrors` reports each superseded row
  that reaches no live row (dangling id, self-reference, cycle) and each duplicate `id`. The wire throws on any error.
- Goldens `console.compose`: self-reference, 2-cycle, chain of two (allowed), duplicate id, plus round 1's 3 cases.
- `#guard`s in `Fixture`: `withSup` (self-reference, 2-cycle), duplicate id, `chainRows`.

Proved (round 2): `reachesLive_sound`, `supersedeErrors_nil_iff` (no error iff every superseded row reaches a live row and
ids are unique), `supersedeErrors_nil_reaches`, `successors_closed`, `supersedeErrors_cycle`, `supersedeErrors_self`,
`varRows_successor`, `varRows_reaches_live`, `partOut_superseding` (the card lists `varRows`, its `cls` is `classOf` of the
live rows among them, and each superseded row of the variant brings one of them to the card). `classOf_superseding` and
`varRows_superseded_by` were removed.

Verified at f97e588b: `sh lean/scripts/check.sh` green (27 s); console-api 678, contracts 7, runner 1622, ci-paths 49 pass.
A probe without the mark on `hero.exit.scoped` gives `measured` (stated in compose.md); with it, `ledger-proved`.

Pre-existing: the owner-link background-start test (`apps/console-api/test/owner-link.test.ts`) also times out on main;
it passed in this run.

Open: none in scope. Writes outside the graph list (round 1): `lean/Fw/Wire/Compose.lean`, `lean/Fw/Ops/Golden.lean`.

Read first: `docs/team/tools/compose.md` "Superseded rows", then `lean/Fw/Console/Compose.lean` "Superseded rows".
