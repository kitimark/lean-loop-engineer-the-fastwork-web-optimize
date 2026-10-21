# device-replay: send a recorded finger path back into a page

A recorded pass (device-lag-recorder) becomes a list of swipes. The tool compiles them into W3C touch actions, sends them to the
page, records what the page saw with the phone recorder, and checks it with the Lean-proved `replayMatches`. Method and statuses:
`research/notes/2026/10-2x-device-replay.md`.

Code (`packages/measure-webkit/`): `src/device-replay.mjs` (TS twin of `lean/Fw/Device/Replay.lean` and `ReplayProfiles.lean`),
`src/device-replay-wd.mjs` (W3C client, safaridriver child, one pass, session), `src/device-replay-cli.mjs` (phone commands),
`src/replay/` (Chromium CDP lane for CI). Golden: `packages/contracts/golden/device/replay.jsonl` (Lean
`lean/scripts/DeviceReplayGolden.lean`; regenerate with `cd lean && lake env lean --run scripts/DeviceReplayGolden.lean >
../packages/contracts/golden/device/replay.jsonl`). Tests: `test/replay-*.test.mjs`, synthetic streams only.

## Commands (phone, from `packages/measure-webkit`)

```
node src/device-replay-cli.mjs source  --in rec-1.json --id user-x --out source.json   # profile + zone data; the file holds a person's finger path
node src/device-replay-cli.mjs make    --source source.json --kind recorded|fast-fling|zone-hero|zone-finish|cold --out profile.json
node src/device-replay-cli.mjs compile --profile profile.json --out actions.json       # W3C payload and tick statistics; no phone
node src/device-replay-cli.mjs check   --profile profile.json --in replay-record.json   # replayMatches with the conjunct of each swipe
node src/device-replay-cli.mjs plan    --kinds recorded,cold --reps 3 --arms 2          # passes and arm order per repeat
FW_REPLAY_URL=<page> node src/device-replay-cli.mjs run --source source.json --kinds recorded --reps 3 --out run.json
```

`run` starts `safaridriver` as its own child (own process group; TERM, then KILL after a grace; stopped again on SIGTERM, SIGINT and exit)
and stops it at the end; it never prints the page address. Keep `source.json`, recordings and `run.json` out of git (`.local/` or the
scratchpad).

Pieces and time limits: a profile is sent as one `/actions` call per swipe (`pieces`, Lean `Fw.Device.Replay.pieces`, golden kind
`pieces`), then a `release`. Every WebDriver call has its own limit (`CALL_MS`; a piece gets `pieceTimeoutMs = 2 x duration + 10 s`, Lean
`pieceTimeoutMs`). A call that does not answer ends the pass with the named error `replay-stall` ("replay of X stalled at piece N of M:
CALL did not answer within T ms", fields profile, piece, pieces, call, timeoutMs; other calls: `wd-timeout`). The CLI prints
`error [code]: message`, exits 3, and records a stalled pass in run.json as `matches:false, swipes:null, stalled:{...}` before it goes on.

iOS Simulator (`--sim <udid>`): sets the capabilities `safari:useSimulator` and `safari:deviceUDID` and, before each fresh session, runs
`prepareSimulator` (`simctl spawn defaults write com.apple.mobilesafari com.apple.TipKit.HideAllTips -bool true`, then `simctl terminate`
of Safari so it reads it). Use an iOS 26.x Simulator: safaridriver found no session host on iOS 27.0 here. The profile must lie inside the
Simulator page (390 x 699 CSS px on an iPhone 17e): a move outside the viewport fails the whole call ("move target out of bounds").
Run it inside the sim slot (`pnpm -s fw slot acquire --kind sim`).

Phone, named user step (before each phone session): open Safari on the phone once and dismiss the first-run tip (the TipKit popover
over the page) by tapping its close button; the hang of the first pilot is attributed to it (INFERRED, see the research note). The
Simulator suppression key is not verified effective, because the tip never appeared there.

## Pilot on the phone

Setup (user, once): `safaridriver --enable` on the Mac (asks for an admin password); on the iPhone Settings > Safari > Advanced >
Remote Automation ON; phone connected and trusted. Then, from `packages/measure-webkit`, with rec-1:

```
node src/device-replay-cli.mjs source --in rec-1.json --id user-x --out source.json
FW_REPLAY_URL=<page> node src/device-replay-cli.mjs run --source source.json --kinds recorded --reps 3 --out run.json
```

Success: all 3 passes satisfy `replayMatches` and the spread between the 3 replays is below the gap between rec-1 and rec-4. The CLI
prints replayMatches per pass and the frame counts and writes run.json; the spread of the 3 replays and the rec-1 vs rec-4 gap are
not computed yet (follow-up pilot-verdict, with the verdict function in Lean). The capabilities (`--caps`, default `{"browserName":"Safari","platformName":"iOS"}`) are UNKNOWN until the
pilot. The automation session may need the phone unlocked; a Safari window in Remote Automation shows an orange bar.

## Chromium lane on CI

Workflow `device-replay.yml` (push `ci/device-replay` with `[ci:device-replay]` in the commit message, or dispatch with `kinds` and
`reps`). It sends the committed profile `packages/measure-chromium/profiles/user-fixture.json` into `snapshot/site` with CDP
`Input.dispatchTouchEvent`, native `requestAnimationFrame`, CPU throttled 6x, and writes `run.json` and `table.md` to the artifact
`device-replay` and the step summary. One run is a proof the lane works, not a class count. Zone kinds need zone data from a
recording, so the CI profile runs `recorded`, `fast-fling` and `cold`.

Reading it: `eventsOk` false on Chromium means the page saw fewer touch events than were sent (coalescing under throttling); that is a
finding about the engine, not a failure of the compiler. `dispatch late` is how late each event left, in ms.

## Limits

Defaults are research values (position 1 px, time 17 ms, lift speed 10 %, start gap 50 ms, speed window 50 ms; Lean stores tenth px and
hundredths of a ms); calibration needs phone replays. The Simulator takes touches through the same W3C path as the phone, but it saw
only 1 of 5 swipes (research note); it is a harness check, not a stand-in for the phone. WDA (path A) is not built.
