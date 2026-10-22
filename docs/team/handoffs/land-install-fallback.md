# land-install-fallback handoff
Branch: worktree-wf_758984cc-042-1; worktree .claude/worktrees/wf_758984cc-042-1. No CI run pushed.
State: Lean `installKind`/`installRunsOnline`, kind `install` (exit 19) in Fw.Console.LandVerdict; goldens land-dry.jsonl (+op landVerdict.install) and land-queue.jsonl regenerated; land.ts `landInstall` + `checkoutLandWt` returns the prep refusal; fw-main prints VERDICT install for dry; tests apps/runner/test/land-install.test.ts and land-verdict.test.ts; land.md paragraph and table row.
Verified: vitest land-install + land-verdict green. Check/test/dry results: see the report.
Open: files outside graph writes (Lean sources, two goldens, fw-main.ts, land-verdict.ts, land-verdict.test.ts, LandQueue.lean count guard). Dry land has no Lean install stage (accepted).
Read first: lean/Fw/Console/LandVerdict.lean (installKind), apps/runner/src/land.ts landInstall.
