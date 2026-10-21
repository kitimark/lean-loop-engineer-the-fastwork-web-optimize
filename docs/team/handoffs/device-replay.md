# Handoff: device-replay (measure-engineer, branch worktree-wf_31fab2d4-529-1)

Read first: `research/notes/2026/10-2x-device-replay.md` (method, 7 check fixes, statuses), then `docs/team/tools/device-replay.md`.

## State
- Lean: `lean/Fw/Device/Replay.lean` (profile, W3C compiler with `compile_dur_le`/`compile_targets`/`px_err`, `replayMatches` with
  one theorem per conjunct, `Lim` defaults), `ReplayProfiles.lean` (fast-fling, zone-loop, cold, arm rotation, schedule with
  theorems), `ReplayGolden.lean` + `lean/scripts/DeviceReplayGolden.lean` -> `packages/contracts/golden/device/replay.jsonl`
  (24 lines; job `device-replay golden check` in `lean/scripts/check.sh`).
- TS (`packages/measure-webkit`): `src/device-replay.mjs` (twin), `src/device-replay-wd.mjs`, `src/device-replay-cli.mjs` (safaridriver
  lane, never run on a phone), `src/replay/` (Chromium CDP lane for CI). Tests `test/replay-{twin,driver,chromium}.test.mjs`
  pass on synthetic fixtures only.
- CI: `.github/workflows/device-replay.yml` (lane, rows in `lean/Fw/Ci/Trigger.lean` and `Overflow.lean`, goldens
  `ci/triggers.jsonl` + `ci/intent.jsonl` regenerated with `cd lean && lake test -- --write-ci-trigger-golden`). Run id in the report.

## Verified
`sh lean/scripts/check.sh` green; measure-webkit tests; `scripts/ci-paths.test.mjs`; apps/runner `ci-triggers`, `land-inputs`,
`land-overflow-widths` tests.

## Open
- Phone pilot (rec-1 x3): needs user step `ask-replay-setup` (`safaridriver --enable`, iPhone Remote Automation ON, booked session).
  Command in the tool doc. Safari capabilities UNKNOWN until then.
- Follow-ups: Simulator lane (no touch path in the harness), limit calibration (`Lim` defaults are research values), pilot verdict
  function in Lean (the CLI prints the numbers), WDA path A not built, bootstrap CI / hero-stall stats not built.
- TS stand-ins: `fromCiProfile`, `makeProfile`, `simulateEvents`, driver glue (decisions are Lean-proved and golden-checked).

## Conventions
Recordings of a person's finger path (`rec-*.json`, `source.json`, `run.json`) stay local; never commit or copy their values.
Do not hand-edit generated goldens. CI push: `git branch -f ci/device-replay HEAD`, `git push origin ci/device-replay`, commit
message contains `[ci:device-replay]`.
