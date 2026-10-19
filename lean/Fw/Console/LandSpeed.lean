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
`landSpeed.prelock`, `landSpeed.verdict`, `landSpeed.cache`, and the premise rows `landSpeed.premise`).
Write or check with `lake env lean --run` on a two-line script calling `writeGolden` / `checkGolden` from `lean/`.

The empirical premises are listed in `premises` (id, statement, theorems, test).
-/
namespace Fw.Console.LandSpeed
open Fw.Ops.PathCheck

/-! ## (a) Result cache: a check that reads only its declared inputs can be replayed from a key hit -/

/-- A repo path. $$\mathrm{Path} = \mathrm{String}$$ -/
abbrev Path := String
/-- A file's content, as its blob id. $$\mathrm{Blob} = \mathbb{N}$$ -/
abbrev Blob := Nat
/-- A file-system state: every path's content (absent files have a fixed blob).
$$\sigma : \mathrm{Path} \to \mathrm{Blob}$$ -/
abbrev St := Path → Blob

/-- A check: an id, the paths it declares it reads (its own program and toolchain included), and its result.
$$c = (\mathit{id},\ \mathit{reads} \in \mathrm{Path}^{*},\ \mathit{run} : (\mathrm{Path}\to\mathrm{Blob}) \to R)$$ -/
structure Check (R : Type) where
  id : String
  reads : List Path
  run : St → R

/-- **Empirical premise `land.readsOnly` (E1).** The check is a function of its declared inputs: two states that
agree on them give the same result.
$$\mathrm{RO}(c) \iff \forall \sigma, \sigma':\ (\forall p \in \mathit{reads}(c):\ \sigma(p) = \sigma'(p)) \Rightarrow \mathit{run}_c(\sigma) = \mathit{run}_c(\sigma')$$ -/
def ReadsOnly {R} (c : Check R) : Prop :=
  ∀ σ σ' : St, (∀ p ∈ c.reads, σ p = σ' p) → c.run σ = c.run σ'

/-- The key: the check id, then each declared path with its blob.
$$\operatorname{key}_\sigma(c) = (\mathit{id}(c),\ [(p, \sigma(p)) : p \in \mathit{reads}(c)])$$ -/
def key {R} (c : Check R) (σ : St) : String × List (Path × Blob) := (c.id, c.reads.map (fun p => (p, σ p)))

/-- Equal keys mean the two states agree on every declared input.
$$\forall c, \sigma, \sigma':\ \operatorname{key}_\sigma(c) = \operatorname{key}_{\sigma'}(c) \Rightarrow \forall p \in \mathit{reads}(c):\ \sigma(p) = \sigma'(p)$$ -/
theorem key_agree {R} (c : Check R) (σ σ' : St) (h : key c σ = key c σ') : ∀ p ∈ c.reads, σ p = σ' p := by
  intro p hp
  have h2 := congrArg Prod.snd h
  simp only [key] at h2
  have := (List.map_inj_left.mp h2) p hp
  simpa using this

/-- **Assumption `land.noCollision` (A1), not a theorem.** The stored digest (sha256 of the canonical encoding) has
no collision on the keys it is applied to.
$$\mathrm{inj}(\mathrm{dig}) \iff \forall k, k':\ \mathrm{dig}(k) = \mathrm{dig}(k') \Rightarrow k = k'$$ -/
def NoCollision (dig : String × List (Path × Blob) → Nat) : Prop := ∀ k k', dig k = dig k' → k = k'

/-- **Cache soundness.** If the check reads only its declared inputs and the digest has no collision, a digest hit
replays exactly the result a fresh run would give.
$$\forall c, \mathrm{dig}, \sigma_0, \sigma:\ \mathrm{RO}(c) \land \mathrm{inj}(\mathrm{dig}) \land \mathrm{dig}(\operatorname{key}_{\sigma_0}(c)) = \mathrm{dig}(\operatorname{key}_{\sigma}(c)) \Rightarrow \mathit{run}_c(\sigma_0) = \mathit{run}_c(\sigma)$$ -/
theorem cache_sound {R} (c : Check R) (dig : String × List (Path × Blob) → Nat) (hro : ReadsOnly c)
    (hinj : NoCollision dig) (σ0 σ : St) (hk : dig (key c σ0) = dig (key c σ)) : c.run σ0 = c.run σ :=
  hro σ0 σ (key_agree c σ0 σ (hinj _ _ hk))

/-- A hit names a stored pair (the first one with that key).
$$\forall S, k, r:\ \operatorname{lookup}_S(k) = \mathrm{some}(r) \Rightarrow (k, r) \in S$$ -/
theorem lookup_mem {α β} [BEq α] [LawfulBEq α] :
    ∀ (S : List (α × β)) (k : α) (r : β), S.lookup k = some r → (k, r) ∈ S
  | [], _, _, h => by simp [List.lookup] at h
  | (a, b) :: S, k, r, h => by
    by_cases hk : k = a
    · subst hk; simp [List.lookup] at h; subst h; simp
    · have : (k == a) = false := by simpa using hk
      simp [List.lookup, this] at h
      exact List.mem_cons_of_mem _ (lookup_mem S k r h)

/-- A store: a list of (digest, result) entries, newest first. $$S \in (\mathbb{N} \times R)^{*}$$ -/
abbrev Store (R : Type) := List (Nat × R)

/-- **Store integrity (I1).** Every entry was written by a real run of this check under its key.
$$\mathrm{Int}(S) \iff \forall (d, r) \in S\ \exists \sigma_0:\ d = \mathrm{dig}(\operatorname{key}_{\sigma_0}(c)) \land r = \mathit{run}_c(\sigma_0)$$ -/
def Integrity {R} (c : Check R) (dig : String × List (Path × Blob) → Nat) (S : Store R) : Prop :=
  ∀ e ∈ S, ∃ σ0 : St, e.1 = dig (key c σ0) ∧ e.2 = c.run σ0

/-- Run through the store: replay the first entry with this digest on a hit, run on a miss.
$$\operatorname{cached}_S(c, \sigma) = \begin{cases} r & \operatorname{lookup}_S(\mathrm{dig}(\operatorname{key}_\sigma(c))) = \mathrm{some}(r) \\ \mathit{run}_c(\sigma) & \operatorname{lookup}_S(\mathrm{dig}(\operatorname{key}_\sigma(c))) = \mathrm{none} \end{cases}$$ -/
def cachedRun {R} (c : Check R) (dig : String × List (Path × Blob) → Nat) (S : Store R) (σ : St) : R :=
  match S.lookup (dig (key c σ)) with
  | some r => r
  | none => c.run σ

