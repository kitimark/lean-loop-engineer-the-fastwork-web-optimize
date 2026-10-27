import Lean.Data.Json
import Fw.Console.LandSpeed
import Fw.Ops.PathCheck
import Fw.Ops.GateEngineTiming
import Fw.Gate.Trajectory
import Fw.Gate.Trajectory.Dispatch
import Fw.Ci.AttemptGolden
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

/-- A workflow's push trigger: its file, the branches it watches and its declared input globs. -/
structure Wf where
  file : String
  branches : List String
  inputs : List String
  crons : List String
deriving Repr, DecidableEq

/-- Replace every `@set` glob by the set's contents (an unknown set stays as it is, matching no path). -/
def expand (S : String → List String) (gs : List String) : List String :=
  gs.flatMap fun g => if g.startsWith "@" then S g else [g]

/-- The push's own change: the files of its diff whose new content differs from `main`'s.
`differs x` says the new content of `x` is not `main`'s. -/
def effective (diff : List String) (differs : String → Bool) : List String := diff.filter differs

/-- Does the push start the workflow? Some effective change is in the scope of its expanded inputs. -/
def Wf.starts (S : String → List String) (w : Wf) (eff : List String) : Bool :=
  selected (expand S w.inputs) eff

/-- The workflows a push starts, in table order. -/
def startedBy (S : String → List String) (ws : List Wf) (diff : List String) (differs : String → Bool) : List String :=
  (ws.filter fun w => w.starts S (effective diff differs)).map (·.file)

/-- The effective change is part of the diff. -/
theorem effective_sub (diff : List String) (differs : String → Bool) (x : String) (h : x ∈ effective diff differs) :
    x ∈ diff := (List.mem_filter.mp h).1

/-- **Starts iff an input changed.** A workflow starts exactly when a path of the diff that differs from `main` is in
the scope of its expanded inputs. -/
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
scope of any workflow's expanded inputs, the push starts no workflow. -/
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
list iff some workflow of that file has an effective change in its inputs. -/
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
merges `main`), no workflow starts, whatever the inputs. -/
theorem merge_starts_nothing (S : String → List String) (ws : List Wf) (diff : List String) (differs : String → Bool)
    (h : ∀ x ∈ diff, differs x = false) : startedBy S ws diff differs = [] :=
  none_started S ws diff differs fun _ _ x hx hd => by rw [h x hx] at hd; exact Bool.noConfusion hd

/-- **The coarse GitHub filter never drops a needed start.** GitHub's `on.push.paths` filter runs on the whole diff
`before..after`; if the workflow starts (an effective input changed) the filter passes, so the generated `paths` list
together with the guard decides exactly `starts`. -/
theorem filter_passes (S : String → List String) (w : Wf) (diff : List String) (differs : String → Bool)
    (h : w.starts S (effective diff differs) = true) : selected (expand S w.inputs) diff = true := by
  obtain ⟨x, hx, _, hi⟩ := (starts_iff S w diff differs).mp h
  exact selected_of_mem _ _ x hx hi

