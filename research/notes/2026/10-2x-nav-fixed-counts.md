# nav-fixed-counts: nav:bar-fixed and nav:logo-3d move no main-thread count on WebKit, nav:clip-box is undecided there, and no flag wins on Chromium

* Verdict (MEASURED, Lean `Fw.Parts.NavFixedCounts`, golden `packages/contracts/golden/parts/nav-fixed-counts.jsonl`): no-win for nav:bar-fixed and nav:logo-3d on WebKit and for all three flags on Chromium, in the hero, rest and finish zones; nav:clip-box on WebKit is not decided (2 of 3 VMs, run 40196217959): Lean reports `undecided` with n = 2 in all three zones. No decided cell is a win. No look-review step is posted, because the rule posts one only for a count win.
* The three flags are look-change class L and stay out of presets until the user's visual review.
* WebKit: no cell is certified in either direction. `nav:clip-box` has 2 of 3 VMs, so none of its cells is decided (n < 3). The other two arms have 3 VMs and 22 cells each (work, layer and byte cells): `nav:bar-fixed` has 12 same and 10 quarantined, `nav:logo-3d` 9 same and 13 quarantined. A quarantined cell is beyond the lane's tolerance in the base or the arm, so it cannot decide.
* Chromium: Layout, UpdateLayoutTree, FunctionCall and cc.Draw equal the base in every zone. The sum of the layer census over the zone's frames is a certified cost in the hero and finish zones (table below). That is a cost cell, not a win, so the Lean rule still reads no-win.

## Runs
* WebKit Simulator at main cb4bec8, 3 VMs x 2 passes: base 40196215217, `nav:bar-fixed` 40196221086, `nav:logo-3d` 40196212618 (6 passes each), `nav:clip-box` 40196217959 (4 passes: VMs r1 and r2).
* The `nav:clip-box` sim r3 job was lost twice to the Determinism sessions stall (the first attempt logged `Timeline.stop` then `Runtime.evaluate` timing out after 120000 ms; the rerun was cancelled). It was not dispatched again. The stall belongs to macos-vm-evidence.
* Chromium swipe-touch-v1, 3 runs each, at 1fac415: base 40171939293, `nav:clip-box` 40171943772, `nav:bar-fixed` 40171960215, `nav:logo-3d` 40171946109. The Chromium arms run at an older commit than the WebKit base; the task accepts the filed Chromium runs as they are (accepted limit). A Chromium base and arm always share their own commit.

