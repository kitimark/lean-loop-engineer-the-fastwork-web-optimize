branch: worktree-wf_ff911e21-2e3-1 (CI branch ci/geom-webkit-midflip)
worktree: .claude/worktrees/wf_ff911e21-2e3-1 (run `sh scripts/wt-prep.sh`, `pnpm install --offline --frozen-lockfile`)
last code commit: 0fae80336 (push 2); the note, ledger note and this handoff are in the next commit (see git log)
CI runs (workflow wktr, both complete, 3 jobs each): 40626070244 push 1 (d361cb6ca) success; 40629283336 push 2 (0fae80336) success. 2 of 3 pushes used.

Task: geom-webkit-midflip (graph r554). Which geom-timed tracks run accelerated mid-flip on WebKit, is any effect pending or ticking
continuously, ThreadedTimeBasedAnimationsEnabled in WKTR vs iOS Safari, recalcs per frame during the flip vs idle.

Verified (MEASURED run 40629283336, WKTR, not phone time): note research/notes/2026/10-2x-geom-webkit-midflip.md has the table. Pref ON: 55 running,
0 pending, 47 accelerated, 0 ticking at 30/50/80 %, Lean agrees 55/55. Pref OFF (phone default from source): second flip 47/0 in all jobs, every OFF job ticked rendered tracks on the main thread past mid-tween in the first flip (first commit late: after 49 %, after 81 % for 21 tracks, after 95 %); once the tween is active and before the first commit all 47 rendered tracks tick. Idle already has 2 recalcs + 1 invalidation per frame
with 0 elements, INFERRED from 4 sweepDoc CSS animations (no sweep-paused arm); flip frames 2 to 3.5 recalcs, creation frame up to 166 elements. Does not explain the phone's 348/396
alone (INFERRED). Next step: phone run with a sweep-paused probe; then task geom-sweep-compositor if style per long frame falls.
Built: Lean Fw.Parts.MorphTrackAccel (tick rule, classOf/readsAccelCls, theorems per branch, golden morph-track-accel.jsonl 317 lines, `--check` ok);
measure-wktr/src/mid-page.mjs (fork of gate-breakpoints track-accel-page.mjs with `P.mid`; merge back in a task owning both); modes mid and mid-thr-off;
src/midflip.mjs (TS STAND-IN; test/midflip.test.mjs has per-branch cases, no golden replay: needs the land.ts read of morph-track-accel.jsonl, add it later);
wktr.yml accel step `--modes mid,mid-thr-off`. Ledger note in research/findings/ledger.json (task geom-webkit-midflip).

Open: re-run check.sh and package tests on the committed tree, dry land, `fw review ready`. A push 3 is optional (more OFF first-flip samples to explain j2's
21 ticking tracks); lane check first (`pnpm -s fw ci push --branch ci/geom-webkit-midflip --lanes wktr --dry`), commit message must carry [ci:wktr] [accel].

Conventions: WKTR frame clock is slow (3-30 frames per 700 ms), so samples are by animation phase. Nothing here is phone time. iOS pref default (false) is
from source (UnifiedWebPreferences.yaml:8557-8570@862f17d), not a shipped build. Analysis scripts are in the session scratchpad only (not committed).
Read first: the note, lean/Fw/Parts/MorphTrackAccel.lean (end), packages/measure-wktr/src/midflip.mjs, research/notes/2026/10-2x-phone-flip-p95.md.
