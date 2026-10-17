# proof-pain-notes handoff

State: `lean/Fw/Parts/PainNotes.lean` (imported in `lean/Fw.lean`), golden `packages/contracts/golden/engine/pain-notes.jsonl`
(20 rows, variant `rewrite+?fw=pain.notes:visible`, base `rewrite`). `sh lean/scripts/check.sh` green. Commit: see `git log` on
this worktree branch ("pain.notes: ...").

Read first: the module docstring of PainNotes.lean (snapshot citations `2.DyWL8TcE.js` pretty 4409-4796, CSS 2344).

Corrections to the task wording (CONFIRMED from the snapshot):
- `.pain-notes{display:none}` at ≤ 860 px hides an empty stage div; the notes render in `.pain-canvas`, which stays shown.
  The ≤ 860 E claim holds because `le` returns before any write (JS 4595), proved without a premise (`narrow_tick_id`, `narrow_run_eq`).
- The interval is `setInterval(le, 3e3)`: 1/3 Hz (20 ticks/min, `ticksPerMinute`), not 33 Hz.
- The original already disarms when IO ratio < 0.12; the variant's new gates are `narrow` and `covered` (`armed`).

Theorems: E `tickO_idle`, `tickV_eq`, `pain_run_eq`, `pain_prefix_eq`, `pain_visSame`; bands `narrow_tick_id`, `narrow_run_eq`,
`wide_armed_iff`; phase `resumeAt_on_grid`, `resumeAt_ge`, `resumeAt_least`, `resume_grid`, `naive_rearm_shifts`;
work `hiddenTick_le`, `hiddenTick_lt`, `frames_le`, `idle_zero`, `cr_idle_tick`, `wk_idle_tick`.

Open premises (hypotheses or model conventions, not axioms):
- `CovOk`: at a clearing tick the original's `T` is already empty (`d`, JS 4728-4731, clears it per frame).
- Gate fidelity: the variant decides with the context `le` reads; gap of < 1 frame between a resize and the MQ `change`
  event (fix: re-check in the `change` listener before paint).
- Phase: the variant re-arms at `resumeAt` (original's grid). Chromium snaps repeats to the grid (timer.cc:150-161@f842f52);
  WebKit re-bases on actual fire time (ThreadTimers.cpp:126-127@862f17d), so drift while disarmed is not reproduced.
- Random draws: the variant's ticks get the original's draws (skipped ticks draw nothing, JS 4591-4603).
- WebKit model pays `commit` on a script-only frame (`base := [.commit]`), hence Composite `≤o`.
- The rewrite has no pain notes yet (apps/site/src/parts/pain is a shell); the golden rows wait on that port.
