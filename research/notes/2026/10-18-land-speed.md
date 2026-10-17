---
id: land-speed
kind: note
title: Why fw land takes ~2 min (and holds the land lock for all of it), and how to get a Lean-touching land under 20 s
status: CONFIRMED
created: 2026-10-18
topics: [tooling, fw-land, mathview, lean, timing, cache, soundness]
---

# fw land speed (land-speed-research)

Synthesis of three read-only investigations (mathview profile, land flow, Lean statements). I re-checked the main
claims at main `84b9f19`. Toolchain paths are relative to `leanprover/lean4:v4.35.0` `src/lean/`.

## Answer first
- A Lean-touching land spends ~88% of its time in one step, the **mathview lint** (p50 118 s). About **96% of that
  step is `collectAxioms`**, recomputed from scratch for each of ~4,077 declarations. MEASURED.
- The whole of `check.sh` runs **while the land lock is held** (land.ts:280-335), so main is blocked for 125-190 s
  per land. CONFIRMED.
- Fix 1 (a shared axiom-reachability memo, ~76 lines in `lean/MathView.lean`) takes mathview from ~110 s to 10.2 s,
  with byte-identical lint output. MEASURED, one local debug run. Fixes 2-4 (a parallel check DAG, checks before the
  lock, a per-module lint cache) bring a Lean land to ~13-20 s with the lock held < 1 s. INFERRED.

## Measured breakdown (`.fw-console/timings.jsonl`, spans since 2026-10-17 20:42 UTC; MEASURED)

| step (tool / step) | n | p50 ms | max ms |
|---|---|---|---|
| fw land / sh lean/scripts/check.sh | 4 | 152,813 (values 112.5, 124.1, 152.8, 191.9 s) | 191,947 |
| lean/check / mathview lint (miss) | 8 | 118,082 | 211,702 |
| lean/check / lake test | 9 | 4,605 | 8,181 |
| lean/check / lake build (incremental) | 9 | 2,163 | 29,877 |
| lean/check / breakgen check lean + site | 7 | 1,176 + 224 | 4,818 |
| lean/check / grep gates, import check, golden wire replay | 9/9/7 | 221 / 90 / 178 | 966 |
| fw land / pnpm runner test (only when apps/runner changes) | 1 | 18,761 | |
| fw land / pnpm contracts test | 3 | 1,143 | 1,876 |
| fw land / worktree cleanup (after the lock) | 4 | 5,457 | 13,151 |
| fw land / merge, merge commit, plan sync, verify, reconcile | 4-6 | 42 / 310 / 254 / 43 / 153 | 875 |

Inside the mathview lint, profiled over 7,833 candidate constants (MEASURED, local debug run at load 15-33):
`collectAxioms` 108,381 ms, `ppSignature` 2,489, `getUnfoldEqnFor?` 708, `latex` 682, `importModules` 565, the rest
< 400. Loop total 112,983 ms. collectAxioms is also ~98% of the export's heartbeats (2,169,694k of the total;
41,159k with the fix). The runs were also slowed by checks running in other worktrees at the same time: land
b37227c's mathview took 140 s while an agent's check.sh ran in parallel, at load 6.8-18.5 on 8 cores. MEASURED.

## Root cause, two levels down

1. **Per-call axiom walk.** `MathView.entryOf` calls `collectAxioms n` for each declaration (lean/MathView.lean:268).
   `collectAxioms` (Lean/Util/CollectAxioms.lean:149-153) starts `runM` from the empty state `{}` (:23-24), and its
   only shared shortcut is `exportedAxiomsExt`, the per-module table that Lean precomputes on export (:136-141).
   mathview imports with `loadExts := false` (lean/MathViewMain.lean:345). Lean/Environment.lean:2428-2431 says
   that in that case "every extension will have its initial value as its state", so the table is empty. Every one
   of the ~4,077 entries re-walks its whole closure through Init and Lean core (up to 25,250 constants).
   Cost ≈ entries × closure, so it grew faster than the repo did. CONFIRMED (source), MEASURED (profile).
2. **Why it was built that way.** `loadExts := false` dates from the first commit of the Lean project (9367dea).
   Loading extensions requires `enableInitializersExecution` (same docstring, :2427-2428), and a plain export does
   not need the extensions, so `false` is the safe default. Nobody saw that it switched off the axiom cache
   (INFERRED). The whole-tree cache (`mathview-cached.sh`, 7d544e2) made replays free, but its key hashes every
   `Fw/**/*.lean` (mathview-cached.sh:14-17), so **every land that touches lean/ misses**. The land protocol
   (land-hardening) checks the exact merged state under the lock (land.ts:312-331). That was the right
   correctness choice when check.sh was short. CONFIRMED.
