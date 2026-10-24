Attempts per job (MEASURED, counted from the job logs). done = a pass with a result; timed out = the touch run passed its limit; code-fail = the touch run ended with a nonzero code.

| run | dispatch | job | done | timed out | code-fail | what was lost |
|---|---|---|---|---|---|---|
| 40105567688 | 1 (4 cycles, 300 s) | 1 | 1 | 5 | 1 | retries on a wedged Simulator |
| 40105567688 | 1 | 2 | - | - | - | cancelled at 80 min, no artifact |
| 40105567688 | 1 | 3 | 0 | 1 | 0 | stalled after the first retry |
| 40105567688 | 1 | 4 | 0 | 1 | 0 | stalled after the first retry |
| 40105567688 | 1 | 5 | - | - | - | runner lost, no artifact |
| 40105567688 | 1 | 6 | 3 | 2 | 0 | partial json |
| 40112979355 | 2 (2 cycles, 480 s) | 1 | 0 | 1 | 0 | retry stalled |
| 40112979355 | 2 | 5 | 0 | 0 | 0 | a touch run still going after 916 s |
| 40112979355 | 2 | 2, 3, 4, 6 | - | - | - | runner lost (probe step 60 to 80 min, no artifact) |
| 40126807029 | 3 (2 cycles, 480 s, reset before a retry) | 2 | 1 | 0 | 0 | then a node undici crash (setTypeOfService EINVAL) |
| 40126807029 | 3 | 4 | 4 | 1 | 0 | release and all not reached in time |
| 40126807029 | 3 | 6 | 2 | 3 | 0 | release timed out twice |
| 40126807029 | 3 | 1, 3, 5 | - | - | - | lost or cancelled, no artifact |

Runner facts (MEASURED): image 20261022.0305.3, 3 vCPU, host load average 300 to 860 on every run, including the earlier good run 40079501230. Passes of that run took 172 to 290 s; the fixed XCUITest cost dominates, so the pass time does not scale with the cycle count.
