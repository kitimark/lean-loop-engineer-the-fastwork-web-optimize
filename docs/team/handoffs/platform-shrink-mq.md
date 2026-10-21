# platform-shrink-mq handoff

**State:** branch `worktree-wf_683d0de1-db2-1` (also pushed as `ci/platform-shrink-mq`). Flag `platform:mq` registered
(`apps/site/src/parts/platform/part.json`, variant `mq`, T0). Lean `lean/Fw/Parts/PlatformShrinkOpt.lean`; goldens
`packages/contracts/golden/parts/platform-shrink.jsonl` (76 rows, written by `fwcore partsgolden` via `PlatformGolden.files`).

**Proved (class E, also across a band change):** `look_gated`, `look_const_iff`, `inl_ungated`, `cls_agree`, `look_agree`,
`platformShrink_visSame`; work `writes_le`, `gated_run`, `gated_run_lt`; `unshrunk_run` (why there is no saving);
`stepV_writes` (TS decision = model). Difference from people.card:mq: the band may change per event (P1 is a hypothesis
on the event gate, the media-change handler runs the frame).

**TS:** `logic.ts` `planShrink`, `cardLook` (golden-checked); `driver.ts` `createShrink(el, env, {gate})`; `index.tsx` gate
`matchMedia(mq.c860)` and a `change` listener. TS stand-ins (not golden-checked): the listener glue, the CSS premise test
`shrink.test.ts` (pins lines 8, 31, 32, 303-315).

**Measured (CI, sha 20467a9):** lean 39680908944 pass; breakpoint-gate `--fw platform:mq` both engines 39680952848 success;
webkit-sim base 39680958629, flag 39680964944. End-of-page window shows no difference above pass noise. Report:
`results/platform-shrink-mq/report.json` (review-reports shape; Lean console.report accepts it; not posted). Recommendation: hold.

**Finding (premise refuted):** the rewrite's last section is the platform card, so a plain scroll never lifts the card
bottom above 0.85 vh; the shrink is 0 and the original writes nothing. Note `research/notes/2026/10-2x-platform-shrink-mq.md`.

**Writes outside the graph writes (generated, needed):** `lean/Fw/Parts/FootprintData.lean`,
`packages/contracts/golden/parts/footprint.gen.json` (`node apps/site/scripts/part-footprint.mjs --write`),
`packages/contracts/golden/preset/v2-proved.decisions.jsonl` (`Fw.Preset.Gen.run []`), `results/platform-shrink-mq/**`.
The land needs `--allow lean/Fw/Parts/FootprintData.lean --allow 'results/platform-shrink-mq/**'` (and the two golden files if refused).

**Open:** Simulator replay of the end of page (morph push) with frame times; re-check if a section is added below the card.
**Read first:** the note above, then `PlatformShrinkOpt.lean` section "The event sequence".
