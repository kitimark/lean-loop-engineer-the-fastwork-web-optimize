branch: worktree-wf_2e9d5616-8a3-1; worktree: .claude/worktrees/wf_2e9d5616-8a3-1; last sha: `git log -1` (WIP parent d4aefd401); CI runs: none (no CI push in this task).
state: Lean flip order and attribution rule, TS twins, tl lane, report and the phone session are done and committed; 16 of 18 visits ran (base 6, geom 5, geom-timed 5); the flip arms are `better` only through the paint count, every frame-time cell is `same`. Raw in `.local/phone/2026-10-28-flip/` (gitignored).
verified: measure-webkit 987 tests pass; golden `phone-arms.jsonl` check; check.sh, ci-paths and runner land-inputs per the report.
open: phone is locked and reads Critical, the Serious clear is unconfirmed (user unlocks it; the next run or `pin-stop --dir` clears the pin); visits 16 (geom-timed) and 17 (geom) not run; the session is not a full Latin design.

## What exists
- Lean: `lean/Fw/Device/FlipAttr.lean` (`workOf`, `cuts`, `innerIdx`, `workTime`, `busy`, `dominant`, `lead`, `tailOf`); `lean/Fw/Device/PhoneArms.lean` section "flip session" (`flipIdx`, 18 visits, `flipGoldenLines`); golden `packages/contracts/golden/device/phone-arms.jsonl` (kind `flipcons`).
- TS twin: `packages/measure-webkit/src/device-flip-attr.mjs`, `device-push.mjs` (`FLIP_ARMS`, `flipOrder`, `flipSlotOf`, `flipOk`), `device-push-run.mjs` (`tlLane`, `ANIM_SNAPSHOT_JS`), `device-phone-run.mjs` (`*.tl.json`), `device-flip-report.mjs` (tables), `device-push-cli.mjs --set flip`.
- Result: `results/phone/2026-10-28-flip-p95/{summary.json,attribution.json,tables.md}`; note `research/notes/2026/10-2x-phone-flip-p95.md`.
- TS stand-ins: `recsOf`, `framesOfVisit`, `attributeVisit` glue; the animation-snapshot owner mapping; the report grouping and `positionCheck`; busy <= interval is a guard test only.

## Run again
Build the three arms (base, `?fw=morph.geom:on`, `?fw=morph.geom:on,morph.tween:geom-timed`) from main with `node scripts/build.mjs --engine aot --configs none ...` as in `phone-cols-probe.md`. Run: `cd packages/measure-webkit && node src/device-push-cli.mjs run --set flip --site <abs>/apps/site/dist/aot --dir <abs raw> --driver <abs raw>/driver --pin Serious --all`; reduce: `node src/device-push-cli.mjs reduce --set flip --dir <raw> --out results/phone/2026-10-28-flip-p95`. Probe the phone (lock, thermal) before a run; after killing a run also stop its xcodebuild child.

## Read first
`research/notes/2026/10-2x-phone-flip-p95.md`, then `research/notes/2026/10-2x-phone-morph-push-r2.md` (the no-veil session to compare with).

## Limits
One session; n = 5 to 6 per arm; heat forced 5 launches; the tl lane has the Timeline on (slower than the frames lane); `RecalculateStyles` and `Composite` carry no element; the picture model is base-unlike; the look is not judged; the veil cost against r2 is INFERRED.