/-- **A skipped run replays.** If the workflow's result depends only on its expanded inputs and the push does not start
it, its result on the new state equals its result on any state that agrees with it outside the effective change (the
state the branch was last verified in, with `main`'s content). -/
theorem skipped_replays {R} (S : String → List String) (w : Wf) (eff : List String) (run : St → R)
    (hrw : ReadsWithin run (expand S w.inputs)) (hs : w.starts S eff = false) (σ σ' : St)
    (hd : ∀ p, p ∉ eff → σ p = σ' p) : run σ = run σ' :=
  skip_sound run (expand S w.inputs) eff hrw hs σ σ' hd

/-! ## The table -/

/-- The path of a workflow file. -/
def own (f : String) : String := s!".github/workflows/{f}"

/-- Branches of a `ci/*` lane that also runs on `main`. -/
def ciMain : List String := ["ci/**", "main"]

/-- Branches of a `ci/*` lane that does not run on `main`. -/
def ciAll : List String := ["ci/**"]

/-- The files `lake build fwcore` reads besides the import cone of `Main`: the build files. `@fwcore.cone` is the cone. -/
def fwcoreFiles : List String :=
  ["lean/Main.lean", "lean/lakefile.toml", "lean/lake-manifest.json", "lean/lean-toolchain", "@cone:Main"]

/-- The files `breakgen` (run by the site build) reads: the build files and the import cone of `BreakgenMain`. -/
def breakgenFiles : List String :=
  ["lean/BreakgenMain.lean", "lean/lakefile.toml", "lean/lake-manifest.json", "lean/lean-toolchain", "@cone:BreakgenMain"]

/-- The named sets. `@cone:<Root>` is the transitive `import` (and `include_str`) closure of the root module inside
`lean/`, computed from the checkout by `scripts/ci-paths.mjs`. -/
def sets : List (String × List String) := [("@fwcore", fwcoreFiles), ("@breakgen", breakgenFiles)]

/-- The set map with the given cones (`cone root` is the file list of the import cone of `root`).

A plain glob maps to itself; a named set expands its cone markers. -/
def setMap (cone : String → List String) (g : String) : List String :=
  match sets.lookup g with
  | some xs => xs.flatMap fun h => if h.startsWith "@cone:" then cone (h.drop 6).toString else [h]
  | none => [g]

/-- The workflow table: the single place where a push trigger is decided.

Each row is (workflow file, branches, input globs); `lean/**` is replaced by the binary's own inputs where the
workflow only builds `fwcore` or `breakgen`, while `lean.yml` and the lean checks keep `lean/**`. -/
def table (_ : Unit := ()) : List Wf := [
  ⟨"breakpoint-gate.yml", ciAll, [
    "packages/gate-breakpoints/**", "apps/site/**", "@fwcore", "@breakgen", "snapshot/**", "snapshot.lock.json",
    "package.json", "pnpm-lock.yaml", "pnpm-workspace.yaml", ".github/scripts/gate-shards.mjs",
    ".github/scripts/gate-jobs.mjs", ".github/scripts/gate-jobs.test.mjs", ".github/scripts/cache-key.mjs", "packages/contracts/golden/gate/schedule.jsonl",
    "packages/contracts/golden/gate/shards.jsonl", "packages/contracts/golden/gate/exit.jsonl", "packages/contracts/golden/gate/flag-delta.jsonl", "packages/contracts/golden/gate/replaced.jsonl",
    "packages/contracts/golden/gate/search.jsonl", ".github/scripts/gate-search.mjs", ".github/scripts/gate-search.test.mjs",
    "packages/contracts/golden/ops/cache.jsonl", ".github/scripts/gate-smoke.mjs", ".github/scripts/merge-gate.mjs",
    ".github/scripts/verify-snapshot.mjs", ".github/scripts/changed-inputs.mjs", ".github/actions/setup-lean/**",
    ".node-version", ".github/actions/setup-pnpm/**", ".github/actions/gate-engine/**", ".github/actions/telemetry/**", "scripts/ci-telemetry/**", own "breakpoint-gate.yml"], []⟩,
  ⟨"chrome-crash-probe.yml", ciAll, [
    "packages/measure-chromium/src/**", "packages/measure-chromium/probes/**", "packages/measure-chromium/docker/driver/**",
    "snapshot/**", "snapshot.lock.json", ".github/scripts/verify-snapshot.mjs", ".github/scripts/changed-inputs.mjs", ".node-version",
    own "chrome-crash-probe.yml"], []⟩,
  ⟨"chromium-counts.yml", ciAll, [
    "packages/measure-chromium/**", "apps/site/**", "@fwcore", "@breakgen", "snapshot/**", "snapshot.lock.json",
    "package.json", "pnpm-lock.yaml", "pnpm-workspace.yaml", ".github/scripts/verify-snapshot.mjs",
    ".github/scripts/runner-info.sh", ".github/scripts/changed-inputs.mjs", ".github/actions/setup-lean/**",
    ".node-version", ".github/actions/setup-pnpm/**", ".github/actions/telemetry/**", "scripts/ci-telemetry/**", own "chromium-counts.yml"], []⟩,
  ⟨"device-replay.yml", ["ci/device-replay"], [
    "packages/measure-webkit/src/replay/**", "packages/measure-webkit/src/device-replay*.mjs", "packages/measure-webkit/src/device-record.mjs",
    "packages/measure-webkit/src/device-session.mjs", "packages/measure-webkit/src/linux/serve.mjs", "packages/measure-webkit/src/linux/run.mjs",
    "packages/measure-webkit/test/replay-*.test.mjs", "packages/contracts/golden/device/**", "packages/measure-chromium/profiles/user-fixture.json",
    "packages/measure-chromium/src/profile.mjs", "packages/measure-chromium/profiles/user-bug-1025*.json", "packages/gate-breakpoints/package.json",
    "packages/contracts/src/flag-key.mjs", "apps/site/**", "snapshot/**", "snapshot.lock.json",
    "package.json", "pnpm-lock.yaml", "pnpm-workspace.yaml", ".github/scripts/verify-snapshot.mjs", ".github/scripts/changed-inputs.mjs",
    ".node-version", ".github/actions/setup-pnpm/**", ".github/actions/telemetry/**", "scripts/ci-telemetry/**", own "device-replay.yml"], []⟩,
  ⟨"difftest.yml", ciAll, [
    "packages/difftest/**", "packages/measure-webkit/src/**", "packages/measure-chromium/src/**",
    "apps/runner/hooks/cap.mjs", "apps/console-api/src/cap/**", "@fwcore", "pnpm-lock.yaml",
    ".github/scripts/changed-inputs.mjs", ".github/actions/setup-lean/**", ".node-version", ".github/actions/setup-pnpm/**",
    "scripts/slot-self.mjs", own "difftest.yml"], []⟩,
  ⟨"engine-premises.yml", ciAll, [
    "packages/measure-chromium/**", "packages/measure-wktr/**", "packages/contracts/golden/ops/engine-premises.jsonl",
    ".github/scripts/runner-info.sh", ".github/scripts/changed-inputs.mjs", ".node-version", own "engine-premises.yml"], []⟩,
  ⟨"font-fidelity.yml", ciAll, [
    "packages/measure-chromium/src/**", "packages/measure-chromium/Dockerfile", "packages/measure-chromium/docker/**",
    "packages/measure-webkit/src/**", "packages/measure-webkit/fixtures/**", "packages/contracts/golden/measure/**", "packages/contracts/golden/port/**", "scripts/port/**",
    "snapshot/**", "snapshot.lock.json", ".github/scripts/verify-snapshot.mjs", ".github/scripts/check-simulator.sh",
    ".github/scripts/changed-inputs.mjs", ".node-version", own "font-fidelity.yml"], []⟩,
  ⟨"gate-gaps.yml", ciAll, [
    "packages/gate-breakpoints/**", "apps/site/**", "@fwcore", "@breakgen", "snapshot/**", "snapshot.lock.json",
    "package.json", "pnpm-lock.yaml", "pnpm-workspace.yaml", ".github/scripts/verify-snapshot.mjs",
    ".github/scripts/check-simulator.sh", ".github/scripts/changed-inputs.mjs", ".github/actions/setup-lean/**",
    ".node-version", ".github/actions/setup-pnpm/**", own "gate-gaps.yml"], []⟩,
  ⟨"land.yml", ["ci/land-*"], [
    "apps/**", "packages/**", "lean/**", "scripts/**", "package.json", "pnpm-lock.yaml", "pnpm-workspace.yaml",
    "docs/team/work-graph.json", "docs/team/incidents/ledger.json", "research/findings/ledger.json",
    "results/baselines/chromium/**", ".github/scripts/changed-inputs.mjs", ".github/actions/setup-lean/**",
    ".node-version", ".github/actions/setup-pnpm/**", ".github/actions/gate-engine/**", ".github/scripts/cache-key.mjs", ".github/scripts/land-base.sh", own "land.yml"], []⟩,
  ⟨"lean-math.yml", ciAll, [
    "lean-math/**", "lean/Fw/Parts/Bezier.lean", "lean/lakefile.toml", "lean/lean-toolchain",
    ".github/scripts/changed-inputs.mjs", ".node-version", own "lean-math.yml"], []⟩,
  ⟨"lean.yml", ciMain, [
    "lean/**", "apps/site/src/breakpoints.gen.json", "apps/site/src/sweeps.gen.json", "apps/site/src/head.gen.json", "scripts/span.sh",
    "scripts/fwcore-build.sh", "scripts/lint-check-sh.mjs", "scripts/fwcore-record-rule.sh", "scripts/fwcore-build.test.mjs", "apps/console-api/src/core/build-base.ts", "scripts/lake-slot.sh", "scripts/lake-slot-lib.sh", "scripts/heavy-lock.mjs", "scripts/heavy-lock.test.mjs", "scripts/slot-self.mjs", "scripts/slot-self.test.mjs", "scripts/lake-slot.test.mjs", "packages/contracts/golden/sched/lake-slot.gen.sh", "scripts/gate-engine-ref.test.mjs", ".github/actions/gate-engine/action.yml",
    "packages/contracts/golden/console/land-dry.jsonl", "packages/contracts/golden/gate/sweeps.jsonl", "packages/contracts/golden/gate/exit.jsonl", "packages/contracts/golden/gate/flag-delta.jsonl", "packages/contracts/golden/gate/replaced.jsonl", "packages/contracts/golden/gate/webkit-screen.jsonl", "packages/contracts/golden/gate/path-pix.jsonl", "packages/contracts/golden/device/session.jsonl", "packages/contracts/golden/device/replay.jsonl", "packages/contracts/golden/measure/webkit-lag.jsonl", "packages/contracts/golden/measure/wkcost.jsonl", "packages/contracts/golden/measure/wkcost-sums.jsonl", "packages/contracts/golden/measure/touch-push.jsonl", "packages/contracts/golden/measure/push-cycle.jsonl", "packages/contracts/golden/measure/touch-lock.jsonl", "packages/contracts/golden/measure/walk-budget.jsonl", "packages/contracts/golden/measure/census.jsonl", "packages/contracts/golden/measure/webkit-profile.jsonl", "packages/contracts/golden/measure/profile.jsonl", "packages/contracts/golden/gate/search.jsonl", "packages/contracts/golden/device/stillruns.jsonl", "packages/contracts/golden/measure/swipe-end.jsonl", "packages/contracts/golden/device/thermal.jsonl", "packages/contracts/golden/device/sim-touch.jsonl", "packages/contracts/golden/device/morph-end-count.jsonl", "packages/contracts/golden/device/sim-relaunch.jsonl", "packages/contracts/golden/device/phone-arms.jsonl", "packages/contracts/golden/ci/ci-state.jsonl", "packages/contracts/golden/ci/attempt-inflight.jsonl", "packages/contracts/golden/gate/transition-list.jsonl", "packages/contracts/golden/parts/platform-sweep-pause.jsonl", "packages/contracts/golden/device/finishruns.jsonl", "packages/contracts/golden/measure/paint-visible.jsonl", "packages/contracts/golden/device/throttle-parts.jsonl", "packages/contracts/golden/measure/offscreen.jsonl", "packages/contracts/golden/measure/offscreen-webkit.jsonl", "packages/contracts/golden/measure/offscreen-windows.jsonl", "packages/contracts/golden/measure/sim-host.jsonl",
    "packages/contracts/golden/gate/smooth.jsonl", "packages/contracts/golden/gate/trajectory-colour.jsonl", "packages/contracts/golden/gate/trajectory-gpu.jsonl", "packages/contracts/fixtures/trajectory-gpu/**", "packages/gate-breakpoints/src/trajectory/cells-gpu-cli.mjs", "packages/gate-breakpoints/src/trajectory/cells-gpu.mjs", "packages/gate-breakpoints/src/trajectory/registry.mjs", "packages/gate-breakpoints/src/spec.mjs", "packages/gate-breakpoints/src/serve.mjs", "packages/gate-breakpoints/src/scope.gen.json", "packages/contracts/golden/parts/contracts.gen.json",
    "packages/contracts/golden/gate/run-perm.jsonl", "packages/contracts/golden/gate/run-perm-cells.jsonl",
    "packages/contracts/golden/parts/stage.jsonl", "packages/contracts/golden/parts/stage-mode.jsonl",
    "packages/contracts/golden/parts/nav-fixed-counts.jsonl", "packages/contracts/golden/parts/nav-fixed-counts.webkit-passes.json", "packages/contracts/golden/parts/nav-fixed-counts.chromium-bands.json",
    "packages/contracts/golden/parts/dormant-counts.jsonl",
    "apps/site/src/registry/layer-opts.gen.ts", "packages/contracts/golden/console/layer-opts.jsonl",
    "apps/site/src/parts/engine.events/quiet.gen.ts", "packages/contracts/golden/parts/react-root-quiet.jsonl",
    "packages/contracts/golden/parts/hero.exit.scoped.json", "packages/contracts/golden/parts/hero-exit.threaded.jsonl", "packages/contracts/golden/parts/hero-exit-offset.jsonl",
    "packages/measure-chromium/scenarios.gen.json",
    "packages/contracts/golden/parts/morph.mount.dormant.jsonl", "packages/contracts/golden/parts/morph-mount-tap.jsonl",
    "packages/contracts/golden/parts/nav-earn.jsonl", "packages/contracts/golden/parts/nav.earn.webkit.jsonl", "packages/contracts/golden/parts/nav.earn.curve.jsonl", "packages/contracts/golden/parts/hero-scene-pause.jsonl", "packages/contracts/golden/parts/hero-contain.jsonl", "packages/contracts/golden/parts/morph.end.jsonl", "packages/contracts/golden/parts/morph-end-nobounce.jsonl", "packages/contracts/golden/parts/combo-scroll.jsonl", "packages/contracts/golden/parts/platform-glint-pause.jsonl", "packages/contracts/golden/parts/platform-glint-hold.jsonl", "packages/contracts/golden/parts/morph-stage.jsonl", "packages/contracts/golden/parts/platform-entries-fill.jsonl", "packages/contracts/golden/parts/platform-sweep-layer.jsonl", "packages/contracts/golden/parts/platform-faded-pause.jsonl",
    "results/gpu-safari/lane/elapsed.golden.jsonl", "packages/contracts/golden/gate/image-arm.jsonl", "packages/contracts/golden/morph-geom.jsonl", "packages/contracts/golden/morph-geom-timed.jsonl", "packages/contracts/golden/parts/hero.accent.drawone.jsonl", "packages/contracts/golden/parts/hero.accent.nolayout.jsonl", "packages/contracts/golden/parts/footprint.classpos.jsonl", "packages/contracts/golden/parts/people-o-preview.jsonl", "packages/contracts/golden/parts/morph-idle-none.jsonl", "packages/contracts/golden/parts/morph.panel.rest.jsonl", "packages/contracts/golden/parts/const-bounds-counts.jsonl", "results/const-bounds-counts/cells.json", "results/const-bounds-counts/tables.md","packages/contracts/golden/parts/morph.columns.final-scale.jsonl",
    "packages/contracts/golden/ops/rebuild-facts.jsonl",
    "packages/contracts/golden/ops/rebuild.jsonl", "packages/contracts/golden/plan/writes-closure.jsonl",
    ".github/scripts/changed-inputs.mjs", ".github/actions/setup-lean/**", ".github/scripts/runner-info.sh",
    ".github/actions/telemetry/**", "scripts/ci-telemetry/**", own "lean.yml", ".node-version"], []⟩,
  ⟨"linux-webkit-probe.yml", ["ci/linux-webkit-probe"], [
    "packages/measure-webkit/src/linux/**", "packages/measure-webkit/test/linux-*.test.mjs", "packages/gate-breakpoints/package.json",
    "snapshot/**", "snapshot.lock.json", "package.json", "pnpm-lock.yaml", "pnpm-workspace.yaml", ".github/scripts/verify-snapshot.mjs",
    ".github/scripts/changed-inputs.mjs", ".node-version", ".github/actions/setup-pnpm/**", ".github/actions/telemetry/**",
    "scripts/ci-telemetry/**", own "linux-webkit-probe.yml"], []⟩,
  ⟨"mutants.yml", ciAll, [
    "lean/Fw/Console.lean", "lean/Fw/Serve.lean", "lean/Fw/Ops/Meter.lean", "lean/Fw/Ops/PathCheck.lean",
    "lean/Fw/Ops/SpawnGuard.lean", "lean/Fw/Ops/Usage.lean", "lean/Fw/Ops/Wire.lean", "lean/Fw/Spec/DeviceQueue.lean",
    "lean/Fw/Wire.lean", "lean/FwTest/Mutants/**", "lean/scripts/mutants.sh", ".github/scripts/changed-inputs.mjs",
    ".github/actions/setup-lean/**", ".node-version", own "mutants.yml"], []⟩,
  ⟨"path-pix.yml", ciAll, [
    "packages/measure-webkit/**", "packages/measure-chromium/**", "packages/gate-breakpoints/**", "apps/site/**", "@breakgen",
    "package.json", "pnpm-lock.yaml", "pnpm-workspace.yaml", ".github/scripts/check-simulator.sh", ".github/scripts/runner-info.sh",
    ".github/scripts/changed-inputs.mjs", "packages/contracts/golden/gate/path-pix.jsonl", ".github/actions/setup-lean/**",
    ".github/actions/setup-pnpm/**", ".github/actions/telemetry/**", "scripts/ci-telemetry/**", ".node-version", own "path-pix.yml"], []⟩,
  ⟨"premise-tests.yml", ciMain, [
    "packages/premise-tests/**", "packages/contracts/golden/ops/premise.jsonl", "lean/Fw/Ops/Premise.lean",
    "apps/runner/src/premises.ts", "package.json", "pnpm-lock.yaml", "pnpm-workspace.yaml",
    ".github/scripts/changed-inputs.mjs", ".node-version", ".github/actions/setup-pnpm/**", ".github/actions/gate-engine/**",
    ".github/scripts/cache-key.mjs", "packages/contracts/golden/ops/cache.jsonl", ".github/actions/telemetry/**", "scripts/ci-telemetry/**", "scripts/slot-self.mjs", own "premise-tests.yml"], []⟩,
  ⟨"preview-e2e.yml", ciAll, [
    "packages/e2e-preview/**", "apps/console-api/src/**", "apps/console-api/package.json", "@fwcore",
    "packages/contracts/src/**", "packages/contracts/package.json", "packages/contracts/golden/console/**",
    "snapshot/**", "package.json", "pnpm-lock.yaml", "pnpm-workspace.yaml", ".github/scripts/changed-inputs.mjs",
    ".github/actions/setup-lean/**", ".node-version", ".github/actions/setup-pnpm/**", ".github/actions/gate-engine/**",
    own "preview-e2e.yml"], []⟩,
  ⟨"sim-speed.yml", ["ci/sim-speed"], [
    "packages/measure-webkit/**", ".github/scripts/sim-speed-*", ".github/scripts/check-simulator.sh",
    ".github/scripts/runner-info.sh", ".github/scripts/changed-inputs.mjs", ".node-version", own "sim-speed.yml"], []⟩,
  ⟨"smoothness.yml", ciAll, [
    "packages/gate-breakpoints/**", "apps/site/**", "@breakgen", "snapshot/**", "snapshot.lock.json",
    "package.json", "pnpm-lock.yaml", "pnpm-workspace.yaml", ".github/scripts/gate-search.mjs", ".github/scripts/gate-search.test.mjs",
    ".github/scripts/gate-smoke.mjs", ".github/scripts/verify-snapshot.mjs", ".github/scripts/cache-key.mjs",
    ".github/scripts/trajectory-line.mjs", ".github/scripts/trajectory-line.test.mjs", "packages/contracts/golden/ci/triggers.jsonl",
    "packages/contracts/golden/gate/search.jsonl", "packages/contracts/golden/gate/smooth.jsonl", "packages/contracts/golden/ops/cache.jsonl",
    ".github/scripts/changed-inputs.mjs", ".github/actions/setup-lean/**", ".node-version", ".github/actions/setup-pnpm/**",
    ".github/actions/gate-engine/**", ".github/actions/telemetry/**", "scripts/ci-telemetry/**", "packages/measure-webkit/**",
    "packages/measure-chromium/src/profile.mjs", "packages/contracts/golden/measure/webkit-profile.jsonl", ".github/scripts/check-simulator.sh",
    ".github/scripts/runner-info.sh", own "smoothness.yml"], []⟩,
  ⟨"snapshot-extract.yml", ciAll, [
    "packages/snapshot-extract/**", "packages/gate-breakpoints/**", "apps/site/**", "snapshot/**", "snapshot.lock.json",
    "package.json", "pnpm-lock.yaml", "pnpm-workspace.yaml", ".github/scripts/verify-snapshot.mjs",
    ".github/scripts/changed-inputs.mjs", ".github/actions/setup-lean/**", ".node-version", ".github/actions/setup-pnpm/**",
    ".github/actions/gate-engine/**", own "snapshot-extract.yml"], []⟩,
  ⟨"toolbar-throttle.yml", ciAll, [
    "packages/measure-webkit/**", "apps/site/**", "@breakgen", "snapshot/**", "snapshot.lock.json",
    "package.json", "pnpm-lock.yaml", "pnpm-workspace.yaml", ".github/scripts/check-simulator.sh", ".github/scripts/verify-snapshot.mjs",
    ".github/scripts/runner-info.sh", ".github/scripts/changed-inputs.mjs", "packages/contracts/golden/device/stillruns.jsonl", "packages/contracts/golden/device/sim-touch.jsonl", "packages/contracts/golden/device/morph-end-count.jsonl",
    ".github/actions/setup-lean/**", ".github/actions/setup-pnpm/**", ".github/actions/telemetry/**", "scripts/ci-telemetry/**",
    ".node-version", own "toolbar-throttle.yml"], []⟩,
  ⟨"trajectory-probe.yml", ciAll, [
    "packages/gate-breakpoints/**", "apps/site/**", "@breakgen", "snapshot/**", "snapshot.lock.json",
    "package.json", "pnpm-lock.yaml", "pnpm-workspace.yaml", ".github/scripts/gate-search.mjs", ".github/scripts/gate-search.test.mjs",
    ".github/scripts/gate-smoke.mjs", ".github/scripts/verify-snapshot.mjs", ".github/scripts/cache-key.mjs",
    ".github/scripts/trajectory-line.mjs", ".github/scripts/trajectory-line.test.mjs", "packages/contracts/golden/ci/triggers.jsonl",
    "packages/contracts/golden/gate/search.jsonl", "packages/contracts/golden/gate/trajectory.jsonl", "packages/contracts/golden/gate/trajectory-colour.jsonl", "packages/contracts/golden/gate/trajectory-dispatch.jsonl", "packages/contracts/golden/ops/cache.jsonl",
    ".github/scripts/changed-inputs.mjs", ".github/actions/setup-lean/**", ".node-version", ".github/actions/setup-pnpm/**",
    ".github/actions/gate-engine/**", ".github/actions/telemetry/**", "scripts/ci-telemetry/**", own "trajectory-probe.yml"], []⟩,
  ⟨"visual-diff.yml", ciAll, [
    "packages/visual-diff/**", "packages/gate-breakpoints/src/**", "packages/gate-breakpoints/package.json",
    "packages/contracts/golden/gate/**", "packages/contracts/golden/port/**", "scripts/port/**", "apps/site/**",
    "@breakgen", "snapshot/**", "snapshot.lock.json", "package.json",
    "pnpm-lock.yaml", "pnpm-workspace.yaml", ".github/scripts/verify-snapshot.mjs", ".github/scripts/changed-inputs.mjs",
    ".github/actions/setup-lean/**", ".node-version", ".github/actions/setup-pnpm/**", ".github/actions/gate-engine/**",
    "scripts/slot-self.mjs", own "visual-diff.yml"], []⟩,
  ⟨"webkit-sim.yml", ciAll, [
    "packages/measure-webkit/**", "snapshot/**", "snapshot.lock.json", ".github/scripts/check-simulator.sh",
    ".github/scripts/verify-snapshot.mjs", ".github/scripts/runner-info.sh", ".github/scripts/changed-inputs.mjs",
    ".github/actions/telemetry/**", "scripts/ci-telemetry/**", ".node-version", own "webkit-sim.yml"], []⟩,
  ⟨"wktr-fixtures.yml", ciAll, [
    "packages/measure-wktr/**", "packages/measure-chromium/src/classify.mjs", "packages/measure-chromium/src/fwcore.mjs",
    "@fwcore", "packages/contracts/golden/measure/wktr.fixtures.jsonl", ".github/scripts/runner-info.sh",
    ".github/scripts/changed-inputs.mjs", ".github/actions/setup-lean/**", ".node-version", own "wktr-fixtures.yml"], []⟩,
  ⟨"wktr.yml", ciAll, [
    "packages/measure-wktr/**", "packages/measure-chromium/src/classify.mjs", "packages/measure-chromium/src/fwcore.mjs",
    "packages/contracts/golden/parts/morph-mount-toolbar.gate.jsonl", "apps/site/src/parts/morph.mount/logic.ts",
    "apps/site/src/parts/morph.mount/gesture.ts", "apps/site/src/parts/engine.scroll/unthrottle.ts",
    "@fwcore", "snapshot/**", "snapshot.lock.json", ".github/scripts/verify-snapshot.mjs", ".github/scripts/runner-info.sh",
    ".github/scripts/changed-inputs.mjs", ".github/scripts/changed-inputs.test.mjs", ".github/actions/setup-lean/**", ".node-version", own "wktr.yml"], []⟩]

#guard (table.map (·.file)).eraseDups.length == table.length

/-- A small stand-in for the cones, for the replay cases (the real cones come from the checkout). -/
def sampleCone : String → List String
  | "Main" => ["lean/Fw/Wire.lean", "lean/Fw/Ops/Wire.lean"]
  | "BreakgenMain" => ["lean/Fw/Site/Breakpoints.lean"]
  | _ => []

/-- Files started by a push (names only) under the sample cones. -/
def run (diff merged : List String) : List String :=
  startedBy (setMap sampleCone) table diff (fun x => !merged.contains x)

-- a Lean test file, a script and a golden change do not start the lanes that only build the binary
#guard run ["lean/FwTest/Lease.lean"] [] == ["land.yml", "lean.yml"]
#guard run ["lean/Fw/Wire.lean"] [] == ["breakpoint-gate.yml", "chromium-counts.yml", "difftest.yml", "gate-gaps.yml", "land.yml", "lean.yml", "mutants.yml", "preview-e2e.yml", "wktr-fixtures.yml", "wktr.yml"]
#guard run ["lean/Fw/Parts/HeroExit.lean"] [] == ["land.yml", "lean.yml"]
-- the site builder (breakgen) cone starts the lanes that build the site; a pixel golden starts the visual diff only
#guard run ["lean/Fw/Site/Breakpoints.lean"] [] == ["breakpoint-gate.yml", "chromium-counts.yml", "gate-gaps.yml", "land.yml", "lean.yml", "path-pix.yml", "smoothness.yml", "toolbar-throttle.yml", "trajectory-probe.yml", "visual-diff.yml"]
#guard run ["packages/contracts/golden/gate/pixel.jsonl"] [] == ["land.yml", "visual-diff.yml"]
#guard run ["docs/team/handoffs/x.md"] [] == []
#guard run [".node-version"] [] == ["breakpoint-gate.yml", "chrome-crash-probe.yml", "chromium-counts.yml", "device-replay.yml", "difftest.yml", "engine-premises.yml", "font-fidelity.yml", "gate-gaps.yml", "land.yml", "lean-math.yml", "lean.yml", "linux-webkit-probe.yml", "mutants.yml", "path-pix.yml", "premise-tests.yml", "preview-e2e.yml", "sim-speed.yml", "smoothness.yml", "snapshot-extract.yml", "toolbar-throttle.yml", "trajectory-probe.yml", "visual-diff.yml", "webkit-sim.yml", "wktr-fixtures.yml", "wktr.yml"]
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
  ("land.yml", "land", "gate-apt"), ("land.yml", "land", "ms-playwright"), ("land.yml", "land", "hs-zip"), ("lean-math.yml", "math", "mathlib"),
  ("lean.yml", "lean", ".lake-cache"), ("premise-tests.yml", "engine", "gate-apt"),
  ("premise-tests.yml", "engine", "ms-playwright"), ("premise-tests.yml", "engine", "hs-zip"),
  ("preview-e2e.yml", "engine", "gate-apt"), ("preview-e2e.yml", "engine", "ms-playwright"),
  ("preview-e2e.yml", "engine", "hs-zip"),
  ("smoothness.yml", "cadence", "gate-apt"), ("smoothness.yml", "cadence", "ms-playwright"),
  ("smoothness.yml", "cadence", "hs-zip"), ("snapshot-extract.yml", "extract", "gate-apt"), ("snapshot-extract.yml", "extract", "ms-playwright"),
  ("snapshot-extract.yml", "extract", "hs-zip"), ("trajectory-probe.yml", "frames", "gate-apt"),
  ("trajectory-probe.yml", "frames", "ms-playwright"), ("trajectory-probe.yml", "frames", "hs-zip"),
  ("trajectory-probe.yml", "probe", "gate-apt"),
  ("trajectory-probe.yml", "probe", "ms-playwright"), ("trajectory-probe.yml", "probe", "hs-zip"),
  ("visual-diff.yml", "navscroll", "gate-apt"),
  ("visual-diff.yml", "navscroll", "ms-playwright"), ("visual-diff.yml", "navscroll", "hs-zip"),
  ("visual-diff.yml", "people-layout", "gate-apt"),
  ("visual-diff.yml", "people-layout", "ms-playwright"), ("visual-diff.yml", "people-layout", "hs-zip"),
  ("visual-diff.yml", "port-fonts", "gate-apt"),
  ("visual-diff.yml", "port-fonts", "ms-playwright"), ("visual-diff.yml", "port-fonts", "hs-zip"),
  ("visual-diff.yml", "shoot", "gate-apt"), ("visual-diff.yml", "shoot", "ms-playwright"),
  ("visual-diff.yml", "shoot", "hs-zip"),
  ("webkit-sim.yml", "sim", "iwdp"), ("wktr-fixtures.yml", "fixtures", "wktr-zip"), ("wktr.yml", "wktr", "wktr-zip")]

/-- The workflows whose push trigger listed `main` before task `ci-main-triggers` (commit 473b49c1). -/
def mainBefore : List String := ["breakpoint-gate.yml", "chromium-counts.yml", "difftest.yml", "gate-gaps.yml",
  "lean.yml", "mutants.yml", "premise-tests.yml", "snapshot-extract.yml", "visual-diff.yml", "webkit-sim.yml"]

/-- The caches job `j` of workflow `f` saves. -/
def savedBy (f j : String) : List String := (cacheWriters.filter fun w => w.1 == f && w.2.1 == j).map (·.2.2)

/-- The caches written by macOS jobs only, which a `main` push never runs (task `macos-teardown-trim`). -/
def macosCaches : List String := ["iwdp"]

/-- The caches a `main` push seeds: every cache that a job of a `mainBefore` workflow saved, except `macosCaches`. -/
def seededCaches : List String :=
  ((cacheWriters.filter fun w => mainBefore.contains w.1 && !macosCaches.contains w.2.2).map (·.2.2)).eraseDups

/-- The (workflow, job) pairs a `main` push runs besides the workflow's `guard`: they save the caches main seeded
before this task (`mainBefore`); `wktr-zip` is excluded. -/
def seeders : List (String × String) := [("lean.yml", "lean"), ("premise-tests.yml", "engine")]

def gateCaches : List String := ["gate-apt", "ms-playwright", "hs-zip"]

def savesOn (ref : String) (w : String × String × String) : Bool :=
  !gateCaches.contains w.2.2 || Fw.Ops.GateEngineTiming.shouldSave ref

def readableFrom (saved reader : String) : Bool := saved == "main" || saved == reader

theorem land_saves_no_gate (rest : String) :
    ∀ w ∈ cacheWriters, w.1 = "land.yml" → gateCaches.contains w.2.2 = true →
      savesOn ("ci/land-" ++ rest) w = false := by
  intro w _ _ hg
  have hm : w.2.2 ∈ gateCaches := List.contains_iff_mem.mp hg
  simp [savesOn, hm, Fw.Ops.GateEngineTiming.land_prefix_no_save]

theorem land_writers_gate :
    (cacheWriters.filter (·.1 == "land.yml")).map (·.2.2) = gateCaches := by decide

theorem gate_saves_main : ∀ w ∈ cacheWriters, savesOn "main" w = true := by decide

theorem branch_entry_unread (saved reader : String) (hm : saved ≠ "main") (hr : reader ≠ saved) :
    readableFrom saved reader = false := by
  simp [readableFrom, hm, Ne.symm hr]

def branchOnlyWriters : List (String × String × String) :=
  cacheWriters.filter fun w => gateCaches.contains w.2.2 && w.1 != "land.yml" && !seeders.contains (w.1, w.2.1)

theorem branchOnly_files : (branchOnlyWriters.map (·.1)).eraseDups =
    ["breakpoint-gate.yml", "preview-e2e.yml", "smoothness.yml", "snapshot-extract.yml", "trajectory-probe.yml",
     "visual-diff.yml"] := by decide

theorem branchOnly_unseeded : ∀ w ∈ branchOnlyWriters, (w.1, w.2.1) ∉ seeders := by decide

def entryMB : String → Nat
  | "gate-apt-webkit" => 108 | "ms-playwright" => 96 | "gate-apt-chromium" => 27 | "hs-zip" => 125 | _ => 0

theorem entry_legs :
    entryMB "gate-apt-webkit" + entryMB "ms-playwright" = 204 ∧
    entryMB "gate-apt-chromium" + entryMB "hs-zip" = 152 ∧
    204 + 152 = 356 := by decide

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

/-- The caches no `main` push seeds: their writers never ran on `main`. -/
theorem unseeded_caches :
    (cacheWriters.map (·.2.2)).eraseDups.filter (fun c => !seededCaches.contains c) = ["wktr-zip", "mathlib", "iwdp"] := by decide

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

theorem ci_triggers : table.map (fun w => (w.file, ciPart w.branches)) = [
    ("breakpoint-gate.yml", ["ci/**"]), ("chrome-crash-probe.yml", ["ci/**"]), ("chromium-counts.yml", ["ci/**"]), ("device-replay.yml", ["ci/device-replay"]), ("difftest.yml", ["ci/**"]),
    ("engine-premises.yml", ["ci/**"]), ("font-fidelity.yml", ["ci/**"]), ("gate-gaps.yml", ["ci/**"]), ("land.yml", ["ci/land-*"]), ("lean-math.yml", ["ci/**"]),
    ("lean.yml", ["ci/**"]), ("linux-webkit-probe.yml", ["ci/linux-webkit-probe"]), ("mutants.yml", ["ci/**"]), ("path-pix.yml", ["ci/**"]), ("premise-tests.yml", ["ci/**"]), ("preview-e2e.yml", ["ci/**"]), ("sim-speed.yml", ["ci/sim-speed"]),
    ("smoothness.yml", ["ci/**"]), ("snapshot-extract.yml", ["ci/**"]), ("toolbar-throttle.yml", ["ci/**"]), ("trajectory-probe.yml", ["ci/**"]), ("visual-diff.yml", ["ci/**"]), ("webkit-sim.yml", ["ci/**"]),
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

/-- The fixed globs that stand in for every import cone in `on.push.paths`. -/
def coneGlobs : List String := ["lean/Fw/**", "lean/*.lean"]

/-- A path is literal: none of its segments holds a `*`. -/
def Literal (f : String) : Prop := ∀ s ∈ segs f, '*' ∉ s.toList

/-- The cones stay inside the coarse globs: every file of every cone is literal and in the scope of `coneGlobs`. -/
def ConeWithin (cone : String → List String) : Prop :=
  ∀ r, ∀ f ∈ cone r, Literal f ∧ inScope (parseScope coneGlobs) f = true

/-- The workflow's generated `on.push.paths`: its inputs with every cone replaced by `coneGlobs`. It takes no cone, so no
change of the import graph can change it. -/
def pushPaths (w : Wf) : List String := expand (setMap fun _ => coneGlobs) w.inputs

/-- Add one file to the cone of one root (a new module that the root now imports). -/
def addModule (cone : String → List String) (root f : String) : String → List String :=
  fun r => if r = root then f :: cone r else cone r

/-- An expanded input under one cone map is an expanded input under the other map, unless it is a cone file of a root
whose whole cone the other map expands. -/
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

/-- A literal glob matches only its own path and the paths below it. -/
theorem literal_prefix (f : String) (p : List String) (hl : Literal f) (h : matchesPath (segs f) p = true) :
    ∃ u, p = segs f ++ u := by
  simp only [matchesPath, List.any_eq_true, List.mem_range] at h
  obtain ⟨k, _, hm⟩ := h
  have hlit : ∀ g ∈ segs f, g ≠ "**" ∧ '*' ∉ g.toList := fun g hg =>
    ⟨fun he => hl g hg (by rw [he]; decide), hl g hg⟩
  have he := (globMatch_lit _ _ hlit).mp hm
  exact ⟨p.drop (k + 1), by rw [he, List.take_append_drop]⟩

/-- **The coarse filter is sound.** If the cones stay inside `coneGlobs`, every path in the scope of the precise
inputs (cones expanded from the checkout) is in the scope of the generated push paths. -/
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

/-- **The generated push filter never drops a needed start.** If the cones stay inside `coneGlobs` and the guard's
precise decision starts the workflow, GitHub's static `paths` filter passes the push's diff. -/
theorem push_filter_passes (c : String → List String) (hc : ConeWithin c) (w : Wf) (diff : List String)
    (differs : String → Bool) (h : w.starts (setMap c) (effective diff differs) = true) :
    selected (pushPaths w) diff = true := by
  obtain ⟨x, hx, _, hi⟩ := (starts_iff (setMap c) w diff differs).mp h
  exact selected_of_mem _ _ x hx (coarse_sound c hc w.inputs x hi)

/-- **A new module under `lean/Fw` changes no workflow file.** The push paths take no cone, so they are the same
before and after; and if the new file is literal and inside `coneGlobs`, the grown cones still stay inside
`coneGlobs`, so the same push paths still pass every push the guard starts. -/
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

/-- The workflows whose generated push filter passes a diff (GitHub's static step, before the guard). -/
def filtered (diff : List String) : List String :=
  (table.filter fun w => selected (pushPaths w) diff).map (·.file)

-- the coarse filter passes a new module under lean/Fw for every fwcore user; the guard then starts only lean.yml
#guard filtered ["lean/Fw/New.lean"] == ["breakpoint-gate.yml", "chromium-counts.yml", "difftest.yml", "gate-gaps.yml", "land.yml", "lean.yml", "path-pix.yml", "preview-e2e.yml", "smoothness.yml", "toolbar-throttle.yml", "trajectory-probe.yml", "visual-diff.yml", "wktr-fixtures.yml", "wktr.yml"]
#guard run ["lean/Fw/New.lean"] [] == ["land.yml", "lean.yml"]
-- a test module is outside every coarse fwcore glob
#guard filtered ["lean/FwTest/Lease.lean"] == ["land.yml", "lean.yml"]
-- the sample cones stay inside the coarse globs
#guard (["Main", "BreakgenMain"].flatMap sampleCone).all (inScope (parseScope coneGlobs))
-- the old precise paths moved with a new module; the push paths do not depend on the cone
#guard expand (setMap sampleCone) ["@fwcore"] != expand (setMap (addModule sampleCone "Main" "lean/Fw/New.lean")) ["@fwcore"]

/-! ## The Node pin rule (task node-pin-local)

One canonical Node version: the repo-root `.node-version`, an exact `x.y.z` at least `nodeMin`. The TS scanner
(`scripts/ci-paths.mjs`) reads the YAML into facts; the decisions below are Lean, and the TS twin is checked against
the golden vectors. -/

/-- The file that holds the pin. -/
def nodeFile : String := ".node-version"

/-- The oldest pin allowed (the first Node whose recursive `fs.watch` of a missing path throws). -/
def nodeMin : Nat × Nat × Nat := (24, 22, 0)

/-- Parse an exact `x.y.z` (three digit-only parts), else `none`. -/
def parseExact (s : String) : Option (Nat × Nat × Nat) :=
  match s.splitOn "." with
  | [a, b, c] =>
    if [a, b, c].all (fun p => p != "" && p.all Char.isDigit) then
      match a.toNat?, b.toNat?, c.toNat? with
      | some x, some y, some z => some (x, y, z)
      | _, _, _ => none
    else none
  | _ => none

/-- Triple order `a ≥ b`. -/
def tripleGe (a b : Nat × Nat × Nat) : Bool :=
  a.1 > b.1 || (a.1 == b.1 && (a.2.1 > b.2.1 || (a.2.1 == b.2.1 && a.2.2 ≥ b.2.2)))

/-- The problems of the pin file's content (`none`: no file): `noFile`, `notExact` or `tooOld`. -/
def pinValueProblems (pin : Option String) : List String :=
  match pin with
  | none => ["noFile"]
  | some s => match parseExact s with
    | none => ["notExact"]
    | some v => if tripleGe v nodeMin then [] else ["tooOld"]

/-- Where the pin is repeated (`.nvmrc`, `engines.node`, pnpm `useNodeVersion`): each copy that is not equal to the
pin is a `differs:<name>` problem; each copy is decided on its own. -/
def copyProblems (pin : Option String) (copies : List (String × Option String)) : List String :=
  copies.filterMap fun (n, v) => if v == pin then none else some ("differs:" ++ n)

/-- What the scanner reads off one job. `setups` holds, for each `actions/setup-node` step, its `node-version-file`
value (`""` when the step has none); `versionKey` is a `node-version:` key anywhere in the job; `pnpmAction` is a use of
the repo's setup-pnpm action (which sets Node up); `runsNode` is a `run:` line that calls node, pnpm, npm or npx.
`nodeBeforeSetup` is true when the first step that runs Node comes before the first setup-node or setup-pnpm step. A
step that runs Node is a `run:` line or a composite action that runs node, with no exemption: the telemetry steps
follow the setup step too. Under `pnpmAction`, the pinned Node is also what pnpm uses: pnpm skips its own Node fetch
when the Node running pnpm (`process.version` under corepack, the PATH node for the packaged binary;
pnpm env/system-node-version/src/index.ts:5-14@v10.34.5) equals `useNodeVersion` (pnpm env/plugin-commands-env/src/node.ts:46-48@v10.34.5).
MEASURED: snapshot-extract run 39460921500 (ci/node-pin-local @ 8a5a8165): setup-pnpm logs node v24.22.0, the frozen
install is done in 0.8 s, and no line fetches Node. -/
structure PinJob where
  setups : List String
  versionKey : Bool
  pnpmAction : Bool
  runsNode : Bool
  nodeBeforeSetup : Bool
  deriving Repr

/-- The problems of one job: `versionKey`, `otherFile` (a setup-node that does not read the pin file) and
`unpinnedNode` (it runs Node with no setup step at all, so it gets the runner's own Node) and `nodeBeforeSetup` (a step
runs Node before the pinned Node is set up, so that step gets the runner's own Node). -/
def jobProblems (j : PinJob) : List String :=
  (if j.versionKey then ["versionKey"] else []) ++
  (if j.setups.any (· != nodeFile) then ["otherFile"] else []) ++
  (if j.runsNode && j.setups.isEmpty && !j.pnpmAction then ["unpinnedNode"] else []) ++
  (if j.nodeBeforeSetup then ["nodeBeforeSetup"] else [])

/-- The problems of a workflow that uses Node, given its Lean row's inputs (`none`: it has no row): `noRow` or
`rowLacksPin`. -/
def rowProblems (usesNode : Bool) (row : Option (List String)) : List String :=
  if !usesNode then [] else
    match row with
    | none => ["noRow"]
    | some ins => if ins.contains nodeFile then [] else ["rowLacksPin"]

theorem jobProblems_versionKey (j : PinJob) : "versionKey" ∈ jobProblems j ↔ j.versionKey = true := by
  simp [jobProblems]

theorem jobProblems_otherFile (j : PinJob) :
    "otherFile" ∈ jobProblems j ↔ ∃ s ∈ j.setups, s ≠ nodeFile := by
  simp [jobProblems]

theorem jobProblems_unpinned (j : PinJob) :
    "unpinnedNode" ∈ jobProblems j ↔ j.runsNode = true ∧ j.setups = [] ∧ j.pnpmAction = false := by
  simp [jobProblems, and_assoc]

theorem jobProblems_nodeBeforeSetup (j : PinJob) :
    "nodeBeforeSetup" ∈ jobProblems j ↔ j.nodeBeforeSetup = true := by
  simp [jobProblems]

theorem pinValueProblems_noFile : pinValueProblems none = ["noFile"] := rfl

theorem pinValueProblems_notExact (s : String) :
    "notExact" ∈ pinValueProblems (some s) ↔ parseExact s = none := by
  unfold pinValueProblems
  cases h : parseExact s <;> simp [h]

theorem pinValueProblems_tooOld (s : String) :
    "tooOld" ∈ pinValueProblems (some s) ↔ ∃ v, parseExact s = some v ∧ tripleGe v nodeMin = false := by
  unfold pinValueProblems
  cases h : parseExact s <;> simp [h]

theorem pinValueProblems_ok (s : String) :
    pinValueProblems (some s) = [] ↔ ∃ v, parseExact s = some v ∧ tripleGe v nodeMin = true := by
  unfold pinValueProblems
  cases h : parseExact s <;> simp [h]

/-- The refusal when the running Node (`process.version`, with or without the leading `v`) is not the pin; `none`
when there is no pin file or the versions are equal. One line that names both versions and the fix. -/
def nodePinRefusal (running : String) (pinned : Option String) : Option String :=
  match pinned with
  | none => none
  | some p =>
    let want := p.trimAscii.copy -- ASCII space, \t, \r, \n only (Init/Data/Char/Basic.lean:97-98@v4.35.0); no BOM, no \f, \v
    let seen := if running.startsWith "v" then (running.drop 1).copy else running
    if seen == want then none else
      some ("refusing to start: running Node " ++ seen ++ " but .node-version pins " ++ want ++
        "; run `nvm install && nvm use` (or start through `pnpm`, which uses the pinned Node) and retry")

theorem nodePinRefusal_none_noPin (r : String) : nodePinRefusal r none = none := rfl

theorem nodePinRefusal_none_iff (r : String) (p : String) :
    nodePinRefusal r (some p) = none ↔
      (if r.startsWith "v" then (r.drop 1).copy else r) = p.trimAscii.copy := by
  unfold nodePinRefusal
  split <;> simp_all

theorem nodePinRefusal_some_iff (r : String) (p : String) :
    (nodePinRefusal r (some p)).isSome ↔
      (if r.startsWith "v" then (r.drop 1).copy else r) ≠ p.trimAscii.copy := by
  unfold nodePinRefusal
  split <;> simp_all

theorem rowProblems_noRow (u : Bool) : "noRow" ∈ rowProblems u none ↔ u = true := by
  cases u <;> simp [rowProblems]

theorem rowProblems_lacks (u : Bool) (ins : List String) :
    "rowLacksPin" ∈ rowProblems u (some ins) ↔ u = true ∧ nodeFile ∉ ins := by
  cases u <;> simp [rowProblems]

theorem copyProblems_iff (pin : Option String) (copies : List (String × Option String)) (n : String) :
    "differs:" ++ n ∈ copyProblems pin copies ↔ ∃ c ∈ copies, c.1 = n ∧ c.2 ≠ pin := by
  simp only [copyProblems, List.mem_filterMap, Option.ite_none_left_eq_some, Option.some.injEq]
  constructor
  · rintro ⟨⟨a, b⟩, hc, hne, he⟩
    exact ⟨(a, b), hc, by simpa using he, by simpa using hne⟩
  · rintro ⟨⟨a, b⟩, hc, rfl, hne⟩
    exact ⟨(a, b), hc, by simpa using hne, rfl⟩

#guard pinValueProblems (some "24.22.0") == []
#guard pinValueProblems (some "24.30.1") == []
#guard pinValueProblems (some "25.0.0") == []
#guard pinValueProblems (some "24.21.9") == ["tooOld"]
#guard pinValueProblems (some "24") == ["notExact"]
#guard pinValueProblems (some ">=24.22.0") == ["notExact"]
#guard pinValueProblems none == ["noFile"]
#guard jobProblems ⟨[".node-version"], false, false, true, false⟩ == []
#guard jobProblems ⟨[], false, false, true, false⟩ == ["unpinnedNode"]
#guard jobProblems ⟨[], false, true, true, false⟩ == []
#guard jobProblems ⟨[".node-version"], false, false, true, true⟩ == ["nodeBeforeSetup"]
#guard jobProblems ⟨["package.json"], true, false, true, false⟩ == ["versionKey", "otherFile"]
#guard rowProblems true none == ["noRow"]
#guard rowProblems true (some ["apps/**"]) == ["rowLacksPin"]
#guard rowProblems false none == []

/-! ## Golden (`packages/contracts/golden/ci/triggers.jsonl`) -/

/-- A JSON array of strings. -/
def strs (xs : List String) : Json := .arr (xs.map Json.str).toArray

/-- The table line: workflows with branches and symbolic inputs, and the named sets. -/
def tableLine (_ : Unit := ()) : Json :=
  Json.mkObj [("kind", "table"),
    ("workflows", .arr (table.map fun w => Json.mkObj [("file", .str w.file), ("branches", strs w.branches),
      ("inputs", strs w.inputs), ("crons", strs w.crons), ("onKeys", strs w.onKeys)]).toArray),
    ("sets", Json.mkObj (sets.map fun (n, xs) => (n, strs xs))), ("coneGlobs", strs coneGlobs),
    ("seeders", .arr (seeders.map fun (f, j) => Json.mkObj [("file", .str f), ("job", .str j)]).toArray),
    ("notMainPush", .str notMainPush),
    ("cacheWriters", .arr (cacheWriters.map fun (f, j, c) =>
      Json.mkObj [("file", .str f), ("job", .str j), ("cache", .str c)]).toArray),
    ("gateCaches", strs gateCaches),
    ("branchOnly", .arr (branchOnlyWriters.map fun (f, j, c) =>
      Json.mkObj [("file", .str f), ("job", .str j), ("cache", .str c)]).toArray)]

/-- A string or `null`. -/
def optStr (o : Option String) : Json := match o with | none => .null | some x => .str x

/-- Pin-file contents the golden decides. -/
def pinValues : List (Option String) :=
  [some "24.22.0", some "24.30.1", some "25.0.0", some "24.21.9", some "23.99.99", some "24", some "24.22",
   some ">=24.22.0", some "v24.22.0", some "24.22.x", some "24.22.0.1", some "", none]

/-- Jobs the golden decides: (setups, versionKey, pnpmAction, runsNode, nodeBeforeSetup). -/
def pinJobs : List PinJob := [
  ⟨[".node-version"], false, false, true, false⟩, ⟨[], false, false, true, false⟩, ⟨[], false, true, true, false⟩,
  ⟨[], false, false, false, false⟩, ⟨["package.json"], false, false, true, false⟩, ⟨[""], false, false, true, false⟩,
  ⟨[], true, false, true, false⟩, ⟨[".node-version", "x"], true, false, true, false⟩,
  ⟨[".node-version"], false, false, true, true⟩, ⟨[], false, true, true, true⟩, ⟨["package.json"], false, false, true, true⟩]

/-- Guard cases the golden decides: (running `process.version`, pin file content). -/
def pinGuards : List (String × Option String) := [
  ("v24.22.0", some "24.22.0"), ("24.22.0", some "24.22.0"), ("v24.22.0", some "24.22.0\n"), ("v24.22.0", some " 24.22.0 "),
  ("v24.14.0", some "24.22.0"), ("v24.23.0", some "24.22.0"), ("24.14.0", some "24.22.0"), ("vv24.22.0", some "24.22.0"),
  ("v1.0.0", none), ("v24.22.0", some ""), ("v24.22.0", some "\uFEFF24.22.0")]

/-- Rows the golden decides: (usesNode, row inputs). -/
def pinRows : List (Bool × Option (List String)) := [
  (true, some [".node-version", "apps/**"]), (true, some ["apps/**"]), (true, none), (false, none), (false, some [])]

/-- Copy sets the golden decides. -/
def pinCopies : List (Option String × List (String × Option String)) := [
  (some "24.22.0", [(".nvmrc", some "24.22.0"), ("engines.node", some "24.22.0"), ("useNodeVersion", some "24.22.0")]),
  (some "24.22.0", [(".nvmrc", some "24.21.0"), ("engines.node", some "24.22.0"), ("useNodeVersion", none)]),
  (some "24.22.0", [(".nvmrc", some "24.22.0"), ("engines.node", some ">=24")])]

/-- The Node pin golden lines. -/
def pinLines : List Json :=
  pinValues.map (fun p => Json.mkObj [("kind", "pinValue"), ("pin", optStr p), ("problems", strs (pinValueProblems p))]) ++
  pinJobs.map (fun j => Json.mkObj [("kind", "pinJob"), ("setups", strs j.setups), ("versionKey", .bool j.versionKey),
    ("pnpmAction", .bool j.pnpmAction), ("runsNode", .bool j.runsNode), ("nodeBeforeSetup", .bool j.nodeBeforeSetup), ("problems", strs (jobProblems j))]) ++
  pinGuards.map (fun (r, p) => Json.mkObj [("kind", "pinGuard"), ("running", .str r), ("pinned", optStr p),
    ("refusal", optStr (nodePinRefusal r p))]) ++
  pinRows.map (fun (u, r) => Json.mkObj [("kind", "pinRow"), ("usesNode", .bool u),
    ("row", match r with | none => .null | some xs => strs xs), ("problems", strs (rowProblems u r))]) ++
  pinCopies.map (fun (p, cs) => Json.mkObj [("kind", "pinCopies"), ("pin", optStr p),
    ("copies", .arr (cs.map fun (n, v) => Json.mkObj [("name", .str n), ("value", optStr v)]).toArray),
    ("problems", strs (copyProblems p cs))])

/-! ## The probe line of a commit message (task `ci-push-probe-inputs`)

A builder cannot dispatch a workflow (the sandbox refuses it, incident `m195`), but it can push to `ci/**`. A line of the
head commit message that starts with `[trajectory` carries the inputs of the trajectory probe for that push:

    [ci:trajectory-probe]
    [trajectory fw=hero.exit:scoped,morph.tween:waapi widths=390,1280 engines=both diagnostic]

A widths subset needs the bare word `diagnostic`; omit `widths` for a verdict run. The mark rule binds the trajectory workflow only:
the smoothness workflow reads the same line as before, and a `[frames:` message is exempt (`ProbeLane`).

The lane is still asked for with its `[ci:trajectory-probe]` token (`Fw.Ci.Intent`); this section decides what the push
runs *with*. Only a line that starts with the keyword counts, so a message that quotes the form in prose asks for nothing.
Keys: `fw`, `preset` (exclusive with `fw`), `widths`, `engines`, `debug`, and the bare word `diagnostic`; each at most once, each with a value from a closed
character set. `debug` names a page recorder of the probe (`nav-transition`, `root-events`) and takes only a value of a closed list; no file
of the repo can turn a recorder on, so nothing that lands on `main` does. A line that does not parse is refused with a reason (the plan step of the workflow fails with it); it is
never ignored. Two such lines are refused too. -/

/-- The inputs of one probe run (an empty string is "none"; `engines` defaults to `both`; `debug` is the page recorder
the run switches on, `""` for none; `diagnostic` marks a run read by hand, which may walk a subset of the widths, see
`Fw.Gate.Trajectory.Dispatch`). -/
structure ProbeIn where
  engines : String
  fw : String
  preset : String
  widths : String
  debug : String
  diagnostic : Bool
deriving Repr, DecidableEq

/-- The inputs of a run whose message names none: the dispatch defaults (a verdict run, all four widths). -/
def ProbeIn.default : ProbeIn := ⟨"both", "", "", "", "", false⟩

/-- The mark of a run: diagnostic when its line says so, else verdict. -/
def ProbeIn.mark (p : ProbeIn) : Fw.Gate.Trajectory.Dispatch.Mark :=
  if p.diagnostic then .diagnostic else .verdict

/-- The decision of the one Lean dispatch rule on the mark and the `widths` of a run. -/
def ProbeIn.walk (p : ProbeIn) : Fw.Gate.Trajectory.Dispatch.Decision :=
  Fw.Gate.Trajectory.Dispatch.dispatchIn p.mark p.widths

/-- Does the dispatch rule accept the widths of the run? -/
def ProbeIn.walksOk (p : ProbeIn) : Bool :=
  match p.walk with
  | .accepted _ => true
  | .refused _ => false

/-- The reason the widths of a run are refused (`""` when they are accepted): the shared dispatch text, and for a subset
what to add to the line. -/
def ProbeIn.walkWhy (p : ProbeIn) : String :=
  match p.walk with
  | .accepted _ => ""
  | .refused .scopedVerdict => Fw.Gate.Trajectory.Dispatch.Why.text .scopedVerdict p.widths ++
      "; add the word diagnostic to the line for a run read by hand"
  | .refused w => w.text p.widths

/-- The lane a probe line is read for (task `traj-dispatch-push-lane`, round 2). The mark rule (`Fw.Gate.Trajectory.Dispatch`)
judges only the `trajectory` lane, whose runs are stored and judged at all four widths. `smoothness` is a different probe whose
verdict is at 390 and 1280, so it keeps the widths allowlist it had before the mark rule. `frames` is a `[frames:` run: it is
read by eye and never stored as a verdict run, so it is exempt from the mark rule. -/
inductive ProbeLane where
  | trajectory
  | smoothness
  | frames
deriving Repr, DecidableEq

/-- Does the mark rule apply to the lane? Only the trajectory lane. -/
def ProbeLane.marked : ProbeLane → Bool
  | .trajectory => true
  | .smoothness => false
  | .frames => false

/-- Does the lane know the bare word `diagnostic`? Trajectory and frames do; smoothness reads a line as it did before the mark
rule, where the word is an unknown token. -/
def ProbeLane.word : ProbeLane → Bool
  | .trajectory => true
  | .smoothness => false
  | .frames => true

/-- The name of a lane in the golden files and the `LANE` input of the line script. -/
def ProbeLane.name : ProbeLane → String
  | .trajectory => "trajectory"
  | .smoothness => "smoothness"
  | .frames => "frames"

/-- Does the message carry the frames token `[frames:` (ASCII case ignored, as the `contains` of the workflow expressions does)? -/
def hasFrames (m : String) : Bool :=
  let l := m.toList.map Char.toLower
  (List.range (l.length + 1)).any fun i => "[frames:".toList.isPrefixOf (l.drop i)

/-- The lane a push is read in: the trajectory workflow reads a message with the frames token as a frames run; every other
workflow and message keeps the lane of its workflow. -/
def effLane (wf : ProbeLane) (m : String) : ProbeLane :=
  if wf == .trajectory && hasFrames m then .frames else wf

/-- Does the mark rule hold the run in this lane to the widths? Marked lanes use the dispatch rule on the mark; the others only
the widths allowlist (a nonempty-or-empty list of lane widths without repeats, as before the mark rule). -/
def ProbeIn.widthsOk (lane : ProbeLane) (p : ProbeIn) : Bool :=
  if lane.marked then p.walksOk else !decide (Fw.Gate.Trajectory.pickWidths p.widths = .refused)

/-- The reason the widths of a run are refused in this lane. -/
def ProbeIn.widthsWhy (lane : ProbeLane) (p : ProbeIn) : String :=
  if lane.marked then p.walkWhy else "widths must be a comma list of 390, 640, 641, 1280 without repeats"

/-- What the message says about the probe inputs. -/
inductive ProbeLine where
  | absent
  | inputs (p : ProbeIn)
  | refused (why : String)
deriving Repr, DecidableEq

/-- What a push does with the probe. -/
inductive PushProbe where
  | notAsked
  | needsLane
  | run (p : ProbeIn)
  | refused (why : String)
deriving Repr, DecidableEq

/-- Whitespace inside a line. -/
def isWs (c : Char) : Bool := c == ' ' || c == '\t' || c == '\r'

/-- A line without leading and trailing whitespace. -/
def trimL (cs : List Char) : List Char := ((cs.dropWhile isWs).reverse.dropWhile isWs).reverse

/-- Split at every `d`, empty parts kept. -/
def splitOn (d : Char) : List Char → List (List Char)
  | [] => [[]]
  | c :: cs =>
    match splitOn d cs with
    | r :: rs => if c == d then [] :: r :: rs else (c :: r) :: rs
    | [] => [[c]]

/-- The keyword that opens the line. -/
def lineKw : List Char := "[trajectory".toList

/-- Does the line (trimmed, lowered) start with the keyword? -/
def isCand (l : List Char) : Bool := lineKw.isPrefixOf ((trimL l).map Char.toLower)

/-- The characters of a value: ASCII letters and digits and `. : , _ @ -`. -/
def valueChar (c : Char) : Bool := c.isAlphanum || c == '.' || c == ':' || c == ',' || c == '_' || c == '@' || c == '-'

/-- The keys of a line. -/
def probeKeys : List String := ["fw", "preset", "widths", "engines", "debug"]

/-- The bare word that marks the run diagnostic (a flag, not a `key=value` pair). -/
def diagnosticWord : String := "diagnostic"

/-- The engines input values. -/
def probeEngines : List String := ["both", "chromium", "playwright-webkit"]

def probeDebugs : List String := ["nav-transition", "root-events"]

/-- Split `key=value` at the first `=`. -/
def splitEq : List Char → Option (List Char × List Char)
  | [] => none
  | '=' :: cs => some ([], cs)
  | c :: cs => (splitEq cs).map fun (k, v) => (c :: k, v)

/-- Add one `key=value` token to the pairs read so far. In a lane without the word (`ProbeLane.word`) `diagnostic` is an
unknown token, as before the mark rule. -/
def addTok (lane : ProbeLane) (acc : List (String × String)) (t : List Char) : Except String (List (String × String)) :=
  match splitEq t with
  | none =>
    if lane.word && String.ofList t == diagnosticWord then
      if acc.any (·.1 == diagnosticWord) then .error s!"key '{diagnosticWord}' given twice"
      else .ok (acc ++ [(diagnosticWord, "true")])
    else .error s!"token '{String.ofList t}' has no '='"
  | some (k, v) =>
    let ks := String.ofList k
    if lane.word && ks == diagnosticWord then .error "diagnostic is a bare word, not diagnostic=..."
    else if !probeKeys.contains ks then
      if lane.word then .error s!"unknown key '{ks}' (keys: fw, preset, widths, engines, debug, diagnostic)"
      else .error s!"unknown key '{ks}' (keys: fw, preset, widths, engines, debug)"
    else if acc.any (·.1 == ks) then .error s!"key '{ks}' given twice"
    else if v.isEmpty then .error s!"key '{ks}' has no value"
    else if !v.all valueChar then .error s!"the value of '{ks}' has a character outside A-Z a-z 0-9 . : , _ @ -"
    else .ok (acc ++ [(ks, String.ofList v)])

/-- All tokens of a line body, left to right. -/
def addAll (lane : ProbeLane) (toks : List (List Char)) : Except String (List (String × String)) :=
  toks.foldl (fun r t => r.bind fun acc => addTok lane acc t) (.ok [])

/-- The inputs from the pairs: defaults, the exclusivity of `fw` and `preset`, the engines allowlist, the widths rule of the
lane (`ProbeIn.widthsOk`: the dispatch rule on the mark for the trajectory lane, the widths allowlist otherwise) and the
recorder allowlist (`debug` is empty or one of `probeDebugs`). -/
def build (lane : ProbeLane) (kv : List (String × String)) : Except String ProbeIn :=
  let g := fun (k d : String) => (kv.lookup k).getD d
  let p : ProbeIn := ⟨g "engines" "both", g "fw" "", g "preset" "", g "widths" "", g "debug" "",
    lane.word && (kv.lookup diagnosticWord).isSome⟩
  if p.fw != "" && p.preset != "" then .error "fw and preset are exclusive"
  else if !probeEngines.contains p.engines then .error "engines must be both, chromium or playwright-webkit"
  else if !p.widthsOk lane then .error (p.widthsWhy lane)
  else if p.debug != "" && !probeDebugs.contains p.debug then .error "debug must be nav-transition or root-events"
  else .ok p

/-- One candidate line parsed. -/
def parseOne (lane : ProbeLane) (l : List Char) : Except String ProbeIn :=
  let t := trimL l
  if t.getLast? != some ']' then .error "the line has no closing ']'"
  else
    let body := (t.drop lineKw.length).dropLast
    if !(body.isEmpty || body.head? == some ' ' || body.head? == some '\t') then
      .error "expected a space after [trajectory"
    else
      match addAll lane ((splitOn ' ' body).filter fun w => !w.isEmpty) with
      | .error w => .error w
      | .ok kv => build lane kv

/-- The candidate lines of a message, in order. -/
def candidates (m : String) : List (List Char) := (splitOn '\n' m.toList).filter isCand

/-- The probe inputs a commit message carries. -/
def parseLine (lane : ProbeLane) (m : String) : ProbeLine :=
  match candidates m with
  | [] => .absent
  | [l] => match parseOne lane l with
    | .ok p => .inputs p
    | .error w => .refused w
  | _ => .refused "more than one [trajectory ...] line"

/-- What a push to `ci/**` does with the probe. `wf` is the workflow reading the message, `lane` says its head commit asks for the
lane (`[ci:trajectory-probe]`). The line is read in `effLane wf m`. -/
def pushProbe (wf : ProbeLane) (lane : Bool) (m : String) : PushProbe :=
  match parseLine (effLane wf m) m with
  | .refused w => .refused w
  | .absent => if lane then .run ProbeIn.default else .notAsked
  | .inputs p => if lane then .run p else .needsLane

/-- Branch no line: the message carries no inputs. -/
theorem parse_absent (lane : ProbeLane) (m : String) (h : candidates m = []) : parseLine lane m = .absent := by
  simp [parseLine, h]

/-- Branch two or more lines: refused. -/
theorem parse_many (lane : ProbeLane) (m : String) (a b : List Char) (r : List (List Char)) (h : candidates m = a :: b :: r) :
    parseLine lane m = .refused "more than one [trajectory ...] line" := by
  simp [parseLine, h]

/-- Branch one line that parses: its inputs. -/
theorem parse_one_ok (lane : ProbeLane) (m : String) (l : List Char) (p : ProbeIn) (h : candidates m = [l]) (hp : parseOne lane l = .ok p) :
    parseLine lane m = .inputs p := by
  simp [parseLine, h, hp]

/-- Branch one line that does not parse: refused with the reason of the line. -/
theorem parse_one_err (lane : ProbeLane) (m : String) (l : List Char) (w : String) (h : candidates m = [l]) (hp : parseOne lane l = .error w) :
    parseLine lane m = .refused w := by
  simp [parseLine, h, hp]

/-- **Every accepted input set is allowed.** `fw` and `preset` are never both set, the engines are one of the three
values, the widths pass the rule of the lane (`ProbeIn.widthsOk`) and the recorder is none or one of `probeDebugs`. -/
theorem build_ok (lane : ProbeLane) (kv : List (String × String)) (p : ProbeIn) (h : build lane kv = .ok p) :
    (p.fw = "" ∨ p.preset = "") ∧ p.engines ∈ probeEngines ∧ p.widthsOk lane = true ∧
      (p.debug = "" ∨ p.debug ∈ probeDebugs) := by
  unfold build at h
  dsimp only at h
  split at h
  · simp at h
  split at h
  · simp at h
  split at h
  · simp at h
  split at h
  · simp at h
  simp only [Except.ok.injEq] at h
  subst h
  rename_i h1 h2 h3 h4
  refine ⟨?_, ?_, ?_, ?_⟩
  · simp only [Bool.and_eq_true, bne_iff_ne, ne_eq, not_and, Classical.not_not] at h1
    by_cases hf : (kv.lookup "fw").getD "" = ""
    · exact Or.inl hf
    · exact Or.inr (h1 hf)
  · simpa using h2
  · simpa using h3
  · simp only [Bool.and_eq_true, bne_iff_ne, ne_eq, Bool.not_eq_true', not_and] at h4
    by_cases hd : (kv.lookup "debug").getD "" = ""
    · exact Or.inl hd
    · exact Or.inr (by simpa using h4 hd)

/-- Branch no `debug` key: the run switches no recorder on. -/
theorem build_debug_none (lane : ProbeLane) (kv : List (String × String)) (p : ProbeIn) (h : build lane kv = .ok p)
    (hk : kv.lookup "debug" = none) : p.debug = "" := by
  unfold build at h
  dsimp only at h
  split at h
  · simp at h
  split at h
  · simp at h
  split at h
  · simp at h
  split at h
  · simp at h
  simp only [Except.ok.injEq] at h
  subst h
  simp [hk]

/-- Branch a `debug` key that is accepted: the run switches exactly that recorder on (`build_ok`: it is listed). -/
theorem build_debug_some (lane : ProbeLane) (kv : List (String × String)) (d : String) (hk : kv.lookup "debug" = some d) (p : ProbeIn) (h : build lane kv = .ok p) : p.debug = d := by
  unfold build at h
  dsimp only at h
  split at h
  · simp at h
  split at h
  · simp at h
  split at h
  · simp at h
  split at h
  · simp at h
  simp only [Except.ok.injEq] at h
  subst h
  simp [hk]

/-- Branch a `debug` key with a value outside `probeDebugs`: the line is refused (never ignored, never run). -/
theorem build_debug_unknown (lane : ProbeLane) (kv : List (String × String)) (d : String) (hk : kv.lookup "debug" = some d)
    (hne : d ≠ "") (hd : d ∉ probeDebugs) : ∃ w, build lane kv = .error w := by
  unfold build
  dsimp only
  simp only [hk, Option.getD_some]
  split
  · exact ⟨_, rfl⟩
  split
  · exact ⟨_, rfl⟩
  split
  · exact ⟨_, rfl⟩
  have hc : (d != "" && !probeDebugs.contains d) = true := by simpa [hne] using hd
  simp only [hc, ↓reduceIte]
  exact ⟨_, rfl⟩

/-- Branch refused line: a push never runs the probe past a refused line, whether or not it asked for the lane. -/
theorem push_refused (wf : ProbeLane) (lane : Bool) (m : String) (w : String) (h : parseLine (effLane wf m) m = .refused w) :
    pushProbe wf lane m = .refused w := by
  simp [pushProbe, h]

/-- Branch no line, lane asked: the probe runs with the defaults. -/
theorem push_default (wf : ProbeLane) (m : String) (h : parseLine (effLane wf m) m = .absent) :
    pushProbe wf true m = .run ProbeIn.default := by
  simp [pushProbe, h]

/-- Branch no line, lane not asked: nothing is asked. -/
theorem push_not_asked (wf : ProbeLane) (m : String) (h : parseLine (effLane wf m) m = .absent) :
    pushProbe wf false m = .notAsked := by
  simp [pushProbe, h]

/-- Branch a line, lane asked: the probe runs with exactly the inputs of the line. -/
theorem push_line (wf : ProbeLane) (m : String) (p : ProbeIn) (h : parseLine (effLane wf m) m = .inputs p) :
    pushProbe wf true m = .run p := by
  simp [pushProbe, h]

/-- Branch a line, lane not asked: the push says it needs the lane token (the inputs would otherwise be ignored). -/
theorem push_needs_lane (wf : ProbeLane) (m : String) (p : ProbeIn) (h : parseLine (effLane wf m) m = .inputs p) :
    pushProbe wf false m = .needsLane := by
  simp [pushProbe, h]

/-- **A push runs the probe only when it asked for the lane.** -/
theorem push_run_asked (wf : ProbeLane) (lane : Bool) (m : String) (p : ProbeIn) (h : pushProbe wf lane m = .run p) :
    lane = true := by
  unfold pushProbe at h
  cases hp : parseLine (effLane wf m) m <;> cases lane <;> simp_all

/-- **The inputs of a run are the line's, parsed once.** A run with a line in the message uses exactly that line's inputs. -/
theorem push_run_is_parse (wf : ProbeLane) (lane : Bool) (m : String) (p : ProbeIn) (h : pushProbe wf lane m = .run p) :
    parseLine (effLane wf m) m = .inputs p ∨ (parseLine (effLane wf m) m = .absent ∧ p = ProbeIn.default) := by
  unfold pushProbe at h
  cases hp : parseLine (effLane wf m) m <;> cases lane <;> simp_all

/-! ### The mark rule on the push line (task `traj-dispatch-push-lane`)

In the trajectory lane a line without the bare word `diagnostic` is a verdict run: the rule of `Fw.Gate.Trajectory.Dispatch`
accepts it only with all four widths. The same rule gates `fw run --trajectory` and the `widths` input of the workflow. The
other lanes (`ProbeLane`) are not held to it: smoothness keeps the widths allowlist it had, a frames run is exempt. -/

/-- A run whose widths the rule accepts has a decision `accepted xs`. -/
theorem walksOk_walk (p : ProbeIn) (h : p.walksOk = true) : ∃ xs, p.walk = .accepted xs := by
  unfold ProbeIn.walksOk at h
  split at h
  · rename_i xs hx; exact ⟨xs, hx⟩
  · simp at h

/-- Branch no `diagnostic` word: the mark of the run is verdict. -/
theorem mark_verdict (p : ProbeIn) (h : p.diagnostic = false) : p.mark = .verdict := by
  simp [ProbeIn.mark, h]

/-- Branch the `diagnostic` word: the mark of the run is diagnostic. -/
theorem mark_diagnostic (p : ProbeIn) (h : p.diagnostic = true) : p.mark = .diagnostic := by
  simp [ProbeIn.mark, h]

/-- Branch verdict run accepted by the rule: it walks all four lane widths. -/
theorem walk_verdict_all (p : ProbeIn) (hd : p.diagnostic = false) (h : p.walksOk = true) :
    ∃ xs, Fw.Gate.Trajectory.Dispatch.dispatchIn .verdict p.widths = .accepted xs ∧
      ∀ w ∈ Fw.Gate.Trajectory.allowedWidths, w ∈ xs := by
  obtain ⟨xs, hx⟩ := walksOk_walk p h
  unfold ProbeIn.walk at hx
  rw [mark_verdict p hd] at hx
  exact ⟨xs, hx, Fw.Gate.Trajectory.Dispatch.verdict_in_all_widths _ _ hx⟩

/-- Branch diagnostic run accepted by the rule: it walks at least one lane width, none twice. -/
theorem walk_diagnostic_some (p : ProbeIn) (hd : p.diagnostic = true) (h : p.walksOk = true) :
    ∃ xs, Fw.Gate.Trajectory.Dispatch.dispatchIn .diagnostic p.widths = .accepted xs ∧ xs ≠ [] ∧
      (∀ w ∈ xs, w ∈ Fw.Gate.Trajectory.allowedWidths) ∧ xs.Nodup := by
  obtain ⟨xs, hx⟩ := walksOk_walk p h
  unfold ProbeIn.walk at hx
  rw [mark_diagnostic p hd] at hx
  unfold Fw.Gate.Trajectory.Dispatch.dispatchIn at hx
  split at hx
  · simp at hx
  · rename_i ws _
    exact ⟨xs, by unfold Fw.Gate.Trajectory.Dispatch.dispatchIn; simp_all,
      (Fw.Gate.Trajectory.Dispatch.accepted_nonempty _ _ _ hx).1,
      (Fw.Gate.Trajectory.Dispatch.accepted_nonempty _ _ _ hx).2,
      Fw.Gate.Trajectory.Dispatch.accepted_nodup _ _ _ hx⟩

/-- The inputs of a line that parses pass the widths rule of its lane. -/
theorem parseOne_widths (lane : ProbeLane) (l : List Char) (p : ProbeIn) (h : parseOne lane l = .ok p) :
    p.widthsOk lane = true := by
  unfold parseOne at h
  dsimp only at h
  split at h
  · simp at h
  split at h
  · simp at h
  split at h
  · simp at h
  · rename_i kv _
    exact (build_ok lane kv p h).2.2.1

/-- The inputs of a parsed message pass the widths rule of the lane it was read in. -/
theorem parseLine_widths (lane : ProbeLane) (m : String) (p : ProbeIn) (h : parseLine lane m = .inputs p) :
    p.widthsOk lane = true := by
  unfold parseLine at h
  rcases hc : candidates m with _ | ⟨l, _ | ⟨l2, r⟩⟩
  · simp [hc] at h
  · rw [hc] at h
    simp only at h
    cases ho : parseOne lane l with
    | error w => simp [ho] at h
    | ok q => simp only [ho, ProbeLine.inputs.injEq] at h; subst h; exact parseOne_widths lane l q ho
  · simp [hc] at h

/-- In the trajectory lane the widths rule is the dispatch rule. -/
theorem widthsOk_trajectory (p : ProbeIn) : p.widthsOk .trajectory = p.walksOk := by
  simp [ProbeIn.widthsOk, ProbeLane.marked]

/-- **A trajectory push whose line carries no `diagnostic` word walks all four widths.** Every run `pushProbe` starts is either a
default run (no line) or the inputs of a parsed line, and both pass the dispatch rule. The push is read in the trajectory lane
(`effLane wf m = .trajectory`: the trajectory workflow, a message without the frames token). -/
theorem push_verdict_all_widths (wf : ProbeLane) (lane : Bool) (m : String) (p : ProbeIn)
    (h : pushProbe wf lane m = .run p) (hl : effLane wf m = .trajectory) (hd : p.diagnostic = false) :
    ∃ xs, Fw.Gate.Trajectory.Dispatch.dispatchIn .verdict p.widths = .accepted xs ∧
      ∀ w ∈ Fw.Gate.Trajectory.allowedWidths, w ∈ xs := by
  apply walk_verdict_all p hd
  rcases push_run_is_parse wf lane m p h with hp | ⟨_, rfl⟩
  · have := parseLine_widths _ m p hp
    rwa [hl, widthsOk_trajectory] at this
  · decide

/-- **A trajectory push whose line carries the `diagnostic` word walks a nonempty subset of the lane widths.** -/
theorem push_diagnostic_widths (wf : ProbeLane) (lane : Bool) (m : String) (p : ProbeIn)
    (h : pushProbe wf lane m = .run p) (hl : effLane wf m = .trajectory) (hd : p.diagnostic = true) :
    ∃ xs, Fw.Gate.Trajectory.Dispatch.dispatchIn .diagnostic p.widths = .accepted xs ∧ xs ≠ [] ∧
      (∀ w ∈ xs, w ∈ Fw.Gate.Trajectory.allowedWidths) ∧ xs.Nodup := by
  apply walk_diagnostic_some p hd
  rcases push_run_is_parse wf lane m p h with hp | ⟨_, rfl⟩
  · have := parseLine_widths _ m p hp
    rwa [hl, widthsOk_trajectory] at this
  · simp [ProbeIn.default] at hd

/-- **A frames message is exempt from the mark rule.** The trajectory workflow reads a message with the `[frames:` token in
the frames lane, whose widths rule is the allowlist alone: a run is never refused for a subset of widths. -/
theorem push_frames_exempt (m : String) (hf : hasFrames m = true) :
    effLane .trajectory m = .frames ∧ ProbeLane.marked .frames = false := by
  simp [effLane, hf, ProbeLane.marked]

/-- **The mark rule binds the trajectory lane alone.** -/
theorem marked_iff (l : ProbeLane) : l.marked = true ↔ l = .trajectory := by
  cases l <;> simp [ProbeLane.marked]

/-- The smoothness workflow keeps its lane whatever the message says. -/
theorem effLane_smoothness (m : String) : effLane .smoothness m = .smoothness := by
  simp [effLane]

/-- A frames lane stays a frames lane. -/
theorem effLane_frames (m : String) : effLane .frames m = .frames := by
  simp [effLane]

/-! ### The smoothness lane is what it was before the mark rule

The smoothness probe parses the same `[trajectory ...]` line, but its verdict is at 390 and 1280, not at four widths, so the
mark rule must not reach it. The functions below are the line reader as it stood before task `traj-dispatch-push-lane`
(a frozen spec, copied from `main`), and the theorems say the smoothness lane is that reader, line for line. -/

/-- Pre-task `addTok`: `diagnostic` is an unknown token. -/
def addTokPre (acc : List (String × String)) (t : List Char) : Except String (List (String × String)) :=
  match splitEq t with
  | none => .error s!"token '{String.ofList t}' has no '='"
  | some (k, v) =>
    let ks := String.ofList k
    if !probeKeys.contains ks then .error s!"unknown key '{ks}' (keys: fw, preset, widths, engines, debug)"
    else if acc.any (·.1 == ks) then .error s!"key '{ks}' given twice"
    else if v.isEmpty then .error s!"key '{ks}' has no value"
    else if !v.all valueChar then .error s!"the value of '{ks}' has a character outside A-Z a-z 0-9 . : , _ @ -"
    else .ok (acc ++ [(ks, String.ofList v)])

/-- Pre-task `addAll`. -/
def addAllPre (toks : List (List Char)) : Except String (List (String × String)) :=
  toks.foldl (fun r t => r.bind fun acc => addTokPre acc t) (.ok [])

/-- Pre-task `build`: fw/preset exclusive, engines allowlist, widths allowlist (`pickWidths`), recorder allowlist. -/
def buildPre (kv : List (String × String)) : Except String ProbeIn :=
  let g := fun (k d : String) => (kv.lookup k).getD d
  let p : ProbeIn := ⟨g "engines" "both", g "fw" "", g "preset" "", g "widths" "", g "debug" "", false⟩
  if p.fw != "" && p.preset != "" then .error "fw and preset are exclusive"
  else if !probeEngines.contains p.engines then .error "engines must be both, chromium or playwright-webkit"
  else if decide (Fw.Gate.Trajectory.pickWidths p.widths = .refused) then
    .error "widths must be a comma list of 390, 640, 641, 1280 without repeats"
  else if p.debug != "" && !probeDebugs.contains p.debug then .error "debug must be nav-transition or root-events"
  else .ok p

/-- Pre-task `parseOne`. -/
def parseOnePre (l : List Char) : Except String ProbeIn :=
  let t := trimL l
  if t.getLast? != some ']' then .error "the line has no closing ']'"
  else
    let body := (t.drop lineKw.length).dropLast
    if !(body.isEmpty || body.head? == some ' ' || body.head? == some '\t') then
      .error "expected a space after [trajectory"
    else
      match addAllPre ((splitOn ' ' body).filter fun w => !w.isEmpty) with
      | .error w => .error w
      | .ok kv => buildPre kv

/-- Pre-task `parseLine`. -/
def parseLinePre (m : String) : ProbeLine :=
  match candidates m with
  | [] => .absent
  | [l] => match parseOnePre l with
    | .ok p => .inputs p
    | .error w => .refused w
  | _ => .refused "more than one [trajectory ...] line"

theorem addTok_smoothness : addTok .smoothness = addTokPre := by
  funext acc t
  unfold addTok addTokPre
  simp [ProbeLane.word]

theorem addAll_smoothness : addAll .smoothness = addAllPre := by
  funext toks
  simp only [addAll, addAllPre, addTok_smoothness]

theorem build_smoothness : build .smoothness = buildPre := by
  funext kv
  simp [build, buildPre, ProbeIn.widthsOk, ProbeIn.widthsWhy, ProbeLane.marked, ProbeLane.word]

theorem parseOne_smoothness : parseOne .smoothness = parseOnePre := by
  funext l
  simp only [parseOne, parseOnePre, addAll_smoothness, build_smoothness]

/-- **The smoothness lane accepts exactly what it accepted before the mark rule.** Line for line, the same inputs or the same
refusal; no `diagnostic` word, no mark rule, the same widths allowlist. -/
theorem parseLine_smoothness (m : String) : parseLine .smoothness m = parseLinePre m := by
  simp only [parseLine, parseLinePre, parseOne_smoothness]

/-- A smoothness push is the pre-task reader's decision. -/
theorem push_smoothness_pre (lane : Bool) (m : String) :
    pushProbe .smoothness lane m =
      (match parseLinePre m with
        | .refused w => .refused w
        | .absent => if lane then .run ProbeIn.default else .notAsked
        | .inputs p => if lane then .run p else .needsLane) := by
  simp only [pushProbe, effLane_smoothness, parseLine_smoothness]

/-- Every run a smoothness push starts has widths the allowlist accepts; the mark rule adds nothing to it. -/
theorem push_smoothness_widths (lane : Bool) (m : String) (p : ProbeIn) (h : pushProbe .smoothness lane m = .run p) :
    Fw.Gate.Trajectory.pickWidths p.widths ≠ .refused := by
  rcases push_run_is_parse .smoothness lane m p h with hp | ⟨_, rfl⟩
  · have hw := parseLine_widths _ m p hp
    rw [effLane_smoothness] at hw
    simpa [ProbeIn.widthsOk, ProbeLane.marked] using hw
  · decide

-- Branch a subset without the word: refused with the dispatch text and the hint.
set_option maxRecDepth 8000 in
example : pushProbe .trajectory true "[trajectory widths=390,641]" = .refused
    ("widths 390,641 is a subset, and a verdict run (stored, judged) walks all four widths (390,640,641,1280); a run short of a width gets no verdict; add the word diagnostic to the line for a run read by hand") := by decide
-- Branch a subset with the word, a complete list with or without it: accepted.
example : pushProbe .trajectory true "[trajectory widths=390,641 diagnostic]" = .run ⟨"both", "", "", "390,641", "", true⟩ := by decide
example : pushProbe .trajectory true "[trajectory widths=390,640,641,1280]" = .run ⟨"both", "", "", "390,640,641,1280", "", false⟩ := by decide
example : pushProbe .trajectory true "[trajectory diagnostic]" = .run { ProbeIn.default with diagnostic := true } := by decide
-- Branch smoothness lane: its 390,1280 line runs as it did, the word is an unknown token.
example : pushProbe .smoothness true "[trajectory preset=v2-proved widths=390,1280]" = .run ⟨"both", "", "v2-proved", "390,1280", "", false⟩ := by decide
example : pushProbe .smoothness true "[trajectory widths=390,1280 diagnostic]" = .refused "token 'diagnostic' has no '='" := by decide
-- Branch frames lane: the documented frames line (docs/team/tools/trajectory-frames.md) parses, in the trajectory workflow too.
example : pushProbe .trajectory true "[ci:trajectory-probe] [frames:nav:x]\n[trajectory engines=playwright-webkit widths=390,1280]"
    = .run ⟨"playwright-webkit", "", "", "390,1280", "", false⟩ := by decide
example : pushProbe .frames true "[trajectory widths=390,1280]" = .run ⟨"both", "", "", "390,1280", "", false⟩ := by decide
-- Branch bad input stays bad under the word; the word is a flag, once.
example : pushProbe .trajectory true "[trajectory widths=800 diagnostic]" = .refused "widths must be a comma list of 390, 640, 641, 1280 without repeats" := by decide
example : pushProbe .trajectory true "[trajectory diagnostic diagnostic]" = .refused "key 'diagnostic' given twice" := by decide
example : pushProbe .trajectory true "[trajectory diagnostic=true]" = .refused "diagnostic is a bare word, not diagnostic=..." := by decide

/-! ## The macOS leg on a push (task `waapi-tail-webkit-p2`)

`probe-apple` costs a shared macOS slot. A dispatch runs it when the plan has a macOS leg; a `ci/*` push runs it only when
its commit asks for what only macOS WebKit gives: a frames run (`[frames:` token) or a page recorder (the `debug=` key
of the probe line). The workflow reads the answer from the `apple_run` output of the plan step. -/

/-- The events the probe workflow starts under. -/
inductive ProbeEv where
  | dispatch
  | ciPush
deriving Repr, DecidableEq

/-- The page recorder the probe line of the message asks for (`""` for none, a refused line or no line). -/
def recorderOf (m : String) : String :=
  match pushProbe .trajectory true m with
  | .run p => p.debug
  | _ => ""

/-- Does the macOS leg run? `appleN` is the number of macOS legs of the plan. -/
def appleRuns (ev : ProbeEv) (m : String) (appleN : Nat) : Bool :=
  appleN != 0 && (match ev with
    | .dispatch => true
    | .ciPush => hasFrames m || recorderOf m != "")

/-- Branch no macOS leg in the plan: nothing runs, whatever the event or message. -/
theorem apple_no_leg (ev : ProbeEv) (m : String) : appleRuns ev m 0 = false := by
  simp [appleRuns]

/-- Branch dispatch: the macOS leg runs whenever the plan has one. -/
theorem apple_dispatch (m : String) (n : Nat) (hn : n ≠ 0) : appleRuns .dispatch m n = true := by
  simp [appleRuns, hn]

/-- Branch push with the frames token: the macOS leg runs. -/
theorem apple_push_frames (m : String) (n : Nat) (hn : n ≠ 0) (hf : hasFrames m = true) :
    appleRuns .ciPush m n = true := by
  simp [appleRuns, hn, hf]

/-- Branch push whose probe line names a recorder: the macOS leg runs. -/
theorem apple_push_debug (m : String) (n : Nat) (hn : n ≠ 0) (hd : recorderOf m ≠ "") :
    appleRuns .ciPush m n = true := by
  simp [appleRuns, hn, hd]

/-- Branch push with neither the frames token nor a recorder: the macOS leg does not run. -/
theorem apple_push_plain (m : String) (n : Nat) (hf : hasFrames m = false) (hd : recorderOf m = "") :
    appleRuns .ciPush m n = false := by
  simp [appleRuns, hf, hd]

/-- **A push runs the macOS leg only on request.** Each run of a push has the frames token or a recorder in the message. -/
theorem apple_push_asked (m : String) (n : Nat) (h : appleRuns .ciPush m n = true) :
    hasFrames m = true ∨ recorderOf m ≠ "" := by
  simp only [appleRuns, Bool.and_eq_true, Bool.or_eq_true, bne_iff_ne, ne_eq] at h
  exact h.2

/-- Messages the macOS golden decides. -/
def appleMsgs : List String := [
  "ci: measure\n\n[ci:trajectory-probe]",
  "[ci:trajectory-probe]\n[trajectory fw=morph.tween:waapi widths=1280 engines=playwright-webkit debug=nav-transition]",
  "[trajectory debug=nav-transition]",
  "[trajectory debug=root-events]",
  "[trajectory debug=other]",
  "[trajectory fw=a.b:c widths=1280]",
  "[trajectory fw=a.b:c debug=nav-transition debug=nav-transition]",
  "ci: look\n\n[frames:morph.tween:waapi]",
  "ci: look\n\n[Frames:morph.tween:waapi]\n[trajectory debug=nav-transition]",
  "[frames",
  "frames: x"]

/-- One macOS golden line: an event, a message, the number of macOS legs and the decision. -/
def appleLine (ev : ProbeEv) (m : String) (n : Nat) : Json :=
  Json.mkObj [("kind", "apple"), ("event", .str (match ev with | .dispatch => "workflow_dispatch" | .ciPush => "push")),
    ("msg", .str m), ("appleN", .num n), ("run", .bool (appleRuns ev m n))]

/-- All macOS golden lines: each message under both events with two legs and with none. -/
def appleLines (_ : Unit := ()) : List Json :=
  appleMsgs.flatMap fun m => [ProbeEv.dispatch, .ciPush].flatMap fun ev => [2, 0].map fun n => appleLine ev m n

example : appleRuns .ciPush "[trajectory debug=nav-transition]" 2 = true := by decide
example : appleRuns .ciPush "[trajectory debug=other]" 2 = false := by decide
example : appleRuns .ciPush "[ci:trajectory-probe]" 2 = false := by decide
example : appleRuns .ciPush "x [FRAMES:a.b:c]" 2 = true := by decide
example : appleRuns .dispatch "" 2 = true := by decide

/-! The probe golden: messages with their lane flag and the decision. -/

/-- Messages the golden decides. -/
def probeMsgs : List String := [
  "ci: measure\n\n[ci:trajectory-probe]",
  "ci: measure\n\n[ci:trajectory-probe]\n[trajectory fw=hero.exit:scoped widths=390,1280 engines=both]",
  "[trajectory preset=v2-proved]",
  "[trajectory fw=morph.tween:waapi,hero.exit:scoped]\n",
  "[Trajectory FW=morph.tween:waapi]",
  "[TRAJECTORY fw=a.b:c engines=chromium]",
  "[trajectory]",
  "  [trajectory   widths=641  engines=playwright-webkit  ]  ",
  "[trajectory widths=390]\r\nbody",
  "text that quotes [trajectory fw=a.b:c] in the middle",
  "ci: x\n\n    [trajectory fw=a.b:c]",
  "[trajectory fw=a.b:c",
  "[trajectory fw=a.b:c] trailing",
  "[trajectoryfw=a.b:c]",
  "[trajectory fw]",
  "[trajectory fw=]",
  "[trajectory colour=red]",
  "[trajectory fw=a.b:c fw=d.e:f]",
  "[trajectory fw=a.b:c preset=v2-proved]",
  "[trajectory engines=firefox]",
  "[trajectory widths=800]",
  "[trajectory widths=390,390]",
  "[trajectory widths=390,]",
  "[trajectory widths=390,641 diagnostic]",
  "[trajectory widths=390,641]",
  "[trajectory widths=1280,390,640,641]",
  "[trajectory diagnostic]",
  "[trajectory diagnostic widths=800]",
  "[trajectory diagnostic widths=390,390]",
  "[trajectory diagnostic diagnostic]",
  "[trajectory diagnostic=true]",
  "[trajectory fw=a.b:c widths=1280 diagnostic debug=nav-transition]",
  "[trajectory fw=a.b:c;rm]",
  "[trajectory fw=$(x)]",
  "[trajectory fw=a b]",
  "[trajectory fw=a.b:c]\n[trajectory widths=390]",
  "[trajectory fw=a.b:c]\n[trajectory fw=a.b:c]",
  "[trajectory fw=a.b:c]\nsome prose\n[trajectory widths=bad]",
  "[trajectory fw=morph.tween:waapi widths=1280 engines=playwright-webkit debug=nav-transition]",
  "[trajectory debug=nav-transition]",
  "[trajectory fw=morph.tween:waapi debug=nav-transition debug=nav-transition]",
  "[trajectory debug=root-events]",
  "[trajectory debug=other]",
  "[trajectory debug=Nav-Transition]",
  "[trajectory debug=nav-transition,nav-transition]",
  "[trajectory debug=]",
  "[ci:trajectory-probe] [frames:nav:earn-no-transition]\n[trajectory engines=playwright-webkit widths=390,1280]",
  "[ci:trajectory-probe] [frames:nav:earn-no-transition]\n[trajectory widths=390,1280 diagnostic]",
  "[ci:smoothness]\n[trajectory preset=v2-proved widths=390,1280]",
  "[ci:smoothness]\n[trajectory preset=v2-proved widths=390,1280 diagnostic]",
  "[ci:smoothness]\n[trajectory preset=v2-proved diagnostic=true]"]

/-- The JSON of a decision. -/
def pushProbeJson : PushProbe → Json
  | .notAsked => Json.mkObj [("kind", "notAsked")]
  | .needsLane => Json.mkObj [("kind", "needsLane")]
  | .run p => Json.mkObj [("kind", "run"), ("engines", .str p.engines), ("fw", .str p.fw), ("preset", .str p.preset),
      ("widths", .str p.widths), ("debug", .str p.debug), ("diagnostic", .bool p.diagnostic)]
  | .refused w => Json.mkObj [("kind", "refused"), ("why", .str w)]

/-- One probe golden line. -/
def probeLine (wf : ProbeLane) (lane : Bool) (m : String) : Json :=
  Json.mkObj [("kind", "probe"), ("msg", .str m), ("wf", .str wf.name), ("lane", .bool lane),
    ("result", pushProbeJson (pushProbe wf lane m))]

/-- All probe golden lines: each message in each lane (`wf`: trajectory, smoothness, frames) with the lane token asked and not asked. -/
def probeLines (_ : Unit := ()) : List Json :=
  probeMsgs.flatMap fun m => [ProbeLane.trajectory, .smoothness, .frames].flatMap fun wf =>
    [probeLine wf true m, probeLine wf false m]

example : pushProbe .trajectory true "[trajectory fw=a.b:c widths=390 diagnostic]" = .run ⟨"both", "a.b:c", "", "390", "", true⟩ := by decide
example : pushProbe .trajectory true "[trajectory debug=nav-transition]" = .run { ProbeIn.default with debug := "nav-transition" } := by decide
example : pushProbe .trajectory true "[trajectory debug=root-events]" = .run { ProbeIn.default with debug := "root-events" } := by decide
example : pushProbe .trajectory true "[trajectory debug=other]" = .refused "debug must be nav-transition or root-events" := by decide
example : pushProbe .trajectory true "x [trajectory fw=a.b:c]" = .run ProbeIn.default := by decide
example : pushProbe .trajectory false "[trajectory fw=a.b:c]" = .needsLane := by decide
example : pushProbe .trajectory true "[trajectory fw=a preset=b]" = .refused "fw and preset are exclusive" := by decide
example : pushProbe .trajectory true "[trajectory fw=a.b:c" = .refused "the line has no closing ']'" := by decide

/-- The replay cases: each is (name, diff, the paths that already equal `main`); the workflows it starts under the
sample cones are added by `caseLine`. -/
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
static push filter passes the diff. -/
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

/-- The text of the golden file: one JSON object per line for the table, the cases, the `if:` forms and the `if:`
checks. -/
def goldenText (_ : Unit := ()) : String :=
  String.join ((tableLine :: cases.map caseLine ++ ifOrigs.map ifFormLine ++ ifTexts.map ifCheckLine ++ pinLines ++ probeLines () ++ appleLines ()).map
    fun j => j.compress ++ "\n")

/-- Compare (or write) the golden file; returns the number of stale files. -/
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
