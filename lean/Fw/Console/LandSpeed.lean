import Lean.Data.Json
import Fw.Console.Land
import Fw.Ops.PathCheck
/-!
# Why the `fw land` speed-ups keep the land verdict

Spec for the land speed-ups of `research/notes/2026/10-18-land-speed.md` (P2-P5): what each faster path must keep
equal to the slow one, and the empirical premises it relies on.

* **(a) Result cache.** A check that reads only its declared inputs can be replayed from a key hit
  (`cache_sound`, `cachedRun_eq`, `integrity_push`); a skipped check (`checksFor` selects none of its declared inputs)
  keeps its verdict (`skip_sound`). Collision-freeness of the digest is an explicit premise (`NoCollision`).
* **(c) Pre-lock checking.** Checking `merge(main₀, tip)` before the lock and fast-forwarding under the lock decides
  exactly what today's protocol decides iff `HEAD = main₀` at commit time (`pre_eq_old`, `pre_moved`,
  `preLand_eq_old`), and the commit it makes is the one `Fw.Console.Land.land_commit_exact` describes
  (`preLand_commit_exact`).
* **(d) Check verdict.** The verdict is a conjunction: sequential = parallel for non-interfering jobs
  (`seq_eq_all`), independent of job order (`all_perm`) and of completion order (`verdict_perm`), and it passes iff
  every job passed (`verdict_jobs_pass_iff`).

Golden vectors: `packages/contracts/golden/console/land-speed.jsonl` (`goldenText`; ops `landSpeed.select`,
`landSpeed.prelock`, `landSpeed.verdict`, `landSpeed.cache`, `landSpeed.seedDue`, `landSpeed.seedLag`, and the
premise rows `landSpeed.premise`).
Generated with it: `apps/runner/src/land-reads.gen.ts` (`readsTs`) and `golden/console/land-scope-regs.jsonl`
(`regText`). Write or check all three with `lake env lean --run scripts/LandReadsGen.lean --write | --check` from `lean/`.

The empirical premises are listed in `premises` (id, statement, theorems, test).
-/
namespace Fw.Console.LandSpeed
open Fw.Ops.PathCheck

/-! ## (a) Result cache: a check that reads only its declared inputs can be replayed from a key hit -/

/-- A repo path. -/
abbrev Path := String
/-- A file's content, as its blob id. -/
abbrev Blob := Nat
/-- A file-system state: every path's content (absent files have a fixed blob). -/
abbrev St := Path → Blob

/-- A check: an id, the paths it declares it reads (its own program and toolchain included), and its result. -/
structure Check (R : Type) where
  id : String
  reads : List Path
  run : St → R

/-- **Empirical premise `land.readsOnly` (E1).** The check is a function of its declared inputs: two states that
agree on them give the same result. -/
def ReadsOnly {R} (c : Check R) : Prop :=
  ∀ σ σ' : St, (∀ p ∈ c.reads, σ p = σ' p) → c.run σ = c.run σ'

/-- The key: the check id, then each declared path with its blob. -/
def key {R} (c : Check R) (σ : St) : String × List (Path × Blob) := (c.id, c.reads.map (fun p => (p, σ p)))

/-- Equal keys mean the two states agree on every declared input. -/
theorem key_agree {R} (c : Check R) (σ σ' : St) (h : key c σ = key c σ') : ∀ p ∈ c.reads, σ p = σ' p := by
  intro p hp
  have h2 := congrArg Prod.snd h
  simp only [key] at h2
  have := (List.map_inj_left.mp h2) p hp
  simpa using this

/-- **Assumption `land.noCollision` (A1), not a theorem.** The stored digest (sha256 of the canonical encoding) has
no collision on the keys it is applied to. -/
def NoCollision (dig : String × List (Path × Blob) → Nat) : Prop := ∀ k k', dig k = dig k' → k = k'

/-- **Cache soundness.** If the check reads only its declared inputs and the digest has no collision, a digest hit
replays exactly the result a fresh run would give. -/
theorem cache_sound {R} (c : Check R) (dig : String × List (Path × Blob) → Nat) (hro : ReadsOnly c)
    (hinj : NoCollision dig) (σ0 σ : St) (hk : dig (key c σ0) = dig (key c σ)) : c.run σ0 = c.run σ :=
  hro σ0 σ (key_agree c σ0 σ (hinj _ _ hk))

/-- A hit names a stored pair (the first one with that key). -/
theorem lookup_mem {α β} [BEq α] [LawfulBEq α] :
    ∀ (S : List (α × β)) (k : α) (r : β), S.lookup k = some r → (k, r) ∈ S
  | [], _, _, h => by simp [List.lookup] at h
  | (a, b) :: S, k, r, h => by
    by_cases hk : k = a
    · subst hk; simp [List.lookup] at h; subst h; simp
    · have : (k == a) = false := by simpa using hk
      simp [List.lookup, this] at h
      exact List.mem_cons_of_mem _ (lookup_mem S k r h)

/-- A store: a list of (digest, result) entries, newest first. -/
abbrev Store (R : Type) := List (Nat × R)

/-- **Store integrity (I1).** Every entry was written by a real run of this check under its key. -/
def Integrity {R} (c : Check R) (dig : String × List (Path × Blob) → Nat) (S : Store R) : Prop :=
  ∀ e ∈ S, ∃ σ0 : St, e.1 = dig (key c σ0) ∧ e.2 = c.run σ0

/-- Run through the store: replay the first entry with this digest on a hit, run on a miss. -/
def cachedRun {R} (c : Check R) (dig : String × List (Path × Blob) → Nat) (S : Store R) (σ : St) : R :=
  match S.lookup (dig (key c σ)) with
  | some r => r
  | none => c.run σ

/-- **The cached run equals a fresh run** for an intact store. -/
theorem cachedRun_eq {R} (c : Check R) (dig : String × List (Path × Blob) → Nat) (S : Store R) (σ : St)
    (hro : ReadsOnly c) (hinj : NoCollision dig) (hS : Integrity c dig S) : cachedRun c dig S σ = c.run σ := by
  unfold cachedRun
  split
  · rename_i r hr
    have hm : (dig (key c σ), r) ∈ S := lookup_mem _ _ _ hr
    obtain ⟨σ0, hd, hr0⟩ := hS _ hm
    simp only at hd hr0
    rw [hr0]
    exact cache_sound c dig hro hinj σ0 σ hd.symm
  · rfl

/-- Storing a fresh run keeps the store intact. -/
theorem integrity_push {R} (c : Check R) (dig : String × List (Path × Blob) → Nat) (S : Store R) (σ : St)
    (hS : Integrity c dig S) : Integrity c dig ((dig (key c σ), c.run σ) :: S) := by
  intro e he
  rcases List.mem_cons.mp he with h | h
  · exact ⟨σ, by rw [h], by rw [h]⟩
  · exact hS e h

/-- **Mutation witness.** If a path the check really depends on is left undeclared, there are two states with equal
keys and different results, so (E1) is false and the test that mutates that path catches it. -/
theorem undeclared_refutes {R} (c : Check R) (σ σ' : St) (hk : key c σ = key c σ') (hne : c.run σ ≠ c.run σ') :
    ¬ ReadsOnly c := fun hro => hne (hro σ σ' (key_agree c σ σ' hk))

/-- The cache decision the land runner makes for a check: the first stored verdict with this digest, or none (run it). -/
def cacheHit (S : Store Bool) (d : Nat) : Option Bool := S.lookup d

#guard cacheHit [(7, true), (9, false)] 9 == some false
#guard cacheHit [(7, true), (7, false)] 7 == some true
#guard cacheHit [(7, true)] 8 == none
#guard cacheHit [] 0 == none

/-! ### Check selection (`checksFor`): a skipped check is a replayed pass -/

/-- A check as `checksFor` declares it: its id and the globs of every path it reads (PathCheck glob semantics;
`!` excludes). -/
structure Decl where
  id : String
  reads : List String
deriving Repr, DecidableEq

/-- Is the check selected for this change? Some changed path is in the scope of its declared globs (so an empty
change selects nothing). -/
def selected (G changed : List String) : Bool := changed.any (inScope (parseScope G))

/-- The ids of the selected checks, in table order. -/
def selectChecks (ds : List Decl) (changed : List String) : List String :=
  (ds.filter (fun d => selected d.reads changed)).map (·.id)

/-- **Empirical premise `land.readsWithin`** (E1 for globs): the check's result depends only on paths in the scope
of its declared globs. -/
def ReadsWithin {R} (run : St → R) (G : List String) : Prop :=
  ∀ σ σ' : St, (∀ p, inScope (parseScope G) p = true → σ p = σ' p) → run σ = run σ'

/-- Exact declared paths covered by globs give the glob premise. -/
theorem readsOnly_within {R} (c : Check R) (G : List String) (hro : ReadsOnly c)
    (hcov : ∀ p ∈ c.reads, inScope (parseScope G) p = true) : ReadsWithin c.run G :=
  fun σ σ' h => hro σ σ' (fun p hp => h p (hcov p hp))

/-- A changed path in the declared scope selects the check (so an undeclared-input test is a scope test). -/
theorem selected_of_mem (G changed : List String) (x : String) (hx : x ∈ changed)
    (hin : inScope (parseScope G) x = true) : selected G changed = true := by
  simp only [selected, List.any_eq_true]
  exact ⟨x, hx, hin⟩

