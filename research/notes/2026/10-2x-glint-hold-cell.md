---
id: 2026-10-29-glint-hold-cell
kind: note
title: "platform.glint:hold-freeze: the mac WebKit morph cell passes, the why entry is linked, the row stays partly-proved so the flag is not yet a v2-proved member"
status: draft
created: 2026-10-29
topics: [platform.glint, hold-freeze, trajectory-probe, mac-webkit, v2-proved, ledger]
---

# glint-hold-cell

Task `glint-hold-cell`, branch `ci/glint-hold-cell` (worktree branch `worktree-wf_886eb0c0-cc0-1`). Pinned unit: the mac WebKit morph
trajectory cell of `platform.glint:hold-freeze` recorded by `Gen.record`, the ledger row's status computed by `why`, and the flag's
`Gen.entry` decision. Follows `10-2x-glint-hold-wktr.md` (that note named these two blockers). No phone, no site code change.

## Answer

- MEASURED: the mac WebKit cell passes on both paths. Run 40831069482 (push 1 of 2, the only push; trajectory-probe, inputs
  `fw=platform.glint:hold-freeze engines=playwright-webkit debug=nav-transition`, read back from artifact `trajectory-inputs`,
  `results/glint-hold-cell/r1/inputs.json`): `Gen.record` stored `mac-webkit hero: pass`, `mac-webkit morph: pass` and `linux-webkit hero: pass`.
  The decision row now reads webkit hero pass, webkit morph pass, chromium hero and morph pass (run 40823517367), trajectory verdict `pass`.
- The mac morph walk has 43 new units of 14416 (content 1, coverage 42), all at one width (641), 129 baseline-red units shared with the faithful
  arm. The Lean rule fails a node only at 2 or more widths. The same shape (one width, coverage on the nav morph, which this flag does not touch)
  is in `10-2x-hero-exit-gate-clear.md`. INFERRED: sampling noise of the nav morph on the macOS runner, one passing run decides the cell.
- The `why` entry is linked and now computes `not-proved` (was `no-link`): the ledger row stays `partly-proved` because two `missingWhy` items
  cannot be closed by a linked theorem (below). So `Gen.entry` for the flag is `notYet [proofs, look]`, and the generator's `ok`
  (`isOpt && why = proved && trajectory pass && not isLook`) fails on `why` alone. Not a member of `v2-proved`; `Gen.run` still writes 2 flags.

## Entry decision, hero.exit-style (computed by `Gen.entry`, `Gen.blockers`, `Gen.ok`)

| requirement | met | evidence |
|---|---|---|
| proofs | no | `why` = not-proved: row `platform.glint:hold-freeze` (n 90) is `partly-proved`, two missingWhy items open |
| gate chromium | yes | run 40823517367, hero and morph pass |
| gate webkit | yes | hero: runs 40823517367, 40831069482 (linux), 40831069482 (mac); morph: mac run 40831069482 |
| look | listed, not needed | `Gen.entry` lists it because `lookDecisions` has no accepted decision; the flag is class E (`Fw.Parts.PlatformGlintHold.hold_eq_faithful`), so `ok` does not ask for a look decision (`!isLook`) |
| q6 | yes | `q6Answer` is set |

## The why entry (CONFIRMED, Lean)

`Fw.Preset.Gen.linkTable` now maps `platform.glint:hold-freeze` to the key (part `platform.glint`, the ledger row's exact candidate string).
The row lists these theorems in `leanFor`: `hold_premise`, `hold_eq_faithful`, `ticking_hold`, `ticking_ramp`, `ticking_le`, `hold_resume_eq`
(Fw.Parts.PlatformGlintHold) and `ramp_left`, `ramp_right`, `hold_both`, `union_ramp` (Fw.Device.GlintHold). `apps/site/src/parts/platform.glint/part.json`
provenance names them too (outside the task's graph writes; it is the one file of the site that the trajectory lane reads, which the push needed).

## What stays open, and why (the missingWhy items)

1. WebKit Simulator per-zone counts (z4500, z5000, finish, whole) are undecided at n = 2 + 3 VMs. A count is a measurement; no theorem closes it.
   The WKTR idle recalc cut of `10-2x-glint-hold-wktr.md` (run 40823517468, about 26 percent, Lean verdict cuts as predicted 3 of 3) is
   a different measure on a different build, so it is not claimed as the zone counts. Closing it needs more Simulator VMs or a decision that the
   WKTR verdict replaces the zone requirement (lead).
2. Chromium gives the wrong value for a backward `setCurrentTime` into segment 0 after the first cycle (diff 235), and the argument that no flag
   path seeks backward (`createPause` seeks forward) has no theorem. `hold_resume_eq` proves that after any pause and resume sequence the hold
   sample equals the uninterrupted original, but it does not state that every seek is forward. A theorem `resume_seek_forward` over the pause
   machine (`Fw.Parts.PlatformGlintPause`, which this task does not write) would close it: follow-up.

## Limits

One mac run decided the cell (a retry was not needed; 1 of 2 pushes used). The mac leg is Playwright WebKit on macOS, not Safari and not the phone.
The mac morph pass is a statement about the nav morph under the flag, which the flag does not touch; the glint itself is watched on the hero path.
