# Handoff: device-lag-recorder (phone felt-lag recorder, replay export), round 2

State: branch `worktree-wf_1fac7337-4ee-1`. Read first: `docs/team/tools/device-lag-recorder.md` (Known effects, the session steps the
lead relays), then `lean/Fw/Device/Session.lean`. Regenerate the golden: `cd lean && lake env lean --run scripts/DeviceSessionGolden.lean > ../packages/contracts/golden/device/session.jsonl`.

## What exists
- Lean `Fw.Device.Session`: zones, 34/50 ms counts per 100 moving frames, longest/median, part stalls (`partSeries`: a value paired with
  the position it was computed from; theorems `partSeries_lag`, `stallAt_fn`, `partSeries_no_false_stall`), taps and triple-tap felt
  marks, the arm verdict, replay strokes, the loader's `replayOk`, `dedupArms` (an arm that loads the same page as an earlier one is
  dropped; theorems head kept / pairwise distinct / covered / length), `planOf` and the plan texts per kept set, a synthetic session.
- Golden `packages/contracts/golden/device/session.jsonl` (kinds plan, dedup, series added). TS twin `device-session.mjs`;
  `device-arms.mjs` resolves each arm's URL to its flags (TS stand-in for the site resolver) and calls the dedup; `device-record.mjs`
  (page recorder: pagehide, visualViewport scale, liveness poll); `device-profile.mjs`; commands `plan|record|reduce|profile|package`.
- CI side: `measure-chromium/src/profile.mjs`, `run.mjs` replay mode (now fails when the replayed gesture never scrolls),
  `profiles/user-fixture.json` (generated; equality tested).

## Verified (fixture only)
`test/device-record.test.mjs` (golden agreement, partSeries/dedup/plan vectors, resolver on the real repo and a temp registry, recorder on a
stubbed page, CLI without a phone), `measure-chromium/test/profile.test.mjs`. On main v2-proved is `{fw:{}}`, so the plan has four steps.

## Open
- No live device run; the Chromium replay run (`pnpm -s fw run --engines chromium --target both --profile user-fixture ...`) is a lead dispatch.
- No WebKit profile loader (WebKit lanes step the scroll at 50 px). The look arm's `--search` comes from `look-change.candidates.jsonl`.
- TS stand-ins: `compareZones`, `packageSession`, `resolveFlags` (site resolver has no Lean spec for presets), CLI glue.

## Conventions
- Raw records stay in `.local/phone/<date>/`; commit only `results/phone/<date>/summary.{json,md}`. Every `plan`/`record` takes the same `--search`.
