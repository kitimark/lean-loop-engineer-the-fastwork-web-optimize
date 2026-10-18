# gate-align-equiv handoff

State: branch worktree-agent-a93a7999388df1e1b (main merged at c5442bc), CI branch `ci/gate-align-equiv`. Premise CI: run 39080496538 (1st), 39081058786 (2nd). Read first: module docstring of `lean/Fw/Gate/AlignEquiv.lean`.

- Lean `Fw.Gate.AlignEquiv`: modes content/fill/other, `eligible`, `contentFill`, `equivSpec`, `alignEquiv`; proved `alignEquiv_refl`, `equivSpec_symm`, `alignEquiv_symm`, `equivSpec_sound` (under `Agrees`), `modeOf_normal_ratio`, `canonItem_*`, `geometry_still_compared`. Golden `packages/contracts/golden/gate/align-equiv.jsonl` (38 cases) from `lean/scripts/AlignEquivGolden.lean` (`--check`), replayed in `lake test`.
- JS mirror `packages/gate-breakpoints/src/align-equiv.mjs` (`canonParts`, in-page `collectAlignFacts`, `attachAlignFacts`); `test/align-equiv.test.mjs` replays the goldens.
- Premises `grid.normal-aspect-ratio-no-stretch`, `grid.stretch-fill-equals-start` (registry, pages, `prem.*` tests in `packages/premise-tests/src/tests.mjs`).

Findings:
- CONFIRMED: the original `.start-selling-platform-row` has `align-items: stretch` at <=640 (snapshot `2.gBuqKVzi.css`), so stageBg's `auto` is stretch (fill), not normal. The fix-stagebg-webkit CSS comment ("spec-equivalent to normal") is wrong. The rule fires only when the rewrite's start-aligned slot fills its row (`contentFill`).
- MEASURED (run 39080496538): for `normal` on a non-replaced ratio box, Chromium stretches it (300 px) but WebKit uses the ratio height (256). The rule now gives it mode `other` (`modeOf_normal_ratio`). In run 39081058786 both grid premises hold on both engines (16/17 each; only the known `cv.auto-margin` fails), and the after-resize values equal the fresh ones. On Chromium, stretch in a row taller than the ratio also widens the box to 375 through the ratio (WebKit keeps 320). The width is not in the model, but `geometry_still_compared` catches it, and `contentFill` only pairs fill with content when the row equals the content height.
- The premise-tests `verdict` job fails on every branch with "console-api is not running" (`pnpm fw premises` in CI), which is pre-existing. Read the engine artifacts.

Open, for integrate-ports (no call-site edits made here):
- `run.mjs`: `import { attachAlignFacts, collectAlignFacts } from './align-equiv.mjs';` plus
  `const collectWith = async (s, arg) => { const raw = await s.evaluate(collectInPage, arg); if (arg.props) attachAlignFacts(raw, await s.evaluate(collectAlignFacts, { parts: arg.parts, props: arg.props })); return raw; };`
  Then replace the 3 `s.evaluate(collectInPage, X)` calls in `evalCollect` with `collectWith(s, X)`.
- `verdict.mjs`: `import { canonParts } from './align-equiv.mjs';` plus
  `const canonArm = (o, r) => { const rr = r.raw ?? r, oo = o.raw ?? o; return { ...rr, parts: canonParts(oo.parts, rr.parts) }; };`
  In `stateRequest`, use `rewrite: armReq(canonArm(s.orig, s.rewrite), ctx.parts)`. fwcore ignores the extra `align` item field.
- A declared non-auto height is conservatively ineligible. The `premise-tests.yml` paths filter lacks `packages/gate-breakpoints/**`, which `tests.mjs` now imports.
- The Lean CI after the lint fix (90e0b7b) has not run. Locally, `lake build`, `lake test` and `mathview --lint` all pass.
