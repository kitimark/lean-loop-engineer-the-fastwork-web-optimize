# Handoff: phone-feel-capture

- Branch `worktree-wf_3521dc2c-a1c-1`; worktree `.claude/worktrees/wf_3521dc2c-a1c-1`; last commit: see `git log -1`.
- CI runs: none (the capture needs the phone; no push).
- Verified: phone dry run on the user's iPhone 2026-10-30 (scripted swipe, Serious pin, 2 visits): fields present and well-formed, Lean counts and tables printed (note, "Dry run"). check.sh and measure-webkit tests: see the report.
- Open: nothing for the unit. Follow-ups: a real finger run to the end of the page (pin fights, blink on a real dip); USB drop on a device.
- Read first: `research/notes/2026/10-2x-phone-feel-capture.md` (fields, definitions, defects fixed incl. the two found by the dry run, dry run table).

## State
- Lean: `lean/Fw/Device/FeelCapture.lean` (counts; limits 17 and 34 ms), `Feel.lean`, `Thermal.lean`;
  goldens `packages/contracts/golden/device/feel.jsonl` and `thermal.jsonl` are generated, never hand-edited.
- TS twins: `device-feel-cap.mjs`, `device-thermal-pin.mjs`, `wip-close.mjs`, `device-phone-pin.mjs`.
- Glue: `device-feel-capture.mjs`, `device-feel-run.mjs`, `device-cli.mjs`, `device-feel-dry.mjs`, `device.mjs` (`tabsOfLaunching`: launches
  Safari when it lists no tab; device-verified, no unit test: TS stand-in glue).

## Conventions
- A capture failure never ends the session: the visit stays unmeasured and `feel.json` log names the error.
- No `setsid` on macOS: start helpers with python `start_new_session=True`.

## Limits
- Scripted swipe, not the user; Serious induced; USB-drop handling unit-tested only; n = 2 per same-look arm; no CI.
