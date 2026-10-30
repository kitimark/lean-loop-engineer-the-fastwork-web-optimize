# threaded-subpixel-why (handoff)

## State
- Branch `worktree-wf_053cfe73-6c8-1`; the last commit is in `git log -1` on that branch. No CI run, no push.
- Answer: `research/notes/2026/10-31-threaded-subpixel-why.md`. WebKit computes the view-timeline time in float32
  and the `contain` start in double. At scroll 0 the card is active at p = 1/(100·2^17), so translate = p × scatter
  (≤ 1e-4 px). This is a numeric artifact and no pixel moves.
- Lean: `lean/Fw/Parts/HeroExitSubpixel.lean`, imported in `lean/Fw.lean`. `check.sh` is green through the slot.
- `residue_le_max`, `residue_lt_gateTol` and `residue_level_change_lt` take `-48 ≤ a ≤ 48` and are
  two-sided; `timeline32_ratio`/`start64_ratio` tie the 1/3 literal to `ratio v`. Claims lint: 0 warnings.

## Verified
- WebKit 862f17d cites are in the note: ScrollTimeline.cpp:383-397, ViewTimeline.cpp:503-646,
  WebAnimationTime.cpp:165-171, AnimationUtilities.h:111-122, WTF dtoa.cpp:130-147.
- MEASURED on the artifact of run 41087718575: all 1408 differing components fit scatterPx × 1/13107200.

## Open
- Gate: the same 1e-6 residue on the hero copy and cue `transform`/`filter` passes, while the card `translate`
  fails. That comparison path in `packages/gate-breakpoints` is not read yet.
- Whether the gate gets a length tolerance backed by `residue_lt_gateTol` is the lead's call; this task made no
  gate change.
- Blink's view-timeline range math is not read; the 1 µs snap (timing_calculations.cc:95-101) is the INFERRED
  reason Chromium reads 0.

## Conventions
- The Lean file copies no numbers by hand: scatter comes from HeroOrbit/HeroDeck and the track from
  HeroExit.trackHeightPx. Proofs use `decide +kernel` or `grind`; there is no Mathlib.

## Read first
- The note's Answer section, then the Lean theorem table.
