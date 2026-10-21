# Handoff: earn-look-review-webkit (split B of earn-transition-retarget), round 2

State: branch `worktree-wf_e007c264-660-1`, CI ref `ci/earn-look-review-webkit`. Delivered: macOS Playwright WebKit frame strips,
faithful vs `?fw=nav:earn-no-transition`, 390 and 1280, open and close, screenshot and screencast sources.

Verified (MEASURED): CI run 39530106935 (commit 494c6db2, macos-26, job probe-apple, `[ci:trajectory-probe] [frames:nav:earn-no-transition]`)
passed. All 8 strips usable by min(shots.faithful, shots.flag) >= 10 (18 to 35 shots per arm, 3 repeats pooled), identity ok. Timing: only the
4 screenshot strips are time-aligned between rows; the 4 screencast strips have a per-row clock offset (labels trail the in-page recorder by
150 to 450 ms), so they show the frame sequence within one row only. Run 39529343997 (one repeat) gave 4 to 10 shots, none usable.
Artifacts `frames-apple-390`, `frames-apple-1280`, expire 2026-11-20. Indexed in `results/earn-look-review/index.json`.
Local tests: gate-breakpoints 447 (441 + 6 new in `test/frames.test.mjs`), ci-paths 52, land-inputs 55; `lean/scripts/check.sh` green.

Design: no new macOS job (Lean `Fw.Ci.Pool.Caps.rows_files_nodup`); a frames step in `probe-apple` on a push whose message has `[frames:`.
`Intent.macosFiles` gained `trajectory-probe.yml`; `golden/ci/intent.jsonl` regenerated. Read first: `docs/team/tools/trajectory-frames.md`,
then `packages/gate-breakpoints/src/trajectory/frames.mjs`. TS stand-in: `usable` in `frames.mjs` (Lean `Fw.Gate.Frames.usable`).
Writes beyond the graph writes: `lean/Fw/Gate/Frames.lean`, `lean/Fw.lean`, `lean/Fw/Ci/Intent.lean`, the intent golden, `engines.mjs`
(`screencast`), `.github/workflows/trajectory-probe.yml`, the tool doc.

Open for the lead (not edited by me):
1. `research/findings/ledger.json` row `nav.earn.noTransition` (`webkit` stays "unknown"): in `missingWhy` replace the Linux strips item with
   "WebKit look-review strips: macOS Playwright WebKit, run 39530106935, artifacts frames-apple-390 and frames-apple-1280 (expire 2026-11-20):
   4 screenshot strips (time-aligned, 18 to 31 shots per arm) and 4 screencast strips (per-row clock offset, not time-aligned between rows),
   all usable by min shots >= 10, 3 repeats pooled; accepted limit: not Safari on a phone". Drop the "stays pending" text in `next`; in
   `userDecision.review` add run and artifacts, name the 4 screenshot strips as the review material.
2. `lean/Fw/Preset/Gen.lean` `lookDecisions` (~line 303): webkit material `pending` to ready with run 39530106935; review material is the 4
   screenshot strips (`*-open.png`, `*-close.png` per width); regenerate the golden JSON and look-change candidates.
3. Linux `frames` job still runs on a frames push. Copy the strips to the private review page before 2026-11-20.
4. Follow-up (not done): `usable` is recorded, not enforced by CI; set `process.exitCode = 3` in `strips()` when any strip is unusable and
   name it in the tool doc.
