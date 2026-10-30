# park-attrib: the WebKit card-translate gate failure is caused by hero.exit:threaded, not by the park

Task `park-attrib`, follow-up of `10-30-scrolldriven-park.md` section 4. No flag or preset change. Playwright WebKit stands in for iOS Safari.

## 1. The rule (Lean, before any run)

`Fw.Ops.Attrib.verdict` (`lean/Fw/Ops/Attrib.lean:31`): a cause is stated only between two gate runs on the same commit whose flag sets
differ in exactly one part (flag = part with its variant; a part set in one run and absent in the other counts as differing). Anything else is
`notAttributable`. Proved: `same_commit`, `one_part`, `other_commit_not_attributable`, `two_parts_not_attributable`,
`zero_parts_not_attributable` (`lean/Fw/Ops/Attrib.lean:37-62`); the cause carries the failing and the passing variant, and they differ
(`causedBy_values_differ`, line 91). Golden `packages/contracts/golden/ops/attrib.jsonl` (18 rows, generator `lean/Fw/Ops/AttribGolden.lean`,
job "attrib golden check" in `lean/scripts/check.sh`).

## 2. Runs (MEASURED, every number from the merge job output of the run)

| run | commit | flags (?fw=) | chromium | playwright-webkit |
|---|---|---|---|---|
| 41058963051 (baseline of the earlier task) | 8cb6814 | none | pass: 7056 readings, 7049 pass, 0 fail, 7 excused | pass: 7056, 6765 pass, 0 fail, 291 excused, 0 cells not ok |
| 41054732597 (park pair) | 768aebf | engine.scroll:unthrottle-park, hero.exit:threaded-park | pass: 7056, 7049 pass, 0 fail, 7 excused | fail: 7056, 6618 pass, 147 fail, 291 excused, 17 cells not ok |
| 41078004214 (this task, the pair without park) | 72d0bfd | engine.scroll:unthrottle, hero.exit:threaded | pass: 7056, 7049 pass, 0 fail, 7 excused | fail: 7056, 6618 pass, 147 fail, 291 excused, 17 cells not ok |
| 39774976109 (earlier task gate-settle-scroll-timeline, dispatch) | ff8c8cd | hero.exit:threaded | pass | fail: 147 readings (its handoff `docs/team/handoffs/gate-settle-scroll-timeline.md:14`; its merge log was not re-read) |
| 41086902481 (same-commit pair, dispatch on main) | 31fdd85 | none (header.flags.search "") | pass: 7056, 7049 pass, 0 fail, 7 excused | pass: 7056, 6765 pass, 0 fail, 291 excused, 0 cells not ok |
| 41087718575 (same-commit pair, dispatch on main) | 31fdd85 | hero.exit:threaded only (`?fw=hero.exit:threaded`) | pass: 7056, 7049 pass, 0 fail, 7 excused | fail: 7056, 6618 pass, 147 fail, 291 excused, 17 cells not ok |

- Failing items of 41078004214 on WebKit: `hero.orbit` style `card` `translate` 1060 probes, original `"0px"`, rewrite `"-0.000022px -0.000015px"`;
  `hero.deck` same property 164 probes, `"0px"` against `"-0.00001px -0.000008px"`. Parts `hero.exit` and `engine.scroll` pass on both engines.
- The readings-table sha256 is identical across runs: WebKit `e524c0eed3fc9707078ee224953866a1550bf6196febc695cf6d55dbd1ee3550` in 41054732597 and 41078004214
  (baseline: `44e52cf58d0f4b0bf9d2519cdf858c62e4306d79ddc0019cdfe4d1f6f352bb0c`); Chromium `bb9c3db13df7cbd72aa3f8aa42392095a3aef0d30892cb765aed070a08afbe8f` in all three.
- Run 41078004214 is the first push of this task (build config `?fw=engine.scroll:unthrottle,hero.exit:threaded` as in commit 768aebfa2). One gate push used of two.
- The baseline run 41058963051 has run conclusion `cancelled` (job not read); its merge job succeeded and printed both verdicts above.

