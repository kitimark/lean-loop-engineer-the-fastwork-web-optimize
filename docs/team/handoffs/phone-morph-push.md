# phone-morph-push handoff (round 2: partial, phone driver blocked)

branch: worktree-phone-morph-push; worktree: .claude/worktrees/phone-morph-push; last sha: `git log -1`; CI runs: none (no CI push needed).
Verified: Lean push-visit rule + golden + TS twin + 8 tests (commits cd3b0a811, 20d1c2181); unit undecided, 0 visits. Open: see below.

## Open (one user step)
Phone: Settings > Developer > turn on Enable UI Automation (keep it unlocked). Then restart the task.

## State
- Lean: `lean/Fw/Device/PhoneArms.lean` push section (pattern, visitSteps, windows/morphEnd, tail stats, counts lane, `visitVals`,
  `pushRounds`, `pushOk`, `noRepeat`, `pushLabel`); golden `packages/contracts/golden/device/phone-arms.jsonl` (regenerate with
  `lake env lean --run scripts/PhoneArmsGolden.lean` in lean/); twin `packages/measure-webkit/src/device-push.mjs`, test `device-push.test.mjs`.
- Phone (MEASURED): the certificate is trusted and the XCUITest run starts, but the first accessibility snapshot never returns
  (Safari, restarted Safari, SpringBoard; 4-7 min each). No push ran, no thermal pin set, nothing induced. Logs in
  `.local/phone/2026-10-27/` (gitignored). Results: `results/phone/2026-10-27-morph-push/`; note `research/notes/2026/10-2x-phone-morph-push.md`.

## Next, once a driver answers
1. `buildDeviceDriver` (src/device-xcui.mjs), `startServer` (src/touch-push.mjs, HOLD_MS fixed per start), expect `ready`.
2. Write `src/device-push-run.mjs`: a push visit as `deps.visit` of `runBlock` (src/device-phone-run.mjs) with `pin` Serious
   (device-thermal-pin.mjs), session = `pushRounds()` from device-push.mjs; frames pass (rAF recorder) and counts pass
   (Timeline, no rAF recorder), `go-<n>` files per `visitSteps`; feed `columns`/`pushLabel`.
3. Raw to `.local/phone/<date>/`, then summary.json, tables.md, note, ledger row, check.sh via fw slot, dry land.

## Conventions
Team id from the keychain at run time (never committed). Kill only PIDs this task started. The push is a fixed XCUITest swipe,
not the user's recorded finger path. If the switch is on and it still hangs, a driver change (src/throttle/driver/UITests) is outside this task's writes.
