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

/-- Branches of a `ci/*` lane that also runs on `main`. $$B = \{\texttt{ci/**},\ \texttt{main}\}$$ -/
def ciMain : List String := ["ci/**", "main"]

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
$$S_{\mathrm{cone}}(g) = \text{the entry of } g \text{ in } \mathrm{sets}\ \text{(or the cone of } g)$$ -/
def setMap (cone : String → List String) (g : String) : List String :=
  match sets.lookup g with
  | some xs => xs.flatMap fun h => if h.startsWith "@cone:" then cone (h.drop 6).toString else [h]
  | none => [g]

/-- The workflow table: the single place where a push trigger is decided.
$$W = [\,(\mathit{file}, B, G)\,]$$ with `lean/**` replaced by the binary's own inputs where the workflow only builds
`fwcore` or `breakgen`; `lean.yml` and the lean checks keep `lean/**`. -/
def table : List Wf := [
  ⟨"breakpoint-gate.yml", ciMain, [
    "packages/gate-breakpoints/**", "apps/site/**", "@fwcore", "@breakgen", "snapshot/**", "snapshot.lock.json",
    "package.json", "pnpm-lock.yaml", "pnpm-workspace.yaml", ".github/scripts/gate-shards.mjs",
    ".github/scripts/gate-jobs.mjs", ".github/scripts/cache-key.mjs", "packages/contracts/golden/gate/schedule.jsonl",
    "packages/contracts/golden/gate/shards.jsonl",
    "packages/contracts/golden/ops/cache.jsonl", ".github/scripts/gate-smoke.mjs", ".github/scripts/merge-gate.mjs",
    ".github/scripts/verify-snapshot.mjs", ".github/scripts/changed-inputs.mjs", ".github/actions/setup-lean/**",
    ".github/actions/setup-pnpm/**", ".github/actions/gate-engine/**", own "breakpoint-gate.yml"]⟩,
  ⟨"chromium-counts.yml", ciMain, [
    "packages/measure-chromium/**", "apps/site/**", "@fwcore", "@breakgen", "snapshot/**", "snapshot.lock.json",
    "package.json", "pnpm-lock.yaml", "pnpm-workspace.yaml", ".github/scripts/verify-snapshot.mjs",
    ".github/scripts/runner-info.sh", ".github/scripts/changed-inputs.mjs", ".github/actions/setup-lean/**",
    ".github/actions/setup-pnpm/**", own "chromium-counts.yml"]⟩,
  ⟨"difftest.yml", ciMain, [
    "packages/difftest/**", "packages/measure-webkit/src/**", "packages/measure-chromium/src/**",
    "apps/runner/hooks/cap.mjs", "apps/console-api/src/cap/**", "@fwcore", "pnpm-lock.yaml",
    ".github/scripts/changed-inputs.mjs", ".github/actions/setup-lean/**", ".github/actions/setup-pnpm/**",
    own "difftest.yml"]⟩,
  ⟨"engine-premises.yml", ["ci/**"], [
    "packages/measure-chromium/**", "packages/measure-wktr/**", "packages/contracts/golden/ops/engine-premises.jsonl",
    ".github/scripts/runner-info.sh", ".github/scripts/changed-inputs.mjs", own "engine-premises.yml"]⟩,
  ⟨"gate-gaps.yml", ciMain, [
    "packages/gate-breakpoints/**", "apps/site/**", "@fwcore", "@breakgen", "snapshot/**", "snapshot.lock.json",
    "package.json", "pnpm-lock.yaml", "pnpm-workspace.yaml", ".github/scripts/verify-snapshot.mjs",
    ".github/scripts/check-simulator.sh", ".github/scripts/changed-inputs.mjs", ".github/actions/setup-lean/**",
    ".github/actions/setup-pnpm/**", own "gate-gaps.yml"]⟩,
  ⟨"lean.yml", ciMain, [
    "lean/**", "apps/site/src/breakpoints.gen.json", ".github/scripts/changed-inputs.mjs",
    ".github/actions/setup-lean/**", ".github/scripts/runner-info.sh", own "lean.yml"]⟩,
  ⟨"mutants.yml", ciMain, [
    "lean/Fw/Console.lean", "lean/Fw/Serve.lean", "lean/Fw/Ops/Meter.lean", "lean/Fw/Ops/PathCheck.lean",
    "lean/Fw/Ops/SpawnGuard.lean", "lean/Fw/Ops/Usage.lean", "lean/Fw/Ops/Wire.lean", "lean/Fw/Spec/DeviceQueue.lean",
    "lean/Fw/Wire.lean", "lean/FwTest/Mutants/**", "lean/scripts/mutants.sh", ".github/scripts/changed-inputs.mjs",
    ".github/actions/setup-lean/**", own "mutants.yml"]⟩,
  ⟨"premise-tests.yml", ciMain, [
    "packages/premise-tests/**", "packages/contracts/golden/ops/premise.jsonl", "lean/Fw/Ops/Premise.lean",
    "apps/runner/src/premises.ts", "package.json", "pnpm-lock.yaml", "pnpm-workspace.yaml",
    ".github/scripts/changed-inputs.mjs", ".github/actions/setup-pnpm/**", ".github/actions/gate-engine/**",
    own "premise-tests.yml"]⟩,
  ⟨"sim-speed.yml", ["ci/sim-speed"], [
    "packages/measure-webkit/**", ".github/scripts/sim-speed-*", ".github/scripts/check-simulator.sh",
    ".github/scripts/runner-info.sh", ".github/scripts/changed-inputs.mjs", own "sim-speed.yml"]⟩,
  ⟨"snapshot-extract.yml", ciMain, [
    "packages/snapshot-extract/**", "packages/gate-breakpoints/**", "apps/site/**", "snapshot/**", "snapshot.lock.json",
    "package.json", "pnpm-lock.yaml", "pnpm-workspace.yaml", ".github/scripts/verify-snapshot.mjs",
    ".github/scripts/changed-inputs.mjs", ".github/actions/setup-lean/**", ".github/actions/setup-pnpm/**",
    ".github/actions/gate-engine/**", own "snapshot-extract.yml"]⟩,
  ⟨"visual-diff.yml", ciMain, [
    "packages/visual-diff/**", "packages/gate-breakpoints/src/**", "packages/gate-breakpoints/package.json",
    "packages/contracts/golden/gate/**", "apps/site/**", "@breakgen", "snapshot/**", "snapshot.lock.json", "package.json",
    "pnpm-lock.yaml", "pnpm-workspace.yaml", ".github/scripts/verify-snapshot.mjs", ".github/scripts/changed-inputs.mjs",
    ".github/actions/setup-lean/**", ".github/actions/setup-pnpm/**", ".github/actions/gate-engine/**",
    own "visual-diff.yml"]⟩,
  ⟨"webkit-sim.yml", ciMain, [
    "packages/measure-webkit/**", "snapshot/**", "snapshot.lock.json", ".github/scripts/check-simulator.sh",
    ".github/scripts/verify-snapshot.mjs", ".github/scripts/runner-info.sh", ".github/scripts/changed-inputs.mjs",
    own "webkit-sim.yml"]⟩,
  ⟨"wktr-fixtures.yml", ["ci/**"], [
    "packages/measure-wktr/**", "packages/measure-chromium/src/classify.mjs", "packages/measure-chromium/src/fwcore.mjs",
    "@fwcore", "packages/contracts/golden/measure/wktr.fixtures.jsonl", ".github/scripts/runner-info.sh",
    ".github/scripts/changed-inputs.mjs", ".github/actions/setup-lean/**", own "wktr-fixtures.yml"]⟩,
  ⟨"wktr.yml", ["ci/**"], [
    "packages/measure-wktr/**", "packages/measure-chromium/src/classify.mjs", "packages/measure-chromium/src/fwcore.mjs",
    "@fwcore", "snapshot/**", "snapshot.lock.json", ".github/scripts/verify-snapshot.mjs", ".github/scripts/runner-info.sh",
    ".github/scripts/changed-inputs.mjs", ".github/actions/setup-lean/**", own "wktr.yml"]⟩]

#guard (table.map (·.file)).eraseDups.length == table.length

/-- A small stand-in for the cones, for the replay cases (the real cones come from the checkout).
$$\mathrm{cone}(\mathrm{Main}) = [\texttt{lean/Fw/Wire.lean},\ \texttt{lean/Fw/Ops/Wire.lean}]$$ -/
def sampleCone : String → List String
  | "Main" => ["lean/Fw/Wire.lean", "lean/Fw/Ops/Wire.lean"]
  | "BreakgenMain" => ["lean/Fw/Site/Breakpoints.lean"]
  | _ => []

/-- Files started by a push (names only) under the sample cones.
$$\operatorname{run}(D, M) = \operatorname{started}(W, S_{\mathrm{sample}}, D, \lambda x.\ x \notin M)$$ -/
def run (diff merged : List String) : List String :=
  startedBy (setMap sampleCone) table diff (fun x => !merged.contains x)

-- a Lean test file, a script and a golden change do not start the lanes that only build the binary
#guard run ["lean/FwTest/Lease.lean"] [] == ["lean.yml"]
#guard run ["lean/Fw/Wire.lean"] [] == ["breakpoint-gate.yml", "chromium-counts.yml", "difftest.yml", "gate-gaps.yml", "lean.yml", "mutants.yml", "wktr-fixtures.yml", "wktr.yml"]
#guard run ["lean/Fw/Parts/HeroExit.lean"] [] == ["lean.yml"]
-- the site builder (breakgen) cone starts the lanes that build the site; a pixel golden starts the visual diff only
#guard run ["lean/Fw/Site/Breakpoints.lean"] [] == ["breakpoint-gate.yml", "chromium-counts.yml", "gate-gaps.yml", "lean.yml", "visual-diff.yml"]
#guard run ["packages/contracts/golden/gate/pixel.jsonl"] [] == ["visual-diff.yml"]
#guard run ["docs/team/handoffs/x.md"] [] == []
-- a merge of main changes lean/ and apps/site but starts nothing
#guard run ["lean/Fw/Wire.lean", "apps/site/src/a.ts"] ["lean/Fw/Wire.lean", "apps/site/src/a.ts"] == []
#guard run ["packages/measure-wktr/src/a.mjs", "lean/Fw/Wire.lean"] ["lean/Fw/Wire.lean"] == ["engine-premises.yml", "wktr-fixtures.yml", "wktr.yml"]
-- a fixture page starts both wktr lanes; the fixture workflow file starts only itself
#guard run ["packages/measure-wktr/fixtures/control/index.html"] [] == ["engine-premises.yml", "wktr-fixtures.yml", "wktr.yml"]
#guard run [".github/workflows/wktr-fixtures.yml"] [] == ["wktr-fixtures.yml"]

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
#guard filtered ["lean/Fw/New.lean"] == ["breakpoint-gate.yml", "chromium-counts.yml", "difftest.yml", "gate-gaps.yml", "lean.yml", "visual-diff.yml", "wktr-fixtures.yml", "wktr.yml"]
#guard run ["lean/Fw/New.lean"] [] == ["lean.yml"]
-- a test module is outside every coarse fwcore glob
#guard filtered ["lean/FwTest/Lease.lean"] == ["lean.yml"]
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
      ("inputs", strs w.inputs)]).toArray),
    ("sets", Json.mkObj (sets.map fun (n, xs) => (n, strs xs))), ("coneGlobs", strs coneGlobs)]

/-- The replay cases: a push (its diff, the paths that already equal `main`); the workflows it starts under the
sample cones are added by `caseLine`.
$$\mathrm{cases} = [\, (n, D, M) \,]$$ -/
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

/-- The text of the golden file. $$\text{one JSON object per line: the table, then the cases}$$ -/
def goldenText : String := String.join ((tableLine :: cases.map caseLine).map fun j => j.compress ++ "\n")

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
