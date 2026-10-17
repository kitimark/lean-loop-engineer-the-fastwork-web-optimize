# 05: Lean 4 in the loop: what to prove, how to test, how to build a provable console backend

Kickoff research note, 2026-10-17. Author: research agent (topic 05). Status: proposal for the plan architect and
the user to review.

Labels: **CONFIRMED** = checked against a cited doc, source file, release or a run I made. **INFERRED** = my
reasoning or recollection, not checked. **MEASURED** = I ran it on this Mac (Apple Silicon, macOS 27) in a
scratch Lean install (below).

---

## 0. TL;DR

1. **Recommendation: "Lean decides, TypeScript does" (architecture (i), with (ii) limited to the boundary).**
   The decision logic lives in one Lake project (`lean/`) as pure functions with theorems: verdict rules, tick
   math, the cost model, flag resolution, and the lock, lifecycle and step state machines. It compiles to one
   native executable, `fwcore`, a JSON-lines worker over stdin/stdout. The Node/TypeScript console backend
   (Hono/Express, the shadcn UI's API) does all I/O: HTTP, files, storage, Chrome/CDP, devices and clocks. It never
   re-implements a decision. Differential testing (fast-check traces against `fwcore`) is used only where a
   decision has to be duplicated in TS, for example a client-side preview in the console UI.
2. **I built a working prototype of this design.** `research/kickoff/05-lean-sketch/` (630 lines of Lean) builds
   with `lake build` on Lean v4.35.0. It has **no `sorry`**, and `#print axioms` shows only `propext`,
   `Classical.choice` and `Quot.sound`. It proves:
   - tick math: `k ≥ 7 ↔ dt ≥ 54 167 µs`
   - the v1 non-overlap verdict: soundness, the n≥3 gate, control/variant symmetry and direction duality
   - a FIFO device lease: the invariant is kept by every step, plus I-113 "re-queue keeps place", I-091 "renew
     never shortens" and FIFO hand-over
   - flags: a config is total by construction, and single-part A/B isolation
   - lifecycle: R→I→D→F→V→L moves exactly one stage per step, and F is reachable only through a NAMED, lead-signed D
   - a linear cost model: monotone, and compositor-only work adds no main-thread cost

   `lake test` runs Plausible on 2 000 random lease traces. On this Mac:
   - clean build: 23 s, including fetching Plausible
   - rebuild after editing one module: 0.5 s
   - no-op rebuild: 0.2 s
   - `fwcore` startup: 30 ms
   - 100 k requests piped through: 0.35 s
   - a Node round trip: about 140 µs
3. **Mutation check (MEASURED).** I put back the v1 bug class I-091, where renew sets `expires := now+ttl`. `lake build`
   then fails at `renew_never_shortens`. I also removed the I-113 guard; then `requeue_keeps_place` and
   `step_inv` stop building. In v1, both bugs reached production and were found by incidents.
4. **No Mathlib in the core.** Core Lean already has `omega`, `decide`, `simp`, `grind`, `Rat`, `Lean.Json`,
   `#guard` and `Std.Http`, which covers everything above. Mathlib costs several GB of cache, and every file that
   imports it loads slowly. Keep it out of `fwcore`. If a deep statistics proof is ever needed (exact
   permutation p-values, Hodges–Lehmann properties), put it in a separate optional `FwMath` package.
5. **Tooling for agents:**
   - `lean-lsp-mcp`: goals, diagnostics, `lean_verify` axiom audit, `lean_multi_attempt`, Loogle and LeanSearch
   - Serena: has a Lean 4 language server since PR #1137 (2026-03-12)
   - `cameronfreer/lean4-skills`: a Claude Code skill for Lean work

   None of these needs Mathlib.
6. **How this cuts the "re-run all tests" pain.** A theorem is checked once, when its module compiles, and covers
   every input. Lake rebuilds only modules whose inputs changed. So:
   - proved properties need no runtime tests;
   - what is left to test at runtime is the glue: the JSON codecs, the TS adapters, persistence and the engines'
     fit to the model;
   - when a tool is adopted or changed, only the boundary tests of the changed adapter re-run.

---

## 1. What I ran (scratch install, nothing global)

- elan v4.2.4 binary from GitHub releases, installed with `ELAN_HOME=<scratchpad>/elan-home elan-init -y
  --no-modify-path`, toolchain `leanprover/lean4:v4.35.0`. No shell profile or PATH change, nothing outside the
  session scratchpad except the copied sources (MEASURED).
- **Toolchain on disk: 2.8 GB** (MEASURED, `du -sh elan-home`). The project's `.lake` is 214 MB, of which
  Plausible is 15 MB (MEASURED).
- Lean version string: `Lean (version 4.35.0, arm64-apple-darwin24.6.0, commit eb6cafb7…, Release)` (MEASURED).
  The latest releases are v4.35.0 (2026-10-12) and v4.36.0-rc1 (2026-10-14) (CONFIRMED, `gh api
  repos/leanprover/lean4/releases`).
- The sketch was copied into the repo at **`research/kickoff/05-lean-sketch/`**, without `.lake/`, which a
  `.gitignore` there excludes. To reproduce:
  `cd research/kickoff/05-lean-sketch && lake build && lake test && echo '{"op":"verdict","dir":"lower","ctl":[5,6,7],"var":[1,2,3]}' | .lake/build/bin/fwcore`.

| measurement (MEASURED, M-series Mac) | value |
|---|---|
| `lake build`, clean, incl. git fetch of Plausible | 23 s wall (16 jobs) |
| `lake test`, first time (builds Plausible) | 6 s |
| `lake test`, warm | 4 s, incl. 2 000 random traces |
| rebuild after editing `Fw/Spec/Flags.lean` | 0.54 s (only that module) |
| no-op `lake build` | 0.2 s |
| `fwcore` binary | 101 MB (73 MB stripped). Links only `libc++` and `libSystem` (`otool -L`). Size comes from statically linking the Lean runtime plus `Lean.Data.Json`'s package |
| `fwcore` cold-cache start + 1 request | 30 ms |
| 100 000 verdict requests piped | 0.35 s (≈3.5 µs each) |
| Node 24 → `fwcore` sequential round trip (child_process + readline) | ≈141 µs |

---

## 2. Lean 4 ecosystem, late 2026

| item | status | notes / source |
|---|---|---|
| elan / lake / `lean-toolchain` pin | CONFIRMED | Each project pins its toolchain, and elan fetches it on demand. Lake reads `lakefile.toml`. `lake test` and `lake lint` use `testDriver` / `lintDriver` (Lake README, `src/lake/README.md` at v4.35.0 l.219-226). |
| `#guard`, `#guard_msgs`, `#eval` | CONFIRMED in core | `src/Lean/Elab/Tactic/Guard.lean` l.146-157 (`#guard`), `src/Lean/Elab/GuardMsgs.lean`. They run while the module compiles, so a failing one fails `lake build`. |
| Decision procedures | CONFIRMED in core | `omega` (linear Nat/Int arithmetic, incl. `/` and `%` by literals), `decide`, `simp`, `grind` (`src/Lean/Elab/Tactic/Grind.lean`). All proofs in the sketch use only these and `cases`/`induction`. |
| `Std.Do` / `mvcgen` | CONFIRMED, experimental | A Hoare logic for monadic (do-notation) programs. Introduced in v4.22.0 as experimental; `mvcgen'` was reimplemented in v4.31 ([v4.22.0 notes](https://lean-lang.org/doc/reference/stable/releases/v4.22.0/), [v4.31.0 notes](https://lean-lang.org/doc/reference/4.33.1/releases/v4.31.0/)). Not needed if the core stays pure (`State → Cmd → State × Reply`). |
| `Rat` | CONFIRMED in core | `src/Init/Data/Rat.lean`. Use it for exact ratios such as p-values. |
| `Float` | CONFIRMED caveat | IEEE binary64 with only a partial logical model. Some operations are opaque. `native_decide` on Float trusts the compiler ([reference: Floating-Point Numbers](https://lean-lang.org/doc/reference/latest/Basic-Types/Floating-Point-Numbers/)). **Design rule:** the decided core uses `Nat`/`Int` µs and `Rat`. The shell converts ms floats to integer µs at the boundary. |
| JSON | CONFIRMED | `Lean.Data.Json` with `deriving Lean.ToJson, Lean.FromJson` (`src/Lean/Data/Json/FromToJson.lean`). The derived wire shape is MEASURED: a constructor with arguments becomes `{"acquire":{"o":"x","now":1,"ttl":900}}`, a nullary one becomes `"released"`, and `Option` becomes `null`/value. The TS side must match it, so it is pinned by golden fixtures (§6.4). |
| HTTP / async | CONFIRMED | `Std.Async` (TCP, UDP, DNS, timers, processes, signals, select) and **`Std.Http`**: "a pure, sans-I/O HTTP/1.1 server" with keep-alive, chunked encoding and `Server.serve` (`src/Std/Http.lean` at v4.35.0). Moved out of `Std.Internal` in PR #13511 (2026-04-23). HTTP/1.1 only: `Std/Http/Protocol/` holds only `H1`. No WebSocket in `src/Std` (code search, 0 hits). TLS: INFERRED absent. The FRO Year 3 roadmap names "a new HTTP server library" for Std 1.0 ([roadmap y3](https://lean-lang.org/fro/roadmap/y3)). Third-party libraries: axiomed/Http (WIP, libuv) and hargup/http-client (curl FFI). |
| SQLite | CONFIRMED gap | No maintained binding found. `drcicero/sqlite.lean` was last pushed 2024-08 with 7 stars. Others are toys (`gh search repos`). Storage stays in Node (`node:sqlite` or JSON files; INFERRED: `node:sqlite` works unflagged in Node 24). |
| Compiler → C, FFI | CONFIRMED | `@[extern]` / `@[export]`. A C host must call module initializers and `lean_io_mark_end_initialization`. The docs say the FFI "was designed for internal use in Lean and should be considered unstable" ([reference: FFI](https://lean-lang.org/doc/reference/latest/Run-Time-Code/Foreign-Function-Interface/)). **So don't build a Node N-API addon on it.** Use the process boundary. |
| Batteries | CONFIRMED active | `leanprover-community/batteries`, pushed 2026-10-16. Not needed for the sketch. |
| Mathlib | CONFIRMED active; cost INFERRED | `lake exe cache get` is required, or Mathlib "will be rebuilt from scratch (which can take hours)" (Lake README l.445). Cache size: several GB of `.olean`s (INFERRED; I did not download it). **Avoid in `fwcore`.** |
| Plausible (property testing) | CONFIRMED | `leanprover-community/plausible`, tags follow toolchains (`v4.35.0`). It supports `deriving Arbitrary` and `deriving Shrinkable` (`Plausible/DeriveShrinkable.lean`, © AWS 2025), the `plausible` tactic, `Testable.check` (CoreM) and `Testable.checkIO` (IO). MEASURED gotcha: `checkIO` needs the property wrapped in `NamedBinder "x" (∀ x, …)`, because only the decorated form has a `Testable` instance. `Testable.check` adds the wrapper itself. |
| LSpec | CONFIRMED | `argumentcomputer/LSpec`, Hspec-style `TestSeq`, pushed 2026-10-07. Optional: core `#guard` plus a test exe covers the need. |
| lean4-cli | CONFIRMED | `leanprover/lean4-cli` (the one Lake uses). Only needed if `fwcore` grows CLI subcommands. |
| Verso | CONFIRMED | `leanprover/verso`, for docs with checked Lean code. Could later render "the rules" page from the specs. Optional. |
| Lean REPL | CONFIRMED | `leanprover-community/repl`. lean-lsp-mcp can use it for fast `lean_run_code`. |
| Maturity as a *production backend* | INFERRED (with CONFIRMED anchors) | Lean in production is mostly specification plus verified core, with the I/O in another language. AWS Cedar does exactly this: a Lean model with proofs, and **differential random testing** against the Rust production code. Proofs found 4 bugs and DRT/PBT found 21 more ([arXiv 2407.01688](https://arxiv.org/abs/2407.01688), [lean-lang.org Cedar case](https://lean-lang.org/use-cases/cedar/)). Lean's own compiler, Lake and LSP server are large production Lean programs. A full web backend in Lean is not well trodden: `Std.Http` is six months out of `Internal`, there is no DB binding, and `Std.Do` is experimental. |

### 2.1 Lean + LLM-agent tooling

| tool | what it gives an agent | status |
|---|---|---|
| **lean-lsp-mcp** (`oOo0oOo/lean-lsp-mcp`, 530★, pushed 2026-09-30) | `lean_goal`, `lean_diagnostic_messages`, `lean_hover_info`, `lean_multi_attempt` (try N tactics at a line), `lean_run_code`, `lean_build`, `lean_local_search` (ripgrep), `lean_loogle`, `lean_leansearch`, `lean_leanfinder`, `lean_hammer_premise`, **`lean_verify`** (lists axioms, so a hidden `sorryAx` shows up, and scans for `unsafe`, `debug.skipKernelTC`, `implemented_by`), `lean_minimal_hypotheses`. Project-scoped setup: `claude mcp add lean-lsp -s project uvx lean-lsp-mcp`, which writes `.mcp.json`. `LEAN_MCP_DISABLED_TOOLS` can switch off `lean_run_code` for reviewers. | CONFIRMED (README, `docs/tools.md`). External search tools are rate-limited to 3 requests / 30 s. |
| **lean4-skills** (`cameronfreer/lean4-skills`, 464★) | A Claude Code skill for Lean proving; the lean-lsp-mcp README recommends it. | CONFIRMED to exist. Fit for our non-Mathlib code: INFERRED, review before adopting. |
| **Serena** | Has a `LEAN4` language: `.lean` files, `lean --server`, and `LEAN_PATH` from `lake env` for cross-file references (`src/solidlsp/language_servers/lean4_language_server.py`, added in PR #1137, 2026-03-12). Needs `lean` on PATH. Our `.serena/project.yml` currently has `language_servers: []`. Set it to `["typescript", "lean4"]` (the first one is the default). | CONFIRMED (source). |
| Loogle / LeanSearch / LeanExplore / LeanFinder | Type-pattern and natural-language search, mostly over Mathlib. Less useful without Mathlib; `lean_local_search` covers core and our code. | CONFIRMED to exist (`nomeata/loogle`, `lean-explore/lean-explore`). |
| LeanDojo, Kimina server, DeepSeek-Prover-V2, Goedel-Prover-V2 | ML theorem-proving research and competition-maths provers. LeanDojo last pushed 2026-01. The prover repos are 2025. | CONFIRMED to exist. **Not needed here:** our goals are small, decidable and arithmetic, and `omega`/`simp`/`grind`/`decide` close them. A strong general model plus lean-lsp-mcp is enough (INFERRED from the sketch: every proof was closed with core tactics in ≤3 iterations). |

Agent lessons from writing the sketch (MEASURED; worth putting in the Lean team's CLAUDE.md):
- `omega` does **not** see through `abbrev Us := Nat`. It treated `37500 ≤ dt` as an opaque atom and failed. Use
  plain `Nat`/`Int` in arithmetic statements, or a `structure` with explicit coercions.
- `omega` does not split `↔`. Use `constructor <;> intro h <;> omega`.
- `if_neg` and `if_false` are deprecated on v4.35. The linter suggests `ite_eq_right` / `ite_false`.
  `simp only [h, ite_false]` is a robust pattern.
- `split at h` cannot see through a `let` in the definition body. Move the `if` into a named helper (`where check …`)
  and `unfold` it.
- Plausible: use `deriving Repr, Arbitrary, Shrinkable` on a small *trace-command* type with `Fin n` fields, so
  owners collide often, rather than generating raw strings.

---

## 3. Evidence from v1: why this is worth it

- **Lock and lease code was the top bug source.** By keyword match on titles, 89 of 276 incidents in
  `console/incidents.json` are lock, lease or queue incidents (INFERRED classification by regex over titles;
  titles CONFIRMED). The ones a state-machine spec would have caught:
  - I-005: lock is not re-entrant across pids, which deadlocks
  - I-011: short lane starves
  - I-041: "granted co-holds on the LIVE chrome-measure lock; exclusivity broken 16:28-16:45Z"
  - I-049: shared readers starve under writer preference
  - I-091: renew shortened a longer lease
  - I-097 and I-136: priority and reader rules interact
  - I-113: "waiter lost its queue place on re-queue"
  - I-122 and I-123: lease expired in the middle of a user step

  `tools/lib/lock.mjs` is 1 685 lines, and the CLI header of `tools/lock.mjs` alone documents about 15 interacting
  rules (l.1-60).
- **Console and steps:** 69 of 276 titles are console, thread or step incidents, e.g. I-059 "the user can tap Done on a part the
  runner ends itself" and I-085 "'nullnull' above answer buttons". The first is a lifecycle-transition bug a
  spec would catch. The second is UI glue, which stays tested the normal way.
- **The tests were slow and flaky:**
  - `npm test` ran about 1 250 tests (`console/incidents.md` l.1211: "1252/1253")
  - 137 unit and 82 e2e test files
  - the commit-hook `npm test` took "~253 s" (I-114)
  - several flaky tests were caused by host load: I-120, I-121, I-159
  - I-021: non-tooling agents ran the full suite, taking the lock slot and CPU
- **The decision code is small and pure:**
  - `tools/lib/ab-stats.mjs` l.34-39: n<3 gives no verdict; non-overlapping ranges give better or worse
  - `tools/lib/stats.mjs` l.42-46: `TICK_MS = 1000/120`; `tick` is a float `Math.round` with a 1e9 guard
  - `tools/lib/stats.mjs` l.216: `sequentialDecision`
  - `tools/lib/stats.mjs` l.429: `twinsFor`

  The rules are specified in prose in `research/architecture/measurement-protocol-v2.md` §3.2 and §5.3, and in
  CLAUDE.md "Calibrated measurement setting" (l.134-158). Small, pure and critical is the ideal shape for a
  verified core.

---

## 4. (a) WHAT to prove

Legend: **P** = proved in the sketch (path:theorem), **T1** = do in the first wave, **T2** = later, **✗** = do not
prove (test or measure instead).

### 4.1 A/B statistics and verdict rules

| property | statement (informal) | status |
|---|---|---|
| Tick exactness | `tick dt = ⌊(240·dt + 10⁶)/(2·10⁶)⌋` (µs). `5 ≤ tick dt ↔ 37 500 ≤ dt`; `7 ≤ tick dt ↔ 54 167 ≤ dt` | **P** `Fw/Spec/Frames.lean: tick_ge5_iff, tick_ge7_iff` |
| Tick monotone | `a ≤ b → tick a ≤ tick b` | **P** `tick_mono` |
| Threshold-count antitone | `t ≤ t' → countAbove t' xs ≤ countAbove t xs`, so the twins are ordered: gt54 ≤ gt50 ≤ gt46 per run | **P** `countAbove_antitone` |
| "Tick-sensitivity" is a +3.5 ms twin | `#{k ≥ 5} = countAbove 37 499`: the legacy ">34" and the tick ">34" differ exactly on frames in (34, 37.5) ms | **P** `tick5_eq_countAbove`. This makes the v1 "threshold-sensitive" label mechanical. |
| Verdict soundness | `verdict .lower ctl var = .better → ∀ y∈var, ∀ x∈ctl, y < x` (max var < min ctl, i.e. U = 0) | **P** `Fw/Spec/Verdict.lean: better_sound` |
| n ≥ 3 gate | `verdict d ctl var = .better → 3 ≤ |ctl| ∧ 3 ≤ |var|` | **P** `better_needs_runs` |
| Symmetry | swapping control and variant turns better into worse | **P** `swap_better` (uses `below_antisymm`) |
| Direction duality | `verdict .higher ctl var = verdict .lower (−ctl) (−var)` | **P** `verdict_higher_eq_lower_neg` |
| Monotone improvement | if a variant's runs are each ≤ those of a variant judged *better*, it is also better | T1. `simp` + `below_spec`. |
| Twin rule | `sensitive v t := v(t−4ms) ≠ v t ∨ v(t+4ms) ≠ v t` (the "any twin differs" rule, protocol §3.2 A5). Theorem: a verdict reported as *not sensitive* has all three verdicts equal. | T1 (definition plus a one-line proof; its value is a single shared definition) |
| Near bands are half-open and disjoint | near34 = (30, 38], near50 = (46, 54], disjoint; every frame is in at most one | T1 (`decide`/`omega`) |
| Sequential ABBA decision | after block 1 (4v4), "win" only if U = 0 and HL ≥ max(1 tick, predicted/2), and so on (protocol §5.3) | T1: encode the decision tree as a total function. Prove that "win" implies U = 0 implies the non-overlap verdict, so the two rules can't contradict each other. |
| Exact p for 4v4, U=0 | `p = 1 / C(8,4) = 1/70` | T2: `decide` on a hand-written combination enumerator in `Rat`, no Mathlib |
| Hodges–Lehmann shift equivariance | `HL(ctl, var + c) = HL(ctl, var) + c` | T2. Needs sorted-median lemmas; a candidate for the optional `FwMath`. |
| Engine timestamps are vsync-quantized (Chrome) / not (WebKit) | | **✗** An empirical engine claim. Measured, and cited to source by the measurement note. |

Boundary rule: the shell rounds `dt_ms` (float) to integer µs once (`Math.round(dt*1000)`). This differs from v1's
float tick only for frames within 0.5 µs of a midpoint (INFERRED, harmless). Write that down once, not per test.

### 4.2 Cost model

The *model* is proved. Whether Blink or WebKit *obey* it is measured by calibration runs; the measurement note
(engine math) owns the coefficients.

| property | status |
|---|---|
| `mainUs` (linear in work counts) is monotone in every count | **P** `Fw/Spec/Cost.lean: mainUs_mono` |
| A compositor-only variant (changes only `CompWork`) has main-thread cost equal to the base | **P** `compositorOnly_same_main`. True by construction, which is the point: the type keeps compositor work out of `mainUs`. |
| Frame-budget preservation: pointwise ≤ work keeps every on-time frame on time | **P** `onTime_of_le` |
| Jank count is monotone in per-frame work (lift to traces: `countAbove` over `mainUs`) | T1 (compose `onTime_of_le` with `countAbove_antitone`) |
| Budget at refresh rate r: `budget = ⌊10⁶ / r⌋ µs`; halving rate (LPM 30 Hz) doubles the budget | T1 |
| Engine-specific "this CSS property is compositor-only in WebKit" | **✗** Source-cited fact, recorded as a *registry entry*, not a theorem. The theorem is about whatever the registry says. |

### 4.3 Feature-flag configuration (pluggable parts)

| property | status |
|---|---|
| Every part has exactly one variant | **P by construction**: `Config := Part → Variant` is a total function, so there is nothing to test |
| `resolve` returns only valid configs (all variants exist, requires/conflicts rules hold) | **P** `Fw/Spec/Flags.lean: resolve_sound` |
| A/B isolation: `override c p v` differs from `c` in exactly `[p]` | **P** `override_diff`. This is v1's "mechanism check: the arm removed exactly the named thing" (protocol §2.3) turned into a type-level fact. |
| The checked-in registry is valid | T1: `site/flags.json` → generated `Fw/Gen/Registry.lean`, plus `theorem registry_ok : registry.wellFormed = true := by decide`. If someone adds a conflicting rule, the build fails. |
| Every ablation set has a positive arm and ≥1 negative sibling on the same base | T1 (decidable check on the plan JSON) |

### 4.4 Console / loop backend as state machines

Every machine has the same shape: `step : State → Cmd → State × Reply`, a pure, total function in which time is
an *input* (`now`). An `Inv` structure is proved preserved by `step`. Specific v1 incidents become named theorems.

**Device and resource lease** (`Fw/Spec/Lease.lean`):

| property | status |
|---|---|
| Mutual exclusion | **P by construction** (`holder : Option Lease`) |
| `Inv`: idle ⇒ empty queue; queue `Nodup`; holder ∉ queue. Preserved by every command | **P** `step_inv`, `inv_init` |
| I-113: re-acquire by a queued waiter leaves the state unchanged | **P** `requeue_keeps_place` |
| I-091: renew never shortens | **P** `renew_never_shortens` |
| FIFO: on release, the head of the queue gets the device and every waiter moves up one place | **P** `release_fifo` |
| **Bounded wait (no starvation):** waiter at position i gets the device within (i+1)·maxHold | T1. **The proof attempt already found a design gap:** the sketch's `renew` lets a holder extend forever, so this theorem is *false* for it. The fix is to store `grantedAt` and cap `expires ≤ grantedAt + maxHold` (v1's 900 s / 3 600 s with `--block`). This is the cheapest kind of bug to find. |
| Shared readers + exclusive writers (v1's chrome-measure lane): no co-hold of exclusive and shared (I-041), readers ahead of a writer are not starved (I-049, I-136) | T1 (same pattern; ranking function = (position, remaining hold)) |
| Lease + user step: no hand-over while the owner's step is on the phone, bounded by grace (I-122, I-123; v1 `tools/lib/phone-step.mjs` l.13-16) | T1: a product machine (lease × step). Prove "handover ⇒ ¬onPhone ∨ grace expired". |

**Topic lifecycle** R→I→D→F→V→L (`Fw/Spec/Stage.lean`, rules from v1 `fixes/LEAD.md` l.91-119):

| property | status |
|---|---|
| Each successful `advance` moves exactly one stage (no skipping) | **P** `advance_one` |
| F is entered only through a D card that is `named` and signed by `lead` (LOCATED builds no fix) | **P** `enter_F` |
| V is signed by the reviewer and L by the lead | T1 (same proof as `enter_F`) |
| Phone-only class needs a Timeline segment card before F (A1) | T1 (extend `Card`) |

**Console steps and threads:** states pending → active → answered | skipped | cancelled, plus "Start over" (v1
`tools/lib/phone-step.mjs` l.10-12).
- Planned theorems (T1): a step is answered at most once; "Done" is refused on runner-ended parts (I-059); "Start
  over" keeps the step `active` and resets parts.
- The thread-routing rules in v1 `tools/lib/thread-routing.mjs` become a total function with a theorem: "every
  thread has exactly one assignee tier" (I-175).

**Event log and replay** (T1, architecture-level):
- The state equals `log.foldl step init`.
- Because `step_inv` holds, *every* replayed state satisfies `Inv`, so the shell never needs an invariant test.
- `fwcore replay log.jsonl` acts as a runtime monitor. It checks that the persisted log really replays to the
  persisted snapshot, which catches shell bugs such as a lost write or a double apply.

### 4.5 What NOT to prove

- **✗ Engine behaviour.** Vsync quantization, WebKit's 60 Hz hint, layer promotion rules: cite the source, measure,
  and record each as a registry fact.
- **✗ UI rendering and visual parity** with the original site: screenshot diffs.
- **✗ I/O adapters:** CDP, WebDriver, files, the clock.
- **✗ Performance numbers.**

Proofs about any of these would be proofs about a model of them. Calibration is what checks that model.

---

## 5. (b) HOW: architectures compared

| | (i) Lean verified core → native `fwcore`, TS shell over JSON-lines | (ii) Lean spec as oracle, TS implementation, differential/property testing | (iii) Full Lean backend (`Std.Http`, Lean storage) |
|---|---|---|---|
| Where decisions live | Lean only | twice (Lean spec + TS impl) | Lean only |
| Guarantee at runtime | the proved function *is* the running function (trust: Lean compiler + JSON codec) | TS impl agrees with spec on sampled traces only | same as (i) |
| Runtime tests needed | codec golden tests + adapter tests | full DRT harness per machine + the TS's own tests | Lean tests for HTTP, storage and everything else |
| Agent productivity | high. TS agents never touch decision code. Lean agents work on small pure files with lean-lsp-mcp. | medium. Every rule change is made twice and kept in sync. | low. Lean is thin for HTTP, DB and CDP, and has no Chrome/CDP client. Agents fight the ecosystem. |
| Build time | `lake build` incremental ≈0.5 s per changed module (MEASURED). TS unaffected. | both toolchains, plus the DRT run (seconds to minutes) | everything in Lake. A Mathlib-free tree is still fast. |
| Debuggability | each request/response is one JSON line, and logs replay deterministically | divergences need shrinking (fast-check does it) | Lean debugging of I/O code is weaker (INFERRED) |
| Ecosystem risk | low. JSON-lines over a pipe needs no FFI (FFI is "unstable" per the docs). | low | high. `Std.Http` is young: HTTP/1.1, no WebSocket, no DB binding. |
| Precedent | — | AWS Cedar (Lean model + Rust + DRT; 4 proof bugs and 21 DRT/PBT bugs found) | none comparable found (INFERRED) |

**Recommendation: (i), using (ii) only where duplication can't be avoided.**
- (i) removes the double implementation that makes (ii) costly. Cedar needed (ii) because its production code had
  to be Rust. We are free to call a native binary.
- (ii) is kept for: (1) any TS mirror of a decision, such as the console UI greying out an invalid flag
  combination before it submits; (2) the boundary itself, as golden and property tests of the JSON codec.
- (iii) is rejected for now. It can be revisited if `Std.Http` matures *and* there is a reason to drop Node, which
  is unlikely because the measurement harness needs Node/CDP anyway.

### 5.1 Runtime shape

```
shadcn console UI ──HTTP/SSE──▶ console-api (Node 24, TS)
                                  │  single writer per resource (actor queue)
                                  │  append-only events.jsonl  (+ snapshot)
                                  ▼
                               fwcore (Lean exe, long-lived child, JSON-lines)
                                  step / verdict / resolve / replay
measurement CLI (TS) ──────────▶ fwcore verdict / tick / twins / decide
```

- **One writer:** console-api serializes all commands for a resource through one queue, then calls `fwcore`.
  v1 used cross-worktree file locks with many writers, which caused I-012 and I-035. Replacing them with a single
  writer and a pure step function removes a whole class of race (INFERRED).
- **Time is data.** The shell sends `now` and a periodic `tick`. The core never reads a clock, so every bug
  replays exactly.
- **Crash safety:** append the `Cmd` to `events.jsonl` first, then apply it. On restart, replay.

### 5.2 Minimal example (from the sketch; all of it builds)

`Fw/Spec/Lease.lean`, abridged:

```lean
structure Lease where
  owner : String
  expires : Nat
deriving Repr, DecidableEq, Lean.ToJson, Lean.FromJson

structure State where
  holder : Option Lease := none        -- mutual exclusion by construction
  queue  : List String  := []
deriving Repr, Lean.ToJson, Lean.FromJson

inductive Cmd where
  | acquire (o : String) (now ttl : Nat) | renew (o : String) (now ttl : Nat)
  | release (o : String) (now ttl : Nat) | tick (now ttl : Nat)
deriving Repr, Lean.ToJson, Lean.FromJson

def step : State → Cmd → State × Reply
  | s, .acquire o now ttl =>
    match s.holder with
    | none   => if s.queue = [] then ({ holder := some ⟨o, now + ttl⟩, queue := [] }, .granted ⟨o, now + ttl⟩)
                else (s, .refused "not normalized")
    | some l =>
      if l.owner = o then (s, .granted l)                         -- re-entrant
      else if o ∈ s.queue then (s, .queued (s.queue.idxOf o))     -- keeps its place (I-113)
      else ({ s with queue := s.queue ++ [o] }, .queued s.queue.length)
  | s, .renew o now ttl => ...   -- expires := max l.expires (now + ttl)   (I-091)
  | s, .release o now ttl => ...  -- holder: promote the queue head; waiter: erase
  | s, .tick now ttl => ...       -- expired holder: promote the queue head

structure Inv (s : State) : Prop where
  idle_empty : s.holder = none → s.queue = []
  nodup      : s.queue.Nodup
  not_both   : ∀ l, s.holder = some l → l.owner ∉ s.queue

theorem step_inv {s : State} (c : Cmd) (h : Inv s) : Inv (step s c).1 := by ...   -- ~60 lines, cases + simp

theorem requeue_keeps_place (s : State) (l : Lease) (o : String) (now ttl : Nat)
    (hl : s.holder = some l) (hne : l.owner ≠ o) (hq : o ∈ s.queue) :
    (step s (.acquire o now ttl)).1 = s := by
  simp [step, hl, hne, hq]

theorem renew_never_shortens (s : State) (l : Lease) (now ttl : Nat) (hl : s.holder = some l) :
    ∃ l', (step s (.renew l.owner now ttl)).1.holder = some l' ∧ l.expires ≤ l'.expires := by
  refine ⟨⟨l.owner, max l.expires (now + ttl)⟩, by simp [step, hl], by simp; omega⟩
```

Compile-time example tests and a Plausible test (`FwTest/Lease.lean`):

```lean
#guard (step {} (.acquire "a" 0 900)).2 matches .granted _
#guard ((step {} (.acquire "a" 0 900)).1 |> fun s => (step s (.acquire "b" 1 900)).2) matches .queued 0

inductive TCmd where                       -- small pools so owners collide
  | acquire (who : Fin 3) (dt : Fin 5) | renew (who : Fin 3) (dt : Fin 5)
  | release (who : Fin 3) (dt : Fin 5) | tick (dt : Fin 2000)
deriving Repr, Arbitrary, Shrinkable

def run (cs : List TCmd) : State := ...    -- fold step over the trace, advancing `now`
def invB (s : State) : Bool := ...         -- the Bool mirror of Inv a TS shell could call

#eval Testable.check (∀ cs : List TCmd, invB (run cs) = true) { numInst := 300 }
-- info: Unable to find a counter-example        (MEASURED, at build time)
```

What the Plausible test is for: `step_inv` already proves the invariant for all traces. The random test checks the
**Bool mirror** `invB` that a boundary would use. Proved statements get no runtime test; only their executable
copies do.

Verdict, from `Fw/Spec/Verdict.lean`:

```lean
def below (b a : List Int) : Bool := b.all fun y => a.all fun x => decide (y < x)   -- max b < min a
def verdict (d : Dir) (ctl var : List Int) : Verdict :=
  if ctl.length < 3 ∨ var.length < 3 then .tooFew
  else match d with
    | .lower  => if below var ctl then .better else if below ctl var then .worse else .noise
    | .higher => if below ctl var then .better else if below var ctl then .worse else .noise
theorem swap_better (h : verdict d ctl var = .better) : verdict d var ctl = .worse := ...
```

Wire (`Fw/Wire.lean` + `Main.lean`): `handle : Json → Except String Json` dispatches on `op`, and `main` loops
`getLine → handleLine → putStrLn → flush`. MEASURED exchange:

```
→ {"op":"lease.step","state":{"holder":{"owner":"fix-hero","expires":1000},"queue":["fix-nav"]},
   "cmd":{"release":{"o":"fix-hero","now":200,"ttl":900}}}
← {"reply":"released","state":{"holder":{"expires":1100,"owner":"fix-nav"},"queue":[]}}
```

### 5.3 TypeScript side (sketch, not built)

```ts
// packages/core-bridge/src/fwcore.ts: one long-lived child, FIFO correlation (requests are serialized)
const p = spawn(FWCORE, [], { stdio: ['pipe', 'pipe', 'inherit'] });
const rl = createInterface({ input: p.stdout }); const waiting: ((j: unknown) => void)[] = [];
rl.on('line', (l) => waiting.shift()!(JSON.parse(l)));
export const call = <T>(req: object) => new Promise<T>((res) => { waiting.push(res as any); p.stdin.write(JSON.stringify(req) + '\n'); });
// zod schemas for State/Cmd/Reply are checked against golden files emitted by `fwcore samples`
```

```ts
// test/oracle.prop.test.ts: (ii) only where TS mirrors a decision, e.g. the UI's flag validity preview
fc.assert(fc.asyncProperty(arbConfigRequest, async (req) => {
  const lean = await call<{ ok: boolean }>({ op: 'flags.resolve', req });
  expect(previewValid(req)).toBe(lean.ok);           // TS mirror must agree with the proved resolver
}), { numRuns: 2000 });
```

### 5.4 Repo layout (proposal; the plan architect owns the final tree)

```
lean/                          Lake project "fwcore" (Mathlib-free)
  lean-toolchain               leanprover/lean4:v4.35.0   (bump deliberately, one PR)
  lakefile.toml                testDriver = "fwtest"; require plausible @ v4.35.0
  Fw/Spec/Frames.lean          ticks, thresholds, twins, near bands
  Fw/Spec/Verdict.lean         non-overlap verdict, sequential ABBA decision
  Fw/Spec/Cost.lean            linear cost model, budgets
  Fw/Spec/Flags.lean           parts, variants, rules, resolve
  Fw/Spec/Lease.lean           device/lane leases (exclusive + shared)
  Fw/Spec/Stage.lean           R→I→D→F→V→L gates
  Fw/Spec/Step.lean            console steps/threads
  Fw/Gen/Registry.lean         GENERATED from site/flags.json (+ registry_ok by decide)
  Fw/Wire.lean                 JSON dispatch: the only boundary
  Main.lean                    fwcore: JSON-lines worker; subcommands replay | samples
  FwTest/*.lean                #guard examples, Plausible traces, wire golden emission
  FwMath/ (optional, separate package, may use Mathlib; never imported by Fw)
packages/core-bridge/          TS client, zod schemas, golden + oracle tests
apps/console-api/              Node HTTP API; single writer; events.jsonl; no decisions
.mcp.json                      lean-lsp (uvx lean-lsp-mcp) + serena
.serena/project.yml            language_servers: ["typescript", "lean4"]
```

### 5.5 Commands and CI

```sh
# one-time per machine (the user decides; elan installs to ~/.elan by default)
curl https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh -sSf | sh -s -- -y --default-toolchain none
cd lean && lake build            # proofs + #guard examples + compile fwcore  (fails on any broken theorem)
lake test                        # Plausible traces + wire golden emission
lake env lean scripts/Axioms.lean   # `#print axioms` on the key theorems: only propext/Classical.choice/Quot.sound
grep -rn --include=*.lean -E '\bsorry\b|native_decide|implemented_by|unsafe' Fw && exit 1   # policy gate
pnpm -F core-bridge test         # zod vs golden, fast-check oracles (TS mirrors only)
```

CI:
- Cache `~/.elan` and `lean/.lake`. Run `lake build`, the axiom/sorry gate and `lake test`.
- Run the TS tests only for packages whose files changed (pnpm `--filter ...[origin/main]`).
- Lean's own incremental build already skips unchanged modules.

### 5.6 How this answers "adopting a tool means re-running all tests"

| layer | how it is checked | re-runs when |
|---|---|---|
| Proved properties (`Fw/Spec`) | kernel-checked at compile time, for all inputs | only modules whose inputs changed (edit one module, rebuild in 0.5 s, MEASURED) |
| Executable mirrors (`invB`, TS previews) | Plausible / fast-check against the proved function | the mirror or its spec changed |
| Wire codecs | golden fixtures emitted by `fwcore samples`, parsed by zod | `Fw/Wire.lean` or the schemas changed |
| Adapters (CDP, devices, files) | small fake-driven tests per adapter | that adapter changed. **Adopting a new tool touches only its adapter.** |
| Engine/model fit | calibration runs (measurement team) | engine or device version changed |

v1 had one 253 s suite (I-114) that guarded everything, because no layer could be trusted on its own.

### 5.7 Team and agent notes (input to the agent-team note)

- **Lean prover role.** Edits only `lean/`. Uses lean-lsp-mcp: `lean_goal`, `lean_multi_attempt`, `lean_verify`.
  Its gate is `lake build` plus the axiom gate. Proof search is the token-heavy step: give it a strong model at
  high effort, with the rule "try `simp`/`omega`/`decide`/`grind` before writing manual proofs".
- **Spec reviewer.** Reads statements only, not proofs; proofs are trusted once `lean_verify` is clean. It checks
  that the theorem says what the protocol prose says. This is where v1 drifted. It can use a mid-tier model.
- **TS shell roles** never edit `lean/`. A new decision means: a spec PR first, then the shell calls the new op.

---

## 6. Risks

1. **Wrong spec, correct proof.** A theorem only proves what it states. Mitigations: the spec reviewer reads
   statements against `measurement-protocol-v2.md`; each named theorem cites the incident or protocol section it
   encodes; plus golden examples (`#guard`) taken from v1 results.
2. **Toolchain churn.** Lean releases about monthly, with rcs in between, and names get deprecated (`if_neg` already
   on v4.35, MEASURED). Pin `lean-toolchain` and bump deliberately: one PR runs the full `lake build`.
3. **Boundary drift.** Lean's derived JSON shape is implicit (§2). Golden fixtures plus zod catch it. Never
   hand-write the TS types.
4. **Install footprint.** The toolchain takes 2.8 GB (MEASURED), and Mathlib would add several GB (INFERRED). Agents
   in worktrees share `~/.elan`, but each worktree has its own `.lake` (214 MB here).
5. **Binary size, 101 MB.** Irrelevant locally. It matters only if `fwcore` ships somewhere. Smaller options exist
   (INFERRED): avoid importing `Lean` and write a tiny JSON codec on `Std`.
6. **Liveness proofs are harder** than safety ones: they need a ranking-function argument over traces. Budget T1
   time for them. The bounded-wait theorem already showed a design gap (§4.4).
7. **Over-proving.** Don't prove UI or engine behaviour (§4.5). Keep the core small: the sketch is 630 lines for
   six areas.

## 7. Open questions for the user

1. Is it OK to install elan in `~/.elan` (2.8 GB per toolchain) on this Mac, and in CI?
2. Should the console backend be Node (recommended), with Lean as a child process? Or do you want to try (iii), a
   Lean HTTP server, as its own experiment?
3. Which v1 rules should be encoded first? My suggestion:
   - verdict + ticks + twins, so measurement verdicts are proved from day one
   - leases (exclusive + shared lane) with bounded wait
   - flag registry validity
   - lifecycle gates
4. Should the R→I→D→F→V→L protocol carry over unchanged? v2's engine-stat measurement may drop the phone-only
   classes. The lifecycle spec should encode the new protocol, not v1's.
5. Is a "Mathlib-free core, optional `FwMath`" policy OK? Exact p-values and HL proofs would live in `FwMath`.

## 8. Sources

- Lean releases: `gh api repos/leanprover/lean4/releases` (v4.35.0 2026-10-12; v4.36.0-rc1 2026-10-14)
- Lean source at v4.35.0:
  - `src/Std/Http.lean`, `src/Std/Http/Server.lean`, `src/Std/Http/Protocol/H1*`
  - `src/Std/Async.lean`
  - `src/Init/Data/Rat.lean`
  - `src/Lean/Data/Json/FromToJson.lean`
  - `src/Lean/Elab/Tactic/Guard.lean`, `src/Lean/Elab/GuardMsgs.lean`, `src/Lean/Elab/Tactic/Grind.lean`
  - `src/Std/Tactic/Do.lean`
  - `src/lake/README.md` (l.201, 219-226, 384, 445)
  - PR #13511 (Async/Http moved out of Internal)
- Lean reference: [Floating-point numbers](https://lean-lang.org/doc/reference/latest/Basic-Types/Floating-Point-Numbers/),
  [FFI](https://lean-lang.org/doc/reference/latest/Run-Time-Code/Foreign-Function-Interface/),
  [v4.22.0 release notes (Std.Do/mvcgen)](https://lean-lang.org/doc/reference/stable/releases/v4.22.0/),
  [v4.31.0 notes (mvcgen')](https://lean-lang.org/doc/reference/4.33.1/releases/v4.31.0/),
  [FRO roadmap Y3](https://lean-lang.org/fro/roadmap/y3)
- Plausible: https://github.com/leanprover-community/plausible (README; `Plausible/Testable.lean` `checkIO`/`check`;
  `Plausible/DeriveShrinkable.lean`; tag `v4.35.0` = `dfa4f381`)
- LSpec: https://github.com/argumentcomputer/LSpec · lean4-cli: https://github.com/leanprover/lean4-cli ·
  REPL: https://github.com/leanprover-community/repl · Verso: https://github.com/leanprover/verso
- lean-lsp-mcp: https://github.com/oOo0oOo/lean-lsp-mcp (README, `docs/tools.md`) · lean4-skills:
  https://github.com/cameronfreer/lean4-skills
- Serena Lean 4: https://github.com/oraios/serena `src/solidlsp/ls_config.py` (LEAN4),
  `src/solidlsp/language_servers/lean4_language_server.py` (commit 09c007d1, PR #1137, 2026-03-12),
  `src/serena/resources/project.template.yml` (`language_servers`)
- Search tools: https://github.com/nomeata/loogle, https://github.com/lean-explore/lean-explore; provers:
  https://github.com/deepseek-ai/DeepSeek-Prover-V2, https://github.com/Goedel-LM/Goedel-Prover-V2,
  https://github.com/project-numina/kimina-lean-server, https://github.com/lean-dojo/LeanDojo
- HTTP third-party: https://github.com/axiomed/http, https://reservoir.lean-lang.org/@hargup/http-client · SQLite:
  https://github.com/drcicero/sqlite.lean
- Cedar: "How We Built Cedar: A Verification-Guided Approach", https://arxiv.org/abs/2407.01688;
  https://lean-lang.org/use-cases/cedar/; https://aws.amazon.com/blogs/opensource/lean-into-verified-software-development/
- v1 repo (read-only):
  - `CLAUDE.md` l.134-158
  - `research/architecture/measurement-protocol-v2.md` §2.3-2.5, §3.2 (l.155-180), §5.3 (l.320-345), §6.1
  - `fixes/LEAD.md` l.91-119
  - `tools/lib/ab-stats.mjs` l.34-39
  - `tools/lib/stats.mjs` l.42-46, 216, 429
  - `tools/lock.mjs` l.1-60 and `tools/lib/lock.mjs` (1 685 lines)
  - `tools/lib/phone-step.mjs` l.1-40
  - `console/incidents.json` / `.md` (I-005, I-011, I-012, I-021, I-035, I-041, I-049, I-059, I-085, I-091, I-097,
    I-113, I-114, I-120, I-121, I-122, I-123, I-136, I-159, I-175)
  - `package.json` test scripts
- Prototype (this repo): `research/kickoff/05-lean-sketch/` (Lean v4.35.0, Plausible v4.35.0). Build and timings in §1.
