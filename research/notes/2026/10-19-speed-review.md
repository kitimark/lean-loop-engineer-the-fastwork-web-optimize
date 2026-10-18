---
id: fable-speed
kind: advice
title: "Fable: faster tests, lint, land checks, Lean builds and CI (ranked)"
status: draft
created: 2026-10-18
inputs: [speed-local.md, speed-ci.md, speed-lean.md, ci-inventory.md]
---

# Fable: where to cut time, ranked

Repo `main` 9e09d311. I re-derived the local numbers from `.fw-console/timings.jsonl` (19,442 spans) and re-read every cited
line; the three notes hold. Two changes carry almost all of the gain, and both fit before C3.

## Answer

| | Finding | Status |
|---|---|---|
| 1 | Local lands: the land wall is set by `apps/runner test`, which jumped 96-110 s → 231-242 s in its last 5 runs because `wait-guard.test.ts` starts one `fwcore` per case (225 spawns, 229 s). `gate-breakpoints test` did the same, 44-55 → 102-109 s (`verdict.test.mjs:22-26`, one spawn per literal case). Successful lands: p50 69 s, p90 235 s, max 326 s. | MEASURED (timings; wait-guard.test.ts:60-62,67-68; verdict.mjs:27 already batches) |
| 2 | CI: the `lean` lane went 3.4 → 13.6 min median because `mathview-differential` (lean.yml:110) runs on every ci/* push (lean is the default lane: Intent.lean:34-35, `lean_never_unchanged`), and its full `mathview --lint` got ~5x slower (18 → 95 s, run 5 times, lean.yml:147-191). The last 9 finished lean runs took 12-28 min. Agents sat 27.5 h in `fw ci wait` (205 waits, p50 9.0 min). | MEASURED (gh run list; timings `ci wait`) |
| 3 | CPU, not wall: every `fwcore` spawn costs ~0.7 CPU-s; the wait-guard hook spawns one per Bash call (17,726 in 15.3 h ≈ 12k CPU-s ≈ 0.22 cores), and check.sh forks 20 uncapped jobs (check.sh:38-70) while lands run ≥ 4 checks (`poolFair`, LandPool.lean:30). Load p50 21, p90 54, max 194 on 8 cores. 315 of 433 check.sh runs were agents outside lands. | MEASURED (sample for the 0.7 s, load ~10) |
| 4 | Load caused 3-5 of 27 refused checks; 22 were real. The `ask` 3 s default (spawn-guard.mjs:47, used at wait-guard.test.ts:68) fails as an assertion, which `LOAD_FAILURE_RE` (land.ts:300) does not match, so Lean `rerunAlone` (LandPool.lean:107) never re-runs it. | CONFIRMED |

## Ranked improvements

Class A = do now (small, shortens the path to C3). B = after C3. C = not worth it. Savings per land use ~125 lands/day (103 in
19.4 h); per CI push use ~80 ci/* pushes/day (21 lean runs in the 6 h after the opt-in). Extrapolations are INFERRED.

| # | Class | What | Files | Saving | Evidence | Risk | Lean piece |
|---|---|---|---|---|---|---|---|
| 1 | A | Batch `wait-guard.test.ts` into one `call` per describe (one fwcore process, N JSON lines; same semantics as the golden wire replay, check.sh:46, and `verdict.mjs:27`) | apps/runner/test/wait-guard.test.ts:60-62,67-68 | runner test 240 → ~40 s; land wall −140 s p90 (runner is the longest pool check); ~170 CPU-s per land; ~5 h land latency/day | 10 spawns 13.85 s vs 1 process 1.46 s (MEASURED sample) | None for correctness: `ops.wait` is stateless; a reply mismatch still names the case. Only the per-case 30 s timeout becomes one bound | Already proved: `Fw.Wire.handleLine` per line; state no theorem needed. Golden stays the oracle |
| 2 | A | Batch the literal cases in `verdict.test.mjs` (one `call(cases.map(...))` for the non-error cases, as `golden: cases` already does at :18) | packages/gate-breakpoints/test/verdict.test.mjs:22-26 | gate test 105 → ~50 s; −55 s per land when it is the critical check | MEASURED 60-68 s step | None (error cases stay one-per-call) | none |
| 3 | A | `mathview-differential` runs only when its inputs change: `lean/MathView*.lean`, `lean/scripts/mathview-cached.sh`, `Fw/Spec/MathFacts.lean`, `Fw/Spec/AxReach.lean`, `Fw/Spec/ConeMiss.lean`, lakefile/manifest/toolchain, lean.yml; always on `main` and on dispatch | lean/Fw/Ci/Trigger.lean, Intent.lean (per-job row), packages/contracts/golden/ci/triggers.jsonl, .github/scripts/changed-inputs.mjs, lean.yml:110-116 (`if:` on a guard output per job) | lean lane 13.6 → ~4 min: −9.6 min wall per push, −13 job-min; ~13 h agent wait/day, ~17 runner-h/day | runs 39142015108/39139487385/39136948064: lean job 2.1-4.0 min, differential 11.7-13.6 min | Could hide a cache-soundness bug that only a Fw/** change exposes (data-dependent key bug). Accepted limit: `main` pushes still run it, and the `lean` job's cached lint still lints the tree | New: job inputs $I_j$; $$\mathrm{skip}(j,\Delta) \Rightarrow \forall p\in\Delta,\ p\notin\mathrm{scope}(I_j)$$ and $$\mathrm{event}\in\{\texttt{main},\texttt{dispatch}\}\Rightarrow \neg\mathrm{skip}(j,\Delta)$$; restate `lean_never_unchanged`/`tip_lean_always` for the `lean` *job*, not the workflow |
| 4 | A | Load class for `rerunAlone`: a null/"unavailable" fwcore reply counts as a load failure; and use 30 s at wait-guard.test.ts:68 as :61 does | lean/Fw/Console/LandPool.lean:106-115, apps/runner/src/land.ts:300, wait-guard.test.ts:68 | removes 2-4 of 27 refusals (each a 2-4 min re-land) | land logs integrate-ports-4-89d6f30/-217ed15 | A real crash that prints "unavailable" is re-run once alone, then fails again: no hidden failure (`settle` takes the second result) | $$\mathrm{lf}'(o)=\mathrm{lf}(o)\lor \texttt{unavailable}\in o,\quad \mathrm{re}(o)\Rightarrow\mathrm{lf}'(o)$$, keep $\forall f.\ \mathrm{rerun}(\top,f)=\bot$ |
| 5 | A (no code) | Prompt rule: before `git push origin ci/*` run `sh lean/scripts/check.sh` (or at least `scripts/mathview-cached.sh`, 9 s p50) | docs/team prompts | 3 of 4 sampled lean failures were lint: ~20 of 28 × 4-15 min round trips | runs 39113394772, 39125672589, 39140966688 | none | none |
| 6 | A (no code) | Gate practice: narrowed `--parts` runs while iterating, one whole-page run as the record; never re-dispatch a branch while its run is live | — | ~94 job-min per avoided duplicate (39141826450 + 39142015714, 2 min apart) | ci-shape, gh | none | exists (`scope_sound`) |
| 7 | A (no code) | Contention: agents outside lands run only the step they changed (`mathview lint`, one golden) and the full check.sh once before commit; lead runs ≤ 1 land while the six lanes build | — | fewer load refusals; 315 of 433 check.sh runs were outside lands | timings `load` | none | none |
| 8 | B | Find the 5x `mathview --lint` slowdown (export 122k → 253k lines for 162 → 216 modules); measure from CI job logs with `--stats` | lean/MathViewMain.lean, lean.yml | −80 s × 5 per differential run; local lint max 266 s | 39114796889 vs 39142015108 | none | none (perf) |
| 9 | B | Cap check.sh's parallel group at `max(1, ⌊c/2⌋)` jobs; fold the three `sweepsgen --sweeps` jobs into one process with 3 `--check` paths | lean/scripts/check.sh:38-55, Lean `Fw.Console.LandPool` | ~13 CPU-s per run; less memory pressure; no wall gain at low load | p50 group 14.1 s, props lint 18.8 s sets the wall | none (`verdict_perm`) | $$\mathrm{verdict}(\pi(J))=\mathrm{verdict}(J)$$ for any schedule $\pi$; cap = `poolFair c c` |
| 10 | B | Serve the wait-guard hook from one long-lived `fwcore serve`, or a Lean pre-filter | apps/runner/hooks/wait-guard.mjs:78, spawn-guard.mjs:47 | ~0.2 cores all day (~12k CPU-s / 15 h) | obs.jsonl count | A pre-filter that is wrong lets a wait through: must be proved conservative | $$\neg\mathrm{mayWait}(c)\Rightarrow\mathrm{decision}(c)=\mathrm{allow}$$ over the golden |
| 11 | B | Check-result cache keyed by `inputKey` (skip a check whose key matched a stored pass) | land.ts:237, LandSpeed.lean:77 | a retried land (integrate-ports-4 ran 3×) costs ~0 | CONFIRMED "not used for caching yet" | relies on A1 `land.noCollision` and declared reads | exists: `cache_sound`, `cachedRun_eq`, `integrity_push` |
| 12 | B | Compile `props lint` into a subcommand; move `FwTestMain` out of fwcore's link cone; keep the cache hard link on strip | lean/scripts/PropsLint.lean, lean/Main.lean:3, fwcore-build script | props lint 18.8 → few s (sets check.sh wall); smaller relinks (104 MB per edit); 7 % disk | speed-lean §2-5 | none | none |
| 13 | B | Replace `rfl` JSON-lookup proofs in `Fw/Wire/Obs.lean:421-470`, Wire/Sched, Sched/Admit with `simp` lemmas | those files | ~35 s off any build whose cone holds Wire.Obs (depth-17 chain) | one profile, load 12-18 | none (same theorem) | same statements, cheaper proof |
| 14 | B | Counts: one `{search, run}` matrix per dispatch sharing the 6 setup jobs; reuse `fwcore-linux-arm64` from lean.yml in the 4 other builders | chromium-counts.yml, webkit-sim.yml, wktr | 3.5 min setup per extra dispatch; 1-2 job-min per sha | inventory §4, speed-ci §3 | none | already a Lego follow-up (`goldenRuns`) |
| 15 | B (lead) | Heavy lanes on `main` pushes (gate, counts, webkit-sim re-run what ci/* verified): keep only if something reads them | changed-inputs.mjs:21, Intent `main_keeps_paths_rule` | ~420 wall-min per 10 h before the opt-in | speed-ci §5 | drops the only post-merge record | $$\mathrm{mainRun}(L)\iff L\in\mathrm{readers}$$ |
| 16 | B | Drop `scope.test.mjs` regeneration (44-49 s) once shown equal to check.sh:55 `sweepsgen scope --check`; `freeze.test.mjs:160` `lake env lean --run` (32-36 s) | packages/gate-breakpoints/test | −45 s gate test after #2 | land logs | the test may assert more than the byte check; verify first | none |
| 17 | C | Compile the other 8 `lean --run` goldens (1-2 s each); macOS boot/teardown (181 s per 22 min job, fixed cost); Lake CI cache (14 s restore, 85 s partial-hit build) | — | small | speed-lean §2, speed-ci §3 | — | — |

## Order and dependencies

1. #1, #2, #4 are test-only edits in one branch (`land-test-speed` exists): land wall p90 235 → ~100 s, CPU −170 s per land. No
   new tooling; they shorten every land in the critical path.
2. #3 is one Lean row plus the guard's per-job output; it is the only CI change before C3 and pays back on every push. Pin
   the unit of decision: a job, with `lean` keeping its default-lane proof. Mathview-differential keeps running on `main`.
3. #5-#7 are prompt text today.
4. Everything else after C3; #8 first (it also lifts the local lint tail), then #9-#12.

## Process changes (no code)

- One land at a time while the six lanes build; agents run the one check they touched, full check.sh once before commit.
- `mathview lint` before any ci/* push.
- Gate: narrowed runs to iterate, one whole-page run per branch as the record; no duplicate dispatch within a run's life.
- No `lake build` in a fresh worktree is needed (artifact cache, lakefile.toml:8-14, p50 3.5 s); do not run `lake clean`.
- Prune the Lake artifact cache (62 GB, 55 GB unreferenced) per docs/team/tools/disk-cleanup.md when disk allows.

Not measured: claim-lint and mathdoc (no spans); why `mathview --lint` is superlinear; the hook's CPU (count × one sample).

## Adversarial check (reviewer)

Fixes:
1. `scratchpad/fable-speed.md`, Answer row 1: replace "jumped because wait-guard starts one fwcore per case" with "per-spawn cost rose under load (test files unchanged a020b32→90337d4); per-case spawns make it scale with load".
2. Same file, A4: drop the `LOAD_FAILURE_RE`/Lean `lf'` part. Keep only `apps/runner/test/wait-guard.test.ts:68` `ask(bin, {...})` → `ask(bin, {...}, 30_000)`. Its "Saving" cell becomes "prevents a future load refusal at :68; 0 recorded".
3. Same file, A3: move it to class B. Restate the saving as "−9.6 min only on pushes where lean is the slowest requested lane; job-min saving −9.6/push". Delete "13 h agent wait/day".
4. Same file, A1/A2: give the land-wall target as "about 100 s, bounded by the next 67-75 s vitest file". Mark the A2 50 s as INFERRED until one land log shows it.

Bottom line:
- Keep A1 (batch wait-guard.test.ts) and A2 (batch verdict.test.mjs literals): test-only, the numbers reproduce, and they shorten every land.
- Keep A4 reduced to the :68 30 s timeout.
- Keep A5-A7 as prompt rules (no code).
- Defer A3 until after C3: it is a new mechanism, its saving is double counted, and it puts the cache-soundness check after merge.
