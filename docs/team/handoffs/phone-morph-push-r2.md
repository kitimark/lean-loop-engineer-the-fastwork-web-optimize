# phone-morph-push-r2 handoff (decided on the phone, Latin-square order)

branch: worktree-phone-morph-push-r2; worktree: .claude/worktrees/phone-morph-push-r2; last sha: `git log -1`; CI runs: none (no CI push in this task).
Verified: 16 phone visits (4 per arm, every arm in every position once, Serious held in all 36 readings, first attempts), reduced into
`results/phone/2026-10-27-morph-push-r2/`; Lean labels: geom worse (style count only), geom-timed same, stage worse. Check green, measure-webkit,
runner, ci-paths, ledger tests green. Check, tests and dry land: see the report.
Open: nothing for the user; the felt-smoothness verdict and the class L look review stay the user's.

## State
- Lean: `lean/Fw/Device/PhoneArms.lean` (`latinIdx`, `latinRows`, `latinOrder`, theorems `latin_*`); golden keys `latin`, `order`, `slots`; twin
  `packages/measure-webkit/src/device-push.mjs` (`latinOrder`, `slotOf`, `pushCells`).
- Recorder reads `data-fw-morph` for morph.stage (`device-push-run.mjs:39`); `pin.before` and `pin.after` come from `device-phone-pin.mjs`.
- Reduce: `node src/device-push-cli.mjs reduce --dir <raw> --out <results>` adds `positions` (by position and by round) and per-cell verdicts.
- Run again: `node src/device-push-cli.mjs run --site apps/site/dist/aot --dir <raw> --driver <driver dir> --pin Serious --all`; 16 visits took about 42 min.
  The site build is `pnpm build` in `apps/site`. Raw files stay in `.local/phone/2026-10-27-r2/`.

## Read first
`research/notes/2026/10-2x-phone-morph-push-r2.md` (table, position check, heat, limits).

## Limits
Fixed XCUITest swipe; Serious only (the phone read Critical after the clear: its own heat); n = 4; `positionCheck` is a TS reducer (stand-in); no CI pushes.
