# refreeze handoff

**State:** done on branch `worktree-agent-aae7cf276627fdde0` (commit trailer `Task: refreeze`); CI branches `ci/refreeze`, `ci/refreeze-b..f`.
Gate: `cd packages/measure-chromium && pnpm test` 21/21 (set `FW_CORE_BIN` to a built fwcore when the worktree has none).

**Runs** (harness commit `f87bf94` = main `c719d73` + the workflow fix; image `sha256:8f0e17f5...` built by 39049264131, reused by the rest through `image_run`)
- swipe-v1: 39049264131, 39049466889, 39049469621
- swipe-touch-v1: 39049471997, 39049478836, 39049481754

**Classes (det/stable/quar), before -> after**
| profile | arm | before | after | roles gate/finding/byDesign |
|---|---|---|---|---|
| swipe-v1 | A | 27/25/10 (62 types) | 32/28/10 (70) | 60/9/1 |
| swipe-v1 | R | none | 44/7/1 (52) | 51/1/0 |
| touch | A | 16/27/19 (62) | 22/32/16 (70) | 54/15/1 |
| touch | R | none | 20/1/30 (51) | 21/30/0 |

**What changed**
- `src/freeze.mjs`: reads the per-target artifact layout (`chromium-counts-<target>-rN`, `chromium-classes/<target>/`), freezes each arm,
  forwards `role`/`reason`/`roles` from measure.freeze, adds `crossArm` from measure.arms; schema `fw.classes.frozen/2`
  (`profiles.<p>.arms.{original,rewrite}`). Test fixture rewritten for two arms, roles and cross-arm.
- `.github/workflows/chromium-counts.yml`: `classify` gets an `if` so `target=original` no longer skips it (lead's request).
- README: "Update 2026-10-17 (refreeze ...)" section.

**Open**
- touch R: run 39049478836 job r2 has 403 frames, the other 8 jobs 409; 30 types quarantined. Touch-race residual; the table carries the worst class.
- Not done: no consumer reads the new shape yet (zone-baseline-lean will); the old docs (handoffs, PLAN) still quote 27/25/10 and 16/27/19.
- `runs/` (downloaded artifacts) is untracked in the worktree; do not add it.
**Read first:** the README section, then `src/freeze.mjs`.