3. **Why nobody noticed.** (a) The timing spans only arrived today (2860daa, 2026-10-18 04:24 +0700). Before that,
   no land phase was timed. (b) Even with spans, `Fw.Obs.Timing` flags `slow` only when $d > \max(B, k\,b)$,
   where $b$ is the p90 of the step's **own** recent window (Timing.lean:15-20), and it needs $n_{\min}=5$
   samples (:99). A step that is slow from its first sample sets its own baseline and never alerts. check.sh has
   4 land samples, so it is still `noBaseline`. CONFIRMED.

## Proposals, ranked (saving per Lean-touching land; today ~126-153 s p50)

| # | change | saving | lock held after | risk |
|---|---|---|---|---|
| P1 | shared exact axiom-reachability memo in MathView | ~100 s (110 → 10.2 s, MEASURED once) | ~20 s | low |
| P2 | check DAG: build everything, then lint, tests, replay, breakgen and package tests in parallel | ~6-10 s after P1 (more on runner lands) | ~13 s | low-med |
| P3 | check before the lock: merge-tree → commit-tree → check C in a warm land worktree → ff under the lock | 0 s wall; lock 125-190 s → < 1 s | < 1 s | med |
| P4 | per-module (cone) lint cache in the git common dir, Merkle key = Lake depHash + tool blob | ~7-9 s after P1 (10 → 1-3 s) | (with P3) < 1 s | med |
| P5 | checksFor reads its declared inputs (a soundness fix) | 0 s (+~10 s on golden-only lands) | | low |

Rejected or deferred (negative results; each mechanism is stated):
- `loadExts := true`: collectAxioms totals 80 ms, but the import grows by 1.2 s, and the instance and notation state
  it loads can change the entry set and the `signature` text; the output was not diffed. Lean's own precompute also
  shares state across a cycle (CollectAxioms.lean:139-141). Rejected. MEASURED/CONFIRMED.
- A naive shared memo (666 ms) can cache a partial set inside an inductive-constructor cycle. Unsound; rejected.
  MEASURED.
- A whole-check.sh cache keyed by the `lean/` tree hash: the merged tree equals the branch tree in only 6 of 25
  recent Lean lands, so ~3-8 s average after P1. Covered by P4. MEASURED.
- Scoping by kind of change (docstring vs code): ~0 s. Docstrings live in the .olean and are what the lint checks.
  INFERRED.
- Splitting mathview across processes: after P1 the whole run is 6.7 s of CPU, and splitting re-pays import and
  render. INFERRED.

### Soundness: theorems (drafts typecheck on v4.35.0, axioms ⊆ {propext, Classical.choice, Quot.sound}; MEASURED)

**P1** (new, over an abstract finite graph `succ : α → List α`, `isAx : α → Bool`; write `axReach` with fuel =
number of constants, not `partial`):
- T1 fixpoint: $R(c)=\{c \mid \mathrm{isAx}(c)\}\cup\bigcup_{d\in\mathrm{succ}(c)}R(d)$.
- T2 memo invariant: $\big(\forall x\in\mathrm{dom}(M),\ M(x)=R(x)\big)$ is preserved. A search from $c$ at depth
  $k$ that returns $\mathrm{low}\ge k$ (it hit no in-progress node above it) returns exactly $R(c)$, and only such
  results are cached.
- T3 equivalence: a root search returns $R(c)=\mathrm{collectAxioms}(c)$, so old and new give the same set.
- `#guard`: on a 3-node constructor cycle, a naive shared memo returns a strict subset, and `axReach` returns $R$.
- Empirical premise: the old `collect` (CollectAxioms.lean:66-71) computes $R$. Test: the full-export diff, equal on
  all 4,077 entries except `heartbeats`. The lint text was byte-identical (370 lines). MEASURED.

**P2** (`seq_eq_all`, `all_perm`): if each job reads only its declared inputs and no job writes what another reads
(NonInterfere), then $\mathrm{seq}(js,\sigma)=\bigwedge_{j\in js}\mathrm{run}_j(\sigma)$, and
$js \sim js' \Rightarrow \bigwedge_{js}=\bigwedge_{js'}$. Premise E4: stage 1 builds every Lake target (fwcore,
mathview, breakgen, test driver). Stage 2 calls `.lake/build/bin/*` directly, never `lake exe`, so nothing rebuilds
while another job reads. CONFIRMED that the runner tests read fwcore (hooks/land-guard.mjs:18-21). Test: on Linux
CI, run each stage-2 job under `strace -f -e trace=openat` and assert reads ⊆ declared reads and writes disjoint
from the other jobs' reads. Mutation: a job that touches fwcore is refused by the NI gate.

