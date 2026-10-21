# graph-check-lean handoff (round 2)

State: branch worktree-wf_06230cac-6e8-3. Commits: fa8bcae6 (round 1), ab44e7d9 (merge main), 70b142b4 (round 2).
`sh lean/scripts/check.sh` green at 70b142b4; apps/runner `pnpm test` (1644 tests) and `node --test scripts/ci-paths.test.mjs` pass.

Done (round 2)
- Preset check judges the index: `presetCheck` argv is now `node scripts/checkmap.mjs file preset` (cwd `.`). With --staged it
  exports the generator inputs (ledger, golden/preset/*, site v2-proved.json, parts/*/part.json) from the index
  (`git checkout-index --prefix=<tmp>/`), links the built `lean/` entries into `<tmp>/lean`, runs `lake env lean --stdin`
  (`Fw.Preset.Gen.run --check`) there, removes the tmp tree. Without --staged it runs in the working tree.
- Trigger: Lean `presetInput` (CheckMap.lean) = ledger, golden/preset/<file>, site v2-proved.json, parts/<p>/part.json,
  lean/Fw/Preset/Gen.lean; `checkFiles` gives the preset check these files; one theorem per input (presetInput_ledger/golden/
  site/part/gen, presetInput_not); plan_covers/plan_sound restated; golden got a case for the inputs (17 cases).
- Tests (scripts/test-checkmap.mjs, section 3, no skips): stale staged ledger + fixed tree refused (~0.5 s); fixed staged + stale
  tree passes (~1.0 s); no --staged judges the tree; staged golden alone and staged part.json alone run the check.
- plan-check.ts: duplicate check only for string ids (+ test). checkmap.mjs header now says which modes read the index blob.

Limits
- Non-json modes (node --check, sh -n, lake, tsc, ruby, python3, swiftc) read the working tree (header states it).
- A staged Gen.lean triggers the check but the built (working tree) Gen code runs; lake build judges the Gen source.
- Test needs lean/.lake built with Fw.Preset.Gen (fails loudly otherwise).

Writes outside the task list: none new besides round 1's CheckMapGolden.lean (golden source) and this handoff.
Read first: lean/Fw/Ops/CheckMap.lean (presetInput, checkFiles), scripts/checkmap.mjs presetMode.
