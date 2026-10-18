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
(`--check`, wired into the land checks of `apps/runner`).
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
#guard run ["packages/measure-wktr/src/a.mjs", "lean/Fw/Wire.lean"] ["lean/Fw/Wire.lean"] == ["wktr-fixtures.yml", "wktr.yml"]
-- a fixture page starts both wktr lanes; the fixture workflow file starts only itself
#guard run ["packages/measure-wktr/fixtures/control/index.html"] [] == ["wktr-fixtures.yml", "wktr.yml"]
#guard run [".github/workflows/wktr-fixtures.yml"] [] == ["wktr-fixtures.yml"]

/-! ## Golden (`packages/contracts/golden/ci/triggers.jsonl`) -/

/-- A JSON array of strings. $$\operatorname{strs}(xs) = [\, \mathrm{str}(x) : x \in xs \,]$$ -/
def strs (xs : List String) : Json := .arr (xs.map Json.str).toArray

/-- The table line: workflows with branches and symbolic inputs, and the named sets.
$$\operatorname{tableLine} = \{\texttt{kind}: \texttt{table},\ \texttt{workflows}: W,\ \texttt{sets}: \mathrm{sets}\}$$ -/
def tableLine : Json :=
  Json.mkObj [("kind", "table"),
    ("workflows", .arr (table.map fun w => Json.mkObj [("file", .str w.file), ("branches", strs w.branches),
      ("inputs", strs w.inputs)]).toArray),
    ("sets", Json.mkObj (sets.map fun (n, xs) => (n, strs xs)))]

/-- The replay cases: a push (its diff, the paths that already equal `main`); the workflows it starts under the
sample cones are added by `caseLine`.
$$\mathrm{cases} = [\, (n, D, M) \,]$$ -/
def cases : List (String × List String × List String) := [
  ("docs only", ["docs/team/handoffs/x.md"], []),
  ("lean test file", ["lean/FwTest/Lease.lean"], []),
  ("lean script", ["lean/scripts/check.sh"], []),
  ("a part module outside the fwcore cone", ["lean/Fw/Parts/HeroExit.lean"], []),
  ("a module in the fwcore cone", ["lean/Fw/Wire.lean"], []),
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

/-- One replay line: the diff, the merged paths, the sample cones and the started workflows.
$$\operatorname{caseLine}(n, D, M) = \{n, D, M, \operatorname{run}(D, M)\}$$ -/
def caseLine (c : String × List String × List String) : Json :=
  Json.mkObj [("kind", "case"), ("name", .str c.1), ("diff", strs c.2.1), ("merged", strs c.2.2),
    ("cones", Json.mkObj [("Main", strs (sampleCone "Main")), ("BreakgenMain", strs (sampleCone "BreakgenMain"))]),
    ("started", strs (run c.2.1 c.2.2))]

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
