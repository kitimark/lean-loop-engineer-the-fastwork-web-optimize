# device-lag-recorder: the felt-lag session on the real iPhone

The lag the user feels is on the phone (WebKit); Chromium at normal speed is smooth, and shows the lag only at 6x CPU throttling.
So the phone is the first source of truth. This tool records one person's swipe passes on the phone, finds the moments the person
marked as laggy, reduces them with Lean, and turns the gesture into a profile CI can replay.

Code: `packages/measure-webkit/src/device-record.mjs` (page recorder, banner flow), `device-session.mjs` (TS twin of
`lean/Fw/Device/Session.lean`), `device-profile.mjs` (export and packaging), `device-cli.mjs` (commands). Golden:
`packages/contracts/golden/device/session.jsonl`. Replay loader: `packages/measure-chromium/src/profile.mjs`.

## What a pass records (`fw.phone.record/1`, page units)

- Per native `requestAnimationFrame`: timestamp (ms), `scrollY` (px) and three part values (per mille, read from the inline custom
  properties the page writes): hero exit `--exit-opacity`, people reveal `--future-shrink`, end-of-page morph `--morph-fade`.
- Every touch event: time, phase (`s` start, `m` move, `e` end, `c` cancel), x, y, fingers down. Listeners are passive and never call
  `preventDefault`, so the page behaves as without them.
- A triple tap anywhere is a felt-lag mark. It is not a special event: Lean finds it afterwards (three taps, each at most 300 ms
  long and 10 px travel at most, 0.5 s apart at most, within 40 px of each other).
- No device name, address or id is in a record. The file holds raw timestamps, so it stays local (`.local/phone/<date>/`, gitignored).

Not recorded: the Timeline. `swipe --timeline` (unchanged) is the counts arm; the recorder takes the frame-interval arm because the
Timeline costs time on the page.

Known effects: (1) a touch on a moving page stops its native fling, so the person's taps change the scroll they mark; tell the
person to tap and carry on. (2) The recorder's own rAF callback and three inline style reads run every frame (inline reads do not
flush layout); it runs before the page's callbacks of that frame, so a part value is the one written in the frame before. Both arms
and both original passes carry the same effect, so the comparison is unaffected.

## Reductions (Lean `Fw.Device.Session`)

Times in hundredths of a ms, positions in tenth px (integers). Per pass and per zone (hero = first two viewports, finish = last
viewport, rest): moving frames over 34 ms and over 50 ms, each per 100 moving frames, longest and median interval; per part the
largest step and the stalls (page moved, value held mid-transition); per felt mark the position, zone and the same counts over its
1.5 s lookback window. The comparison: an arm beats the original in a zone only when its worst pass is below the original's best
pass by more than the original's pass-to-pass spread (verdicts `beats | worse | same | unresolved`; one original pass or no arm
pass is `unresolved`). This is why the plan has two original passes.

## Session steps (the lead relays these one at a time; each is a short instruction to the user)

Before: the phone is plugged in and unlocked, Light appearance, auto-lock off, no other pass in the last 5 minutes (block <= 15 min,
cool >= 5; the five passes take about 9 minutes). `sh scripts/sim-lock.sh` is not involved. Output files go to
`.local/phone/<date>/rec-<k>.json`. Run from `packages/measure-webkit` with Node 24; the rewrite is built (`apps/site/dist/aot`).

`node src/device-cli.mjs plan` prints the five banner texts. The banner is drawn on the phone's page; the lead tells the user the same
words in the console.

| step | arm | command | what the user is told |
|---|---|---|---|
| 1 | original | `node src/device-cli.mjs record --step 1 --target original --out ../../.local/phone/<date>/rec-1.json` | "Step 1 of 5, the original page: swipe top to bottom and back at normal reading speed for 90 s; when it feels laggy, tap 3 times quickly." |
| 2 | rewrite | `... record --step 2 --target rewrite --site ../../apps/site/dist/aot --out .../rec-2.json` | same, "the faithful rewrite" |
| 3 | rewrite + v2-proved flags | `... record --step 3 --target rewrite --site ../../apps/site/dist/aot --out .../rec-3.json` (search `?preset=v2-proved` is the default of step 3) | same, "the rewrite with the v2-proved flags" |
| 4 | rewrite + look-change flags | `... record --step 4 --target rewrite --site ../../apps/site/dist/aot --search '?fw=<part:variant,...>' --out .../rec-4.json` | same, "the rewrite with the look-change flags"; the lead picks the flags from `packages/contracts/golden/preset/look-change.candidates.jsonl` before the session and puts them in the report |
| 5 | original again | `... record --step 5 --target original --out .../rec-5.json` | same, "the original page, again" |

Each command first shows a 6 s countdown banner with the step text, then removes the banner and records 90 s, then shows "DONE". The
lead sends the next step only after the previous command printed its one-line summary (frames, taps, felt marks). A step whose
arm and `--target` disagree, or step 4 without `--search`, is refused before the phone is touched. If a pass lost frames (summary
`frames` far under 5400), repeat that step alone.

## After the session (no phone)

- `node src/device-cli.mjs reduce --in rec-1.json,rec-2.json,rec-3.json,rec-4.json,rec-5.json` prints the comparison per zone.
- `node src/device-cli.mjs package --kind session --in <the five> --date <date> --out ../../results/phone/<date>` writes
  `summary.json` and `summary.md`: reports, comparison and felt marks with position, zone and counts only. No time stamps, no
  per-frame data, no touch points, no device. Commit only that directory.
- Replay the user's exact gesture in CI: `node src/device-cli.mjs profile --in rec-1.json --id user-<date> --out
  ../measure-chromium/profiles/user-<date>.json` (one profile per pass; taps are dropped, the swipes are replayed one event per
  virtual frame; `input.feltFrames` lists the frames of the marks). Commit it, push `ci/<name>`, then
  `pnpm -s fw run --engines chromium --target both --profile user-<date> --runs 3 --ref ci/<name>`.
  The profile is checked by `parseProfile` (Lean `replayOk`: single finger, two points or more per stroke, inside the viewport,
  strokes in order, at most 12000 frames) before the run; a refused profile names the reason.
- The WebKit lanes have no profile loader (they step the scroll at 50 px), so the replay runs on Chromium only. A WebKit replay
  needs a loader in `scrollrun.mjs`: follow-up.

## Proof on the synthetic session

`session.jsonl` ends with a Lean-built session (480 frames, 5 strokes, 2 triple taps). `test/device-record.test.mjs` checks:
record -> TS reductions equal Lean's report -> replay strokes -> exported profile equals the committed
`packages/measure-chromium/profiles/user-fixture.json` and loads in `parseProfile` -> package without timestamps or device. The
page recorder runs against a stubbed page (passive listeners, no `preventDefault`, one clock for frames and touches).
