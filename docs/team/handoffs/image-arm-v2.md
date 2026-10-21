# image-arm-v2 handoff (final design round, round 3)
Branch `worktree-wf_4ab15aff-5d3-2` (CI branch `ci/image-arm-v2`). Final commit = the one that last touched this file; code and
note at 0e24c616 (decide code 0cb6552d). Measured at f3ee5ee0 = gate-gaps run 39527779967 (success), images-decide job 118996415162 (success).
Read first: `research/notes/2026/10-21-image-arm-v2.md`, then the generated companion `10-21-image-arm-v2-cells.md`.
## State
- Result at the 22 probe ids of arm-probes.json (lossless PNG32 copies): no part admissible. Exact: people.card and people.carousel
  shippedFails (both engines), 8 noCopy. Fit: lookChange morph.columns/morph.panel/people.card/people.carousel/people.deck, undecided hero.deck/exit/orbit.
- Against run 39520488340 (JPEG q95): exact people.carousel lookChange -> shippedFails; fit people.carousel WebKit shippedFails -> lookChange; rest unchanged.
- Tables in the note are `arm decide --splice` output over the run's artifacts, plus `--cells --out` companion, committed unedited; every
  section except Coverage equals the run's images-decide artifact (the note holds 6 of 7; Decoded saving is in the companion).
- Verified at the final tip: `git merge main` clean; gate-breakpoints `node --test` 464 pass 0 skip; ci-paths 52 pass; runner land-inputs 55 pass;
  `sh lean/scripts/check.sh` exit 0 ("check: all lean/ gates green"); golden: "image-arm golden: ../packages/contracts/golden/gate/image-arm.jsonl is up to date (91 lines)".
- Measurement-code diff `git diff --stat f3ee5ee0..HEAD -- packages/gate-breakpoints/src packages/visual-diff apps/site .github/workflows/gate-gaps.yml
  lean/Fw/Measure/ImageArm.lean ':(exclude)...armdecide.mjs' ':(exclude)...src/trajectory'` printed nothing.
## For the lead at land
- check.sh job line (outside my write list): `job "image-arm golden check" lake env lean --run scripts/ImageArmGolden.lean --check ../packages/contracts/golden/gate/image-arm.jsonl`.
- Approve the removal of the `images-verify` job from `.github/workflows/gate-gaps.yml` (replaced by images-pages + images-decide; the `arm verify` CLI path stays legacy).
- Ledger-key rows: `image-arm-v2`: no part admissible at the 22 probe ids, lossless exact copies, run 39527779967 @ f3ee5ee0, decide 0cb6552d;
  `image-arm-v2.vs-r1`: exact people.carousel lookChange -> shippedFails, fit people.carousel WebKit shippedFails -> lookChange (JPEG q95 run 39520488340);
  `image-arm-v2.1to1`: Skia tweak_sampling CONFIRMED (SkImageShader.cpp:473-484@95ee33d7), WebKit Skia port kLinear (GraphicsContextSkia.cpp:188-201@862f17d), WebKit DPR 2/3 integer matrix, GPU raster, CoreGraphics INFERRED.
## TS stand-ins (not proved as TS)
`armplan.mjs` and the decision in `armdecide.mjs` are twins checked against the 91-line Lean golden; unproved glue: `imgOf`, `whyFile`, grouping in `armdecide.mjs`.
## Writes outside the task's list
`lean/Fw.lean`, `lean/scripts/ImageArmGolden.lean`, `packages/contracts/golden/gate/image-arm.jsonl`, `.github/workflows/gate-gaps.yml`, `research/notes/2026/10-21-image-arm-v2-cells.md`.
## Open items (follow-ups, below the pinned unit)
46 of 68 width x DPR pairs and 24 probes at probed pairs unprobed; people.carousel flips between runs; GPU raster, CoreGraphics, frame time; legacy pages.mjs/verify.mjs/arm.mjs stay.
