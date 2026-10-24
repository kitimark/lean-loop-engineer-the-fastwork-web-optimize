# commission-band-mech (part-builder)

- Branch `worktree-wf_e22d700e-552-1`, worktree `.claude/worktrees/wf_e22d700e-552-1`, last commit 1b71d5581 (profile only).
- CI branch `ci/commission-band-mech-1` (push 1 of 3, commit 1b71d5581, message asks `[ci:chromium-counts]` with
  `[counts profile=commission-rect-v1 runs=2 target=rewrite]`):
  - chromium-counts run 40139371262 (running), lean run 40139371309 (running, default lane).
- Writes outside the task: `packages/measure-chromium/profiles/commission-rect-v1.json` (new counts profile, swipe-v1 plus `cardProbe`).

## State
- Verified so far (offline, from downloaded artifacts): WebKit sim runs 39837001915 / 39843567401 per-step RecalculateStyles; the saving
  at y 3500-4500 is the exit window of the follower (fit of the Lean frame model to the base/flag step sets, scratchpad/cbm/fitw.mjs).
- Chromium swipe counts (runs 39837044649 / 39843560957): saving frames form one run y 2700-3590; the gate's static rect (T 3194, H 1203)
  does not reproduce it, a fit needs H about 700-800; commission-rect-v1 reads the in-session rect to settle this.
- Gate run 39843552595 (CI Chromium, 124 probes) holds section/card rects: `probes[].rewrite.raw.viewFirst.commission` (first read, page top =
  document coordinates) and `.parts.commission` (after the part is brought into view).

## Open
- Lean: `CommissionOptWindow.lean` (bands, quiet theorem), generated layout table from the gate rects, golden lines, `bandgate.test.ts` replay.
- Note `research/notes/2026/10-2x-commission-band-mech.md`, ledger row `commission.band-gate` missingWhy update.
