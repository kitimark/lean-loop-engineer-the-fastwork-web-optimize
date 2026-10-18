# gate-exit-verdict (handoff)

State: branch worktree-agent-a76c54864e94895dc (commit in the report). `cli.mjs summary` now prints one verdict line per engine
and exits 0 only when every judged engine passed.

Read first: `lean/Fw/Gate/Exit.lean` (rule, theorems, golden lines), `packages/gate-breakpoints/src/cli.mjs` (TS stand-in at the top),
`packages/gate-breakpoints/test/exit.test.mjs`.

Rule (Lean `Fw.Gate.Exit`): engine verdict = fail if any table cell fails; else unsettled if some reachable probe did not settle on an
arm; else pass if some cell passed; else notRendered. `exitCode` = 0 iff at least one engine was judged and all passed.
Proved: exit_zero_iff, exit_ne_zero_of_fail / _of_unsettled / _of_notRendered, engineVerdict_pass_iff, engineVerdict_fail,
engineVerdict_unsettled_ne_pass, exit_ne_zero_of_fail_cell.
not-comparable cells and not-run blocks are ignored (green runs have them: matchMedia "=Lean" on fractional-gaps; blocks a narrowed run skips).

Conventions: `cli.mjs` only runs its commands when it is the entry point (`import.meta.url` check), so the test imports the reducers.
Golden `packages/contracts/golden/gate/exit.jsonl` was generated from `Fw.Gate.Exit.goldenLines` with a scratch `lake env lean --run`
file (`def main := for l in goldenLines do IO.println l`); it is not wired into `breakgen` (BreakgenMain.lean was outside the write list).

Open items:
- TS stand-in (engineVerdict/exitCode in cli.mjs) is temporary: replace by an fwcore op, and unify `EngineVerdict` with `Fw.Gate.Settle`
  when gate-settle lands (TODO in Exit.lean; `unsettled` becomes the settle state instead of the count of unsettled probes).
- WORKFLOW (gate-speed-ci owns `.github/workflows/breakpoint-gate.yml`): the summary step does NOT mask the exit code (`set -euo pipefail`,
  line 281 `node packages/gate-breakpoints/src/cli.mjs summary --out "$out"`). With the new exit the step now fails and lines 282-286
  (sha256, GITHUB_STEP_SUMMARY) are skipped, and the upload step (line 287, `gate-merged-*`) is skipped too, so the artifact is lost.
  Change: line 281 -> `rc=0; node packages/gate-breakpoints/src/cli.mjs summary --out "$out" || rc=$?`; after the `} >> "$GITHUB_STEP_SUMMARY"`
  block add `exit "$rc"`; add `if: ${{ !cancelled() }}` to the upload-artifact step at line 287.
- Mistake-retro readers (`gate-merged-*/summary.json`) keep working only after that workflow change.
