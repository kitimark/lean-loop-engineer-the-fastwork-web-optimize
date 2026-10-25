branch: worktree-wf_85104618-090-1
worktree: .claude/worktrees/wf_85104618-090-1
last commit: see git log (round 2: registry conflict; no new CI push, the conflict changes no runtime path of the 8-flag arms)
CI runs: device-replay 40142598495 success (push 1 of 3; 2 left unused); lean 40142598556 success
verified: lean check.sh green; site test 7423 pass (combo-scroll golden 48 rows through the reducer and the driver); measure-webkit 698; runner 3471; ci-paths 56; site typecheck clean
result (MEASURED, run 40142598495): user flags and user+passive, 11 of 11 replays each: 0 writes against a native scroll, 0 no-finger reversals, 0 script jumps; the build before (13f319e2a) also 0, so the replay does not discriminate old from new rule (reopen moves are non-cancelable); Lean and the driver test do
open: phone re-check by the user; toolbar-resize fight y~1859 (out of scope); a profile whose reopen is a cancelable first move would discriminate (follow-up)
conventions: held := Event.defaultPrevented after the handler (Lean Dlv/holds, TS end.logic hold + driver move); golden only from lean/scripts/ComboScrollGolden.lean; waapi and waapi-scoped cannot be picked with morph.end.release:on (registry conflict; Lean Fw.Parts.ComboScroll.decided_no_release_waapi); +allpassive arms (all-passive harness, were +passive in the run) = PASSIVE_JS in combo-replay.mjs
read first: research/notes/2026/10-2x-combo-held-identity.md, lean/Fw/Parts/ComboScroll.lean, apps/site/src/parts/morph.tween/end.logic.ts

round 2: waapi_* theorems removed from ComboScroll.lean; arms renamed +allpassive; check.sh, site 7721, console-api 782, measure-webkit 698, runner 3471, ci-paths 56 green
writes outside the graph row: none
