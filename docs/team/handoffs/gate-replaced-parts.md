# gate-replaced-parts handoff

**State:** branch `worktree-wf_b45aa19b-35b-1`, worktree `.claude/worktrees/wf_b45aa19b-35b-1`; work commits ccb158b74 (Lean +
harness) and 48af2e168 (note), then this handoff and the main merge. No CI runs (none needed: Lean and node tests only).
**Lean:** `lean/Fw/Gate/FlagDelta.lean` adds `ReplacedPart` and `replacedParts` (empty) and a `replaced` golden line,
plus `DItem.rewriteCount` (default none). `flag-delta.jsonl` is byte-identical. `lean/Fw/Gate/Replaced.lean` adds `absent`, `excuse` (a delta first, then
an entry), `readingVerdict` and `excusedItems`. Theorems: `entry_same_part`, `other_part_none/_fails`,
`present_none`, `present_anchor_fails`, `not_count_none`, `excuse_style`, `readingVerdict_nil`, `excusedItems_nil`,
`pass_items`, `absent_pass`, `countStatus_absent`. Golden `packages/contracts/golden/gate/replaced.jsonl` (2 fixture
entries, 26 cases; `lean/scripts/GateReplacedGolden.lean`, check.sh job "replaced golden check"; trigger rows in
`lean/Fw/Ci/Trigger.lean` with `golden/ci/triggers.jsonl` regenerated).
**Harness:** `packages/gate-breakpoints/src/replaced.mjs` replays the Lean decision. `summary.mjs applyFlagDeltas`
uses it with the canonical entries from `flag-delta.jsonl`. `flag-delta.mjs wireItem` carries `rewriteCount`. Tests:
`test/replaced.test.mjs` replays every case and has the fixture integration, plus `test/flag-delta.test.mjs`, which
pins the canonical list (empty).
**Verified:** check.sh green (slot); gate-breakpoints tests 797/797; ci-paths 56/56; runner land-inputs 73/73.
**Open:** morph-stage adds the two entries, as given in `research/notes/2026/10-2x-gate-replaced-parts.md`, then reruns the gate.
**Read first:** the note, then `lean/Fw/Gate/Replaced.lean`.
