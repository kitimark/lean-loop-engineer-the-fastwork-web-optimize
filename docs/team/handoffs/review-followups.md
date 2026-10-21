# Handoff: review-followups (console-builder)

State: branch `worktree-wf_f3657445-cd9-2`, committed; round 3 (final design round) accepted. Read first: `lean/Fw/Console/ReviewPreview.lean`
(`roundTag`, `roundOfKey`, `roundEventsOf`), `apps/console-api/test/review-preview-door.test.ts`.

Built
1. Door: `review-preview-door.test.ts` proves `POST /api/commands` and the cap `stamp` refuse `review.previewed` for every actor; only the preview route
   (done) records it. Mutation check: moving `internalCommands` into `PublicCommand` failed 3 tests (reverted).
2. Exact flag match: Lean `searchFlags`, `searchHasFlag` (+ `searchHasFlag_iff`, `searchHasFlag_false`), `carries`; wire `names` {search, flag} and plan
   `carries`; goldens (`nav:earn` vs `nav:earn-no-transition` both ways, comma list, second `fw`); the route refuses (500) a plan whose search lacks the flag.
   It hardens an invariant and fixes no live bug.
3. Round scoping by identity: the reader places a `review.previewed` event by the round tag parsed from its KEY (`...-desktop#1`), never by seq or posting
   order. Lean: `keyPrefix`, `roundOfKey` (+ `roundOfKey_eventKey`, `roundOfKey_roundTag`: the parser inverts the builder), `roundEventsOf tag evs`;
   T1 `shown_iff_named`, `named_round_shows`; T2 `other_rounds_show_nothing`, `keyed_elsewhere_hidden` (covers the unposted window and races: the key is
   fixed at record time); T3 `record_key_shown` (a repeat click duplicates a shown event); `untagged_first_round_only`. Round identity is the tag string
   ("" first round, "#k"). Wire events {flag, device, key?}; an old caller's `posts` is ignored. preview.ts passes each event's key.
   Goldens from Lean (`lake env lean --run scripts/OpsGolden.lean`). Door test "the reviewer's window" ends desktop true with one event keyed `#1`;
   it failed with the seq-based reader restored.

Verified: check.sh exit 0; console-api 734, console-web 80, ci-paths 54, land-inputs 55.

Accepted limits: L1 an event without a key belongs to round 1 only. L2 the wire carries key; absent = round 1. L3 that ensureReviewSteps posts the id the
recorder tagged (`stepOf`, `freshId` in Review.lean) is cited, not proved; the window test exercises it. L4 no UI redesign, no log rewrite.

Open (follow-ups from the round-3 review)
- Add `roundStep_eq_item` (or restate `record_key_shown` against the reader's item step) to link T3 to the reader.
- `roundOfKey_untagged` proves only the empty key; narrow its docstring or prove the no-prefix case.
- The empty-search and per-key facts are `#guard`s (`String.splitOn` does not reduce in the kernel).
- After editing Lean, run `lake build` before console-api tests, else they run the old fwcore binary.
- Extra writes: `lean/Fw/Wire/ReviewPreview.lean`, `lean/Fw/Wire/Console.lean`, `lean/Fw/Ops/Golden.lean`, `lean/Fw/Console/{Review,ReviewPreview}.lean`,
  `packages/contracts/golden/console/reviewPreview.jsonl`. No TS stand-ins.
