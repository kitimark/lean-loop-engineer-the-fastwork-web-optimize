# Handoff: lfg-mathview-facts

**State:** round 3 (final design round) on branch `worktree-wf_f776a9ff-79f-1`: round 2 (`e19d526`) and main
(`563181c`) merged, then the lead's closed design. Not landed. The CI mathview-differential job has not run.

**Round 3 (lead decisions, round-2 reviews refused):**
- `reachFromWire S W` = null when $S = []$, else `S.all W` (per subject, no aggregate). Proved: `wire_all`
  (true ⇒ every subject in W), `wire_false_iff` (false ⇔ some `(x, false)` in `subjectsWire`), `wire_none_iff`.
- New `subjectsWire S W = S.map (x, W x)`; the export emits `subjectsWire: [{name, wired}]` (8th key, null when facts
  are missing). `reachFromWire` stays `Option Bool`.
- `opsOf` also requires `hasEntry`, so no `ctorIdx`/`ofNat`/generated subjects; `ctorOps` uses `opsOf`, so the
  fallback feeds the same all-rule.
- Math minors: `sidesDefEq` math names isDefEq at default transparency with budget $k$; `factsOf` passes
  `defEqBudget`; `Facts` is an 8-tuple.
- Guards (Probe5): `dispatch_sound`, `partVerdict_pass_iff`, `isLanded_isDone` → `some false`; `Kind.ofNat_ctorIdx`
  has no subjects (null).

**Counts (MEASURED locally, `lake exe mathview`):**

| export | theorems | true | false | null |
|---|---|---|---|---|
| round 2 (`e19d526`) | 2796 | 1685 | 949 | 162 |
| round 3 | 2799 | 1220 | 1417 | 162 |

The round-3 export has 0 true theorems with an unwired subject, 0 rule mismatches against `subjectsWire`, and 0 subjects
without an entry. The only `.ofNat` subject left is the hand-written `Fw.Site.Breakpoints.Px.ofNat`.

**Stated limits (unchanged):** defEq depends on the environment; `hasEntry` copies the MathView filters; CI
differential not run yet; `wire%` reads `scripts/` relative to the working directory.

**Read first:** `lean/Fw/Spec/MathFacts.lean` (`reachFromWire`, `subjectsWire`, `wire_all`, `opsOf`, `subjectsOf`),
then `lean/Fw/Spec/MathFactsGuards.lean` and `entryJson` in `lean/MathViewMain.lean`.

**Open:** note section 6 (research/notes/2026/10-18-lean-first-gate.md) still describes any-semantics; out of scope.