/-- **Skip soundness.** If the check reads only within its declared globs and no changed path is in their scope,
then its result on the new state equals its result on the old one (the states differ only on changed paths), so
skipping it replays its last verdict exactly. -/
theorem skip_sound {R} (run : St → R) (G changed : List String) (hrw : ReadsWithin run G)
    (hs : selected G changed = false) (σ σ' : St) (hd : ∀ p, p ∉ changed → σ p = σ' p) : run σ = run σ' := by
  apply hrw
  intro p hp
  apply hd
  intro hm
  rw [selected_of_mem G changed p hm hp] at hs
  exact Bool.noConfusion hs

/-- Membership in the selection, unfolded. -/
theorem mem_selectChecks (ds : List Decl) (changed : List String) (i : String) :
    i ∈ selectChecks ds changed ↔ ∃ d ∈ ds, selected d.reads changed = true ∧ d.id = i := by
  simp [selectChecks, and_assoc]

/-- The declared reads proposed for `lean/scripts/check.sh` (P5): `lean/**` plus what it reads outside `lean/`
(the golden files `lake test` replays, the site's generated breakpoint files, the gate's generated scope file that
`sweepsgen --scope --check` compares, the workflow files the lane lint of `Fw.Ops.Premise` reads, the span helper, the fwcore build helper,
the incident ledger that `scripts/PropsLint.lean` matches the registry rows against, and the findings ledger, the parts
and the site preset that `Fw.Preset.Gen.run ["--check"]` regenerates the v2-proved preset from and compares, and the
generated TS copy of this list that `checkGolden` compares, and the generated gh bounds that the timing golden check compares). `checksfor-inputs` owns the final list. -/
def checkShReads : List String :=
  ["lean/**", "packages/contracts/golden/**", "apps/site/src/breakpoints.gen.json",
    "apps/site/src/sweeps.gen.json", "apps/site/src/head.gen.json", "packages/gate-breakpoints/src/scope.gen.json", ".github/workflows/**",
    "scripts/span.sh", "scripts/lint-check-sh.mjs", "scripts/fwcore-build.sh", "scripts/fwcore-record-rule.sh", "scripts/lake-slot.sh", "scripts/lake-slot-lib.sh", "scripts/heavy-lock.mjs", "scripts/slot-self.mjs", "docs/team/incidents/ledger.json", "research/findings/ledger.json",
    "apps/site/src/parts/**", "apps/site/src/registry/presets/v2-proved.json", "apps/site/src/registry/layer-opts.gen.ts",
    "packages/measure-chromium/scenarios.gen.json", "apps/runner/src/land-reads.gen.ts",
    "packages/contracts/fixtures/trajectory-gpu/**", "packages/gate-breakpoints/src/trajectory/cells-gpu-cli.mjs",
    "packages/gh-budget/src/bounds.gen.ts", "results/gpu-safari/lane/elapsed.golden.jsonl",
    "results/dormant-counts/zones.json"]

def sampleDecls : List Decl :=
  [⟨"check.sh", checkShReads⟩, ⟨"contracts", ["packages/contracts/**"]⟩]

#guard selectChecks sampleDecls ["packages/contracts/golden/obs/timing.jsonl"] == ["check.sh", "contracts"]
#guard selectChecks sampleDecls ["lean/Fw/Console/Land.lean"] == ["check.sh"]
#guard selectChecks sampleDecls ["docs/team/handoffs/x.md"] == []
#guard selectChecks sampleDecls [] == []
#guard selectChecks sampleDecls ["apps/site/src/breakpoints.gen.json"] == ["check.sh"]
#guard selectChecks sampleDecls ["packages/gate-breakpoints/src/scope.gen.json"] == ["check.sh"]
#guard selectChecks sampleDecls ["packages/gate-breakpoints/src/scope.mjs"] == []
#guard selectChecks sampleDecls [".github/workflows/lean.yml"] == ["check.sh"]
#guard selectChecks sampleDecls [".github/scripts/changed-inputs.mjs"] == []
#guard selectChecks [⟨"lean", ["lean/**", "!lean/math.lock.json"]⟩] ["lean/math.lock.json"] == []
#guard selectChecks sampleDecls ["../lean/x.lean"] == []
#guard selectChecks sampleDecls ["docs/team/incidents/ledger.json"] == ["check.sh"]
#guard selectChecks sampleDecls ["docs/team/incidents/other.json"] == []
#guard selectChecks sampleDecls ["research/findings/ledger.json"] == ["check.sh"]
#guard selectChecks sampleDecls ["apps/site/src/parts/nav.hitTest/part.json"] == ["check.sh"]
#guard selectChecks sampleDecls ["apps/site/src/registry/presets/original.json"] == []

/-- The parsed check.sh scope: each declared glob split at `/`, and no exclusions. -/
theorem parseScope_checkShReads : parseScope checkShReads =
    ⟨[["lean", "**"], ["packages", "contracts", "golden", "**"], ["apps", "site", "src", "breakpoints.gen.json"],
      ["apps", "site", "src", "sweeps.gen.json"], ["apps", "site", "src", "head.gen.json"], ["packages", "gate-breakpoints", "src", "scope.gen.json"],
      [".github", "workflows", "**"], ["scripts", "span.sh"], ["scripts", "lint-check-sh.mjs"], ["scripts", "fwcore-build.sh"], ["scripts", "fwcore-record-rule.sh"], ["scripts", "lake-slot.sh"], ["scripts", "lake-slot-lib.sh"], ["scripts", "heavy-lock.mjs"], ["scripts", "slot-self.mjs"],
      ["docs", "team", "incidents", "ledger.json"],
      ["research", "findings", "ledger.json"], ["apps", "site", "src", "parts", "**"],
      ["apps", "site", "src", "registry", "presets", "v2-proved.json"], ["apps", "site", "src", "registry", "layer-opts.gen.ts"],
      ["packages", "measure-chromium", "scenarios.gen.json"], ["apps", "runner", "src", "land-reads.gen.ts"],
      ["packages", "contracts", "fixtures", "trajectory-gpu", "**"], ["packages", "gate-breakpoints", "src", "trajectory", "cells-gpu-cli.mjs"],
      ["packages", "gh-budget", "src", "bounds.gen.ts"], ["results", "gpu-safari", "lane", "elapsed.golden.jsonl"],
      ["results", "dormant-counts", "zones.json"]], []⟩ := by
  have hi : checkShReads.filter (!·.startsWith "!") = checkShReads := by
    simp (config := {decide := true}) [checkShReads]
  have he : checkShReads.filter (·.startsWith "!") = [] := by
    simp (config := {decide := true}) [checkShReads]
  rw [parseScope, hi, he]
  simp only [List.map_nil, checkShReads, List.map_cons, Scope.mk.injEq, List.cons.injEq, and_true]
  and_intros <;> simp (config := {decide := true}) [segs, String.splitOn, String.splitOnAux]

/-- check.sh is selected whenever some changed path is in the parsed check.sh scope, in any check table `D`
holding the check `check.sh` with reads `G_check`. -/
theorem checkSh_selected_of_inScope (ds : List Decl) (changed : List String) (x : String)
    (hd : (⟨"check.sh", checkShReads⟩ : Decl) ∈ ds) (hx : x ∈ changed)
    (hin : inScope (parseScope checkShReads) x = true) :
    "check.sh" ∈ selectChecks ds changed :=
  (mem_selectChecks ds changed _).2 ⟨_, hd, List.any_eq_true.2 ⟨x, hx, hin⟩, rfl⟩

/-- A change to the gate's generated scope file (which `sweepsgen --scope --check` in `check.sh` reads) selects
`check.sh`: for every check table `D` holding the check `check.sh` with reads `G_check`, every change list
`X` and every changed path `x ∈ X` whose segments (split at `/`, empty and `.` segments dropped) equal those of
`packages/gate-breakpoints/src/scope.gen.json`. -/
theorem scopeGen_selects_checkSh (ds : List Decl) (changed : List String) (x : String)
    (hd : (⟨"check.sh", checkShReads⟩ : Decl) ∈ ds) (hx : x ∈ changed)
    (hs : segs x = ["packages", "gate-breakpoints", "src", "scope.gen.json"]) :
    "check.sh" ∈ selectChecks ds changed := by
  refine checkSh_selected_of_inScope ds changed x hd hx ?_
  rw [inScope_iff, parseScope_checkShReads, hs]
  refine ⟨by simp, by simp, ⟨["packages", "gate-breakpoints", "src", "scope.gen.json"], by simp, ?_⟩, by simp⟩
  exact matchesPath_lit _ (by simp) (by simp (config := {decide := true}))

/-- A change to a workflow file (which the lane lint of `Fw.Ops.Premise`, run by `check.sh`, reads) selects
`check.sh`: for every check table `D` holding the check `check.sh` with reads `G_check`, every change list
`X` and every changed path `x ∈ X` whose segments start with `.github`, `workflows` and whose remaining segments
`r` (possibly none) hold no `..`. -/
theorem workflow_selects_checkSh (ds : List Decl) (changed : List String) (x : String) (r : List String)
    (hd : (⟨"check.sh", checkShReads⟩ : Decl) ∈ ds) (hx : x ∈ changed)
    (hs : segs x = ".github" :: "workflows" :: r) (hr : ".." ∉ r) :
    "check.sh" ∈ selectChecks ds changed := by
  refine checkSh_selected_of_inScope ds changed x hd hx ?_
  rw [inScope_iff, parseScope_checkShReads, hs]
  refine ⟨by simp, by simpa using hr, ⟨[".github", "workflows", "**"], by simp, ?_⟩, by simp⟩
  have h2 : matchesPath [".github", "workflows", "**"] [".github", "workflows"] = true := by
    simp [matchesPath, globMatch, segMatch, List.range_succ]
  simpa using matchesPath_append _ _ r h2

