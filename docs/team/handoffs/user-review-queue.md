# user-review-queue handoff (round 2)

State: branch `worktree-wf_73319e74-c87-1`, not landed; the lead lands it. Read `docs/team/tools/review.md` first.

Built: Lean `Fw.Console.Review` (items from `Gen.lookDecisions`, `one_item_per_pending`, `closed_only_on_decision`,
`recorded_append`, `decided_stays`, `accept_ok`, `open_accepts`, `closed_refused`, `repost_accepts`, `undecided_actionable`),
wire `Fw.Wire.Review` (`console.review`; steps now carry `open`), goldens `golden/console/review.jsonl` (23 cases).
console-api `src/review/routes.ts`, console-web `Reviews.tsx`, tab Reviews with count badge, Compose marker.

Round 2 changes (findings 1-6 of round 1):
- Step state in Lean: `Rec.isOpen` (waiting or started). A step closed without a verdict (done, cancelled, answered with a
  non-verdict word) refuses an answer; the item needs a new step `review-<flag>#<k>` (id chosen in Lean, `freshId`). Proved:
  an open item with an open step is accepted for keep and reject; after the new step is posted it is too. API tests cover
  started-then-done, cancelled and two closed steps.
- Your steps list: no Start, Done or answer button for ids starting `review-`; a link to `?tab=reviews` instead.
- `Gen.lookDecisions` is structured (verdict kept/rejected/accepted, review pending/done, material per engine). Review reads
  the field. `Gen.ledgerDisagreements` checks ledger row 39 `userDecision` against it in every `Gen.run` (also `--check`).
  The material table in routes.ts is gone; it comes from the op output.
- GET /api/reviews is read-only. Steps are posted by POST, at startup and every minute (`ensureReviewSteps`, main.ts).
- The step.answer design is the accepted design (review.md); idempotency keys now include the step id.

Not delivered / limits: the lead applies a keep or reject to `Gen.lookDecisions` by hand; `freshId` unused-ness is not proved
(the reducer refuses a duplicate post). The startup post means a cancelled step is re-posted within a minute, not at once.
TS stand-ins: none. Generated: `golden/preset/look-change.candidates.jsonl`, `golden/console/review.jsonl`.
Open: put the private link in `.local/reviews.json` on the lead's machine; restart the console to load the new fwcore.