/-- **The cached run equals a fresh run** for an intact store.
$$\forall c, \mathrm{dig}, S, \sigma:\ \mathrm{RO}(c) \land \mathrm{inj}(\mathrm{dig}) \land \mathrm{Int}(S) \Rightarrow \operatorname{cached}_S(c, \sigma) = \mathit{run}_c(\sigma)$$ -/
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

/-- Storing a fresh run keeps the store intact.
$$\forall c, \mathrm{dig}, S, \sigma:\ \mathrm{Int}(S) \Rightarrow \mathrm{Int}\big((\mathrm{dig}(\operatorname{key}_\sigma(c)), \mathit{run}_c(\sigma)) :: S\big)$$ -/
theorem integrity_push {R} (c : Check R) (dig : String × List (Path × Blob) → Nat) (S : Store R) (σ : St)
    (hS : Integrity c dig S) : Integrity c dig ((dig (key c σ), c.run σ) :: S) := by
  intro e he
  rcases List.mem_cons.mp he with h | h
  · exact ⟨σ, by rw [h], by rw [h]⟩
  · exact hS e h

/-- **Mutation witness.** If a path the check really depends on is left undeclared, there are two states with equal
keys and different results, so (E1) is false and the test that mutates that path catches it.
$$\forall c, \sigma, \sigma':\ \operatorname{key}_\sigma(c) = \operatorname{key}_{\sigma'}(c) \land \mathit{run}_c(\sigma) \ne \mathit{run}_c(\sigma') \Rightarrow \lnot\,\mathrm{RO}(c)$$ -/
theorem undeclared_refutes {R} (c : Check R) (σ σ' : St) (hk : key c σ = key c σ') (hne : c.run σ ≠ c.run σ') :
    ¬ ReadsOnly c := fun hro => hne (hro σ σ' (key_agree c σ σ' hk))

/-- The cache decision the land runner makes for a check: the first stored verdict with this digest, or none (run it).
$$\operatorname{hit}(S, d) = \operatorname{lookup}_S(d) = \begin{cases} \mathrm{some}(r) & (d, r) \text{ is the first entry of } S \text{ with digest } d \\ \mathrm{none} & \text{no entry of } S \text{ has digest } d \ (\text{e.g. } S = [\,]) \end{cases}$$ -/
def cacheHit (S : Store Bool) (d : Nat) : Option Bool := S.lookup d

#guard cacheHit [(7, true), (9, false)] 9 == some false
#guard cacheHit [(7, true), (7, false)] 7 == some true
#guard cacheHit [(7, true)] 8 == none
#guard cacheHit [] 0 == none

/-! ### Check selection (`checksFor`): a skipped check is a replayed pass -/

/-- A check as `checksFor` declares it: its id and the globs of every path it reads (PathCheck glob semantics;
`!` excludes).
$$d = (\mathit{id},\ G \in \mathrm{Glob}^{*})$$ -/
structure Decl where
  id : String
  reads : List String
deriving Repr, DecidableEq

/-- Is the check selected for this change? Some changed path is in the scope of its declared globs (so an empty
change selects nothing).
$$\operatorname{sel}(G, X) \iff \exists x \in X:\ \mathrm{in}(\mathrm{parse}(G), x)$$ -/
def selected (G changed : List String) : Bool := changed.any (inScope (parseScope G))

/-- The ids of the selected checks, in table order.
$$\operatorname{select}(D, X) = [\, d.\mathit{id} : d \in D,\ \operatorname{sel}(d.G, X) \,]$$ -/
def selectChecks (ds : List Decl) (changed : List String) : List String :=
  (ds.filter (fun d => selected d.reads changed)).map (·.id)

/-- **Empirical premise `land.readsWithin`** (E1 for globs): the check's result depends only on paths in the scope
of its declared globs.
$$\mathrm{RW}(\mathit{run}, G) \iff \forall \sigma, \sigma':\ (\forall p:\ \mathrm{in}(\mathrm{parse}(G), p) \Rightarrow \sigma(p) = \sigma'(p)) \Rightarrow \mathit{run}(\sigma) = \mathit{run}(\sigma')$$ -/
def ReadsWithin {R} (run : St → R) (G : List String) : Prop :=
  ∀ σ σ' : St, (∀ p, inScope (parseScope G) p = true → σ p = σ' p) → run σ = run σ'

/-- Exact declared paths covered by globs give the glob premise.
$$\forall c, G:\ \mathrm{RO}(c) \land (\forall p \in \mathit{reads}(c):\ \mathrm{in}(\mathrm{parse}(G), p)) \Rightarrow \mathrm{RW}(\mathit{run}_c, G)$$ -/
theorem readsOnly_within {R} (c : Check R) (G : List String) (hro : ReadsOnly c)
    (hcov : ∀ p ∈ c.reads, inScope (parseScope G) p = true) : ReadsWithin c.run G :=
  fun σ σ' h => hro σ σ' (fun p hp => h p (hcov p hp))

/-- A changed path in the declared scope selects the check (so an undeclared-input test is a scope test).
$$\forall G, X, x:\ x \in X \land \mathrm{in}(\mathrm{parse}(G), x) \Rightarrow \operatorname{sel}(G, X)$$ -/
theorem selected_of_mem (G changed : List String) (x : String) (hx : x ∈ changed)
    (hin : inScope (parseScope G) x = true) : selected G changed = true := by
  simp only [selected, List.any_eq_true]
  exact ⟨x, hx, hin⟩

