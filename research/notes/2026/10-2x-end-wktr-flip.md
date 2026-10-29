# end-wktr-flip

Question: on WebKit (WKTR, pref OFF, the open morph of the page end), do `platform:faded-pause` and `platform.glint:compositor` cut the style
recalcs, and what is left of the compositor's flip residual (80-88 against the all-paused floor 68-75 in glint-compositor r4)?
Why: the user feels the end of the page laggy on every arm (phone 2026-10-29: base 1, v2-proved 3, +glint-hold 3). The Simulator lane never reaches
the open morph; the WKTR flip arm does. Task `end-wktr-flip`. Class counts per 100 frames, not phone time. WKTR is not iOS Safari (limit, below).

## Rules decided before the data (CONFIRMED, Lean)
`lean/Fw/Device/EndWktr.lean` at 1025b2bcc, pushed in 49a5c04f3 before any run; golden `packages/contracts/golden/device/end-wktr.jsonl`; the
reducer `packages/measure-wktr/src/end-wktr.mjs` replays it (`test/end-wktr.test.mjs`).
- Cell verdict (`judge`): band = max(floor((b - f) / 16), spread of the base series in recalcs per 100 frames). Unread below 12 frames in any series;
  no-contrast when base < floor + 50 (recalc) or + 20 (layout, compositing, layerFlush); uninformative when b - f <= 2 band; else cuts if v + band < b,
  adds if b + band < v, else no change. Theorems `cuts_spec`, `adds_spec`, `noChange_spec`, `cuts_lt_base`. A run needs 2 judged jobs, all equal, else mixed.
- Cause of the compositor flip residual (`causeOf`, five cases `cause_none / running / markup / both / offset`): the flip reading v against the
  page's own all-paused floor p (same process) and the base floor f. `offset_le`: an "offset" residual is at most f + 2 band, so it cannot be a
  compositor effect larger than the band. Mechanism (`mechOf`): frames with a recalc by category written / animated / empty, live minus all-paused,
  a category counts above the band (`catSum_partition`).
- Hypothesis before the run (INFERRED from glint-compositor r1/r2/r4, where floors moved 68-96 between processes): most of the 80-88 against 68-75
  is a floor offset between processes.

## Arms (MEASURED lane, run 40869911524 at 49a5c04f3, 3 jobs j1..j3, pref OFF, `morph.geom:on,morph.tween:geom-timed`, 402x820)
Flip arm = the wheel at the page bottom, 16 reps of about 4 frames. `nat` = the page as shipped (nothing paused); `pall` = all animations and SMIL
paused in the same process (the floor); `iso` = the old glint-compositor arm (other animations paused, glint kept); `obsf` / `pallf` = per-frame
records of live and all-paused.

## Result: recalcs per 100 frames, flip arm (MEASURED, run 40869911524, results/end-wktr-flip/r1/wktr-j{1,2,3}, verdicts in verdict.txt)

| arm | j1 | j2 | j3 | Lean verdict over 3 jobs |
|---|---|---|---|---|
| base (nat) | 244 | 242 | 237 | - |
| all-paused floor (same process as base) | 83 | 70 | 81 | - |
| platform:faded-pause | 87 | 89 | 91 | cuts (3 of 3) |
| platform.glint:compositor | 146 | 142 | 219 | cuts (3 of 3) |
| faded-pause + compositor | 87 | 92 | 70 | cuts (3 of 3) |
| band (max of floor-gap / 16 and base spread) | 11 | 10 | 9 | |

At the floor (v <= f + band): faded-pause 1 of 3 jobs (j1 87 against 83 + 11; j2 89 is 9 above 70 + 10, j3 91 is 1 above 81 + 9), both 2 of 3 (j1 87, j3 70; j2 92 is 12 above 70 + 10), compositor alone 0 of 3.
Frames per series 48-74 in every cell (minimum 12), so no cell is unread.
- Faded-pause takes the natural flip from about 240 to about 90 (floor 70-83): the cut is real in all three jobs, and what is left is 4-19 per 100 frames
  above the floor.
- Compositor alone cuts, but only to 142-219: it does not reach the floor in any job. Adding it to faded-pause changes nothing the rule can see
  (both 87/92/70 against faded-pause alone 87/89/91; INFERRED: no Lean rule compares both with faded-pause): `platform:faded-pause` is the arm that matters at the page end.
