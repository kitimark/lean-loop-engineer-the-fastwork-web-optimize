branch: worktree-wf_a2056a82-d7a-1 (CI branch ci/commission-band-gate)
worktree: .claude/worktrees/wf_a2056a82-d7a-1 (under the repo root)
last commit: 9997b6272 (pushed to ci/commission-band-gate)

CI runs (state at last update: all dispatched at 19:05Z, running):
- breakpoint-gate both engines `--fw commission:band-gate`: 39836996121 running
- webkit-sim base: 39837001915 / flag: 39837008165 (which is which: see `gh run view`, flag run has fw=commission:band-gate) running
- chromium-counts swipe-v1 x3 base / flag: 39837044649, 39837049981 running

Done: Lean `lean/Fw/Parts/CommissionOpt.lean` (look_gated, look_const_iff, inl_ungated, exit_catchup, fol_cls_agree,
look_agree, commission_visSame, writes_orig, writes_le, gated_run, gated_run_lt, stepV_writes); goldens
`packages/contracts/golden/parts/commission-gate.jsonl` (via `CommissionOptGolden.lean`, registered in `Golden.lean`);
flag `commission:band-gate` (part.json, `driver.ts` opts.bandGate, `logic.ts` planWrite/cardLook, `index.tsx`, test
`bandgate.test.ts`); provisional ledger row n46 (chromium/webkit unknown until measured).
Open: read run results, fill ledger row n46, regenerate preset (`lean/.lake` run of Fw.Preset.Gen.run []), note
`research/notes/2026/10-2x-commission-band-gate.md`, lean check.sh, dry land, review ready.
Outside the task writes: lean/Fw.lean, lean/Fw/Parts/Golden.lean, lean/Fw/Parts/FootprintData.lean,
packages/contracts/golden/parts/footprint.gen.json, packages/contracts/golden/preset/v2-proved.decisions.jsonl,
research/findings/ledger.json.
