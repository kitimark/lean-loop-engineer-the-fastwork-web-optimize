Cells: arm median (base median) verdict; B = beats the base beyond the base spread, W = worse, = same, ? unresolved. Counts are per 500 px bins summed over a zone; frame metrics are moving frames over 34 / 50 ms per 100.

### hero

| arm | Layout | RecalculateStyles | Paint | Composite | FireAnimationFrame | FunctionCall | EventDispatch | over34 | over50 | counts | frames |
|---|---|---|---|---|---|---|---|---|---|---|---|
| base (n=1 visits) | 195 [195-196] | 175 [175-175] | 539 [519-544] | 59 [59-59] | 192 [192-192] | 424 [422-425] | 262 [260-262] | 0.00 [0.00-0.88] | 0.00 [0.00-0.00] | | |
| original | 213 (195) W | 197 (175) W | 457 (539) B | 59 (59) = | 194 (192) W | 301 (424) B | 30 (262) B | 100.00 (0.00) W | 100.00 (0.00) W | mixed | worse |
| hero.exit:threaded | 165 (195) B | 159 (175) B | 665 (539) W | 59 (59) = | 163 (192) B | 460 (424) W | 338 (262) W | 0.90 (0.00) = | 0.00 (0.00) = | mixed | same |
| hero:scene-pause | 195 (195) = | 187 (175) W | 483 (539) = | 59 (59) = | 192 (192) = | 712 (424) W | 562 (262) W | 1.81 (0.00) W | 0.00 (0.00) = | worse | worse |
| morph.columns:idle-none | 191 (195) = | 175 (175) = | 506 (539) = | 59 (59) = | 192 (192) = | 422 (424) = | 260 (262) = | 0.00 (0.00) = | 0.00 (0.00) = | same | same |
| morph.countdown:hidden-pause | 195 (195) = | 177 (175) = | 487 (539) = | 59 (59) = | 192 (192) = | 481 (424) W | 325 (262) W | 1.83 (0.00) W | 0.00 (0.00) = | worse | worse |
| morph.countdown:strip | - (195) ? | - (175) ? | - (539) ? | - (59) ? | - (192) ? | - (424) ? | - (262) ? | - (0.00) ? | - (0.00) ? | unresolved | unresolved |
| nav.hitTest:hit-skip | - (195) ? | - (175) ? | - (539) ? | - (59) ? | - (192) ? | - (424) ? | - (262) ? | - (0.00) ? | - (0.00) ? | unresolved | unresolved |
| engine.events:quiet | - (195) ? | - (175) ? | - (539) ? | - (59) ? | - (192) ? | - (424) ? | - (262) ? | - (0.00) ? | - (0.00) ? | unresolved | unresolved |
| morph.panel:const-bounds | - (195) ? | - (175) ? | - (539) ? | - (59) ? | - (192) ? | - (424) ? | - (262) ? | - (0.00) ? | - (0.00) ? | unresolved | unresolved |
| nav:clip-box | - (195) ? | - (175) ? | - (539) ? | - (59) ? | - (192) ? | - (424) ? | - (262) ? | - (0.00) ? | - (0.00) ? | unresolved | unresolved |
| nav:bar-fixed | - (195) ? | - (175) ? | - (539) ? | - (59) ? | - (192) ? | - (424) ? | - (262) ? | - (0.00) ? | - (0.00) ? | unresolved | unresolved |
| nav:logo-3d | - (195) ? | - (175) ? | - (539) ? | - (59) ? | - (192) ? | - (424) ? | - (262) ? | - (0.00) ? | - (0.00) ? | unresolved | unresolved |
| morph.mount:shift-dormant | - (195) ? | - (175) ? | - (539) ? | - (59) ? | - (192) ? | - (424) ? | - (262) ? | - (0.00) ? | - (0.00) ? | unresolved | unresolved |

### finish