**P3** (`pre_eq_old`, `pre_moved`, `pre_commit_checked`): with $T=\mathrm{merge}(m_0,b)$ checked and $C$ the commit
with parents $[m_0,b]$: if $h=m_0$ the outcome equals today's protocol; if $h\ne m_0$ nothing is committed (retry);
and if it commits then $\mathrm{parents}=[h,b]\wedge\mathrm{tree}=T\wedge\mathrm{chk}(T)$. It composes with
`Fw.Console.Land.landTip` (Land.lean:427) and `land_commit_exact` (Land.lean:572). The Lean change is a guard
$s.\mathrm{head}=m_0$ on `begin`. Empirical premises and their tests:
- `git -c attr.tree=<m0> merge-tree --write-tree m0 tip` reproduces 30 of the last 30 land trees, up to the
  evidence edit. Without `attr.tree`, 7 of 30 differ in `lean/Fw.lean`, because the `merge=union` driver in
  .gitattributes is skipped. MEASURED. Replay test in CI.
- **Today the committed tree is not the checked tree**: `writeEvidence` (land.ts:323) runs after `runChecks`
  (land.ts:318), and `apps/runner/test/plan.test.ts:49-50` reads `docs/team/work-graph.json`. CONFIRMED. P3 applies
  the evidence edit to T *before* checking, which removes the premise of `evidence_irrelevant`.
- The checked worktree must hold exactly C: `git checkout --detach C` plus `git clean -fdx -e .lake -e node_modules`.
  Mutation test: an untracked imported `.lean` file is cleaned (or refused).

**P4** (`mkey_sound`, `mkey_congr`, `lint_modular`, `integrity_push`, `lintAll_nil_iff`). The key is
$K(m)=H(m,\mathrm{src}(m),t,[K(i)]_{i\in\mathrm{imp}(m)})$, where $t$ hashes MathView*.lean, lean-toolchain, the
manifest and lakefile options. Lake's depHash already mixes the import traces, source, toolchain and options
(Lake/Build/Module.lean:600-627); $t$ must be added to it. Theorems:
- `mkey_sound`: $H$ injective ⇒ equal keys mean equal sources on all of $\mathrm{cone}(m)$.
- `mkey_congr`: a change outside $\mathrm{cone}(m)$ keeps $K(m)$.
- `lint_modular`: $\mathrm{ConeLocal}\wedge\mathrm{HInj}\wedge\mathrm{ModIntegrity}\Rightarrow\mathrm{lintInc}=\mathrm{lintAll}$
  (same lines, same order, same verdict).
- `integrity_push`: writing only fresh results keeps the store exact.

Empirical premises and their tests:
- E2 cone locality: no cross-module `attribute [`, `add_decl_doc`, `@[app_unexpander`, `notation` or `macro_rules`
  in lean/Fw (0 hits today, MEASURED). Add a grep gate in check-partial.sh.
- E3: the sort key becomes total, (module, line, name). There are 0 ties today, but qsort at MathView.lean:298 is
  not total.
- A CI differential job compares the incremental and full runs on the same tree, modulo `heartbeats`.
- Mutations: editing MathView.lean changes every $K$. A docstring edit in a leaf M changes only $K(M)$. An edit
  outside cone(M) keeps $K(M)$.

**P5** (`cache_sound`, `undeclared_refutes`). `checksFor` is itself a cache: a skipped check counts as a replayed
pass. It is sound only if reads(check.sh) is fully declared. Today it selects check.sh only for `lean/` paths
(land.ts:99), but `lake test` reads `packages/contracts/golden/**` (Fw/Obs/Timing.lean:913,917;
Fw/Parts/PlatformGolden.lean:11; Fw/Serve.lean:1135). CONFIRMED gap. The card fast-forward path also checks the
branch worktree without any cleanliness test (land.ts:268), and the main checkout is checked with
`--untracked-files=no` only (land.ts:164). Mutation test: a one-line change to
`packages/contracts/golden/obs/timing.jsonl` must select check.sh.

