# Gate: trajectory GPU cells

Specification: `lean/Fw/Gate/TrajectoryGpu.lean`. Golden: `packages/contracts/golden/gate/trajectory-gpu.jsonl`
(regenerate with `lake env lean --run scripts/TrajectoryGpuGolden.lean`, then its `--check`). JS twins:
`packages/gate-breakpoints/src/trajectory/cells-gpu.mjs`; the in-page recorder is `cells-gpu-page.mjs`.

## Grades

- A unit grades E, Q (one frame of shift), L, or not comparable (`null`, no grade). A rep grades by its worst part:
  E < E1 < Q < L.
- A same-code (A/A) run must grade E in every unit. Q or L on an A/A is recorder or tolerance noise, not a result.

## Not comparable

- A pain-dark unit whose base never flips in one direction (scrolling up or down) has nothing to compare in that
  direction. Its grade is `null`, and the unit is reported as not comparable, never E. Lean: `painDir_no_flip`,
  `painCell_no_flip_up`, `painCell_no_flip_down`.
- A null rep, or a unit with no reps, makes the unit not comparable the same way (`worst_none_mem`).

## Carousel swaps

- A swap series starts at the last frame before the first motion (`dropHold`, `rebase`) for the motion match. The hold
  (frames between the avatar insertion and the first motion, `holds`) is graded apart: `holdGrade` is E iff the base and
  cand holds of a swap pair differ by at most 1 frame, else L (A/A spread 1 frame: runs 39852684450, 39861846900); the
  swap rep grade is the worse of the motion and the hold grade.
- Settle and tail stop rules of the recorder (`carouselSample`): wait for a swap, then 6 equal frames, cap 2.2 s;
  after `ms`, record on until 6 equal frames, cap 1.5 s. Lean: `settleRun`, `tailRun`, golden kinds `settle`, `tail`.
  A test drives the page function with a scripted clock against those vectors.

## Panel effect

- Reference and candidate are compared as residuals against the declared effect (`residual`, `modelGrade`). The
  opacity model has a kink at m = 4/5, so interpolating a sparse reference across it is not a measurement of the
  candidate.
