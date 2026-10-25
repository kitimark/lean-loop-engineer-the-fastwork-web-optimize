# Handoff: pool-dispatch-poller (console-builder)

Branch `worktree-wf_2de28e7d-882-1`, worktree `.claude/worktrees/wf_2de28e7d-882-1`, last commit f2dcdb41 (ci branch `ci/pool-dispatch-poller` pushed at it).

CI runs (checkpoint 1): lean 40194602056 queued; webkit-sim push run 40194602049 completed success in seconds (guard skip: no input file changed, so no sim ran; the GitHub twin cell has to be dispatched with `fw run`).
Codemagic: NOT triggered. The worktree has no `.local/codemagic.json` (app id) or ledger, and the sandbox denied copying them from the main checkout.
Lead command (from the worktree): copy `<main>/.local/codemagic.json` and `<main>/.local/codemagic-ledger.json` into `.local/` here, then
`node scripts/codemagic.mjs trigger --pool --branch ci/pool-dispatch-poller --vars '{"FW_TARGET":"original","FW_PRESET":"original","FW_FW":"","FW_VM":"r1","FW_SESSIONS":"1"}'`, then `node scripts/codemagic.mjs wait --build <id> --out <dir>` (poll >= 120 s) and `node scripts/codemagic.mjs compare`.

Verified: Lean `Fw.Ci.PoolTier` cell theorems build; `scripts/codemagic.test.mjs` 26 pass.
Open: runner glue (route at dispatch in fw run, busy reader, events), docs, checks, dry land.
