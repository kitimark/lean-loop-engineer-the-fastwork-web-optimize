# react-root-quiet-events handoff

- Branch `worktree-wf_9787e251-d23-1`, worktree `.claude/worktrees/wf_9787e251-d23-1`, CI branch `ci/react-root-quiet-events`; last commit = `git log -1`.
- CI runs: push 1 (66be821dd) trajectory-probe: pending (id to be filled by `fw ci wait --branch ci/react-root-quiet-events --workflow trajectory-probe`).
- Verified locally: `lake env lean Fw/Parts/ReactRootOpt.lean` clean; site vitest for `parts/engine.events` and `debug/root-events` green; `tsc --noEmit` green; trajectory-line and debug node tests green; `part-footprint.mjs --write` and `Fw.Preset.Gen.run []` regenerated.
- Open: check.sh, site/runner test scripts, land dry, the CI counts (webkit-sim dispatches are the lead's).

## Design
- Lean `Fw.Parts.ReactRootOpt`: `regs` = what react-dom 19.3.1 registers on a root (87 types, 142 listeners, from `listenToAllSupportedEvents`), `quietRegs` drops the 7 animation/transition types. Theorems: `quiet_none`, `quiet_keeps`, `handled_stays`, `orig_registers`, `quiet_drops`, `records_*`.
- Golden `packages/contracts/golden/parts/react-root-quiet.jsonl` replayed by `apps/site/src/parts/engine.events/quiet.golden.test.ts` against the real react-dom `createRoot` on a recording container.
- Flag `engine.events:quiet`: `quietContainer(#root)` in `entry-client.tsx` gives the container an own `addEventListener` that drops the 7 types. `quiet.scan.test.ts` checks the premises over the files entry-client reaches (no handler prop, no MUI input, no portal, hand listeners only on their own targets).
- Recorder `fw-debug=root-events` (apps/site/src/debug/root-events.ts) counts watched registrations and window-level dispatches; the trajectory probe saves it in `runs[].morph.debugReps`.
- WebKit: one EventDispatch per (node, phase) that has a listener, `EventTarget.cpp:313-357@862f17d`; events are enqueued and dispatched whether or not a listener exists (`StyleOriginatedAnimation.cpp:390-412@862f17d`).
