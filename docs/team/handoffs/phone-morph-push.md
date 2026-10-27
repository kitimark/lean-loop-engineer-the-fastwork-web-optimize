# phone-morph-push handoff (round 3: decided on the phone)

branch: worktree-phone-morph-push; worktree: .claude/worktrees/phone-morph-push; last sha: `git log -1`; CI runs: none (no CI push needed).
Verified: 12 phone visits (3 per arm, interleaved, Serious held in all 27 readings, first attempts), reduced into
`results/phone/2026-10-27-morph-push/`; labels from the Lean twin: geom-timed better, geom mixed, stage worse. Check, tests, dry land: see the report.
Open: nothing for the user; the felt-smoothness verdict and the class L look review stay the user's.

## State
- Lean rule/golden/twin: `lean/Fw/Device/PhoneArms.lean`, `packages/contracts/golden/device/phone-arms.jsonl`, `src/device-push.mjs`.
- I/O (no decisions): `src/device-push-run.mjs` (lanes, `pushVisit`, `driverHolder`, `summarize`), `device-push-cli.mjs`
  (`plan`, `run`, `reduce`), `device-push-tables.mjs`, `device-push-chan.mjs`; `runBlock` in `device-phone-run.mjs` takes arms/values/visitS.
- Cause of the round-2 hang: the Simulator driver's file channel cannot work on a real phone (runner sandbox). `device-push-chan.mjs`
  embeds a phone PushServer (requests = files in its Documents container via `xcrun devicectl device copy to`, answers = `FWPUSH`
  marker lines in the xcodebuild log). Do not edit `src/throttle/driver/**` (task morph-push-sim).
- Run again: `node src/device-push-cli.mjs run --site ../../apps/site/dist/aot --dir <raw> --driver <driver dir> --pin Serious --all`,
  then `reduce --dir <raw> --out <results>`. Raw files stay in `.local/phone/2026-10-27/`.

## Read first
`research/notes/2026/10-2x-phone-morph-push.md` (table, cause, limits).

## Limits
Fixed XCUITest swipe, not the user's finger path; Serious only; n = 3 per arm; stage's morph is not read by the recorder
(`data-fw-morph`, not `--morph`), so its spans end at the last scroll change; no CI pushes.
