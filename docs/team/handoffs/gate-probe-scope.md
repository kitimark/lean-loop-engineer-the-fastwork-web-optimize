# Handoff: gate-probe-scope (Lean probe scope per pilot part)

Branch worktree-agent-aa83b01fcad24da97 on main a7a544f; commits 74ba652 (scope) and 5f0d2f0 (docstring fixes); CI ref
`ci/gate-probe-scope`. Run ids are in the report to the lead.

## State
- `lean/Fw/Gate/Scope.lean`: part key = truth vector of the part's conditions (orig and rewrite media ids), extra width
  facts (engine.scroll floor 320) and continuous knees (hero.exit 889, 1422, 875, 1500). Scope = width-edge pair seeds +
  greedy cover of every reachable key class per port; sweeps kept iff the key moves along them. `scope_sound`: any run
  with scope ⊆ S_r ⊆ matrix and sweep scope ⊆ K_r ⊆ sweeps gives the part the full-matrix verdict, under hypothesis H
  (module docstring and `scope.gen.json` "hypothesis"). Coverage facts are kernel-decided (`decide`), no native_decide.
- `lean/Fw/Gate/ScopeGen.lean` -> `packages/gate-breakpoints/src/scope.gen.json` via `node scripts/scopegen.mjs`
  (`--check` compares bytes; temp driver because Fw modules may not define root `main`).
- Sizes: engine.scroll 4 probes 0 sweeps; nav.hitTest 1/0; hero.countdown 9/3; hero.exit 9/3; union 20 probes, 4 sweeps.
- Readers: `src/spec.mjs scopeFor`, `src/run.mjs` (filters probes/sweeps, header.parts.scope),
  `.github/scripts/gate-shards.mjs` (shards only scope ids), `.github/scripts/merge-gate.mjs` (recomputes and checks the
  header scope), `breakpoint-gate.yml` (plan sparse-checkout adds `packages/gate-breakpoints/src`). README updated.
- Test: `test/scope.test.mjs` (Lean bytes, ids, sweeps = sweepDefs, rewrite = media.ts MEDIA_IDS, orig/extra/dismissed =
  inventory conditions of the owners, knees = inventory knees, scopeFor union). Package tests 24/24.

## Conventions
- Full matrix (no `--parts`) stays the gate of record; H fails if a part reads a condition outside its key.
- Adding a part: add a `PartUse` to `pilotParts` (owners from the inventory, every inventory condition kept, extra or
  dismissed with a reason), rebuild, regenerate; `scope_covers` etc. re-decide by kernel.

## Open items
- Ask the lead to add `node packages/gate-breakpoints/scripts/scopegen.mjs --check` to `lean/scripts/check.sh` (not in my
  write list); package tests are not in CI.
- Wall clock for hero.* is bounded by the desktop sweep (57 stops), so savings are mostly loads/runner minutes.
- Read first: Scope.lean module docstring, then `scope_sound`, then `spec.mjs scopeFor`.
