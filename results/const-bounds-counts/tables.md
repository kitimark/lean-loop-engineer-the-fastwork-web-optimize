## WebKit Simulator

Base run 40196215217, flag `morph.panel:const-bounds` run 40196209240, commit cb4bec8. Passes: base 6 from 3 VMs, flag 6 from 3 VMs. Cell verdict: the flag passes beat (or lose to) every base pass by more than the base spread; thin = fewer than 3 VMs on a side.

### hero: no-win

beats 0, worse 0, same 11, unresolved 0, thin 0

| quantity | at y | base passes | flag passes | VMs base/flag | verdict |
|---|---|---|---|---|---|
| Layout | - | 194, 189, 197, 187, 189, 185 | 209, 204, 204, 203, 186, 205 | 3/3 | same |
| RecalculateStyles | - | 177, 178, 186, 181, 182, 178 | 194, 190, 187, 189, 181, 187 | 3/3 | same |
| Paint | - | 453, 525, 545, 520, 480, 514 | 462, 451, 526, 520, 529, 448 | 3/3 | same |
| Composite | - | 61, 61, 61, 61, 61, 61 | 61, 61, 61, 61, 61, 61 | 3/3 | same |
| FunctionCall | - | 695, 482, 659, 487, 522, 491 | 779, 790, 738, 706, 483, 832 | 3/3 | same |
| EventDispatch | - | 540, 321, 501, 324, 368, 328 | 633, 642, 582, 552, 320, 692 | 3/3 | same |
| paintArea | - | 27622399, 29991421, 27947083, 29981347, 29555178, 28890182 | 27843935, 27415446, 29963433, 29315022, 30236566, 27504423 | 3/3 | same |
| layers | 0 | 108, 112, 106, 110, 106, 106 | 111, 110, 110, 110, 107, 106 | 3/3 | same |
| memBytes | 0 | 36.15, 41.32, 36.15, 41.45, 36.15, 41.11 | 36.55, 36.49, 36.51, 41.45, 36.15, 41.11 | 3/3 | same |
| layers | 1500 | 112, 112, 112, 114, 112, 112 | 112, 112, 112, 112, 112, 112 | 3/3 | same |
| memBytes | 1500 | 87.02, 87.02, 87.02, 87.05, 87.02, 87.02 | 87.02, 87.02, 87.02, 87.02, 87.02, 87.02 | 3/3 | same |

### finish: no-win

beats 0, worse 0, same 11, unresolved 2, thin 4

| quantity | at y | base passes | flag passes | VMs base/flag | verdict |
|---|---|---|---|---|---|
| Layout | - | 75, 65, 91, 71, 66, 65 | 81, 108, 78, 78, 66, 76 | 3/3 | same |
| RecalculateStyles | - | 80, 70, 86, 73, 73, 69 | 82, 96, 82, 82, 69, 83 | 3/3 | same |
| Paint | - | 196, 174, 206, 178, 177, 173 | 198, 236, 194, 198, 170, 198 | 3/3 | same |
| Composite | - | 30, 30, 30, 30, 30, 30 | 30, 30, 30, 30, 30, 30 | 3/3 | same |
| FunctionCall | - | 235, 295, 246, 225, 232, 213 | 251, 358, 227, 237, 209, 248 | 3/3 | same |
| EventDispatch | - | 174, 230, 184, 162, 170, 148 | 190, 290, 166, 176, 144, 186 | 3/3 | same |
| paintArea | - | 4292824, 3632437, 4304145, 3872962, 4026381, 3914739 | 3921801, 5098429, 3897688, 4351603, 3877670, 4228651 | 3/3 | same |
| layers | 4500 | 141, 145, 141, 141, 145, 145 | 142, 141, 145, 144, 145, 141 | 3/3 | same |
| memBytes | 4500 | 153.64, 149.26, 149.26, 153.64, 149.26, 149.26 | 149.26, 149.26, 149.26, 169.93, 149.26, 153.64 | 3/3 | same |
| layers | 5267 | 124, 128 | 124, 124, 128, 124, 128, 124 | 1/3 thin | same |
| memBytes | 5267 | 97.87, 97.87 | 97.87, 97.87, 97.87, 97.87, 97.87, 97.87 | 1/3 thin | same |
| layers | 5231 | 124, 124, 128, 128 |  | 2/0 thin | unresolved |
| memBytes | 5231 | 105.79, 105.79, 105.79, 105.79 |  | 2/0 thin | unresolved |

### rest: no-win

beats 0, worse 0, same 9, unresolved 0, thin 0

| quantity | at y | base passes | flag passes | VMs base/flag | verdict |
|---|---|---|---|---|---|
| Layout | - | 349, 359, 334, 353, 349, 352 | 324, 327, 330, 342, 355, 309 | 3/3 | same |
| RecalculateStyles | - | 391, 391, 392, 396, 392, 395 | 391, 390, 396, 398, 391, 383 | 3/3 | same |
| Paint | - | 631, 668, 615, 664, 611, 674 | 597, 568, 605, 603, 630, 553 | 3/3 | same |
| Composite | - | 118, 118, 118, 118, 118, 118 | 118, 118, 118, 118, 118, 118 | 3/3 | same |
| FunctionCall | - | 972, 937, 979, 932, 901, 946 | 1033, 1104, 945, 915, 933, 1073 | 3/3 | same |
| EventDispatch | - | 696, 649, 693, 645, 604, 657 | 752, 824, 660, 616, 645, 794 | 3/3 | same |
| paintArea | - | 37936287, 40250702, 37765499, 38990594, 36628937, 39417105 | 36365953, 36682494, 36077787, 36234867, 39225588, 36728939 | 3/3 | same |
| layers | 3000 | 136, 140, 136, 136, 140, 140 | 136, 136, 140, 136, 140, 136 | 3/3 | same |
| memBytes | 3000 | 101.26, 101.26, 101.26, 101.26, 101.26, 101.26 | 101.26, 101.26, 101.26, 101.26, 101.26, 101.26 | 3/3 | same |

