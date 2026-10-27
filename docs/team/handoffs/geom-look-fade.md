# geom-look-fade handoff
Branch: worktree-wf_a3cf32ea-bfb-1. Worktree: .claude/worktrees/wf_a3cf32ea-bfb-1. CI branch: ci/geom-look-fade. Last commit: the branch tip (468fb0a08 is the code commit).
CI runs: push 1 (no marker, every workflow skipped, run 40585096601: no measurement); push 2 (`[ci:breakpoint-gate]` in the message): run id in the next section once known.

State: code done and committed, measurement running.
- Lean: lean/Fw/Parts/MorphGeomLookRule.lean (pixel rule, pixel range, share, track value, count, scroll, platform-fade, settled), proofs compiled; golden lines `look*` in packages/contracts/golden/morph-geom.jsonl (Lean generates, `--check` up to date).
- JS stand-in: packages/premise-tests/src/look-rule.mjs, checked line by line against the golden by test/look-rule.test.mjs (14 tests). Element attribution (elementTable) is reporting only, no verdict reads it.
- Harness: packages/premise-tests/src/look.mjs writes the platform fade on base from the golden, reads back scrollY, platform opacity, nav data-fw-morph and every non-CSS `data-mg` track, writes per-region PNGs (nav, cols, page) of both arms plus diff PNGs to out/look/<on|timed>/img/<band>/m<m>/, and a per-element table in the JSON. Always exit 0; `verify.ok` per row.
- look/timed: real wheel tween for m=1, untouched page for m=0, mid m skipped with a reason (timed has no pinnable value between rest states).
- Also edited outside the task writes: .github/workflows/breakpoint-gate.yml (upload `look/*/img`), apps/runner/src/land.ts (premise-tests reads the golden), lean/Fw/Ci/Trigger.lean + golden/ci/triggers.jsonl (premise-tests.yml trigger row lists the golden).

Verified: node tests (premise-tests 17, ci-paths 56, land-inputs 73), check.sh green through the slot, plan lint 0 errors. Local Chrome debug run (not a result, other dist): 390x844 verify ok at m 0, .5, 1 for both flags.
Open: CI numbers (before 40553185213 vs after), what still differs per element, WebKit runs, note, ledger, dry land, review.
Conventions: a push runs breakpoint-gate only with `[ci:breakpoint-gate]` in the head commit message. Look artifacts: flip-cell-<engine>/premise-tests/out/look/<on|timed>. Scratch summary script: scratchpad/geomlook/sum.mjs.
Read first: research/notes/2026/10-2x-geom-look-fade.md (when written), then look.mjs.