/-- **Skip soundness.** If the check reads only within its declared globs and no changed path is in their scope,
then its result on the new state equals its result on the old one (the states differ only on changed paths), so
skipping it replays its last verdict exactly.
$$\forall \mathit{run}, G, X, \sigma, \sigma':\ \mathrm{RW}(\mathit{run}, G) \land \lnot\operatorname{sel}(G, X) \land (\forall p \notin X:\ \sigma(p) = \sigma'(p)) \Rightarrow \mathit{run}(\sigma) = \mathit{run}(\sigma')$$ -/
theorem skip_sound {R} (run : St → R) (G changed : List String) (hrw : ReadsWithin run G)
    (hs : selected G changed = false) (σ σ' : St) (hd : ∀ p, p ∉ changed → σ p = σ' p) : run σ = run σ' := by
  apply hrw
  intro p hp
  apply hd
  intro hm
  rw [selected_of_mem G changed p hm hp] at hs
  exact Bool.noConfusion hs

/-- Membership in the selection, unfolded.
$$\forall D, X, i:\ i \in \operatorname{select}(D, X) \iff \exists d \in D:\ \operatorname{sel}(d.G, X) \land d.\mathit{id} = i$$ -/
theorem mem_selectChecks (ds : List Decl) (changed : List String) (i : String) :
    i ∈ selectChecks ds changed ↔ ∃ d ∈ ds, selected d.reads changed = true ∧ d.id = i := by
  simp [selectChecks, and_assoc]

/-- The declared reads proposed for `lean/scripts/check.sh` (P5): `lean/**` plus what it reads outside `lean/`
(the golden files `lake test` replays, the site's generated breakpoint files, the gate's generated scope file that
`sweepsgen --scope --check` compares, the workflow files the lane lint of `Fw.Ops.Premise` reads, the span helper, the fwcore build helper,
the incident ledger that `scripts/PropsLint.lean` matches the registry rows against, and the findings ledger, the parts
and the site preset that `Fw.Preset.Gen.run ["--check"]` regenerates the v2-proved preset from and compares). `checksfor-inputs` owns the
final list.
$$G_{\mathrm{check}} = [\texttt{lean/**},\ \texttt{packages/contracts/golden/**},\ \texttt{apps/site/src/breakpoints.gen.json},\ \texttt{apps/site/src/sweeps.gen.json},\ \texttt{apps/site/src/head.gen.json},\ \texttt{packages/gate-breakpoints/src/scope.gen.json},\ \texttt{.github/workflows/**},\ \texttt{scripts/span.sh},\ \texttt{scripts/fwcore-build.sh},\ \texttt{docs/team/incidents/ledger.json},\ \texttt{research/findings/ledger.json},\ \texttt{apps/site/src/parts/**},\ \texttt{apps/site/src/registry/presets/v2-proved.json},\ \texttt{packages/measure-chromium/scenarios.gen.json}]$$ -/
def checkShReads : List String :=
  ["lean/**", "packages/contracts/golden/**", "apps/site/src/breakpoints.gen.json",
    "apps/site/src/sweeps.gen.json", "apps/site/src/head.gen.json", "packages/gate-breakpoints/src/scope.gen.json", ".github/workflows/**",
    "scripts/span.sh", "scripts/fwcore-build.sh", "docs/team/incidents/ledger.json", "research/findings/ledger.json",
    "apps/site/src/parts/**", "apps/site/src/registry/presets/v2-proved.json",
    "packages/measure-chromium/scenarios.gen.json"]

/-- The sample `checksFor` table of the golden cases: check.sh and one package test.
$$D_0 = [(\texttt{check.sh}, G_{\mathrm{check}}),\ (\texttt{contracts}, [\texttt{packages/contracts/**}])]$$ -/
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

/-- The parsed check.sh scope: each declared glob split at `/`, and no exclusions.
$$\mathrm{parse}(G_{\mathrm{check}}) = \big([[\texttt{lean}, \texttt{**}],\ [\texttt{packages}, \texttt{contracts}, \texttt{golden}, \texttt{**}],\ [\texttt{apps}, \texttt{site}, \texttt{src}, \texttt{breakpoints.gen.json}],\ [\texttt{apps}, \texttt{site}, \texttt{src}, \texttt{sweeps.gen.json}],\ [\texttt{apps}, \texttt{site}, \texttt{src}, \texttt{head.gen.json}],\ [\texttt{packages}, \texttt{gate-breakpoints}, \texttt{src}, \texttt{scope.gen.json}],\ [\texttt{.github}, \texttt{workflows}, \texttt{**}],\ [\texttt{scripts}, \texttt{span.sh}],\ [\texttt{scripts}, \texttt{fwcore-build.sh}],\ [\texttt{docs}, \texttt{team}, \texttt{incidents}, \texttt{ledger.json}],\ [\texttt{research}, \texttt{findings}, \texttt{ledger.json}],\ [\texttt{apps}, \texttt{site}, \texttt{src}, \texttt{parts}, \texttt{**}],\ [\texttt{apps}, \texttt{site}, \texttt{src}, \texttt{registry}, \texttt{presets}, \texttt{v2-proved.json}],\ [\texttt{packages}, \texttt{measure-chromium}, \texttt{scenarios.gen.json}]],\ [\,]\big)$$ -/
theorem parseScope_checkShReads : parseScope checkShReads =
    ⟨[["lean", "**"], ["packages", "contracts", "golden", "**"], ["apps", "site", "src", "breakpoints.gen.json"],
      ["apps", "site", "src", "sweeps.gen.json"], ["apps", "site", "src", "head.gen.json"], ["packages", "gate-breakpoints", "src", "scope.gen.json"],
      [".github", "workflows", "**"], ["scripts", "span.sh"], ["scripts", "fwcore-build.sh"], ["docs", "team", "incidents", "ledger.json"],
      ["research", "findings", "ledger.json"], ["apps", "site", "src", "parts", "**"],
      ["apps", "site", "src", "registry", "presets", "v2-proved.json"],
      ["packages", "measure-chromium", "scenarios.gen.json"]], []⟩ := by
  have hi : checkShReads.filter (!·.startsWith "!") = checkShReads := by
    simp (config := {decide := true}) [checkShReads]
  have he : checkShReads.filter (·.startsWith "!") = [] := by
    simp (config := {decide := true}) [checkShReads]
  rw [parseScope, hi, he]
  simp only [List.map_nil, checkShReads, List.map_cons, Scope.mk.injEq, List.cons.injEq, and_true]
  and_intros <;> simp (config := {decide := true}) [segs, String.splitOn, String.splitOnAux]

/-- check.sh is selected whenever some changed path is in the parsed check.sh scope, in any check table $D$
holding the check `check.sh` with reads $G_{\mathrm{check}}$.
$$\forall D, X, x:\ (\texttt{check.sh}, G_{\mathrm{check}}) \in D \land x \in X \land \mathrm{in}(\mathrm{parse}(G_{\mathrm{check}}), x) \Rightarrow \texttt{check.sh} \in \operatorname{select}(D, X)$$ -/
theorem checkSh_selected_of_inScope (ds : List Decl) (changed : List String) (x : String)
    (hd : (⟨"check.sh", checkShReads⟩ : Decl) ∈ ds) (hx : x ∈ changed)
    (hin : inScope (parseScope checkShReads) x = true) :
    "check.sh" ∈ selectChecks ds changed :=
  (mem_selectChecks ds changed _).2 ⟨_, hd, List.any_eq_true.2 ⟨x, hx, hin⟩, rfl⟩

/-- A change to the gate's generated scope file (which `sweepsgen --scope --check` in `check.sh` reads) selects
`check.sh`: for every check table $D$ holding the check `check.sh` with reads $G_{\mathrm{check}}$, every change list
$X$ and every changed path $x \in X$ whose segments (split at `/`, empty and `.` segments dropped) equal those of
`packages/gate-breakpoints/src/scope.gen.json`.
$$\forall D, X, x:\ (\texttt{check.sh}, G_{\mathrm{check}}) \in D \land x \in X \land \mathrm{segs}(x) = [\texttt{packages}, \texttt{gate-breakpoints}, \texttt{src}, \texttt{scope.gen.json}] \Rightarrow \texttt{check.sh} \in \operatorname{select}(D, X)$$ -/
theorem scopeGen_selects_checkSh (ds : List Decl) (changed : List String) (x : String)
    (hd : (⟨"check.sh", checkShReads⟩ : Decl) ∈ ds) (hx : x ∈ changed)
    (hs : segs x = ["packages", "gate-breakpoints", "src", "scope.gen.json"]) :
    "check.sh" ∈ selectChecks ds changed := by
  refine checkSh_selected_of_inScope ds changed x hd hx ?_
  rw [inScope_iff, parseScope_checkShReads, hs]
  refine ⟨by simp, by simp, ⟨["packages", "gate-breakpoints", "src", "scope.gen.json"], by simp, ?_⟩, by simp⟩
  exact matchesPath_lit _ (by simp) (by simp (config := {decide := true}))

/-- A change to a workflow file (which the lane lint of `Fw.Ops.Premise`, run by `check.sh`, reads) selects
`check.sh`: for every check table $D$ holding the check `check.sh` with reads $G_{\mathrm{check}}$, every change list
$X$ and every changed path $x \in X$ whose segments start with `.github`, `workflows` and whose remaining segments
$r$ (possibly none) hold no `..`.
$$\forall D, X, x, r:\ (\texttt{check.sh}, G_{\mathrm{check}}) \in D \land x \in X \land \mathrm{segs}(x) = \texttt{.github} :: \texttt{workflows} :: r \land \texttt{..} \notin r \Rightarrow \texttt{check.sh} \in \operatorname{select}(D, X)$$ -/
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

/-- The id of the static read-set scan (`apps/runner` `test/land-inputs.test.ts`, premise `land.readsOnly`).
$$\mathrm{scanId} = \texttt{reads-scan}$$ -/
def scanId : String := "reads-scan"

/-- The inclusion globs of a declared read list (exclusions dropped, so the scan over-approximates).
$$\operatorname{pos}(G) = [\, g \in G : g_0 \ne \texttt{!}\,]$$ -/
def posGlobs (G : List String) : List String := G.filter (!·.startsWith "!")

/-- The scan's own reads: every inclusion glob any check of the table declares (package sources, extra reads, lock files).
$$G_{\mathrm{scan}}(D) = \operatorname{concat}[\, \operatorname{pos}(d.G) : d \in D \,]$$ -/
def scanReads (ds : List Decl) : List String := ds.flatMap (fun d => posGlobs d.reads)

/-- The table with the scan appended as its own cheap check.
$$D^{+} = D \mathbin{+\!\!+} [(\texttt{reads-scan},\ G_{\mathrm{scan}}(D))]$$ -/
def withScan (ds : List Decl) : List Decl := ds ++ [⟨scanId, scanReads ds⟩]

/-- Every glob of the scan reads is an inclusion.
$$\forall D, g \in G_{\mathrm{scan}}(D):\ g_0 \ne \texttt{!}$$ -/
theorem scanReads_no_excl (ds : List Decl) : ∀ g ∈ scanReads ds, g.startsWith "!" = false := by
  intro g hg
  simp only [scanReads, posGlobs, List.mem_flatMap, List.mem_filter] at hg
  obtain ⟨_, _, h⟩ := hg
  simpa using h.2

/-- A path in the scope of any declared check is in the scope of the scan.
$$\forall D, d \in D, x:\ \mathrm{in}(\mathrm{parse}(d.G), x) \Rightarrow \mathrm{in}(\mathrm{parse}(G_{\mathrm{scan}}(D)), x)$$ -/
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
(package sources included), the scan is selected: a land that changes only `apps/site` still runs it.
$$\forall D, X, d \in D, x \in X:\ \mathrm{in}(\mathrm{parse}(d.G), x) \Rightarrow \texttt{reads-scan} \in \operatorname{select}(D^{+}, X)$$ -/
theorem scan_selected (ds : List Decl) (changed : List String) (d : Decl) (hd : d ∈ ds) (x : String)
    (hx : x ∈ changed) (hin : inScope (parseScope d.reads) x = true) :
    scanId ∈ selectChecks (withScan ds) changed :=
  (mem_selectChecks _ _ _).2 ⟨⟨scanId, scanReads ds⟩, by simp [withScan],
    List.any_eq_true.2 ⟨x, hx, inScope_scanReads ds d hd x hin⟩, rfl⟩

/-- Precision: if no table check has the scan's id and no changed path lies in the scope of the scan's reads, the scan is not selected.
$$\left(\forall d \in D:\ d.\mathit{id} \ne \texttt{reads-scan}\right) \Rightarrow \left(\forall x \in X:\ \lnot\mathrm{in}(\mathrm{parse}(G_{\mathrm{scan}}(D)), x)\right) \Rightarrow \texttt{reads-scan} \notin \operatorname{select}(D^{+}, X)$$ -/
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

/-- The sample table with a site package check and the scan.
$$D_1 = (D_0 \mathbin{+\!\!+} [(\texttt{site}, [\texttt{apps/site/**}])])^{+}$$ -/
def scanDecls : List Decl := withScan (sampleDecls ++ [⟨"site", ["apps/site/**"]⟩])

#guard selectChecks scanDecls ["apps/site/src/x.ts"] == ["site", "reads-scan"]
#guard selectChecks scanDecls ["docs/team/handoffs/x.md"] == []
#guard selectChecks scanDecls ["packages/contracts/golden/obs/timing.jsonl"] == ["check.sh", "contracts", "reads-scan"]

/-! ## (c) Pre-lock checking: check merge(main₀, tip) outside the lock, commit it only if main is still main₀ -/

/-- What the commit step decides.
$$\mathrm{Out} = \mathrm{commit}(T, \mathit{ps}) \mid \mathrm{refuse} \mid \mathrm{retry}$$ -/
inductive Out where
  | commit (tree : String) (parents : List String)
  | refuse
  | retry
deriving DecidableEq, Repr

/-- The current protocol, seen at the moment the lock is taken with `HEAD = h`: merge, check, commit.
$$\mathrm{old}(h, b) = \begin{cases}\mathrm{commit}(\mu(h,b), [h,b]) & \chi(\mu(h,b)) \\ \mathrm{refuse} & \lnot\chi(\mu(h,b))\end{cases}$$ -/
def old (merge : String → String → String) (chk : String → Bool) (h b : String) : Out :=
  if chk (merge h b) then .commit (merge h b) [h, b] else .refuse

/-- The pre-lock protocol: `T = merge(main₀, b)` and its verdict `v` were computed before the lock; under the lock only
`HEAD = main₀` is compared, and the precomputed commit is fast-forwarded (`git commit-tree T -p main₀ -p b`, then
`merge --ff-only`): the committed tree is the checked tree by construction.
$$\mathrm{pre}(m_0, v, h, b) = \begin{cases}\mathrm{retry} & h \ne m_0 \\ \mathrm{commit}(\mu(m_0,b), [m_0,b]) & h = m_0 \land v \\ \mathrm{refuse} & h = m_0 \land \lnot v\end{cases}$$ -/
def pre (merge : String → String → String) (m0 : String) (v : Bool) (h b : String) : Out :=
  if h ≠ m0 then .retry else if v then .commit (merge m0 b) [m0, b] else .refuse

/-- **Pre-lock equivalence.** When main is still main₀ at the lock, the pre-lock protocol decides exactly what the
current protocol decides, with $v = \chi(\mu(m_0, b))$ computed earlier (premise `land.checkDeterministic`).
$$\forall \mu, \chi, m_0, h, b:\ h = m_0 \Rightarrow \mathrm{pre}(m_0, \chi(\mu(m_0,b)), h, b) = \mathrm{old}(h, b)$$ -/
theorem pre_eq_old (merge : String → String → String) (chk : String → Bool) (m0 h b : String) (hh : h = m0) :
    pre merge m0 (chk (merge m0 b)) h b = old merge chk h b := by
  subst hh; unfold pre old; by_cases hc : chk (merge h b) <;> simp [hc]

/-- **Fallback.** When main moved, nothing is committed: the land re-checks against the new main or falls back to the
locked protocol (`prelockAction`).
$$\forall \mu, m_0, v, h, b:\ h \ne m_0 \Rightarrow \mathrm{pre}(m_0, v, h, b) = \mathrm{retry}$$ -/
theorem pre_moved (merge : String → String → String) (m0 h b : String) (v : Bool) (hh : h ≠ m0) :
    pre merge m0 v h b = .retry := by
  simp [pre, hh]

/-- **Iff.** The pre-lock protocol agrees with the current one exactly when `HEAD = main₀` at commit time (the current
protocol never answers `retry`).
$$\forall \mu, \chi, m_0, h, b:\ \mathrm{pre}(m_0, \chi(\mu(m_0,b)), h, b) = \mathrm{old}(h, b) \iff h = m_0$$ -/
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
`HEAD` seen under the lock.
$$\forall \mu, \chi, m_0, h, b, T, \mathit{ps}:\ \mathrm{pre}(m_0, \chi(\mu(m_0,b)), h, b) = \mathrm{commit}(T, \mathit{ps}) \Rightarrow \chi(T) \land T = \mu(h, b) \land \mathit{ps} = [h, b]$$ -/
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
protocol applies the edit before checking, so it does not need this premise.
$$\forall c, \sigma, p, w:\ \mathrm{RO}(c) \land p \notin \mathit{reads}(c) \Rightarrow \mathit{run}_c(\sigma[p \mapsto w]) = \mathit{run}_c(\sigma)$$ -/
theorem evidence_irrelevant {R} (c : Check R) (hro : ReadsOnly c) (σ : St) (p : Path) (w : Blob)
    (hp : p ∉ c.reads) : c.run (fun q => if q = p then w else σ q) = c.run σ :=
  hro _ _ (fun q hq => by
    have : q ≠ p := fun e => hp (e ▸ hq)
    simp [this])

/-! ### On the `Fw.Console.Land` repo model -/

open Fw.Console.Land

/-- Today's land on the repo model: take the lock (`begin`), others act (`es`), then commit the merge if the check
of `merge(main₀, tip)` passes, else abort.
$$\mathrm{oldLand}(R, t, i, k, es) = \begin{cases} \operatorname{step}(R_2, \mathrm{land}(i,k))_1 & \chi(\mu(R_1.\mathit{pre}, t)) \\ \operatorname{step}(R_2, \mathrm{abort})_1 & \lnot\chi(\mu(R_1.\mathit{pre}, t)) \end{cases},\quad R_1 = \operatorname{step}(R, \mathrm{begin}(t))_1,\ R_2 = \operatorname{run}(R_1, es)$$ -/
def oldLand (merge : String → String → String) (chk : String → Bool) (s : Repo) (tip id task : String)
    (es : List Land.Event) : Repo :=
  let s1 := (Land.step s (.begin tip)).1
  let s2 := Land.run s1 es
  if chk (merge s1.pre tip) then (Land.step s2 (.land id task)).1 else (Land.step s2 .abort).1

/-- The pre-lock land on the repo model: the verdict `v` of `merge(main₀, tip)` is known before the lock; if `HEAD`
is not `main₀` or `v` failed, the lock is never taken and the repo is unchanged; otherwise lock, others act,
fast-forward to the checked commit.
$$\mathrm{preLand}(R, m_0, v, t, i, k, es) = \begin{cases} \operatorname{step}(\operatorname{run}(\operatorname{step}(R, \mathrm{begin}(t))_1, es), \mathrm{land}(i,k))_1 & R.\mathit{head} = m_0 \land v \\ R & \text{otherwise} \end{cases}$$ -/
def preLand (s : Repo) (m0 : String) (v : Bool) (tip id task : String) (es : List Land.Event) : Repo :=
  if s.head = m0 ∧ v = true then (Land.step (Land.run (Land.step s (.begin tip)).1 es) (.land id task)).1 else s

/-- **Pre-lock land = today's land on main**, when `HEAD = main₀` and the lock is free: same `HEAD`, same log, lock
released.
$$\forall \mu, \chi, R, m_0, t, i, k, es:\ \lnot R.\mathit{locked} \land (\forall e \in es:\ \mathrm{safe}(e)) \land R.\mathit{head} = m_0 \Rightarrow \big(P.\mathit{head}, P.\mathit{log}, P.\mathit{locked}\big) = \big(O.\mathit{head}, O.\mathit{log}, O.\mathit{locked}\big),\quad P = \mathrm{preLand}(R, m_0, \chi(\mu(m_0, t)), t, i, k, es),\ O = \mathrm{oldLand}(R, t, i, k, es)$$ -/
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
the lock is released.
$$\forall R, m_0, t, i, k, es:\ \lnot R.\mathit{locked} \land (\forall e \in es:\ \mathrm{safe}(e)) \land R.\mathit{head} = m_0 \Rightarrow P.\mathit{log} = (i, [m_0, t], \mathrm{some}(k)) :: R.\mathit{log} \land P.\mathit{head} = i \land \lnot P.\mathit{locked},\quad P = \mathrm{preLand}(R, m_0, \top, t, i, k, es)$$ -/
theorem preLand_commit_exact (s : Repo) (m0 tip id task : String) (es : List Land.Event) (hu : s.locked = false)
    (hs : ∀ e ∈ es, e.safe = true) (hh : s.head = m0) :
    let P := preLand s m0 true tip id task es
    P.log = { id := id, parents := [m0, tip], task := some task } :: s.log ∧ P.head = id ∧ P.locked = false := by
  intro P
  have hP : P = (Land.step (Land.run (Land.step s (.begin tip)).1 es) (.land id task)).1 := by simp [P, preLand, hh]
  rw [hP, ← hh]
  exact land_commit_exact s tip id task es hu hs

/-- **Main moved: nothing happens.** If `HEAD` is not `main₀`, the pre-lock land leaves the repo exactly as it is.
$$\forall R, m_0, v, t, i, k, es:\ R.\mathit{head} \ne m_0 \Rightarrow \mathrm{preLand}(R, m_0, v, t, i, k, es) = R$$ -/
theorem preLand_moved (s : Repo) (m0 : String) (v : Bool) (tip id task : String) (es : List Land.Event)
    (hh : s.head ≠ m0) : preLand s m0 v tip id task es = s := by
  simp [preLand, hh]

/-! ### The runner's decision under the lock -/

/-- What the land runner does after taking the lock with a pre-made commit.
$$\mathrm{Act} = \mathrm{ff} \mid \mathrm{refuse} \mid \mathrm{recheck} \mid \mathrm{fallback}$$ -/
inductive Action where
  | ff | refuse | recheck | fallback
deriving DecidableEq, Repr

/-- The JSON name of an action. $$\operatorname{name}(a) \in \{\texttt{ff}, \texttt{refuse}, \texttt{recheck}, \texttt{fallback}\}$$ -/
def Action.name : Action → String
  | .ff => "ff" | .refuse => "refuse" | .recheck => "recheck" | .fallback => "fallback"

/-- The decision: if `HEAD` is still `main₀`, fast-forward on a pass and refuse on a fail; if main moved, re-check
against the new main while `attempt < maxRetry` (attempts count from 0), else fall back to the locked protocol.
$$\operatorname{act}(h, m_0, v, a, n) = \begin{cases} \mathrm{ff} & h = m_0 \land v \\ \mathrm{refuse} & h = m_0 \land \lnot v \\ \mathrm{recheck} & h \ne m_0 \land a < n \\ \mathrm{fallback} & h \ne m_0 \land a \ge n \end{cases}$$ -/
def prelockAction (head m0 : String) (v : Bool) (attempt maxRetry : Nat) : Action :=
  if head = m0 then (if v then .ff else .refuse) else if attempt < maxRetry then .recheck else .fallback

/-- The runner's decision is the `pre` decision: it fast-forwards exactly when `pre` commits and refuses exactly when
`pre` refuses; when main moved, `pre` answers retry.
$$\forall \mu, h, m_0, v, a, n, b:\ (\operatorname{act}(h, m_0, v, a, n) = \mathrm{ff} \iff \mathrm{pre}(m_0, v, h, b) = \mathrm{commit}(\mu(m_0, b), [m_0, b])) \land (\operatorname{act}(h, m_0, v, a, n) = \mathrm{refuse} \iff \mathrm{pre}(m_0, v, h, b) = \mathrm{refuse})$$ -/
theorem prelockAction_pre (merge : String → String → String) (head m0 b : String) (v : Bool) (a n : Nat) :
    (prelockAction head m0 v a n = .ff ↔ pre merge m0 v head b = .commit (merge m0 b) [m0, b]) ∧
    (prelockAction head m0 v a n = .refuse ↔ pre merge m0 v head b = .refuse) := by
  unfold prelockAction pre
  by_cases hh : head = m0 <;> by_cases hv : v = true <;> by_cases ha : a < n <;> simp [hh, hv, ha]

/-- **Bounded retry.** Once `attempt ≥ maxRetry`, a moved main gives fallback, never another re-check.
$$\forall h, m_0, v, a, n:\ h \ne m_0 \land n \le a \Rightarrow \operatorname{act}(h, m_0, v, a, n) = \mathrm{fallback}$$ -/
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
at least one. The pool size never changes a verdict (`verdict_perm`); it only changes how many run at the same time.
$$\operatorname{pool}(c, \ell) = \max(1,\ c - \ell)$$ -/
def poolSize (cores loadCeil : Nat) : Nat := max 1 (cores - loadCeil)

/-- The pool is never empty, so a land always makes progress.
$$\forall c, \ell:\ 1 \le \operatorname{pool}(c, \ell)$$ -/
theorem poolSize_pos (cores loadCeil : Nat) : 1 ≤ poolSize cores loadCeil := by
  unfold poolSize; omega

/-- **Monotone in load.** More load never gives a larger pool.
$$\forall c, \ell \le \ell':\ \operatorname{pool}(c, \ell') \le \operatorname{pool}(c, \ell)$$ -/
theorem poolSize_anti_load (cores l l' : Nat) (h : l ≤ l') : poolSize cores l' ≤ poolSize cores l := by
  unfold poolSize; omega

/-- **Monotone in cores.** More cores never give a smaller pool.
$$\forall c \le c', \ell:\ \operatorname{pool}(c, \ell) \le \operatorname{pool}(c', \ell)$$ -/
theorem poolSize_mono_cores (c c' l : Nat) (h : c ≤ c') : poolSize c l ≤ poolSize c' l := by
  unfold poolSize; omega

/-- The pool never exceeds the cores (when there is at least one).
$$\forall c \ge 1, \ell:\ \operatorname{pool}(c, \ell) \le c$$ -/
theorem poolSize_le_cores (cores l : Nat) (hc : 1 ≤ cores) : poolSize cores l ≤ cores := by
  unfold poolSize; omega

#guard poolSize 10 0 == 10
#guard poolSize 10 3 == 7
#guard poolSize 10 23 == 1
#guard poolSize 0 0 == 1
#guard old (· ++ "+" ++ ·) (fun _ => true) "m0" "b" == .commit "m0+b" ["m0", "b"]
#guard pre (· ++ "+" ++ ·) "m0" true "m1" "b" == .retry

/-! ## (d) Parallel checks: non-interfering checks give the same verdict in any order -/

/-- A check with its effect on the state (build outputs, logs) and the paths it writes.
$$j = (c,\ \mathit{eff} : \Sigma \to \Sigma,\ \mathit{writes}),\quad \forall \sigma, p:\ p \notin \mathit{writes}(j) \Rightarrow \mathit{eff}_j(\sigma)(p) = \sigma(p)$$ -/
structure Job where
  chk : Check Bool
  eff : St → St
  writes : List Path
  frame : ∀ σ p, p ∉ writes → eff σ p = σ p

/-- Run jobs one after another; each check sees the effects of the jobs before it.
$$\mathrm{seq}(\sigma, [\,]) = \top,\quad \mathrm{seq}(\sigma, j :: js) = \mathit{run}_j(\sigma) \land \mathrm{seq}(\mathit{eff}_j(\sigma), js)$$ -/
def seqVerdict : St → List Job → Bool
  | _, [] => true
  | σ, j :: js => j.chk.run σ && seqVerdict (j.eff σ) js

/-- **Empirical premise `land.nonInterfere` (E4).** No job writes a path another job of the same stage reads (for
every pair at different positions of the list).
$$\mathrm{NI}(js) \iff \forall k < l < |js|:\ \mathit{writes}(js_k) \cap \mathit{reads}(js_l) = \varnothing \land \mathit{writes}(js_l) \cap \mathit{reads}(js_k) = \varnothing$$ -/
def NonInterfere (js : List Job) : Prop :=
  js.Pairwise (fun a b => (∀ p ∈ a.writes, p ∉ b.chk.reads) ∧ (∀ p ∈ b.writes, p ∉ a.chk.reads))

/-- **Parallel = sequential.** For read-only, non-interfering jobs the sequential verdict is the conjunction of the
verdicts each job gets on the start state, so running them at once gives the same verdict.
$$\forall js:\ (\forall j \in js:\ \mathrm{RO}(j)) \land \mathrm{NI}(js) \Rightarrow \forall \sigma:\ \mathrm{seq}(\sigma, js) = \textstyle\bigwedge_{j \in js} \mathit{run}_j(\sigma)$$ -/
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

/-- **Order independence.** The conjunction does not depend on the order of the jobs.
$$\forall js, js', \sigma:\ js \sim js' \Rightarrow \textstyle\bigwedge_{j \in js} \mathit{run}_j(\sigma) = \bigwedge_{j \in js'} \mathit{run}_j(\sigma)$$ -/
theorem all_perm (js js' : List Job) (hp : js.Perm js') (σ : St) :
    js.all (fun j => j.chk.run σ) = js'.all (fun j => j.chk.run σ) := by
  rw [Bool.eq_iff_iff]
  simp [List.all_eq_true, hp.mem_iff]

/-! ### The runner's verdict over completions -/

/-- The overall verdict of a stage: pass, the failed job ids, or the job ids still running.
$$\mathrm{V} = \mathrm{pass} \mid \mathrm{fail}(\mathit{ids}) \mid \mathrm{pending}(\mathit{ids})$$ -/
inductive Verdict where
  | pass
  | fail (ids : List String)
  | pending (ids : List String)
deriving DecidableEq, Repr

/-- The failed ids: expected ids with an `(id, false)` completion, in `expected` order.
$$F(E, D) = [\, i \in E : (i, \bot) \in D \,]$$ -/
def failedIds (expected : List String) (done : List (String × Bool)) : List String :=
  expected.filter (fun i => done.contains (i, false))

/-- The missing ids: expected ids with no completion at all, in `expected` order.
$$M(E, D) = [\, i \in E : (i, \bot) \notin D \land (i, \top) \notin D \,]$$ -/
def missingIds (expected : List String) (done : List (String × Bool)) : List String :=
  expected.filter (fun i => !(done.contains (i, false) || done.contains (i, true)))

/-- The verdict over the completions received so far (`done`: (id, ok) pairs in arrival order; ids not in
`expected` are ignored). A failure wins over missing jobs (the runner may cancel the rest).
$$\operatorname{verdict}(E, D) = \begin{cases} \mathrm{fail}(F(E,D)) & F(E,D) \ne [\,] \\ \mathrm{pending}(M(E,D)) & F(E,D) = [\,] \land M(E,D) \ne [\,] \\ \mathrm{pass} & F(E,D) = [\,] \land M(E,D) = [\,] \end{cases}$$ -/
def verdict (expected : List String) (done : List (String × Bool)) : Verdict :=
  match failedIds expected done with
  | f@(_ :: _) => .fail f
  | [] => match missingIds expected done with
    | [] => .pass
    | m@(_ :: _) => .pending m

/-- **Completion order does not matter.** The verdict depends only on which completions arrived, not on their order.
$$\forall E, D, D':\ D \sim D' \Rightarrow \operatorname{verdict}(E, D) = \operatorname{verdict}(E, D')$$ -/
theorem verdict_perm (expected : List String) (done done' : List (String × Bool)) (hp : done.Perm done') :
    verdict expected done = verdict expected done' := by
  have hc : ∀ x, done.contains x = done'.contains x := by
    intro x
    rw [Bool.eq_iff_iff]; simp [hp.mem_iff]
  simp only [verdict, failedIds, missingIds, hc]

/-- The verdict passes iff nothing failed and nothing is missing.
$$\forall E, D:\ \operatorname{verdict}(E, D) = \mathrm{pass} \iff F(E, D) = [\,] \land M(E, D) = [\,]$$ -/
theorem verdict_eq_pass (expected : List String) (done : List (String × Bool)) :
    verdict expected done = .pass ↔ failedIds expected done = [] ∧ missingIds expected done = [] := by
  unfold verdict
  rcases failedIds expected done with _ | ⟨a, f⟩ <;> rcases missingIds expected done with _ | ⟨b, m⟩ <;> simp

/-- The verdict passes iff every expected job completed with `true` and none with `false`.
$$\forall E, D:\ \operatorname{verdict}(E, D) = \mathrm{pass} \iff \forall i \in E:\ (i, \top) \in D \land (i, \bot) \notin D$$ -/
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
iff the sequential run passes).
$$\forall js, \sigma, D:\ D \sim [(\mathit{id}_j, \mathit{run}_j(\sigma)) : j \in js] \Rightarrow \big(\operatorname{verdict}([\mathit{id}_j : j \in js], D) = \mathrm{pass} \iff \textstyle\bigwedge_{j \in js} \mathit{run}_j(\sigma)\big)$$ -/
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
pending.
$$\forall E, D, D', i:\ i \in E \land (i, \bot) \in D \Rightarrow \exists F:\ \operatorname{verdict}(E, D \mathbin{+\!\!+} D') = \mathrm{fail}(F)$$ -/
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

/-! ## Empirical premises (registry rows; ids to be merged into `Fw.Ops.Premise` once it is on main) -/

/-- A premise row: id, statement, the theorems that assume it, and the test that asserts it.
$$p = (\mathit{id},\ \mathit{statement},\ \mathit{theorems},\ \mathit{test})$$ -/
structure PremiseRow where
  id : String
  statement : String
  theorems : List String
  test : String

/-- The empirical premises and assumptions of this module, with the test that covers each (7 rows, distinct ids).
$$\mathrm{premises} = [p_1, \dots, p_7],\quad p_k = (\mathit{id}_k, \mathit{statement}_k, \mathit{theorems}_k, \mathit{test}_k)$$ -/
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
    ["pre_commit_checked"], "apps/runner/test: an untracked imported .lean file in the land worktree is cleaned or refused"⟩]

#guard premises.length == 7
#guard (premises.map (·.id)).eraseDups.length == premises.length

/-! ## Golden vectors (`packages/contracts/golden/console/land-speed.jsonl`) -/

open Lean

/-- A JSON array of strings.
$$\operatorname{strs}(xs) = [\, \mathrm{str}(x) : x \in xs \,]$$ -/
def strs (xs : List String) : Json := .arr (xs.map Json.str).toArray

/-- One golden line: its name, the request object and the response object.
$$\operatorname{line}(n, q, r) = \{\texttt{name}: n,\ \texttt{request}: q,\ \texttt{response}: r\}$$ -/
def line (name : String) (req resp : List (String × Json)) : Json :=
  Json.mkObj [("name", .str name), ("request", Json.mkObj req), ("response", Json.mkObj resp)]

/-- A `landSpeed.select` case over a decl table: the reply is `selectChecks`.
$$\operatorname{selectCase}(n, D, X) = \operatorname{line}(n, \{D, X\}, \{\texttt{selected}: \operatorname{select}(D, X)\})$$ -/
def selectCase (name : String) (ds : List Decl) (changed : List String) : Json :=
  line name [("op", "landSpeed.select"),
      ("checks", .arr (ds.map fun d => Json.mkObj [("id", .str d.id), ("reads", strs d.reads)]).toArray),
      ("changed", strs changed)]
    [("selected", strs (selectChecks ds changed))]

/-- A `landSpeed.prelock` case: the reply is `prelockAction`.
$$\operatorname{prelockCase}(n, h, m_0, v, a, k) = \operatorname{line}(n, \{h, m_0, v, a, k\}, \{\texttt{action}: \operatorname{act}(h, m_0, v, a, k)\})$$ -/
def prelockCase (name head m0 : String) (v : Bool) (a n : Nat) : Json :=
  line name [("op", "landSpeed.prelock"), ("head", .str head), ("main0", .str m0), ("verdict", .bool v),
      ("attempt", toJson a), ("maxRetry", toJson n)]
    [("action", .str (prelockAction head m0 v a n).name)]

/-- The JSON reply of a verdict: its tag and its ids (empty for pass).
$$\operatorname{json}(\mathrm{pass}) = (\texttt{pass}, [\,]),\quad \operatorname{json}(\mathrm{fail}(I)) = (\texttt{fail}, I),\quad \operatorname{json}(\mathrm{pending}(I)) = (\texttt{pending}, I)$$ -/
def verdictJson : Verdict → List (String × Json)
  | .pass => [("verdict", "pass"), ("ids", strs [])]
  | .fail ids => [("verdict", "fail"), ("ids", strs ids)]
  | .pending ids => [("verdict", "pending"), ("ids", strs ids)]

/-- A `landSpeed.verdict` case: the reply is `verdict`.
$$\operatorname{verdictCase}(n, E, D) = \operatorname{line}(n, \{E, D\}, \operatorname{json}(\operatorname{verdict}(E, D)))$$ -/
def verdictCase (name : String) (e : List String) (d : List (String × Bool)) : Json :=
  line name [("op", "landSpeed.verdict"), ("expected", strs e),
      ("done", .arr (d.map fun (i, b) => Json.arr #[.str i, .bool b]).toArray)]
    (verdictJson (verdict e d))

/-- A `landSpeed.cache` case: the reply is whether `cacheHit` found an entry, and its verdict (null on a miss).
$$\operatorname{cacheCase}(n, S, d) = \operatorname{line}(n, \{S, d\}, \{\texttt{hit}: \operatorname{hit}(S, d) \ne \mathrm{none},\ \texttt{verdict}: \operatorname{hit}(S, d)\})$$ -/
def cacheCase (name : String) (S : Store Bool) (d : Nat) : Json :=
  line name [("op", "landSpeed.cache"), ("store", .arr (S.map fun (k, b) => Json.arr #[toJson k, .bool b]).toArray),
      ("digest", toJson d)]
    [("hit", .bool (cacheHit S d).isSome), ("verdict", match cacheHit S d with | some b => .bool b | none => .null)]

/-- A `landSpeed.premise` row: the premise id in the request, its statement, theorems and test in the reply.
$$\operatorname{premiseCase}(p) = \operatorname{line}(\texttt{premise } p.\mathit{id}, \{p.\mathit{id}\}, \{p.\mathit{statement}, p.\mathit{theorems}, p.\mathit{test}\})$$ -/
def premiseCase (p : PremiseRow) : Json :=
  line s!"premise {p.id}" [("op", "landSpeed.premise"), ("id", .str p.id)]
    [("statement", .str p.statement), ("theorems", strs p.theorems), ("test", .str p.test)]

/-- Every golden case: 11 select, 6 prelock, 6 verdict and 4 cache cases, then one row per premise.
$$\mathrm{cases} = \mathrm{select}_{1..11} \mathbin{+\!\!+} \mathrm{prelock}_{1..6} \mathbin{+\!\!+} \mathrm{verdict}_{1..6} \mathbin{+\!\!+} \mathrm{cache}_{1..4} \mathbin{+\!\!+} [\operatorname{premiseCase}(p) : p \in \mathrm{premises}]$$ -/
def cases : List Json :=
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
    cacheCase "empty store: miss" [] 0] ++ premises.map premiseCase

#guard cases.length == 34

/-- The golden file text: one compressed JSON line per case.
$$\mathrm{goldenText} = \operatorname{concat}[\, \operatorname{compress}(c) \mathbin{+\!\!+} \text{"\textbackslash n"} \,]_{c \in \mathrm{cases}}$$ -/
def goldenText : String := String.join (cases.map fun c => c.compress ++ "\n")

/-- The golden file, relative to `lean/`.
$$\mathrm{goldenPath} = \texttt{../packages/contracts/golden/console/land-speed.jsonl}$$ -/
def goldenPath : System.FilePath := "../packages/contracts/golden/console/land-speed.jsonl"

/-- Write the golden file (IO).
$$\mathrm{writeGolden}:\ \mathrm{goldenPath} \leftarrow \mathrm{goldenText}$$ -/
def writeGolden : IO Unit := IO.FS.writeFile goldenPath goldenText

/-- Is the golden file the Lean output? (IO)
$$\mathrm{checkGolden} \iff \operatorname{read}(\mathrm{goldenPath}) = \mathrm{goldenText}$$ -/
def checkGolden : IO Bool := do return (← IO.FS.readFile goldenPath) == goldenText

end Fw.Console.LandSpeed
