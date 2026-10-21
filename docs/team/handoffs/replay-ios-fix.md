# replay-ios-fix handoff

State: branch `worktree-wf_0e6082a8-d0f-1` (main merged); tests green: `pnpm --filter @fw/measure-webkit test`, `scripts/ci-paths.test.mjs`,
`apps/runner` land-inputs (56), `sh lean/scripts/check.sh`.

Done
- Lean `Fw.Device.Replay` section "The replay in pieces": `pieces`, `pieceTimeoutMs` + shape/length/duration theorems; golden kind `pieces`
  in `packages/contracts/golden/device/replay.jsonl` (regenerate: `lake env lean --run scripts/DeviceReplayGolden.lean`).
- Driver (`packages/measure-webkit/src/device-replay-wd.mjs`): one `/actions` call per swipe, per-call limits (`CALL_MS`),
  named `replay-stall` / `wd-timeout` (CLI exit 3), safaridriver in its own process group stopped on SIGTERM/SIGINT/exit,
  `prepareSimulator` (TipKit HideAllTips + Safari terminate), CLI `--sim <udid>`.
- Notes: `research/notes/2026/10-2x-device-replay.md`; usage: `docs/team/tools/device-replay.md`.
Round 2: `replayMatches` cannot be true on a page that scrolls natively under the touch; two named reasons, source-cited and
MEASURED (research note): (1) drift, `WebAutomationSessionIOS.mm:205` + `PageClientImplIOS.mm:548-551` put the touch at planned y minus
scrollY, not compensable (`WebAutomationSession.cpp:2424-2425`); (2) native scroll take-over loses `touchend` and wedges the session
(mechanism UNKNOWN). On a replay-capable page (root offset 0, page cancels touchmove) the harness saw 5 of 5 swipes x 3 passes;
`replayMatches` false there from piece lag only (`startOk` 50 ms, `timeOk` 17 ms fail from piece 2). `/root` gave a named
`replay-stall` in 48 s, no orphan. Signal handler now waits graceMs, SIGKILLs the group, re-raises (real-signal test);
`recorderSeconds` adds one second per piece.
Verified: tests above; Simulator runs (local debug, iOS 26.5): 2 on the site (1 of 5 swipes), 3 passes on `/ok` (5 of 5), 1 stall.
Open
- Lead: add `packages/measure-webkit/src/device-replay.mjs` to the task writes in `docs/team/work-graph.json` (I edited it; the file is outside the list).
- Phone session (lead books): dismiss the Safari first-run tip first; run `run --kinds recorded`; a stall ends as `replay-stall`.
- Lag compensation (Lean change, subtract summed lag from the next lead-in pause); wedge mechanism UNKNOWN; XCUITest/idb driver idea.
- `HideAllTips` suppression unverified; CI reproduction (3 jobs) not done; iOS 27.0 Simulators have no safaridriver session host.
- TS stand-ins (no decision logic): `prepareSimulator`, `startSafaridriver`, `ReplayStall`/`WdTimeout`; `pieces`/`pieceTimeoutMs` golden-checked.
Conventions: the Simulator profile must fit the page (390 x 699 on a 17e) or the whole call fails out of bounds; never commit a person's
recording; Simulator runs inside the sim slot.
Read first: the research note section "iOS: how automation sends touches".
