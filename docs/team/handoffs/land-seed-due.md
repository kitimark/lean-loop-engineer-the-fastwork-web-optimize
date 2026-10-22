# land-seed-due handoff

State: branch worktree-wf_c027430e-c9e-1 (commits "land-seed-due: ..."). After a land that moved main, `fw land` prints
`PUSH-DUE <n>` when main is more than 5 Lake-key paths ahead of origin/main; the lead scans and pushes.

Done and verified
- Lean `lean/Fw/Console/LandSpeed.lean` section (e): `seedReads` (the `hashFiles` globs of the setup-lean cache key),
  `seedPath`, `seedThreshold` = 5, `seedLag`, `seedDue`; theorems `seedDue_iff`, `seedDue_false_iff`, `seedDue_mono`,
  `seedDue_zero/five/six`, `seedLag_le`, `seedLag_eq_zero_iff`, `seedLag_cons_key`, `seedLag_cons_other`,
  `seedLag_append`; `#guard`s.
- Golden `packages/contracts/golden/console/land-speed.jsonl`: ops `landSpeed.seedDue` (0, 5, 6) and
  `landSpeed.seedLag` (4 cases). New `check.sh` stage `land-speed golden check` (the file had no Lean check before);
  a mutated golden fails it.
- `apps/runner/src/land.ts`: `SEED_READS`, `SEED_THRESHOLD`, `seedLag`, `seedDue` (TS mirror replayed against the
  golden), `unpushedLag` (git glue), option `unpushedLag` for tests; the two lines are the last result lines.
- `apps/runner/test/land-seed-due.test.ts`: golden replay, `SEED_READS` equals the action.yml key globs, real lands
  in a throwaway repo (6 -> PUSH-DUE 6, 5 -> none, lag counts earlier unpushed lands, no origin ref -> none).
- New declared read: `.github/actions/setup-lean/action.yml` in `PACKAGE_EXTRA_READS["apps/runner"]`.
- Docs: `docs/team/tools/land.md` section "PUSH-DUE".
- `check.sh` green on CI, run 39706622221 (stage `land-speed golden check` 0.4 s). apps/runner: tsc and the full
  vitest suite green (86 files, 2407 tests, `--maxWorkers=2`); `ci-paths.test.mjs` green; dry land `VERDICT dry`.
  The local slot was stalled on stale swap (inc-slot-stall), so these ran outside the slot.

Open (follow-ups)
- Under `fw land --queue` result lines go to stderr (`apps/runner/src/fw.ts`, not in this task's writes); a stdout
  `PUSH-DUE` there needs fw.ts.
- The lag counts files, not the import cone; a one-file change to a root module can rebuild more (accepted: approved
  metric and threshold).

Read first: `docs/team/tools/land.md` (PUSH-DUE section), `lean/Fw/Console/LandSpeed.lean` section (e).