## Chromium

Base run 40171939293, flag `morph.panel:const-bounds` run 40171951145, commit 1fac415. Runs: base 3, flag 3; frames of a run per zone: hero 208, rest 269, finish 294. Sums of the per-frame counts of the zone, one number per run; verdict as above.

### Chromium hero: no-win

beats 0, worse 0, same 14, unresolved 0, thin 0

| count | base runs | flag runs | runs base/flag | verdict |
|---|---|---|---|---|
| trace.Layout | 230, 232, 229 | 232, 232, 231 | 3/3 | same |
| metric.LayoutCount | 191, 193, 190 | 193, 192, 192 | 3/3 | same |
| trace.Layout.dirtyObjects | 3074, 3082, 3070 | 3086, 3082, 3078 | 3/3 | same |
| trace.InvalidateLayout | 275, 277, 274 | 276, 278, 276 | 3/3 | same |
| trace.UpdateLayoutTree | 764, 764, 764 | 764, 764, 764 | 3/3 | same |
| metric.RecalcStyleCount | 747, 747, 747 | 747, 747, 747 | 3/3 | same |
| trace.Paint | 1618, 1618, 1618 | 1618, 1618, 1618 | 3/3 | same |
| trace.PrePaint | 861, 861, 861 | 861, 861, 861 | 3/3 | same |
| trace.cc.Commit | 208, 208, 208 | 208, 208, 208 | 3/3 | same |
| trace.FunctionCall | 2117, 2117, 2117 | 2117, 2117, 2117 | 3/3 | same |
| trace.EventDispatch | 787, 787, 787 | 787, 788, 787 | 3/3 | same |
| raster.invalidationAreaPx | 61876603, 61825770, 61825811 | 61825815, 61825770, 61876562 | 3/3 | same |
| census.layers | 24389, 24389, 24389 | 24388, 24389, 24388 | 3/3 | same |
| census.drawingAreaPx | 1650546194, 1650546194, 1650546194 | 1650546194, 1648502026, 1648502026 | 3/3 | same |

### Chromium finish: cost

beats 0, worse 4, same 10, unresolved 0, thin 0

| count | base runs | flag runs | runs base/flag | verdict |
|---|---|---|---|---|
| trace.Layout | 71, 71, 71 | 71, 71, 71 | 3/3 | same |
| metric.LayoutCount | 71, 71, 71 | 71, 71, 71 | 3/3 | same |
| trace.Layout.dirtyObjects | 758, 758, 758 | 920, 920, 920 | 3/3 | worse |
| trace.InvalidateLayout | 73, 73, 73 | 73, 73, 73 | 3/3 | same |
| trace.UpdateLayoutTree | 564, 564, 564 | 564, 562, 564 | 3/3 | same |
| metric.RecalcStyleCount | 564, 564, 564 | 564, 562, 564 | 3/3 | same |
| trace.Paint | 1188, 1188, 1188 | 1189, 1189, 1189 | 3/3 | worse |
| trace.PrePaint | 628, 628, 628 | 627, 628, 628 | 3/3 | same |
| trace.cc.Commit | 289, 289, 289 | 289, 289, 289 | 3/3 | same |
| trace.FunctionCall | 2819, 2825, 2825 | 2821, 2825, 2819 | 3/3 | same |
| trace.EventDispatch | 655, 658, 658 | 657, 658, 655 | 3/3 | same |
| raster.invalidationAreaPx | 161536393, 161536319, 161536319 | 161764743, 161764743, 161764743 | 3/3 | worse |
| census.layers | 61315, 61312, 61314 | 61315, 61313, 61313 | 3/3 | same |
| census.drawingAreaPx | 4278903627, 4278900169, 4278900921 | 4282153055, 4282152303, 4282152303 | 3/3 | worse |

### Chromium rest: no-win

beats 0, worse 0, same 14, unresolved 0, thin 0

| count | base runs | flag runs | runs base/flag | verdict |
|---|---|---|---|---|
| trace.Layout | 173, 173, 173 | 173, 173, 173 | 3/3 | same |
| metric.LayoutCount | 173, 173, 173 | 173, 173, 173 | 3/3 | same |
| trace.Layout.dirtyObjects | 2650, 2650, 2650 | 2650, 2650, 2650 | 3/3 | same |
| trace.InvalidateLayout | 178, 178, 178 | 178, 178, 178 | 3/3 | same |
| trace.UpdateLayoutTree | 1064, 1064, 1064 | 1064, 1062, 1064 | 3/3 | same |
| metric.RecalcStyleCount | 1064, 1064, 1064 | 1064, 1062, 1064 | 3/3 | same |
| trace.Paint | 981, 979, 979 | 979, 979, 980 | 3/3 | same |
| trace.PrePaint | 969, 969, 969 | 969, 970, 970 | 3/3 | same |
| trace.cc.Commit | 269, 269, 269 | 269, 269, 269 | 3/3 | same |
| trace.FunctionCall | 3498, 3492, 3492 | 3492, 3492, 3498 | 3/3 | same |
| trace.EventDispatch | 731, 728, 728 | 728, 728, 731 | 3/3 | same |
| raster.invalidationAreaPx | 13712939, 13712939, 13712939 | 13712939, 13715419, 13715419 | 3/3 | same |
| census.layers | 38735, 38735, 38735 | 38735, 38736, 38736 | 3/3 | same |
| census.drawingAreaPx | 3242143590, 3242143590, 3242143590 | 3242143590, 3242143590, 3242143590 | 3/3 | same |

