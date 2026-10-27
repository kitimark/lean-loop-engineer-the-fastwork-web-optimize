# Phone morph push at the end of the page (round 3: decided on the phone, 3 visits per arm)

Question: on the real iPhone (WebKit), at the end of the page, do the morph arms change the lag during real pushes?
Arms: base, morph.geom:on, morph.geom:on + morph.tween:geom-timed, morph.stage:on; end segment only; one thermal state (Serious).

## Result (MEASURED, 2026-10-27)
Phone run: 12 visits, 3 per arm, interleaved (base, geom, geom-timed, stage, three times), every visit first attempt, no visit lost.
All 27 thermal readings (block start, between lanes, visit end) read Serious with our induced condition held; the Lean pin gate said
go each time. Each visit is two lanes of 10 XCUITest pushes (2 pattern asks + 3 back-to-back asks, each ask = push forward, hold, back,
hold). Cells are median [min-max] over the 3 visits. Frame intervals in ms; counts are Timeline records between each push and its morph
end, summed over the 10 pushes.

| arm | n | p95 | p99 | max | frames over 50 ms | style | layout | paint | rAF | label |
|---|---|---|---|---|---|---|---|---|---|---|
| base | 3 | 71 [68-75] | 103 [97-112] | 368 [333-371] | 56 [54-63] | 898 | 777 | 9058 | 148 | base |
| morph.geom:on | 3 | 55 [54-65] | 89 [80-97] | 108 [102-141] | 70 [68-86] | 1854 | 1249 | 8242 | 223 | mixed |
| geom + geom-timed | 3 | 76 [71-77] | 109 [107-145] | 140 [132-166] | 67 [63-82] | 1120 | 920 | 8659 | 155 | better |
| morph.stage:on | 3 | 86 [66-95] | 121 [90-141] | 980 [109-1145] | 175 [135-185] | 2435 | 1662 | 21597 | 332 | worse |

The labels are the Lean rule `pushLabel` (`armLabel` over the columns against the base). Full per-visit rows and ranges:
`results/phone/2026-10-27-morph-push/{summary.json,tables.md}`. Raw lanes are in `.local/phone/2026-10-27/` (gitignored).

- geom-timed: better by the rule (max 140 vs 368 ms, style/layout/rAF counts lower than geom alone), but p95 and p99 are not below
  the base and frames over 50 ms are higher; the rule counts the columns, the felt smoothness is the user's. It is a class L arm:
  its look stays the user's visual review, never a preset.
- morph.geom:on: mixed (lower p95, p99 and max, higher over-50 count and 2x style recalculation).
- morph.stage:on: worse by the rule on frames over 50 ms (175 vs 56) and on every count column (2.4x paint). Its p95, p99
  and max medians are higher but overlap the base, so those cells are same. One visit has a 1145 ms frame.
- Unpinned base trial (110 s, thermal Nominal to Fair) gave p95 36, p99 42 ms: at Serious the base is about twice as slow, so
  numbers are only comparable inside this run.
- The push is a fixed XCUITest swipe (forward, hold, back, hold), not the user's recorded finger path. Serious is the only
  thermal state. n = 3 per arm is the rule's minimum; ranges overlap for p95 and p99 between arms, so only max and the count
  columns separate them.
- Pin end: our condition owner stopped and the clear was confirmed; the phone still read Critical for 5 minutes from its own heat
  (`end heatRemains`).

## Cause of the round-2 hang (MEASURED, 2026-10-27)
Round 2 blamed the automation switch. With UI Automation on, the driver works, and the real cause was the driver's file channel:
`throttle/driver/UITests/PushServer.swift` writes `ready` and reads `go-<n>` under a Mac path (the Simulator shares the Mac file
system), but on a real iPhone the XCUITest runner has its own sandbox, so the Mac never saw `ready`. (The log tail ended at an
accessibility snapshot only because the serve loop logs nothing.) Fix, inside this task: `src/device-push-chan.mjs` carries a
phone copy of the server (embedded source, built into a copy of the driver) that reads `go-<n>` and `stop` from its own Documents
container and prints `FWPUSH ready` / `FWPUSH done <n> ok <up ms> <down ms>` marker lines; the Mac side copies request files in with
`xcrun devicectl device copy to` (about 0.5 s) and turns marker lines into `ready` / `done-<n>` files. The driver starts before the
page loads (a Safari showing the loaded page made a snapshot of Safari hang in a separate probe; SpringBoard supplies the touch
coordinates). The driver log is removed before each start, because a stale log appended across runs made `done-<n>` appear without a push.

## Limits (INFERRED unless noted)
- morph.stage:on writes `data-fw-morph`, not the inline `--morph` the frames recorder reads, so its morph amount reads 0 and its span
  end is the last frame where the scroll position changed. Its counts are likely understated, not overstated, so "worse" holds in
  direction.
- The recorder calls `getAnimations` once per frame (its own cost, same for all arms).

## What was built (CONFIRMED in code)
- Lean `lean/Fw/Device/PhoneArms.lean` push-visit section, golden `packages/contracts/golden/device/phone-arms.jsonl`, twin
  `packages/measure-webkit/src/device-push.mjs` (`pushRounds`, `pushOk`, `noRepeat`, `spans`, `visitVals`, `clockOff`, `pushLabel`).
- I/O: `device-push-run.mjs` (frames lane, counts lane, `pushVisit`, `driverHolder`, `summarize`), `device-push-cli.mjs`
  (`plan`, `run`, `reduce`), `device-push-tables.mjs`, `device-push-chan.mjs`; `runBlock` in `device-phone-run.mjs` takes the arm
  list, value function and visit length, so the pinned session, state file and fault classes are reused.
- Tests: `test/device-push.test.mjs` (golden) and `test/device-push-run.test.mjs`. TS stand-ins: the channel, recorder JS and
  tables formatting hold no decisions.
