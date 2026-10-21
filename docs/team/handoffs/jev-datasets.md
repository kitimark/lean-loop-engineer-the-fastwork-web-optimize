# jev-datasets handoff

State: branch worktree-wf_2a4f5755-f50-1. Rules in `lean/Fw/Oracle/Labels.lean` (golden `packages/contracts/golden/oracle/labels.jsonl`), extractor `scripts/jev-datasets.mjs`, tests `scripts/jev-datasets.test.mjs` (13 pass), note `research/notes/2026/10-2x-jev-datasets.md` (counts, gaps). Read the note first.
Verified: `sh lean/scripts/check.sh` green; node tests and `land-inputs.test.ts` green. Rerun: `node scripts/jev-datasets.mjs --sets d1,d2,d3,d4` (data lands in gitignored `.cache/jev/<set>.jsonl`; `--no-gh --logs-dir .cache/jev/d3-logs` reuses cached logs). No Jev call, no `gh api`.
Round 2 (branch merged with main at b2d4dff0; ledger commit ecdc0787; counts.json 2026-10-22T00:57:38+07:00). Counts (rows / labelled / held out): D1 115/115/33; D2 2434/1509/602 (364 labelled held out); D3 347/21/98 (5 labelled); D4 10/10/0 (gap, alerts not persisted). D2 row id is `<task>#<workflow id>#f<n>`; the workflow id is a local run id (follow-up 9: redact `wf_` ids before jev-replay sends text; ids are not sent).
Round-2 fixes: synthetic ids in the test, e-mail local part only in localNames (test added), stable D2 ids, regrade sentence. Real session/agent ids were in an earlier commit of this branch (07a41145, never pushed): squash on land.
Follow-ups left: D3 passedSameSha keyed on inputs/arms; Fable regrade by cited index not position; `wf_` redaction rule; severity `follow-up` infix anchor (Labels.lean:105).
Open: D4 needs persisted alerts plus the lead's action; D3 thin (146 logs read, success list only since 10-19); D2 regrades rare (Fable positional, 1 of 46 applied); redaction/parsing/Fable-line finder are TS stand-ins.
Convention: label rules only in Lean; held out = FNV-1a 32 of id mod 4 = 0; datasets never committed.
Example rows (text shortened; label | id or text):
D1 c-orphan-wait | inc-orphan-wait-loop, inc-silent-stdin-bg, inc-watch-bg-ampersand
D1 c-order-derived | inc-unlanded-handback, inc-claim-order, inc-plan-sync-on-land-only
D1 c-shared-no-lock | inc-commit-during-land, inc-fw-lean-import-conflict, inc-findings-shared-entry
D1 c-quota | inc-gh-rate-limit, inc-ci-trigger-drift, inc-ci-run-cap-prompt
D1 c-proxy-verdict | inc-variant-gate-flags-off, inc-part-scope-breakpoint-gap, inc-red-on-main-by-design
D1 c-identity-heuristic | inc-worktree-role-as-teammate, inc-land-waiters-pgrep, inc-land-retry-text-match
D1 c-late-check | inc-slow-land, inc-land-undeclared-reads, inc-land-scope-stale-base
D1 c-unearned-claim | inc-evidence-before-land, inc-premise-unmeasured-goldens, inc-prompt-premise-align
D1 c-sample-validity | inc-gate-scan-page-state, inc-ci-rerun-partial-arms, inc-obs-matrix-context-commission
D1 c-env-assume | inc-ci-verdict-needs-api, inc-land-inputs-untracked-exists, inc-zsh-colon-modifier
D1 c-spec-gap | inc-land-dry-no-verdict, inc-handoff-write-refused, inc-wait-guard-while-read-fp
D1 c-handcopy (2) | inc-ci-hardcoded-expect, inc-proof-of-typed-expectation; c-policy-prose (1) | inc-lead-cd-cwd
D2 blocker | "This breaks the pinned unit ('reading the staged blob')" | "The `only` input can never produce counts..." | "This is false. ... scope.gen..."
D2 fix-before-land | "These lines went stale after item (1)..." | "The workflow now runs `node --test .github/scripts/traj..." | "The lint reports this incident as fixed, and that is fa..."
D2 follow-up | "Re-run today, this prints 'VERDICT stale review-flow-v2..." | "It searches only the latest 100 runs across the whole r..." | "The runner agent swaps in the run states by following p..."
D2 unlabelled (medium, info, ...) | "The pinned unit asks for MEASURED before/after fw land..." | "The import regex /^(?:public\s+)?import\s+(\S+)/ takes..."
D3 ours | "ci: webkit cadence run 7, third job per leg..." | "ci: prove the mark rule on the push line..." | "node-pin-local r3: setup step first in 5 jobs" (log tail: error exit code 1 after an AssertionError)
D3 infra | "[ci:land] land wire-obs-proof-split d84bf19" | "ci: request [ci:webkit-sim] r3 with the proxy kill fault" (log has an infra phrase)
D3 flake (1) | "webkit-sim" run whose sha passed in the same workflow
D4 ask-user | "Agent main needs input" (user acted) | "Spool lines need a look: sweep:lifeOf x1..." (user acted)
D4 ignore | "Agent main needs input" (lead cancelled), twice
D4 mitigate | "Agent main stopped on an API failure; the lead restarts..." | "A helper stopped on an API error" | "Spool lines need a look: session_pid:unknown x1..."
