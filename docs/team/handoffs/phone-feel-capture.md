# Handoff: phone-feel-capture

- Branch `worktree-wf_3521dc2c-a1c-1`; worktree `.claude/worktrees/wf_3521dc2c-a1c-1`; last code commit 5c7487ae8.
- CI runs: none (the capture needs the phone; no push).
- Verified: check.sh green (init-cost lint fixed: `captureLines` is a function of Unit); measure-webkit tests 1033/1033; `scripts/ci-paths.test.mjs` 56/56; runner land-inputs 73/73; plan lint 0 errors; recorder smoke-run in desktop Chrome (not a result).
- Open: the phone dry run was NOT run: phone paired but not on USB at the start and the end (ping, idevice_id, ioreg). Plug it in, unlock it, run `device-feel-dry.mjs` (command in the note).
- Read first: `research/notes/2026/10-2x-phone-feel-capture.md` (fields, definitions, defects fixed, limits).

## State
- Lean: `lean/Fw/Device/FeelCapture.lean` (counts: long frames, pin fights, re-targets, blinks, top zone), `Feel.lean`
  (Capture record, summary, `measured`, `flagOf`, `jointWith`, `closeCause`, six fresh letters), `Thermal.lean`
  (`termGate`, `droppedClear`, `endVerdictDrop`, `conditionSetDrop`, `recoverActD`, `fallbackAct`); goldens
  `packages/contracts/golden/device/feel.jsonl` (59 lines) and `thermal.jsonl` are generated, never hand-edited.
- TS twins: `device-feel-cap.mjs` (counts, joint, `jointText`), `device-thermal-pin.mjs` (drop rules, `ConditionOwner`
  waits for the set ack), `wip-close.mjs` (`closeCause`, message), `device-phone-pin.mjs` (drop end verdict).
- Glue: `device-feel-capture.mjs` (page recorder `CAP_START_JS`, Timeline, `inputsOf`, raw `visits/NN-<label>.json`),
  `device-feel-run.mjs` (capture per visit; `rate` and `stop` end it; `stopFallback`), `device-cli.mjs` (`--seed` required,
  tables printed on every end), `device-feel-dry.mjs` (scripted-swipe drive for the dry run).

## Conventions
- A capture failure never ends the session: the visit stays unmeasured and `feel.json` log names the error.
- Compare captured visits with captured visits only (the Timeline is on during a visit).
- Arms are not built in git: build them with the command in the kit note; run `pnpm install --offline --frozen-lockfile` in a fresh worktree first.

## Limits
- Scripted swipe, not the user; Serious induced; USB-drop handling unit-tested only; n = 2 per same-look arm; no CI.
- The work-graph `writes` of this task omit `Thermal.lean`; dry land passes only with `--allow lean/Fw/Device/Thermal.lean`
  (`VERDICT dry phone-feel-capture`). The lead adds `Thermal.lean` and `thermal.jsonl` to `writes` on main, or lands with `--allow`.
