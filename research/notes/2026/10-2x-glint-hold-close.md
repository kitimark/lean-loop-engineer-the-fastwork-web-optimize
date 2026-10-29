# platform.glint:hold-freeze: close the seek item, one look rule for entry and preset (task glint-hold-close)

Follows `10-2x-glint-hold-cell.md` ("What stays open"). No CI or phone run in this task.

## 1. Every resume seek goes forward (CONFIRMED, Lean)

`Fw.Parts.PlatformGlintPause.resume_seek_forward` (`lean/Fw/Parts/PlatformGlintPause.lean`): along a run of `hide` and
`reveal` observations with nondecreasing times, every resume seek of the pause machine targets an elapsed time at or
after the one the clock froze at. `seeks p os` lists the (frozen, target) pair of each seek in run order; the theorem
says `frozen ≤ target` for every pair. The invariant `Fwd b now p` adds to `Same b p` (from `same_run`) that a paused
clock froze at an elapsed time no later than `now - b`; `fwd_step` keeps it across one observation whose time is at
least `now`. `resume_seek_forward_start` is the same statement from the start state with no other premise.

The machine is the one `platform.glint/pause.ts` `pauseStep` runs (hide: `off = read - t`; reveal: seek to `t + off`),
so the flag path never issues the backward `setCurrentTime` that Chromium gets wrong (diff 235, `10-2x-glint-hold-freeze.md`).
The second `missingWhy` item of the ledger row is closed; the theorem is in the row's `leanFor` and in
`Fw.Preset.Gen.holdRowNames`, which `Gen.run` checks against `leanFor` (`holdLinkGaps`). Limit (INFERRED, as before): the
model does not clamp at 0 the way `setCurrentTime` does, and observation times come from one monotone clock (`now()`).

## 2. One look rule for `Gen.entry` and `V2Proved.ok` (CONFIRMED, Lean)

Rule (`Fw.Preset.Gen.lookMet`): the look requirement is met when every registered entry of the flag is class `e` or
`eS` (`Fw.Preset.V2Proved.exactLook`, same look proved in Lean) or when the user accepted its look; a class `q`, `l` or
unclassified flag needs the decision. Each branch has its own theorem (`lookMet_of_exact`, `lookMet_of_accepted`,
`lookMet_false`).

`entry_enter_iff_ok_of_exact`: for a registered `optimized` flag with `exactLook`, `entry = enter` exactly when
`V2Proved.ok` admits it (`not_isLook_of_exactLook` supplies the `!isLook` clause of `ok`). `Gen.run` also fails when a
decided class E flag disagrees (`entryGaps`, with `#guard` cases), and `v2-proved.decisions.jsonl` now carries
`entry` (decision and blockers) for every decided flag, not only `hero.exit:threaded`.

Decisions changed by the rule (regenerated with `Gen.run`, compared against the previous golden): no `member`,
`why`, `trajectory` or `shadowedBy` value changed, and `v2-proved.json` is unchanged (`engine.scroll:unthrottle`,
`hero.exit:threaded`). The old rule gave every flag without an accepted look a `look` blocker; the new rule drops it
for the seven class E or E-s flags: `hero:scene-pause`,
`platform.glint:hold-freeze`, `hero.exit:contain`, `pain:dark-scroll`, `platform.entries:fill-release`,
`platform.glint:offscreen-pause`, `platform:faded-pause`. `hero.exit:threaded` stays `enter` (accepted look).

Remaining divergence outside class E (MEASURED on the golden): `engine.scroll:unthrottle` is unclassified, so
`ok` admits it and `entry` reads not yet, blocker `look`. Making `ok` take the rule as well would drop it from
`v2-proved` until its part names a class or the user accepts its look; that is a lead decision, not made here.

## 3. Provenance

`apps/site/src/parts/platform.glint/part.json` `hold-freeze.provenance.lean` now names `ticking_ramp`, `hold_resume_eq`,
`Fw.Parts.PlatformGlintPause.resume_seek_forward` and `Fw.Device.GlintHold` `ramp_left`, `ramp_right`, `hold_both`,
`union_ramp`.

## 4. Simulator per-zone counts: stays open

The two measures ask different questions, so the WKTR verdict does not replace the zone counts (INFERRED from the
two notes):

| measure | question | run |
|---|---|---|
| Simulator zones | does the flag lower the per-zone engine counters (Paint, InvalidateLayout and the rest) on the swipe path in z4500, z5000, finish and whole | flag 40349914211, base 40349930733; undecided at n = 2 + 3 VMs |
| WKTR idle recalc | does the flag lower style recalcs per 100 frames in the idle and flip cells of WKTR (pref off) | 40823517468; idle cuts as predicted 3 of 3, flip mixed |

The WKTR idle recalcs touch no element of the style tree (`zsum` 0 in every idle arm, `10-2x-glint-hold-wktr.md`), so
a recalc cut need not show as a zone counter gain. The first `missingWhy` item stays, with this reason in its text.
Closing it needs more Simulator VMs or a lead decision to drop the zone requirement.

## 5. Entry decision for platform.glint:hold-freeze

`Gen.entry`: not yet, blockers `[proofs]` (golden `v2-proved.decisions.jsonl`). The gates pass on both families
and the look is met by class E. `proofs` stays unmet because the ledger row is `partly-proved` with the Simulator item
open; `V2Proved.ok` is false for the same reason, so the flag is not in `v2-proved`.
