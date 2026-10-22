branch: worktree-wf_a2056a82-d7a-1 (CI branch ci/commission-band-gate)
worktree: .claude/worktrees/wf_a2056a82-d7a-1 (under the repo root)
last commit: see `git log -1` (CI runs below measured 9997b6272; later commits touch only a Lean golden function and docs)

CI runs (19:37Z):
- lean push run 39836959930 failed at 9997b62 (init cost lint on gateLines; fixed locally, check.sh green; re-push pending)
- breakpoint-gate flag `--fw commission:band-gate` 39836996121: FAIL (chromium 124 readings, webkit 39): section custom props
  --commission-enter-shrink/--commission-shrink differ orig "0" vs rewrite "1" in the band (the gate compares computed custom
  props); runway height rows also fail (probably the faithful baseline, see base gate run)
- breakpoint-gate base (no flag) 39840038549: running (decides whether commission already fails without the flag)
- webkit-sim base 39837001915 success / flag 39837008165 running
- chromium-counts swipe-v1 x3: base 39837044649, flag 39837049981, both success. MEASURED window scrollY 3070-3530
  (commission bottom 0.85h..0.35h at 430x932): RecalcStyleCount per frame 5.02 -> 3.07, UpdateLayoutTree elementCount
  127.3 -> 60.1, layers/tiles/Paint/Layout/FunctionCall equal. Scratch scripts in the lead scratchpad cbg/.

Done: Lean `lean/Fw/Parts/CommissionOpt.lean` (look_gated, look_const_iff, inl_ungated, exit_catchup, fol_cls_agree,
look_agree, commission_visSame, writes_orig, writes_le, gated_run, gated_run_lt, stepV_writes); goldens
`packages/contracts/golden/parts/commission-gate.jsonl`; flag `commission:band-gate` (part.json, driver.ts opts.bandGate,
logic.ts planWrite/cardLook, index.tsx, bandgate.test.ts); provisional ledger row n46.
Open: gate verdict (see above), webkit numbers, fill ledger row n46 + regenerate preset (printf import Fw.Preset.Gen /
#eval Fw.Preset.Gen.run [] via lake env lean --run on a scratch file), note research/notes/2026/10-2x-commission-band-gate.md,
re-push, dry land, review ready.
Outside the task writes: lean/Fw.lean, lean/Fw/Parts/Golden.lean, lean/Fw/Parts/FootprintData.lean,
packages/contracts/golden/parts/footprint.gen.json, packages/contracts/golden/preset/v2-proved.decisions.jsonl,
research/findings/ledger.json.