- Layout and compositing counts: compositing cuts like recalcs in every arm. Layout: faded-pause cuts and both cut;
  compositor alone and the iso arm are mixed (j3 108 against base 104, an outlier process, see below); layerFlush is no-contrast (133 per 100 frames in
  every arm: one flush per frame whatever the animations do), so nothing there is a candidate.

## The compositor flip residual, split by cause (MEASURED)
iso arm (the glint-compositor r4 arm, glint animation kept running, everything else paused) against the floor:

| job | base-process floor f | compositor page, all paused (p) | compositor flip, live (v) | band | cause (Lean) |
|---|---|---|---|---|---|
| j1 | 83 | 79 | 89 | 6 | no residual (v <= f + band) |
| j2 | 70 | 88 | 70 | 11 | no residual |
| j3 | 81 | 175 | 166 | 6 | the variant markup (p > f + band, v not above p) |

- 2 of 3 jobs: the compositor flip is at the floor (89 against 83, 70 against 70). The residual of glint-compositor r4 is not the compositor: the
  all-paused floor itself moves by process (j2: 70 in the base process, 88 for the compositor page all paused; r1/r2 floors 68-96). Lean overall:
  `mixed`, because j3 reads differently.
- j3: the compositor page is high with everything paused (own floor 175) and live (166), against the base-process floor 81 and band 6, so the
  running glint adds nothing (v <= p); Lean names that "markup". Its flip runs longer windows (comp-iso 74 frames per series against 48 for the
  floor and for `both`; `rs.wins` mostly 4-5 frames per rep against 3) and writes the morph panel in every rep (obsf and pallf records of the compositor
  page: `mut:morph-panel#data-expanded` 16 and 16 frames with a recalc, `mut:nav#class` 23 and 23, against 4 and 4 for each key in j1 and
  3 and 3 in j2), so in this process the flip reached a different page state: a workload difference, cause not isolated
  (INFERRED, run 40869911524). The base and `both` series carry no key table, so their writes are not counted.
- Mechanism (Lean `mechOf`, live against all-paused, same process, frames with a recalc by category, per 100 frames):

| job | written live / paused | animated | empty | name |
|---|---|---|---|---|
| j1 | 68 / 61 | 20 / 32 | 0 / 0 | one category: written (band 6) |
| j2 | 63 / 53 | 24 / 32 | 0 / 0 | nothing above the band (band 11) |
| j3 | 169 / 149 | 11 / 24 | 0 / 0 | one category: written (band 6) |

  Overall `mixed` (the rule's own output). Written frames (DOM mutations) carry most recalcs, live and paused. The live glint arm is above its
  paused read by more than the band in j1 (written 68 against 61, band 6) and j3 (169 against 149, band 6), not in j2 (63 against 53, band 11).
  Keys, frames with a recalc live / paused as the files show them: `mut:nav#style` and `mut:nav#data-fw-morph` 11/11 in j1 (the rule's key
  line prints `-`: no key is higher live), 13/10 in j2, 38/36 in j3; the entry bundle's `timer:interval` (T>E, line 47) 11/11 in j1, 13/10 in
  j2, and in j3 the interval through `gc` (line 45) 24/21 (also `ev:animationiteration` 2/0 in j3). Animated is lower live than paused (20/32,
  24/32, 11/24) and empty is 0 in all jobs.

## Next candidate
The floor is the remainder: 70-90 recalcs per 100 frames at the page end with every animation paused, made of frames where the page writes
`nav` style and `data-fw-morph` (the nav hide and the morph publish; `waapi.driver.ts:28,44` says `data-fw-morph` is written at the push, at a
threshold and at the end; the `nav#style` writer is INFERRED from the key, not yet read). Next: one arm with the nav style/data-fw-morph writes
batched to the push and the end of the tween, measured against `pall` in the same process (`obsf` keys name the writers; `pall` is the floor to beat).
Not the glint, which is at the floor on 2 of 3 jobs; `faded-pause` already takes the rest.

## Limits
- WKTR is not iOS Safari; counts are recalcs and layouts, not felt smoothness. The phone check comes with the user's capture session.
- The cause of j3 is not isolated (a workload difference between the flip's page states is INFERRED; a second process would tell); the overall is `mixed` as the rule says.
- Floors move by process (70-88 here), so any claim below the band (9-11) is not made.
- faded-pause look stays class E (user's visual review); no preset changed.