/-! ### The read-set scan: selected by every change a check can read -/

/-- The id of the static read-set scan (`apps/runner` `test/land-inputs.test.ts`, premise `land.readsOnly`). -/
def scanId : String := "reads-scan"

/-- The inclusion globs of a declared read list (exclusions dropped, so the scan over-approximates). -/
def posGlobs (G : List String) : List String := G.filter (!·.startsWith "!")

/-- The scan's own reads: every inclusion glob any check of the table declares (package sources, extra reads, lock files). -/
def scanReads (ds : List Decl) : List String := ds.flatMap (fun d => posGlobs d.reads)

/-- The table with the scan appended as its own cheap check. -/
def withScan (ds : List Decl) : List Decl := ds ++ [⟨scanId, scanReads ds⟩]

/-- Every glob of the scan reads is an inclusion. -/
theorem scanReads_no_excl (ds : List Decl) : ∀ g ∈ scanReads ds, g.startsWith "!" = false := by
  intro g hg
  simp only [scanReads, posGlobs, List.mem_flatMap, List.mem_filter] at hg
  obtain ⟨_, _, h⟩ := hg
  simpa using h.2

/-- A path in the scope of any declared check is in the scope of the scan. -/
theorem inScope_scanReads (ds : List Decl) (d : Decl) (hd : d ∈ ds) (x : String)
    (h : inScope (parseScope d.reads) x = true) : inScope (parseScope (scanReads ds)) x = true := by
  rw [inScope_iff] at h ⊢
  obtain ⟨h1, h2, ⟨g, hg, hm⟩, _⟩ := h
  refine ⟨h1, h2, ⟨g, ?_, hm⟩, ?_⟩
  · simp only [parseScope, List.mem_map, List.mem_filter] at hg ⊢
    obtain ⟨s, hs, rfl⟩ := hg
    refine ⟨s, ⟨?_, hs.2⟩, rfl⟩
    simp only [scanReads, posGlobs, List.mem_flatMap, List.mem_filter]
    exact ⟨d, hd, hs.1, hs.2⟩
  · intro g hg
    simp only [parseScope, List.mem_map, List.mem_filter] at hg
    obtain ⟨s, ⟨hs, hb⟩, _⟩ := hg
    have := scanReads_no_excl ds s hs
    simp_all

/-- **Selection soundness of the read-set scan.** If any changed path lies in the scope of any check's declared reads
(package sources included), the scan is selected: a land that changes only `apps/site` still runs it. -/
theorem scan_selected (ds : List Decl) (changed : List String) (d : Decl) (hd : d ∈ ds) (x : String)
    (hx : x ∈ changed) (hin : inScope (parseScope d.reads) x = true) :
    scanId ∈ selectChecks (withScan ds) changed :=
  (mem_selectChecks _ _ _).2 ⟨⟨scanId, scanReads ds⟩, by simp [withScan],
    List.any_eq_true.2 ⟨x, hx, inScope_scanReads ds d hd x hin⟩, rfl⟩

/-- Precision: if no table check has the scan's id and no changed path lies in the scope of the scan's reads, the scan is not selected. -/
theorem scan_not_selected (ds : List Decl) (changed : List String)
    (hid : ∀ d ∈ ds, d.id ≠ scanId)
    (h : ∀ x ∈ changed, inScope (parseScope (scanReads ds)) x = false) :
    scanId ∉ selectChecks (withScan ds) changed := by
  intro hm
  obtain ⟨d, hd, hsel, hid'⟩ := (mem_selectChecks _ _ _).1 hm
  simp only [withScan, List.mem_append, List.mem_singleton] at hd
  rcases hd with hd | rfl
  · exact hid d hd hid'
  · obtain ⟨x, hx, hx'⟩ := List.any_eq_true.1 hsel
    simp [h x hx] at hx'

/-- The sample table with a site package check and the scan. -/
def scanDecls : List Decl := withScan (sampleDecls ++ [⟨"site", ["apps/site/**"]⟩])

#guard selectChecks scanDecls ["apps/site/src/x.ts"] == ["site", "reads-scan"]
#guard selectChecks scanDecls ["docs/team/handoffs/x.md"] == []
#guard selectChecks scanDecls ["packages/contracts/golden/obs/timing.jsonl"] == ["check.sh", "contracts", "reads-scan"]

/-! ### Two-phase selection: the fwcore users follow the binary digest -/

/-- The path that stands for the stripped fwcore binary in a check's declared reads. -/
def fwcoreBin : String := "lean/.lake/build/bin/fwcore"

/-- The tracked paths the binary's bytes depend on; the build slot's files are left out (premise `land.binaryOfLean`). -/
def fwcoreBuildReads : List String := ["lean/**", "scripts/fwcore-build.sh", "scripts/fwcore-record-rule.sh"]

/-- Two binary digests (`none`: unknown) that do not show one binary. -/
def digestDiffers : Option String → Option String → Bool
  | some a, some b => a != b
  | _, _ => true

/-- Did the binary move between main₀ (`d0`) and the merge tree (`d1`): the change reaches the build and the digests differ or one is unknown. -/
def binMoved (changed : List String) (d0 d1 : Option String) : Bool :=
  selected fwcoreBuildReads changed && digestDiffers d0 d1

/-- The phase-2 change: the changed paths, plus `fwcoreBin` when the binary moved. -/
def withBin (changed : List String) (d0 d1 : Option String) : List String :=
  if binMoved changed d0 d1 then changed ++ [fwcoreBin] else changed

/-- The two-phase selection: `selectChecks` over the phase-2 change. -/
def selectTwoPhase (ds : List Decl) (changed : List String) (d0 d1 : Option String) : List String :=
  selectChecks ds (withBin changed d0 d1)

theorem binMoved_unbuilt (changed : List String) (d0 d1 : Option String)
    (h : selected fwcoreBuildReads changed = false) : binMoved changed d0 d1 = false := by
  simp [binMoved, h]

theorem binMoved_main_unknown (changed : List String) (d1 : Option String)
    (h : selected fwcoreBuildReads changed = true) : binMoved changed none d1 = true := by
  simp [binMoved, h, digestDiffers]

theorem binMoved_merge_unknown (changed : List String) (d0 : Option String)
    (h : selected fwcoreBuildReads changed = true) : binMoved changed d0 none = true := by
  cases d0 <;> simp [binMoved, h, digestDiffers]

theorem binMoved_differ (changed : List String) (a b : String)
    (h : selected fwcoreBuildReads changed = true) (hab : a ≠ b) : binMoved changed (some a) (some b) = true := by
  simp [binMoved, h, digestDiffers, hab]

theorem binMoved_same (changed : List String) (a : String) : binMoved changed (some a) (some a) = false := by
  simp [binMoved, digestDiffers]

theorem binMoved_iff (changed : List String) (d0 d1 : Option String) :
    binMoved changed d0 d1 = true ↔ selected fwcoreBuildReads changed = true ∧ ¬ ∃ a, d0 = some a ∧ d1 = some a := by
  cases d0 <;> cases d1 <;> simp [binMoved, digestDiffers]
  exact fun _ => not_congr eq_comm

theorem withBin_unmoved (changed : List String) (d0 d1 : Option String) (h : binMoved changed d0 d1 = false) :
    withBin changed d0 d1 = changed := by
  simp [withBin, h]

theorem selectTwoPhase_same (ds : List Decl) (changed : List String) (a : String) :
    selectTwoPhase ds changed (some a) (some a) = selectChecks ds changed := by
  simp [selectTwoPhase, withBin_unmoved _ _ _ (binMoved_same changed a)]

theorem user_selected_of_moved (ds : List Decl) (changed : List String) (d0 d1 : Option String) (d : Decl)
    (hd : d ∈ ds) (hbin : inScope (parseScope d.reads) fwcoreBin = true) (hm : binMoved changed d0 d1 = true) :
    d.id ∈ selectTwoPhase ds changed d0 d1 := by
  refine (mem_selectChecks _ _ _).2 ⟨d, hd, selected_of_mem _ _ fwcoreBin ?_ hbin, rfl⟩
  simp [withBin, hm]

/-- **Empirical premise `land.binaryOfLean`**: the build maps a state to the binary it writes, and two states that agree on
the paths of `fwcoreBuildReads` (the binary itself aside) build the same binary. -/
def BinaryOfBuildReads (build : St → Blob) : Prop :=
  ∀ σ σ' : St, (∀ p, p ≠ fwcoreBin → inScope (parseScope fwcoreBuildReads) p = true → σ p = σ' p) → build σ = build σ'

