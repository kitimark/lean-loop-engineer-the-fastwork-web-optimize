# scene-pause-kcopy handoff

- Branch: worktree-wf_6617cda3-14e-1; worktree .claude/worktrees/wf_6617cda3-14e-1
- Last commit: this handoff commit (review round 2, after build head 4d752f021); ci/scene-pause-kcopy = 4d752f021 (lead
  dispatches), ci/scene-pause-kcopy-2 = 08b9d953a
- CI runs: trajectory 40139690556 (push, Chromium + Linux WebKit): success, recorded; trajectory 40143377510 (dispatch,
  macOS + Linux WebKit): success, recorded (mac-webkit morph fail); census flag 40151792642 (3 of 3 VMs): success;
  census base 40151813906 (r2, r3 success, r1 cancelled): cancelled; census 40143379767 (1 VM, EINVAL): superseded
- Verified: hero_paused_hidden_copy and the golden replay (build round); census reduced per VM (note section y 5267
  census): flag 39-47 layers, base 124-128, will-change 90 to 5 in every pass; Gen.record + Gen.run: hero:scene-pause
  not a member (status partly-proved, trajectory falsified by the macOS morph cell).
- Open: the macOS nav background-color close@0 fail also appears in the A/A arm 39472217441; it needs the in-flight
  rule (docs/team/tools/trajectory-probe.md) or an A/A rate before the morph cell and the ledger status move.

## What is where
- `lean/Fw/Parts/HeroScenePause.lean` section 7 (kCopy) and section 8 (`Open`, open@1 runs).
- `packages/contracts/golden/preset/v2-proved.trajectory.jsonl`, `v2-proved.decisions.jsonl`: written by Gen.record
  and Gen.run only.
- Note: research/notes/2026/10-2x-scene-pause-kcopy.md; ledger row hero.scenePause.

## Conventions
- Census dispatch: `pnpm -s fw run --target rewrite --engines webkit --fw hero:scene-pause --ref <ci branch>`.
- Census reduction: artifacts webkit-sim-r*, `passes[].census[]` (`scrollY`, `layerCount`, `reasonCounts.willChange`).
- Record a trajectory run: `Fw.Preset.Gen.record [run, sha, "-", <artifact dirs trajectory-*>]`, then `Gen.run []`.
