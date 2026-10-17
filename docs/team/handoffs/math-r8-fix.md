# Handoff: math-r8-fix

**State:** branch `worktree-agent-a71d9b008c4e49e49` on top of 7d564e2. The commit is the one with trailer `Task: math-r8-fix`.
Gate: `sh lean/scripts/check.sh` is green (66 s with a warm cache); console-api has 199 tests and runner has 102 tests, all green.

**Done**
- All 49 `disagree` rows of research/notes/2026/10-17-math-review-r8-fee88b2.md are fixed. Most fixes are docstring-only and touch these modules:
  - Obs.Health
  - Console.Alert
  - Gate.State, Gate.Items and Gate.Compare
  - Site.BreakpointMatrix
  - Store.Layout and Store.Reduce
  - Board
- Fw.Store.reduceOk_sound: the binder `r` is now quantified in the math, which clears the mathview warning.
- Lean behaviour changes, all in Fw/Store/Layout.lean:
  - `workflowInputs .chromium` now matches .github/workflows/chromium-counts.yml: profile, runs, target, preset, fw, image_run.
  - `dispatchInputs .chromium` sends `preset` and `fw`. The new `fwInput` joins the flags as `part:variant` with commas.
  - New theorems: `blocked_chromium` (chromium is never blocked) and `needs_dispatched` (every input a request needs is dispatched).
  - New `isPart` for flag parts. It works like `isId`, but letters after the first may be upper case. Before this, the real site part `nav.hitTest` was refused ("fw: part and variant must be ids"). Variants still use `isId`.
- Goldens are regenerated: packages/contracts/golden/store/plan.jsonl. Case 3 is renamed: chromium is now planned and only webkit is blocked on `fw`.
- apps/runner/test/run.test.ts: the refusal test now uses webkit. A new test checks that a chromium preset/fw dry run is not refused.

**Conventions used**
- A bound variable that shadows an accessor is written `\varphi`.
- Record fields are named in a `where o = (t, A, \ell, \Sigma)` clause.
- List counts are written `|[x ∈ L | p]|`. Case rows are first-match, written so they do not overlap.

**Open items**
- `dispatchInputs` does not send `target` or `image_run`, so the workflow defaults apply (`both`, none). The store key has no target, so a default run files both the original and the rewrite artifacts under one key. Decide between sending `target=rewrite` and adding target to the key.
- Other handoffs still describe the old {profile, runs} limitation: rewrite-ci-lane.md:17 and store-and-run.md:17.
- `isPart` allows upper case. On a case-insensitive filesystem, two parts that differ only in case would share a path. The registry has no such pair today.
- webkit-sim.yml still has no preset or fw input, so webkit stays BLOCKED for those requests.

**Read first:** the review note above, then `workflowInputs`, `blocked` and `dispatchInputs` in lean/Fw/Store/Layout.lean.
