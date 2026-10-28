branch: worktree-wf_066a7844-684-1 (CI branch ci/geom-prewarm)
worktree: .claude/worktrees/wf_066a7844-684-1 (under the main checkout)
last commit: see `git log -1`
CI runs: push 1 (4db117d42) wktr 40636360090 ok, breakpoint-gate 40636360067 FAIL (A3a desktop, A4 all). push 2 (779167974) wktr 40640739377 ok, breakpoint-gate 40640739317 FAIL (A3a ok 12/12 both engines, A4 0/12 both engines). push 3: see the end of this file.

Findings so far
- gate (push 2): with the held set the desktop first take is 1 ms (Chromium and WebKit) against 96-120 ms (Chromium phone widths) and 320-650 ms (WebKit phone widths) when it falls back; A3a and A5 pass; A4 fails in every band.
- A4 cause: the probe's baseWidth is read while the tree is held; `.is-flip` lays the nav out at the final box (1240 px at 1280), so base 1240 against 984 after the leave (maxDev 256). Holding the flip tree changes the nav box (layout and hit testing) outside the flip, not only the look. A fix needs the nav box at m=0 inside the held tree (geom.css, tracks origin) or a verify base read before the warm (gate-breakpoints, outside this task).
- wktr push 2: the held set (55 tracks) was built at 6.8 s, the first push at 9.1 s was refused (is-on-dark not yet set), the old code then cooled the set. Push 3 keeps the held set on a refused push (Lean held_refused_keeps).
- Probe trace (`__fwPrewarmTrace`): events not-ready, build, stale-push, stale-warm, resize, fast, create.

Code
- Lean `lean/Fw/Parts/MorphGeomPrewarm.lean`, Gen + golden `packages/contracts/golden/parts/morph-geom-prewarm.jsonl` (12 scenarios + rewarm timing), check.sh job, Trigger row.
- TS `apps/site/src/parts/morph.tween/geom-timed.driver.ts` (warm, cool, resize, take fast path), `driver.ts` (warm when near and idle, rewarm REWARM_MS after a leave), `morph.geom/index.tsx` (ready, fresh, later, trace).
- Probe `packages/measure-wktr/src/mid-page.mjs`; wktr.yml token `[accel-prewarm]`; part-footprint.mjs maxRecDepth.
Open: push 3 numbers, note research/notes/2026/10-2x-geom-prewarm.md, ledger entry, dry land, review ready. Not delivered: gate A4 on both engines, look report.
TS stand-ins: when the tween driver calls warm/cool; the resize debounce.
