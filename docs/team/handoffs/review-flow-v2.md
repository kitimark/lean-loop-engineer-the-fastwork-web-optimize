# review-flow-v2 handoff

State: branch worktree-wf_ad651a2b-c27-1 (commit in the report). Read first: `lean/Fw/Plan/ReviewReady.lean`.

Built
- Lean `Fw.Plan.ReviewReady`: `reviewReady` (review | dispatch | wait | returnToBuilder; ranked fault > dispatch > wait),
  `itemGate`, `verdictOf` (accept iff no blocker), `recheck`, `strictVerdict` (interim: also refuse on fix-before-land).
  One theorem per branch: `reviewReady_{returnToBuilder,dispatch,wait,review}_iff`, `verdictOf_{refuse,accept}_iff`,
  `recheck_iff`, `strict_accept_iff`, `strict_accept_verdict`, `no_review_without_dry`; `#guard` goldens in the file.
- fwcore ops `plan.reviewReady`, `plan.reviewVerdict` (`lean/Fw/Wire/Plan.lean`, table updated).
- `fw review ready --report <file|-> [--task id]` (exit 0 review, 21 wait, 22 dispatch, 23 returnToBuilder) and
  `fw review verdict --findings <file|-> [--audited yes]` (`apps/runner/src/review-ready.ts`); needs no console-api.
- Golden `packages/contracts/golden/plan/review-ready.jsonl` (from fwcore; regenerate with FW_WRITE_REVIEW_READY_GOLDEN=1) and
  `apps/runner/test/review-ready.test.ts`.
- `build-review.js`: preamble requires `fw land --dry` (`dry`) and `items`; BUILD schema gains items/runs/dry/gate; a `runner`
  gate agent runs `fw review ready` (builder's own gate line is not trusted); non-review answers return to the lead with
  `gate`/`gateLine` and `adv: null`; reviewer grades 3 levels and gets accept from `fw review verdict`.
- `fable-refusals.js`: check returns `{spec, corrections}`, no accept bit.
- `docs/team/tools/prompt-rules.md`: rules R5b, R5c.

Verified: see the report (check.sh, runner tests, ci-paths, land-inputs, dry land).

Open / accepted limits
- Medium-only audit (32 refusals) not done; until then `fw review verdict` without `--audited yes` refuses on fix-before-land.
- Declared extra writes beyond the graph list: `lean/Fw/Wire/Plan.lean` (new ops), `apps/runner/test/` none other.
- Workflow scripts are not run by any test here; syntax-checked only (node --check on a wrapped copy). First live run is the proof.
- Item status words are fixed in Lean (`Status.ofString`); the schema enum in build-review.js must follow if one is added.
