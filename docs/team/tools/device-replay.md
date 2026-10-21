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

`run` starts `safaridriver` as its own child and stops it at the end; it never prints the page address. Keep `source.json`,
recordings and `run.json` out of git (`.local/` or the scratchpad).

## Pilot on the phone (a booked session; the lead relays the user step `ask-replay-setup`)

Setup (user, once): `safaridriver --enable` on the Mac (asks for an admin password); on the iPhone Settings > Safari > Advanced >
Remote Automation ON; phone connected and trusted. Then, from `packages/measure-webkit`, with rec-1:

```
node src/device-replay-cli.mjs source --in rec-1.json --id user-x --out source.json
FW_REPLAY_URL=<page> node src/device-replay-cli.mjs run --source source.json --kinds recorded --reps 3 --out run.json
```

Success: all 3 passes satisfy `replayMatches` and the spread between the 3 replays is below the gap between rec-1 and rec-4. The CLI
prints both numbers. The capabilities (`--caps`, default `{"browserName":"Safari","platformName":"iOS"}`) are UNKNOWN until the
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
hundredths of a ms); calibration needs phone replays. The Simulator has no touch path in the harness. WDA (path A) is not built.
