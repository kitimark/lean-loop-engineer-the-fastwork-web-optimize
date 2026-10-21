# image-arm-v2 handoff

Branch `worktree-wf_4ab15aff-5d3-2`, CI branch `ci/image-arm-v2`; measured tip 4e4a44d6 = gate-gaps run 39520488340 (success).
Read first: `research/notes/2026/10-21-image-arm-v2.md` (outcome, tables, engine-source answer).

## State
- Lean `lean/Fw/Measure/ImageArm.lean` (+ import in `lean/Fw.lean`, driver `lean/scripts/ImageArmGolden.lean`); golden
  `packages/contracts/golden/gate/image-arm.jsonl` (75 lines; under `gate/` so gate-breakpoints' declared reads cover it).
- `packages/gate-breakpoints/src/images/`: `armgen` (golden), `armplan` (TS twin), `armv2` (pipeline), `armdecide` (tables),
  `arm-probes.json` (22 probes, 3 shards); `arm-build.mjs` routes `arm run|decide`. Workflow: gate-gaps `images-pages`, `images-decide`.
- Result: 0 of 10 parts admissible under the exact policy (people.card shippedFails, people.carousel lookChange, 8 noCopy).

## Verified
gate-breakpoints tests 426 pass; ci-paths 49 pass; runner land-inputs 55 pass; `lean/scripts/check.sh` green;
`armgen.mjs --check` up to date; CI run 39520488340 green (3 reps x 2 engines).

## Open items
- `lean/scripts/check.sh` has no job for this golden (outside my write list). Add:
  `job "image-arm golden check" lake env lean --run scripts/ImageArmGolden.lean --check ../packages/contracts/golden/gate/image-arm.jsonl`.
- people.carousel (exact) flipped between shippedFails (run 39506658971) and lookChange (39520488340): noisy baseline.
- Legacy `pages.mjs`, `verify.mjs`, `arm.mjs` stay (tests import them).
- Run 39513157760 lost a runner job (cancelled, no log); rerun was green.

## TS stand-ins (not proved)
`imgOf`, `whyFile` (report), `sizedOf` filter for fit, aggregation in `armdecide.mjs`. Decision, snapping, saving are Lean.

## Writes outside the task's list
`lean/Fw.lean`, `lean/scripts/ImageArmGolden.lean`, `packages/contracts/golden/gate/image-arm.jsonl`.

## Ledger-key rows for the lead
- image-arm-v2: 0 of 10 parts admissible (exact), CI 39520488340; decode memory only.
- 1:1: WebKit ImageQualityController.cpp:176@862f17d -> Default quality; Blink image_painter.cc:210@f842f52 snaps, no 1:1 branch;
  Skia sampling not read (INFERRED).

Push: `git branch -f ci/image-arm-v2 HEAD`, `git push origin ci/image-arm-v2`; message carries `[images-arm] [ci:gate-gaps]`.
