# react-root-quiet-events handoff

- Branch `worktree-wf_9787e251-d23-1`, worktree `.claude/worktrees/wf_9787e251-d23-1`, CI branch `ci/react-root-quiet-events`; last commit = `git log -1`.
- CI runs: `40122201939` trajectory-probe (push 1, 66be821dd, `fw=engine.events:quiet debug=root-events diagnostic`) success, recorder rows in `results/react-root-quiet-events/probe-40122201939.json`; `40122202078` lean success. Push 2 (final code, same probe line) id: see `gh run list --branch ci/react-root-quiet-events`.
- Verified: `lean/scripts/check.sh` green before the check.sh job for the generated table was added; site, gate-breakpoints and runner package tests green; `tsc` green; ci-paths test green; `part-footprint.mjs --check` green; `fw plan lint` has no writesClosure line for this task.
- Open: the lead's dispatches (WebKit Simulator before/after x3 and the breakpoint gate with the flag), commands in the report.

## Design
- Lean `Fw.Parts.ReactRootOpt`: `regs` = what react-dom 19.3.1 registers on a root (87 types, 142 listeners), `quietRegs` drops the 7 animation/transition types. Theorems `quiet_none`, `quiet_keeps`, `handled_stays`, `orig_registers`, `quiet_drops`, `records_*`. Generated `quiet.gen.ts` is checked by the check.sh job "react-root-quiet golden check".
- Golden `packages/contracts/golden/parts/react-root-quiet.jsonl` replayed by `apps/site/src/parts/engine.events/quiet.golden.test.ts` against the real react-dom `createRoot` on a recording container.
- Flag `engine.events:quiet`: `quietContainer(#root)` in `entry-client.tsx` gives the container an own `addEventListener` that drops the 7 types. `quiet.scan.test.ts` checks the premises over the files entry-client reaches.
- Recorder `fw-debug=root-events` (apps/site/src/debug/root-events.ts), trajectory-probe debug name added in `Fw.Ci.Trigger` (`probeDebugs`), `.github/scripts/trajectory-line.mjs`, `packages/gate-breakpoints/src/trajectory/debug.mjs`.
- WebKit: one EventDispatch per (node, phase) with a listener, `EventTarget.cpp:313-357@862f17d`; read the note `research/notes/2026/10-20-react-root-quiet-events.md` first.
