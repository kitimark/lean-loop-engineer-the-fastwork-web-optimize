Pin positions in the finish lane, pooled over runs 40158609202 (jobs 1, 2) and 40167641467 (jobs 1 and 3 to 10).
Source: the recorder frames (`rec.y`, `rec.mx`, `rec.o`, `rec.ca`) of every usable pass. The open start is the first frame of an
open stretch; the pin is the scrollY read at that frame (`end.logic.ts:61` `pinAfter`), and `rec.ca` are the instant
`scrollTo` writes while open. MEASURED.

| group | open starts | scrollY at open start: min / median / max (px) | above the end (first two rows: above 5228 px; other rows: above that frame's maxScrollY) |
|---|---|---|---|
| first open of a pass (from rest, all arms) | 27 | 5186 / 5249 / 5330 | 16 of 27 above 5228 |
| later opens of a pass (re-opens, all arms) | 51 | 5189 / 5226 / 5342 | 21 of 51 above 5228 |
| rewrite (faithful) | 28 | 5186 / 5223 / 5319 | 12 |
| clamp | 24 | 5220 / 5226 / 5330 | 11 |
| flip | 16 | 5190 / 5240 / 5342 | 12 |
| release | 4 | 5247 / 5259 / 5301 | 4 |
| all | 3 | 5249 / 5264 / 5324 | 3 |
| all + unthrottle | 3 | 5252 / 5258 / 5262 | 3 |

All 78 open starts: 5186 to 5342, median 5226; 45 of 78 above the frame's maxScrollY (median +22 px, up to +115 px).
Instant writes while open (n 414): 5183 to 5264, median 5226. maxScrollY itself ranges 5227 to 5267 (toolbar collapsed
versus expanded).
