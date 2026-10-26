# offscreen-vm-count: WebKit entries and marquee now read undecided in Lean; sweep and glint keep their verdicts

* Answer (MEASURED, re-read of existing CI artifacts, no new runs). With the VM-count rule in `Fw.Measure.OffscreenWebKit`, an arm needs passes from at least 3 distinct VMs. Entries and marquee (2 VMs each) read undecided in all 4 zones. Before the rule, entries read gain in all 4 zones. Sweep and glint (3 VMs each) keep every verdict. No cell of `10-2x-platform-attribution.md` changes: that note already reported entries and marquee as undecided. Before this change the label was written by hand; now it is the Lean verdict.
* Rule (Lean `Fw.Measure.OffscreenWebKit`): `Pass` carries `vm`. `vmCount` counts distinct VM ids, and `usable` requires `minVms = 3` VMs per arm on top of the pass rule (`passUsable`, unchanged). Theorems: `noData_of_fewVmsBase`, `noData_of_fewVmsFlag`, `zones_noData_of_fewVmsBase`, `zones_noData_of_fewVmsFlag` and `zones_noData_of_undecided` (fewer than 3 VMs in either arm gives noData in every zone); `verdict_eq_passVerdict`, `zoneVerdicts_eq_pass` and `decided_of_not_undecided` (with 3 or more VMs per arm, the verdict equals the pass-rule verdict). Golden `packages/contracts/golden/measure/offscreen-webkit.jsonl` is replayed by `packages/measure-webkit/test/offscreen-webkit.test.mjs`.
* Reader: `node packages/measure-webkit/src/offscreen-webkit-cli.mjs --arm base=<dirs> --arm name=<dirs>`. Each dir must be named `webkit-sim-r<k>`; k is the VM id, and the reader fails on any other name. An undecided cell prints `undecided (n=<base>+<arm> VMs)`, and the column `pass rule only` shows the old verdict. The same k in two runs counts as one VM. That can only undercount VMs, so a cell may read undecided too often but never decided too often.

## Inputs (artifacts `webkit-sim-r<k>` from `gh run download`)
| arm | run | VMs with a session | passes |
|---|---|---|---|
| base | 40203774734 (r2, r3), 40236531932 (r1) | 3 | 6 |
| sweep | 40237513521 (r1-r3) | 3 | 6 |
| glint | 40236465002 (r1-r3) | 3 | 6 |
| entries | 40236534457 (r2, r3; r1 has no session json) | 2 | 4 |
| marquee | 40236475717 (r1, r2; r3 has no session json) | 2 | 4 |

## Before (CLI at d8c3516) and after, per arm and zone
| zone (steps) | sweep before / after | glint before / after | entries before / after | marquee before / after |
|---|---|---|---|---|
| z4500 (10) | noGain / noGain | noGain / noGain | gain / undecided (n=3+2) | noGain / undecided (n=3+2) |
| z5000 (5) | gain / gain | gain / gain | gain / undecided (n=3+2) | noGain / undecided (n=3+2) |
| finish (15) | gain / gain | noGain / noGain | gain / undecided (n=3+2) | noGain / undecided (n=3+2) |
| whole (105) | gain / gain | gain / gain | gain / undecided (n=3+2) | noGain / undecided (n=3+2) |

The counts that differ under the pass rule are the same as before, for example entries finish ObserverCallback less and sweep finish Paint 166-222 / 80-143.
