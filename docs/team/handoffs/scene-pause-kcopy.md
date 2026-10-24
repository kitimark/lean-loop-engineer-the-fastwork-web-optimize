# scene-pause-kcopy handoff

- Branch: worktree-wf_6617cda3-14e-1; worktree .claude/worktrees/wf_6617cda3-14e-1
- Last commit: this handoff commit (child of merge 845e23150; dry land VERDICT dry); ci/scene-pause-kcopy = 4e2471228 (push 1),
  ci/scene-pause-kcopy-2 = 08b9d953a (push 2, no lane; a second sha for census run 3)
- CI runs: trajectory-probe 40139690556 (push, 4e2471228, fw=hero:scene-pause, all widths): success; Chromium
  UNDECIDED (leave-one-out only), playwright-webkit CLEAN; recorded with Gen.record (3 cells pass, webkit morph pending)
- Verified: `lake build Fw.Parts.HeroScenePause Fw.Preset.Gen` OK; standard axioms only; check.sh green (after the
  first main merge); golden hero-scene-pause.jsonl regenerated, equal to the Lean output; site tests 7376 passed;
  Gen.run --check up to date (hero:scene-pause linked, verdict not-proved: status partly-proved).
- Open: y 5267 census to n=3 (2 webkit-sim dispatches, lead); macOS WebKit morph cell (trajectory dispatch, lead);
  after both: Gen.record the apple run, set the ledger status if the census holds, rerun Gen.run.

## What is where
- `lean/Fw/Parts/HeroScenePause.lean` section 7: `heroAnims` (CSS-read table, replayed by the site test against every
  @keyframes of the hero subtree), `after_splash_copy`, `card_stops`, `threaded_card_after_splash`,
  `hero_paused_hidden_copy`, `hero_paused_same_after_splash`, `kMax_le_kCopy`.
- Section 8 (namespace `Open`): the recorded runs under the open@1 rule (`byMFirst`): `recorded_open_late`,
  `recorded_clean`, `red_needs_original`, `run_640_family`.
- `lean/Fw/Preset/Gen.lean`: link `hero:scene-pause` -> ledger key (hero, candidate text).
- Note: research/notes/2026/10-2x-scene-pause-kcopy.md; ledger row hero.scenePause plus one notes row.

## Conventions
- Census dispatch: `pnpm -s fw run --target rewrite --engines webkit --fw hero:scene-pause --ref <ci branch>`; a
  repeated sha is a cache hit, so the two runs need two shas.
- Record a trajectory run: `Fw.Preset.Gen.record [run, sha, "-", <artifact dirs trajectory-*>]`, then `Gen.run []`.
