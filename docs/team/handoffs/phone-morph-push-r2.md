# phone-morph-push-r2 handoff (WIP: phone session running)

branch: worktree-phone-morph-push-r2; worktree: .claude/worktrees/phone-morph-push-r2; last sha: `git log -1`; CI runs: none (no CI push in this task).
State: Lean Latin order + stage recorder fix + thermal before/after committed (5e6a0cd66). Phone session (16 visits, Serious) started; raw files
in `.local/phone/2026-10-27-r2/` (gitignored). Result, note, ledger, check.sh and dry land are still open.

## State
- Lean: `lean/Fw/Device/PhoneArms.lean` (`latinIdx`, `latinRows`, `latinOrder`, theorems `latin_*`), golden keys `latin`, `order`, `slots` in
  `packages/contracts/golden/device/phone-arms.jsonl`, twin `src/device-push.mjs` (`latinOrder`, `slotOf`, `pushCells`).
- Recorder: `FRAMES_START_JS` reads `data-fw-morph` when the inline `--morph` is empty (morph.stage writes it: `apps/site/src/parts/morph.stage/index.tsx:69`).
- Pin: `src/device-phone-pin.mjs` notes `pin.before` (just before the pin) and `pin.after` (last read-back after the clear).
- Reduce: `node src/device-push-cli.mjs reduce --dir <raw> --out results/phone/2026-10-27-morph-push-r2` (adds `positions`, per-cell `cells`).
- Run: `node src/device-push-cli.mjs run --site apps/site/dist/aot --dir <raw> --driver <driver dir> --pin Serious --all` (resumes done visits).

## Read first
`research/notes/2026/10-2x-phone-morph-push.md`, then this task's note `research/notes/2026/10-2x-phone-morph-push-r2.md` (when written).
