branch: worktree-wf_77bb82fa-fc7-1 (CI ref ci/waapi-scoped-webkit, same commit as the branch head)
worktree: .claude/worktrees/wf_77bb82fa-fc7-1
last commit: see git log -1
CI runs: none. `fw ci push --dry` says smoothness and trajectory-probe would not start (guard rule unchanged: no input differs from main).
verified: WebKit source read (StyleInterpolation.cpp:256-265: custom properties are not accelerated); patch applies (git apply --check).
verdict: closed negative finding for the iPhone lag, with fix requirements (note below).
undelivered: Simulator counts per zone (Timeline is off in touch windows; counts only in the macOS WebKit leg) and the Simulator stale-class check.
open (lead): dispatch commands in results/waapi-scoped-webkit/lead-commands.md; recorder.mjs patch (outside writes) in results/waapi-scoped-webkit/recorder-nav-class-sampler.patch; waapi-tail-drop decides the WebKit width tail.
read first: research/notes/2026/10-2x-waapi-scoped-webkit.md