## 3. Verdicts (Lean `verdict`, goldens rows 13-18 of `attrib.jsonl`)

| comparison | differ in | commits | verdict |
|---|---|---|---|
| 41054732597 vs 41078004214 | 2 parts (both variants) | 768aebf, 72d0bfd | notAttributable |
| 41078004214 vs 41058963051 | 2 parts | 72d0bfd, 8cb6814 | notAttributable |
| 41054732597 vs 41058963051 | 2 parts | 768aebf, 8cb6814 | notAttributable |
| 39774976109 vs 41058963051 | 1 part | ff8c8cd, 8cb6814 | notAttributable (two commits) |
| **41087718575 vs 41086902481** | 1 part (`hero.exit`: threaded against absent) | same, 31fdd85 | **causedBy hero.exit** (failing `threaded`, passing none) |

The last row is golden row 18 (`packages/contracts/golden/ops/attrib.jsonl`, regenerated from `lean/Fw/Ops/AttribGolden.lean`; the verdict is `Fw.Ops.Attrib.verdict`, `same_commit` and `one_part` hold).

MEASURED attribution (same commit 31fdd85 on main, both runs `workflow_dispatch`, the only difference the `fw` input; every number from the merge job output): without flags
both engines pass (Chromium 7049 pass, 0 fail, 7 excused; WebKit 6765 pass, 0 fail, 291 excused, 0 cells not ok). With `hero.exit:threaded` alone Chromium passes (7049 pass,
0 fail, 7 excused) and WebKit fails 147 readings in 17 cells (6618 pass, 291 excused): `hero.orbit` style `card` `translate`, 1060 probes, original `"0px"`, rewrite
`"-0.000022px -0.000015px"`; `hero.deck` same property, 164 probes, `"0px"` against `"-0.00001px -0.000008px"`. The failing cells (hero.orbit 10 groups, hero.deck 7 groups
in the `not ok` lines) and the readings-table sha256 `e524c0eed3fc9707078ee224953866a1550bf6196febc695cf6d55dbd1ee3550` equal those of run 41078004214
(the pair without park) and run 41054732597 (the park pair). The park flags and `engine.scroll:unthrottle` are not needed for the failure. The earlier reading that the
park holds a formula with a sub-pixel residual (`10-30-scrolldriven-park.md` section 4) is withdrawn as the cause.

## 4. What comes with what

- MEASURED (attributed by the rule): `hero.exit:threaded` causes the WebKit card-translate gate failure; the same-commit pair above, flag-set difference of size 1. This also
  covers the park flags: they ride on threaded (`threaded-park`) and fail for it.
- INFERRED, not read from source: why WebKit computes `-0.000022px -0.000015px` for the card `translate` under threaded where the original computes `0px`.
  The carrier of the sub-pixel value is the cards' scroll-driven animation that `hero.exit:threaded` adds; unthrottle animates one separate element.
- v2-proved and the shipped preset hold `hero.exit:threaded` (`apps/site/src/registry/presets/v2-proved.json`). Its preset entry (commit d6174ba8c, 2026-10-29) had no
  breakpoint-gate run: the breakpoint gate of `preset=v2-proved` run 40101370753 passed on both engines (note `10-2x-webkit-morph-cell.md:101`) when the preset held
  `unthrottle` only (`10-2x-webkit-morph-cell.md:86`), and no breakpoint-gate run of the three-flag preset is on record in the last 40 runs of the workflow. Every
  breakpoint-gate run with threaded fails WebKit with these readings (39774976109, 41078004214, 41087718575). Whether the preset keeps it is the user's decision; this task
  changes no flag and no preset.

## 5. OPEN

- Why the rewrite computes the sub-pixel `card` `translate` under threaded on WebKit: not read from WebKit source (follow-up).
- Playwright WebKit stands in for iOS Safari: the failure is measured there, not on the phone.
- The WebKit breakpoint-gate cell for v2-proved and shipped (threaded is a member) is refused by 147 readings; the preset decision is the user's.