| arm | Layout | RecalculateStyles | Paint | Composite | FireAnimationFrame | FunctionCall | EventDispatch | over34 | over50 | counts | frames |
|---|---|---|---|---|---|---|---|---|---|---|---|
| base (n=1 visits) | 52 [47-53] | 76 [76-77] | 163 [157-175] | 34 [34-34] | 89 [89-89] | 201 [189-278] | 130 [118-206] | 0.00 [0.00-1.72] | 0.00 [0.00-0.00] | | |
| original | 72 (52) W | 86 (76) W | 185 (163) = | 34 (34) = | 85 (89) B | 125 (201) = | 17 (130) B | 1.78 (0.00) = | 1.78 (0.00) W | mixed | worse |
| hero.exit:threaded | 33 (52) B | 76 (76) = | 158 (163) = | 34 (34) = | 72 (89) B | 172 (201) = | 118 (130) = | 1.72 (0.00) = | 0.00 (0.00) = | better | same |
| hero:scene-pause | 80 (52) W | 90 (76) W | 214 (163) = | 34 (34) = | 84 (89) B | 228 (201) = | 160 (130) = | 0.00 (0.00) = | 0.00 (0.00) = | mixed | same |
| morph.columns:idle-none | 53 (52) = | 77 (76) = | 170 (163) = | 34 (34) = | 89 (89) = | 285 (201) = | 214 (130) = | 0.00 (0.00) = | 0.00 (0.00) = | same | same |
| morph.countdown:hidden-pause | 86 (52) W | 89 (76) W | 207 (163) = | 34 (34) = | 85 (89) = | 246 (201) = | 178 (130) = | 5.55 (0.00) = | 1.85 (0.00) W | worse | worse |
| morph.countdown:strip | - (52) ? | - (76) ? | - (163) ? | - (34) ? | - (89) ? | - (201) ? | - (130) ? | - (0.00) ? | - (0.00) ? | unresolved | unresolved |
| nav.hitTest:hit-skip | - (52) ? | - (76) ? | - (163) ? | - (34) ? | - (89) ? | - (201) ? | - (130) ? | - (0.00) ? | - (0.00) ? | unresolved | unresolved |
| engine.events:quiet | - (52) ? | - (76) ? | - (163) ? | - (34) ? | - (89) ? | - (201) ? | - (130) ? | - (0.00) ? | - (0.00) ? | unresolved | unresolved |
| morph.panel:const-bounds | - (52) ? | - (76) ? | - (163) ? | - (34) ? | - (89) ? | - (201) ? | - (130) ? | - (0.00) ? | - (0.00) ? | unresolved | unresolved |
| nav:clip-box | - (52) ? | - (76) ? | - (163) ? | - (34) ? | - (89) ? | - (201) ? | - (130) ? | - (0.00) ? | - (0.00) ? | unresolved | unresolved |
| nav:bar-fixed | - (52) ? | - (76) ? | - (163) ? | - (34) ? | - (89) ? | - (201) ? | - (130) ? | - (0.00) ? | - (0.00) ? | unresolved | unresolved |
| nav:logo-3d | - (52) ? | - (76) ? | - (163) ? | - (34) ? | - (89) ? | - (201) ? | - (130) ? | - (0.00) ? | - (0.00) ? | unresolved | unresolved |
| morph.mount:shift-dormant | - (52) ? | - (76) ? | - (163) ? | - (34) ? | - (89) ? | - (201) ? | - (130) ? | - (0.00) ? | - (0.00) ? | unresolved | unresolved |

### rest

