# countdown-hidden-arm handoff

## State
- Branch `worktree-wf_e80309b1-ad5-3`. The commit that adds this file is the final state.
- Decision: negative. `hero.countdown:hidden-pause` drops no element in frames 104-200 in any of the 4 arms. No
  preset change. `Fw.Preset.Gen.run []` rewrote the preset files byte-identical.

## Verified
- Arms and same-sha controls (chromium-counts, sha bcf9c7e0, 3 reps):
  - swipe-v1: base 39312082945 vs 39313893490, v2-proved 39312057983 vs 39313899612.
  - swipe-touch-v1: base 39312091230 vs 39313905095, v2-proved 39312076214 vs 39313910145.
- Lean: `hidden_work_idle` (with d = 0, skipWrites is the identity) and `hidden_pass_absorbed` (the style pass is
  absorbed when another part touches the stage), both in `lean/Fw/Parts/HeroCountdownHidden.lean`.
- `sh lean/scripts/check.sh` passes at the final commit.
- The ledger gets one notes row (task countdown-hidden-arm, field chromium) on the k8h entry.

## Open
- Why the faithful face writes restyle no element in the lane (part page run 39257533380, frames 120-146). The
  candidates are equal strings or detached handles. One debug read of `style.transform` on two consecutive spring
  frames settles it.
- If the faces do move after a fix, rerun the 4 arms. The Lean `k8h` link row goes in `linkTable` only on a measured
  drop.

## Read first
- `research/notes/2026/10-20-countdown-hidden-arm.md`
- `results/countdown-hidden-arm/summary.json`
