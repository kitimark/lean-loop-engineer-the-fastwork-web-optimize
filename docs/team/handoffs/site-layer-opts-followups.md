# site-layer-opts-followups (part-builder)

Branch `worktree-wf_4dc1280f-1ad-1`, worktree `.claude/worktrees/wf_4dc1280f-1ad-1`. No CI push (none needed; local checks only).
Last commit: see `git log -1` on the branch. CI runs: none.

Done:
- Order-exact replay: `apps/site/src/registry/layer-opts.test.ts` compares `layerOpts` to the canonical `fwl` in URL order (no sort).
- Encoded-fwl rule, decided in Lean: refuse in both. `Fw.Console.BuildsOpen.okChar_percent`, `okChar_plus`,
  `validate_encoded_fwl` (validate refuses `%`/`+` searches whole with `charsetReason`). Three new rows in
  `layers-search.jsonl` (via `Fw.Ops.Golden.layersSearchCases`). `resolve.ts` refuses with the same reasons whenever `fwl=`
  is present (length > 2000 or a char outside the console charset); no decoding. Searches without `fwl` keep the old behaviour (TS stand-in: the charset regex and length constant mirror Lean).
- Reap tests on main tip 7fd1d23d (worktree, reap code untouched): `vitest run reap` in apps/runner, 5 files, 126 tests, all pass in 41 s. The builder's 10 failures did not reproduce (likely load or a branch-local cause). No task filed.

Open: none beyond the lead's land.
Read first: BuildsOpen.lean (validate_encoded_fwl), resolve.ts top.
