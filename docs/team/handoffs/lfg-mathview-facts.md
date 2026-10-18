# Handoff: lfg-mathview-facts

**State:** done on branch `worktree-wf_57efa528-98a-1` (see `git log -3`); `sh lean/scripts/check.sh` green; not landed.

**What it does.** `lean/MathViewMain.lean` adds 7 keys to every theorem entry: `headConst`, `implArg` (`{index, expr}`
or null), `assumes`, `killOf`, `class` (closed | rfl | defEq | general), `reach` and `reachFromWire`. Non-theorem
entries and every existing field stay byte-identical. MEASURED locally: with the 7 keys and heartbeats removed, the
6048 old entries hash the same as the pre-change export. `mathview-cached.sh --diff` reports identical output for a
cold store, a warm store and a half-pruned store.

**Read first.**
- `lean/Fw/Spec/MathFacts.lean`: the pure decisions with `#guard`s (`classify`, `implIdx`, `killOf`, `wireRoot`,
  `fwIdents`, `reachFromWire`), 2 theorems (`closed_binders`, `general_of`), the MetaM glue `factsOf` and `wireReach`,
  and the `facts%` term elaborator.
- `lean/Fw/Spec/MathFactsGuards.lean`: `#guard`s on real Fw theorems, one per class and per fact.
- `lean/Fw/Spec/Reach.lean`: `closure` and the registry readers, moved out of `scripts/PropsLint.lean`, which now
  imports them. One copy of the logic, no duplicate.
- `MathViewMain.lean`, section "Facts per theorem": the types `Stored`, `withFacts`, `factsGlobals` and `entryJson`.

**Conventions.**
- Facts are computed in a fresh Core/Meta state for each theorem, within `factsBudget` (20000k heartbeats).
- `plainUnfold` turns off smart unfolding. Smart unfolding needs the matcher extension, which `loadExts := false`
  does not load. Without this, `facts%` and the export would disagree, for example on `wsum_single`.
- The registry rows and the Sig Dom/Cod are global inputs. Their key (`factsGlobals`) is mixed into the tool hash.
- `reachFromWire` is computed after the merge on every run and never stored.
- The tool hash now includes `MathFacts.lean` and `Reach.lean`, so it covers 8 sources in total.

**Open items.**
- The CI mathview-differential job has not run yet. It needs a `ci/*` push, which the lead decides.
- The `defEq` class sits on a heartbeat budget. Near the edge the result depends on the environment:
  `MorphMountOpt.cr_swipe_mixed` is `defEq` in the export but `general` under `facts%` with extensions loaded.
  Every other theorem (2721 compared) matches.
- Generators are matched only by fully qualified `Fw.` identifiers in `scripts/*Golden.lean`.
- `reach` follows definition bodies and theorem types, not proof bodies (the `closure` rule).
- `killOf` matches only `¬ P x` with x a registered row or replay. An `Assume` id must be a literal.
- The export takes about 54 s wall (MEASURED locally), against 40 s before. The `export` phase on a cold store is 40-49 s.
- The task asked for a `checker` subagent on the docstrings, but no spawn tool was available. The 6-point checklist
  was self-applied instead.
