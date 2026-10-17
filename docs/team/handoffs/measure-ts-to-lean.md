# measure-ts-to-lean (lean-prover)

**State:** done on branch `worktree-wf_c2b8a932-977-3` (one commit, "lean: measure.selfCheck + measure.snapshotCounts").

**What exists now**
- `lean/Fw/Measure/SelfCheck.lean` is the classes.mjs self-check in Lean. Its `classOf` uses exact integer thresholds: `50·δ ≤ n`;
  `s ≤ 3 ∨ 500·m·s ≤ |ΣT|` (stable); `50·m·s ≤ |ΣT|` (shifting). It also holds the `harness` GC list and `check`/`aligned`. It has 21 theorems,
  including: an iff per class, monotonicity in δ and s, soundness of `check`, and a bridge from δ = 0 to `Holds .deterministic`.
- `lean/Fw/Measure/Snapshot.lean`: `census` computes the 12 counts that trace.mjs `snapshotCounts` emits. It has 7 theorems.
- `lean/Fw/Measure/Wire.lean` adds two ops: `measure.selfCheck` (`{runs}` → `{rows, frames, framesAligned, runs}`) and
  `measure.snapshotCounts` (`{snapshot}` → `{counts}`). The goldens are in `packages/contracts/golden/measure/` (10 files, 67 cases).
- `packages/measure-chromium/src/classes.mjs` gets its classes from fwcore; the TS thresholds and GC list are deleted. `classify.mjs` was already
  on fwcore and is unchanged. `test/fwcore.test.mjs` checks trace.mjs `snapshotCounts` against the Lean goldens.

**Verified**
- `lake build` and `lake test` pass, with 0 stale goldens.
- `node --test test/pure.test.mjs test/fwcore.test.mjs`: 8/8 pass.
- `scripts/check.sh` is green, with no lint warnings in the new files.
- classes.mjs and classify.mjs output is byte-identical before and after on 7 saved count sets (35 outputs).
- The deleted TS logic agrees with the Lean goldens in 11/11 cases.

**Conventions:** every threshold is cross-multiplied so it stays in ℕ/ℤ (no floats). The `$$` math quantifies every explicit binder (mathview lint).

**Open items**
- TS stand-ins: trace.mjs `snapshotCounts` stays (no Lean in the container; the goldens check it). classes.mjs `metaEqual`, byte identity and sha256 are raw-file glue.
- `lean/README.md` op list and `packages/measure-chromium/README.md` (it mentions the classes.mjs thresholds) are not updated: they are outside this task's writes.
- Float vs exact edge: the deleted JS used `0.002·|mean|`. It agrees with the new exact rule except for float rounding at the boundary; the golden "0.2% boundary" case pins the exact rule.
- Worktree build: `lake env lean` asked for missing `.olean`s, so I hard-linked 12 from the elan `lake/cache/artifacts/<hash>.olean` (local only; the known artifact-cache issue).

**Read first:** `SelfCheck.lean` header, then `Wire.lean` `opSelfCheck`, then the selfCheck cases in `Golden.lean`.
