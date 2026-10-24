branch: worktree-wf_85104618-090-1
worktree: .claude/worktrees/wf_85104618-090-1
last commit: 2b6100ecb (pushed to ci/device-replay; code at 3cd384e43)
CI runs: device-replay 40142598495 running (push 1 of 3, 6 legs one after the other, ~1.5 h); lean 40142598556 running
verified locally: lean check.sh green; site test 7423 pass (combo-scroll golden 48 rows through the reducer and the driver); measure-webkit 698 pass; runner 3471; ci-paths 56; site typecheck clean
open: CI result (user + passive arms: zero writes against a native scroll, zero no-finger reversals), research note, ledger note row, dry land, review gate
poll: pnpm -s fw ci wait 40142598495 (>= 120 s apart, free runners only); pushes left: 2 (git branch -f ci/device-replay HEAD; git push origin ci/device-replay; message needs [ci:device-replay])
read first: lean/Fw/Parts/ComboScroll.lean (Dlv, holds, arm_late_holds, arm_passive_quiet, waapi_pin_eq_base), apps/site/src/parts/morph.tween/end.logic.ts (hold, prevented), packages/measure-webkit/src/replay/combo-replay.mjs (PASSIVE_JS)
