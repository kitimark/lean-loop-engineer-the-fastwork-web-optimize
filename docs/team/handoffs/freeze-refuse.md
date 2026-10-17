# freeze-refuse handoff

**State:** done on branch `worktree-agent-ac0dd12d504a65088` (based on main `3aa3a5b`; commit trailer `Task: freeze-refuse`).
Gates: `lean/scripts/check-fast.sh` ok (build, `lake test`, goldens, math view lint; no Freeze warnings);
`pnpm --filter ./packages/measure-chromium test` 23/23; `node src/freeze.mjs <6 runs> --built-by 39049264131 --check` "identical".

**What changed**
- `lean/Fw/Measure/Freeze.lean`: `Job {name, frames, trajectory?}`; `RunTable` gets `jobs`. The old `freeze` is now `freezeTables`
  (`freezeTables_ok_iff` = old proof). New `freeze` = `freezeTables`, then `framesRefusal`: a run without jobs, or jobs (of any runs)
  with different frame counts, are refused; the message names every job whose count is not `modeOf` (most frequent, first on ties).
  Theorems: `freeze_ok_iff` (adds the two job conditions), `freeze_frames` (accepted => one frame count = `framesCommon`),
  `freeze_frames_differ`, `freeze_eq_framesMsg`, `framesRefusal_eq_none_iff`, `oddJobs_ne_nil`, `oddJobs_sound`, `trajectoriesEqual_iff`.
- Trajectory hashes are reported (`trajectoriesEqual`), not refused: touch A in the committed table has two trajectories at one frame
  count (`allTrajectoriesEqual: false`), so a refusal would break the table.
- Wire `measure.freeze`: runs need `jobs [{name, frames, trajectorySha256?}]`; reply adds `frames`, `trajectoriesEqual`.
- Goldens (`packages/contracts/golden/measure/measure.freeze.jsonl`): old cases get 3x409-frame jobs; new: 403-vs-409 (names
  `chromium-counts-rewrite-r2 of workflow run 39049478836`), odd first job + two odd jobs, run without jobs, missing `jobs`, touch trajectories.
- `packages/measure-chromium/src/freeze.mjs`: sends jobs (`counts.frames.length`, `meta.trajectorySha256`), prefixes refusals with
  `<profile>/<arm>:`, `allTrajectoriesEqual` from Lean. Test: `fakeRuns({ short: true })` refusal. README section "Update 2026-10-18".

**Checked (MEASURED 2026-10-18):** runs 39049471997, 39049478836, 39049481754 -> `swipe-touch-v1/rewrite: ... job
chromium-counts-rewrite-r2 of workflow run 39049478836 has 403 frames; 8 of 9 jobs have 409 frames`.

**Open**
- `measure.classify` is unchanged (missing frames read 0); the CI classify step still uploads a table for a short job. A refusal there
  would fail the workflow earlier; not done (its frame-mode callers and proofs assume arbitrary series). Lead's call.
- The `rule` text in `classes.frozen.json` does not mention the frame check (changing it breaks byte identity); add it at the next refreeze.
- Math view page (`docs/plan/loop-plan.html`) still lists the old `freeze` entries; page-writer regenerates.

**Read first:** `Freeze.lean` section "Jobs", then `opFreeze` in `Fw/Measure/Wire.lean`.
