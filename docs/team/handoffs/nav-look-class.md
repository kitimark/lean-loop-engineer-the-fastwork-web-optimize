branch: `worktree-wf_92a5f1de-e33-1`
worktree: `.claude/worktrees/wf_92a5f1de-e33-1`
last commit: see `git log -1` (single work commit on top of main deb64c934)
CI runs: none pushed (no new measurement; accepted limit). Evidence cited: gpu-safari local Simulator run gpu-safari-sim-2026-10-23T00-46-14-744Z (results/gpu-safari/nav-*.json), trajectory-probe runs 39887328839 clip-box, 39887331854 bar-fixed, 39887335005 logo-3d (morph path RED on both engines; nav-clip cell E 4 each).
verified: `lake build Fw.Parts.Footprint`; Gen.run regenerated the preset goldens; check.sh and land dry see the report.
open: user look review (keep or drop the three arms); macOS Safari evidence waits for the Mac unlock (gpu-safari-mac); registry-vs-rule agreement is by hand (Gen does not read the evidence): follow-up.

## State
- `lean/Fw/Parts/Footprint.lean` (end of file): `isLookChange` is true (class L) when mid-morph changed px exceed the lane's later-load floor, or the morph trajectory is red, or the cell is L; else Q. Theorems: `look_of_px`, `look_of_traj`, `look_of_cell` (one per OR-branch), `q_only_if_clean`, `rest_blind`, `cell_blind`, `clipBox_look`, `barFixed_look`, `logo3d_look`.
- `apps/site/src/parts/nav/part.json`: clip-box, bar-fixed, logo-3d now `kind: proposal`, `visClass: L` (tier dropped), limits cite the evidence.
- Goldens regenerated from Lean (`Fw.Preset.Gen.run []`): look-change.candidates.jsonl gains the three flags; v2-proved.decisions.jsonl drops their rows. v2-proved.json unchanged (they were not members).
- Ledger rows nav.clip-box, nav.bar-fixed, nav.logo-3d: CLASS L text in `visual`; note `research/notes/2026/10-2x-nav-fixed-size.md` row updated.

## Why the old gates were blind
The rest-state gate compares settled frames and the nav-clip cell grades open/close frames; both end where --morph is 0 or 1, where the union box and clip-path equal the original box. The mid-morph pill edge ring and subpixel shift exist only between (m0.1 to m0.9).

## Review proposal (for the user)
Look at the nav while the hero pill morphs, 390 and 1280 wide, with ?fw=nav:clip-box, nav:bar-fixed, nav:logo-3d against the original; decide keep or drop each. No preset gets them without a yes.

## Read first
`lean/Fw/Parts/Footprint.lean` (end of file), then `research/notes/2026/10-2x-gpu-safari-lane.md`.
