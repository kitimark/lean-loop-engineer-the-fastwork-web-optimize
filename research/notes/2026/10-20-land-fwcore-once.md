# Land: build fwcore once per run (negative finding)

Task land-fwcore-once. Premise: a lean-changing land builds fwcore in all four legs ("4x"), so it should build once. Status: CLOSED, not shipped.
The shipped design (prep job, download in the legs) was reverted; `git diff main...HEAD` holds this note, docs and the Lean "why".

## Measurements (MEASURED, single runs, free arm runners)

| shape | run | wall | fwcore per leg |
|---|---|---|---|
| lean change, before (main) | 39369049545 | 477 s | 251 to 265 s, in parallel |
| lean change, after (binary only, failed) | 39369120267 | 769 s | download 2 s, then suites-a 314 s (modules rebuilt) |
| lean change, after (build tree) | 39370530353 | 553 s | prep job 321 s (setup 46, build 259, upload 9, other 7), legs 4 to 6 s download |
| non-lean, before | 39369095720 | 116 s | 0 to 1 s |
| non-lean, after (exact key, prep skipped) | 39369869288 | 129 s | 0 to 1 s |
| non-lean, after (no exact key) | 39369107918 | 187 s | 19 s (cache state, not the change) |

Runner time fell 43% (1650 s in the four legs to 937 s in prep job + legs; guard excluded); wall time rose 76 s (477 s to 553 s). The probe branches stay on origin as evidence.

## Mechanism

- The four builds ran in parallel, so they cost one build of latency, not four. The saving was runner time, which is free on free runners.
- The prep job is serial: the legs wait for its setup, build and upload, and then each pays a download. The legs' own setup (checkout, toolchain 45 s,
  pnpm) no longer overlaps the build.
- A bare binary is not enough: suites run `lake env lean` scripts that import Fw modules and rebuilt them (270 s, run 39369120267).

## Lean statement (`lean/Fw/Ops/WallTime.lean`)

Parallel jobs finish at the maximum of their times. With a leg `(s, r)` (setup, remaining work) and build `b`:
`wallPar b = wall(s + r) + b` (`wallPar_eq`), `wallPrep P b U d = wall(s + r) + d + (P + b + U)` (`wallPrep_eq`), so
`wallPar b <= wallPrep P b U d` (`wallPrep_ge`), with equality iff `P + U + d = 0` (`wallPrep_eq_par_iff`). The `#guard`s hold 477 < 553 and the 76 s gap.

## General lesson

Runner time is free on free runners; only wall time counts. A shared prep job is serial and cannot beat parallel legs unless the legs' setup
overlaps the build. An overlap design (legs start at once, wait for the artifact) can at best equal the parallel wall time, so it is not worth its
complexity. Before removing duplicated work, check whether the duplicates are on the critical path.