## Rule (CONFIRMED in Lean, `verdict`, `win_sound`, `cost_sound`, `armOf_*_iff`, `workVal_partition`)
* A cell is the sum of one count over the steps (WebKit) or 500 px bands (Chromium) of one zone, one value per pass. WebKit zones are `Fw.Device.Session.zoneOf` (hero: first 2 viewports, finish: last viewport, rest). Steps above 5200 px are dropped (the passes end at 5231 or 5267, a page-height variant). Chromium bands map by hand: load frames and y 0 to 1500 are the hero, y 5000 and the tail are the finish, the rest between.
* Census cells are keyed by the requested scroll position; the end state is matched by position, because its y depends on the variant.
* Decided only with 3 VMs in both arms and neither arm beyond its tolerance (`Fw.Measure.WebKit.cellStatus`, zone sums 2 or 10 %, layer counts 1 or 5 %, bytes 2 %). Win: every arm pass below every base pass. Cost: above. Same: ranges overlap. A flag is win in a zone with a win cell and no cost cell, trade with both, no-win with a decided cell and no win cell, undecided when no cell is usable (`armOf_undecided_iff`; the golden carries the zone's fewest VMs).

## WebKit cells (MEASURED; min..max over passes, n = VMs; "noisy" = beyond tolerance, "n<3" = fewer than 3 VMs)
| count | zone | base | clip-box | verdict | bar-fixed | verdict | logo-3d | verdict |
|---|---|---|---|---|---|---|---|---|
| Layout | hero | 185..197 | 195..212 (n2) | n<3 | 179..208 | noisy | 184..211 | noisy |
| Layout | rest | 334..359 | 329..343 (n2) | n<3 | 335..358 | same | 317..357 | noisy |
| Layout | finish | 65..91 | 73..95 (n2) | n<3 | 49..101 | noisy | 65..109 | noisy |
| RecalculateStyles | hero | 177..186 | 183..195 (n2) | n<3 | 175..190 | same | 177..196 | same |
| RecalculateStyles | rest | 391..396 | 387..403 (n2) | n<3 | 389..398 | same | 383..400 | same |
| RecalculateStyles | finish | 69..86 | 77..92 (n2) | n<3 | 67..96 | noisy | 70..93 | noisy |
| FunctionCall | hero | 482..695 | 708..792 (n2) | n<3 | 480..755 | noisy | 482..820 | noisy |
| FunctionCall | rest | 901..979 | 971..1035 (n2) | n<3 | 913..1064 | noisy | 912..1173 | noisy |
| FunctionCall | finish | 213..295 | 219..262 (n2) | n<3 | 187..294 | noisy | 217..318 | noisy |
| Composite | hero, rest, finish | 61, 118, 30 | same (n2) | n<3 | same | same | same | same |
| layers | end state, finish | 124..128 | 124..128 (n2) | n<3 | 124..128 | same | 124..128 | same |
| layers | y 3000, rest | 136..140 | 136..141 (n2) | n<3 | 136..140 | same | 136..144 | noisy |
| layers | y 4500, finish | 141..145 | 142..145 (n2) | n<3 | 141..147 | same | 141..145 | same |

* Composite is identical in every pass of every arm (61, 118 and 30), so it carries no information about the flags (MEASURED).
* The backing bytes of the end state are 97.9M or 105.8M by page-height variant, in every arm; the byte cells are quarantined or n < 3 except at y 1500 (both decided arms) and y 3000 (`nav:bar-fixed`), where they overlap the base (golden rows `backingBytes`).
* The Layout and FunctionCall spread inside one arm (for example base hero Layout 185..197, FunctionCall 482..695) is larger than any plausible effect of a flag, so those cells cannot decide.

## Chromium cells (MEASURED; sums over the zone's frames, 3 runs, all n3)
| count | zone | base | clip-box | bar-fixed | logo-3d |
|---|---|---|---|---|---|
| Layout | hero, rest, finish | 256..259, 169, 48 | same | same | same |
| UpdateLayoutTree | hero, rest, finish | 884, 1174, 334 | same | same | same |
| FunctionCall | rest | 3916 | same (3912..3921) | cost (3920..3925) | same (3913..3916) |
| cc.Draw | hero, rest, finish | 248, 302, 221 | same | same | same |
| census.layers | hero | 30760 | cost (30761..30762) | cost (30762..30763) | cost (30771..30772) |
| census.layers | finish | 49453..49456 | cost (49492) | cost (49490..49492) | cost (49676..49678) |

* The finish zone has 221 frames, so the census cost is +36 to +39 layer-frames for `nav:clip-box`, +34 to +39 for `nav:bar-fixed` and +220 to +225 for `nav:logo-3d`: `nav:logo-3d` holds about one extra layer in every finish frame (INFERRED from the sum; the per-frame census is not in the files).
* The `nav:bar-fixed` rest FunctionCall cost is 4 to 9 calls on 3916 (0.1 to 0.2 %). The rule certifies it because the 3 runs of the arm are all above the 3 of the base. It is not a mechanism claim.
* The earlier Chromium swipe-v1 runs (research/notes/2026/10-2x-nav-fixed-size.md) found every zone equal; this run agrees on all work counts.

## Mechanism and Lean why (INFERRED: proved in the Lean model, whose pass rule is assumed, not read from engine source)
* The flags remove layout units, not layout passes. `units_fall_normal`: under Normal compositing the layout units per morph frame are 3 for `nav:clip-box`, 2 for `nav:bar-fixed` and 1 for `nav:logo-3d` (the bar and logo layout units are the ones `NavBarFixedWork.bar_layout_normal` and `logo3d_layout_normal` remove).
* The panel stays placed by insets in every arm, so one layout pass is queued in every morph frame of every arm and under both compositing policies (`pass_every_arm`, `units_fall_passes_equal`). A `Layout` record is one per pass, so the record count cannot see the units fall. INFERRED: this is why Layout stays inside the spread. The earlier note research/notes/2026/10-2x-nav-fixed-size.md reached the same reading: no count moves on Chromium swipe-v1.
* The morph writes the same `--morph` values in every arm (`NavBarFixed` writer theorems), so RecalculateStyles and FunctionCall are predicted equal. MEASURED: equal wherever the cell is decided.
* The flags add layers while the morph class is on: at most 1, 2 and 3 (`addedLayers_arms`, from `NavBarFixedWork.layer_budget`). WebKit cannot show them: the end-state layer census varies by 4 between passes in the base (`endSpread`, guarded `3 <= endSpread`), and `shift_not_above` proves that a shift of at most the spread is never read as a cost. Chromium shows them (table above).
* The model is refuted by any certified win or cost cell of the four work counts (`refutes_iff`). Chromium nav:bar-fixed rest FunctionCall is such a cost (3920..3925 vs 3916, 0.1 to 0.2 %), so the prediction FunctionCall-equal is refuted there on Chromium (cause unknown); the layer-census costs are allowed by `addedLayers_arms`. No cell is a win.

## Limits
* `nav:clip-box` on WebKit is not decided (2 VMs). A rerun with 3 VMs is the only way to decide it; the task forbids a new dispatch.
* The WebKit Layout, RecalculateStyles and FunctionCall cells are mostly beyond the lane's tolerance. A win of under 10 % cannot be certified with 3 VMs x 2 passes.
* The felt gain is not a count (CI VMs have no real GPU): the user's phone review decides, as the ledger rows state.
* Chromium bands are a hand map of the 500 px bands onto zones, not `zoneOf`.

## Reproduce
`results/nav-fixed-counts/extract.mjs` (WebKit artifacts) and `extract-chromium.mjs` (the filed store) only read and write JSON; the two data files they write sit in `packages/contracts/golden/parts/` (`nav-fixed-counts.webkit-passes.json`, `nav-fixed-counts.chromium-bands.json`), because the lake skip reads only that directory outside `lean/`. Every decision is in `lean/Fw/Parts/NavFixedCounts.lean`; the golden is `jsonl` of that module. Lake does not track `include_str`, so the module guards the runs and pass counts the data files hold.
