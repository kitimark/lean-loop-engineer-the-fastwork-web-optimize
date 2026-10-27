# Morph push on the Simulator: per-push windows (Lean PushCycle.armVerdict, minVms 3)

Runs: run 1 = dl3, run 2 = dl4 (run N here = the Nth directory given).

| arm | VMs (>= 3 windows) | job:passes:windows | style | layout | paint | rAF | slow |
| --- | --- | --- | --- | --- | --- | --- | --- |
| base | 1 | 1:0:0 2:0:0 3:0:0 2:1:6 3:0:0 | - / - / - / 12.5 / - | - / - / - / 10.7 / - | - / - / - / 107.3 / - | - / - / - / 3 / - | - / - / - / 2 / - |
| geom | 4 | 1:0:0 2:1:6 3:1:6 2:1:6 3:1:6 | - / 9.5 / 12.5 / 29.8 / 17.5 | - / 8 / 10.8 / 27.5 / 14.5 | - / 104.7 / 108 / 123.7 / 112.3 | - / 2.7 / 3.3 / 4 / 3.8 | - / 1.3 / 1.7 / 3.3 / 2.2 |
| timed | 1 | 1:0:0 2:0:0 3:0:0 2:1:6 3:0:0 | - / - / - / 40.5 / - | - / - / - / 37.7 / - | - / - / - / 139 / - | - / - / - / 6.3 / - | - / - / - / 7.3 / - |

Counts per push window (mean over the VM windows), one value per VM.

| arm against | verdict | counter spreads (style, layout, paint, rAF, slow; raw, a verdict only with 3 VMs in both arms) |
| --- | --- | --- |
| geom vs base | undecided:fewBase | same same same same same |
| timed vs base | undecided:fewBase | more more more more more |
| timed vs geom | undecided:fewArm | more more more more more |

| arm | no style, layout, paint, rAF in any window | no page rAF in any window |
| --- | --- | --- |
| base | undecided | undecided |
| geom | stirred | stirred |
| timed | undecided | undecided |

Largest window count per arm (style layout paint rAF slow): base 25 21 126 4 5; geom 42 40 144 5 6; timed 61 54 158 10 11

Lost:
- run 1 job 1: morph-base-r1: failed:notReady
- run 1 job 1: morph-geom-r1: failed:notReady
- run 1 job 1: morph-timed-r1: failed:notReady
- run 1 job 2: morph-timed-r1: failed:notReady
- run 1 job 2: morph-base-r1: failed:notReady
- run 1 job 3: morph-timed-r1: failed:notReady
- run 1 job 3: morph-base-r1: failed:notReady
- run 2 job 1: no result file
- run 2 job 3: morph-timed-r1: failed:restartFailed
- run 2 job 3: morph-base-r1: failed:notReady
