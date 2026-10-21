# Handoff: device-lag-recorder (phone felt-lag recorder, replay export)

State: branch `worktree-wf_1fac7337-4ee-1`, commits after `d198f4ec`. Read first: `docs/team/tools/device-lag-recorder.md` (the
session steps the lead relays), then `lean/Fw/Device/Session.lean`.

## What exists
- Lean `Fw.Device.Session`: zones, 34/50 ms counts per 100 moving frames, longest/median, part stalls and largest step, taps and
  triple-tap felt marks with 1.5 s windows, the arm verdict (beyond the original's pass spread), replay strokes on the 60 Hz grid,
  the loader's `replayOk`, the A/B/A plan and its banner texts, a synthetic session. Theorems: per OR-branch of `zoneOf`,
  `verdict`, `triple`, `isTap`, `strokes`, `replay`; zones partition the frames; every produced stroke passes `strokeOk`.
- Golden `packages/contracts/golden/device/session.jsonl` (`lean/scripts/DeviceSessionGolden.lean`, check.sh job, Trigger.lean read).
- TS twin `packages/measure-webkit/src/device-session.mjs`; page recorder `device-record.mjs`; export/packaging `device-profile.mjs`;
  commands `plan | record | reduce | profile | package --kind session` in `device-cli.mjs`.
- CI side: `packages/measure-chromium/src/profile.mjs` (`parseProfile`, `replayOk`, `replayEvents`), `run.mjs` input mode `replay`
  with a `{until:"script"}` segment, `profiles/user-fixture.json` (generated from the synthetic session, equality is tested).

## Verified (fixture only)
`test/device-record.test.mjs` (golden agreement, fixture pipeline record -> reduce -> replay -> profile -> loader -> package,
privacy of the package, the page recorder on a stubbed page, the CLI without a phone); `measure-chromium/test/profile.test.mjs`.

## Open
- No live device run, no Chromium replay run: `run.mjs` replay mode is untested in the container (needs a lead dispatch, see report).
- The WebKit lane has no profile loader (steps scroll at 50 px): a WebKit replay is a follow-up.
- The look arm's `--search` is picked by the lead from `look-change.candidates.jsonl` at session time.
- Part selectors are inline custom properties (`--exit-opacity`, `--future-shrink`, `--morph-fade`); a series stuck at 0 means a miss
  (the recorder logs it). TS stand-ins: `compareZones` (a map of Lean's verdict per zone), `packageSession` and the CLI glue.

## Conventions
- Raw records stay in `.local/phone/<date>/`; commit only `results/phone/<date>/summary.{json,md}` (no timestamps, no device).
- A tap on a moving page stops its fling (said in the doc); the recorder adds one rAF callback per frame (probe effect, same in all arms).
- Regenerate the golden: `cd lean && lake build Fw.Device.Session && lake env lean --run scripts/DeviceSessionGolden.lean > ../packages/contracts/golden/device/session.jsonl`.
