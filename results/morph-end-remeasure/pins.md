Pin positions in the finish lane, pooled over runs 40158609202 (jobs 1, 2), 40167641467 (jobs 1 and 3 to 10) and
40193540518 (jobs 2, 4 to 9). Source: the recorder frames (`rec.y`, `rec.mx`, `rec.o`, `rec.ca`) of every pass that
has a recording (usable or not). MEASURED.

Two quantities carry the word "pin":
- scrollY at the first frame of an open stretch (`rec.y` where `rec.o` rises), in px;
- the first instant `scrollTo` write while that stretch is open (`rec.ca`, the argument the page passes, which is the
  stored pin `end.logic.ts:61` `pinAfter`), in px.

| group | open starts | scrollY at open start: min / median / max | open starts above that frame's maxScrollY, above 5228 |
|---|---|---|---|
| first open of a pass | 45 | 5184 / 5250 / 5330 | 33 above maxScrollY, 29 above 5228 |
| later opens | 78 | 5189 / 5226 / 5342 | 44 above maxScrollY, 32 above 5228 |
| rewrite | 52 | 5186 / 5226 / 5319 | 28 above maxScrollY, 22 above 5228 |
| clamp | 24 | 5220 / 5226 / 5330 | 11 above maxScrollY, 11 above 5228 |
| flip | 28 | 5184 / 5224 / 5342 | 19 above maxScrollY, 10 above 5228 |
| release | 7 | 5238 / 5250 / 5301 | 7 above maxScrollY, 7 above 5228 |
| all | 6 | 5210 / 5250 / 5324 | 6 above maxScrollY, 5 above 5228 |
| all-unthrottle | 6 | 5247 / 5255 / 5263 | 6 above maxScrollY, 6 above 5228 |
| every open start | 123 | 5184 / 5228 / 5342 | 77 above maxScrollY, 61 above 5228 |

Over all 123 open starts the scrollY above maxScrollY has median +29 px, up to +115 px. maxScrollY itself ranges 5191 to
5267 (toolbar collapsed versus expanded). The release, all and all+unthrottle arms write no pin (the page holds
closed), so they have open starts but no writes.

First write per open stretch (the stored pin as the page applies it), against the scrollY at that stretch's open frame
(104 stretches with a write, the `rewrite`, `clamp` and `flip` arms):

| arm | stretches | first write min / median / max (px) | scrollY at open frame min / median / max (px) | open frame above the write by more than 1 px |
|---|---|---|---|---|
| rewrite | 52 | 5183 / 5222 / 5279 | 5186 / 5226 / 5319 | 28 |
| clamp | 24 | 5220 / 5223 / 5226 | 5220 / 5226 / 5330 | 11 |
| flip | 28 | 5184 / 5220 / 5228 | 5184 / 5224 / 5342 | 18 |

The first write is at or under maxScrollY (+1 px) in 100 of 104 stretches; all instant writes while open (n 590): 5183 to
5279, median 5226.

Per open stretch, reversals and spring-back fights from the lock reducer (`lockCounts`), first stretch of a pass against
later stretches:

| arm | stretches | reversals mean | fights mean | displaced frames median |
|---|---|---|---|---|
| all first | 6 | 1.00 | 0.00 | 0 |
| all-unthrottle first | 6 | 1.00 | 0.00 | 0 |
| clamp first | 5 | 3.40 | 1.80 | 10 |
| clamp later | 18 | 4.72 | 2.39 | 12 |
| flip first | 7 | 3.00 | 1.43 | 9 |
| flip later | 21 | 4.81 | 2.62 | 10 |
| release first | 7 | 1.00 | 0.00 | 0 |
| rewrite first | 13 | 2.46 | 1.46 | 3 |
| rewrite later | 39 | 4.13 | 2.13 | 9 |
