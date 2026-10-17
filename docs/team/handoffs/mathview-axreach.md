# mathview-axreach handoff

State: one commit on the worktree branch (see `git log -1 -- lean/Fw/Spec/AxReach.lean`). check.sh green (90 s, cache miss).

Read first: `lean/Fw/Spec/AxReach.lean` (spec + proofs), then the `## Axioms` section of `lean/MathView.lean` (`axSucc`, `axIsAx`, the loop in `entries`).

What changed:
- `Fw.AxReach.search` is a fuel-bounded (total) depth-first search with one shared memo and Tarjan's low-link test: a node's axiom list is stored only when `k ≤ low`, so a node inside an inductive/constructor cycle never caches a partial set.
- Proved: `reach_fix` (T1 fixpoint), `loop_spec`, `search_spec` (memo stays exact, stack restored, sound, complete up to the stack), `search_exact` (T2: `low ≥ k` gives exactly R(c)), `query_exact` / `query_fresh` (T3: every query, the first on an empty memo too, returns exactly R(c)). Axioms: standard only. `#guard`s on a 4-node cyclic graph (incl. "1 is not memoised").
- `MathView.entries` calls `Fw.AxReach.query (axSucc kenv) (axIsAx kenv) fuel memo n`, with `axSucc` mirroring `CollectAxioms.collect` (Lean/Util/CollectAxioms.lean:56-67 @ v4.35.0) and `kenv = (env.setExporting false).toKernelEnv`. Fuel = #constants + 2; out of fuel falls back to `collectAxioms n` (never observed).
- `entryOf` now takes `axs` as an argument; axioms are computed for every candidate before the `bounded` wrapper, so `heartbeats` per entry drop (expected; not linted).

Measured (local, debug runs, load 23-48 on 8 cores): old 172 s / 194 s, new 16 s, same tree. Differential: lint text identical, JSON byte-identical after removing `"heartbeats":` lines (4,192 entries).

Open items:
- T3 links to Lean's `collectAxioms` by source reading (its root result is R(c); its interior cache can be partial but only the root is returned) plus the differential; Lean core's `partial def` itself is not proved.
- No theorem that fuel `#constants + 2` always suffices (stack holds distinct nodes; INFERRED); the fallback keeps output exact either way.
- math-reviewer / math lock have not seen the new `Fw.AxReach` entries.
