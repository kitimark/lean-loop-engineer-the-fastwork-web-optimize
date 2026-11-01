branch: worktree-wf_779ff154-e9a-1
worktree: .claude/worktrees/wf_779ff154-e9a-1 under the repo root
No CI runs.

State: main merged (Lean side taken from main). checkKind returns fwcoreBuild for BUILD_ARGV and for `sh lean/scripts/check.sh`
(apps/runner/src/land.ts:224). land-parallel.test.ts replays all 13 golden rows, expects check.sh = fwcoreBuild, and has main's
"fwcore users wait for check.sh" test back. Note 11-01-dry-land-waves.md: 82 ms, 15.8 s, scratch commits 6e8d03d58 / b8bd0ee, dry set has no check.sh.
Hidden lake builds: check.sh, scripts/fwcore-build.sh (BUILD_ARGV) and LINT_ARGV.axioms (lakeLint) build Lake; packages/gate-breakpoints test also runs lake build fwcore (scripts/scopegen.mjs:21), classed coreUser, so it starts after every build and its build is a no-op then (INFERRED); a Kind for a check that both builds and uses fwcore is a follow-up.
Verified: runner test 3784 pass, ci-paths test 56 pass, check.sh green, typecheck.
Stand-in: kindDeps/checkDeps in land.ts (TS, golden-checked, Lean replacement by a fwcore op).
Open: cold runs not fixed; no load-aware baseline.
