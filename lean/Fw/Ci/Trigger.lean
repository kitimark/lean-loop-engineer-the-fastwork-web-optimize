import Lean.Data.Json
import Fw.Console.LandSpeed
import Fw.Ops.PathCheck
/-!
# Which workflows a push to `ci/*` starts (task `ci-trigger-lean`)

A push starts a workflow iff the push changes one of the workflow's declared inputs. "Changes" is the part of the push
the agent owns: a file in the push's diff (`before..after`) whose new content is not already the content on `main`
(`effective`). A merge of `main` into the branch therefore changes nothing, and a later push to a branch that already
touched a workflow's inputs does not start it again (the first `ci-trigger-scope` fix compared against `before..after`
and the guard compared against the merge-base, so both fired on merges and on every later push).

Declared inputs are globs with the `PathCheck` semantics (the same `inScope` as the land checks). A glob starting with
`@` names a set (`@fwcore`: the files the `fwcore` binary is built from, i.e. its import cone, not all of `lean/**`);
`expand` replaces it. The set contents come from outside (the import graph of the checkout), so every theorem holds for
every set map.

Generated from this file, never by hand: `packages/contracts/golden/ci/triggers.jsonl` (the table and the replay cases).
`scripts/ci-paths.mjs` expands it into `on.push.paths` of `.github/workflows/*.yml` (`--write`) or fails when they differ
(`--check`, wired into the land checks of `apps/runner`). The static paths write every cone as the fixed `coneGlobs`
(`pushPaths`), so a new module changes no workflow file; the guard job (`.github/scripts/changed-inputs.mjs`) expands the
cones from the checkout and decides `starts` exactly (section "Coarse push filter, precise guard").
-/
namespace Fw.Ci.Trigger
open Lean Fw.Ops.PathCheck
open Fw.Console.LandSpeed (selected selected_of_mem skip_sound ReadsWithin St)

/-- A workflow's push trigger: its file, the branches it watches and its declared input globs.
$$w = (\mathit{file},\ B,\ G \in \mathrm{Glob}^{*})$$ -/
structure Wf where
  file : String
  branches : List String
  inputs : List String
  crons : List String
deriving Repr, DecidableEq

/-- Replace every `@set` glob by the set's contents (an unknown set stays as it is, matching no path).
$$\operatorname{expand}(S, G) = \bigl[\, h : g \in G,\ h \in (S(g)\ \text{if } g \text{ starts with } @,\ \text{else } [g]) \,\bigr]$$ -/
def expand (S : String → List String) (gs : List String) : List String :=
  gs.flatMap fun g => if g.startsWith "@" then S g else [g]

/-- The push's own change: the files of its diff whose new content differs from `main`'s.
Here $m(x)$ says the new content of $x$ is not `main`'s.
$$\operatorname{eff}(D, m) = [\, x \in D : m(x) \,]$$ -/
def effective (diff : List String) (differs : String → Bool) : List String := diff.filter differs

/-- Does the push start the workflow? Some effective change is in the scope of its expanded inputs.
$$\operatorname{starts}(w, S, X) \iff \exists x \in X:\ \mathrm{in}(\mathrm{parse}(\operatorname{expand}(S, w.G)), x)$$ -/
def Wf.starts (S : String → List String) (w : Wf) (eff : List String) : Bool :=
  selected (expand S w.inputs) eff

/-- The workflows a push starts, in table order.
$$\operatorname{started}(W, S, D, m) = [\, w.\mathit{file} : w \in W,\ \operatorname{starts}(w, S, \operatorname{eff}(D, m)) \,]$$ -/
def startedBy (S : String → List String) (ws : List Wf) (diff : List String) (differs : String → Bool) : List String :=
  (ws.filter fun w => w.starts S (effective diff differs)).map (·.file)

/-- The effective change is part of the diff.
$$\forall D, m, x:\ x \in \operatorname{eff}(D, m) \Rightarrow x \in D$$ -/
theorem effective_sub (diff : List String) (differs : String → Bool) (x : String) (h : x ∈ effective diff differs) :
    x ∈ diff := (List.mem_filter.mp h).1

/-- **Starts iff an input changed.** A workflow starts exactly when a path of the diff that differs from `main` is in
the scope of its expanded inputs.
$$\forall S, w, D, m:\ \operatorname{starts}(w, S, \operatorname{eff}(D, m)) \iff \exists x \in D:\ m(x) \land \mathrm{in}(\mathrm{parse}(\operatorname{expand}(S, w.G)), x)$$ -/
theorem starts_iff (S : String → List String) (w : Wf) (diff : List String) (differs : String → Bool) :
    w.starts S (effective diff differs) = true ↔
      ∃ x ∈ diff, differs x = true ∧ inScope (parseScope (expand S w.inputs)) x = true := by
  simp only [Wf.starts, selected, effective, List.any_eq_true, List.mem_filter]
  constructor
  · rintro ⟨x, ⟨hx, hd⟩, hi⟩
    exact ⟨x, hx, hd, hi⟩
  · rintro ⟨x, hx, hd, hi⟩
    exact ⟨x, ⟨hx, hd⟩, hi⟩

/-- **Soundness: a change outside every declared input starts nothing.** If no effective change of the push is in the
scope of any workflow's expanded inputs, the push starts no workflow.
$$\forall S, W, D, m:\ (\forall w \in W,\ \forall x \in D:\ m(x) \Rightarrow \lnot\mathrm{in}(\mathrm{parse}(\operatorname{expand}(S, w.G)), x)) \Rightarrow \operatorname{started}(W, S, D, m) = [\,]$$ -/
theorem none_started (S : String → List String) (ws : List Wf) (diff : List String) (differs : String → Bool)
    (h : ∀ w ∈ ws, ∀ x ∈ diff, differs x = true → inScope (parseScope (expand S w.inputs)) x = false) :
    startedBy S ws diff differs = [] := by
  unfold startedBy
  have : ws.filter (fun w => w.starts S (effective diff differs)) = [] := by
    apply List.filter_eq_nil_iff.mpr
    intro w hw hs
    obtain ⟨x, hx, hd, hi⟩ := (starts_iff S w diff differs).mp hs
    rw [h w hw x hx hd] at hi
    exact Bool.noConfusion hi
  rw [this]; rfl

/-- **Completeness: the workflows started are exactly the ones with a changed input.** The file of `w` is in the started
list iff some workflow of that file has an effective change in its inputs.
$$\forall S, W, D, m, f:\ f \in \operatorname{started}(W, S, D, m) \iff \exists w \in W:\ w.\mathit{file} = f \land \exists x \in D:\ m(x) \land \mathrm{in}(\mathrm{parse}(\operatorname{expand}(S, w.G)), x)$$ -/
theorem mem_startedBy (S : String → List String) (ws : List Wf) (diff : List String) (differs : String → Bool) (f : String) :
    f ∈ startedBy S ws diff differs ↔
      ∃ w ∈ ws, w.file = f ∧ ∃ x ∈ diff, differs x = true ∧ inScope (parseScope (expand S w.inputs)) x = true := by
  simp only [startedBy, List.mem_map, List.mem_filter]
  constructor
  · rintro ⟨w, ⟨hw, hs⟩, hf⟩
    exact ⟨w, hw, hf, (starts_iff S w diff differs).mp hs⟩
  · rintro ⟨w, hw, hf, hx⟩
    exact ⟨w, ⟨hw, (starts_iff S w diff differs).mpr hx⟩, hf⟩

/-- **A merge of `main` starts nothing.** If every path of the diff already has `main`'s content (a push that only
merges `main`), no workflow starts, whatever the inputs.
$$\forall S, W, D, m:\ (\forall x \in D:\ \lnot m(x)) \Rightarrow \operatorname{started}(W, S, D, m) = [\,]$$ -/
theorem merge_starts_nothing (S : String → List String) (ws : List Wf) (diff : List String) (differs : String → Bool)
    (h : ∀ x ∈ diff, differs x = false) : startedBy S ws diff differs = [] :=
  none_started S ws diff differs fun _ _ x hx hd => by rw [h x hx] at hd; exact Bool.noConfusion hd

/-- **The coarse GitHub filter never drops a needed start.** GitHub's `on.push.paths` filter runs on the whole diff
`before..after`; if the workflow starts (an effective input changed) the filter passes, so the generated `paths` list
together with the guard decides exactly `starts`.
$$\forall S, w, D, m:\ \operatorname{starts}(w, S, \operatorname{eff}(D, m)) \Rightarrow \operatorname{sel}(\operatorname{expand}(S, w.G), D)$$ -/
theorem filter_passes (S : String → List String) (w : Wf) (diff : List String) (differs : String → Bool)
    (h : w.starts S (effective diff differs) = true) : selected (expand S w.inputs) diff = true := by
  obtain ⟨x, hx, _, hi⟩ := (starts_iff S w diff differs).mp h
  exact selected_of_mem _ _ x hx hi

