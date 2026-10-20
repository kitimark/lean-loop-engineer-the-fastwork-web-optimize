# user-review-queue handoff

State: branch `worktree-wf_73319e74-c87-1`, not landed; the lead lands it. Read `docs/team/tools/review.md` first.

Built: Lean `Fw.Console.Review` (items from `Gen.lookDecisions`, `one_item_per_pending`, `closed_only_on_decision`,
`recorded_append`, `decided_stays`, `accept_ok`, `audience_is_owner`), wire `Fw.Wire.Review`, op `console.review`
(in `Wire/Console.lean`), goldens `golden/console/review.jsonl` (15 cases, from `Fw/Ops/Golden.lean` `named`).
console-api `src/review/routes.ts` (`GET /api/reviews`, `POST /api/reviews/:flag`; `createApp` takes a last `reviewRoot`,
default the parent of the console dir). console-web `Reviews.tsx`, tab Reviews with count badge, Compose marker.
Ledger row 39 `userDecision.decision` now says "kept 2026-10-21; visual review deferred to the console".

Deviation: no new `user.review` event type. The contracts package and the Lean reducer are outside this task's writes, so the
decision is the user's `step.answer` (keep or reject) on the step `review-<flag>` that console-api posts. Same single-writer
path; the reducer already refuses a second answer. A dedicated event can replace it later.

Not delivered: the lead edits `Gen.lookDecisions` words by hand after a decision (accepted limit); the existing "Your steps"
list also shows the review step with its two option buttons (a direct answer, no confirm). No review material was produced.
TS stand-ins: none (the route only forwards Lean's verdict). `MATERIAL` in `routes.ts` is a table of facts (run id, artifact).

Verified: see the report. Open: put the private link in `.local/reviews.json` on the lead's machine.
