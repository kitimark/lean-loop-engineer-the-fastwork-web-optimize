# Simulator end-of-page: does throttle-lift remove the finish-zone signature?

Task note for sim-finish-throttle. Answer first.

## Answer

- The pinned metric (still runs of 5-6 frames in the last 600 px, the phone's band) shows no signature in the Simulator: verdict **no-signature** in every job of both runs (MEASURED, runs 40076091168 and 40079501230). Rewrite 2 band runs in 14,410 finish frames, original 2 in 13,205, lift 1 in 10,965.
- A different shape does show, in the same finish zone: still runs of 1-9 frames per 1000 finish frames, original 27.7, rewrite 29.1, rewrite + throttle-lift 2.3 (MEASURED; 8-10 usable passes per arm; every job with lift data 1.9-2.6 against 23-36). Applied to those counts, the Lean verdict formula (lift runs x base frames x 5 <= base runs x lift frames) gives lifted: 25 x 14,410 x 5 = 1.80M <= 420 x 10,965 = 4.61M (INFERRED: exploratory metric, not declared before the runs).
- Reading (INFERRED): the Simulator runs rAF at a median 33-38 ms gap (about 28 Hz) on the CI runner, so a throttle that holds scrollY for several 60 Hz frames shows as runs of 1-2 frames, not 5-6. The band was set from phone 60 Hz frames.
- Reversals of scrollY while the morph panel is open (4.1-4.6 per usable pass) and open lateness (1-3 frames) do not differ between arms.
- Slow frames: gaps over 50 ms appear in the Simulator (13.0 per 100 rewrite, 25.8 original, 21.0 lift) but the CI runner dominates them (Mac GPU absent; INFERRED not to transfer), and lift is not lower. They are not compared with the phone (phone finish zone slow frames per 100: original 4.19-10.09, rewrite 2.46-6.56, lift 0.00-1.17).

## Table per arm and job (run 1 40076091168 / run 2 40079501230)

Band runs / still runs of 1-9 / usable passes / finish frames:

| job | arm | run 1 | run 2 |
|---|---|---|---|
| 1 | rewrite | 0 / 45 / 1 / 1248 | 0 / 51 / 1 / 1739 |
| 1 | lift | 0 / 5 / 2 / 2061 | 0 / 6 / 2 / 2964 |
| 1 | original | 1 / 67 / 2 / 2123 | no usable pass |
| 2 | rewrite | 0 / 92 / 2 / 3189 | 2 / 86 / 2 / 3109 |
| 2 | lift | 1 / 3 / 1 / 1151 | 0 / 7 / 2 / 2722 |
| 2 | original | 0 / 78 / 2 / 2655 | 0 / 58 / 2 / 2491 |
| 3 | rewrite | 0 / 47 / 1 / 1474 | 0 / 99 / 2 / 3651 |
| 3 | lift | no usable pass | 0 / 4 / 1 / 2067 |
| 3 | original | 1 / 81 / 2 / 2935 | 0 / 82 / 2 / 3001 |

Verdict per job: no-signature (or no-data where a pass was lost). Full tables: `results/sim-finish-throttle/run-*-table.md`.

## Limits

- Touch-driver timeouts lost passes (run 1 job 3 lift; run 2 job 1 original and one rewrite, step limit hit): three jobs per run, lift data in 5 of 6 jobs.
- Hero-lane reference (run 39667548341): 163 band runs in 10,104 exit frames for rewrite, 0 in 9,740 for lift.- Per-job frame statistics (short runs per 1000 frames, rAF gaps over 50 ms per 100, median gap) are in `results/sim-finish-throttle/frames-by-job.txt`.
- Phone slow-frame and felt-smoothness numbers are not reproducible here.

## Follow-up

A cadence-scaled band (or the 1-9 short count as the declared metric) in a later Lean verdict, then one more pass over the phone and the Simulator.