## The mistake (user rule: cause, Lean-provable?, hardening)
- **Cause.** A per-call library helper (`collectAxioms`) was used in a loop over all declarations, and its shared
  cache was off because `loadExts := false`. On top of that, a whole-tree cache key guarantees a miss on every Lean
  land, and the lock protocol puts the miss on main's critical path. The relative-only slow rule kept it invisible.
- **Lean-provable?** Yes. P1 T1-T3 prove that the fast path gives the same result. For the detection gap, prove in
  `Fw.Obs.Timing` `self_baseline_hides`: if every window sample is $\ge d/k$, then the verdict is not `slow` for any
  $d$, so a step that is slow from day one never alerts. Its fix is `ceiling_alerts`: with a new per-step absolute
  ceiling $C$, $d>C(\mathrm{step})\wedge\neg\mathrm{noisy}\Rightarrow\mathrm{verdict}=\mathrm{overCeiling}$, with no
  baseline and no $n_{\min}$ needed.
- **Hardening.**
  - Ceilings: `fw land` total 30 s, `lean/check mathview lint` 20 s, and a new `fw land / lock held` span 5 s.
  - A `#guard` replays the four measured check.sh spans (112-192 s) and asserts `overCeiling`.
  - An `inc-land-slow` incident record.
  - The P5 declared-reads list is shared by checksFor, the module cache and the NI gate.

## Recommended implementation plan (Lean first; each task gives before/after spans)

| id | owner (.claude/agents) | writes | deps | Lean-touching land p50 / lock held after it |
|---|---|---|---|---|
| land-speed-lean | lean-prover | lean/Fw/Console/LandSpeed.lean, lean/Fw.lean, packages/contracts/golden/console/land-speed.jsonl | – | unchanged (spec only) |
| mathview-axreach | lean-prover | lean/MathView.lean, lean/Fw/Spec/AxReach.lean, lean/Fw.lean | – | ~26 s / ~20 s |
| land-timing-ceiling | measure-engineer | lean/Fw/Obs/Timing.lean, packages/contracts/golden/obs/timing.jsonl, apps/runner/src/land.ts (lock-held span only), docs/team/incidents/** | – | alerts on regression |
| checksfor-inputs | console-builder | apps/runner/src/land.ts, apps/runner/test/land-*.test.ts | land-speed-lean, land-timing-ceiling | +0 s (soundness) |
| check-dag | console-builder | lean/scripts/check.sh, lean/scripts/check-partial.sh, apps/runner/src/land.ts (runChecks) | mathview-axreach, checksfor-inputs | ~19 s (runner lands ~21 s) / ~13 s |
| land-prelock | console-builder | apps/runner/src/land.ts, lean/Fw/Console/Land.lean, hooks/land-guard.mjs, apps/runner/test/** | check-dag, land-speed-lean | ~19 s / < 1 s |
| mathview-module-cache | lean-prover (Lean, key) + console-builder (wrapper) | lean/MathViewMain.lean, lean/MathView.lean, lean/scripts/mathview-cached.sh, .github/workflows/** (differential job) | mathview-axreach, check-dag | ~13 s / < 1 s |

- Order: three parallel starts (land-speed-lean, mathview-axreach, land-timing-ceiling). After that, `land.ts`
  writers run in series: checksfor-inputs → check-dag → land-prelock. The target (Lean land < 20 s p50, lock < 5 s)
  is met after **land-prelock**. INFERRED from the spans above.
- Next hot spot (not investigated): `worktree cleanup` (5.5 s p50, 13 s max) runs after the lock but inside
  `fw land`. Once the module cache is in, it is ~40% of the land.
- The drafts (LandSpeed.lean with 336 lines of proved statements, axreach.patch, the profiler, affected.py,
  cone.py) are in this session's scratchpad under `land-speed/`. They are not committed; land-speed-lean and
  mathview-axreach start from them.

## What this changes in the plan
- **docs/team/work-graph.json, tooling stream (M5)**: add the seven tasks above with these deps.
  `land-speed-research` → done with this note.
- **docs/plan/PLAN.md, the land / console section**: the land protocol becomes "check the pre-made merge commit C
  outside the lock, then compare-and-fast-forward under the lock" (P3). The Lean-first spec for it is
  Fw.Console.LandSpeed plus a head-guard on `Land.begin`.
- **docs/plan/PLAN.md, the timing / observability section**: `Fw.Obs.Timing` gains absolute per-step ceilings
  (`fw land` 30 s, mathview lint 20 s, lock held 5 s). A relative baseline alone is no longer the only slow rule.