| arm | Layout | RecalculateStyles | Paint | Composite | FireAnimationFrame | FunctionCall | EventDispatch | over34 | over50 | counts | frames |
|---|---|---|---|---|---|---|---|---|---|---|---|
| base (n=1 visits) | 375 [374-384] | 395 [395-399] | 899 [887-899] | 120 [120-120] | 400 [400-400] | 831 [831-858] | 532 [532-558] | 0.46 [0.45-0.46] | 0.46 [0.45-0.46] | | |
| original | 358 (375) = | 415 (395) W | 705 (899) B | 120 (120) = | 444 (400) W | 601 (831) B | 60 (532) B | 79.48 (0.46) W | 79.48 (0.46) W | mixed | worse |
| hero.exit:threaded | 321 (375) B | 396 (395) = | 981 (899) W | 120 (120) = | 340 (400) B | 861 (831) = | 625 (532) W | 0.46 (0.46) = | 0.46 (0.46) = | mixed | same |
| hero:scene-pause | 350 (375) B | 407 (395) W | 595 (899) B | 120 (120) = | 418 (400) = | 1003 (831) W | 700 (532) W | 1.43 (0.46) W | 0.47 (0.46) = | mixed | worse |
| morph.columns:idle-none | 381 (375) = | 395 (395) = | 876 (899) = | 120 (120) = | 400 (400) = | 831 (831) = | 532 (532) = | 0.45 (0.46) = | 0.45 (0.46) = | same | same |
| morph.countdown:hidden-pause | 356 (375) B | 408 (395) W | 637 (899) B | 120 (120) = | 400 (400) = | 1006 (831) W | 720 (532) W | 3.06 (0.46) W | 1.02 (0.46) = | mixed | worse |
| morph.countdown:strip | - (375) ? | - (395) ? | - (899) ? | - (120) ? | - (400) ? | - (831) ? | - (532) ? | - (0.46) ? | - (0.46) ? | unresolved | unresolved |
| nav.hitTest:hit-skip | - (375) ? | - (395) ? | - (899) ? | - (120) ? | - (400) ? | - (831) ? | - (532) ? | - (0.46) ? | - (0.46) ? | unresolved | unresolved |
| engine.events:quiet | - (375) ? | - (395) ? | - (899) ? | - (120) ? | - (400) ? | - (831) ? | - (532) ? | - (0.46) ? | - (0.46) ? | unresolved | unresolved |
| morph.panel:const-bounds | - (375) ? | - (395) ? | - (899) ? | - (120) ? | - (400) ? | - (831) ? | - (532) ? | - (0.46) ? | - (0.46) ? | unresolved | unresolved |
| nav:clip-box | - (375) ? | - (395) ? | - (899) ? | - (120) ? | - (400) ? | - (831) ? | - (532) ? | - (0.46) ? | - (0.46) ? | unresolved | unresolved |
| nav:bar-fixed | - (375) ? | - (395) ? | - (899) ? | - (120) ? | - (400) ? | - (831) ? | - (532) ? | - (0.46) ? | - (0.46) ? | unresolved | unresolved |
| nav:logo-3d | - (375) ? | - (395) ? | - (899) ? | - (120) ? | - (400) ? | - (831) ? | - (532) ? | - (0.46) ? | - (0.46) ? | unresolved | unresolved |
| morph.mount:shift-dormant | - (375) ? | - (395) ? | - (899) ? | - (120) ? | - (400) ? | - (831) ? | - (532) ? | - (0.46) ? | - (0.46) ? | unresolved | unresolved |

### Per arm (all zones)

| arm | visits | counts | frames |
|---|---|---|---|
| original | 1 | mixed | worse |
| hero.exit:threaded | 1 | mixed | same |
| hero:scene-pause | 1 | mixed | worse |
| morph.columns:idle-none | 1 | same | same |
| morph.countdown:hidden-pause | 1 | mixed | worse |
| morph.countdown:strip | 0 | unresolved | unresolved |
| nav.hitTest:hit-skip | 0 | unresolved | unresolved |
| engine.events:quiet | 0 | unresolved | unresolved |
| morph.panel:const-bounds | 0 | unresolved | unresolved |
| nav:clip-box | 0 | unresolved | unresolved |
| nav:bar-fixed | 0 | unresolved | unresolved |
| nav:logo-3d | 0 | unresolved | unresolved |
| morph.mount:shift-dormant | 0 | unresolved | unresolved |
