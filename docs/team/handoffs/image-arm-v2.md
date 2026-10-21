# image-arm-v2 handoff

Branch `worktree-wf_4ab15aff-5d3-2`, CI branch `ci/image-arm-v2`. Measured tip 4e4a44d6 = gate-gaps run 39520488340 (success).
Read first: `research/notes/2026/10-21-image-arm-v2.md` (outcome, tables, engine-source answer).

## State
- Lean `lean/Fw/Measure/ImageArm.lean` (+ import in `lean/Fw.lean`, driver `lean/scripts/ImageArmGolden.lean`), golden
  `packages/contracts/golden/gate/image-arm.jsonl` (75 lines, under `gate/` so gate-breakpoints' declared reads cover it).
- `packages/gate-breakpoints/src/images/`: `armgen.mjs` (golden run/check), `armplan.mjs` (TS twin), `armv2.mjs` (per-probe
  pipeline), `armdecide.mjs` (tables), `arm-probes.json` (22 probes, 3 shards), `arm-build.mjs` routes `arm run|decide`.
- `.github/workflows/gate-gaps.yml`: `images-pages` (shards 1..3, ImageMagick, json artifact `images-arm-*`, exact-policy
  images `armimg-*` retention 3), `images-decide`; `images-verify` removed.
- Result: no part admissible under the exact policy (people.card shippedFails, people.carousel lookChange, 8 noCopy).

## Verified (local, before the report)
gate-breakpoints `node --test test/*.test.mjs` 426 pass; `scripts/ci-paths.test.mjs` 49 pass; apps/runner land-inputs 55 pass;
`sh lean/scripts/check.sh` green; `node src/images/armgen.mjs --check` up to date. CI: run 39520488340 green, 3 reps x 2 engines.

## Open items
- `lean/scripts/check.sh` has no job for this golden (file outside my write list). Add:
  `job "image-arm golden check" lake env lean --run scripts/ImageArmGolden.lean --check ../packages/contracts/golden/gate/image-arm.jsonl`.
- people.carousel exact flips between shippedFails (run 39506658971) and lookChange (39520488340): noisy baseline; a decision
  needs more reps or a settled baseline.
- Legacy: `pages.mjs`, `verify.mjs`, `arm.mjs` stay (tests import them); remove with their tests when nobody reads them.
- Run 39513157760 lost one runner job (cancelled, no log); rerun fixed it, not a code fault.

## TS stand-ins (not proved)
`imgOf` (reading -> Lean input), `whyFile` (report), `sizedOf` filter for fit, the aggregation in `armdecide.mjs`.
The decision, snapping and saving are Lean (twin checked against the golden).

## Writes outside the task's list (reported)
`lean/Fw.lean`, `lean/scripts/ImageArmGolden.lean`, `packages/contracts/golden/gate/image-arm.jsonl`.

## Ledger-key rows for the lead (not written by me)
- image-arm-v2: exact policy admissible parts = 0 of 10 (CI 39520488340); decode-memory saving only, no frame time.
- 1:1 question: WebKit ImageQualityController.cpp:176@862f17d returns Default quality (no copy shortcut);
  Blink image_painter.cc:210@f842f52 snaps dest rect, no 1:1 branch; Skia sampling not read (INFERRED).

## Conventions
Push `git branch -f ci/image-arm-v2 HEAD` then `git push origin ci/image-arm-v2`; commit message carries `[images-arm] [ci:gate-gaps]`.
