# chromium-desktop-crash handoff

- Branch: worktree-wf_d355c294-3d5-1 (CI branch ci/chromium-desktop-crash, last pushed sha cfcbfe9)
- Worktree: .claude/worktrees/wf_d355c294-3d5-1
- Last commit: see `git log -1` (main merged after the last CI run; no measured file changed by the merge)
- Dispatches: 8 of 12 used.

## CI runs
| run | what | state |
|---|---|---|
| 39865150834 | rewrite 1280 crash-1280 | failed (renderer crash) |
| 39865162582 | original 1280 crash-1280 | failed (renderer crash) |
| 39865167197 | rewrite 861 crash-861 | failed (renderer crash) |
| 39866519567 | rewrite crash-probe-1 (35 variants x 2 jobs) | probe rows read, classify fails by design |
| 39867671059 | rewrite crash-probe-2 | probe rows read |
| 39867655875 | original crash-probe-2 | probe rows read |
| 39868985767 | rewrite desktop-1280 runs 3 | complete, all green (52/11/5 classes) |
| 39869000429 | original desktop-1280 runs 3 | complete, all green (52/13/2 classes) |

## Verified (MEASURED)
- Cause: `text-wrap: balance` on the people card title (applied only above 860 px) crashes Chrome Headless Shell 156.0.8078.4 (SIGSEGV 0x84), rewrite and original alike;
  none of 16 tested harness settings is involved; untested: BeginFrameControl, `--run-all-compositor-stages-before-draw` (the harness
  needs both), and full Chrome vs Headless Shell, so whether stock Chrome 156 crashes on this page is not known (INFERRED Chrome bug).
  In the rewrite the trigger is the people title h2 (balance) holding the inline-grid `o`.
- Workaround: profile `desktop-1280` sets `text-wrap: wrap` through `profile.css`; passing runs above. Note: `research/notes/2026/10-2x-chromium-desktop-crash.md`.
- Chrome change: not made (the lane has no pin input, the Dockerfile pin would move every committed count).

## Open
- Desktop counts from `desktop-1280` are for the page without text balancing; do not compare with phone or mobile profiles.
- Narrowing the workaround to the one offending element (rewrite: people h2; original: not found) and filing a Chromium bug are not done.
- Any other desktop profile needs the same `css` line until Chrome moves past this bug.
