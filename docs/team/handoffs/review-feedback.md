# review-feedback handoff (console-builder), round 2

Branch `worktree-wf_21068a14-405-1`. Read `docs/team/tools/review-feedback.md` first (who decides what).

## State (all five round-1 findings fixed; `lean/scripts/check.sh` exit 0; console-api, console-web, runner, contracts tests green)
- Watch alert wired: `Code.reviewFeedback` (`review.feedback`, rank 12 after `procLong`, later ranks +1), `System.feedback` (list of
  `Fw.Console.ReviewFeedback.Ev`), `sFeedback` over `FeedbackAlert.alerts`, theorems `feedback_iff`, `feedback_post_opens`,
  `feedback_reply_closes` in `Health.lean`; wire `fbEvJson/fbEvOf` + round trip in `Wire/Obs.lean`; 3 cases in `Obs/Golden.lean`;
  `collectFeedback` in `apps/runner/src/watch-collect.ts`; watch test runs real fwcore (post opens, reply closes).
- Door test: `/api/commands`, every actor with and without the secret, for `review.feedback` (user only) and the reply (lead only).
- Idempotency key `review-feedback-<flag>-<id>`; same cid on two flags: second is refused (422), first keeps its comment.
- Cap unit = code points (Lean `String.length`); zod `FeedbackText` counts code points; golden `console/reviewFeedback.jsonl` has 2000 and
  2001 astral characters; textarea `maxLength` removed (it counted UTF-16 units).
- Send path: `sendFeedback` in `ReviewFeedback.tsx` (extracted so a test can run it); tests stub `crypto` without randomUUID. Mutations
  shown to fail (restored): `crypto.randomUUID()` instead of `makeCid()`, URL typo, body without `cid`.

## Extra writes beyond the graph list
`lean/Fw/Wire/Obs.lean` (feedback wire; `maxHeartbeats` of `systemOf_systemJson` 4M -> 16M, that file now builds in ~10 min cold),
`lean/Fw/Ops/Golden.lean`, `packages/contracts/{src/index.ts,test/contracts.test.ts,schema/*.json}`, `docs/team/tools/watch-rules.md`.

## Open
- `systemOf_systemJson` is slow (whnf of `rfl` over a 15-key object); a faster proof would cut a cold build.
- TS stand-ins: none for decisions.
