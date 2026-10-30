# park-attrib: the WebKit card-translate gate failure comes with hero.exit:threaded, not with the park

Task `park-attrib`, follow-up of `10-30-scrolldriven-park.md` section 4. No flag or preset change. Playwright WebKit stands in for iOS Safari.

## 1. The rule (Lean, before any run)

`Fw.Ops.Attrib.verdict` (`lean/Fw/Ops/Attrib.lean:31`): a cause is stated only between two gate runs on the same commit whose flag sets
differ in exactly one part (flag = part with its variant; a part set in one run and absent in the other counts as differing). Anything else is
`notAttributable`. Proved: `same_commit`, `one_part`, `other_commit_not_attributable`, `two_parts_not_attributable`,
`zero_parts_not_attributable` (`lean/Fw/Ops/Attrib.lean:37-62`); the cause carries the failing and the passing variant, and they differ
(`causedBy_values_differ`, line 91). Golden `packages/contracts/golden/ops/attrib.jsonl` (17 rows, generator `lean/Fw/Ops/AttribGolden.lean`,
job "attrib golden check" in `lean/scripts/check.sh`).

## 2. Runs (MEASURED, every number from the merge job output of the run)

| run | commit | flags (?fw=) | chromium | playwright-webkit |
|---|---|---|---|---|
| 41058963051 (baseline of the earlier task) | 8cb6814 | none | pass: 7056 readings, 7049 pass, 0 fail, 7 excused | pass: 7056, 6765 pass, 0 fail, 291 excused, 0 cells not ok |
| 41054732597 (park pair) | 768aebf | engine.scroll:unthrottle-park, hero.exit:threaded-park | pass: 7056, 7049 pass, 0 fail, 7 excused | fail: 7056, 6618 pass, 147 fail, 291 excused, 17 cells not ok |
| 41078004214 (this task, the pair without park) | 72d0bfd | engine.scroll:unthrottle, hero.exit:threaded | pass: 7056, 7049 pass, 0 fail, 7 excused | fail: 7056, 6618 pass, 147 fail, 291 excused, 17 cells not ok |
| 39774976109 (earlier task gate-settle-scroll-timeline, dispatch) | ff8c8cd | hero.exit:threaded | pass | fail: 147 readings (its handoff `docs/team/handoffs/gate-settle-scroll-timeline.md:14`; its merge log was not re-read) |

- Failing items of 41078004214 on WebKit: `hero.orbit` style `card` `translate` 1060 probes, original `"0px"`, rewrite `"-0.000022px -0.000015px"`;
  `hero.deck` same property 164 probes, `"0px"` against `"-0.00001px -0.000008px"`. Parts `hero.exit` and `engine.scroll` pass on both engines.
- The readings-table sha256 is identical across runs: WebKit `e524c0eed3fc9707078ee224953866a1550bf6196febc695cf6d55dbd1ee3550` in 41054732597 and 41078004214
  (baseline: `44e52cf58d0f4b0bf9d2519cdf858c62e4306d79ddc0019cdfe4d1f6f352bb0c`); Chromium `bb9c3db13df7cbd72aa3f8aa42392095a3aef0d30892cb765aed070a08afbe8f` in all three.
- Run 41078004214 is the first push of this task (build config `?fw=engine.scroll:unthrottle,hero.exit:threaded` as in commit 768aebfa2; workflow reverted
  afterwards). One gate push used of two.
- The baseline run 41058963051 has run conclusion `cancelled` (job not read); its merge job succeeded and printed both verdicts above.

## 3. Verdicts (Lean `verdict`, goldens rows 13-17 of `attrib.jsonl`)

| comparison | differ in | commits | verdict |
|---|---|---|---|
| 41054732597 vs 41078004214 | 2 parts (both variants) | 768aebf, 72d0bfd | notAttributable |
| 41078004214 vs 41058963051 | 2 parts | 72d0bfd, 8cb6814 | notAttributable |
| 41054732597 vs 41058963051 | 2 parts | 768aebf, 8cb6814 | notAttributable |
| 39774976109 vs 41058963051 | 1 part | ff8c8cd, 8cb6814 | notAttributable (two commits) |
| two runs on one commit, `hero.exit:threaded` against none (not run yet) | 1 part | same | causedBy hero.exit |

Plain statement: no pair of runs on record licenses a cause, so the failure is not attributed by the rule. It is, however, MEASURED that the park flags are not needed
for it: the pair without any park flag fails with the same 147 readings, the same two items and the same table hash. The earlier reading that the park holds a
formula with a sub-pixel residual (`10-30-scrolldriven-park.md` section 4) is withdrawn as the cause: the park pair and the plain pair read the same.

## 4. What comes with what (INFERRED from the runs above)

- Every WebKit run with `hero.exit:threaded` on (alone in 39774976109; with `unthrottle` in 41078004214; as `threaded-park` in 41054732597) fails these cells; the one
  run without it passes. The cards are hero parts that `hero.exit:threaded` animates; `engine.scroll:unthrottle` animates one separate element. So threaded is the carrier
  (INFERRED), unthrottle and the park are not (MEASURED: removing the park flags changes nothing; unthrottle alone was not run on WebKit in this task).
- v2-proved and the shipped preset hold `hero.exit:threaded` (`apps/site/src/registry/presets/v2-proved.json`). Gate evidence that covers these cells: none passes. The
  breakpoint gate of `preset=v2-proved` run 40101370753 passed on both engines (note `10-2x-webkit-morph-cell.md:101`) when the preset held `unthrottle` only
  (`10-2x-webkit-morph-cell.md:86`); threaded entered the preset on 2026-10-29 (commit d6174ba8c) on trajectory-probe evidence, and no breakpoint-gate run of
  the three-flag preset is on record in the last 40 runs of the workflow (`gh run list --workflow breakpoint-gate`). The only breakpoint-gate runs with threaded
  fail WebKit with these readings (39774976109 and 41078004214).

## 5. OPEN

- One same-commit pair would attribute it by the rule: two dispatches of breakpoint-gate on one ref at one commit, `fw` empty and `fw=hero.exit:threaded`, engines both
  (`pnpm -s fw run --gate --engines both --ref main` and the same with `--fw hero.exit:threaded`; main's workflow builds the unflagged site and takes the flags from the
  `fw` input). Verdict `causedBy hero.exit` if the first passes and the second fails. Lead dispatch, not started here. The remote `ci/park-attrib` still holds
  72d0bfd91 with the temporary workflow edit: the final commit could not be pushed (the pre-push lane check refuses a tip that names no changed lane).
- Why the rewrite computes `-0.000022px -0.000015px` for the card `translate` where the original computes `0px` under threaded: not read from WebKit source here.
- The WebKit breakpoint-gate cell for v2-proved and shipped (threaded is a member): refused by 147 readings; not mine to change (no preset change).
