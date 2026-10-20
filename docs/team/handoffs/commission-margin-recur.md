# Handoff: commission-margin-recur (closed as a finding)

State: prose only. The branch holds the note `research/notes/2026/10-20-commission-margin-recur.md` (status finding) and
this handoff; no gate, Lean or site code. The earlier code branch `worktree-wf_9961f6d6-6b3-1` at 68e07807 is not merged.

Cause: read path CONFIRMED (Blink file:line@f842f52), trigger INFERRED. A used auto margin is layout output of the container's
pass. A box in a `content-visibility:auto` skipped subtree with no container pass that wrote its margins reads the zero strut
`0px`. A 1 px resize cures `inner` (22 of 22 stale loads, diag v2) but not `rows`. The rect is right while the style read is
wrong; the geometry-derived margins (83.33/116.33/7.33) are (steady + p) x 0.916667 - p, with s = 0.916667 the card scale and p the parent padding-left (56 px for inner, 0 for rows; INFERRED) (run 39340222228).

History, kept as evidence only: a nudged fresh load (9c31df36) failed 3 of 3 (runs 39335178250, 39335168536, 39335157627). A key
mask was tried at 22b3fd20 (ci/cmr-fix2) and refused in review as a tolerance widening; its proof runs are 39344334974,
39344352614, 39350369366 (infra loss 39344343539) and the flagged heads 39344441533, 39344450727, 39344459695. Diag code lives
only on `cmr-diag3` / `ci/cmr-diag3`; do not merge it.

Verified: counts in the note re-read from the diag logs of runs 39333030506 (v2) and 39340222228 (v3b); read paths cited to
file:line@f842f52. Not verified: the WebKit commission columns and their UNREACHABLE cells (no main-branch run id).

Open, in dependency order: `cmr-margin-typed-om` (premise: `computedStyleMap` returns `auto` where `getComputedStyle` returns
the strut), `cmr-margin-rect-rule` (rect-verdict rule for margins non-fixed in both arms; constraints are in the note's Next
section), `cmr-strut-asym` (why the original is stale 21 of 96 against 1 of 96, and why `rows` survives a resize).

Read first: the note, sections Answer, Diagnostics, Next.
