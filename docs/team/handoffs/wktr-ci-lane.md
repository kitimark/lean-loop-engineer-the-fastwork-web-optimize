# Handoff: wktr-ci-lane (WKTR lane, 3 signed CI runs)

State: branch `worktree-agent-a48e555c576e62627` (CI branch `ci/wktr-ci-lane`, workflow commit 82b0495; final commit
adds the freeze file and README). Signed runs 39054209180, 39058900156, 39061993891 (jobs 2, passes 3, `live,vt,vt-still`).

Read first: `packages/measure-wktr/README.md` ("Why the counts drift", "Results"), then `classes.frozen.json`.

Result: `live` 2 deterministic / 7 quarantined; `vt` 2 deterministic / 1 stable (styleInvalidations) / 6 quarantined.
`vt-still` not frozen (fwcore refuses: one of 18 passes had 103 frames, docH 5903 vs 5963). Drift = mostly harness
(page clock: vt cuts styleRecalcs k 78 to 31), then CSS animations on the engine's real clock (still cuts to ~14), residue
+-1 phase shift and extra layouts not attributed (INFERRED UI-process/decode timing).

Conventions: variants `live|vt` + `-warm -still -trace` (canonical order, `src/variants.mjs`); files
`counts-<variant>-<pass>.json`; one workflow run = jobs x passes; classes are fwcore only (`measure.classify` in CI,
`measure.freeze` via `src/freeze.mjs`). Freeze: `gh run download <id> --dir runs/<id>` x3, then
`FW_CORE_BIN=... node packages/measure-wktr/src/freeze.mjs runs/<a> runs/<b> runs/<c> --variants live,vt [--check]`.
freeze.mjs sends `jobs` to `measure.freeze`, so it needs an fwcore newer than this branch's base (main d5a90ac has no
`jobs` field; the freeze test and the CLI pass with the current main-checkout binary).

Workflow: dispatch only (`gh workflow run wktr.yml --ref ci/wktr-ci-lane -f jobs=2 -f passes=3 -f variants=...`); a push
to the branch starts a wktr push run: cancel it. With `jobs=1` download-artifact has no subdirectory (workflow handles it).

Open items:
- `src/reduce.mjs` stays a TS stand-in (deltas, undercount arithmetic, ev zero-fill): needs a Lean op + goldens.
- Attribute the layout/compositing residue (try hooks mode; image decode vs UI-process visible-rect messages).
- Why one vt-still pass was 60 px shorter (docH): not investigated.
- Re-sign `vt-still` or a `vt-warm` profile if wanted: 3 more workflow runs.
- GitHub API limit: poll CI no faster than every 120 s.
