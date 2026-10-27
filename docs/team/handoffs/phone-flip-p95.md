branch: worktree-wf_2e9d5616-8a3-1; worktree: .claude/worktrees/wf_2e9d5616-8a3-1; last sha: `git log -1`; CI runs: none (no CI push; the phone session 2026-10-28-flip is final, 16 of 18 visits).
state (round 2, graph r544): WebKit `Composite` is its own off-main kind `commitWait` (not main-busy); per-arm split regenerated; `over50Rate` visit cell in Lean `visitVals`/`pushMetrics`; note, attribution.json, tables.md regenerated.
verified: check.sh green; measure-webkit 987 tests; ci-paths 56; runner land-inputs 73; golden `phone-arms.jsonl` --check; plan lint 0 errors.
numbers (tl lane, over-50 frames not main-busy): base 424/424, geom 105/311, geom-timed 46/396; main-busy long frames are 99% `RecalculateStyles` in the flip arms. Over 50 per 100 per visit: 9.1, 11.3, 10.6, verdicts `same`.
open: no phone run for visits 16/17; the Serious pin clear is unconfirmed (user unlocks the phone; the next run or `pin-stop --dir` clears it); veil cost vs r2 stays INFERRED; the gate's handling of phone session ids is a follow-up.

## What exists
- Lean: `lean/Fw/Device/FlipAttr.lean` (`Work.commitWait`, `busyWorks` without it, `dominant` with branches commitWait/idle/busy, theorems `commitWait_not_busy`, `composite_not_busy`, `dominant_commitWait`, `dominant_idle`, `dominant_not_busy`; WebKit@862f17d Page.cpp:2587-2609 and RemoteLayerTreeDrawingArea.mm:357,431-448 cited in the module doc); `PhoneArms.lean` (`rate`, `pushMetrics` + `over50Rate`, `visitVals`, `visitVals_rate`, `flipIdx`); golden `packages/contracts/golden/device/phone-arms.jsonl` (kinds flipwork, flipattr with `wait`, fliptail, flipcons, pushvisit).
- TS twin: `packages/measure-webkit/src/device-flip-attr.mjs` (`WAIT`, `callerOf`), `device-push.mjs` (`rate`, `visitVals`), `device-push-tables.mjs`, `device-flip-report.mjs` (not-main-busy column, style invalidation callers).
- Result: `results/phone-flip-p95/{summary.json,attribution.json,tables.md}`; note `research/notes/2026/10-2x-phone-flip-p95.md`.
- TS stand-ins: `recsOf`, `framesOfVisit`, `attributeVisit` glue; `callerOf`; animation-snapshot owner mapping; report grouping and `positionCheck`; busy <= interval is a guard test only.

## Run again (reduce only, no phone)
`cd packages/measure-webkit && node src/device-push-cli.mjs reduce --set flip --dir <main checkout>/.local/phone/2026-10-28-flip --out ../../results/phone-flip-p95`. Raw lanes are gitignored in the main checkout.
Phone run: see the earlier sections of `phone-cols-probe.md`; `device-push-cli.mjs run --set flip ... --pin Serious --all`.

## Read first
`research/notes/2026/10-2x-phone-flip-p95.md`, then `research/notes/2026/10-2x-phone-morph-push-r2.md`.

## Limits
One session; n = 5 to 6 per arm; tl lane has the Timeline on; `RecalculateStyles` and `Composite` carry no element (the `setProperty` caller names no property); picture model base-unlike; look not judged.
