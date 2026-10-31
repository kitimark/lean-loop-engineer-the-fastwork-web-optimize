# park-engage: why hero.exit:threaded-park did not engage at the end of the page, and the fix

Task `park-engage`, follow-up of `10-31-sim-end-cut.md` (the park never engaged in 3 of 3 jobs: 13 view-timeline animations kept ticking) and of
`10-30-scrolldriven-park.md` section 3. `hero.exit:threaded-park` stays class L (look-change proposal); no preset change; no breakpoint gate (not shipped).

## 1. Cause (MEASURED, CI iOS Simulator, run 41179356320 on 39d27a6ab, the unfixed park, 3 rounds)

The page census now reads the DOM state of the park: `live` (data-exit-live: the hand-over ran, so `startParkOn` ran), `styled` (the park stylesheet is in
the head), `parked` (data-exit-parked on the track). Source: `results/park-engage/r1/park.txt`.

| arm | live | styled | parked | view-driven | rounds |
|---|---|---|---|---|---|
| park (instant jump to the end) | true | true | false | 13 | 3 of 3 |
| parkWalk (steps of 100 px per frame) | true | true | true | 0 | 3 of 3 |

- Candidate (b) is refuted: `startParkOn` ran (live and styled true) in every round.
- Candidate (a) holds: after the jump the observer sat at "near" and reported nothing, so the park stayed off; a walk makes the sentinel cross the
  viewport, the observer reports far, the park engages.
- Mechanism (CONFIRMED by the pair above, the observer spec is INFERRED): an IntersectionObserver reports when the intersection state changes; the 0-height sentinel
  goes from below the viewport to above it in one jump without ever intersecting, so no entry is delivered.

## 2. Fix and engage rule (Lean `Fw.Parts.ScrollPark`)

Two events start the park: the observer reporting the sentinel far (`io_engages`), and a scroll event at a position more than the margin (one viewport) past the
end of the exit range (`scrollEvent_engages`). The scroll listener is now always on (it was added only while parked); a parked page unparks as before
(`scrollParked`). Theorems, each path on its own:
- `jump_engages`: a position past the margin where the observer's last report was near and `ioParked` is false: `scrollEvent` parks. One event, any state before.
- `walk_engages`: any run of scroll events that ends past the margin ends parked, whatever the state before.
- `io_engages`: the observer path.
- `scrollEvent_no_stale` (held value = animated value, so the look is the same as before), `scrollEvent_restores` (inside the range the hero is live).
TS `park.ts` `scrollEvent` and `createPark` are checked against `packages/contracts/golden/parts/scroll-park.jsonl` (9 `scrollEvent` lines); the
controller also checks the position once at start (a page loaded past the margin). Glue (not proved, no decision): the boundary is read (a layout read)
only when `y` passes the last read threshold plus margin, so a scroll event normally costs one compare. A stale threshold above the true one delays the
park until the observer reports (accepted limit).

## 3. Result (MEASURED, run 41181664848 on 0039fbb95, fixed park, 3 rounds)

`results/park-engage/r2/park.txt`: both arms live, styled, parked, view-driven 0, took in 3 of 3 rounds (park after the jump, parkWalk after the steps).
Not measured here: the effect on the end-of-page style-recalc rate of the full stack (task sim-end-cut-2).

## 4. Harness

`--arms park` of `sim-end-floor-cli.mjs` (workflow tokens `[end-floor] [end-park]`) runs the two park arms of `src/sim-park-engage.mjs`;
`park-report` formats the census (`took` = parked and no view-driven animation). The page script gained the `park` probe in every census and the `walk` act.

## 5. Re-run after merging main (MEASURED, run 41185704042 on 0058ef332)

Main brought the arm sets of sim-end-cut; the park arms became the set `park` (`--arms park`) and the workflow token `[end-park]` picks it. Same result on the merged
harness: both arms parked, view-driven 0, took in 3 of 3 rounds (`results/park-engage/r3/park.txt`).
