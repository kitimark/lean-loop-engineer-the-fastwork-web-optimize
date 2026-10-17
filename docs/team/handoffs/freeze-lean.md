# freeze-lean handoff

**State:** done on branch `worktree-agent-a15e1e6d363ee0d09` (the commit that adds this note).
- `sh lean/scripts/check.sh` is green (about 65 s).
- `pnpm --filter ./packages/measure-chromium test` passes 13/13.

**What exists**
- `lean/Fw/Measure/Freeze.lean`: the freeze rule.
  - The frozen class of a type is its worst `Level` (det < stable < quar). A type missing from a run counts as quar.
  - `k` and `t` are maxima over the runs; `tBound` is the smallest over the runs.
  - `freeze` refuses fewer than 3 runs, a repeated run id, a run without an image digest, and mixed digests.
  - Proofs:
    - order independence (`worstOf_perm`, `worstOf_congr`);
    - monotone (`worstOf_cons`, `worstOf_mono`, `le_worstOf`);
    - idempotent (`worstOf_append_self`, `worstOf_replicate`, `worstOf_refreeze`);
    - agrees with classify on one run (`worstOf_single_classify`);
    - when the freeze answers (`freeze_ok_iff`, `freeze_few`, `freeze_mixed`).
  - Axioms: standard only (propext, Classical.choice, Quot.sound).
- `lean/Fw/Measure/Wire.lean` op `measure.freeze`.
  - Its 9 golden cases are in `Golden.lean`, written to `packages/contracts/golden/measure/measure.freeze.jsonl`.
- `packages/measure-chromium/src/freeze.mjs`.
  - It reads downloaded run dirs; per run, fwcore `measure.classify` must reproduce `classes.json`.
  - The pooled class comes from classify over all jobs; the signed table comes from fwcore `measure.freeze`.
  - It writes `classes.frozen.json`; `--check` diffs against the committed file.

**Reproduce:** run `gh run download <id> --dir runs/<id> --pattern 'chromium-c*'` for each run:
- swipe-v1: 39038861283, 39038967198, 39038970307
- swipe-touch-v1: 39038973297, 39038976656, 39038979125

Then run `node packages/measure-chromium/src/freeze.mjs runs/* --built-by 39038861283 --check`, which reports "identical".

**Diff against the old hand-made file:** all class data is identical (62 types per profile, tallies 27/25/10 and 16/27/19). Two fields changed:
- `rule`: the text now names measure.freeze.
- `harness`: it is now `commitByRun`. Run 39038861283 ran fdd2b7c and the other five ran 429e22a; the two commits have the same tree (`git diff` is empty).

**Open**
- lean/README.md and the measure-chromium README do not mention freeze yet; they were outside my write list.
- Not proved: the order of the type list itself is unchanged under run permutation. Only the per-type class is proved order-independent.
**Read first:** the header of `Freeze.lean`, then `freeze.mjs`.
