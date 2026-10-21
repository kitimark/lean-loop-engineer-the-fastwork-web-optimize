# replay-ios-fix handoff

State: branch `worktree-wf_0e6082a8-d0f-1` (main merged); tests green: `pnpm --filter @fw/measure-webkit test`, `scripts/ci-paths.test.mjs`,
`apps/runner` land-inputs (56), `sh lean/scripts/check.sh`.

Done
- Lean `Fw.Device.Replay` section "The replay in pieces": `pieces`, `pieceTimeoutMs` + shape/length/duration theorems; golden kind `pieces`
  in `packages/contracts/golden/device/replay.jsonl` (regenerate: `lake env lean --run scripts/DeviceReplayGolden.lean`).
- Driver (`packages/measure-webkit/src/device-replay-wd.mjs`): one `/actions` call per swipe, per-call limits (`CALL_MS`),
  named `replay-stall` / `wd-timeout` (CLI exit 3), safaridriver in its own process group stopped on SIGTERM/SIGINT/exit,
  `prepareSimulator` (TipKit HideAllTips + Safari terminate), CLI `--sim <udid>`.
- Source reading and Simulator measurement: `research/notes/2026/10-2x-device-replay.md`; usage: `docs/team/tools/device-replay.md`.

Verified: tests above; one local debug run on iOS 26.5 Simulator (original and rewrite, 1 rep): replayMatches false, 1 of 5 swipes seen,
no stall.

Open
- Phone session (lead books): dismiss the Safari first-run tip first; run `run --kinds recorded`; a stall now ends as `replay-stall`.
- Why 4 of 5 swipes lose their touchend, and why probe sessions wedged after a scrolling swipe but the harness passes did not: UNKNOWN.
- `HideAllTips` suppression unverified (tip never appeared on the Simulator). iOS 27.0 Simulators have no safaridriver session host.
- CI reproduction of the Simulator run (3 jobs) not done.
- TS stand-ins (no decision logic): `prepareSimulator`, `startSafaridriver`, `ReplayStall`/`WdTimeout`; `pieces`/`pieceTimeoutMs` are
  golden-checked. `device-replay.mjs` was edited (outside the graph writes list).

Conventions: the Simulator profile must fit the page (390 x 699 on a 17e) or the whole call fails out of bounds; never commit a person's
recording; Simulator runs inside the sim slot.
Read first: the research note section "iOS: how automation sends touches".
