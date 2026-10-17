# Handoff: phone-session-1 / 1b (gap-device, gap-light, swipe-baseline)

State: committed in worktree branch `worktree-agent-a86c502bf74782600`. Code commit `196eac4`; results and note in the
following commit. Read first: `results/phone/2026-10-17-s1/README.md`, then `research/notes/2026/10-17-phone-session-1.md`.

## What exists
- `packages/measure-webkit/src/device.mjs`: phone selection (model + OS), own iwdp ports 9460/9461, LAN server, redaction,
  readouts. `device-runs.mjs` (counts, scripted frames), `device-compare.mjs` (tables, pooling), `device-cli.mjs`
  (`ping | counts | frames | compare | package`). `serve.mjs` got a backward-compatible `host` option.
- `packages/gate-breakpoints/src/gaps/devicecells.mjs` + `devicedrive.mjs`: `gaps device-drive --sim <evidence.json> --out DIR`.
- Tests: `device.test.mjs` (5), `devicecells.test.mjs` (2, needs FW_CORE_BIN). Raw passes and timestamps stay local.

## Conventions
- No address, device id or device name in any file (`redact`; scrub hook blocks IP literals, tests build them from parts).
- Never touch ports 9221/9222/9341/9342, the second phone, or processes not started by this run. Block <= 15 min, cool >= 5.
- Run order used: `counts` original, rewrite; then `frames` A R A R, 5 reps at 800 px/s; `package` strips raw data.

## Open items
- Finger-swipe metric needs the user (lead decides). Dark appearance on the phone: switch to Light for a gap-device S check.
- aA zoom, landscape and mouse steps in `gap-device` DEVICE.md need a hand.
- Redo the rewrite arm on a finished rewrite. No TS stand-ins hold decision logic; verdict decisions come from fwcore.
- CI cannot run the phone; the phone lane is local-by-necessity (work-graph reason: real device).

## Session 1b (2026-10-18), branch `worktree-agent-afd1f8f277a866f52`
- Done: gap-light (Light: 8/8 agree, W X T S L pass), finger swipe on the original (`results/phone/2026-10-18-s1b/`, note
  `research/notes/2026/10-18-phone-session-1b.md`). New: `device-swipe.mjs` and `device-cli.mjs swipe [--timeline] [--seconds n]
  [--wait-light s]`: the page shows the instructions as a banner on the phone (a subagent has no channel to the lead mid-run),
  removes it, records every frame's rAF timestamp and scrollY, retries a timed-out poll, shows DONE at the end.
- Gap drive needs FW_CORE_BIN and a Simulator evidence file (`gh run download 39044573514 -n gaps-raw-macos-m1`).
- Open: rewrite swipe (`--target rewrite --site apps/site/dist/aot`, build with `pnpm --filter @fw/site build`), counts under a
  swipe (`--timeline`; attribution of idle time to the last 50 px band is a known simplification), 2 to 3 repeat recordings for spread.