/-- **A skipped run replays.** If the workflow's result depends only on its expanded inputs and the push does not start
it, its result on the new state equals its result on any state that agrees with it outside the effective change (the
state the branch was last verified in, with `main`'s content).
$$\mathrm{RW}(\mathit{run}, \operatorname{expand}(S, w.G)) \land \lnot\operatorname{starts}(w, S, X) \land (\forall p \notin X:\ \sigma(p) = \sigma'(p)) \Rightarrow \mathit{run}(\sigma) = \mathit{run}(\sigma')$$ -/
theorem skipped_replays {R} (S : String → List String) (w : Wf) (eff : List String) (run : St → R)
    (hrw : ReadsWithin run (expand S w.inputs)) (hs : w.starts S eff = false) (σ σ' : St)
    (hd : ∀ p, p ∉ eff → σ p = σ' p) : run σ = run σ' :=
  skip_sound run (expand S w.inputs) eff hrw hs σ σ' hd

/-! ## The table -/

/-- The path of a workflow file. $$\operatorname{own}(f) = \texttt{.github/workflows/}f$$ -/
def own (f : String) : String := s!".github/workflows/{f}"

/-- Branches of a `ci/*` lane that also runs on `main`. $$B = [\texttt{ci/**},\ \texttt{main}]$$ -/
def ciMain : List String := ["ci/**", "main"]

/-- Branches of a `ci/*` lane that does not run on `main`. -/
def ciAll : List String := ["ci/**"]

/-- The files `lake build fwcore` reads besides the import cone of `Main`: the build files. `@fwcore.cone` is the cone.
$$F_{\mathrm{core}} = [\texttt{lean/Main.lean},\ \texttt{lean/lakefile.toml},\ \texttt{lean/lake-manifest.json},\ \texttt{lean/lean-toolchain},\ @\mathrm{cone}(\mathrm{Main})]$$ -/
def fwcoreFiles : List String :=
  ["lean/Main.lean", "lean/lakefile.toml", "lean/lake-manifest.json", "lean/lean-toolchain", "@cone:Main"]

/-- The files `breakgen` (run by the site build) reads: the build files and the import cone of `BreakgenMain`.
$$F_{\mathrm{gen}} = [\texttt{lean/BreakgenMain.lean},\ \texttt{lean/lakefile.toml},\ \texttt{lean/lake-manifest.json},\ \texttt{lean/lean-toolchain},\ @\mathrm{cone}(\mathrm{BreakgenMain})]$$ -/
def breakgenFiles : List String :=
  ["lean/BreakgenMain.lean", "lean/lakefile.toml", "lean/lake-manifest.json", "lean/lean-toolchain", "@cone:BreakgenMain"]

/-- The named sets. `@cone:<Root>` is the transitive `import` (and `include_str`) closure of the root module inside
`lean/`, computed from the checkout by `scripts/ci-paths.mjs`.
$$S(@\mathrm{fwcore}) = F_{\mathrm{core}},\quad S(@\mathrm{breakgen}) = F_{\mathrm{gen}}$$ -/
def sets : List (String × List String) := [("@fwcore", fwcoreFiles), ("@breakgen", breakgenFiles)]

/-- The set map with the given cones (`cone root` is the file list of the import cone of `root`).
$$S_{\mathrm{cone}}(g) = \begin{cases} \operatorname{flatMap}\big(h \mapsto \mathrm{cone}(R) \text{ if } h = \texttt{@cone:}R \text{ else } [h],\ xs\big) & (g, xs) \text{ is the first pair of } \mathrm{sets} \text{ with key } g \\ [g] & \text{no pair of } \mathrm{sets} \text{ has key } g \end{cases}$$

A plain glob maps to itself; a named set expands its cone markers. -/
def setMap (cone : String → List String) (g : String) : List String :=
  match sets.lookup g with
  | some xs => xs.flatMap fun h => if h.startsWith "@cone:" then cone (h.drop 6).toString else [h]
  | none => [g]

/-- The workflow table: the single place where a push trigger is decided.
$$\begin{aligned}
W &= [w_1, \dots, w_{14}],\quad B = \mathrm{ciAll} \\
w_{1} &= (\texttt{breakpoint-gate.yml}, B, G_{1}) \\
G_{1} &= [\texttt{packages/gate-breakpoints/**}, \texttt{apps/site/**}, \texttt{@}\mathrm{fwcore}, \texttt{@}\mathrm{breakgen}, \\
&\quad \texttt{snapshot/**}, \texttt{snapshot.lock.json}, \texttt{package.json}, \texttt{pnpm-lock.yaml}, \\
&\quad \texttt{pnpm-workspace.yaml}, \texttt{.github/scripts/gate-shards.mjs}, \texttt{.github/scripts/gate-jobs.mjs}, \texttt{.github/scripts/cache-key.mjs}, \\
&\quad \texttt{packages/contracts/golden/gate/schedule.jsonl}, \texttt{packages/contracts/golden/ops/cache.jsonl}, \texttt{.github/scripts/gate-smoke.mjs}, \texttt{.github/scripts/merge-gate.mjs}, \\
&\quad \texttt{.github/scripts/gate-search.mjs}, \texttt{.github/scripts/gate-search.test.mjs}, \texttt{packages/contracts/golden/gate/search.jsonl}, \\
&\quad \texttt{.github/scripts/verify-snapshot.mjs}, \texttt{.github/scripts/changed-inputs.mjs}, \texttt{.github/actions/setup-lean/**}, \texttt{.github/actions/setup-pnpm/**}, \\
&\quad \texttt{.github/actions/gate-engine/**}, \operatorname{own}(\texttt{breakpoint-gate.yml})] \\
w_{2} &= (\texttt{chromium-counts.yml}, B, G_{2}) \\
G_{2} &= [\texttt{packages/measure-chromium/**}, \texttt{apps/site/**}, \texttt{@}\mathrm{fwcore}, \texttt{@}\mathrm{breakgen}, \\
&\quad \texttt{snapshot/**}, \texttt{snapshot.lock.json}, \texttt{package.json}, \texttt{pnpm-lock.yaml}, \\
&\quad \texttt{pnpm-workspace.yaml}, \texttt{.github/scripts/verify-snapshot.mjs}, \texttt{.github/scripts/runner-info.sh}, \texttt{.github/scripts/changed-inputs.mjs}, \\
&\quad \texttt{.github/actions/setup-lean/**}, \texttt{.github/actions/setup-pnpm/**}, \operatorname{own}(\texttt{chromium-counts.yml})] \\
w_{3} &= (\texttt{difftest.yml}, B, G_{3}) \\
G_{3} &= [\texttt{packages/difftest/**}, \texttt{packages/measure-webkit/src/**}, \texttt{packages/measure-chromium/src/**}, \texttt{apps/runner/hooks/cap.mjs}, \\
&\quad \texttt{apps/console-api/src/cap/**}, \texttt{@}\mathrm{fwcore}, \texttt{pnpm-lock.yaml}, \texttt{.github/scripts/changed-inputs.mjs}, \\
&\quad \texttt{.github/actions/setup-lean/**}, \texttt{.github/actions/setup-pnpm/**}, \operatorname{own}(\texttt{difftest.yml})] \\
w_{4} &= (\texttt{engine-premises.yml}, [\texttt{ci/**}], G_{4}) \\
G_{4} &= [\texttt{packages/measure-chromium/**}, \texttt{packages/measure-wktr/**}, \texttt{packages/contracts/golden/ops/engine-premises.jsonl}, \texttt{.github/scripts/runner-info.sh}, \\
&\quad \texttt{.github/scripts/changed-inputs.mjs}, \operatorname{own}(\texttt{engine-premises.yml})] \\
w_{5} &= (\texttt{gate-gaps.yml}, B, G_{5}) \\
G_{5} &= [\texttt{packages/gate-breakpoints/**}, \texttt{apps/site/**}, \texttt{@}\mathrm{fwcore}, \texttt{@}\mathrm{breakgen}, \\
&\quad \texttt{snapshot/**}, \texttt{snapshot.lock.json}, \texttt{package.json}, \texttt{pnpm-lock.yaml}, \\
&\quad \texttt{pnpm-workspace.yaml}, \texttt{.github/scripts/verify-snapshot.mjs}, \texttt{.github/scripts/check-simulator.sh}, \texttt{.github/scripts/changed-inputs.mjs}, \\
&\quad \texttt{.github/actions/setup-lean/**}, \texttt{.github/actions/setup-pnpm/**}, \operatorname{own}(\texttt{gate-gaps.yml})] \\
w_{6} &= (\texttt{lean.yml}, \mathrm{ciMain}, G_{6}) \\
G_{6} &= [\texttt{lean/**}, \texttt{apps/site/src/breakpoints.gen.json}, \texttt{apps/site/src/sweeps.gen.json}, \texttt{apps/site/src/head.gen.json}, \texttt{scripts/span.sh}, \\
&\quad \texttt{scripts/fwcore-build.sh}, \texttt{packages/contracts/golden/gate/sweeps.jsonl}, \texttt{packages/contracts/golden/gate/exit.jsonl}, \texttt{packages/contracts/golden/gate/search.jsonl}, \\
&\quad \texttt{packages/gate-breakpoints/src/scope.gen.json}, \texttt{packages/contracts/golden/parts/contracts.gen.json}, \texttt{packages/contracts/golden/parts/stage.jsonl}, \texttt{packages/contracts/golden/parts/stage-mode.jsonl}, \\
&\quad \texttt{packages/measure-chromium/scenarios.gen.json}, \texttt{packages/contracts/golden/parts/morph.mount.dormant.jsonl}, \texttt{.github/scripts/changed-inputs.mjs}, \texttt{.github/actions/setup-lean/**}, \\
&\quad \texttt{.github/scripts/runner-info.sh}, \operatorname{own}(\texttt{lean.yml})] \\
w_{7} &= (\texttt{mutants.yml}, B, G_{7}) \\
G_{7} &= [\texttt{lean/Fw/Console.lean}, \texttt{lean/Fw/Serve.lean}, \texttt{lean/Fw/Ops/Meter.lean}, \texttt{lean/Fw/Ops/PathCheck.lean}, \\
&\quad \texttt{lean/Fw/Ops/SpawnGuard.lean}, \texttt{lean/Fw/Ops/Usage.lean}, \texttt{lean/Fw/Ops/Wire.lean}, \texttt{lean/Fw/Spec/DeviceQueue.lean}, \\
&\quad \texttt{lean/Fw/Wire.lean}, \texttt{lean/FwTest/Mutants/**}, \texttt{lean/scripts/mutants.sh}, \texttt{.github/scripts/changed-inputs.mjs}, \\
&\quad \texttt{.github/actions/setup-lean/**}, \operatorname{own}(\texttt{mutants.yml})] \\
w_{8} &= (\texttt{premise-tests.yml}, B, G_{8}) \\
G_{8} &= [\texttt{packages/premise-tests/**}, \texttt{packages/contracts/golden/ops/premise.jsonl}, \texttt{lean/Fw/Ops/Premise.lean}, \texttt{apps/runner/src/premises.ts}, \\
&\quad \texttt{package.json}, \texttt{pnpm-lock.yaml}, \texttt{pnpm-workspace.yaml}, \texttt{.github/scripts/changed-inputs.mjs}, \\
&\quad \texttt{.github/actions/setup-pnpm/**}, \texttt{.github/actions/gate-engine/**}, \texttt{.github/scripts/cache-key.mjs}, \\
&\quad \texttt{packages/contracts/golden/ops/cache.jsonl}, \operatorname{own}(\texttt{premise-tests.yml})] \\
w_{9} &= (\texttt{sim-speed.yml}, [\texttt{ci/sim-speed}], G_{9}) \\
G_{9} &= [\texttt{packages/measure-webkit/**}, \texttt{.github/scripts/sim-speed-*}, \texttt{.github/scripts/check-simulator.sh}, \texttt{.github/scripts/runner-info.sh}, \\
&\quad \texttt{.github/scripts/changed-inputs.mjs}, \operatorname{own}(\texttt{sim-speed.yml})] \\
w_{10} &= (\texttt{snapshot-extract.yml}, B, G_{10}) \\
G_{10} &= [\texttt{packages/snapshot-extract/**}, \texttt{packages/gate-breakpoints/**}, \texttt{apps/site/**}, \texttt{snapshot/**}, \\
&\quad \texttt{snapshot.lock.json}, \texttt{package.json}, \texttt{pnpm-lock.yaml}, \texttt{pnpm-workspace.yaml}, \\
&\quad \texttt{.github/scripts/verify-snapshot.mjs}, \texttt{.github/scripts/changed-inputs.mjs}, \texttt{.github/actions/setup-lean/**}, \texttt{.github/actions/setup-pnpm/**}, \\
&\quad \texttt{.github/actions/gate-engine/**}, \operatorname{own}(\texttt{snapshot-extract.yml})] \\
w_{11} &= (\texttt{visual-diff.yml}, B, G_{11}) \\
G_{11} &= [\texttt{packages/visual-diff/**}, \texttt{packages/gate-breakpoints/src/**}, \texttt{packages/gate-breakpoints/package.json}, \texttt{packages/contracts/golden/gate/**}, \\
&\quad \texttt{packages/contracts/golden/port/**}, \texttt{scripts/port/**}, \texttt{apps/site/**}, \texttt{@}\mathrm{breakgen}, \texttt{snapshot/**}, \texttt{snapshot.lock.json}, \\
&\quad \texttt{package.json}, \texttt{pnpm-lock.yaml}, \texttt{pnpm-workspace.yaml}, \texttt{.github/scripts/verify-snapshot.mjs}, \\
&\quad \texttt{.github/scripts/changed-inputs.mjs}, \texttt{.github/actions/setup-lean/**}, \texttt{.github/actions/setup-pnpm/**}, \texttt{.github/actions/gate-engine/**}, \\
&\quad \operatorname{own}(\texttt{visual-diff.yml})] \\
w_{12} &= (\texttt{webkit-sim.yml}, B, G_{12}) \\
G_{12} &= [\texttt{packages/measure-webkit/**}, \texttt{snapshot/**}, \texttt{snapshot.lock.json}, \texttt{.github/scripts/check-simulator.sh}, \\
&\quad \texttt{.github/scripts/verify-snapshot.mjs}, \texttt{.github/scripts/runner-info.sh}, \texttt{.github/scripts/changed-inputs.mjs}, \operatorname{own}(\texttt{webkit-sim.yml})] \\
w_{13} &= (\texttt{wktr-fixtures.yml}, [\texttt{ci/**}], G_{13}) \\
G_{13} &= [\texttt{packages/measure-wktr/**}, \texttt{packages/measure-chromium/src/classify.mjs}, \texttt{packages/measure-chromium/src/fwcore.mjs}, \texttt{@}\mathrm{fwcore}, \\
&\quad \texttt{packages/contracts/golden/measure/wktr.fixtures.jsonl}, \texttt{.github/scripts/runner-info.sh}, \texttt{.github/scripts/changed-inputs.mjs}, \texttt{.github/actions/setup-lean/**}, \\
&\quad \operatorname{own}(\texttt{wktr-fixtures.yml})] \\
w_{14} &= (\texttt{wktr.yml}, [\texttt{ci/**}], G_{14}) \\
G_{14} &= [\texttt{packages/measure-wktr/**}, \texttt{packages/measure-chromium/src/classify.mjs}, \texttt{packages/measure-chromium/src/fwcore.mjs}, \texttt{@}\mathrm{fwcore}, \\
&\quad \texttt{snapshot/**}, \texttt{snapshot.lock.json}, \texttt{.github/scripts/verify-snapshot.mjs}, \texttt{.github/scripts/runner-info.sh}, \\
&\quad \texttt{.github/scripts/changed-inputs.mjs}, \texttt{.github/actions/setup-lean/**}, \operatorname{own}(\texttt{wktr.yml})]
\end{aligned}$$

Each row is (workflow file, branches, input globs); `lean/**` is replaced by the binary's own inputs where the
workflow only builds `fwcore` or `breakgen`, while `lean.yml` and the lean checks keep `lean/**`. -/
def table : List Wf := [
  ⟨"breakpoint-gate.yml", ciAll, [
    "packages/gate-breakpoints/**", "apps/site/**", "@fwcore", "@breakgen", "snapshot/**", "snapshot.lock.json",
    "package.json", "pnpm-lock.yaml", "pnpm-workspace.yaml", ".github/scripts/gate-shards.mjs",
    ".github/scripts/gate-jobs.mjs", ".github/scripts/gate-jobs.test.mjs", ".github/scripts/cache-key.mjs", "packages/contracts/golden/gate/schedule.jsonl",
    "packages/contracts/golden/gate/shards.jsonl", "packages/contracts/golden/gate/exit.jsonl",
    "packages/contracts/golden/gate/search.jsonl", ".github/scripts/gate-search.mjs", ".github/scripts/gate-search.test.mjs",
    "packages/contracts/golden/ops/cache.jsonl", ".github/scripts/gate-smoke.mjs", ".github/scripts/merge-gate.mjs",
    ".github/scripts/verify-snapshot.mjs", ".github/scripts/changed-inputs.mjs", ".github/actions/setup-lean/**",
    ".github/actions/setup-pnpm/**", ".github/actions/gate-engine/**", ".github/actions/telemetry/**", "scripts/ci-telemetry/**", own "breakpoint-gate.yml"], []⟩,
  ⟨"chromium-counts.yml", ciAll, [
    "packages/measure-chromium/**", "apps/site/**", "@fwcore", "@breakgen", "snapshot/**", "snapshot.lock.json",
    "package.json", "pnpm-lock.yaml", "pnpm-workspace.yaml", ".github/scripts/verify-snapshot.mjs",
    ".github/scripts/runner-info.sh", ".github/scripts/changed-inputs.mjs", ".github/actions/setup-lean/**",
    ".github/actions/setup-pnpm/**", ".github/actions/telemetry/**", "scripts/ci-telemetry/**", own "chromium-counts.yml"], []⟩,
  ⟨"difftest.yml", ciAll, [
    "packages/difftest/**", "packages/measure-webkit/src/**", "packages/measure-chromium/src/**",
    "apps/runner/hooks/cap.mjs", "apps/console-api/src/cap/**", "@fwcore", "pnpm-lock.yaml",
    ".github/scripts/changed-inputs.mjs", ".github/actions/setup-lean/**", ".github/actions/setup-pnpm/**",
    own "difftest.yml"], []⟩,
  ⟨"engine-premises.yml", ciAll, [
    "packages/measure-chromium/**", "packages/measure-wktr/**", "packages/contracts/golden/ops/engine-premises.jsonl",
    ".github/scripts/runner-info.sh", ".github/scripts/changed-inputs.mjs", own "engine-premises.yml"], []⟩,
  ⟨"gate-gaps.yml", ciAll, [
    "packages/gate-breakpoints/**", "apps/site/**", "@fwcore", "@breakgen", "snapshot/**", "snapshot.lock.json",
    "package.json", "pnpm-lock.yaml", "pnpm-workspace.yaml", ".github/scripts/verify-snapshot.mjs",
    ".github/scripts/check-simulator.sh", ".github/scripts/changed-inputs.mjs", ".github/actions/setup-lean/**",
    ".github/actions/setup-pnpm/**", own "gate-gaps.yml"], []⟩,
  ⟨"land.yml", ["ci/land-*"], [
    "apps/**", "packages/**", "lean/**", "scripts/**", "package.json", "pnpm-lock.yaml", "pnpm-workspace.yaml",
    "docs/team/work-graph.json", "docs/team/incidents/ledger.json", "research/findings/ledger.json",
    "results/baselines/chromium/**", ".github/scripts/changed-inputs.mjs", ".github/actions/setup-lean/**",
    ".github/actions/setup-pnpm/**", own "land.yml"], []⟩,
  ⟨"lean.yml", ciMain, [
    "lean/**", "apps/site/src/breakpoints.gen.json", "apps/site/src/sweeps.gen.json", "apps/site/src/head.gen.json", "scripts/span.sh",
    "scripts/fwcore-build.sh", "packages/contracts/golden/gate/sweeps.jsonl", "packages/contracts/golden/gate/exit.jsonl", "packages/contracts/golden/gate/search.jsonl",
    "packages/gate-breakpoints/src/scope.gen.json", "packages/contracts/golden/parts/contracts.gen.json",
    "packages/contracts/golden/parts/stage.jsonl", "packages/contracts/golden/parts/stage-mode.jsonl", "packages/measure-chromium/scenarios.gen.json",
    "packages/contracts/golden/parts/morph.mount.dormant.jsonl",
    ".github/scripts/changed-inputs.mjs", ".github/actions/setup-lean/**", ".github/scripts/runner-info.sh",
    ".github/actions/telemetry/**", "scripts/ci-telemetry/**", own "lean.yml"], []⟩,
  ⟨"mutants.yml", ciAll, [
    "lean/Fw/Console.lean", "lean/Fw/Serve.lean", "lean/Fw/Ops/Meter.lean", "lean/Fw/Ops/PathCheck.lean",
    "lean/Fw/Ops/SpawnGuard.lean", "lean/Fw/Ops/Usage.lean", "lean/Fw/Ops/Wire.lean", "lean/Fw/Spec/DeviceQueue.lean",
    "lean/Fw/Wire.lean", "lean/FwTest/Mutants/**", "lean/scripts/mutants.sh", ".github/scripts/changed-inputs.mjs",
    ".github/actions/setup-lean/**", own "mutants.yml"], []⟩,
  ⟨"premise-tests.yml", ciMain, [
    "packages/premise-tests/**", "packages/contracts/golden/ops/premise.jsonl", "lean/Fw/Ops/Premise.lean",
    "apps/runner/src/premises.ts", "package.json", "pnpm-lock.yaml", "pnpm-workspace.yaml",
    ".github/scripts/changed-inputs.mjs", ".github/actions/setup-pnpm/**", ".github/actions/gate-engine/**",
    ".github/scripts/cache-key.mjs", "packages/contracts/golden/ops/cache.jsonl", ".github/actions/telemetry/**", "scripts/ci-telemetry/**", own "premise-tests.yml"], []⟩,
  ⟨"sim-speed.yml", ["ci/sim-speed"], [
    "packages/measure-webkit/**", ".github/scripts/sim-speed-*", ".github/scripts/check-simulator.sh",
    ".github/scripts/runner-info.sh", ".github/scripts/changed-inputs.mjs", own "sim-speed.yml"], []⟩,
  ⟨"snapshot-extract.yml", ciAll, [
    "packages/snapshot-extract/**", "packages/gate-breakpoints/**", "apps/site/**", "snapshot/**", "snapshot.lock.json",
    "package.json", "pnpm-lock.yaml", "pnpm-workspace.yaml", ".github/scripts/verify-snapshot.mjs",
    ".github/scripts/changed-inputs.mjs", ".github/actions/setup-lean/**", ".github/actions/setup-pnpm/**",
    ".github/actions/gate-engine/**", own "snapshot-extract.yml"], []⟩,
  ⟨"visual-diff.yml", ciAll, [
    "packages/visual-diff/**", "packages/gate-breakpoints/src/**", "packages/gate-breakpoints/package.json",
    "packages/contracts/golden/gate/**", "packages/contracts/golden/port/**", "scripts/port/**", "apps/site/**",
    "@breakgen", "snapshot/**", "snapshot.lock.json", "package.json",
    "pnpm-lock.yaml", "pnpm-workspace.yaml", ".github/scripts/verify-snapshot.mjs", ".github/scripts/changed-inputs.mjs",
    ".github/actions/setup-lean/**", ".github/actions/setup-pnpm/**", ".github/actions/gate-engine/**",
    own "visual-diff.yml"], []⟩,
  ⟨"webkit-sim.yml", ciAll, [
    "packages/measure-webkit/**", "snapshot/**", "snapshot.lock.json", ".github/scripts/check-simulator.sh",
    ".github/scripts/verify-snapshot.mjs", ".github/scripts/runner-info.sh", ".github/scripts/changed-inputs.mjs",
    ".github/actions/telemetry/**", "scripts/ci-telemetry/**", own "webkit-sim.yml"], []⟩,
  ⟨"wktr-fixtures.yml", ciAll, [
    "packages/measure-wktr/**", "packages/measure-chromium/src/classify.mjs", "packages/measure-chromium/src/fwcore.mjs",
    "@fwcore", "packages/contracts/golden/measure/wktr.fixtures.jsonl", ".github/scripts/runner-info.sh",
    ".github/scripts/changed-inputs.mjs", ".github/actions/setup-lean/**", own "wktr-fixtures.yml"], []⟩,
  ⟨"wktr.yml", ciAll, [
    "packages/measure-wktr/**", "packages/measure-chromium/src/classify.mjs", "packages/measure-chromium/src/fwcore.mjs",
    "@fwcore", "snapshot/**", "snapshot.lock.json", ".github/scripts/verify-snapshot.mjs", ".github/scripts/runner-info.sh",
    ".github/scripts/changed-inputs.mjs", ".github/actions/setup-lean/**", own "wktr.yml"], []⟩]

#guard (table.map (·.file)).eraseDups.length == table.length

/-- A small stand-in for the cones, for the replay cases (the real cones come from the checkout).
$$\mathrm{cone}(r) = \begin{cases} [\texttt{lean/Fw/Wire.lean},\ \texttt{lean/Fw/Ops/Wire.lean}] & r = \texttt{Main} \\ [\texttt{lean/Fw/Site/Breakpoints.lean}] & r = \texttt{BreakgenMain} \\ [\,] & \text{otherwise} \end{cases}$$ -/
def sampleCone : String → List String
  | "Main" => ["lean/Fw/Wire.lean", "lean/Fw/Ops/Wire.lean"]
  | "BreakgenMain" => ["lean/Fw/Site/Breakpoints.lean"]
  | _ => []

/-- Files started by a push (names only) under the sample cones.
$$\operatorname{run}(D, M) = \operatorname{started}(W, S_{\mathrm{sample}}, D, \lambda x.\ x \notin M)$$ -/
def run (diff merged : List String) : List String :=
  startedBy (setMap sampleCone) table diff (fun x => !merged.contains x)

-- a Lean test file, a script and a golden change do not start the lanes that only build the binary
#guard run ["lean/FwTest/Lease.lean"] [] == ["land.yml", "lean.yml"]
#guard run ["lean/Fw/Wire.lean"] [] == ["breakpoint-gate.yml", "chromium-counts.yml", "difftest.yml", "gate-gaps.yml", "land.yml", "lean.yml", "mutants.yml", "wktr-fixtures.yml", "wktr.yml"]
#guard run ["lean/Fw/Parts/HeroExit.lean"] [] == ["land.yml", "lean.yml"]
-- the site builder (breakgen) cone starts the lanes that build the site; a pixel golden starts the visual diff only
#guard run ["lean/Fw/Site/Breakpoints.lean"] [] == ["breakpoint-gate.yml", "chromium-counts.yml", "gate-gaps.yml", "land.yml", "lean.yml", "visual-diff.yml"]
#guard run ["packages/contracts/golden/gate/pixel.jsonl"] [] == ["land.yml", "visual-diff.yml"]
#guard run ["docs/team/handoffs/x.md"] [] == []
-- a merge of main changes lean/ and apps/site but starts nothing
#guard run ["lean/Fw/Wire.lean", "apps/site/src/a.ts"] ["lean/Fw/Wire.lean", "apps/site/src/a.ts"] == []
#guard run ["packages/measure-wktr/src/a.mjs", "lean/Fw/Wire.lean"] ["lean/Fw/Wire.lean"] == ["engine-premises.yml", "land.yml", "wktr-fixtures.yml", "wktr.yml"]
-- a fixture page starts both wktr lanes; the fixture workflow file starts only itself
#guard run ["packages/measure-wktr/fixtures/control/index.html"] [] == ["engine-premises.yml", "land.yml", "wktr-fixtures.yml", "wktr.yml"]
#guard run [".github/workflows/wktr-fixtures.yml"] [] == ["wktr-fixtures.yml"]

/-! ## Main pushes (task `ci-main-triggers`)

A `main` push runs only the jobs that save the caches main seeded before this task (`mainBefore`); `wktr-zip` stays
excluded. A run restores caches of its own branch and of the default branch only (docs.github.com, dependency caching,
"Restrictions for accessing a cache"). -/

/-- Every job that saves a cache, as (workflow, job, cache), the cache named by the last segment of its `path:`.
`scripts/ci-paths.mjs` reads the same list from the workflows and their local actions and fails when they differ. -/
def cacheWriters : List (String × String × String) := [
  ("breakpoint-gate.yml", "gate", "gate-apt"), ("breakpoint-gate.yml", "gate", "ms-playwright"),
  ("breakpoint-gate.yml", "gate", "hs-zip"), ("engine-premises.yml", "webkit", "wktr-zip"),
  ("lean.yml", "lean", ".lake-cache"), ("premise-tests.yml", "engine", "gate-apt"),
  ("premise-tests.yml", "engine", "ms-playwright"), ("premise-tests.yml", "engine", "hs-zip"),
  ("snapshot-extract.yml", "extract", "gate-apt"), ("snapshot-extract.yml", "extract", "ms-playwright"),
  ("snapshot-extract.yml", "extract", "hs-zip"), ("visual-diff.yml", "navscroll", "gate-apt"),
  ("visual-diff.yml", "navscroll", "ms-playwright"), ("visual-diff.yml", "navscroll", "hs-zip"),
  ("visual-diff.yml", "people-layout", "gate-apt"),
  ("visual-diff.yml", "people-layout", "ms-playwright"), ("visual-diff.yml", "people-layout", "hs-zip"),
  ("visual-diff.yml", "port-fonts", "gate-apt"),
  ("visual-diff.yml", "port-fonts", "ms-playwright"), ("visual-diff.yml", "port-fonts", "hs-zip"),
  ("visual-diff.yml", "shoot", "gate-apt"), ("visual-diff.yml", "shoot", "ms-playwright"),
  ("visual-diff.yml", "shoot", "hs-zip"),
  ("wktr-fixtures.yml", "fixtures", "wktr-zip"), ("wktr.yml", "wktr", "wktr-zip")]

/-- The workflows whose push trigger listed `main` before task `ci-main-triggers` (commit 473b49c1). -/
def mainBefore : List String := ["breakpoint-gate.yml", "chromium-counts.yml", "difftest.yml", "gate-gaps.yml",
  "lean.yml", "mutants.yml", "premise-tests.yml", "snapshot-extract.yml", "visual-diff.yml", "webkit-sim.yml"]

/-- The caches job `j` of workflow `f` saves. -/
def savedBy (f j : String) : List String := (cacheWriters.filter fun w => w.1 == f && w.2.1 == j).map (·.2.2)

/-- The caches a `main` push seeds: every cache that a job of a `mainBefore` workflow saved. -/
def seededCaches : List String := ((cacheWriters.filter fun w => mainBefore.contains w.1).map (·.2.2)).eraseDups

/-- The (workflow, job) pairs a `main` push runs besides the workflow's `guard`: they save the caches main seeded
before this task (`mainBefore`); `wktr-zip` is excluded. -/
def seeders : List (String × String) := [("lean.yml", "lean"), ("premise-tests.yml", "engine")]

/-- The job `if:` conjunct that skips a job on a `main` push and keeps it on every other event. -/
def notMainPush : String := "github.event_name != 'push' || github.ref != 'refs/heads/main'"

/-- A push to `main` starts a run of the workflow. -/
def Wf.onMain (w : Wf) : Bool := w.branches.contains "main"

/-- A `main` push runs job `j` of workflow `w`. -/
def mainRuns (w : Wf) (j : String) : Bool := w.onMain && (j == "guard" || seeders.contains (w.file, j))

/-- The branches of a list other than `main`. -/
def ciPart (bs : List String) : List String := bs.filter (· != "main")

/-- Every seeded cache is saved by a seeder. -/
theorem seeders_cover : ∀ c ∈ seededCaches, ∃ s ∈ seeders, c ∈ savedBy s.1 s.2 := by decide

/-- Every cache a seeder saves is a seeded cache. -/
theorem seeders_only_seeded : ∀ s ∈ seeders, ∀ c ∈ savedBy s.1 s.2, c ∈ seededCaches := by decide

/-- **The seeders save exactly the seeded caches.** -/
theorem seeders_save_iff (c : String) : c ∈ seededCaches ↔ ∃ s ∈ seeders, c ∈ savedBy s.1 s.2 :=
  ⟨seeders_cover c, fun ⟨s, hs, hc⟩ => seeders_only_seeded s hs c hc⟩

/-- Every seeder saves some cache. -/
theorem seeders_save : ∀ s ∈ seeders, savedBy s.1 s.2 ≠ [] := by decide

/-- The seeded caches: the Lake artifacts and the three gate-engine downloads. -/
theorem seeded_caches : seededCaches = ["gate-apt", "ms-playwright", "hs-zip", ".lake-cache"] := by decide

/-- The one cache no `main` push seeds: its writers never ran on `main`. -/
theorem unseeded_caches :
    (cacheWriters.map (·.2.2)).eraseDups.filter (fun c => !seededCaches.contains c) = ["wktr-zip"] := by decide

/-- A workflow lists `main` iff a seeder job is in it. -/
theorem main_iff_seeder : ∀ w ∈ table, w.onMain = true ↔ w.file ∈ seeders.map Prod.fst := by decide

/-- Every seeder names a workflow of the table. -/
theorem seeders_in_table : ∀ s ∈ seeders, ∃ w ∈ table, w.file = s.1 := by decide

/-- **A `main` push runs only the seeders.** It runs a job iff the job is a seeder, or the guard of a seeder's
workflow. -/
theorem mainRuns_iff (w : Wf) (hw : w ∈ table) (j : String) :
    mainRuns w j = true ↔ (w.file, j) ∈ seeders ∨ (j = "guard" ∧ w.file ∈ seeders.map Prod.fst) := by
  have hm := main_iff_seeder w hw
  simp only [mainRuns, Bool.and_eq_true, Bool.or_eq_true, beq_iff_eq, List.contains_iff_mem]
  constructor
  · rintro ⟨h, rfl | hs⟩
    · exact Or.inr ⟨rfl, hm.mp h⟩
    · exact Or.inl hs
  · rintro (hs | ⟨rfl, hf⟩)
    · exact ⟨hm.mpr (List.mem_map.mpr ⟨_, hs, rfl⟩), Or.inr hs⟩
    · exact ⟨hm.mpr hf, Or.inl rfl⟩

/-- **No workflow has a cron.** A schedule runs on the default branch, so a cron would start a `main` run. -/
theorem no_crons : ∀ w ∈ table, w.crons = [] := by decide

/-- The keys the top-level `on:` of a workflow may hold; `scripts/ci-paths.mjs` refuses every other key. -/
def Wf.onKeys (w : Wf) : List String := ["push", "workflow_dispatch"] ++ (if w.crons = [] then [] else ["schedule"])

/-- `push` is an allowed key. -/
theorem onKeys_push (w : Wf) : "push" ∈ w.onKeys := by simp [Wf.onKeys]

/-- `workflow_dispatch` is an allowed key. -/
theorem onKeys_dispatch (w : Wf) : "workflow_dispatch" ∈ w.onKeys := by simp [Wf.onKeys]

/-- `schedule` is an allowed key iff the row has a cron. -/
theorem onKeys_schedule (w : Wf) : "schedule" ∈ w.onKeys ↔ w.crons ≠ [] := by
  by_cases h : w.crons = [] <;> simp [Wf.onKeys, h]

/-- **The `on:` allowlist.** A key is allowed iff it is `push`, `workflow_dispatch`, or `schedule` with a cron. -/
theorem onKeys_iff (w : Wf) (k : String) :
    k ∈ w.onKeys ↔ k = "push" ∨ k = "workflow_dispatch" ∨ (k = "schedule" ∧ w.crons ≠ []) := by
  by_cases h : w.crons = [] <;> simp [Wf.onKeys, h]

/-- Every row allows exactly `push` and `workflow_dispatch`, so no workflow has a key that starts a `main` run. -/
theorem table_onKeys : ∀ w ∈ table, w.onKeys = ["push", "workflow_dispatch"] := by decide

#guard (⟨"x.yml", ciAll, [], ["0 0 * * *"]⟩ : Wf).onKeys == ["push", "workflow_dispatch", "schedule"]
#guard !(⟨"x.yml", ciAll, [], []⟩ : Wf).onKeys.contains "schedule"
#guard !(⟨"x.yml", ciAll, [], []⟩ : Wf).onKeys.contains "workflow_run"
#guard !(⟨"x.yml", ciAll, [], ["0 0 * * *"]⟩ : Wf).onKeys.contains "pull_request"

/-- A row lists its `ci/` branches, then `main` iff it runs on `main`. -/
theorem branches_split : ∀ w ∈ table, w.branches = ciPart w.branches ++ (if w.onMain then ["main"] else []) := by
  decide

/-- The `ci/**` triggers, unchanged by task `ci-main-triggers`. -/
theorem ci_triggers : table.map (fun w => (w.file, ciPart w.branches)) = [
    ("breakpoint-gate.yml", ["ci/**"]), ("chromium-counts.yml", ["ci/**"]), ("difftest.yml", ["ci/**"]),
    ("engine-premises.yml", ["ci/**"]), ("gate-gaps.yml", ["ci/**"]), ("land.yml", ["ci/land-*"]),
    ("lean.yml", ["ci/**"]), ("mutants.yml", ["ci/**"]), ("premise-tests.yml", ["ci/**"]), ("sim-speed.yml", ["ci/sim-speed"]),
    ("snapshot-extract.yml", ["ci/**"]), ("visual-diff.yml", ["ci/**"]), ("webkit-sim.yml", ["ci/**"]),
    ("wktr-fixtures.yml", ["ci/**"]), ("wktr.yml", ["ci/**"])] := by decide

#guard (table.filter (·.onMain)).map (·.file) == ["lean.yml", "premise-tests.yml"]
#guard table.all fun w => (ciPart w.branches).all (·.startsWith "ci/")
#guard table.any fun w => w.file == "lean.yml" && mainRuns w "lean" && mainRuns w "guard"
#guard table.any fun w => w.file == "premise-tests.yml" && mainRuns w "engine" && !mainRuns w "verdict"
#guard !table.any fun w => w.file == "lean.yml" && mainRuns w "engine"
#guard !table.any fun w => w.file == "breakpoint-gate.yml" && mainRuns w "guard"
#guard savedBy "premise-tests.yml" "engine" == ["gate-apt", "ms-playwright", "hs-zip"]

/-! ### The job `if:` that skips a `main` push

A non-seeder job of a workflow that lists `main` carries `${{ (e) && (notMainPush) }}`, or `${{ (notMainPush) }}` when
it had no `if:`. The left group is checked to close only at its end (outside quoted strings), so `&&` is the top-level
operator whatever `e` holds. -/

/-- The text before the first group. -/
def openL : List Char := "${{ (".toList

/-- The text between the two groups. -/
def andL : List Char := ") && (".toList

/-- The text after the last group. -/
def closeL : List Char := ") }}".toList

/-- The two-group form with condition `m` and conjunct `c`. -/
def wrapL (c m : List Char) : List Char := openL ++ m ++ andL ++ c ++ closeL

/-- The one-group form with conjunct `c`. -/
def bareL (c : List Char) : List Char := openL ++ c ++ closeL

/-- Scanning from depth `d` (inside a quoted string iff `q`), the parentheses never close the outer group and end at
depth 1 outside a string. -/
def inner : Nat → Bool → List Char → Bool
  | d, q, [] => d == 1 && !q
  | d, true, '\'' :: r => inner d false r
  | d, true, _ :: r => inner d true r
  | d, false, '\'' :: r => inner d true r
  | d, false, '(' :: r => inner (d + 1) false r
  | d, false, ')' :: r => d > 1 && inner (d - 1) false r
  | d, false, _ :: r => inner d false r

/-- The first group of `t` if `t` has the two-group form with conjunct `c`. -/
def candidate (c t : List Char) : List Char :=
  (t.drop openL.length).take (t.length - (openL.length + andL.length + c.length + closeL.length))

/-- Does `t` have the one-group form, or the two-group form with a first group that closes only at its end? -/
def carries (c t : List Char) : Bool :=
  t == bareL c || (t == wrapL c (candidate c t) && inner 1 false (candidate c t))

/-- The first group of the two-group form is its condition. -/
theorem candidate_wrap (c m : List Char) : candidate c (wrapL c m) = m := by
  have h1 : (openL ++ m ++ andL ++ c ++ closeL).drop openL.length = m ++ (andL ++ c ++ closeL) := by
    simp [List.append_assoc]
  simp only [candidate, wrapL, h1, List.length_append]
  rw [List.take_append_of_le_length (by omega), List.take_of_length_le (by omega)]

/-- The one-group form is accepted. -/
theorem carries_bare (c : List Char) : carries c (bareL c) = true := by simp [carries]

/-- The two-group form is accepted when its condition closes only at its end. -/
theorem carries_wrap (c m : List Char) (h : inner 1 false m = true) : carries c (wrapL c m) = true := by
  simp [carries, candidate_wrap, h]

/-- **Only the two forms are accepted.** -/
theorem carries_sound (c t : List Char) (h : carries c t = true) :
    t = bareL c ∨ ∃ m, inner 1 false m = true ∧ t = wrapL c m := by
  simp only [carries, Bool.or_eq_true, Bool.and_eq_true, beq_iff_eq] at h
  rcases h with h | ⟨h, hi⟩
  · exact Or.inl h
  · exact Or.inr ⟨_, hi, h⟩

/-- `notMainPush` is itself a group. -/
theorem notMainPush_inner : inner 1 false notMainPush.toList = true := by decide

/-- The `if:` a non-seeder job gets from its own condition `orig`, if any. -/
def withNotMain (orig : Option String) : String :=
  String.ofList (match orig with
    | none => bareL notMainPush.toList
    | some o => wrapL notMainPush.toList o.toList)

/-- Does a job `if:` carry `notMainPush` as its top-level conjunct? -/
def carriesNotMain (t : String) : Bool := carries notMainPush.toList t.toList

/-- A job without an `if:` gets an accepted one. -/
theorem withNotMain_none : carriesNotMain (withNotMain none) = true := by
  simp [carriesNotMain, withNotMain, carries_bare]

/-- A job whose condition closes only at its end gets an accepted `if:`. -/
theorem withNotMain_some (o : String) (h : inner 1 false o.toList = true) :
    carriesNotMain (withNotMain (some o)) = true := by
  simp [carriesNotMain, withNotMain, carries_wrap _ _ h]

/-- The conditions of the golden `if:` cases (`none`: a job without an `if:`). -/
def ifOrigs : List (Option String) := [none, some "needs.guard.outputs.run == 'true'", some "a || b",
  some "a) || (b", some "x == '('", some "always() && needs.guard.outputs.run == 'true'"]

/-- The `if:` texts of the golden check cases. -/
def ifTexts : List String := [withNotMain none, withNotMain (some "a || b"),
  "${{ (" ++ notMainPush ++ ") || true }}", "${{ a || b && (" ++ notMainPush ++ ") }}",
  "${{ (a) || (b) && (" ++ notMainPush ++ ") }}", "${{ a == 'b' }}", ""]

#guard carriesNotMain (withNotMain (some "a || b"))
#guard !carriesNotMain "${{ (x) || true }}"
#guard !carriesNotMain ("${{ (" ++ notMainPush ++ ") || true }}")
#guard !carriesNotMain ("${{ a || b && (" ++ notMainPush ++ ") }}")
#guard !carriesNotMain (withNotMain (some "a) || (b"))
#guard carriesNotMain (withNotMain (some "x == '('"))

/-! ## Coarse push filter, precise guard (task `ci-cone-glob`)

The generated `on.push.paths` used to list every file of the cones, so each new module imported by `Main.lean` rewrote
7–8 workflow files and every parallel branch that added a module conflicted there. Now the static filter replaces each
cone by the fixed globs `coneGlobs` (`pushPaths`, which takes no cone at all), and the guard job computes the precise
cone from the checkout at run time and decides `starts` exactly (`starts_iff`). `coarse_sound` shows the static filter
never drops a path the precise inputs hold, as long as the cones stay inside `coneGlobs` (`ConeWithin`, checked by
`scripts/ci-paths.mjs`); `paths_stable_under_new_module` shows a new module under `lean/Fw` keeps that. -/

/-- The fixed globs that stand in for every import cone in `on.push.paths`.
$$C = [\texttt{lean/Fw/**},\ \texttt{lean/*.lean}]$$ -/
def coneGlobs : List String := ["lean/Fw/**", "lean/*.lean"]

/-- A path is literal: none of its segments holds a `*`.
$$\forall f:\ \operatorname{lit}(f) \iff \forall s \in \mathrm{segs}(f):\ \texttt{*} \notin s$$ -/
def Literal (f : String) : Prop := ∀ s ∈ segs f, '*' ∉ s.toList

/-- The cones stay inside the coarse globs: every file of every cone is literal and in the scope of $C$.
$$\forall c:\ \operatorname{within}(c) \iff \forall r,\ \forall f \in c(r):\ \operatorname{lit}(f) \land \mathrm{in}(\mathrm{parse}(C), f)$$ -/
def ConeWithin (cone : String → List String) : Prop :=
  ∀ r, ∀ f ∈ cone r, Literal f ∧ inScope (parseScope coneGlobs) f = true

/-- The workflow's generated `on.push.paths`: its inputs with every cone replaced by $C$. It takes no cone, so no
change of the import graph can change it.
$$\forall w:\ \operatorname{push}(w) = \operatorname{expand}(S_C, w.G),\qquad S_C = \operatorname{setMap}(\lambda r.\ C)$$ -/
def pushPaths (w : Wf) : List String := expand (setMap fun _ => coneGlobs) w.inputs

/-- Add one file to the cone of one root (a new module that the root now imports).
$$\forall c, r_0, f, r:\ \operatorname{add}(c, r_0, f)(r) = \begin{cases} f :: c(r) & r = r_0 \\ c(r) & r \ne r_0 \end{cases}$$ -/
def addModule (cone : String → List String) (root f : String) : String → List String :=
  fun r => if r = root then f :: cone r else cone r

/-- An expanded input under one cone map is an expanded input under the other map, unless it is a cone file of a root
whose whole cone the other map expands.
$$\forall c, c', G, g:\ g \in \operatorname{expand}(\operatorname{setMap}(c), G) \Rightarrow g \in \operatorname{expand}(\operatorname{setMap}(c'), G) \lor \exists r:\ g \in c(r) \land c'(r) \subseteq \operatorname{expand}(\operatorname{setMap}(c'), G)$$ -/
theorem mem_expand_setMap (c c' : String → List String) (gs : List String) (g : String)
    (h : g ∈ expand (setMap c) gs) :
    g ∈ expand (setMap c') gs ∨ ∃ r, g ∈ c r ∧ ∀ y ∈ c' r, y ∈ expand (setMap c') gs := by
  simp only [expand, List.mem_flatMap] at h ⊢
  obtain ⟨i, hi, hg⟩ := h
  by_cases ha : i.startsWith "@" = true
  · rw [ite_eq_left ha] at hg
    unfold setMap at hg
    cases hl : sets.lookup i with
    | none =>
      rw [hl] at hg
      left
      exact ⟨i, hi, by rw [ite_eq_left ha]; unfold setMap; rw [hl]; exact hg⟩
    | some xs =>
      rw [hl] at hg
      simp only [List.mem_flatMap] at hg
      obtain ⟨h0, hh0, hg0⟩ := hg
      by_cases hc : h0.startsWith "@cone:" = true
      · rw [ite_eq_left hc] at hg0
        right
        refine ⟨_, hg0, fun y hy => ⟨i, hi, ?_⟩⟩
        rw [ite_eq_left ha]; unfold setMap; rw [hl]
        simp only [List.mem_flatMap]
        exact ⟨h0, hh0, by rw [ite_eq_left hc]; exact hy⟩
      · rw [ite_eq_right hc] at hg0
        left
        refine ⟨i, hi, ?_⟩
        rw [ite_eq_left ha]; unfold setMap; rw [hl]
        simp only [List.mem_flatMap]
        exact ⟨h0, hh0, by rw [ite_eq_right hc]; exact hg0⟩
  · rw [ite_eq_right ha] at hg
    left
    exact ⟨i, hi, by rw [ite_eq_right ha]; exact hg⟩

/-- A literal glob matches only its own path and the paths below it.
$$\forall f, p:\ \operatorname{lit}(f) \land \mathrm{mp}(\mathrm{segs}(f), p) \Rightarrow \exists u:\ p = \mathrm{segs}(f) \mathbin{+\!\!+} u$$ -/
theorem literal_prefix (f : String) (p : List String) (hl : Literal f) (h : matchesPath (segs f) p = true) :
    ∃ u, p = segs f ++ u := by
  simp only [matchesPath, List.any_eq_true, List.mem_range] at h
  obtain ⟨k, _, hm⟩ := h
  have hlit : ∀ g ∈ segs f, g ≠ "**" ∧ '*' ∉ g.toList := fun g hg =>
    ⟨fun he => hl g hg (by rw [he]; decide), hl g hg⟩
  have he := (globMatch_lit _ _ hlit).mp hm
  exact ⟨p.drop (k + 1), by rw [he, List.take_append_drop]⟩

/-- **The coarse filter is sound.** If the cones stay inside $C$, every path in the scope of the precise inputs (cones
expanded from the checkout) is in the scope of the generated push paths.
$$\forall c, G, x:\ \operatorname{within}(c) \land \mathrm{in}(\mathrm{parse}(\operatorname{expand}(\operatorname{setMap}(c), G)), x) \Rightarrow \mathrm{in}(\mathrm{parse}(\operatorname{expand}(S_C, G)), x)$$ -/
theorem coarse_sound (c : String → List String) (hc : ConeWithin c) (gs : List String) (x : String)
    (h : inScope (parseScope (expand (setMap c) gs)) x = true) :
    inScope (parseScope (expand (setMap fun _ => coneGlobs) gs)) x = true := by
  rw [inScope_iff] at h ⊢
  obtain ⟨hne, hdd, ⟨g, hg, hm⟩, hex⟩ := h
  refine ⟨hne, hdd, ?_, ?_⟩
  · simp only [parseScope, List.mem_map, List.mem_filter] at hg
    obtain ⟨g0, ⟨hg0, hn⟩, rfl⟩ := hg
    rcases mem_expand_setMap c (fun _ => coneGlobs) gs g0 hg0 with hq | ⟨r, hr, hall⟩
    · exact ⟨segs g0, by simp only [parseScope, List.mem_map, List.mem_filter]; exact ⟨g0, ⟨hq, hn⟩, rfl⟩, hm⟩
    · obtain ⟨hlit, hin⟩ := hc r g0 hr
      obtain ⟨u, hu⟩ := literal_prefix g0 _ hlit hm
      rw [inScope_iff] at hin
      obtain ⟨_, _, ⟨g1, hg1, hm1⟩, _⟩ := hin
      simp only [parseScope, List.mem_map, List.mem_filter] at hg1
      obtain ⟨g2, ⟨hg2, hn2⟩, rfl⟩ := hg1
      refine ⟨segs g2, ?_, by rw [hu]; exact matchesPath_append _ _ _ hm1⟩
      simp only [parseScope, List.mem_map, List.mem_filter]
      exact ⟨g2, ⟨hall g2 hg2, hn2⟩, rfl⟩
  · intro g hg
    simp only [parseScope, List.mem_map, List.mem_filter] at hg
    obtain ⟨g0, ⟨hg0, hb⟩, rfl⟩ := hg
    rcases mem_expand_setMap (fun _ => coneGlobs) c gs g0 hg0 with hp | ⟨r, hr, _⟩
    · exact hex _ (by simp only [parseScope, List.mem_map, List.mem_filter]; exact ⟨g0, ⟨hp, hb⟩, rfl⟩)
    · exfalso
      simp only [coneGlobs, List.mem_cons, List.not_mem_nil, or_false] at hr
      rcases hr with rfl | rfl <;> exact absurd hb (by simp)

/-- **The generated push filter never drops a needed start.** If the cones stay inside $C$ and the guard's precise
decision starts the workflow, GitHub's static `paths` filter passes the push's diff.
$$\forall c, w, D, m:\ \operatorname{within}(c) \land \operatorname{starts}(w, \operatorname{setMap}(c), \operatorname{eff}(D, m)) \Rightarrow \operatorname{sel}(\operatorname{push}(w), D)$$ -/
theorem push_filter_passes (c : String → List String) (hc : ConeWithin c) (w : Wf) (diff : List String)
    (differs : String → Bool) (h : w.starts (setMap c) (effective diff differs) = true) :
    selected (pushPaths w) diff = true := by
  obtain ⟨x, hx, _, hi⟩ := (starts_iff (setMap c) w diff differs).mp h
  exact selected_of_mem _ _ x hx (coarse_sound c hc w.inputs x hi)

/-- **A new module under `lean/Fw` changes no workflow file.** The push paths take no cone, so they are the same
before and after; and if the new file is literal and inside $C$, the grown cones still stay inside $C$, so the same
push paths still pass every push the guard starts.
$$\forall c, r_0, f:\ \bigl(\operatorname{within}(c) \land \operatorname{lit}(f) \land \mathrm{in}(\mathrm{parse}(C), f)\bigr) \Rightarrow \Bigl(\operatorname{within}(\operatorname{add}(c, r_0, f)) \land \forall w, D, m:\ \bigl(\operatorname{starts}(w, \operatorname{setMap}(\operatorname{add}(c, r_0, f)), \operatorname{eff}(D, m)) \Rightarrow \operatorname{sel}(\operatorname{push}(w), D)\bigr)\Bigr)$$ -/
theorem paths_stable_under_new_module (c : String → List String) (root f : String) (hc : ConeWithin c)
    (hl : Literal f) (hf : inScope (parseScope coneGlobs) f = true) :
    ConeWithin (addModule c root f) ∧ ∀ (w : Wf) (diff : List String) (differs : String → Bool),
      w.starts (setMap (addModule c root f)) (effective diff differs) = true → selected (pushPaths w) diff = true := by
  have hc' : ConeWithin (addModule c root f) := by
    intro r y hy
    unfold addModule at hy
    split at hy
    · rcases List.mem_cons.mp hy with rfl | hy
      · exact ⟨hl, hf⟩
      · exact hc r y hy
    · exact hc r y hy
  exact ⟨hc', fun w diff differs h => push_filter_passes _ hc' w diff differs h⟩

/-- The workflows whose generated push filter passes a diff (GitHub's static step, before the guard).
$$\forall D:\ \operatorname{filtered}(D) = [\, w.\mathit{file} : w \in W,\ \operatorname{sel}(\operatorname{push}(w), D) \,]$$ -/
def filtered (diff : List String) : List String :=
  (table.filter fun w => selected (pushPaths w) diff).map (·.file)

-- the coarse filter passes a new module under lean/Fw for every fwcore user; the guard then starts only lean.yml
#guard filtered ["lean/Fw/New.lean"] == ["breakpoint-gate.yml", "chromium-counts.yml", "difftest.yml", "gate-gaps.yml", "land.yml", "lean.yml", "visual-diff.yml", "wktr-fixtures.yml", "wktr.yml"]
#guard run ["lean/Fw/New.lean"] [] == ["land.yml", "lean.yml"]
-- a test module is outside every coarse fwcore glob
#guard filtered ["lean/FwTest/Lease.lean"] == ["land.yml", "lean.yml"]
-- the sample cones stay inside the coarse globs
#guard (["Main", "BreakgenMain"].flatMap sampleCone).all (inScope (parseScope coneGlobs))
-- the old precise paths moved with a new module; the push paths do not depend on the cone
#guard expand (setMap sampleCone) ["@fwcore"] != expand (setMap (addModule sampleCone "Main" "lean/Fw/New.lean")) ["@fwcore"]

/-! ## Golden (`packages/contracts/golden/ci/triggers.jsonl`) -/

/-- A JSON array of strings. $$\operatorname{strs}(xs) = [\, \mathrm{str}(x) : x \in xs \,]$$ -/
def strs (xs : List String) : Json := .arr (xs.map Json.str).toArray

/-- The table line: workflows with branches and symbolic inputs, and the named sets.
$$\operatorname{tableLine} = \{\texttt{kind}: \texttt{table},\ \texttt{workflows}: [\,\{\texttt{file}: w.\mathit{file},\ \texttt{branches}: w.B,\ \texttt{inputs}: w.G\} : w \in W\,],\ \texttt{sets}: \mathrm{sets},\ \texttt{coneGlobs}: C\}$$ -/
def tableLine : Json :=
  Json.mkObj [("kind", "table"),
    ("workflows", .arr (table.map fun w => Json.mkObj [("file", .str w.file), ("branches", strs w.branches),
      ("inputs", strs w.inputs), ("crons", strs w.crons), ("onKeys", strs w.onKeys)]).toArray),
    ("sets", Json.mkObj (sets.map fun (n, xs) => (n, strs xs))), ("coneGlobs", strs coneGlobs),
    ("seeders", .arr (seeders.map fun (f, j) => Json.mkObj [("file", .str f), ("job", .str j)]).toArray),
    ("notMainPush", .str notMainPush),
    ("cacheWriters", .arr (cacheWriters.map fun (f, j, c) =>
      Json.mkObj [("file", .str f), ("job", .str j), ("cache", .str c)]).toArray)]

/-- The replay cases: a push (its diff, the paths that already equal `main`); the workflows it starts under the
sample cones are added by `caseLine`.
$$\begin{aligned}
\mathrm{cases} = [\, &(\text{docs only}, [\texttt{docs/team/handoffs/x.md}], [\,]), \\
&(\text{lean test file}, [\texttt{lean/FwTest/Lease.lean}], [\,]), \\
&(\text{lean script}, [\texttt{lean/scripts/check.sh}], [\,]), \\
&(\text{a part module outside the fwcore cone}, [\texttt{lean/Fw/Parts/HeroExit.lean}], [\,]), \\
&(\text{a module in the fwcore cone}, [\texttt{lean/Fw/Wire.lean}], [\,]), \\
&(\text{a new module under lean/Fw, not yet imported}, [\texttt{lean/Fw/New.lean}], [\,]), \\
&(\text{the breakgen cone}, [\texttt{lean/Fw/Site/Breakpoints.lean}], [\,]), \\
&(\text{lake manifest}, [\texttt{lean/lake-manifest.json}], [\,]), \\
&(\text{wktr package}, [\texttt{packages/measure-wktr/src/a.mjs}], [\,]), \\
&(\text{site source}, [\texttt{apps/site/src/a.tsx}], [\,]), \\
&(\text{the guard script}, [\texttt{.github/scripts/changed-inputs.mjs}], [\,]), \\
&(\text{a merge of main only}, X, X), \\
&(\text{a merge of main plus one own file}, [\texttt{lean/Fw/Wire.lean}, \texttt{packages/measure-wktr/src/a.mjs}], [\texttt{lean/Fw/Wire.lean}]), \\
&(\text{the workflow file itself}, [\texttt{.github/workflows/wktr.yml}], [\,]), \\
&(\text{a wktr fixture page}, [\texttt{packages/measure-wktr/fixtures/control/index.html}], [\,]), \\
&(\text{nothing changed}, [\,], [\,])\,] \\
X = [\, &\texttt{lean/Fw/Wire.lean}, \texttt{apps/site/src/a.tsx}, \texttt{packages/measure-wktr/src/a.mjs}\,]
\end{aligned}$$

Each case is (name $n$, diff $D$, merged paths $M$). -/
def cases : List (String × List String × List String) := [
  ("docs only", ["docs/team/handoffs/x.md"], []),
  ("lean test file", ["lean/FwTest/Lease.lean"], []),
  ("lean script", ["lean/scripts/check.sh"], []),
  ("a part module outside the fwcore cone", ["lean/Fw/Parts/HeroExit.lean"], []),
  ("a module in the fwcore cone", ["lean/Fw/Wire.lean"], []),
  ("a new module under lean/Fw, not yet imported", ["lean/Fw/New.lean"], []),
  ("the breakgen cone", ["lean/Fw/Site/Breakpoints.lean"], []),
  ("lake manifest", ["lean/lake-manifest.json"], []),
  ("wktr package", ["packages/measure-wktr/src/a.mjs"], []),
  ("site source", ["apps/site/src/a.tsx"], []),
  ("the guard script", [".github/scripts/changed-inputs.mjs"], []),
  ("a merge of main only", ["lean/Fw/Wire.lean", "apps/site/src/a.tsx", "packages/measure-wktr/src/a.mjs"],
    ["lean/Fw/Wire.lean", "apps/site/src/a.tsx", "packages/measure-wktr/src/a.mjs"]),
  ("a merge of main plus one own file", ["lean/Fw/Wire.lean", "packages/measure-wktr/src/a.mjs"], ["lean/Fw/Wire.lean"]),
  ("the workflow file itself", [".github/workflows/wktr.yml"], []),
  ("a wktr fixture page", ["packages/measure-wktr/fixtures/control/index.html"], []),
  ("nothing changed", [], [])]

/-- One replay line: the diff, the merged paths, the sample cones, the started workflows and the workflows whose
static push filter passes the diff.
$$\operatorname{caseLine}(n, D, M) = \{\texttt{kind}: \texttt{case},\ \texttt{name}: n,\ \texttt{diff}: D,\ \texttt{merged}: M,\ \texttt{cones}: \{\texttt{Main}: \mathrm{cone}(\mathrm{Main}),\ \texttt{BreakgenMain}: \mathrm{cone}(\mathrm{BreakgenMain})\},\ \texttt{started}: \operatorname{run}(D, M),\ \texttt{filtered}: \operatorname{filtered}(D)\}$$ -/
def caseLine (c : String × List String × List String) : Json :=
  Json.mkObj [("kind", "case"), ("name", .str c.1), ("diff", strs c.2.1), ("merged", strs c.2.2),
    ("cones", Json.mkObj [("Main", strs (sampleCone "Main")), ("BreakgenMain", strs (sampleCone "BreakgenMain"))]),
    ("started", strs (run c.2.1 c.2.2)), ("filtered", strs (filtered c.2.1))]

/-- One golden `if:` form: a condition and the `if:` it gets. -/
def ifFormLine (o : Option String) : Json :=
  Json.mkObj [("kind", "ifForm"), ("orig", match o with | none => .null | some x => .str x),
    ("emitted", .str (withNotMain o)), ("carries", .bool (carriesNotMain (withNotMain o)))]

/-- One golden `if:` check: a text and whether it carries `notMainPush`. -/
def ifCheckLine (t : String) : Json :=
  Json.mkObj [("kind", "ifCheck"), ("text", .str t), ("carries", .bool (carriesNotMain t))]

/-- The text of the golden file. $$\text{one JSON object per line: the table, the cases, the if forms and checks}$$ -/
def goldenText : String :=
  String.join ((tableLine :: cases.map caseLine ++ ifOrigs.map ifFormLine ++ ifTexts.map ifCheckLine).map
    fun j => j.compress ++ "\n")

/-- Compare (or write) the golden file; returns the number of stale files.
$$\operatorname{runGolden}(\mathit{write}) = 0\ \text{if the file equals goldenText (or was written), else } 1$$ -/
def runGolden (root : System.FilePath) (write : Bool) : IO Nat := do
  let p := root / ".." / "packages" / "contracts" / "golden" / "ci" / "triggers.jsonl"
  if write then
    IO.FS.createDirAll (root / ".." / "packages" / "contracts" / "golden" / "ci")
    IO.FS.writeFile p goldenText
    IO.println s!"ci trigger golden: written {cases.length} cases"
    return 0
  let cur ← try IO.FS.readFile p catch _ => pure ""
  if cur != goldenText then
    IO.println s!"ci trigger golden: {p} is stale (regenerate: cd lean && lake test -- --write-ci-trigger-golden)"
    return 1
  IO.println s!"ci trigger golden: {cases.length} cases ok"
  return 0

end Fw.Ci.Trigger
