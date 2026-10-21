# Handoff: earn-look-review-webkit (split B of earn-transition-retarget)

State: branch `worktree-wf_e007c264-660-1`, CI ref `ci/earn-look-review-webkit`. Delivered: macOS Playwright WebKit frame strips,
faithful vs `?fw=nav:earn-no-transition`, 390 and 1280, open and close, screenshot and screencast sources.

Verified (MEASURED): CI run 39530106935 (commit 494c6db2, macos-26, job probe-apple, `[ci:trajectory-probe] [frames:nav:earn-no-transition]`)
passed. All 8 strips usable (min(shots.faithful, shots.flag) >= 10, 18 to 35 shots per arm, 3 repeats pooled), identity ok. Run 39529343997
(one repeat) gave 4 to 10 shots, none usable: the runner takes 130 to 300 ms per screenshot. Artifacts `frames-apple-390`,
`frames-apple-1280`, expire 2026-11-20. Indexed in `results/earn-look-review/index.json` (run, artifact, path, source, reps, shots, usable).
Local tests: gate-breakpoints (446 + 6 new in `test/frames.test.mjs`), ci-paths 52, land-inputs 55; `lean/scripts/check.sh` green.

Design: no new macOS job (Lean `Fw.Ci.Pool.Caps.rows_files_nodup`); a frames step in `probe-apple` on a push whose message has `[frames:`
(walk and merge-apple skipped). `Intent.macosFiles` gained `trajectory-probe.yml`; `golden/ci/intent.jsonl` regenerated.
Tool doc: `docs/team/tools/trajectory-frames.md`. Read first: that doc, then `packages/gate-breakpoints/src/trajectory/frames.mjs`.

TS stand-in: `usable` in `frames.mjs` (Lean `Fw.Gate.Frames.usable`, same cases in the test). Writes beyond the graph writes:
`lean/Fw/Gate/Frames.lean` (new), `lean/Fw.lean` (import), `lean/Fw/Ci/Intent.lean`, `packages/contracts/golden/ci/intent.jsonl`,
`packages/gate-breakpoints/src/engines.mjs` (`screencast`), `.github/workflows/trajectory-probe.yml`, `docs/team/tools/trajectory-frames.md`.

Open for the lead (not edited by me):
1. `research/findings/ledger.json` row `nav.earn.noTransition`: `webkit` stays "unknown" (no counters); in `missingWhy` replace the
   "WebKit look-review strips: Linux ... task earn-look-review-webkit" item with: "WebKit look-review strips: macOS Playwright WebKit,
   run 39530106935, artifacts frames-apple-390 and frames-apple-1280 (expire 2026-11-20), 8 strips all usable (18 to 35 shots per arm,
   3 repeats pooled); accepted limit: not Safari on a phone". In `next` drop "stays pending until task earn-look-review-webkit delivers
   WebKit strips"; in `userDecision.review` add the run and artifacts.
2. `lean/Fw/Preset/Gen.lean` `lookDecisions` (~line 303): webkit material `pending` with `task := some "earn-look-review-webkit"`
   to ready with run 39530106935 and the artifact names; regenerate the golden JSON (~line 685) and the look-change candidates.
3. Linux `frames` job still also runs on a frames push (unchanged). Copy the strips into the lead's private review page before 2026-11-20.

Conventions: PNGs stay CI artifacts, never in git. Index regenerated from the run's `strips/index.json` per artifact.
