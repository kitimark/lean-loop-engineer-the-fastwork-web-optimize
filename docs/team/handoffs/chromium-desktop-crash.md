# chromium-desktop-crash handoff (checkpoint)

- Branch: worktree-wf_d355c294-3d5-1 (CI branch ci/chromium-desktop-crash)
- Worktree: .claude/worktrees/wf_d355c294-3d5-1
- Last pushed commit: 77ca330 (profiles crash-1280, crash-861, crash-860); later commits: see git log
- CI runs (profile crash-1280/crash-861, runs=2, sha 77ca330):
  - 39865150834 rewrite @1280: failed (Runtime.evaluate timed out)
  - 39865162582 original @1280: failed (same)
  - 39865167197 rewrite @861: failed (same)
- Dispatch budget: 3 of 12 used.

## Verified (MEASURED)
- The crash is not rewrite-specific: the faithful original snapshot also dies at 1280x800. The lane never ran a desktop-width
  profile before (all earlier profiles are 430 mobile), so this is not a regression. Earlier branch finding: 860 passes, 861 crashes.
- Earlier crash log (run 39862057861): SIGSEGV SEGV_MAPERR 0x84 in the renderer, Inspector.targetCrashed ~0.7 s after navigation.

## Inferred (static disassembly of the stripped Chrome Headless Shell 156.0.8078.4)
- The faulting chain passes through the function holding "Renderer.Layout.TextWrapBalance/TextWrapPretty" (inline_layout_algorithm.cc
  Balance/Optimize, score_line_breaker.cc) under LayoutNG block recursion. The site sets text-wrap balance/pretty only above 860 px.
- Open: whether a harness override (UA, locale, tz, flags, n0 census) is the trigger, or Chrome itself.

## Work in the tree
- run.mjs: --profile-file, profile.dropFlags, profile.css, FW_SKIP (ua,locale,tz), FW_LOAD_ONLY, FW_PROFILE_DIR, Inspector.targetCrashed
  handler (prints signal block, exit 76), kill chrome on exit.
- crash-probe.mjs + profiles/crash-probe-1.json (35 variants): one fresh Chrome per variant, rows ok|crash|hang.
- host.mjs: a profile with `probe` runs crash-probe.mjs.

## Next
- Push, dispatch `pnpm -s fw run --target rewrite --profile crash-probe-1 --runs 2 --ref ci/chromium-desktop-crash`, read PROBE rows with `gh run view <id> --log`.
- Fix or workaround from the matrix, then a passing desktop run on base with --runs 3.
