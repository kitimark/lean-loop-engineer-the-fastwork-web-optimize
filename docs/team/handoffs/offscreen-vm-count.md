# offscreen-vm-count handoff
* Branch: worktree-wf_92b98b26-109-1; worktree: .claude/worktrees/wf_92b98b26-109-1.
* Last code commit: 707f67e75 (this handoff is committed after it). check.sh green, measure-webkit 883/883, contracts, ci-paths 56/56,
  runner land-inputs 73/73; dry land `VERDICT dry offscreen-vm-count`; review ready `VERDICT review-ready offscreen-vm-count review`.
* CI runs: none started.
* Verified: the Lean VM-count rule in `lean/Fw/Measure/OffscreenWebKit.lean` (`vmCount`, `enoughVms`, `undecided`, `passUsable`,
  `passVerdict`; theorems `noData_of_fewVms*`, `zones_noData_of_*`, `verdict_eq_passVerdict`, `zoneVerdicts_eq_pass`,
  `decided_of_not_undecided`). The golden was regenerated from `OffscreenWebKitGolden`, and the JS twin and test replay it.
  The CLI reads the VM id from `webkit-sim-r<k>`. A re-read of the platform-attribution artifacts shows entries and
  marquee undecided in all zones, with sweep and glint unchanged (`research/notes/2026/10-2x-offscreen-vm-count.md`).
* Open: none in the unit. The lead decides whether `10-2x-platform-attribution.md` drops its "prose stand-in" sentence
  (no cell changed).
* Conventions: never hand-edit the golden; regenerate it with
  `printf 'import Fw.Measure.OffscreenWebKitGolden\n#eval Fw.Measure.OffscreenWebKitGolden.write Fw.Measure.OffscreenWebKitGolden.goldenPath\n' | lake env lean --stdin`
  from `lean/`.
* Read first: the note above, then `OffscreenWebKit.lean` from `minVms` down.