theorem fwcore_digest_skip {R} (run : St → R) (G changed : List String) (hrw : ReadsWithin run G) (a : String)
    (hs : selected G changed = false) (dig : Blob → String) (hinj : ∀ x y, dig x = dig y → x = y) (σ σ' : St)
    (hd : ∀ p, p ∉ changed → p ≠ fwcoreBin → σ p = σ' p) (h0 : dig (σ fwcoreBin) = a) (h1 : dig (σ' fwcoreBin) = a) :
    selected G (withBin changed (some a) (some a)) = false ∧ run σ = run σ' := by
  rw [withBin_unmoved _ _ _ (binMoved_same changed a)]
  refine ⟨hs, skip_sound run G changed hrw hs σ σ' fun p hp => ?_⟩
  by_cases hb : p = fwcoreBin
  · subst hb; exact hinj _ _ (h0.trans h1.symm)
  · exact hd p hp hb

theorem fwcore_nobuild_skip {R} (run : St → R) (G changed : List String) (hrw : ReadsWithin run G)
    (d0 d1 : Option String) (hs : selected G changed = false) (hnb : selected fwcoreBuildReads changed = false)
    (build : St → Blob) (hbin : BinaryOfBuildReads build) (σ σ' : St) (hb : σ fwcoreBin = build σ)
    (hb' : σ' fwcoreBin = build σ') (hd : ∀ p, p ∉ changed → p ≠ fwcoreBin → σ p = σ' p) :
    selected G (withBin changed d0 d1) = false ∧ run σ = run σ' := by
  rw [withBin_unmoved _ _ _ (binMoved_unbuilt changed d0 d1 hnb)]
  refine ⟨hs, skip_sound run G changed hrw hs σ σ' fun p hp => ?_⟩
  by_cases hp' : p = fwcoreBin
  · subst hp'
    rw [hb, hb']
    refine hbin σ σ' fun q hq hin => hd q (fun hm => ?_) hq
    rw [selected_of_mem _ _ q hm hin] at hnb
    exact Bool.noConfusion hnb
  · exact hd p hp hp'

theorem leanFw_inScope : inScope (parseScope fwcoreBuildReads) "lean/Fw.lean" = true := by
  have hp : segs "lean/Fw.lean" = ["lean", "Fw.lean"] := by
    simp (config := {decide := true}) [segs, String.splitOn, String.splitOnAux]
  have hg : segs "lean/**" = ["lean", "**"] := by
    simp (config := {decide := true}) [segs, String.splitOn, String.splitOnAux]
  have hs : segs "scripts/fwcore-build.sh" = ["scripts", "fwcore-build.sh"] := by
    simp (config := {decide := true}) [segs, String.splitOn, String.splitOnAux]
  have hr : segs "scripts/fwcore-record-rule.sh" = ["scripts", "fwcore-record-rule.sh"] := by
    simp (config := {decide := true}) [segs, String.splitOn, String.splitOnAux]
  have h1 : "lean/**".startsWith "!" = false := by simp
  have h2 : "scripts/fwcore-build.sh".startsWith "!" = false := by simp
  have h3 : "scripts/fwcore-record-rule.sh".startsWith "!" = false := by simp
  have hm : matchesPath ["lean", "**"] ["lean", "Fw.lean"] = true := by
    simp only [matchesPath, List.any_eq_true, List.mem_range]
    exact ⟨1, by decide, by simp [globMatch, segMatch_lit]⟩
  simp [inScope, parseScope, fwcoreBuildReads, h1, h2, h3, hp, hg, hs, hr, hm]

/-- A build that copies one Lean source into the binary. -/
def copyBuild : St → Blob := fun σ => σ "lean/Fw.lean"

theorem copyBuild_binaryOfBuildReads : BinaryOfBuildReads copyBuild :=
  fun _ _ h => h "lean/Fw.lean" (by decide) leanFw_inScope

theorem binaryOfBuildReads_satisfiable :
    ∃ build : St → Blob, BinaryOfBuildReads build ∧
      ∃ σ σ' : St, σ fwcoreBin = build σ ∧ σ' fwcoreBin = build σ' ∧ build σ ≠ build σ' :=
  ⟨copyBuild, copyBuild_binaryOfBuildReads, fun p => if p = fwcoreBin ∨ p = "lean/Fw.lean" then 1 else 0,
    fun _ => 0, by decide, by decide, by decide⟩

example : (fun σ : St => σ fwcoreBin) (fun p => if p = fwcoreBin ∨ p = "lean/Fw.lean" then 1 else 0)
    = (fun σ : St => σ fwcoreBin) (fun p => if p = fwcoreBin ∨ p = "lean/Fw.lean" ∨ p = "docs/x.md" then 1 else 0) := by
  have hb : segs fwcoreBin = ["lean", ".lake", "build", "bin", "fwcore"] := by
    simp (config := {decide := true}) [fwcoreBin, segs, String.splitOn, String.splitOnAux]
  have hx : segs "docs/x.md" = ["docs", "x.md"] := by
    simp (config := {decide := true}) [segs, String.splitOn, String.splitOnAux]
  have hg : segs "lean/**" = ["lean", "**"] := by
    simp (config := {decide := true}) [segs, String.splitOn, String.splitOnAux]
  have hs : segs "scripts/fwcore-build.sh" = ["scripts", "fwcore-build.sh"] := by
    simp (config := {decide := true}) [segs, String.splitOn, String.splitOnAux]
  have hr : segs "scripts/fwcore-record-rule.sh" = ["scripts", "fwcore-record-rule.sh"] := by
    simp (config := {decide := true}) [segs, String.splitOn, String.splitOnAux]
  have h0 : fwcoreBin.startsWith "!" = false := by simp [fwcoreBin]
  have h1 : "lean/**".startsWith "!" = false := by simp
  have h2 : "scripts/fwcore-build.sh".startsWith "!" = false := by simp
  have h3 : "scripts/fwcore-record-rule.sh".startsWith "!" = false := by simp
  have hrw : ReadsWithin (fun σ : St => σ fwcoreBin) [fwcoreBin] := fun σ σ' h => h fwcoreBin (by
    have hm : matchesPath (segs fwcoreBin) (segs fwcoreBin) = true := by
      rw [hb]; simp only [matchesPath, List.any_eq_true, List.mem_range]
      exact ⟨4, by decide, by simp [globMatch, segMatch_lit]⟩
    simp [inScope, parseScope, h0, hm]
    rw [hb]; simp)
  refine (fwcore_nobuild_skip (fun σ : St => σ fwcoreBin) [fwcoreBin] ["docs/x.md"] hrw none none ?_ ?_ copyBuild
    copyBuild_binaryOfBuildReads _ _ (by decide) (by decide) ?_).2
  · simp [selected, inScope, parseScope, h0, hb, hx, matchesPath, globMatch, segMatch]
  · simp [selected, inScope, parseScope, fwcoreBuildReads, h1, h2, h3, hg, hs, hr, hx, matchesPath, globMatch, segMatch]
  · intro p hp _
    simp only [List.mem_singleton] at hp
    simp [hp]

/-- The sample table of the two-phase golden cases: check.sh, two fwcore users, a site check and the scan. -/
def binDecls : List Decl :=
  withScan [⟨"check.sh", checkShReads⟩, ⟨"console-api", ["apps/console-api/**", "lean/Fw/Console/PreviewFacts.lean", fwcoreBin]⟩,
    ⟨"difftest", ["packages/difftest/**", fwcoreBin]⟩, ⟨"site", ["apps/site/**"]⟩]

#guard selectTwoPhase binDecls ["lean/Fw/Console/Land.lean"] (some "a") (some "a") == ["check.sh", "reads-scan"]
#guard selectTwoPhase binDecls ["lean/Fw/Console/Land.lean"] (some "a") (some "b") == ["check.sh", "console-api", "difftest", "reads-scan"]
#guard selectTwoPhase binDecls ["lean/Fw/Console/Land.lean"] none (some "a") == ["check.sh", "console-api", "difftest", "reads-scan"]
#guard selectTwoPhase binDecls ["lean/Fw/Console/Land.lean"] (some "a") none == ["check.sh", "console-api", "difftest", "reads-scan"]
#guard selectTwoPhase binDecls ["lean/Fw/Console/PreviewFacts.lean"] (some "a") (some "a") == ["check.sh", "console-api", "reads-scan"]
#guard selectTwoPhase binDecls ["apps/site/src/x.ts"] none none == ["site", "reads-scan"]
#guard selectTwoPhase binDecls ["scripts/fwcore-build.sh"] (some "a") (some "a") == ["check.sh", "reads-scan"]
#guard selectTwoPhase binDecls ["scripts/fwcore-build.sh"] (some "a") (some "b") == ["check.sh", "console-api", "difftest", "reads-scan"]
#guard selectTwoPhase binDecls ["docs/team/handoffs/x.md"] none none == []
#guard binMoved ["lean/x.lean"] (some "a") (some "a") == false
#guard binMoved ["apps/site/x.ts"] (some "a") (some "b") == false

/-! ## (c) Pre-lock checking: check merge(main₀, tip) outside the lock, commit it only if main is still main₀ -/

/-- What the commit step decides. -/
inductive Out where
  | commit (tree : String) (parents : List String)
  | refuse
  | retry
deriving DecidableEq, Repr

/-- The current protocol, seen at the moment the lock is taken with `HEAD = h`: merge, check, commit. -/
def old (merge : String → String → String) (chk : String → Bool) (h b : String) : Out :=
  if chk (merge h b) then .commit (merge h b) [h, b] else .refuse

/-- The pre-lock protocol: `T = merge(main₀, b)` and its verdict `v` were computed before the lock; under the lock only
`HEAD = main₀` is compared, and the precomputed commit is fast-forwarded (`git commit-tree T -p main₀ -p b`, then
`merge --ff-only`): the committed tree is the checked tree by construction. -/
def pre (merge : String → String → String) (m0 : String) (v : Bool) (h b : String) : Out :=
  if h ≠ m0 then .retry else if v then .commit (merge m0 b) [m0, b] else .refuse

/-- **Pre-lock equivalence.** When main is still main₀ at the lock, the pre-lock protocol decides exactly what the
current protocol decides, with `v = χ(μ(m_0, b))` computed earlier (premise `land.checkDeterministic`). -/
theorem pre_eq_old (merge : String → String → String) (chk : String → Bool) (m0 h b : String) (hh : h = m0) :
    pre merge m0 (chk (merge m0 b)) h b = old merge chk h b := by
  subst hh; unfold pre old; by_cases hc : chk (merge h b) <;> simp [hc]

/-- **Fallback.** When main moved, nothing is committed: the land re-checks against the new main or falls back to the
locked protocol (`prelockAction`). -/
theorem pre_moved (merge : String → String → String) (m0 h b : String) (v : Bool) (hh : h ≠ m0) :
    pre merge m0 v h b = .retry := by
  simp [pre, hh]

/-- **Iff.** The pre-lock protocol agrees with the current one exactly when `HEAD = main₀` at commit time (the current
protocol never answers `retry`). -/
theorem pre_eq_old_iff (merge : String → String → String) (chk : String → Bool) (m0 h b : String) :
    pre merge m0 (chk (merge m0 b)) h b = old merge chk h b ↔ h = m0 := by
  constructor
  · intro he
    by_cases hh : h = m0
    · exact hh
    · rw [pre_moved merge m0 h b _ hh] at he
      unfold old at he
      by_cases hc : chk (merge h b) <;> simp [hc] at he
  · exact pre_eq_old merge chk m0 h b

/-- **Checked = committed.** Whatever the pre-lock protocol commits is a tree that passed the checks, on top of the
`HEAD` seen under the lock. -/
theorem pre_commit_checked (merge : String → String → String) (chk : String → Bool) (m0 h b T : String)
    (ps : List String) (hc : pre merge m0 (chk (merge m0 b)) h b = .commit T ps) :
    chk T = true ∧ T = merge h b ∧ ps = [h, b] := by
  unfold pre at hc
  by_cases hh : h ≠ m0
  · simp [hh] at hc
  · have hh' : h = m0 := Classical.byContradiction hh
    subst hh'
    by_cases hv : chk (merge h b) = true
    · simp [hv] at hc; obtain ⟨h1, h2⟩ := hc; subst h1; subst h2; exact ⟨hv, rfl, rfl⟩
    · simp [hv] at hc

/-- **Evidence edit is invisible to the checks** (today's protocol writes `docs/team/work-graph.json` after
checking): if the edited path is not read, the verdict of the committed tree equals the checked one. The pre-lock
protocol applies the edit before checking, so it does not need this premise. -/
theorem evidence_irrelevant {R} (c : Check R) (hro : ReadsOnly c) (σ : St) (p : Path) (w : Blob)
    (hp : p ∉ c.reads) : c.run (fun q => if q = p then w else σ q) = c.run σ :=
  hro _ _ (fun q hq => by
    have : q ≠ p := fun e => hp (e ▸ hq)
    simp [this])

/-! ### On the `Fw.Console.Land` repo model -/

open Fw.Console.Land

/-- Today's land on the repo model: take the lock (`begin`), others act (`es`), then commit the merge if the check
of `merge(main₀, tip)` passes, else abort. -/
def oldLand (merge : String → String → String) (chk : String → Bool) (s : Repo) (tip id task : String)
    (es : List Land.Event) : Repo :=
  let s1 := (Land.step s (.begin tip)).1
  let s2 := Land.run s1 es
  if chk (merge s1.pre tip) then (Land.step s2 (.land id task)).1 else (Land.step s2 .abort).1

/-- The pre-lock land on the repo model: the verdict `v` of `merge(main₀, tip)` is known before the lock; if `HEAD`
is not `main₀` or `v` failed, the lock is never taken and the repo is unchanged; otherwise lock, others act,
fast-forward to the checked commit. -/
def preLand (s : Repo) (m0 : String) (v : Bool) (tip id task : String) (es : List Land.Event) : Repo :=
  if s.head = m0 ∧ v = true then (Land.step (Land.run (Land.step s (.begin tip)).1 es) (.land id task)).1 else s

/-- **Pre-lock land = today's land on main**, when `HEAD = main₀` and the lock is free: same `HEAD`, same log, lock
released. -/
theorem preLand_eq_old (merge : String → String → String) (chk : String → Bool) (s : Repo) (m0 tip id task : String)
    (es : List Land.Event) (hu : s.locked = false) (hs : ∀ e ∈ es, e.safe = true) (hh : s.head = m0) :
    let P := preLand s m0 (chk (merge m0 tip)) tip id task es
    let O := oldLand merge chk s tip id task es
    P.head = O.head ∧ P.log = O.log ∧ P.locked = O.locked := by
  intro P O
  have h1 : (Land.step s (.begin tip)).1 = { s with locked := true, merge := some tip, pre := s.head } := by
    simp [Land.step, hu]
  have hr : Land.run (Land.step s (.begin tip)).1 es = (Land.step s (.begin tip)).1 :=
    run_safe_locked es _ (by simp [h1]) hs
  subst hh
  by_cases hc : chk (merge s.head tip) = true
  · have hP : P = (Land.step (Land.run (Land.step s (.begin tip)).1 es) (.land id task)).1 := by simp [P, preLand, hc]
    have hO : O = (Land.step (Land.run (Land.step s (.begin tip)).1 es) (.land id task)).1 := by
      simp only [O, oldLand]; rw [h1]; simp [hc]
    rw [hP, hO]; exact ⟨rfl, rfl, rfl⟩
  · have hP : P = s := by simp [P, preLand, hc]
    have hO : O = (Land.step (Land.run (Land.step s (.begin tip)).1 es) .abort).1 := by
      simp only [O, oldLand]; rw [h1]; simp [hc]
    rw [hP, hO, hr, h1]
    simp [Land.step, hu]

/-- **The pre-lock commit is `land_commit_exact`'s commit**: with `HEAD = main₀`, a free lock, safe events in the
window and a passing verdict, the new commit has parents (main₀, tip) and the `Task:` trailer, main moves to it and
the lock is released. -/
theorem preLand_commit_exact (s : Repo) (m0 tip id task : String) (es : List Land.Event) (hu : s.locked = false)
    (hs : ∀ e ∈ es, e.safe = true) (hh : s.head = m0) :
    let P := preLand s m0 true tip id task es
    P.log = { id := id, parents := [m0, tip], task := some task } :: s.log ∧ P.head = id ∧ P.locked = false := by
  intro P
  have hP : P = (Land.step (Land.run (Land.step s (.begin tip)).1 es) (.land id task)).1 := by simp [P, preLand, hh]
  rw [hP, ← hh]
  exact land_commit_exact s tip id task es hu hs

/-- **Main moved: nothing happens.** If `HEAD` is not `main₀`, the pre-lock land leaves the repo exactly as it is. -/
theorem preLand_moved (s : Repo) (m0 : String) (v : Bool) (tip id task : String) (es : List Land.Event)
    (hh : s.head ≠ m0) : preLand s m0 v tip id task es = s := by
  simp [preLand, hh]

/-! ### The runner's decision under the lock -/

/-- What the land runner does after taking the lock with a pre-made commit. -/
inductive Action where
  | ff | refuse | recheck | fallback
deriving DecidableEq, Repr

/-- The JSON name of an action. -/
def Action.name : Action → String
  | .ff => "ff" | .refuse => "refuse" | .recheck => "recheck" | .fallback => "fallback"

/-- The decision: if `HEAD` is still `main₀`, fast-forward on a pass and refuse on a fail; if main moved, re-check
against the new main while `attempt < maxRetry` (attempts count from 0), else fall back to the locked protocol. -/
def prelockAction (head m0 : String) (v : Bool) (attempt maxRetry : Nat) : Action :=
  if head = m0 then (if v then .ff else .refuse) else if attempt < maxRetry then .recheck else .fallback

/-- The runner's decision is the `pre` decision: it fast-forwards exactly when `pre` commits and refuses exactly when
`pre` refuses; when main moved, `pre` answers retry. -/
theorem prelockAction_pre (merge : String → String → String) (head m0 b : String) (v : Bool) (a n : Nat) :
    (prelockAction head m0 v a n = .ff ↔ pre merge m0 v head b = .commit (merge m0 b) [m0, b]) ∧
    (prelockAction head m0 v a n = .refuse ↔ pre merge m0 v head b = .refuse) := by
  unfold prelockAction pre
  by_cases hh : head = m0 <;> by_cases hv : v = true <;> by_cases ha : a < n <;> simp [hh, hv, ha]

/-- **Bounded retry.** Once `attempt ≥ maxRetry`, a moved main gives fallback, never another re-check. -/
theorem prelockAction_fallback (head m0 : String) (v : Bool) (a n : Nat) (hh : head ≠ m0) (ha : n ≤ a) :
    prelockAction head m0 v a n = .fallback := by
  simp [prelockAction, hh, Nat.not_lt.mpr ha]

#guard prelockAction "m0" "m0" true 0 3 == .ff
#guard prelockAction "m0" "m0" false 0 3 == .refuse
#guard prelockAction "m1" "m0" true 0 3 == .recheck
#guard prelockAction "m1" "m0" false 2 3 == .recheck
#guard prelockAction "m1" "m0" true 3 3 == .fallback
#guard prelockAction "m1" "m0" true 0 0 == .fallback

/-! ## Pool size under load -/

/-- How many checks may run at once: the cores not taken by other work (`loadCeil` = the one-minute load average rounded up),
at least one. The pool size never changes a verdict (`verdict_perm`); it only changes how many run at the same time. -/
def poolSize (cores loadCeil : Nat) : Nat := max 1 (cores - loadCeil)

/-- The pool is never empty, so a land always makes progress. -/
theorem poolSize_pos (cores loadCeil : Nat) : 1 ≤ poolSize cores loadCeil := by
  unfold poolSize; omega

/-- **Monotone in load.** More load never gives a larger pool. -/
theorem poolSize_anti_load (cores l l' : Nat) (h : l ≤ l') : poolSize cores l' ≤ poolSize cores l := by
  unfold poolSize; omega

/-- **Monotone in cores.** More cores never give a smaller pool. -/
theorem poolSize_mono_cores (c c' l : Nat) (h : c ≤ c') : poolSize c l ≤ poolSize c' l := by
  unfold poolSize; omega

/-- The pool never exceeds the cores (when there is at least one). -/
theorem poolSize_le_cores (cores l : Nat) (hc : 1 ≤ cores) : poolSize cores l ≤ cores := by
  unfold poolSize; omega

#guard poolSize 10 0 == 10
#guard poolSize 10 3 == 7
#guard poolSize 10 23 == 1
#guard poolSize 0 0 == 1
#guard old (· ++ "+" ++ ·) (fun _ => true) "m0" "b" == .commit "m0+b" ["m0", "b"]
#guard pre (· ++ "+" ++ ·) "m0" true "m1" "b" == .retry

/-! ## (d) Parallel checks: non-interfering checks give the same verdict in any order -/

/-- A check with its effect on the state (build outputs, logs) and the paths it writes. -/
structure Job where
  chk : Check Bool
  eff : St → St
  writes : List Path
  frame : ∀ σ p, p ∉ writes → eff σ p = σ p

/-- Run jobs one after another; each check sees the effects of the jobs before it. -/
def seqVerdict : St → List Job → Bool
  | _, [] => true
  | σ, j :: js => j.chk.run σ && seqVerdict (j.eff σ) js

/-- **Empirical premise `land.nonInterfere` (E4).** No job writes a path another job of the same stage reads (for
every pair at different positions of the list). -/
def NonInterfere (js : List Job) : Prop :=
  js.Pairwise (fun a b => (∀ p ∈ a.writes, p ∉ b.chk.reads) ∧ (∀ p ∈ b.writes, p ∉ a.chk.reads))

/-- **Parallel = sequential.** For read-only, non-interfering jobs the sequential verdict is the conjunction of the
verdicts each job gets on the start state, so running them at once gives the same verdict. -/
theorem seq_eq_all (js : List Job) (hro : ∀ j ∈ js, ReadsOnly j.chk) (hni : NonInterfere js) :
    ∀ σ, seqVerdict σ js = js.all (fun j => j.chk.run σ) := by
  induction js with
  | nil => intro σ; rfl
  | cons j js ih =>
    intro σ
    have hni' := List.pairwise_cons.mp hni
    simp only [seqVerdict, List.all_cons]
    rw [ih (fun k hk => hro k (by simp [hk])) hni'.2 (j.eff σ)]
    have e : ∀ k ∈ js, k.chk.run (j.eff σ) = k.chk.run σ := by
      intro k hk
      apply hro k (by simp [hk])
      intro p hp
      apply j.frame
      intro hw
      exact (hni'.1 k hk).1 p hw hp
    have hall : js.all (fun k => k.chk.run (j.eff σ)) = js.all (fun k => k.chk.run σ) := by
      rw [Bool.eq_iff_iff]; simp only [List.all_eq_true]
      exact ⟨fun h k hk => (e k hk) ▸ h k hk, fun h k hk => (e k hk).symm ▸ h k hk⟩
    rw [hall]

/-- **Order independence.** The conjunction does not depend on the order of the jobs. -/
theorem all_perm (js js' : List Job) (hp : js.Perm js') (σ : St) :
    js.all (fun j => j.chk.run σ) = js'.all (fun j => j.chk.run σ) := by
  rw [Bool.eq_iff_iff]
  simp [List.all_eq_true, hp.mem_iff]

/-! ### The runner's verdict over completions -/

/-- The overall verdict of a stage: pass, the failed job ids, or the job ids still running. -/
inductive Verdict where
  | pass
  | fail (ids : List String)
  | pending (ids : List String)
deriving DecidableEq, Repr

/-- The failed ids: expected ids with an `(id, false)` completion, in `expected` order. -/
def failedIds (expected : List String) (done : List (String × Bool)) : List String :=
  expected.filter (fun i => done.contains (i, false))

/-- The missing ids: expected ids with no completion at all, in `expected` order. -/
def missingIds (expected : List String) (done : List (String × Bool)) : List String :=
  expected.filter (fun i => !(done.contains (i, false) || done.contains (i, true)))

/-- The verdict over the completions received so far (`done`: (id, ok) pairs in arrival order; ids not in
`expected` are ignored). A failure wins over missing jobs (the runner may cancel the rest). -/
def verdict (expected : List String) (done : List (String × Bool)) : Verdict :=
  match failedIds expected done with
  | f@(_ :: _) => .fail f
  | [] => match missingIds expected done with
    | [] => .pass
    | m@(_ :: _) => .pending m

/-- **Completion order does not matter.** The verdict depends only on which completions arrived, not on their order. -/
theorem verdict_perm (expected : List String) (done done' : List (String × Bool)) (hp : done.Perm done') :
    verdict expected done = verdict expected done' := by
  have hc : ∀ x, done.contains x = done'.contains x := by
    intro x
    rw [Bool.eq_iff_iff]; simp [hp.mem_iff]
  simp only [verdict, failedIds, missingIds, hc]

/-- The verdict passes iff nothing failed and nothing is missing. -/
theorem verdict_eq_pass (expected : List String) (done : List (String × Bool)) :
    verdict expected done = .pass ↔ failedIds expected done = [] ∧ missingIds expected done = [] := by
  unfold verdict
  rcases failedIds expected done with _ | ⟨a, f⟩ <;> rcases missingIds expected done with _ | ⟨b, m⟩ <;> simp

/-- The verdict passes iff every expected job completed with `true` and none with `false`. -/
theorem verdict_pass_iff (expected : List String) (done : List (String × Bool)) :
    verdict expected done = .pass ↔ ∀ i ∈ expected, (i, true) ∈ done ∧ (i, false) ∉ done := by
  rw [verdict_eq_pass]
  simp only [failedIds, missingIds, List.filter_eq_nil_iff]
  constructor
  · intro ⟨hf, hm⟩ i hi
    have h1 := hf i hi
    have h2 := hm i hi
    simp at h1 h2
    exact ⟨h2 h1, h1⟩
  · intro h
    refine ⟨fun i hi => by simpa using (h i hi).2, fun i hi => ?_⟩
    simp [(h i hi).1]

/-- **Parallel completions give the sequential verdict.** If the completions are the jobs' results on the start
state, in any arrival order, the verdict passes iff the conjunction of the job results holds (so, with `seq_eq_all`,
iff the sequential run passes). -/
theorem verdict_jobs_pass_iff (js : List Job) (σ : St) (done : List (String × Bool))
    (hp : done.Perm (js.map fun j => (j.chk.id, j.chk.run σ))) :
    verdict (js.map (·.chk.id)) done = .pass ↔ js.all (fun j => j.chk.run σ) = true := by
  rw [verdict_perm _ _ _ hp, verdict_pass_iff]
  simp only [List.mem_map, List.all_eq_true]
  constructor
  · intro h j hj
    have h2 := h j.chk.id ⟨j, hj, rfl⟩
    cases hr : j.chk.run σ
    · exact absurd ⟨j, hj, by rw [hr]⟩ h2.2
    · rfl
  · intro h i ⟨j, hj, hji⟩
    subst hji
    refine ⟨⟨j, hj, by rw [h j hj]⟩, ?_⟩
    intro ⟨k, hk, hke⟩
    simp only [Prod.mk.injEq] at hke
    have := h k hk
    rw [hke.2] at this
    exact Bool.noConfusion this

/-- **A failure is final.** Once an expected job failed, more completions never turn the verdict into pass or
pending. -/
theorem verdict_fail_final (expected : List String) (done more : List (String × Bool)) (i : String)
    (hi : i ∈ expected) (hf : (i, false) ∈ done) : ∃ F, verdict expected (done ++ more) = .fail F := by
  have hne : failedIds expected (done ++ more) ≠ [] := by
    intro h
    simp only [failedIds, List.filter_eq_nil_iff] at h
    exact h i hi (by simp [hf])
  unfold verdict
  cases h : failedIds expected (done ++ more) with
  | nil => exact absurd h hne
  | cons a f => exact ⟨a :: f, rfl⟩

#guard verdict ["lint", "test"] [("test", true), ("lint", true)] == .pass
#guard verdict ["lint", "test"] [("test", true)] == .pending ["lint"]
#guard verdict ["lint", "test"] [("test", false)] == .fail ["test"]
#guard verdict ["lint", "test"] [("lint", true), ("test", false), ("test", true)] == .fail ["test"]
#guard verdict [] [] == .pass
#guard verdict ["lint"] [("other", false)] == .pending ["lint"]

def seedReads : List String :=
  ["lean/lean-toolchain", "lean/lake-manifest.json", "lean/lakefile.toml", "lean/*.lean", "lean/Fw/**", "lean/FwTest/**"]

def seedPath (x : String) : Bool := inScope (parseScope seedReads) x

def seedThreshold : Nat := 5

def seedLag (changed : List String) : Nat := (changed.filter seedPath).length

def seedDue (lag : Nat) : Bool := decide (seedThreshold < lag)

theorem seedDue_iff (lag : Nat) : seedDue lag = true ↔ seedThreshold < lag := by
  simp [seedDue]

theorem seedDue_false_iff (lag : Nat) : seedDue lag = false ↔ lag ≤ seedThreshold := by
  simp [seedDue]

theorem seedDue_mono (a b : Nat) (hab : a ≤ b) (ha : seedDue a = true) : seedDue b = true := by
  rw [seedDue_iff] at *; omega

theorem seedDue_zero : seedDue 0 = false := by decide

theorem seedDue_five : seedDue 5 = false := by decide

theorem seedDue_six : seedDue 6 = true := by decide

theorem seedLag_le (changed : List String) : seedLag changed ≤ changed.length :=
  List.length_filter_le _ _

theorem seedLag_eq_zero_iff (changed : List String) :
    seedLag changed = 0 ↔ ∀ x ∈ changed, seedPath x = false := by
  simp [seedLag, List.filter_eq_nil_iff]

theorem seedLag_cons_key (x : String) (r : List String) (hx : seedPath x = true) :
    seedLag (x :: r) = seedLag r + 1 := by
  simp [seedLag, hx]

theorem seedLag_cons_other (x : String) (r : List String) (hx : seedPath x = false) :
    seedLag (x :: r) = seedLag r := by
  simp [seedLag, hx]

theorem seedLag_append (a b : List String) : seedLag (a ++ b) = seedLag a + seedLag b := by
  simp [seedLag, List.filter_append]

#guard seedPath "lean/Fw/Console/Land.lean"
#guard seedPath "lean/FwTest/Main.lean"
#guard seedPath "lean/Fw.lean"
#guard seedPath "lean/lakefile.toml"
#guard seedPath "lean/lake-manifest.json"
#guard seedPath "lean/lean-toolchain"
#guard !seedPath "lean/scripts/check.sh"
#guard !seedPath "lean/land-legs.txt"
#guard !seedPath "lean/math.lock.json"
#guard !seedPath "lean/scripts/LandLegsGolden.lean"
#guard !seedPath "docs/team/tools/land.md"
#guard !seedPath "../lean/Fw.lean"
#guard seedLag [] == 0
#guard seedLag ["lean/Fw/A.lean", "lean/scripts/x.sh", "docs/x.md", "lean/Fw.lean"] == 2
#guard seedDue 0 == false
#guard seedDue 5 == false
#guard seedDue 6 == true
#guard seedDue (seedLag ["lean/Fw/A.lean", "lean/Fw/B.lean", "lean/Fw/C.lean", "lean/Fw/D.lean", "lean/Fw/E.lean",
  "lean/Fw/F.lean"]) == true

/-! ## Empirical premises (registry rows; ids to be merged into `Fw.Ops.Premise` once it is on main) -/

/-- A premise row: id, statement, the theorems that assume it, and the test that asserts it. -/
structure PremiseRow where
  id : String
  statement : String
  theorems : List String
  test : String

/-- The empirical premises and assumptions of this module, with the test that covers each (8 rows, distinct ids). -/
def premises : List PremiseRow := [
  ⟨"land.readsOnly", "a check reads only its declared inputs (E1)",
    ["cache_sound", "cachedRun_eq", "skip_sound", "seq_eq_all", "evidence_irrelevant"],
    "apps/runner/test/land-inputs.test.ts: a change to an undeclared input (packages/contracts/golden/obs/timing.jsonl) selects check.sh; any change in a check's declared reads selects the reads-scan check (scan_selected); CI strace reads ⊆ declared reads"⟩,
  ⟨"land.readsWithin", "a check reads only paths in the scope of its declared globs (E1 for globs)",
    ["skip_sound"], "apps/runner/test/land-inputs.test.ts: checksFor equals selectChecks on golden landSpeed.select"⟩,
  ⟨"land.noCollision", "sha256 of the canonical key encoding has no collision (A1; assumption, not tested)",
    ["cache_sound", "cachedRun_eq"], "none (cryptographic assumption)"⟩,
  ⟨"land.nonInterfere", "no stage-2 job writes a path another job reads; stage 2 calls .lake/build/bin/* directly (E4)",
    ["seq_eq_all", "verdict_jobs_pass_iff"], "CI strace -f -e trace=openat per stage-2 job: writes disjoint from other jobs' reads"⟩,
  ⟨"land.checkDeterministic", "re-running the checks on the same tree gives the same verdict",
    ["pre_eq_old", "preLand_eq_old"], "CI: check.sh twice on one commit, same exit code"⟩,
  ⟨"land.mergeTreeReproduces", "git -c attr.tree=<m0> merge-tree --write-tree m0 tip equals the tree git merge makes",
    ["pre_eq_old", "preLand_eq_old"], "replay test over the last 30 land merges (30/30 measured)"⟩,
  ⟨"land.checkedWorktreeExact", "the land worktree holds exactly commit C (checkout --detach C; clean -fdx -e .lake -e node_modules)",
    ["pre_commit_checked"], "apps/runner/test: an untracked imported .lean file in the land worktree is cleaned or refused"⟩,
  ⟨"land.binaryOfLean", "on one machine scripts/fwcore-build.sh is a function `build` of the state that reads only lean/** and scripts/fwcore-build.sh (BinaryOfBuildReads build, satisfiable: binaryOfBuildReads_satisfiable); the build slot it runs lake under (scripts/lake-slot-lib.sh, packages/contracts/golden/sched/lake-slot.gen.sh, and scripts/span.sh after a wait) sets only when lake starts, LEAN_NUM_THREADS, LAKE_SLOT and an inherited lock fd 9; these do not change the bytes (INFERRED, not measured); the binary the land checks is `build` of its tree, and sha256 of its bytes has no collision",
    ["fwcore_digest_skip", "fwcore_nobuild_skip"], "MEASURED 2026-10-19 (task land-fwcore-key): a docstring-only edit of lean/Fw/Console/LandQueue.lean (linked into fwcore), rebuilt with scripts/fwcore-build.sh, left the sha256 of the binary at 8a4fd2d6ff6f, as did a rerun and the rebuild after the revert; fwcore-build.sh strips once per link because on macOS a second strip changes the bytes (8a4fd2d6ff6f to 495249a32f9b); the land hashes real builds, so a toolchain change only selects more"⟩]

#guard premises.length == 8
#guard (premises.map (·.id)).eraseDups.length == premises.length

/-! ## Golden vectors (`packages/contracts/golden/console/land-speed.jsonl`) -/

open Lean

/-- A JSON array of strings. -/
def strs (xs : List String) : Json := .arr (xs.map Json.str).toArray

/-- One golden line: its name, the request object and the response object. -/
def line (name : String) (req resp : List (String × Json)) : Json :=
  Json.mkObj [("name", .str name), ("request", Json.mkObj req), ("response", Json.mkObj resp)]

/-- A `landSpeed.select` case over a decl table: the reply is `selectChecks`. -/
def selectCase (name : String) (ds : List Decl) (changed : List String) : Json :=
  line name [("op", "landSpeed.select"),
      ("checks", .arr (ds.map fun d => Json.mkObj [("id", .str d.id), ("reads", strs d.reads)]).toArray),
      ("changed", strs changed)]
    [("selected", strs (selectChecks ds changed))]

/-- A `landSpeed.select2` case: the reply is `binMoved` and `selectTwoPhase`. -/
def select2Case (name : String) (ds : List Decl) (changed : List String) (d0 d1 : Option String) : Json :=
  let dj : Option String → Json := fun d => match d with | some a => .str a | none => .null
  line name [("op", "landSpeed.select2"),
      ("checks", .arr (ds.map fun d => Json.mkObj [("id", .str d.id), ("reads", strs d.reads)]).toArray),
      ("changed", strs changed), ("main0Digest", dj d0), ("mergeDigest", dj d1)]
    [("binMoved", .bool (binMoved changed d0 d1)), ("selected", strs (selectTwoPhase ds changed d0 d1))]

/-- A `landSpeed.prelock` case: the reply is `prelockAction`. -/
def prelockCase (name head m0 : String) (v : Bool) (a n : Nat) : Json :=
  line name [("op", "landSpeed.prelock"), ("head", .str head), ("main0", .str m0), ("verdict", .bool v),
      ("attempt", toJson a), ("maxRetry", toJson n)]
    [("action", .str (prelockAction head m0 v a n).name)]

/-- The JSON reply of a verdict: its tag and its ids (empty for pass). -/
def verdictJson : Verdict → List (String × Json)
  | .pass => [("verdict", "pass"), ("ids", strs [])]
  | .fail ids => [("verdict", "fail"), ("ids", strs ids)]
  | .pending ids => [("verdict", "pending"), ("ids", strs ids)]

/-- A `landSpeed.verdict` case: the reply is `verdict`. -/
def verdictCase (name : String) (e : List String) (d : List (String × Bool)) : Json :=
  line name [("op", "landSpeed.verdict"), ("expected", strs e),
      ("done", .arr (d.map fun (i, b) => Json.arr #[.str i, .bool b]).toArray)]
    (verdictJson (verdict e d))

/-- A `landSpeed.cache` case: the reply is whether `cacheHit` found an entry, and its verdict (null on a miss). -/
def cacheCase (name : String) (S : Store Bool) (d : Nat) : Json :=
  line name [("op", "landSpeed.cache"), ("store", .arr (S.map fun (k, b) => Json.arr #[toJson k, .bool b]).toArray),
      ("digest", toJson d)]
    [("hit", .bool (cacheHit S d).isSome), ("verdict", match cacheHit S d with | some b => .bool b | none => .null)]

def seedLagCase (name : String) (changed : List String) : Json :=
  line name [("op", "landSpeed.seedLag"), ("changed", strs changed)]
    [("lag", toJson (seedLag changed)), ("due", .bool (seedDue (seedLag changed))),
      ("counted", strs (changed.filter seedPath))]

def seedDueCase (lag : Nat) : Json :=
  line s!"lag {lag}" [("op", "landSpeed.seedDue"), ("lag", toJson lag)] [("due", .bool (seedDue lag))]

/-- A `landSpeed.premise` row: the premise id in the request, its statement, theorems and test in the reply. -/
def premiseCase (p : PremiseRow) : Json :=
  line s!"premise {p.id}" [("op", "landSpeed.premise"), ("id", .str p.id)]
    [("statement", .str p.statement), ("theorems", strs p.theorems), ("test", .str p.test)]

def cases (_ : Unit := ()) : List Json :=
  [selectCase "golden-only change selects check.sh (P5 mutation)" sampleDecls
      ["packages/contracts/golden/obs/timing.jsonl"],
    selectCase "lean change selects check.sh only" sampleDecls ["lean/Fw/Console/Land.lean"],
    selectCase "docs-only change selects nothing" sampleDecls ["docs/team/handoffs/x.md"],
    selectCase "empty change selects nothing" sampleDecls [],
    selectCase "site generated breakpoints select check.sh" sampleDecls ["apps/site/src/breakpoints.gen.json"],
    selectCase "gate generated scope selects check.sh" sampleDecls ["packages/gate-breakpoints/src/scope.gen.json"],
    selectCase "workflow change selects check.sh" sampleDecls [".github/workflows/lean.yml"],
    selectCase "excluded path is not selected" [⟨"lean", ["lean/**", "!lean/math.lock.json"]⟩]
      ["lean/math.lock.json"],
    selectCase "path with .. is never in scope" sampleDecls ["../lean/x.lean"],
    selectCase "site-only change selects the read scan" scanDecls ["apps/site/src/x.ts"],
    selectCase "docs-only change does not select the read scan" scanDecls ["docs/team/handoffs/x.md"],
    prelockCase "main unchanged, pass: fast-forward" "m0" "m0" true 0 3,
    prelockCase "main unchanged, fail: refuse" "m0" "m0" false 0 3,
    prelockCase "main moved: re-check" "m1" "m0" true 0 3,
    prelockCase "main moved after a stale fail: re-check" "m1" "m0" false 2 3,
    prelockCase "main moved, retries used: fall back to the locked protocol" "m1" "m0" true 3 3,
    prelockCase "no retries allowed: fall back" "m1" "m0" true 0 0,
    verdictCase "all passed, any order" ["lint", "test"] [("test", true), ("lint", true)],
    verdictCase "one still running" ["lint", "test"] [("test", true)],
    verdictCase "one failed, other running: fail now" ["lint", "test"] [("test", false)],
    verdictCase "fail and pass for one id: fail" ["lint", "test"] [("lint", true), ("test", false), ("test", true)],
    verdictCase "no jobs: pass" [] [],
    verdictCase "unexpected id is ignored" ["lint"] [("other", false)],
    cacheCase "hit replays the stored verdict" [(7, true), (9, false)] 9,
    cacheCase "first entry wins" [(7, true), (7, false)] 7,
    cacheCase "miss: run the check" [(7, true)] 8,
    cacheCase "empty store: miss" [] 0,
    select2Case "lean change, equal digest: no fwcore user" binDecls ["lean/Fw/Console/Land.lean"] (some "a") (some "a"),
    select2Case "lean change, digests differ: every fwcore user" binDecls ["lean/Fw/Console/Land.lean"] (some "a") (some "b"),
    select2Case "lean change, main0 digest unknown: every fwcore user" binDecls ["lean/Fw/Console/Land.lean"] none (some "a"),
    select2Case "lean change, merge build dirty or missing: every fwcore user" binDecls ["lean/Fw/Console/Land.lean"] (some "a") none,
    select2Case "explicit lean source read selects its package at equal digest" binDecls ["lean/Fw/Console/PreviewFacts.lean"] (some "a") (some "a"),
    select2Case "no build read changed: unknown digests select no fwcore user" binDecls ["apps/site/src/x.ts"] none none,
    select2Case "build script change, equal digest: no fwcore user" binDecls ["scripts/fwcore-build.sh"] (some "a") (some "a"),
    select2Case "build script change, digests differ: every fwcore user" binDecls ["scripts/fwcore-build.sh"] (some "a") (some "b"),
    select2Case "docs-only change selects nothing" binDecls ["docs/team/handoffs/x.md"] none none,
    seedDueCase 0, seedDueCase 5, seedDueCase 6,
    seedLagCase "no change: lag 0" [],
    seedLagCase "only build-free lean paths and docs: lag 0"
      ["lean/scripts/check.sh", "lean/land-legs.txt", "lean/math.lock.json", "docs/team/tools/land.md"],
    seedLagCase "five key paths: not due"
      ["lean/Fw/A.lean", "lean/FwTest/B.lean", "lean/Fw.lean", "lean/lakefile.toml", "lean/scripts/x.sh",
        "lean/lean-toolchain"],
    seedLagCase "six key paths: due"
      ["lean/Fw/A.lean", "lean/FwTest/B.lean", "lean/Fw.lean", "lean/lakefile.toml", "lean/lake-manifest.json",
        "lean/lean-toolchain", "docs/x.md"]] ++ premises.map premiseCase

#guard cases.length == 51

/-- The golden file text: one compressed JSON line per case. -/
def goldenText (_ : Unit := ()) : String := String.join (cases.map fun c => c.compress ++ "\n")

/-- The golden file, relative to `lean/`. -/
def goldenPath : System.FilePath := "../packages/contracts/golden/console/land-speed.jsonl"

/-- Write the golden file (IO). -/
def writeGolden : IO Unit := IO.FS.writeFile goldenPath goldenText

def readsTsPath : System.FilePath := "../apps/runner/src/land-reads.gen.ts"

def readsTs (_ : Unit := ()) : String :=
  "// Generated by lean/scripts/LandReadsGen.lean (Fw.Console.LandSpeed.checkShReads). Do not edit.\n" ++
    "export const CHECK_SH_READS: string[] = [\n" ++
    String.join (checkShReads.map fun g => "  " ++ (Json.str g).compress ++ ",\n") ++ "];\n"

def regReply (c : RegCase) : List (String × Json) :=
  let (ok, reason, vs) : Bool × Json × List String := match c.verdict with
    | .ok => (true, .null, [])
    | .noWrites => (false, .str "noWrites", [])
    | .outOfScope v => (false, .str "outOfScope", v)
  [("ok", .bool ok), ("reason", reason), ("violations", strs vs),
    ("scope", strs (landScope c.writes c.names [] c.task c.stream))]

def regLine (c : RegCase) : Json :=
  line c.name [("op", "console.landScope"), ("writes", strs c.writes), ("names", strs c.names), ("task", .str c.task),
    ("stream", .str c.stream), ("paths", strs c.paths)] (regReply c)

def regText (_ : Unit := ()) : String := String.join (regCases.map fun c => (regLine c).compress ++ "\n")

def regPath : System.FilePath := "../packages/contracts/golden/console/land-scope-regs.jsonl"

def genFiles (_ : Unit := ()) : List (System.FilePath × String) :=
  [(goldenPath, goldenText ()), (readsTsPath, readsTs ()), (regPath, regText ())]

def writeAll : IO Unit := (genFiles ()).forM fun (p, t) => IO.FS.writeFile p t

def checkGolden : IO Bool := (genFiles ()).foldlM (init := true) fun ok (p, t) => do
  let cur ← try IO.FS.readFile p catch _ => pure ""
  if cur == t then return ok
  IO.eprintln s!"{p} differs from Fw.Console.LandSpeed (regenerate: cd lean && lake env lean --run scripts/LandReadsGen.lean --write)"
  return false

end Fw.Console.LandSpeed
