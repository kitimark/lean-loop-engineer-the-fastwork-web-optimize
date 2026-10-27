branch: worktree-phone-cols-probe; worktree: .claude/worktrees/phone-cols-probe; last commit: `git log -1`; CI runs: none (no CI push in this task).
state: probe variant, Lean session and the TS twin are committed; the 16-visit phone session was started (set cols, Serious, raw in `.local/phone/2026-10-27-cols/`); results, note, ledger note and dry land follow.

## What exists
- Probe: `morph.columns:probe-off` (kind probe, never in a preset): `apps/site/src/parts/morph.columns/{part.json,morph.module.css}`; registry test `apps/site/src/registry/probes.test.ts`; golden `packages/contracts/golden/preset/probes.jsonl` (from Fw.Preset.Gen).
- Lean: `lean/Fw/Device/PhoneArms.lean`, section "Column probe session": `colsArms`, `colsRows` (same index matrix `latinIdx` as r2), `cols_*` theorems, `colsContrasts`, `contrasts_differ_by_probe`, `cause` / `causes` (decided, overlap, withinSpread, unresolved), `takenOf` / `pushesOf` with `takenOf_le`; golden lines `colscons`, `colscause`, `coltrace`.
- TS twin: `packages/measure-webkit/src/device-push.mjs` (`COLS_*`, `colsOrder`, `causes`, `contrastOf`, `takenOf`), `device-push-run.mjs` (`TRACE_HOOK_JS` installs `window.__fwTakeTrace` in both lanes, `traceOf`, `contrastsOf`, `takeShareOf`), `device-push-cli.mjs --set cols`, tables in `device-push-tables.mjs`.
- TS stand-in: `traceOf` maps driver trace events to the 10 touches (take inside the touch window); the driver-level counts are the Lean `pushesOf`/`takenOf` twin.

## Run again
Build: `cd apps/site && node scripts/build.mjs --engine aot --configs none --config '' --config '?fw=morph.columns:probe-off' --config '?fw=morph.geom:on,morph.tween:geom-timed' --config '?fw=morph.geom:on,morph.tween:geom-timed,morph.columns:probe-off'`.
Run: `cd packages/measure-webkit && node src/device-push-cli.mjs run --set cols --site <abs>/apps/site/dist/aot --dir <abs raw> --driver <abs raw>/driver --pin Serious --all`; reduce: `node src/device-push-cli.mjs reduce --set cols --dir <raw> --out results/phone/2026-10-27-cols-probe`.

## Read first
`research/notes/2026/10-2x-phone-cols-probe.md` (once written), then `research/notes/2026/10-27-end-columns-probe.md` (the plan).

## Limits
Probe arm is never a preset; the flip look lacks the veil and the object-fit image model; fixed XCUITest swipe; Serious only; n = 4 per arm; no CI pushes.
